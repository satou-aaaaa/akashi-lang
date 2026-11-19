// CLI の終了コードと --json の形（AI のつなぎ口なので変えない）
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

const cli = (...args) => spawnSync(process.execPath, ['bin/akashi.js', ...args], { encoding: 'utf8' });

test('check ok exits 0 and counts examples', () => {
  const r = cli('check', 'examples/gcd.ak');
  assert.equal(r.status, 0);
  assert.match(r.stdout, /ok: 2\/2 examples passed/);
});

test('run prints the program output', () => {
  const r = cli('run', 'examples/hello.ak');
  assert.equal(r.status, 0);
  assert.equal(r.stdout, 'hello, akashi\n');
});

test('--json gives code, position and fix, and exits 1 on error', () => {
  const r = cli('check', 'examples/bad/e206-positional.ak', '--json');
  assert.equal(r.status, 1);
  const j = JSON.parse(r.stdout);
  assert.equal(j.ok, false);
  assert.deepEqual(Object.keys(j.diagnostics[0]).sort(), ['code', 'col', 'fix', 'kind', 'line', 'message']);
  assert.equal(j.diagnostics[0].code, 'E206');
});

test('explain names the error', () => {
  const r = cli('explain', 'E207');
  assert.equal(r.status, 0);
  assert.match(r.stdout, /arguments out of order/);
});

test('spec prints the short spec for prompts', () => {
  const r = cli('spec');
  assert.equal(r.status, 0);
  assert.match(r.stdout, /^# Akashi language spec/);
});
