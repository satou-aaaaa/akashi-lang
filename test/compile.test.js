// コンパイラ（src/wasm.js）の答えが、インタプリタ（意味の正）と同じかを比べる。
// 比べるもの：画面への出力・終わりのコード・実行時のエラー番号。
// 見本：examples/*.ak のうちコンパイルできるもの、test/compile/*.ak、自動で作った式。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, mkdtempSync, writeFileSync, symlinkSync, mkdirSync, cpSync, lstatSync, readlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runSource, buildSource, analyze, CODES } from '../src/index.js';
import { runWasm } from '../src/host.js';
import { openFolder, openOutFolder } from '../src/folder.js';

function viaInterpreter(src, folder, outFolder, file) {
  const r = runSource(src, { grants: { folder, outFolder }, file });
  return { out: r.output, exit: r.ok ? 0 : 1, code: r.ok ? null : r.diagnostics[0].code };
}

function viaWasm(src, folder, outFolder, file) {
  const b = buildSource(src, { file });
  if (!b.ok) return { unsupported: b.diagnostics[0] };
  assert.ok(WebAssembly.validate(b.bytes), 'the module is valid WebAssembly');
  let out = '';
  let err = '';
  const exit = runWasm(b.bytes, { stdout: (s) => { out += s; }, stderr: (s) => { err += s; }, folder: folder ? openFolder(folder) : undefined, outFolder: outFolder ? openOutFolder(outFolder) : undefined });
  return { out, exit, code: err.match(/\b([ER]\d{3})\b/)?.[1] ?? null, err };
}

const same = (src, label, folder, file) => {
  const w = viaWasm(src, folder, undefined, file);
  if (w.unsupported) return false;
  const i = viaInterpreter(src, folder, undefined, file);
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
      if (same(src, f, grant && fileURLToPath(new URL(`../${grant}`, import.meta.url)), fileURLToPath(new URL(f, dir)))) compiled++;
      else assert.fail(`${f} must be supported by the compiler (examples and test/compile)`);
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
  symlinkSync(root, join(inside, 'up'));
  symlinkSync(join(inside, 'sub'), join(inside, 'sub-link'));
  const prog = (path) => `fn main(console: Console, folder: Folder) -> Unit do
  match read_text(from: folder, path: "${path}")
    case Ok(value: t) then print(to: console, value: if str_len(text: t) > 50 then to_str(value: str_len(text: t)) else t end)
    case Err(message: m) then print(to: console, value: "Err " ++ m)
  end
end`;
  const paths = ['a.txt', 'sub/b.txt', 'bom.txt', 'bad.txt', 'surrogate.txt', 'big.txt', 'nothing.txt', 'sub', 'ok-link.txt', 'link.txt', 'up/secret.txt', 'sub-link/b.txt',
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
  assert.deepEqual(imports, ['fd_write', 'proc_exit', 'fd_prestat_get', 'fd_prestat_dir_name', 'path_filestat_get', 'path_open', 'fd_filestat_get', 'fd_read', 'fd_close']);
});

test('a program that only writes files does not import the reading functions', () => {
  const b = buildSource('fn main(out: OutFolder) -> Unit do\n  let r: Result[Unit] = write_text(to: out, path: "a.txt", text: "x")\n  ()\nend\n');
  assert.ok(b.ok, JSON.stringify(b.diagnostics));
  const imports = WebAssembly.Module.imports(new WebAssembly.Module(b.bytes)).map((x) => x.name);
  assert.deepEqual(imports, ['fd_write', 'proc_exit', 'fd_prestat_get', 'fd_prestat_dir_name', 'path_filestat_get', 'path_open', 'fd_close']);
});

// フォルダの中身を { 名前: 中身 or '-> リンク先' or '/' } にする（書いた結果を比べるため）
function tree(dir, base = '') {
  const out = {};
  for (const f of readdirSync(dir).sort()) {
    const p = join(dir, f);
    const st = lstatSync(p);
    if (st.isSymbolicLink()) out[base + f] = `-> ${readlinkSync(p)}`;
    else if (st.isDirectory()) { out[`${base + f}/`] = '/'; Object.assign(out, tree(p, `${base + f}/`)); }
    else out[base + f] = readFileSync(p, 'utf8');
  }
  return out;
}

