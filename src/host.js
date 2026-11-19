// コンパイルした WebAssembly を動かす小さな受け皿。WASI preview1 のうち fd_write（画面と標準エラー）と proc_exit を渡す。
// folder（src/folder.js の読む鍵）を渡したときだけ「read」、outFolder（書く鍵）を渡したときだけ「write」という名前のフォルダを
// fd 3 から順に開け、fd_prestat_get・fd_prestat_dir_name・path_filestat_get・path_open・fd_filestat_get・fd_read・fd_write・fd_close が働く。
// 「read」は読むだけ、「write」は「作るか空にして書く」だけ（ほかの頼み方は ENOTCAPABLE）。消す・名前を変える・時計・乱数・通信は渡さない（鍵の考えと同じ）。
// ブラウザ（遊べるページ）でも Node でも同じものを使う。wasmtime など本物の WASI でも、同じ .wasm がそのまま動く。
class Exit extends Error {
  constructor(code) { super(`exit ${code}`); this.code = code; }
}

// WASI の errno（使う分だけ）
const E = { BADF: 8, IO: 29, ISDIR: 31, NOENT: 44, NOTCAPABLE: 76 };
const READ_RIGHTS = 2n | (1n << 21n); // fd_read と fd_filestat_get
const WRITE_RIGHTS = 1n << 6n; // fd_write
const CREAT_TRUNC = 1 | 8; // oflags：無ければ作る・あれば空にする

