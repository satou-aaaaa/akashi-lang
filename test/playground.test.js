// 遊べるページ：ブラウザで動く部品が Node の部品を使っていないか・外へ通信しないか・仕事の中身
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { handle } from '../playground/handle.js';

const root = new URL('../', import.meta.url);
const read = (p) => readFileSync(new URL(p, root), 'utf8');

// ブラウザで読むファイルを、import をたどって全部集める
function browserFiles() {
  const seen = new Set();
  const visit = (p) => {
    if (seen.has(p)) return;
    seen.add(p);
    for (const [, spec] of read(p).matchAll(/(?:import|export)\s[^'"]*?from\s+['"]([^'"]+)['"]|import\s+['"]([^'"]+)['"]/g)) {
      assert.ok(spec.startsWith('.'), `${p} imports '${spec}', which a browser cannot load`);
      visit(new URL(spec, new URL(p, root)).pathname.slice(new URL(root).pathname.length));
    }
  };
  ['playground/app.js', 'playground/worker.js'].forEach(visit);
  return [...seen];
}

test('files loaded by the browser use no Node modules and no outside network', () => {
  const files = browserFiles();
  assert.ok(files.includes('src/core.js') && files.includes('src/wasm.js') && files.includes('src/fmt.js'), files.join(' '));
  for (const f of files) {
    const text = read(f);
    assert.doesNotMatch(text, /from\s+['"]node:/, `${f} must not use Node modules`);
    assert.doesNotMatch(text, /https?:\/\/(?!github\.com\/satou-aaaaa)/, `${f} must not reach other sites`);
  }
});

test('the page forbids outside connections with its Content-Security-Policy', () => {
  const html = read('index.html');
  const csp = html.match(/Content-Security-Policy" content="([^"]+)"/)[1];
  for (const want of ["default-src 'none'", "script-src 'self'", "connect-src 'self'", "worker-src 'self'"]) assert.ok(csp.includes(want), want);
  assert.doesNotMatch(csp, /https?:|\*|unsafe/);
  assert.doesNotMatch(html, /<script(?![^>]*src="playground\/)/, 'only our own scripts');
});

test('the examples listed in the page exist', () => {
  const names = read('playground/app.js').match(/const EXAMPLES = \[([^\]]+)\]/)[1].match(/'([^']+)'/g).map((x) => x.slice(1, -1));
  for (const n of names) assert.ok(read(`examples/${n}.ak`).length > 0, n);
});

test('check, run, wasm and fmt give results like the command line', () => {
  const src = read('examples/gcd.ak');
  assert.match(handle({ action: 'check', src }).summary, /^ok: 2\/2 examples passed/);
  assert.equal(handle({ action: 'run', src }).output, '21\n');
  const w = handle({ action: 'wasm', src });
  assert.equal(w.output, '21\n');
  assert.ok(w.bytes > 100);
  assert.equal(handle({ action: 'fmt', src: 'fn main(console:Console)->Unit do print(to:console,value:1) end' }).text, 'fn main(console: Console) -> Unit do print(to: console, value: 1) end\n');
  const bad = handle({ action: 'run', src: 'fn main(console: Console) -> Unit do print(to: console, value: 1 + "a") end' });
  assert.equal(bad.diagnostics[0].code, 'E201');
});

test('the page cannot read files: a program that asks for a Folder is refused', () => {
  const r = handle({ action: 'run', src: read('examples/read_file.ak') });
  assert.equal(r.diagnostics[0].code, 'R509');
});
