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
      return `Token(kind: ${JSON.stringify(t.t)}, text: ${JSON.stringify(text)}, line: ${t.pos.line}, col: ${t.pos.col})`;
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
