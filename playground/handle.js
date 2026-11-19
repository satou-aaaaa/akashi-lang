// 遊べるページの仕事（ブラウザの Worker の中で動く。Node のテストからも呼ぶ）。
// 外とは何も通信しない。Folder の鍵は渡さない（ページからファイルは読めない）。
import { checkSource, runSource, buildSource, format } from '../src/core.js';
import { runWasm } from '../src/host.js';

export function handle({ action, src }) {
  switch (action) {
    case 'check': {
      const r = checkSource(src);
      return { ok: r.ok, diagnostics: r.diagnostics, summary: r.ok ? `ok: ${r.examples.passed}/${r.examples.total} examples passed, ${r.generated} generated inputs kept every ensures` : '' };
    }
    case 'run': {
      const r = runSource(src);
      return { ok: r.ok, diagnostics: r.diagnostics, output: r.output };
    }
    case 'wasm': {
      const b = buildSource(src);
      if (!b.ok) return { ok: false, diagnostics: b.diagnostics, output: '' };
      let output = '';
      let errors = '';
      const exit = runWasm(b.bytes, { stdout: (s) => { output += s; }, stderr: (s) => { errors += s; } });
      return { ok: exit === 0, diagnostics: [], output, errors, bytes: b.bytes.length };
    }
    case 'fmt': {
      const r = format(src);
      return r.ok ? { ok: true, text: r.text, diagnostics: [] } : { ok: false, diagnostics: [r.error] };
    }
    default:
      return { ok: false, diagnostics: [], output: `unknown action ${action}` };
  }
}
