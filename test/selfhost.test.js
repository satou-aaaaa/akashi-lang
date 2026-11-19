// セルフホスト（docs/compiler.md 段階5）：Akashi で書いた部品が、JS の処理系と同じ答えを出すかを比べる。
// 今は字句解析（compiler/lexer.ak）。リポジトリの全部の .ak（壊れた見本も）を、src/parse.js の lex と比べる。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, mkdtempSync, writeFileSync, statSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { lex } from '../src/parse.js';
import { AkashiError } from '../src/errors.js';
import { runSource, buildSource } from '../src/index.js';
import { runWasm } from '../src/host.js';
import { openFolder } from '../src/folder.js';

const root = fileURLToPath(new URL('../', import.meta.url));
const driver = join(root, 'compiler', 'lex_main.ak');

// JS の lex の答えを、compiler/lex_main.ak と同じ形の文字にする
function expected(src) {
  try {
    return lex(src).filter((t) => t.t !== 'eof').map((t) => {
      const text = t.t === 'str' ? t.v : t.t === 'int' ? src.slice(t.pos.offset, t.end) : t.v;
      const endCol = t.pos.col + [...src.slice(t.pos.offset, t.end)].length;
      return `Token(kind: ${JSON.stringify(t.t)}, text: ${JSON.stringify(text)}, line: ${t.pos.line}, col: ${t.pos.col}, end_col: ${endCol})`;
    }).join('\n') + '\n';
  } catch (e) {
    if (!(e instanceof AkashiError)) throw e;
    return `error ${e.diag.code} ${e.diag.line}:${e.diag.col} ${e.diag.message}\n`;
  }
}

function akFiles(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) return akFiles(p);
    return f.endsWith('.ak') ? [p] : [];
  });
}

const files = ['examples', 'test/compile', 'compiler'].flatMap((d) => akFiles(join(root, d)));
// 字句の端の場合（壊れたものも）
const extra = ['', 'x', '12ab', '1.5', '1.', '"abc', '"a\nb"', '"\\q"', '"\\n\\t\\"\\\\"', 'a!b', 'a != b', '!', '->-', '{', '😀 x', '"😀" y', '# c\nx', 'a\r\nb', '9007199254740993', 'é_1'];

test('the Akashi lexer (compiled to wasm) gives the same tokens as src/parse.js for every .ak file and edge cases', () => {
  const b = buildSource(readFileSync(driver, 'utf8'), { file: driver });
  assert.ok(b.ok, JSON.stringify(b.diagnostics));
  const dir = mkdtempSync(join(tmpdir(), 'akashi-lex-'));
  const cases = [...files.map((f) => [f.slice(root.length), readFileSync(f, 'utf8')]), ...extra.map((s) => [JSON.stringify(s), s])];
  assert.ok(files.length > 60, `found ${files.length} files`);
  for (const [label, src] of cases) {
    writeFileSync(join(dir, 'input.ak'), src);
    let out = '';
    let err = '';
    const exit = runWasm(b.bytes, { stdout: (s) => { out += s; }, stderr: (s) => { err += s; }, folder: openFolder(dir) });
    assert.equal(exit, 0, `${label}\n${err}`);
    // 字句が1つも無いときは空の行だけ
    assert.equal(out, expected(src) === '\n' ? '\n' : expected(src), label);
  }
});

test('the Akashi lexer gives the same answer in the interpreter, quickly, even on its own source', () => {
  const dir = mkdtempSync(join(tmpdir(), 'akashi-lex-i-'));
  const src = readFileSync(join(root, 'compiler', 'lexer.ak'), 'utf8');
  writeFileSync(join(dir, 'input.ak'), src);
  const t0 = Date.now();
  const r = runSource(readFileSync(driver, 'utf8'), { file: driver, grants: { folder: dir } });
  const ms = Date.now() - t0;
  assert.equal(r.ok, true, JSON.stringify(r.diagnostics));
  assert.equal(r.output, expected(src));
  // 大きな値を渡す関数を何千回も呼んでも遅くならない（約束の文を毎回作っていたときは 60 秒かかった）
  assert.ok(ms < 20000, `took ${ms} ms`);
});

// ---- 構文解析（compiler/parser.ak）----
import { parse, scan } from '../src/parse.js';
import { dirname, basename } from 'node:path';
import { cpSync, existsSync, rmSync } from 'node:fs';
import { analyze } from '../src/core.js';

