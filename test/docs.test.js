// 説明書きの中の ```akashi のコードは、全部 check に通ること（説明書きが古くなったら落ちる）。
// 通らない書き方を見せたいときは ```text にする。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { checkSource } from '../src/index.js';

const root = new URL('../', import.meta.url);
const files = ['README.md', ...readdirSync(new URL('docs/', root)).filter((f) => f.endsWith('.md')).map((f) => `docs/${f}`)];

for (const file of files) {
  const md = readFileSync(new URL(file, root), 'utf8');
  const blocks = [...md.matchAll(/^```akashi\n([\s\S]*?)^```$/gm)].map((m) => m[1]);
  blocks.forEach((src, i) => {
    test(`${file} code block ${i + 1} passes check`, () => {
      const c = checkSource(src);
      assert.deepEqual(c.diagnostics.map((d) => `${d.code} ${d.message}`), [], src);
    });
  });
}

test('links between docs point to files that exist', () => {
  for (const file of [...files, 'llms.txt']) {
    const md = readFileSync(new URL(file, root), 'utf8');
    const base = new URL(file, root);
    for (const [, target] of md.matchAll(/\]\(([^)#\s]+)(?:#[^)]*)?\)/g)) {
      if (/^https?:/.test(target)) continue;
      assert.ok(existsSync(new URL(target, base)), `${file} links to missing ${target}`);
    }
  }
});

test('the tutorial, how-to, reference and explanation documents all exist (Diátaxis)', () => {
  for (const f of ['docs/tutorial.md', 'docs/howto.md', 'docs/reference.md', 'docs/security.md', 'docs/DESIGN.md', 'docs/SPEC.md', 'docs/ERRORS.md', 'llms.txt']) {
    assert.ok(existsSync(new URL(f, root)), f);
  }
});
