// コンパイラ（src/wasm.js）の答えが、インタプリタ（意味の正）と同じかを比べる。
// 比べるもの：画面への出力・終わりのコード・実行時のエラー番号。
// 見本：examples/*.ak のうちコンパイルできるもの、test/compile/*.ak、自動で作った式。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, mkdtempSync, writeFileSync, symlinkSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runSource, buildSource, analyze, CODES } from '../src/index.js';
import { runWasm } from '../src/host.js';
import { openFolder } from '../src/folder.js';

function viaInterpreter(src, folder) {
  const r = runSource(src, { grants: { folder } });
  return { out: r.output, exit: r.ok ? 0 : 1, code: r.ok ? null : r.diagnostics[0].code };
}

function viaWasm(src, folder) {
  const b = buildSource(src);
  if (!b.ok) return { unsupported: b.diagnostics[0] };
  assert.ok(WebAssembly.validate(b.bytes), 'the module is valid WebAssembly');
  let out = '';
  let err = '';
  const exit = runWasm(b.bytes, { stdout: (s) => { out += s; }, stderr: (s) => { err += s; }, folder: folder ? openFolder(folder) : undefined });
  return { out, exit, code: err.match(/\b([ER]\d{3})\b/)?.[1] ?? null, err };
}

const same = (src, label, folder) => {
  const w = viaWasm(src, folder);
  if (w.unsupported) return false;
  const i = viaInterpreter(src, folder);
  assert.deepEqual({ out: w.out, exit: w.exit, code: w.code }, i, `${label}\n${w.err ?? ''}`);
  return true;
};

const dirs = [new URL('../examples/', import.meta.url), new URL('./compile/', import.meta.url)];
let compiled = 0;
for (const dir of dirs) {
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.ak'))) {
    const src = readFileSync(new URL(f, dir), 'utf8');
    const grant = src.match(/^# grant: (.+)$/m)?.[1];
    test(`wasm and interpreter agree: ${f}`, () => {
      if (same(src, f, grant && fileURLToPath(new URL(`../${grant}`, import.meta.url)))) compiled++;
      else assert.ok(!dir.href.endsWith('/compile/'), `${f} in test/compile must be supported by the compiler`);
    });
  }
}

test('hello and gcd compile (the compiler is not silently skipping everything)', () => {
  assert.ok(compiled >= 10, `only ${compiled} programs compiled`);
});