const q = (s) => JSON.stringify(s);
const node = (kind, text, pos, kids = []) => `Node(kind: ${q(kind)}, text: ${q(text)}, line: ${pos ? pos.line : 0}, col: ${pos ? pos.col : 0}, kids: [${kids.join(', ')}])`;

// src/parse.js の木を、compiler/parser.ak の Node と同じ形の文字にする（形の説明は docs/compiler.md「構文解析の木」）
function treeText(src, ast) {
  const ty = (t) => t.k === 'Data' ? node('t', t.name, null, t.args.map(ty)) : t.k === 'List' || t.k === 'Dict' ? node('t', t.k, null, [ty(t.of)]) : node('t', t.k, null);
  const block = (b) => node('block', '', null, [...b.lets.map((l) => l.k === 'let' ? node('let', l.name, l.pos, [ty(l.type), ex(l.value)]) : node('do', '', l.pos, [ex(l.expr)])), ex(b.result)]);
  const ex = (e) => {
    switch (e.k) {
      case 'int': return node('int', /^[0-9]+/.exec(src.slice(e.pos.offset))[0], e.pos);
      case 'str': return node('str', e.v, e.pos);
      case 'bool': return node('bool', String(e.v), e.pos);
      case 'unit': return node('unit', '', e.pos);
      case 'var': return node('var', e.name, e.pos);
      case 'list': return node('list', '', e.pos, e.items.map(ex));
      case 'bin': return node('bin', e.op, e.pos, [ex(e.left), ex(e.right)]);
      case 'un': return node('un', e.op, e.pos, [ex(e.arg)]);
      case 'if': return node('if', '', e.pos, [ex(e.cond), block(e.thenB), block(e.elseB)]);
      case 'call': return node('call', e.name, e.pos, e.args.map((a) => node('arg', a.name ?? '', a.pos, [ex(a.value)])));
      case 'match': return node('match', '', e.pos, [ex(e.subject), ...e.arms.map((a) => node('arm', a.variant, a.pos, [node('at', a.variant, a.vpos), ...a.binds.map((b) => node('bind', `${b.field} ${b.name}`, b.pos)), ex(a.value)]))]);
      default: throw new Error(`unknown expression ${e.k}`);
    }
  };
  const clause = (c) => node('clause', c.src, null, [ex(c.expr)]);
  return node('program', '', null, [
    ...ast.uses.map((u) => node('use', u.path, u.pos)),
    ...ast.types.map((t) => node('type', t.name, t.pos, t.variants.map((v) => node('case', v.name, v.pos, v.fields.map((f) => node('field', f.name, f.pos, [ty(f.type)])))))),
    ...ast.fns.map((f) => node('fn', f.name, f.pos, [
      node('params', '', null, f.params.map((p) => node('param', p.name, p.pos, [ty(p.type)]))),
      ty(f.ret),
      node('requires', '', null, f.requires.map(clause)),
      node('ensures', '', null, f.ensures.map(clause)),
      node('examples', '', null, f.examples.map(clause)),
      block(f.body),
    ])),
  ]);
}

// use でたどれるファイルの型の名前（src/modules.js と同じく全部のファイルぶん）
function typesVia(file, seen = new Set()) {
  if (seen.has(file)) return [];
  seen.add(file);
  let s;
  try { s = scan(readFileSync(file, 'utf8')); } catch { return []; }
  return [...s.types, ...s.uses.flatMap((u) => { try { return typesVia(join(dirname(file), u.path), seen); } catch { return []; } })];
}

function expectedTree(src, otherTypes) {
  try {
    return treeText(src, parse(src, { otherTypes })) + '\n';
  } catch (e) {
    if (!(e instanceof AkashiError)) throw e;
    return `error ${e.diag.code} ${e.diag.line}:${e.diag.col} ${e.diag.message}\n`;
  }
}