test('writing files agrees with the interpreter, including links in and out, folders and bad paths', () => {
  const base = mkdtempSync(join(tmpdir(), 'akashi-w-'));
  const make = (name) => {
    const root = join(base, name);
    const inside = join(root, 'out');
    mkdirSync(join(inside, 'sub'), { recursive: true });
    writeFileSync(join(root, 'secret.txt'), 'secret');
    writeFileSync(join(inside, 'old.txt'), 'old text that is longer');
    symlinkSync(join(root, 'secret.txt'), join(inside, 'link.txt'));
    symlinkSync(join(inside, 'old.txt'), join(inside, 'in-link.txt'));
    symlinkSync(root, join(inside, 'up'));
    symlinkSync(join(inside, 'sub'), join(inside, 'sub-link'));
    symlinkSync(join(inside, 'none.txt'), join(inside, 'dangling.txt'));
    return { root, inside };
  };
  const prog = (path) => `fn main(console: Console, out: OutFolder) -> Unit do
  print(to: console, value: write_text(to: out, path: "${path}", text: "new é😀\\n"))
end`;
  const paths = ['a.txt', 'sub/b.txt', 'old.txt', 'sub', 'nope/c.txt', 'old.txt/x', 'link.txt', 'in-link.txt', 'dangling.txt', 'up/secret.txt', 'sub-link/c.txt',
    '../secret.txt', 'sub/../a.txt', '/tmp/x', 'C:x', '', 'a\\\\b', './a.txt', 'sub//b.txt', 'sub/', '.', 'x..'];
  const codes = [];
  paths.forEach((p, k) => {
    const a = make(`i${k}`);
    const b = make(`w${k}`);
    const i = viaInterpreter(prog(p), undefined, a.inside);
    const w = viaWasm(prog(p), undefined, b.inside);
    assert.ok(!w.unsupported, `not compiled: ${p}`);
    assert.deepEqual({ out: w.out, exit: w.exit, code: w.code }, i, `${p}\n${w.err}`);
    // 書いた結果も同じ（リンクの先・外のファイルは変わらない）
    const fix = (t, root) => JSON.parse(JSON.stringify(t).replaceAll(root, '<root>'));
    assert.deepEqual(fix(tree(b.root), b.root), fix(tree(a.root), a.root), p);
    assert.equal(readFileSync(join(a.root, 'secret.txt'), 'utf8'), 'secret', `${p} must not touch files outside`);
    codes.push(i.code);
  });
  assert.ok(codes.filter((c) => c === 'R507').length >= 10, 'paths that leave the folder or follow links stop with R507');
  assert.equal(viaWasm(prog('a.txt')).code, 'R509');
  assert.equal(viaInterpreter(prog('a.txt')).code, 'R509');
});

test('write_bytes writes exactly the bytes, and stops on a byte outside 0..255 before touching the file', () => {
  const base = mkdtempSync(join(tmpdir(), 'akashi-wb-'));
  const prog = (path, bytes) => `fn main(console: Console, out: OutFolder) -> Unit do
  print(to: console, value: write_bytes(to: out, path: "${path}", bytes: ${bytes}))
end`;
  const cases = [['a.bin', '[0, 97, 255, 10, 128]'], ['a.bin', '[]'], ['a.bin', 'range(from: 0, to: 256)'], ['a.bin', '[1, 256]'], ['a.bin', '[-1]'], ['../x.bin', '[1]'], ['../x.bin', '[300]'], ['nope/a.bin', '[1]']];
  cases.forEach(([p, bytes], k) => {
    const a = join(base, `i${k}`);
    const b = join(base, `w${k}`);
    mkdirSync(a);
    mkdirSync(b);
    const i = viaInterpreter(prog(p, bytes), undefined, a);
    const w = viaWasm(prog(p, bytes), undefined, b);
    assert.deepEqual({ out: w.out, exit: w.exit, code: w.code }, i, `${p} ${bytes}\n${w.err}`);
    assert.deepEqual(tree(b), tree(a), `${p} ${bytes}`);
  });
  const c = join(base, 'check');
  mkdirSync(c);
  viaWasm(prog('a.bin', '[0, 97, 255, 10, 128]'), undefined, c);
  assert.deepEqual([...readFileSync(join(c, 'a.bin'))], [0, 97, 255, 10, 128]);
});