test('unsupported features give E600 with a position and a fix', () => {
  const b = buildSource('fn dbl(x: Int) -> Int\n  ensures true\n  example dbl(x: 1) == 2\ndo\n  x * 2\nend\n\nfn main(console: Console) -> Unit do\n  print(to: console, value: dbl)\nend\n');
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

// 自動で作ったリストの式（段階2）を、両方で動かして比べる。種は固定
function genList(r, d) {
  const pick = (xs) => xs[Math.floor(r() * xs.length)];
  if (d <= 0 || r() < 0.2) {
    if (r() < 0.3) return `range(from: ${genInt(r, 1)}, to: ${pick(['0', '3', '10', '-2'])})`;
    const n = Math.floor(r() * 5);
    return `[${Array.from({ length: n }, () => genInt(r, 1)).join(', ')}]`;
  }
  switch (Math.floor(r() * 8)) {
    case 0: return `reverse(list: ${genList(r, d - 1)})`;
    case 1: return `take(list: ${genList(r, d - 1)}, count: ${pick(['0', '1', '3', '9', '-1'])})`;
    case 2: return `drop(list: ${genList(r, d - 1)}, count: ${pick(['0', '2', '9', '-2'])})`;
    case 3: return `sort(list: ${genList(r, d - 1)})`;
    case 4: return `append(list: ${genList(r, d - 1)}, item: ${genInt(r, 1)})`;
    case 5: return `(${genList(r, d - 1)} ++ ${genList(r, d - 1)})`;
    case 6: return `map(list: ${genList(r, d - 1)}, func: twice)`;
    default: return `filter(list: ${genList(r, d - 1)}, func: odd)`;
  }
}

test('generated list expressions give the same result (200 programs)', () => {
  const r = rng(20261120);
  const head = 'fn twice(x: Int) -> Int\n  ensures true\n  example twice(x: 1) == 2\ndo\n  x * 2\nend\n\nfn odd(x: Int) -> Bool\n  ensures true\n  example odd(x: 3)\ndo\n  x % 2 != 0\nend\n\n';
  let errors = 0;
  for (let i = 0; i < 200; i++) {
    const l = genList(r, 3);
    const k = r();
    const e = k < 0.5 ? l : k < 0.6 ? `sum(list: ${l})` : k < 0.7 ? `max(list: ${l})` : k < 0.8 ? `get(list: ${l}, index: ${Math.floor(r() * 4)})` : k < 0.9 ? `at(list: ${l}, index: ${Math.floor(r() * 4) - 1})` : `${l} == ${genList(r, 2)}`;
    const src = `${head}fn main(console: Console) -> Unit do print(to: console, value: ${e}) end`;
    if (analyze(src).diagnostics.length) continue;
    assert.ok(same(src, e), `not compiled: ${e}\n${JSON.stringify(viaWasm(src).unsupported)}`);
    if (viaInterpreter(src).code) errors++;
  }
  assert.ok(errors > 5 && errors < 150, `the generated programs should include both errors and results (${errors} errors)`);
});

// 自動で作った文字の式を、両方で動かして比べる。種は固定
function genStr(r, d) {
  const pick = (xs) => xs[Math.floor(r() * xs.length)];
  const atoms = ['""', '"a"', '"ab,c"', '",,"', '" x y "', '"あい,う"', '"a\\nb\\n"', '"\\n"', '"😀,😀"', '"a\\"b\\\\"', '"<&>"'];
  if (d <= 0 || r() < 0.3) return pick(atoms);
  switch (Math.floor(r() * 5)) {
    case 0: return `(${genStr(r, d - 1)} ++ ${genStr(r, d - 1)})`;
    case 1: return `join(parts: split(text: ${genStr(r, d - 1)}, by: ${pick(['","', '"a"', '"\\n"', '"😀"'])}), by: ${pick(['"-"', '""', '"あ"'])})`;
    case 2: return `trim(text: ${genStr(r, d - 1)})`;
    case 3: return `join(parts: reverse(list: chars(text: ${genStr(r, d - 1)})), by: "")`;
    default: return `to_str(value: html_text(value: ${genStr(r, d - 1)}))`;
  }
}

test('generated text expressions give the same result (200 programs)', () => {
  const r = rng(20261121);
  for (let i = 0; i < 200; i++) {
    const s = genStr(r, 3);
    const k = r();
    const e = k < 0.3 ? s : k < 0.45 ? `split(text: ${s}, by: ",")` : k < 0.55 ? `lines(text: ${s})` : k < 0.65 ? `chars(text: ${s})`
      : k < 0.75 ? `contains(text: ${s}, part: ${genStr(r, 1)})` : k < 0.85 ? `starts_with(text: ${s}, prefix: ${genStr(r, 1)})`
        : k < 0.9 ? `ends_with(text: ${s}, suffix: ${genStr(r, 1)})` : `[${s}, ${genStr(r, 2)}]`;
    const src = `fn main(console: Console) -> Unit do print(to: console, value: ${e}) end`;
    if (analyze(src).diagnostics.length) continue;
    assert.ok(same(src, e), `not compiled: ${e}\n${JSON.stringify(viaWasm(src).unsupported)}`);
  }
});

// 自動で作った辞書の式を、両方で動かして比べる（鍵の順・重なり・数の食い違い・全角や絵文字の鍵）。種は固定
function genDict(r, d) {
  const pick = (xs) => xs[Math.floor(r() * xs.length)];
  const keys = ['""', '"a"', '"b"', '"ab"', '"B"', '"é"', '"😀"', '"あ"', '"a b"'];
  if (d <= 0 || r() < 0.25) {
    const n = Math.floor(r() * 4);
    const ks = Array.from({ length: n }, () => pick(keys));
    const vs = Array.from({ length: r() < 0.1 ? n + 1 : n }, () => genInt(r, 1));
    return `dict(keys: [${ks.join(', ')}], values: [${vs.join(', ')}])`;
  }
  switch (Math.floor(r() * 3)) {
    case 0: return `dict_put(dict: ${genDict(r, d - 1)}, key: ${pick(keys)}, value: ${genInt(r, 1)})`;
    case 1: return `dict_remove(dict: ${genDict(r, d - 1)}, key: ${pick(keys)})`;
    default: return `dict_put(dict: ${genDict(r, d - 1)}, key: ${pick(keys)}, value: dict_size(dict: ${genDict(r, d - 1)}))`;
  }
}

test('generated dictionary expressions give the same result (200 programs)', () => {
  const r = rng(20261122);
  let errors = 0;
  for (let i = 0; i < 200; i++) {
    const m = genDict(r, 3);
    const k = r();
    const key = ['"a"', '"b"', '"😀"', '"zz"'][Math.floor(r() * 4)];
    const e = k < 0.4 ? m : k < 0.5 ? `dict_keys(dict: ${m})` : k < 0.6 ? `dict_values(dict: ${m})` : k < 0.7 ? `dict_get(dict: ${m}, key: ${key})`
      : k < 0.8 ? `dict_has(dict: ${m}, key: ${key})` : k < 0.9 ? `${m} == ${genDict(r, 2)}` : `[${m}, ${genDict(r, 1)}]`;
    const src = `fn main(console: Console) -> Unit do print(to: console, value: ${e}) end`;
    if (analyze(src).diagnostics.length) continue;
    assert.ok(same(src, e), `not compiled: ${e}\n${JSON.stringify(viaWasm(src).unsupported)}`);
    if (viaInterpreter(src).code) errors++;
  }
  assert.ok(errors > 5 && errors < 150, `the generated programs should include both errors and results (${errors} errors)`);
});

// ファイルを読む（段階3）：渡したフォルダの中だけ。外へのリンク・.. ・渡していないときは止まる。読めないものは Err
test('reading files agrees with the interpreter, including links out, folders, bad UTF-8 and a BOM', () => {
  const root = mkdtempSync(join(tmpdir(), 'akashi-'));
  const inside = join(root, 'in');
  mkdirSync(inside);
  mkdirSync(join(inside, 'sub'));
  writeFileSync(join(root, 'secret.txt'), 'secret');
  writeFileSync(join(inside, 'a.txt'), 'line 1\r\nline 2\n');
  writeFileSync(join(inside, 'sub', 'b.txt'), 'あい😀');
  writeFileSync(join(inside, 'bom.txt'), Buffer.from([0xef, 0xbb, 0xbf, 0x68, 0x69]));
  writeFileSync(join(inside, 'bad.txt'), Buffer.from([0x61, 0xc0, 0xaf]));
  writeFileSync(join(inside, 'surrogate.txt'), Buffer.from([0xed, 0xa0, 0x80]));
  writeFileSync(join(inside, 'big.txt'), 'x'.repeat(200000));
  symlinkSync(join(root, 'secret.txt'), join(inside, 'link.txt'));
  symlinkSync(join(inside, 'a.txt'), join(inside, 'ok-link.txt'));
  const prog = (path) => `fn main(console: Console, folder: Folder) -> Unit do
  match read_text(from: folder, path: "${path}")
    case Ok(value: t) then print(to: console, value: if str_len(text: t) > 50 then to_str(value: str_len(text: t)) else t end)
    case Err(message: m) then print(to: console, value: "Err " ++ m)
  end
end`;
  const paths = ['a.txt', 'sub/b.txt', 'bom.txt', 'bad.txt', 'surrogate.txt', 'big.txt', 'nothing.txt', 'sub', 'ok-link.txt', 'link.txt',
    '../secret.txt', 'sub/../a.txt', '/etc/passwd', 'C:x', '', 'a\\\\b', './a.txt', 'sub/./b.txt', '..x/a', 'x..'];
  const codes = [];
  for (const p of paths) {
    assert.ok(same(prog(p), p, inside), `not compiled: ${p}`);
    codes.push(viaInterpreter(prog(p), inside).code);
  }
  assert.ok(codes.filter((c) => c === 'R507').length >= 5, 'paths that leave the folder stop with R507');
  // 渡していないときは R509（遊べるページと同じ）
  assert.equal(viaWasm(prog('a.txt')).code, 'R509');
  assert.equal(viaInterpreter(prog('a.txt')).code, 'R509');
});

test('a program that reads files imports only the five reading functions, and asks only for the read right', () => {
  const b = buildSource(readFileSync(new URL('../examples/read_file.ak', import.meta.url), 'utf8'));
  const imports = WebAssembly.Module.imports(new WebAssembly.Module(b.bytes)).map((x) => x.name);
  assert.deepEqual(imports, ['fd_write', 'proc_exit', 'fd_prestat_get', 'path_open', 'fd_filestat_get', 'fd_read', 'fd_close']);
});

// 自分の受け皿（src/host.js）だけでなく、ほかの WASI の実装（Node の node:wasi。中身は uvwasi）でも同じに動くか。
// 受け皿がゆるすぎて、本物の WASI では動かない（権利が足りない など）ことを見逃さないため
test('compiled file reading also works on another WASI implementation (node:wasi)', async () => {
  const { WASI } = await import('node:wasi');
  const { openSync, closeSync } = await import('node:fs');
  const dir = mkdtempSync(join(tmpdir(), 'akashi-wasi-'));
  const outPath = join(dir, 'out.txt');
  const files = fileURLToPath(new URL('../examples/files', import.meta.url));
  const src = readFileSync(new URL('../examples/read_file.ak', import.meta.url), 'utf8');
  const fd = openSync(outPath, 'w');
  const wasi = new WASI({ version: 'preview1', args: [], env: {}, preopens: { '.': files }, stdout: fd, returnOnExit: true });
  const instance = await WebAssembly.instantiate(new WebAssembly.Module(buildSource(src).bytes), wasi.getImportObject());
  const exit = wasi.start(instance);
  closeSync(fd);
  assert.equal(exit, 0);
  assert.equal(readFileSync(outPath, 'utf8'), viaInterpreter(src, files).out);
});
