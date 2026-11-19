// セルフホスト（docs/compiler.md 段階5）：Akashi で書いた部品が、JS の処理系と同じ答えを出すかを比べる。
// 今は字句解析（compiler/lexer.ak）。リポジトリの全部の .ak（壊れた見本も）を、src/parse.js の lex と比べる。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, mkdtempSync, writeFileSync, statSync } from 'node:fs';
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
import { dirname } from 'node:path';

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