test('a program can read one folder and write another, and the names decide which is which', () => {
  const root = mkdtempSync(join(tmpdir(), 'akashi-rw-'));
  mkdirSync(join(root, 'in'));
  mkdirSync(join(root, 'out'));
  writeFileSync(join(root, 'in', 'a.txt'), 'abc');
  const src = `fn main(console: Console, out: OutFolder, folder: Folder) -> Unit do
  match read_text(from: folder, path: "a.txt")
    case Ok(value: t) then print(to: console, value: write_text(to: out, path: "b.txt", text: t ++ t))
    case Err(message: m) then print(to: console, value: m)
  end
end`;
  const w = viaWasm(src, join(root, 'in'), join(root, 'out'));
  assert.equal(w.out, 'Ok(value: ())\n', w.err);
  assert.equal(readFileSync(join(root, 'out', 'b.txt'), 'utf8'), 'abcabc');
  assert.equal(viaWasm(src, join(root, 'in')).code, 'R509');
  assert.equal(viaWasm(src, undefined, join(root, 'out')).code, 'R509');
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
  const wasi = new WASI({ version: 'preview1', args: [], env: {}, preopens: { read: files }, stdout: fd, returnOnExit: true });
  const instance = await WebAssembly.instantiate(new WebAssembly.Module(buildSource(src).bytes), wasi.getImportObject());
  const exit = wasi.start(instance);
  closeSync(fd);
  assert.equal(exit, 0);
  assert.equal(readFileSync(outPath, 'utf8'), viaInterpreter(src, files).out);
});

test('compiled file writing also works on another WASI implementation (node:wasi), and does not follow links', async () => {
  const { WASI } = await import('node:wasi');
  const { openSync, closeSync } = await import('node:fs');
  const root = mkdtempSync(join(tmpdir(), 'akashi-wasi-w-'));
  const inside = join(root, 'out');
  mkdirSync(join(inside, 'sub'), { recursive: true });
  writeFileSync(join(root, 'secret.txt'), 'secret');
  symlinkSync(join(root, 'secret.txt'), join(inside, 'link.txt'));
  const run = async (path) => {
    const src = `fn main(console: Console, out: OutFolder) -> Unit do\n  print(to: console, value: write_text(to: out, path: "${path}", text: "hi😀"))\nend\n`;
    const outPath = join(root, 'stdout.txt');
    const fd = openSync(outPath, 'w');
    const wasi = new WASI({ version: 'preview1', args: [], env: {}, preopens: { write: inside }, stdout: fd, stderr: fd, returnOnExit: true });
    const instance = await WebAssembly.instantiate(new WebAssembly.Module(buildSource(src).bytes), wasi.getImportObject());
    const exit = wasi.start(instance);
    closeSync(fd);
    return { exit, out: readFileSync(outPath, 'utf8') };
  };
  assert.deepEqual(await run('sub/a.txt'), { exit: 0, out: 'Ok(value: ())\n' });
  assert.equal(readFileSync(join(inside, 'sub', 'a.txt'), 'utf8'), 'hi😀');
  // リンクの先が中でも外でも、段のどこにあっても止める（node:wasi は段の途中のリンクを外までたどるので、プログラム自身が確かめる）
  symlinkSync(root, join(inside, 'up'));
  for (const p of ['up/secret.txt', 'link.txt']) {
    const r = await run(p);
    assert.equal(r.exit, 1, p);
    assert.match(r.out, /R507/, p);
  }
  assert.equal(readFileSync(join(root, 'secret.txt'), 'utf8'), 'secret');
  assert.deepEqual(await run('nope/a.txt'), { exit: 0, out: `Err(message: "the folder of 'nope/a.txt' does not exist")\n` });
});

