// examples/*.ak は通って期待どおり表示し、examples/bad/*.ak は1行目の「# expect: コード」のエラーを出す
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { checkSource, runSource } from '../src/index.js';

const dir = new URL('../examples/', import.meta.url);
// 「# grant: <フォルダ>」の行があれば、そのフォルダを Folder として渡す（CLI の --allow-read と同じ）
const grantOf = (src) => ({ folder: src.match(/^# grant: (.+)$/m)?.[1] });
const read = (name) => readFileSync(new URL(name, dir), 'utf8');

for (const f of readdirSync(dir).filter((x) => x.endsWith('.ak'))) {
  test(`good: ${f}`, () => {
    const src = read(f);
    const c = checkSource(src, { file: new URL(f, dir).pathname });
    assert.deepEqual(c.diagnostics, []);
    const r = runSource(src, { grants: grantOf(src), file: new URL(f, dir).pathname });
    assert.equal(r.ok, true, JSON.stringify(r.diagnostics));
    assert.equal(r.output, read(f.replace(/\.ak$/, '.out')));
  });
}

const badDir = new URL('bad/', dir);
for (const f of readdirSync(badDir).filter((x) => x.endsWith('.ak'))) {
  test(`bad: ${f}`, () => {
    const src = readFileSync(new URL(f, badDir), 'utf8');
    const want = src.match(/^# expect: (\w+)/)[1];
    const r = runSource(src, { grants: grantOf(src), file: new URL(f, badDir).pathname });
    assert.equal(r.ok, false);
    assert.equal(r.diagnostics[0].code, want, JSON.stringify(r.diagnostics, null, 2));
    for (const d of r.diagnostics) {
      assert.ok(d.fix && d.fix.length > 5, `${d.code} has a fix`);
      assert.ok(d.line > 0 && d.col > 0, `${d.code} has a position`);
    }
  });
}
