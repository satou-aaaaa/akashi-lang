// まとめの入口（Node の部品を使わない。ブラウザでもこのまま動く）。check（静的検査＋example）と run（main を実行）と build（WebAssembly）。
// Node から使うときは src/index.js（Folder にフォルダの名前を渡せる）。
import { AkashiError, diag } from './errors.js';
import { parseProgram } from './modules.js';
import { check } from './check.js';
import { Machine } from './run.js';
import { fuzz } from './fuzz.js';
import { compile } from './wasm.js';

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
// load(パス)：use で読むファイルの中身を返す（無ければ null）。main のファイルのフォルダからの相対パスで呼ばれる
export function analyze(src, { load } = {}) {
  const p = catchAkashi(() => parseProgram(src, { load }));
  if (p.error) return { ok: false, diagnostics: [p.error] };
  const diagnostics = check(p.value);
  return { ok: diagnostics.length === 0, diagnostics, program: p.value };
}

// 検査＋全部の example を回す。{ ok, diagnostics, examples: { passed, total } }
export function checkSource(src, { load } = {}) {
  const a = analyze(src, { load });
  if (!a.ok) return { ok: false, diagnostics: a.diagnostics, examples: { passed: 0, total: 0 }, generated: 0 };
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
  // example が通ったら、自動で作った入力でも ensures が守られるかを試す
  const fz = diagnostics.length === 0 ? fuzz(a.program) : { diagnostics: [], checked: 0 };
  diagnostics.push(...fz.diagnostics);
  return { ok: diagnostics.length === 0, diagnostics, examples: { passed, total }, generated: fz.checked };
}

// 検査（example も）が通ったら main を動かす。{ ok, diagnostics, output }
// grants.folder：main が Folder を求めたときに渡す鍵（src/folder.js の openFolder で作る）。無ければ渡さない
export function runSource(src, { out, grants = {}, load } = {}) {
  const c = checkSource(src, { load });
  if (!c.ok) return { ok: false, diagnostics: c.diagnostics, output: '' };
  const a = analyze(src, { load });
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
      args[p.name] = grants.folder;
    }
    if (p.type.k === 'OutFolder') {
      if (!grants.outFolder) {
        return { ok: false, diagnostics: [diag('R509', `main asks for an OutFolder ('${p.name}') but none was granted`, p.pos, 'run with --allow-write <folder> to let this program write files in that folder (and nowhere else)')], output: '' };
      }
      args[p.name] = grants.outFolder;
    }
  }
  let output = '';
  const m = new Machine(a.program, (s) => { output += s; if (out) out(s); });
  const r = catchAkashi(() => m.callFn('main', args, main.pos));
  return r.error ? { ok: false, diagnostics: [r.error], output } : { ok: true, diagnostics: [], output };
}

// 検査（example・自動の試しも）が通ったら WebAssembly にする。{ ok, diagnostics, bytes }
export function buildSource(src, { load } = {}) {
  const c = checkSource(src, { load });
  if (!c.ok) return { ok: false, diagnostics: c.diagnostics };
  const a = analyze(src, { load }); // 型を節に残した木（compile が使う）
  return compile(a.program);
}

export { CODES, RETIRED, formatDiag } from './errors.js';
export { format } from './fmt.js';
