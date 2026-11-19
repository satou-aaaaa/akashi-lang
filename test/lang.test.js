// 言語のきまりを1つずつ確かめる
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { analyze, checkSource, runSource, CODES, RETIRED } from '../src/index.js';
import { readdirSync } from 'node:fs';

const codes = (src) => analyze(src).diagnostics.map((d) => d.code);
const out = (body) => {
  const r = runSource(`fn say(console: Console, text: Str) -> Unit do print(to: console, value: text) end\nfn main(console: Console) -> Unit\ndo\n${body}\nend\n`);
  assert.equal(r.ok, true, JSON.stringify(r.diagnostics));
  return r.output;
};

test('arithmetic is integer, / truncates toward zero', () => {
  assert.equal(out('print(to: console, value: 7 / 2)\nprint(to: console, value: -7 / 2)\nprint(to: console, value: 7 % 3)\nprint(to: console, value: 2 + 3 * 4)'), '3\n-3\n1\n14\n');
});

test('strings and lists join with ++', () => {
  assert.equal(out('print(to: console, value: "a" ++ "b")\nprint(to: console, value: [1] ++ [2, 3])'), 'ab\n[1, 2, 3]\n');
});

test('every if has its own end, also after else', () => {
  assert.equal(out('let n: Int = 5\nprint(to: console, value: if n < 0 then "neg" else if n == 0 then "zero" else "pos" end end)'), 'pos\n');
});

test('== compares lists by value', () => {
  assert.equal(out('print(to: console, value: [1, 2] == [1, 2])\nprint(to: console, value: [1] != [2])'), 'true\ntrue\n');
});

test('and / or short-circuit', () => {
  assert.equal(out('let xs: List[Int] = []\nprint(to: console, value: len(list: xs) > 0 and get(list: xs, index: 0) == 1)'), 'false\n');
});

test('empty list gets its type from let', () => {
  assert.deepEqual(codes('fn main(console: Console) -> Unit do\n let xs: List[Str] = []\n print(to: console, value: append(list: xs, item: "a"))\nend'), []);
  assert.ok(codes('fn main(console: Console) -> Unit do\n let xs: List[Str] = []\n print(to: console, value: append(list: xs, item: 1))\nend').includes('E201'));
});

test('a non-Unit value cannot be thrown away', () => {
  assert.ok(codes('fn main(console: Console) -> Unit do\n 1 + 2\n print(to: console, value: 1)\nend').includes('E201'));
});

test('no truthiness: if needs Bool', () => {
  assert.ok(codes('fn f(n: Int) -> Int ensures true example f(n: 1) == 1 do if n then 1 else 0 end end').includes('E201'));
});

test('no implicit conversion between Str and Int', () => {
  assert.ok(codes('fn f(n: Int) -> Str ensures true example f(n: 1) == "1" do "" ++ n end').includes('E201'));
});

test('examples and contracts cannot use capabilities', () => {
  assert.ok(codes('fn f(n: Int) -> Int ensures true example print(to: console, value: 1) == () do n end').includes('E300'));
  assert.ok(codes('fn f(console: Console, n: Int) -> Int requires print(to: console, value: n) == () do n end').includes('E300'));
});

test('a function that is given a Console may print; its caller passes it on', () => {
  assert.equal(out('say(console: console, text: "x")').length >= 0, true);
});

test('capabilities cannot be returned, put in lists or compared', () => {
  assert.ok(codes('fn leak(console: Console) -> Console do console end\nfn main(console: Console) -> Unit do print(to: console, value: 1) end').includes('E309'));
  assert.ok(codes('fn main(console: Console) -> Unit do print(to: console, value: len(list: [console])) end').includes('E309'));
  assert.ok(codes('fn main(console: Console) -> Unit do print(to: console, value: console == console) end').includes('E309'));
});

test('a Folder can only read inside the granted folder', () => {
  const src = (path) => `fn main(console: Console, folder: Folder) -> Unit do print(to: console, value: read_text(from: folder, path: "${path}")) end`;
  const grants = { folder: 'examples/files' };
  assert.equal(runSource(src('fruits.txt'), { grants }).output, 'Ok(value: "apple\\nbanana\\ncherry\\n")\n');
  assert.equal(runSource(src('nothing.txt'), { grants }).output, 'Err(message: "\'nothing.txt\' does not exist")\n');
  for (const bad of ['/etc/passwd', '../bad/r507-escape.ak', 'a/../../x', 'a\\\\b']) {
    assert.equal(runSource(src(bad), { grants }).diagnostics[0].code, 'R507', bad);
  }
  assert.equal(runSource(src('fruits.txt')).diagnostics[0].code, 'R509');
});

