// Folder の鍵の中身（Node だけ）。渡されたフォルダの中のファイルだけを読む。
// 外を指すリンクは本当の場所（realpath）で確かめて止める。無い・フォルダ・UTF-8 でないものは「読めない」として返す（Err になる）。
import { realpathSync, readFileSync, statSync } from 'node:fs';
import { resolve, sep } from 'node:path';

export function openFolder(dir) {
  const root = realpathSync(dir);
  return {
    cap: 'Folder',
    root,
    read(path) {
      let real;
      try {
        real = realpathSync(resolve(root, path));
      } catch {
        return { missing: `'${path}' does not exist` };
      }
      if (real !== root && !real.startsWith(root + sep)) return { escape: true };
      if (!statSync(real).isFile()) return { missing: `'${path}' is not a file` };
      try {
        return { text: new TextDecoder('utf-8', { fatal: true }).decode(readFileSync(real)) };
      } catch {
        return { missing: `'${path}' could not be read as UTF-8 text` };
      }
    },
  };
}
