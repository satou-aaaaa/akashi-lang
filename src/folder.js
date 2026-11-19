// Folder の鍵の中身（Node だけ）。渡されたフォルダの中のファイルだけを読む。
// 外を指すリンクは本当の場所（realpath）で確かめて止める。無い・フォルダ・UTF-8 でないものは「読めない」として返す（Err になる）。
// インタプリタは read（文字で返す）を、コンパイルした .wasm の受け皿（src/host.js）は readBytes（バイトで返す）を使う。どちらも同じ確かめ方をする。
import { realpathSync, readFileSync, statSync } from 'node:fs';
import { resolve, sep } from 'node:path';

export function openFolder(dir) {
  const root = realpathSync(dir);
  // { bytes } か { missing, why: 'noent' | 'isdir' | 'io' } か { escape }
  const readBytes = (path) => {
    let real;
    try {
      real = realpathSync(resolve(root, path));
    } catch {
      return { missing: `'${path}' does not exist`, why: 'noent' };
    }
    if (real !== root && !real.startsWith(root + sep)) return { escape: true };
    if (!statSync(real).isFile()) return { missing: `'${path}' is not a file`, why: 'isdir' };
    try {
      return { bytes: readFileSync(real) };
    } catch {
      return { missing: `'${path}' could not be read as UTF-8 text`, why: 'io' };
    }
  };
  return {
    cap: 'Folder',
    root,
    readBytes,
    read(path) {
      const r = readBytes(path);
      if (!r.bytes) return r;
      try {
        return { text: new TextDecoder('utf-8', { fatal: true }).decode(r.bytes) };
      } catch {
        return { missing: `'${path}' could not be read as UTF-8 text` };
      }
    },
  };
}
