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
  assert.equal(runSource(src('fruits.txt'), { grants }).output, 'apple\nbanana\ncherry\n\n');
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
  const coveredHere = ['E301', 'R504', ...RETIRED];
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
