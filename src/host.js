// コンパイルした WebAssembly を動かす小さな受け皿。WASI preview1 のうち fd_write（画面と標準エラー）と proc_exit だけを渡す。
// ファイル・時計・乱数・通信などは渡さないので、プログラムはそれらに触れない（鍵の考えと同じ）。
// ブラウザ（遊べるページ）でも Node でも同じものを使う。wasmtime など本物の WASI でも、同じ .wasm がそのまま動く。
class Exit extends Error {
  constructor(code) { super(`exit ${code}`); this.code = code; }
}

export function runWasm(bytes, { stdout = () => {}, stderr = () => {} } = {}) {
  let memory;
  const decoder = new TextDecoder();
  const wasi = {
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