// stats を渡すと、終わったときのメモリの大きさ（バイト）を stats.memoryBytes に入れる（テストがメモリの使いすぎに気づくため）
export function runWasm(bytes, { stdout = () => {}, stderr = () => {}, folder, outFolder, stats } = {}) {
  let memory;
  const decoder = new TextDecoder();
  // 渡すフォルダ（fd 3 から）。名前で見分ける
  const dirs = [['read', folder], ['write', outFolder]].filter(([, x]) => x).map(([nm, x], i) => ({ fd: 3 + i, name: nm, dir: x }));
  const dirOf = (fd) => dirs.find((d) => d.fd === fd);
  const files = new Map(); // fd → 読む { bytes, at } ／ 書く { out, path, chunks }
  let nextFd = 3 + dirs.length;
  const wasi = {
    fd_prestat_get(fd, buf) {
      const d = dirOf(fd);
      if (!d) return E.BADF;
      const view = new DataView(memory.buffer);
      view.setUint8(buf, 0); // 種類：フォルダ
      view.setUint32(buf + 4, d.name.length, true); // 名前の長さ
      return 0;
    },
    fd_prestat_dir_name(fd, buf, len) {
      const d = dirOf(fd);
      if (!d) return E.BADF;
      new Uint8Array(memory.buffer, buf, Math.min(len, d.name.length)).set(new TextEncoder().encode(d.name).subarray(0, len));
      return 0;
    },
    // リンクをたどらずに種類を見る（コンパイルしたプログラムが、パスの段にリンクが無いかを確かめるのに使う）
    path_filestat_get(fd, flags, path, pathLen, buf) {
      const d = dirOf(fd);
      if (!d) return E.BADF;
      const name = decoder.decode(new Uint8Array(memory.buffer, path, pathLen));
      // フォルダの外は見せない（.. の段・/ で始まる・\ を含むものは断る）
      if (flags !== 0 || name.startsWith('/') || name.includes('\\') || name.split('/').includes('..')) return E.NOTCAPABLE;
      const k = d.dir.kind(name);
      if (!k) return E.NOENT;
      new Uint8Array(memory.buffer, buf, 64).fill(0);
      new DataView(memory.buffer).setUint8(buf + 16, { dir: 3, file: 4, link: 7 }[k] ?? 0);
      return 0;
    },
    path_open(fd, dirflags, path, pathLen, oflags, rightsBase, rightsInheriting, fdflags, opened) {
      const d = dirOf(fd);
      if (!d) return E.BADF;
      const name = decoder.decode(new Uint8Array(memory.buffer, path, pathLen));
      if (d.name === 'write') {
        // 書く：作るか空にする、書く権利だけ、リンクはたどらない、のときだけ
        if (oflags !== CREAT_TRUNC || dirflags !== 0 || fdflags !== 0 || (BigInt(rightsBase) & ~WRITE_RIGHTS) !== 0n || BigInt(rightsInheriting) !== 0n) return E.NOTCAPABLE;
        const w = d.dir.writeBytes(name, new Uint8Array(0));
        if (w.escape) return E.NOTCAPABLE;
        if (!w.ok) return { noent: E.NOENT, isdir: E.ISDIR }[w.why] ?? E.IO;
        const id = nextFd++;
        files.set(id, { out: d.dir, path: name, chunks: [] });
        new DataView(memory.buffer).setUint32(opened, id, true);
        return 0;
      }
      if (oflags !== 0 || fdflags !== 0 || (BigInt(rightsBase) & ~READ_RIGHTS) !== 0n || BigInt(rightsInheriting) !== 0n) return E.NOTCAPABLE;
      const r = d.dir.readBytes(name);
      if (r.escape) return E.NOTCAPABLE;
      if (!r.bytes) return { noent: E.NOENT, isdir: E.ISDIR }[r.why] ?? E.IO;
      const id = nextFd++;
      files.set(id, { bytes: r.bytes, at: 0 });
      new DataView(memory.buffer).setUint32(opened, id, true);
      return 0;
    },
    fd_filestat_get(fd, buf) {
      const f = files.get(fd);
      if (!f || !f.bytes) return E.BADF;
      new Uint8Array(memory.buffer, buf, 64).fill(0);
      const view = new DataView(memory.buffer);
      view.setUint8(buf + 16, 4); // ふつうのファイル
      view.setBigUint64(buf + 32, BigInt(f.bytes.length), true);
      return 0;
    },
    fd_read(fd, iovs, count, nread) {
      const f = files.get(fd);
      if (!f || !f.bytes) return E.BADF;
      const view = new DataView(memory.buffer);
      let total = 0;
      for (let i = 0; i < count; i++) {
        const ptr = view.getUint32(iovs + i * 8, true);
        const len = view.getUint32(iovs + i * 8 + 4, true);
        const part = f.bytes.subarray(f.at, f.at + len);
        new Uint8Array(memory.buffer, ptr, part.length).set(part);
        f.at += part.length;
        total += part.length;
      }
      view.setUint32(nread, total, true);
      return 0;
    },
    // 書いたファイルは、閉じるときにまとめて書く（開けたときに、作れるか・空にできるかは確かめてある）
    fd_close(fd) {
      const f = files.get(fd);
      if (!f) return E.BADF;
      files.delete(fd);
      if (f.chunks) {
        const all = new Uint8Array(f.chunks.reduce((n, c) => n + c.length, 0));
        let at = 0;
        for (const c of f.chunks) { all.set(c, at); at += c.length; }
        if (!f.out.writeBytes(f.path, all).ok) return E.IO;
      }
      return 0;
    },
    fd_write(fd, iovs, count, written) {
      const view = new DataView(memory.buffer);
      const f = files.get(fd);
      if (f) {
        if (!f.chunks) return E.BADF;
        let total = 0;
        for (let i = 0; i < count; i++) {
          const ptr = view.getUint32(iovs + i * 8, true);
          const len = view.getUint32(iovs + i * 8 + 4, true);
          f.chunks.push(new Uint8Array(memory.buffer, ptr, len).slice());
          total += len;
        }
        view.setUint32(written, total, true);
        return 0;
      }
      let text = '';
      let total = 0;
      for (let i = 0; i < count; i++) {
        const ptr = view.getUint32(iovs + i * 8, true);
        const len = view.getUint32(iovs + i * 8 + 4, true);
        text += decoder.decode(new Uint8Array(memory.buffer, ptr, len));
        total += len;
      }
      view.setUint32(written, total, true);
      if (fd === 1) stdout(text);
      else if (fd === 2) stderr(text);
      else return 8; // EBADF：ほかの出口は無い
      return 0;
    },
    proc_exit(code) { throw new Exit(code); },
  };
  const instance = new WebAssembly.Instance(new WebAssembly.Module(bytes), { wasi_snapshot_preview1: wasi });
  memory = instance.exports.memory;
  try {
    instance.exports._start();
    return 0;
  } catch (e) {
    if (e instanceof Exit) return e.code;
    throw e;
  } finally {
    if (stats) stats.memoryBytes = memory.buffer.byteLength;
  }
}