test('a program without Folder cannot read files even when a folder is granted', () => {
  assert.ok(codes('fn main(console: Console) -> Unit do print(to: console, value: read_text(from: folder, path: "fruits.txt")) end').includes('E300'));
});

test('wrong argument name suggests the right one', () => {
  const d = analyze('fn area(width: Int, height: Int) -> Int ensures true example area(widht: 1, height: 2) == 2 do width * height end').diagnostics;
  assert.equal(d[0].code, 'E202');
  assert.match(d[0].fix, /width/);
});

test('E401/E402 are not required for main or functions with capabilities', () => {
  assert.deepEqual(codes('fn say(console: Console, s: Str) -> Unit do print(to: console, value: s) end\nfn main(console: Console) -> Unit do say(console: console, s: "x") end'), []);
});

test('run without main gives E301', () => {
  const r = runSource('fn f(n: Int) -> Int ensures true example f(n: 1) == 1 do n end');
  assert.equal(r.diagnostics[0].code, 'E301');
});

test('check reports every failing example with actual and expected', () => {
  const c = checkSource('fn inc(x: Int) -> Int ensures true example inc(x: 1) == 3 example inc(x: 2) == 5 do x + 1 end');
  assert.equal(c.diagnostics.length, 2);
  assert.equal(c.diagnostics[0].actual, '2');
  assert.equal(c.diagnostics[0].expected, '3');
});

test('overflow is an error, not a wrong number', () => {
  const r = runSource('fn main(console: Console) -> Unit do print(to: console, value: 9007199254740991 + 1) end');
  assert.equal(r.diagnostics[0].code, 'R504');
});

test('every error code has a sample in examples/bad or a test here', () => {
  const samples = readdirSync(new URL('../examples/bad/', import.meta.url)).map((f) => f.slice(0, 4).toUpperCase());
  const coveredHere = ['E301', 'R504', 'E600', 'R513', ...RETIRED]; // E600・R513 は test/compile.test.js
  for (const code of Object.keys(CODES)) {
    assert.ok(samples.includes(code) || coveredHere.includes(code), `${code} needs a sample in examples/bad/`);
  }
});

test('docs/ERRORS.md is generated from examples/bad (run node scripts/gen-errors.mjs)', async () => {
  const { readFileSync } = await import('node:fs');
  const { render } = await import('../scripts/gen-errors.mjs');
  assert.equal(readFileSync(new URL('../docs/ERRORS.md', import.meta.url), 'utf8'), render());
});

test('the complete example in docs/SPEC.md runs', async () => {
  const { readFileSync } = await import('node:fs');
  const spec = readFileSync(new URL('../docs/SPEC.md', import.meta.url), 'utf8');
  const code = spec.split('## Complete example')[1].split('```')[1];
  const r = runSource(code);
  assert.equal(r.ok, true, JSON.stringify(r.diagnostics));
  assert.equal(r.output, 'total = 12\n');
});

test('outside text cannot change the shape of HTML or SQL', () => {
  const r = runSource(`fn main(console: Console) -> Unit do
  print(to: console, value: html(template: "<p title=\\"{}\\">{}</p>", values: [html_text(value: "\\" onclick=\\"x"), html_text(value: "<img src=x onerror=alert(1)>")]))
  print(to: console, value: sql(template: "DELETE FROM t WHERE id = ?", values: ["1 OR 1=1"]))
end`);
  assert.equal(r.ok, true, JSON.stringify(r.diagnostics));
  assert.equal(r.output, '<p title="&quot; onclick=&quot;x">&lt;img src=x onerror=alert(1)&gt;</p>\nDELETE FROM t WHERE id = ? -- params: ["1 OR 1=1"]\n');
});

test('templates must be literals and Html cannot be joined as text', () => {
  assert.ok(codes('fn main(console: Console) -> Unit do\n let t: Str = "<p>{}</p>"\n print(to: console, value: html(template: t, values: [html_text(value: "a")]))\nend').includes('E310'));
  assert.ok(codes('fn main(console: Console) -> Unit do print(to: console, value: html_text(value: "a") ++ html_text(value: "b")) end').includes('E201'));
  assert.ok(codes('fn main(console: Console) -> Unit do print(to: console, value: html(template: "{}", values: ["raw"])) end').includes('E201'));
});

