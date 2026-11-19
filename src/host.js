// コンパイルした WebAssembly を動かす小さな受け皿。WASI preview1 のうち fd_write（画面と標準エラー）と proc_exit を渡す。
// folder（src/folder.js の鍵）を渡したときだけ、そのフォルダを fd 3 として開け、読むための5つ（fd_prestat_get・path_open・fd_filestat_get・fd_read・fd_close）が働く。
// 書く・作る・消すための権利は渡さない（path_open で読む以外を頼まれたら ENOTCAPABLE）。時計・乱数・通信は渡さない（鍵の考えと同じ）。
// ブラウザ（遊べるページ）でも Node でも同じものを使う。wasmtime など本物の WASI でも、同じ .wasm がそのまま動く。
class Exit extends Error {
  constructor(code) { super(`exit ${code}`); this.code = code; }
}

// WASI の errno（使う分だけ）
const E = { BADF: 8, IO: 29, ISDIR: 31, NOENT: 44, NOTCAPABLE: 76 };
const READ_RIGHTS = 2n | (1n << 21n); // fd_read と fd_filestat_get
const DIR_FD = 3;

export function runWasm(bytes, { stdout = () => {}, stderr = () => {}, folder } = {}) {
  let memory;
  const decoder = new TextDecoder();
  const files = new Map(); // fd → { bytes, at }
  let nextFd = DIR_FD + 1;
  const wasi = {
    fd_prestat_get(fd, buf) {
      if (fd !== DIR_FD || !folder) return E.BADF;
      const view = new DataView(memory.buffer);
      view.setUint8(buf, 0); // 種類：フォルダ
      view.setUint32(buf + 4, 1, true); // 名前の長さ（"."）
      return 0;
    },
    path_open(fd, dirflags, path, pathLen, oflags, rightsBase, rightsInheriting, fdflags, opened) {
      if (fd !== DIR_FD || !folder) return E.BADF;
      if (oflags !== 0 || fdflags !== 0 || (BigInt(rightsBase) & ~READ_RIGHTS) !== 0n || BigInt(rightsInheriting) !== 0n) return E.NOTCAPABLE;
      const r = folder.readBytes(decoder.decode(new Uint8Array(memory.buffer, path, pathLen)));
      if (r.escape) return E.NOTCAPABLE;
      if (!r.bytes) return { noent: E.NOENT, isdir: E.ISDIR }[r.why] ?? E.IO;
      const id = nextFd++;
      files.set(id, { bytes: r.bytes, at: 0 });
      new DataView(memory.buffer).setUint32(opened, id, true);
      return 0;
    },
    fd_filestat_get(fd, buf) {
      const f = files.get(fd);
      if (!f) return E.BADF;
      new Uint8Array(memory.buffer, buf, 64).fill(0);
      const view = new DataView(memory.buffer);
      view.setUint8(buf + 16, 4); // ふつうのファイル
      view.setBigUint64(buf + 32, BigInt(f.bytes.length), true);
      return 0;
    },
    fd_read(fd, iovs, count, nread) {
      const f = files.get(fd);
      if (!f) return E.BADF;
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
    fd_close(fd) { return files.delete(fd) ? 0 : E.BADF; },
    fd_write(fd, iovs, count, written) {
      const view = new DataView(memory.buffer);
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
  }
}
