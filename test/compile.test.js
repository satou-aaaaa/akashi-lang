// コンパイラ（src/wasm.js）の答えが、インタプリタ（意味の正）と同じかを比べる。
// 比べるもの：画面への出力・終わりのコード・実行時のエラー番号。
// 見本：examples/*.ak のうちコンパイルできるもの、test/compile/*.ak、自動で作った式。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { runSource, buildSource, analyze, CODES } from '../src/index.js';
import { runWasm } from '../src/host.js';

function viaInterpreter(src) {
  const r = runSource(src);
  return { out: r.output, exit: r.ok ? 0 : 1, code: r.ok ? null : r.diagnostics[0].code };
}

function viaWasm(src) {
  const b = buildSource(src);
  if (!b.ok) return { unsupported: b.diagnostics[0] };
  assert.ok(WebAssembly.validate(b.bytes), 'the module is valid WebAssembly');
  let out = '';
  let err = '';
  const exit = runWasm(b.bytes, { stdout: (s) => { out += s; }, stderr: (s) => { err += s; } });
  return { out, exit, code: err.match(/\b([ER]\d{3})\b/)?.[1] ?? null, err };
}

const same = (src, label) => {
  const w = viaWasm(src);
  if (w.unsupported) return false;
  const i = viaInterpreter(src);
  assert.deepEqual({ out: w.out, exit: w.exit, code: w.code }, i, `${label}\n${w.err ?? ''}`);
  return true;
};

const dirs = [new URL('../examples/', import.meta.url), new URL('./compile/', import.meta.url)];
let compiled = 0;
for (const dir of dirs) {
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.ak'))) {
    const src = readFileSync(new URL(f, dir), 'utf8');
    if (/^# grant:/m.test(src)) continue;
    test(`wasm and interpreter agree: ${f}`, () => {
      if (same(src, f)) compiled++;
      else assert.ok(!dir.href.endsWith('/compile/'), `${f} in test/compile must be supported by the compiler`);
    });
  }
}

test('hello and gcd compile (the compiler is not silently skipping everything)', () => {
  assert.ok(compiled >= 10, `only ${compiled} programs compiled`);
});

test('unsupported features give E600 with a position and a fix', () => {
  const b = buildSource('fn main(console: Console) -> Unit do print(to: console, value: len(list: [1, 2])) end');
  assert.equal(b.ok, false);
  assert.equal(b.diagnostics[0].code, 'E600');
  assert.ok(b.diagnostics[0].line > 0 && b.diagnostics[0].fix.length > 10);
  assert.ok(CODES.E600);
});

test('a program that does not pass check is not compiled', () => {
  const b = buildSource('fn main(console: Console) -> Unit do print(to: console, value: 1 + "a") end');
  assert.equal(b.diagnostics[0].code, 'E201');
});

test('the module imports only fd_write and proc_exit (no files, clock, random or network)', () => {
  const b = buildSource(readFileSync(new URL('../examples/gcd.ak', import.meta.url), 'utf8'));
  const imports = WebAssembly.Module.imports(new WebAssembly.Module(b.bytes)).map((x) => `${x.module}.${x.name}`);
  assert.deepEqual(imports, ['wasi_snapshot_preview1.fd_write', 'wasi_snapshot_preview1.proc_exit']);
  const exports = WebAssembly.Module.exports(new WebAssembly.Module(b.bytes)).map((x) => x.name).sort();
  assert.deepEqual(exports, ['_start', 'memory']);
});

// 自動で作った式（Int と Bool）を、両方で動かして比べる。種は固定
function rng(seed) {
  let a = seed >>> 0;
  return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
function genInt(r, d) {
  if (d <= 0 || r() < 0.25) {
    const pool = [0, 1, -1, 2, 7, -13, 100, 3037000499, 9007199254740991, -9007199254740991, 4503599627370496];
    return String(pool[Math.floor(r() * pool.length)]);
  }
  const ops = ['+', '-', '*', '/', '%'];
  if (r() < 0.15) return `-(${genInt(r, d - 1)})`;
  if (r() < 0.15) return `if ${genBool(r, d - 1)} then ${genInt(r, d - 1)} else ${genInt(r, d - 1)} end`;
  return `(${genInt(r, d - 1)} ${ops[Math.floor(r() * ops.length)]} ${genInt(r, d - 1)})`;
}
function genBool(r, d) {
  if (d <= 0 || r() < 0.2) return r() < 0.5 ? 'true' : 'false';
  const k = r();
  if (k < 0.5) return `(${genInt(r, d - 1)} ${['<', '<=', '>', '>=', '==', '!='][Math.floor(r() * 6)]} ${genInt(r, d - 1)})`;
  if (k < 0.7) return `not ${genBool(r, d - 1)}`;
  return `(${genBool(r, d - 1)} ${r() < 0.5 ? 'and' : 'or'} ${genBool(r, d - 1)})`;
}

test('generated Int and Bool expressions give the same result (300 programs)', () => {
  const r = rng(20261119);
  let errors = 0;
  for (let i = 0; i < 300; i++) {
    const e = r() < 0.7 ? genInt(r, 4) : genBool(r, 4);
    const src = `fn main(console: Console) -> Unit do print(to: console, value: ${e}) end`;
    if (analyze(src).diagnostics.length) continue;
    assert.ok(same(src, src));
    if (viaInterpreter(src).code) errors++;
  }
  assert.ok(errors > 10 && errors < 250, `the generated programs should include both errors and results (${errors} errors)`);
});
