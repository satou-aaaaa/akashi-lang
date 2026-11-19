// 使う道具の決まり（docs/security.md）：依存はゼロ、Node は保守中の版、処理系は Node の標準の部品だけを使う
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { isBuiltin } from 'node:module';

const root = new URL('../', import.meta.url);
const read = (p) => readFileSync(new URL(p, root), 'utf8');

test('package.json has no dependencies of any kind', () => {
  const pkg = JSON.parse(read('package.json'));
  for (const k of ['dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies', 'bundleDependencies', 'bundledDependencies']) {
    assert.ok(!pkg[k] || Object.keys(pkg[k]).length === 0, `${k} must stay empty (docs/security.md)`);
  }
  assert.ok(!existsSync(new URL('node_modules/', root)) || readdirSync(new URL('node_modules/', root)).length === 0, 'node_modules must be empty');
});

test('source files import only Node built-ins and our own files', () => {
  for (const dir of ['src/', 'bin/', 'scripts/', 'test/']) {
    for (const f of readdirSync(new URL(dir, root)).filter((x) => /\.(m?js)$/.test(x))) {
      const text = read(dir + f);
      for (const [, spec] of text.matchAll(/(?:^|\n)\s*import\s[^'"]*['"]([^'"]+)['"]|import\(\s*['"]([^'"]+)['"]\s*\)/g)) {
        if (!spec) continue;
        assert.ok(spec.startsWith('.') || isBuiltin(spec), `${dir}${f} imports '${spec}', which is not a Node built-in`);
      }
    }
  }
});

test('the Node version in .nvmrc is a maintained LTS line (22 or later)', () => {
  const major = Number(read('.nvmrc').trim().replace(/^v/, '').split('.')[0]);
  assert.ok(major >= 22 && major % 2 === 0, `.nvmrc must name an even (LTS) major >= 22, got ${major}`);
  assert.ok(Number(process.versions.node.split('.')[0]) >= 22, 'tests must run on Node 22 or later');
});
