// 重い計算で画面が止まらないように、検査と実行は Worker で行う（ページ側は時間切れで止められる）
import { handle } from './handle.js';

self.onmessage = (e) => {
  try {
    self.postMessage({ id: e.data.id, ...handle(e.data) });
  } catch (err) {
    self.postMessage({ id: e.data.id, ok: false, diagnostics: [], output: '', crash: String(err && err.message || err) });
  }
};
