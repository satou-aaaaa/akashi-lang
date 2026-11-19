// まとめの入口。check（静的検査＋example）と run（main を実行）。
import { AkashiError, diag } from './errors.js';
import { parse } from './parse.js';
import { check } from './check.js';
import { realpathSync } from 'node:fs';
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
// grants.folder：main が Folder を求めたときに渡すフォルダ（CLI の --allow-read）。無ければ渡さない
export function runSource(src, { out, grants = {} } = {}) {
  const c = checkSource(src);
  if (!c.ok) return { ok: false, diagnostics: c.diagnostics, output: '' };
  const a = analyze(src);
  const main = a.program.fns.find((f) => f.name === 'main');
  if (!main) {
    return { ok: false, diagnostics: [diag('E301', 'there is no main function', { line: 1, col: 1 }, 'add: fn main(console: Console) -> Unit do ... end')], output: '' };
  }
  const args = {};
  for (const p of main.params) {
    if (p.type.k === 'Console') args[p.name] = { cap: 'Console' };
    if (p.type.k === 'Folder') {
      if (!grants.folder) {
        return { ok: false, diagnostics: [diag('R509', `main asks for a Folder ('${p.name}') but none was granted`, p.pos, 'run with --allow-read <folder> to let this program read files in that folder (and nowhere else)')], output: '' };
      }
      args[p.name] = { cap: 'Folder', root: realpathSync(grants.folder) };
    }
  }
  let output = '';
  const m = new Machine(a.program, (s) => { output += s; if (out) out(s); });
  const r = catchAkashi(() => m.callFn('main', args, main.pos));
  return r.error ? { ok: false, diagnostics: [r.error], output } : { ok: true, diagnostics: [], output };
}

export { CODES, RETIRED, formatDiag } from './errors.js';