// html_text の置きかえで守れない場所の穴は E312（OWASP の XSS を防ぐまとめ：引用符の無い属性・script・イベント・URL の属性）
test('html holes are only allowed where html_text keeps them safe (E312)', () => {
  const holeCodes = (t) => codes(`fn main(console: Console) -> Unit do print(to: console, value: html(template: ${JSON.stringify(t)}, values: [html_text(value: "javascript:alert(1)")])) end`);
  for (const bad of ['<a href="{}">x</a>', '<a HREF=" JavaScript:{}">', '<img src={}>', '<p title={}>', '<p {}>', '<script>let a = "{}"</script>', '<p onclick="go({})">', '<p style="{}">', '<iframe srcdoc="{}">', '<!-- {} -->', '<a href="&#106;avascript:{}">']) {
    assert.ok(holeCodes(bad).includes('E312'), bad);
  }
  for (const ok of ['<p>{}</p>', '<p title="{}">', "<p title='{}'>", '<a href="/users/{}">', '<a href="?q={}">', '<a href="#{}">', '<a href="mailto:{}">', '<a href="HTTPS:' + '//example.com/{}">', '<script>1</script><p>{}</p>', '<textarea>{}</textarea>']) {
    assert.ok(!holeCodes(ok).includes('E312'), ok);
  }
});

test('when picks the first true line and needs else', () => {
  assert.equal(out('let n: Int = 42\nprint(to: console, value: when\n n < 10 then "small"\n n < 100 then "medium"\n else "large"\nend)'), 'medium\n');
});

test('generated inputs find a broken ensures and show the smallest one', () => {
  const c = checkSource('fn abs(x: Int) -> Int ensures result >= 0 example abs(x: 3) == 3 do x end');
  assert.equal(c.diagnostics[0].code, 'R511');
  assert.equal(c.diagnostics[0].input, 'abs(x: -1)');
});

test('generated inputs respect requires', () => {
  const c = checkSource('fn per(total: Int, count: Int) -> Int requires count > 0 ensures true example per(total: 4, count: 2) == 2 do total / count end');
  assert.equal(c.ok, true, JSON.stringify(c.diagnostics));
  assert.ok(c.generated > 50);
});

test('generated inputs give the same result every time (fixed seed)', () => {
  const src = 'fn f(xs: List[Int], s: Str) -> Int ensures result >= 0 example f(xs: [1], s: "a") == 2 do len(list: xs) + str_len(text: s) end';
  assert.deepEqual(checkSource(src), checkSource(src));
});

test('long-running generated inputs are skipped, not reported', () => {
  const c = checkSource('fn spin(n: Int) -> Int requires n >= 0 ensures true example spin(n: 1) == 0 do if n == 0 then 0 else spin(n: n - 1) end end');
  assert.equal(c.ok, true, JSON.stringify(c.diagnostics));
});

// v0.5：自分で作る型・漏れの無い match・Option・Result
const SHAPE = 'type Shape\n  case Circle(radius: Int)\n  case Rect(width: Int, height: Int)\nend\n';

test('a declared type is built with named fields and printed back the same way', () => {
  const src = `${SHAPE}fn main(console: Console) -> Unit do print(to: console, value: [Circle(radius: 1), Rect(width: 2, height: 3)]) end`;
  assert.equal(runSource(src).output, '[Circle(radius: 1), Rect(width: 2, height: 3)]\n');
});

test('match must handle every case; a later new case is reported where it is missed', () => {
  const area = 'fn area(s: Shape) -> Int\n  ensures true\n  example area(s: Circle(radius: 1)) == 3\ndo\n  match s\n    case Circle(radius: r) then 3 * r * r\n    case Rect(width: w, height: h) then w * h\n  end\nend\n';
  assert.deepEqual(codes(SHAPE + area), []);
  const grown = SHAPE.replace('end\n', '  case Dot\nend\n');
  assert.deepEqual(codes(grown + area), ['E210']);
});

