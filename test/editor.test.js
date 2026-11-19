// エディタの色分け（editors/vscode）が、処理系の言葉とそろっているか
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { KEYWORDS, TYPE_NAMES, CAPABILITY_TYPES } from '../src/parse.js';

const dir = new URL('../editors/vscode/', import.meta.url);
const json = (p) => JSON.parse(readFileSync(new URL(p, dir), 'utf8'));

test('the extension files are valid JSON and point at each other', () => {
  const pkg = json('package.json');
  assert.equal(pkg.contributes.languages[0].extensions[0], '.ak');
  assert.ok(!pkg.dependencies && !pkg.devDependencies, 'no dependencies');
  json(pkg.contributes.languages[0].configuration);
  const g = json(pkg.contributes.grammars[0].path);
  assert.equal(g.scopeName, pkg.contributes.grammars[0].scopeName);
});

test('every keyword and built-in type of the language is highlighted', () => {
  const grammar = json('syntaxes/akashi.tmLanguage.json');
  const regexes = [];
  const walk = (o) => {
    for (const [k, v] of Object.entries(o)) {
      if ((k === 'match' || k === 'begin' || k === 'end') && typeof v === 'string') regexes.push(new RegExp(v)); // JavaScript の正規表現として読める
      else if (v && typeof v === 'object') walk(v);
    }
  };
  walk(grammar.repository);
  // 言葉そのものに、どれかの決まりが言葉の全体として当たる
  // fn・type・let は後ろの名前と組で色が付くので、名前を続けた形でも試す
  const hit = (word) => [` ${word} `, ` ${word} Name `].some((text) => regexes.some((r) => { const m = r.exec(text); return m && m[0].trim().split(/\s+/).includes(word); }));
  for (const k of KEYWORDS) assert.ok(hit(k), `keyword ${k} is not highlighted`);
  for (const t of [...TYPE_NAMES, ...CAPABILITY_TYPES]) assert.ok(hit(t), `type ${t} is not highlighted`);
});