// 構文の端の場合（壊れたものも）
const parseExtra = [
  '', 'fn', 'fn f', 'fn f(', 'fn f() do 1 end', 'fn f() -> Int', 'fn f() -> Int do end', 'fn f() -> Int do 1', 'end', 'use "a.ak"\nfn f() -> Int do 1 end\nuse "b.ak"', 'use x',
  'type t case A end', 'type T end', 'type T case a end', 'type T case A(x Int) end', 'type T case A(x: Int, y: List[Str]) case B end',
  'fn f(x: Null) -> Int do 1 end', 'fn f(x: List) -> Int do 1 end', 'fn f(x: 1) -> Int do 1 end', 'fn f() -> Int effects io do 1 end',
  'fn f() -> Int do let x = 1 x end', 'fn f() -> Int do let x: Int = 1 end', 'fn f() -> Int do if a then 1 end end', 'fn f() -> Int do if a then 1 else 2 end end',
  'fn f() -> Int do a and b or c end', 'fn f() -> Bool do 0 < x < 9 end', 'fn f() -> Int do when a then 1 end end', 'fn f() -> Int do when else 1 end end',
  'fn f() -> Int do match x case A then 1 else 2 end end', 'fn f() -> Int do match x end end', 'fn f() -> Int do match x case A(v: a, w: _) then a case B then 2 end end',
  'fn f() -> Int do g(x: 1, 2, y: [1, 2], z: []) end', 'fn f() -> Int do g( end', 'fn f() -> Int do -(1 + 2) * 3 - not x % 2 end', 'fn f() -> Int do 1 + 2 ++ 3 - 4 end',
  'fn f() -> Int do (1 end', 'fn f() -> Int do [1, end', 'fn f() -> Int do then end', 'fn f() -> Int do f(x: 1) g(y: 2) 3 end',
  'fn f() -> Int\n  requires x > 0 and\n    y > 0\n  ensures result == "a\\"b"\n  example f() == 1\ndo\n  1\nend',
  'fn f() -> Str do "😀" ++ x end', 'fn f() -> Int do a or b or c and d end',
  // 自分で作った型は、組み込みと同じ名前でも自分の型として読む（List・Dict でも [ ] を付けない）
  'type List case A end\nfn f(x: List) -> Int do 1 end', 'type Dict case D end fn f(x: Dict) -> Dict do x end',
];

test('the Akashi parser (compiled to wasm) gives the same tree as src/parse.js for every .ak file and edge cases', () => {
  const pdriver = join(root, 'compiler', 'parse_main.ak');
  const b = buildSource(readFileSync(pdriver, 'utf8'), { file: pdriver });
  assert.ok(b.ok, JSON.stringify(b.diagnostics));
  const dir = mkdtempSync(join(tmpdir(), 'akashi-parse-'));
  const cases = [
    ...files.map((f) => [f.slice(root.length), readFileSync(f, 'utf8'), typesVia(f)]),
    ...parseExtra.map((s) => [JSON.stringify(s), s, []]),
  ];
  for (const [label, src, other] of cases) {
    writeFileSync(join(dir, 'input.ak'), src);
    writeFileSync(join(dir, 'types.txt'), other.join(' '));
    let out = '';
    let err = '';
    const exit = runWasm(b.bytes, { stdout: (s) => { out += s; }, stderr: (s) => { err += s; }, folder: openFolder(dir) });
    assert.equal(exit, 0, `${label}\n${err}`);
    assert.equal(out, expectedTree(src, other), label);
  }
});

test('the Akashi parser gives the same tree in the interpreter, quickly, on its own source', () => {
  const pdriver = join(root, 'compiler', 'parse_main.ak');
  const dir = mkdtempSync(join(tmpdir(), 'akashi-parse-i-'));
  const file = join(root, 'compiler', 'parser.ak');
  const src = readFileSync(file, 'utf8');
  writeFileSync(join(dir, 'input.ak'), src);
  writeFileSync(join(dir, 'types.txt'), typesVia(file).join(' '));
  const t0 = Date.now();
  const r = runSource(readFileSync(pdriver, 'utf8'), { file: pdriver, grants: { folder: dir } });
  const ms = Date.now() - t0;
  assert.equal(r.ok, true, JSON.stringify(r.diagnostics));
  assert.equal(r.output, expectedTree(src, typesVia(file)));
  assert.ok(ms < 30000, `took ${ms} ms`);
});

// ---- 型の検査（compiler/check.ak）----

