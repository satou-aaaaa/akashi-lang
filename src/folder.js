// Folder の鍵の中身（Node だけ）。渡されたフォルダの中のファイルだけを読む。
// リンクはたどらない：パスのどの段にリンクがあっても止める（{ escape }）。念のため本当の場所（realpath）でも中かを確かめる。
// 無い・フォルダ・UTF-8 でないものは「読めない」として返す（Err になる）。
// インタプリタは read（文字で返す）を、コンパイルした .wasm の受け皿（src/host.js）は readBytes（バイトで返す）を使う。どちらも同じ確かめ方をする。
import { realpathSync, readFileSync, statSync, lstatSync, openSync, writeSync, closeSync, constants } from 'node:fs';
import { resolve, sep, dirname, basename, join } from 'node:path';

// パスの段を前から1つずつ見て、リンクがあれば true（無い段に来たら、そこで終わり）。
// コンパイルしたプログラムも同じ見方をする（path_filestat_get をリンクをたどらずに呼ぶ）。受け皿の sandbox だけに頼らないため
function linkOnTheWay(root, path) {
  const parts = path.split('/');
  for (let i = 1; i <= parts.length; i++) {
    let st;
    try { st = lstatSync(join(root, ...parts.slice(0, i))); } catch { return false; }
    if (st.isSymbolicLink()) return true;
  }
  return false;
}

// path_filestat_get（リンクをたどらない）の答え：'link' | 'dir' | 'file' | 'other' か、無ければ null
function kindOf(root, path) {
  let st;
  try { st = lstatSync(join(root, path)); } catch { return null; }
  return st.isSymbolicLink() ? 'link' : st.isDirectory() ? 'dir' : st.isFile() ? 'file' : 'other';
}

export function openFolder(dir) {
  const root = realpathSync(dir);
  // { bytes } か { missing, why: 'noent' | 'isdir' | 'io' } か { escape }
  const readBytes = (path) => {
    if (linkOnTheWay(root, path)) return { escape: true };
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
    kind: (path) => kindOf(root, path),
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

// OutFolder の鍵の中身（Node だけ）。渡されたフォルダの中にだけ書く。
// 読むときと同じく、パスのどの段にリンクがあっても止める。念のため親フォルダの本当の場所（realpath）でも中かを確かめ、O_NOFOLLOW で開ける。
// 書けたら { ok: true }、書けない（親が無い・フォルダ）なら { missing, why }、外を指すなら { escape }
export function openOutFolder(dir) {
  const root = realpathSync(dir);
  const writeBytes = (path, bytes) => {
    if (linkOnTheWay(root, path)) return { escape: true };
    const full = resolve(root, path);
    let parent;
    try {
      parent = realpathSync(dirname(full));
    } catch {
      return { missing: `the folder of '${path}' does not exist`, why: 'noent' };
    }
    if (parent !== root && !parent.startsWith(root + sep)) return { escape: true };
    const target = join(parent, basename(full));
    let st = null;
    try { st = lstatSync(target); } catch { /* まだ無い：作る */ }
    if (st && st.isSymbolicLink()) return { escape: true };
    if (st && !st.isFile()) return { missing: `'${path}' is not a file`, why: 'isdir' };
    let fd;
    try {
      fd = openSync(target, constants.O_WRONLY | constants.O_CREAT | constants.O_TRUNC | (constants.O_NOFOLLOW ?? 0), 0o644);
      let off = 0;
      while (off < bytes.length) off += writeSync(fd, bytes, off, bytes.length - off);
      return { ok: true };
    } catch {
      return { missing: `'${path}' could not be written`, why: 'io' };
    } finally {
      if (fd !== undefined) closeSync(fd);
    }
  };
  return {
    cap: 'OutFolder',
    root,
    writeBytes,
    kind: (path) => kindOf(root, path),
    write(path, text) { return writeBytes(path, Buffer.from(text, 'utf8')); },
  };
}
