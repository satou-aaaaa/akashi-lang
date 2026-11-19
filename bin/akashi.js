#!/usr/bin/env node
// 使い方: akashi check <file> [--json] / akashi run <file> [--json] [--allow-read <folder>] / akashi explain <code> / akashi spec
//         akashi build <file> [-o out.wasm] [--json] / akashi wasm <file.wasm>
// 権利は既定で画面（Console）だけ。ファイルを読むには --allow-read で読んでよいフォルダを1つ渡す
import { readFileSync, writeFileSync } from 'node:fs';
import { checkSource, runSource, buildSource, formatDiag, CODES } from '../src/index.js';
import { runWasm } from '../src/host.js';

const args = process.argv.slice(2);
const json = args.includes('--json');
const ai = args.indexOf('--allow-read');
const folder = ai >= 0 ? args[ai + 1] : undefined;
if (ai >= 0 && !folder) usage();
const oi = args.indexOf('-o');
const outFile = oi >= 0 ? args[oi + 1] : undefined;
if (oi >= 0 && !outFile) usage();
const skip = new Set([ai, ai + 1, oi, oi + 1].filter((i, k) => (k < 2 ? ai >= 0 : oi >= 0)));
const [cmd, file] = args.filter((a, i) => a !== '--json' && !skip.has(i));

function usage() {
  console.error('usage: akashi check <file.ak> [--json]\n       akashi run <file.ak> [--json] [--allow-read <folder>]\n       akashi build <file.ak> [-o out.wasm] [--json]   (compile to WebAssembly)\n       akashi wasm <file.wasm>   (run a compiled program; it can only print)\n       akashi explain <code>\n       akashi spec   (print the short spec to paste into an AI prompt)');
  process.exit(2);
}

// AI に貼る短い仕様をそのまま出す（初めて見る言語は、説明を文脈に入れると書けるようになるため。docs/DESIGN.md）
if (cmd === 'spec') {
  process.stdout.write(readFileSync(new URL('../docs/SPEC.md', import.meta.url), 'utf8'));
  process.exit(0);
}
if (cmd === 'explain') {
  const title = CODES[file];
  if (!title) usage();
  console.log(`${file}: ${title}\nsee docs/ERRORS.md#${file.toLowerCase()}`);
  process.exit(0);
}
// コンパイルした .wasm を動かす。渡すのは画面と標準エラーだけ
if (cmd === 'wasm') {
  if (!file) usage();
  process.exit(runWasm(readFileSync(file), { stdout: (s) => process.stdout.write(s), stderr: (s) => process.stderr.write(s) }));
}
if (cmd === 'build') {
  if (!file) usage();
  const res = buildSource(readFileSync(file, 'utf8'));
  const out = outFile ?? file.replace(/\.ak$/, '') + '.wasm';
  if (res.ok) writeFileSync(out, res.bytes);
  if (json) console.log(JSON.stringify({ ok: res.ok, diagnostics: res.diagnostics, file, output: res.ok ? out : null, bytes: res.ok ? res.bytes.length : 0 }, null, 2));
  else if (res.ok) console.log(`ok: wrote ${out} (${res.bytes.length} bytes)`);
  else for (const d of res.diagnostics) console.error(formatDiag(d, file));
  process.exit(res.ok ? 0 : 1);
}
if (!['check', 'run'].includes(cmd) || !file) usage();

const src = readFileSync(file, 'utf8');
const res = cmd === 'check'
  ? checkSource(src)
  : runSource(src, { out: json ? undefined : (s) => process.stdout.write(s), grants: { folder } });

if (json) {
  console.log(JSON.stringify({ ...res, file }, null, 2));
} else {
  for (const d of res.diagnostics) console.error(formatDiag(d, file));
  if (cmd === 'check' && res.ok) console.log(`ok: ${res.examples.passed}/${res.examples.total} examples passed, ${res.generated} generated inputs kept every ensures`);
}
process.exit(res.ok ? 0 : 1);