// JS の検査（src/core.js の analyze：use をたどって読む＋check）の答えを、compiler/check_main.ak と同じ形の文字にする
function expectedCheck(file) {
  const dir = dirname(file);
  const a = analyze(readFileSync(file, 'utf8'), { load: (rel) => (existsSync(join(dir, rel)) ? readFileSync(join(dir, rel), 'utf8') : null) });
  if (a.ok) return 'ok\n';
  return a.diagnostics.map((d) => `${d.file ? `${d.file}: ` : ''}${d.code} ${d.line}:${d.col} ${d.message}`).join('\n') + '\n';
}

// 型の検査の端の場合（エラーの文の違いを全部出す）
const checkExtra = [
`type Int case A end
type Shape case Some(x: Int) case Circle(r: Int, r: Int) end
type Shape case B end
fn print() -> Int ensures true example 1 == 1 do 1 end
fn Circle() -> Int ensures true example 1 == 1 do 1 end
fn f(x: Int, x: Int) -> Int ensures true example 1 == 1 do let x: Int = 1 x end
fn f() -> Int do 1 end`,
`type T case A(c: Console) end
fn f(xs: List[Console]) -> Console ensures true example 1 == 1 do let y: List[Folder] = [] get(list: xs, index: 0) end`,
`fn main(console: Console, c2: Console) -> Int do 1 end`,
`fn g() -> Int ensures true example g() == 1 do
  let a: List[Int] = [1, "x", true]
  let b: Int = -"s"
  let c: Bool = not 1
  let d: Int = if 1 then 2 else "x" end
  let e: Int = "a" + 1
  let h: Bool = 1 < "b"
  let i: Bool = 1 and true
  let j: Bool = 1 == "x"
  let k: Str = 1 ++ 2
  let l: Str = "a" ++ [1]
  let m: List[Int] = [1] ++ ["a"]
  1
end`,
`fn f2(x: Int) -> Int ensures true example f2(x: 1) == 1 do x end
fn g2() -> Bool ensures true example g2() do f2 == f2 end
fn h2() -> Int ensures true example h2() == 1 do f2(1) + f2(x: 1, x: 2) + f2(y: 1) + f2() end
fn k2(a: Int, b: Int) -> Int ensures true example k2(b: 1, a: 2) == 3 do k2(b: 1, a: 2) end`,
`type Shape case Circle(r: Int) case Square(side: Int) case Dot end
fn area(s: Shape) -> Int ensures true example area(s: Dot) == 0 do
  match s
    case Circle(r: r) then r
    case Circle(r: q) then q
  end
end
fn a2(s: Shape) -> Int ensures true example 1 == 1 do
  match s
    case Circle(radius: r) then r
    case Square(side: _) then "x"
    case Dot then 0
    case Some(value: v) then 1
    case Nope then 1
  end
end
fn a3(s: Shape) -> Int ensures true example 1 == 1 do
  match s
    case _ then 1
  end
end
fn a4(x: Int) -> Int ensures true example 1 == 1 do
  match x
    case Dot then 1
  end
end
fn a5(s: Shape) -> Int ensures true example 1 == 1 do Circle + Dot(x: 1) + Circle(r: 1, r: 2) end`,
`fn w(console: Console) -> Unit do print(to: console, value: 1) end
fn main(console: Console) -> Unit do
  print(to: console, value: 1)
  w(console: console)
end
fn bad(x: Int) -> Unit requires print(to: c, value: 1) == () do print(to: console, value: x) end
fn bad2(folder: Folder) -> Unit do print(to: folder, value: 1) end
fn bad3(c: Console) -> Unit do print(to: c, value: w) end
fn bad4(x: Int) -> Int ensures true example 1 == 1 do 1 end`,
`fn main(console: Console) -> Unit do
  let t: Str = "<p>{}</p>"
  let a: Html = html(template: t, values: [])
  let b: Html = html(template: "<p>{}{}</p>", values: [html_text(value: "x")])
  let c: Sql = sql(template: "select ? from ?", values: ["a"])
  print(to: console, value: null)
  print(to: console, value: len)
  print(to: console, value: unknown)
  print(to: console, value: zork(a: 1, b: q))
  1
  print(to: console, value: console == console)
  print(to: console, value: [console])
end`,
`fn f(x: Option[Int]) -> Int ensures true example f(x: None) == 0 do
  match x
    case Some(value: v) then v
    case None then 0
  end
end
fn g(r: Result[Str]) -> Str ensures true example g(r: Ok(value: "a")) == "a" do
  match r
    case Ok(value: v) then v
    case Err(message: m) then m
  end
end
fn h(xs: List[Int]) -> Int ensures result >= 0 example h(xs: [1]) == 1 do
  fold(list: xs, init: 0, func: add) + len(list: map(list: xs, func: f3)) + sum(list: filter(list: xs, func: pos))
end
fn add(a: Int, b: Int) -> Int ensures true example add(a: 1, b: 2) == 3 do a + b end
fn f3(x: Int) -> Str ensures true example f3(x: 1) == "1" do to_str(value: x) end
fn pos(x: Int) -> Bool ensures true example pos(x: 1) do x > 0 end
fn m2() -> Int ensures true example m2() == 1 do
  match at(list: [1], index: 0)
    case Some(value: v) then v
    case None then "x"
  end
end
fn m3() -> Int ensures true example m3() == 1 do
  match None
    case None then 1
    case Some(value: v) then v
  end
end
fn m4() -> Int ensures true example 1 == 1 do fold(list: [1], init: "a", func: add) + map(list: 1, func: f3) end`,
`fn a(x: Int) -> Int requires x ensures 1 ensures result example 3 do x end
fn b(c: Console) -> Int ensures result == 1 example b(c: c) == 1 do 1 end
fn result(x: Int) -> Int ensures true example 1 == 1 do x end`,
`type P case P(x: Int, y: Int) end
fn f(p: P) -> Int ensures true example f(p: P(x: 1, y: 2)) == 3 do
  match p
    case P(x: a, y: f) then a
    case P(x: a, y: b) then b
  end
end
fn g(p: P) -> Int ensures true example 1 == 1 do
  match p
    case P(y: b, x: a) then a
  end
end
fn h(p: P) -> Int ensures true example 1 == 1 do
  match p
    case P(x: print, y: _) then 1
  end
end`,
`fn f(x: List[Int]) -> Dict[Int] ensures true example 1 == 1 do dict(keys: ["a"], values: x) end
fn g() -> Int ensures true example 1 == 1 do
  let d: Dict[Str] = f(x: [1])
  dict_size(dict: d) + get(list: [[1]], index: 0)
end
fn k() -> Unit ensures true example k() == () do () end
fn k2() -> Unit ensures true example 1 == 1 do k2 end`,
`fn f(out: OutFolder, folder: Folder) -> Unit do
  match read_text(from: folder, path: "a")
    case Ok(value: t) then match write_text(to: out, path: "b", text: t)
      case Ok(value: _) then ()
      case Err(message: _) then ()
    end
    case Err(message: m) then ()
  end
end
fn g(folder: Folder) -> Unit do
  match write_text(to: folder, path: "b", text: "x")
    case Ok(value: _) then ()
    case Err(message: _) then ()
  end
end
fn main(console: Console, folder: Folder, out: OutFolder) -> Unit do f(out: out, folder: folder) end`,
];