test('match has no catch-all: else and _ are refused', () => {
  assert.deepEqual(codes('fn f(x: Option[Int]) -> Int\n  ensures true\n  example f(x: None) == 0\ndo match x case None then 0 else 1 end end'), ['E211']);
  assert.ok(codes('fn f(x: Option[Int]) -> Int\n  ensures true\n  example f(x: None) == 0\ndo match x case None then 0 case _ then 1 end end').includes('E211'));
});

test('a case from another type, a repeated case and wrong fields are reported', () => {
  assert.ok(codes(`${SHAPE}fn f(x: Option[Int]) -> Int\n  ensures true\n  example f(x: None) == 0\ndo match x case None then 0 case Circle(radius: r) then r end end`).includes('E211'));
  assert.ok(codes('fn f(x: Option[Int]) -> Int\n  ensures true\n  example f(x: None) == 0\ndo match x case None then 0 case None then 1 case Some(value: v) then v end end').includes('E211'));
  assert.deepEqual(codes(`${SHAPE}fn f(s: Shape) -> Int\n  ensures true\n  example f(s: Circle(radius: 1)) == 1\ndo match s case Circle(radius: r) then r case Rect(height: h, width: w) then w end end`), ['E212']);
});

test('there is no null: missing values are Option, and the fix says so', () => {
  assert.deepEqual(codes('fn main(console: Console) -> Unit do print(to: console, value: null) end'), ['E200']);
  assert.equal(out('print(to: console, value: [parse_int(text: "12"), parse_int(text: "1.5"), parse_int(text: "")])'), '[Some(value: 12), None, None]\n');
  assert.equal(out('print(to: console, value: [at(list: [5], index: 0), at(list: [5], index: 1)])'), '[Some(value: 5), None]\n');
});

test('an Option or Result cannot be used as its value without match', () => {
  assert.deepEqual(codes('fn main(console: Console) -> Unit do print(to: console, value: parse_int(text: "1") + 1) end'), ['E201']);
});

test('pattern names follow the no-shadowing rule', () => {
  assert.ok(codes('fn f(n: Int, x: Option[Int]) -> Int\n  ensures true\n  example f(n: 1, x: None) == 1\ndo match x case Some(value: n) then n case None then n end end').includes('E203'));
});

test('capabilities cannot be stored in data', () => {
  assert.ok(codes('fn main(console: Console) -> Unit do print(to: console, value: Some(value: console)) end').includes('E309'));
  assert.ok(codes('type Box case Box(c: Console) end\nfn main(console: Console) -> Unit do print(to: console, value: 1) end').includes('E309'));
});

test('generated inputs reach declared types and are shrunk', () => {
  const src = `${SHAPE}fn area(s: Shape) -> Int\n  ensures result >= 0\n  example area(s: Rect(width: 2, height: 3)) == 6\ndo\n  match s\n    case Circle(radius: r) then 3 * r\n    case Rect(width: w, height: h) then w * h\n  end\nend\n`;
  const c = checkSource(src);
  assert.equal(c.diagnostics[0].code, 'R511');
  assert.match(c.diagnostics[0].input, /^area\(s: (Circle\(radius: -1\)|Rect\(width: -?1, height: -?1\))\)$/);
});

test('recursive types work and generation stops at a safe depth', () => {
  const src = 'type Tree\n  case Leaf\n  case Node(left: Tree, value: Int, right: Tree)\nend\nfn size(t: Tree) -> Int\n  ensures result >= 0\n  example size(t: Node(left: Leaf, value: 1, right: Leaf)) == 1\ndo\n  match t\n    case Leaf then 0\n    case Node(left: l, value: _, right: r) then size(t: l) + 1 + size(t: r)\n  end\nend\n';
  const c = checkSource(src);
  assert.deepEqual(c.diagnostics, []);
  assert.ok(c.generated > 0);
});

// v0.7：標準の道具
test('standard list and text tools', () => {
  assert.equal(out('print(to: console, value: [take(list: [1, 2, 3], count: 5), drop(list: [1, 2, 3], count: 5), reverse(list: [1, 2])])'), '[[1, 2, 3], [], [2, 1]]\n');
  assert.equal(out('print(to: console, value: [sort(list: [3, -1, 2]), [sum(list: [])]])'), '[[-1, 2, 3], [0]]\n');
  assert.equal(out('print(to: console, value: [chars(text: ""), split(text: "a", by: ","), [join(parts: [], by: ",")]])'), '[[], ["a"], [""]]\n');
});

