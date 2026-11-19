# AGENTS.md

AI（LLM）が書きやすく間違えにくい小さな言語 Akashi の試作（処理系は Node.js、依存なし）。言語の説明は docs/SPEC.md、エラーは docs/ERRORS.md。

## 準備

Node.js 22（`.nvmrc`）だけ。入れるものは無いので scripts/setup.sh も置かない。

## push する前の確認

```bash
npm test
```

## 決まり

- エラーのコード（E100 など）の意味は変えない。新しい誤りには新しいコードを足す（AI が覚えて直せるように）。
- コードを足したら `examples/bad/<コード>-<名前>.ak`（1行目に `# expect: <コード>`）を足し、`node scripts/gen-errors.mjs` で docs/ERRORS.md を作り直す（テストが見本の抜けと古さを落とす）。
- どの診断にも、位置と「次にどう書けば通るか」の fix を付ける（テストが見る）。
- 言語の決まりを変えたら docs/SPEC.md も同じ PR で直す。SPEC は AI に貼る文書なので短く保つ。
- 実行時の深さは JS の呼び出しの深さに合わせて 500 まで（src/run.js の MAX_DEPTH）。

## 共通のきまり

- PR の作り方・マージの仕方は satou-aaaaa/shared-workflows の `routines/pr.md`、全体のきまりは `routines/common.md` に従う。
- CI の部品は shared-workflows の共通部品を呼ぶ（検査は node-test.yml、秘密の検査は secret-scan.yml）。リポジトリ側の .github/workflows には呼び出しと設定値だけを書く。
- Claude 以外の AI・人が作業するときは、shared-workflows の `routines/tool-map.md` と `routines/without-claude.md` を読む。