// いくつものファイル（use）。main.ak から読む
const checkFiles = [
  { 'main.ak': 'use "lib/a.ak"\nfn main(console: Console) -> Unit do print(to: console, value: twice(x: 2)) end', 'lib/a.ak': 'use "b.ak"\nfn twice(x: Int) -> Int ensures true example twice(x: 1) == 2 do x + bad end', 'lib/b.ak': 'type Shape case Dot end\nfn main() -> Int do 1 end' },
  { 'main.ak': 'use "a.ak"\nfn main(console: Console) -> Unit do print(to: console, value: f(s: Dot)) end', 'a.ak': 'use "main.ak"\ntype Shape case Dot end\nfn f(s: Shape) -> Int ensures true example f(s: Dot) == 1 do "x" end' },
  { 'main.ak': 'use "a.ak"\nuse "missing.ak"\nfn main() -> Unit do () end', 'a.ak': 'fn f() -> Int do 1 end' },
  { 'main.ak': 'use "../x.ak"\nfn main() -> Unit do () end' },
  { 'main.ak': 'use "a.ak"\nfn main() -> Unit do () end', 'a.ak': 'fn f() -> Int do 1.5 end' },
  { 'main.ak': 'use "a.ak"\nfn main() -> Unit do () end', 'a.ak': 'fn f( -> Int do 1 end' },
  { 'main.ak': 'use "a.ak"\nfn f() -> Int ensures true example f() == 1 do 1 end\nfn main() -> Unit do () end', 'a.ak': 'fn f() -> Str do "a" end\nfn g(s: Shape) -> Int do 1 end', 'b.ak': '' },
  { 'main.ak': 'use "a.ak"\ntype List case L end\nfn main() -> Unit do () end', 'a.ak': 'fn f(x: List) -> Int ensures true example 1 == 1 do 1 end' },
  { 'main.ak': 'use "lib/a.ak"\nfn main(console: Console) -> Unit do print(to: console, value: twice(x: 2)) end', 'lib/a.ak': 'use "b.ak"\nfn twice(x: Int) -> Int ensures true example twice(x: 1) == 2 do x + bad end', 'lib/b.ak': 'type Shape case Dot end\nfn g() -> Str do 1 end' },
  { 'main.ak': 'use "a.ak"\nfn f() -> Int ensures true example f() == 1 do 1 end\nfn main() -> Unit do () end', 'a.ak': 'fn f() -> Str do "a" end\nfn g(s: Shape) -> Int do 1 end', 'b.ak': '' },
];