test('standard tools stop instead of guessing: negative counts, empty separators, overflowing sums', () => {
  assert.equal(runSource('fn main(console: Console) -> Unit do print(to: console, value: take(list: [1], count: -1)) end').diagnostics[0].code, 'R506');
  assert.equal(runSource('fn main(console: Console) -> Unit do print(to: console, value: split(text: "ab", by: "")) end').diagnostics[0].code, 'R506');
  assert.equal(runSource('fn main(console: Console) -> Unit do print(to: console, value: sum(list: [9007199254740991, 1])) end').diagnostics[0].code, 'R504');
});

test('standard tool names are reserved like every other name', () => {
  assert.ok(codes('fn sum(xs: List[Int]) -> Int\n  ensures true\n  example sum(xs: []) == 0\ndo 0 end\nfn main(console: Console) -> Unit do print(to: console, value: 1) end').includes('E203'));
});

// v0.11：文字（コードポイント）単位の道具（字句解析を Akashi で書くため）
test('slice, code_of and char_of count characters, not bytes, and stop on bad input', () => {
  assert.equal(out('print(to: console, value: [slice(text: "aあ😀b", from: 1, to: 3), char_of(code: 128512)])'), '["あ😀", "😀"]\n');
  assert.equal(out('print(to: console, value: [code_of(char: "あ"), code_of(char: "😀")])'), '[12354, 128512]\n');
  for (const bad of ['slice(text: "ab", from: 1, to: 3)', 'slice(text: "ab", from: 2, to: 1)', 'code_of(char: "ab")', 'char_of(code: 55296)', 'char_of(code: -1)']) {
    assert.equal(runSource(`fn main(console: Console) -> Unit do print(to: console, value: ${bad}) end`).diagnostics[0].code, 'R506', bad);
  }
});

// 複数のファイル（use）。パスの決まり・エラーの場所・名前の重なり・輪・ブラウザ（読む方法が無い）
test('use reads other files, reports errors in the file where they are, and keeps names unique', async () => {
  const { mkdtempSync, mkdirSync, writeFileSync } = await import('node:fs');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const core = await import('../src/core.js');
  const dir = mkdtempSync(join(tmpdir(), 'akashi-use-'));
  mkdirSync(join(dir, 'lib'));
  const put = (name, text) => writeFileSync(join(dir, name), text);
  const main = (uses, body = 'print(to: console, value: 1)') => `${uses.map((u) => `use "${u}"`).join('\n')}\n\nfn main(console: Console) -> Unit\ndo\n  ${body}\nend\n`;
  const pure = (name, body = 'n + 1') => `fn ${name}(n: Int) -> Int\n  ensures true\n  example ${name}(n: 1) == ${name}(n: 1)\ndo\n  ${body}\nend\n`;
  const run = (src) => runSource(src, { file: join(dir, 'main.ak') });
  put('lib/a.ak', `use "b.ak"\n\n${pure('inc_a', 'inc_b(n: n)')}`);
  put('lib/b.ak', `use "a.ak"\n\n${pure('inc_b')}`); // 輪になっていてもよい
  assert.equal(run(main(['lib/a.ak'], 'print(to: console, value: inc_a(n: 1))')).output, '2\n');
  put('lib/bad.ak', pure('oops', 'n + "x"'));
  const bad = run(main(['lib/bad.ak'])).diagnostics[0];
  assert.equal(bad.code, 'E201');
  assert.equal(bad.file, 'lib/bad.ak');
  assert.equal(bad.line, 5);
  put('lib/dup.ak', pure('inc_b'));
  assert.equal(run(main(['lib/a.ak', 'lib/dup.ak'])).diagnostics[0].code, 'E203');
  for (const p of ['../x.ak', '/x.ak', 'lib\\\\a.ak', 'lib/a.txt', 'lib//a.ak', 'C:a.ak']) assert.equal(run(main([p])).diagnostics[0].code, 'E113', p);
  assert.equal(run(main(['lib/none.ak'])).diagnostics[0].code, 'E114');
  // ブラウザ（遊べるページ）にはファイルが無い
  assert.equal(core.runSource(main(['lib/a.ak'])).diagnostics[0].code, 'E114');
  // use は fn・type より前だけ
  assert.equal(run(`${pure('f')}\nuse "lib/a.ak"\n`).diagnostics[0].code, 'E100');
});
