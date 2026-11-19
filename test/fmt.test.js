// akashi fmt：意味を変えない・2回かけても同じ・リポジトリの .ak と説明書きのコードは整っている
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { format } from '../src/fmt.js';
import { parse } from '../src/parse.js';

const root = new URL('../', import.meta.url);
const tree = (src) => JSON.stringify(parse(src), (k, v) => (k === 'pos' || k === 'vpos' || k === 'src' ? undefined : v));

const files = ['examples/', 'examples/bad/', 'test/compile/'].flatMap((d) =>
  readdirSync(new URL(d, root)).filter((f) => f.endsWith('.ak')).map((f) => d + f));
const docBlocks = ['README.md', ...readdirSync(new URL('docs/', root)).filter((f) => f.endsWith('.md')).map((f) => `docs/${f}`)]
  .flatMap((f) => [...readFileSync(new URL(f, root), 'utf8').matchAll(/^```akashi\n([\s\S]*?)^```$/gm)].map((m, i) => [`${f} block ${i + 1}`, m[1]]));

test('every .ak file in the repository is formatted (run node bin/akashi.js fmt <file>)', () => {
  for (const f of files) {
    const src = readFileSync(new URL(f, root), 'utf8');
    const r = format(src);
    if (!r.ok) continue; // 構文の誤りの見本（E1xx）は整えられない
    assert.equal(r.text, src, `${f} is not formatted`);
  }
});

test('code in the docs is formatted', () => {
  for (const [name, src] of docBlocks) assert.equal(format(src).text, src, `${name} is not formatted`);
});

const MESSY = 'type   Shape\ncase Circle( radius :Int )\n      case Dot\nend\n\n\n\n# area\nfn area(s:Shape)->Int   # c\nensures result>=0\n      example area(s:Dot)==0\ndo\n\n  match s\ncase Circle(radius:r) then 3*r*r\n case Dot then 0\n   end\n\nend\nfn main(console:Console)->Unit do\nlet x:Int=if 1<2 then -1 else 2-(-3) end\n  when\n x>0 then print(to:console,value:[1,2])\nelse print(to:console,value:not(x==1))\nend\n    if x == 1 then\nprint(to: console, value: "a  #b")\n  else\n  print(to: console, value: List)\nend\nend\n';
const NEAT = `type Shape
  case Circle(radius: Int)
  case Dot
end

# area
fn area(s: Shape) -> Int # c
  ensures result >= 0
  example area(s: Dot) == 0
do
  match s
    case Circle(radius: r) then 3 * r * r
    case Dot then 0
  end
end

fn main(console: Console) -> Unit do
  let x: Int = if 1 < 2 then -1 else 2 - (-3) end
  when
    x > 0 then print(to: console, value: [1, 2])
    else print(to: console, value: not (x == 1))
  end
  if x == 1 then
    print(to: console, value: "a  #b")
  else
    print(to: console, value: List)
  end
end
`;

test('messy code becomes the standard layout', () => {
  assert.equal(format(MESSY).text, NEAT);
});

test('formatting never changes the meaning and is stable (all samples, twice)', () => {
  const sources = [MESSY, ...files.map((f) => readFileSync(new URL(f, root), 'utf8')), ...docBlocks.map(([, s]) => s)];
  for (const src of sources) {
    const r = format(src);
    if (!r.ok) continue;
    assert.equal(tree(r.text), tree(src));
    assert.equal(format(r.text).text, r.text);
  }
});

test('a program with a syntax error is not formatted, and the error is reported', () => {
  const r = format('fn f( -> Int do 1 end');
  assert.equal(r.ok, false);
  assert.equal(r.error.code, 'E100');
});

// 2026-11-19：「case ... then」の後ろの行に値を書くと、値の行が case と同じ深さに戻っていた（test/compile/data.ak で見つけた）
test('a match arm whose value is on the next line is indented one step deeper', () => {
  const src = 'fn f(x: Option[Int]) -> Int\n  ensures true\n  example f(x: None) == 0\ndo\n  match x\n    case Some(value: v) then\n      v + 1\n    case None then 0\n  end\nend\n';
  assert.equal(format(src).text, src);
  assert.equal(format(src.replace('      v + 1', 'v + 1')).text, src);
  const nested = 'fn g(x: Option[Int]) -> Int\n  ensures true\n  example g(x: None) == 0\ndo\n  match x\n    case Some(value: v) then\n      if v > 0 then\n        v\n      else\n        0\n      end\n    case None then 0\n  end\nend\n';
  assert.equal(format(nested).text, nested);
});