test('the Akashi type checker (compiled to wasm) gives the same errors as src/check.js for every .ak file and edge cases', () => {
  const cdriver = join(root, 'compiler', 'check_main.ak');
  const b = buildSource(readFileSync(cdriver, 'utf8'), { file: cdriver });
  assert.ok(b.ok, JSON.stringify(b.diagnostics));
  const run = (dir, label, file) => {
    let out = '';
    let err = '';
    const exit = runWasm(b.bytes, { stdout: (s) => { out += s; }, stderr: (s) => { err += s; }, folder: openFolder(dir) });
    assert.equal(exit, 0, `${label}\n${err}`);
    assert.equal(out, expectedCheck(file), label);
  };
  // リポジトリの .ak：フォルダを写して、main.txt にそのファイルの名前を書く
  const copies = new Map();
  for (const f of files) {
    const d = dirname(f);
    if (!copies.has(d)) {
      const t = mkdtempSync(join(tmpdir(), 'akashi-check-'));
      cpSync(d, t, { recursive: true });
      copies.set(d, t);
    }
    writeFileSync(join(copies.get(d), 'main.txt'), basename(f));
    run(copies.get(d), f.slice(root.length), f);
  }
  const sets = [...checkExtra.map((src) => ({ 'main.ak': src })), ...checkFiles];
  for (const [i, set] of sets.entries()) {
    const dir = mkdtempSync(join(tmpdir(), 'akashi-check-x-'));
    for (const [name, src] of Object.entries(set)) {
      mkdirSync(dirname(join(dir, name)), { recursive: true });
      writeFileSync(join(dir, name), src);
    }
    run(dir, `case ${i}: ${JSON.stringify(set)}`, join(dir, 'main.ak'));
    rmSync(dir, { recursive: true });
  }
});

test('the Akashi type checker gives the same answer in the interpreter, on the compiler itself', () => {
  const cdriver = join(root, 'compiler', 'check_main.ak');
  const dir = mkdtempSync(join(tmpdir(), 'akashi-check-i-'));
  cpSync(join(root, 'compiler'), dir, { recursive: true });
  writeFileSync(join(dir, 'main.txt'), 'check_main.ak');
  const t0 = Date.now();
  const r = runSource(readFileSync(cdriver, 'utf8'), { file: cdriver, grants: { folder: dir } });
  const ms = Date.now() - t0;
  assert.equal(r.ok, true, JSON.stringify(r.diagnostics));
  assert.equal(r.output, expectedCheck(cdriver));
  assert.equal(r.output, 'ok\n');
  assert.ok(ms < 60000, `took ${ms} ms`);
});

// ---- コード生成（compiler/wasm.ak）と不動点（段階6）----
import { openOutFolder } from '../src/folder.js';

// .wasm にした build_main で、フォルダ dir の main.txt のファイルをコンパイルし、{ out, err, exit, bytes } を返す
function buildWith(compiler, dir, mainName) {
  writeFileSync(join(dir, 'main.txt'), mainName);
  const outDir = mkdtempSync(join(tmpdir(), 'akashi-build-out-'));
  let out = '';
  let err = '';
  const exit = runWasm(compiler, { stdout: (s) => { out += s; }, stderr: (s) => { err += s; }, folder: openFolder(dir), outFolder: openOutFolder(outDir) });
  const bytes = out === 'ok\n' ? readFileSync(join(outDir, 'out.wasm')) : null;
  rmSync(outDir, { recursive: true });
  return { out, err, exit, bytes };
}

