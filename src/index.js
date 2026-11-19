// まとめの入口。check（静的検査＋example）と run（main を実行）。
import { AkashiError, diag } from './errors.js';
import { parse } from './parse.js';
import { check } from './check.js';
import { Machine } from './run.js';

function catchAkashi(fn) {
  try {
    return { value: fn() };
  } catch (e) {
    if (e instanceof AkashiError) return { error: e.diag };
    if (e instanceof RangeError) return { error: diag('R505', 'recursion too deep', null, 'check that the recursion reaches its base case') };
    throw e;
  }
}

// 構文と型の検査だけ。{ ok, diagnostics, program }
export function analyze(src) {
  const p = catchAkashi(() => parse(src));
  if (p.error) return { ok: false, diagnostics: [p.error] };
  const diagnostics = check(p.value);
  return { ok: diagnostics.length === 0, diagnostics, program: p.value };
}

// 検査＋全部の example を回す。{ ok, diagnostics, examples: { passed, total } }
export function checkSource(src) {
  const a = analyze(src);
  if (!a.ok) return { ok: false, diagnostics: a.diagnostics, examples: { passed: 0, total: 0 } };
  const m = new Machine(a.program, () => {});
  const diagnostics = [];
  let passed = 0;
  let total = 0;
  for (const f of a.program.fns) {
    for (const ex of f.examples) {
      total++;
      const r = catchAkashi(() => m.example(f.name, ex));
      if (r.error) diagnostics.push(r.error);
      else passed++;
    }
  }
  return { ok: diagnostics.length === 0, diagnostics, examples: { passed, total } };
}

// 検査（example も）が通ったら main を動かす。{ ok, diagnostics, output }
export function runSource(src, { out } = {}) {
  const c = checkSource(src);
  if (!c.ok) return { ok: false, diagnostics: c.diagnostics, output: '' };
  const a = analyze(src);
  if (!a.program.fns.some((f) => f.name === 'main')) {
    return { ok: false, diagnostics: [diag('E301', 'there is no main function', { line: 1, col: 1 }, 'add: fn main() -> Unit effects io do ... end')], output: '' };
  }
  let output = '';
  const m = new Machine(a.program, (s) => { output += s; if (out) out(s); });
  const r = catchAkashi(() => m.callFn('main', {}, { line: 1, col: 1 }));
  return r.error ? { ok: false, diagnostics: [r.error], output } : { ok: true, diagnostics: [], output };
}

export { CODES, formatDiag } from './errors.js';
