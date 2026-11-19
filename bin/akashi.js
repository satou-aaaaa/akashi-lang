#!/usr/bin/env node
// 使い方: akashi check <file> [--json] / akashi run <file> [--json] [--allow-read <folder>] / akashi explain <code> / akashi spec
// 権利は既定で画面（Console）だけ。ファイルを読むには --allow-read で読んでよいフォルダを1つ渡す
import { readFileSync } from 'node:fs';
import { checkSource, runSource, formatDiag, CODES } from '../src/index.js';

const args = process.argv.slice(2);
const json = args.includes('--json');
const ai = args.indexOf('--allow-read');
const folder = ai >= 0 ? args[ai + 1] : undefined;
if (ai >= 0 && !folder) usage();
const [cmd, file] = args.filter((a, i) => a !== '--json' && (ai < 0 || (i !== ai && i !== ai + 1)));

function usage() {
  console.error('usage: akashi check <file.ak> [--json]\n       akashi run <file.ak> [--json] [--allow-read <folder>]\n       akashi explain <code>\n       akashi spec   (print the short spec to paste into an AI prompt)');
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