const bdriver = join(root, 'compiler', 'build_main.ak');
let stage1;
const stage1Bytes = () => {
  if (!stage1) {
    const b = buildSource(readFileSync(bdriver, 'utf8'), { file: bdriver });
    assert.ok(b.ok, JSON.stringify(b.diagnostics));
    stage1 = b.bytes;
  }
  return stage1;
};

// Akashi で書いたコンパイラが、JS のコンパイラ（src/wasm.js）と1バイトも違わない .wasm を書く。
// JS がコンパイルできるものは全部（E600 で逃げない）。言語や src/wasm.js を変えたら compiler/wasm.ak も同じに直す
test('the Akashi compiler (compiled to wasm) writes the same .wasm bytes as src/wasm.js for every program', () => {
  const copies = new Map();
  let n = 0;
  for (const f of files) {
    if (f === bdriver) continue; // 下の不動点のテストで見る
    const js = buildSource(readFileSync(f, 'utf8'), { file: f });
    const e600 = !js.ok && js.diagnostics[0].code === 'E600' ? js.diagnostics[0] : null; // main の無いファイル（use で使う部品）など
    if (!js.ok && !e600) continue;
    const d = dirname(f);
    if (!copies.has(d)) {
      const t = mkdtempSync(join(tmpdir(), 'akashi-build-'));
      cpSync(d, t, { recursive: true });
      copies.set(d, t);
    }
    const label = f.slice(root.length);
    const r = buildWith(stage1Bytes(), copies.get(d), basename(f));
    assert.equal(r.exit, 0, `${label}\n${r.err}`);
    if (e600) {
      assert.equal(r.out, `E600 ${e600.line}:${e600.col} ${e600.message}\n`, label);
      continue;
    }
    assert.equal(r.out, 'ok\n', label);
    assert.deepEqual(r.bytes, Buffer.from(js.bytes), label);
    n++;
  }
  assert.ok(n >= 50, `only ${n} programs were compared`);
});

// 段階6：JS で作ったコンパイラ（段階1）で自分をコンパイルして段階2、段階2で段階3。どれも1バイトも違わない
test('the compiler compiles itself to the same bytes (fixed point: stage 1 = stage 2 = stage 3)', () => {
  const dir = mkdtempSync(join(tmpdir(), 'akashi-self-'));
  cpSync(join(root, 'compiler'), dir, { recursive: true });
  const t0 = Date.now();
  const s2 = buildWith(stage1Bytes(), dir, 'build_main.ak');
  assert.equal(s2.out, 'ok\n', s2.err);
  // 今は約 1.5 秒。メモリを 1 ページずつ増やしていたころは 30 秒かかった（2026-11-19）。大きく遅くなったら気づくように
  assert.ok(Date.now() - t0 < 20000, `the compiler took ${Date.now() - t0} ms to compile itself`);
  assert.deepEqual(s2.bytes, Buffer.from(stage1Bytes()), 'stage 2 differs from stage 1');
  const s3 = buildWith(new Uint8Array(s2.bytes), dir, 'build_main.ak');
  assert.equal(s3.out, 'ok\n', s3.err);
  assert.deepEqual(s3.bytes, s2.bytes, 'stage 3 differs from stage 2');
});

test('the Akashi compiler gives the same bytes in the interpreter', () => {
  const dir = mkdtempSync(join(tmpdir(), 'akashi-build-i-'));
  const outDir = mkdtempSync(join(tmpdir(), 'akashi-build-i-out-'));
  const f = join(root, 'examples', 'gcd.ak');
  writeFileSync(join(dir, 'main.ak'), readFileSync(f, 'utf8'));
  const r = runSource(readFileSync(bdriver, 'utf8'), { file: bdriver, grants: { folder: dir, outFolder: outDir } });
  assert.equal(r.ok, true, JSON.stringify(r.diagnostics));
  assert.equal(r.output, 'ok\n');
  assert.deepEqual(readFileSync(join(outDir, 'out.wasm')), Buffer.from(buildSource(readFileSync(f, 'utf8'), { file: f }).bytes));
});