test('compiled reading does not follow links even on a WASI host that would (node:wasi)', async () => {
  const { WASI } = await import('node:wasi');
  const { openSync, closeSync } = await import('node:fs');
  const root = mkdtempSync(join(tmpdir(), 'akashi-wasi-r-'));
  const inside = join(root, 'in');
  mkdirSync(inside);
  writeFileSync(join(root, 'secret.txt'), 'secret');
  writeFileSync(join(inside, 'a.txt'), 'a');
  symlinkSync(root, join(inside, 'up'));
  symlinkSync(join(root, 'secret.txt'), join(inside, 'link.txt'));
  for (const [p, want] of [['up/secret.txt', 1], ['link.txt', 1], ['a.txt', 0]]) {
    const src = `fn main(console: Console, folder: Folder) -> Unit do\n  print(to: console, value: read_text(from: folder, path: "${p}"))\nend\n`;
    const outPath = join(root, 'stdout.txt');
    const fd = openSync(outPath, 'w');
    const wasi = new WASI({ version: 'preview1', args: [], env: {}, preopens: { read: inside }, stdout: fd, stderr: fd, returnOnExit: true });
    const instance = await WebAssembly.instantiate(new WebAssembly.Module(buildSource(src).bytes), wasi.getImportObject());
    const exit = wasi.start(instance);
    closeSync(fd);
    assert.equal(exit, want, p);
    assert.doesNotMatch(readFileSync(outPath, 'utf8'), /secret/, p);
  }
});

// 2026-11-19：join・リストの表示が concat のくり返しで、長さの2乗の時間とメモリだった（大きな木の表示で 4GB を超え、場所があふれて壊れた）。
// 長いものでも1回でつなぐこと、concat が同じ答えを出すことを、インタプリタと比べて確かめる
test('join, showing long lists and concat take linear time and memory, and agree with the interpreter', () => {
  const src = `fn piece(i: Int) -> Str
  ensures str_len(text: result) > 0
  example piece(i: 3) == "item 3"
do
  "item " ++ to_str(value: i)
end

fn twice(i: Int) -> List[Int]
  ensures len(list: result) == 2
  example twice(i: 1) == [1, 1]
do
  [i, i]
end

fn main(console: Console) -> Unit
do
  let xs: List[Int] = range(from: 0, to: 200000)
  print(to: console, value: str_len(text: to_str(value: xs)))
  print(to: console, value: str_len(text: join(parts: map(list: xs, func: piece), by: ", ")))
  print(to: console, value: str_len(text: to_str(value: dict(keys: map(list: range(from: 0, to: 20000), func: piece), values: range(from: 0, to: 20000)))))
  let ys: List[Int] = concat(lists: map(list: xs, func: twice))
  print(to: console, value: [len(list: ys), get(list: ys, index: 399999), sum(list: ys)])
  print(to: console, value: concat(lists: [[1], [], [2, 3]]))
  print(to: console, value: join(parts: [], by: ", ") == "")
end
`;
  const t0 = Date.now();
  assert.ok(same(src, 'long lists'));
  assert.ok(Date.now() - t0 < 20000, `took ${Date.now() - t0} ms`);
});

// 大きすぎる値は、前に作った値を壊さずに R513 で止まる（前は場所があふれて、メモリの外を書く失敗か、黙って上書きした）
test('a compiled program that runs out of memory stops with R513 instead of overwriting memory', () => {
  const big = 'x'.repeat(1200);
  const src = `fn piece(i: Int) -> Str
  ensures true
  example str_len(text: piece(i: 0)) == 1200
do
  "${big}"
end

fn main(console: Console) -> Unit
do
  print(to: console, value: str_len(text: join(parts: map(list: range(from: 0, to: 1000000), func: piece), by: "")))
end
`;
  const w = viaWasm(src);
  assert.equal(w.exit, 1, w.err);
  assert.equal(w.code, 'R513');
  assert.match(w.err, /out of memory/);
});
