// 複数のファイル（部品）。use "other.ak" で、ほかのファイルの関数と型を使えるようにする。
// 決まり：パスは use を書いたファイルからの相対パスで、.ak で終わり、main のファイルのフォルダの中だけ（.. ・/ で始まる・\\ は E113）。
// 読んだファイルの関数と型は、全部1つのプログラムにまとまる（名前は全部のファイルで1回だけ。重なりは E203）。
// 同じファイルを何度 use しても1回だけ読む（輪になっていてもよい）。main は main のファイルにだけ書ける（E115）。
// ファイルを読む方法（load）は呼ぶ側が渡す（Node は src/index.js、ブラウザでは無し）。ここは Node の部品を使わない。
import { AkashiError, diag } from './errors.js';
import { parse, scan } from './parse.js';

// 使う側のファイル（main のフォルダからの相対パス）と use のパスから、main のフォルダからの相対パスを作る。だめなら null
export function resolveUse(from, path) {
  if (!path.endsWith('.ak') || path.startsWith('/') || path.includes('\\') || path.includes('\0') || /^[A-Za-z]:/.test(path)) return null;
  const parts = [...from.split('/').slice(0, -1), ...path.split('/')];
  if (parts.some((p) => p === '..' || p === '')) return null;
  return parts.filter((p) => p !== '.').join('/');
}

// main のファイルの文字から、use をたどって全部のファイルを読み、1つのプログラムにする
export function parseProgram(src, { load } = {}) {
  const files = [{ name: '', src, scanned: scan(src) }];
  const seen = new Set(['']);
  for (let k = 0; k < files.length; k++) {
    const f = files[k];
    for (const u of f.scanned.uses) {
      const rel = resolveUse(f.name || 'main.ak', u.path);
      if (rel === null) {
        throw new AkashiError(diag('E113', `use path '${u.path}' is not allowed`, u.pos, 'write a relative path to an .ak file inside the folder of the main file, without .. (e.g. use "lib/text.ak")'));
      }
      if (seen.has(rel)) continue;
      const text = load ? load(rel) : null;
      if (typeof text !== 'string') {
        throw new AkashiError(diag('E114', `used file '${rel}' was not found`, u.pos, load ? `create ${rel} (in the folder of the main file), or fix the path; paths are relative to the file that has the use line` : 'use needs files; run the program from a file with akashi check/run/build (the playground has only one file)'));
      }
      seen.add(rel);
      files.push({ name: rel, src: text, scanned: scan(text, rel) });
    }
  }
  const allTypes = files.flatMap((f) => f.scanned.types);
  const program = { fns: [], types: [] };
  for (const f of files) {
    const p = parse(f.src, { file: f.name || undefined, otherTypes: allTypes });
    if (f.name) {
      const m = p.fns.find((x) => x.name === 'main');
      if (m) throw new AkashiError(diag('E115', `the used file '${f.name}' has a main function`, m.pos, 'only the file you run has main; move main there or rename this function'));
    }
    program.fns.push(...p.fns);
    program.types.push(...p.types);
  }
  return program;
}
