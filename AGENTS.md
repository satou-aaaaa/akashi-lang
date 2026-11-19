# AGENTS.md

AI（LLM）が書きやすく間違えにくい小さな言語 Akashi の試作（処理系は Node.js、依存なし）。説明書きの地図は README.md の「説明書き」。AI に貼る仕様は docs/SPEC.md、エラーは docs/ERRORS.md、設計の根拠は docs/DESIGN.md。

## 準備

Node.js 22（`.nvmrc`）だけ。入れるものは無いので scripts/setup.sh も置かない。

## push する前の確認

```bash
npm test
```

## 決まり

- 依存を足さない（package.json の依存の欄は空、import は Node の標準の部品と自分のファイルだけ。test/deps.test.js が見る）。理由と例外の手順は docs/security.md「使う道具の決まり」。
- コンパイラ（src/wasm.js）の意味の正はインタプリタ（src/run.js）。コンパイラで扱える書き方を足したら test/compile/ に境目の見本を足す（両方で同じ答えかをテストが比べる）。

- エラーのコード（E100 など）の意味は変えない。新しい誤りには新しいコードを足す（AI が覚えて直せるように）。
- コードを足したら `examples/bad/<コード>-<名前>.ak`（1行目に `# expect: <コード>`）を足し、`node scripts/gen-errors.mjs` で docs/ERRORS.md を作り直す（テストが見本の抜けと古さを落とす）。
- どの診断にも、位置と「次にどう書けば通るか」の fix を付ける（テストが見る）。
- 言語の決まりを変えたら、同じ PR で docs/SPEC.md（英語・AI に貼る・短く）と docs/reference.md（日本語・全部）を直す。入門（tutorial）・やり方集（howto）に影響があればそれも。
- 説明書きは Diátaxis の4種類（入門・やり方集・決まり・解説）に分けて置く。新しい文書もどれか1つに入れる。
- 説明書きの ```akashi のコードはテストが全部 check に通す。通らない書き方を見せるときは ```text にする。
- 問題点への答えを足したり見送ったりしたら、docs/DESIGN.md の表（入れた・入れなかった）に1行足す。
- 外に触る組み込み関数を足すときは、必ず権利の型（Console・Folder の仲間）を引数に取らせる。どこからでも呼べる外への関数は作らない。
- もう出さないコードは src/errors.js の RETIRED に入れ、番号を使い回さない。
- 実行時の深さは JS の呼び出しの深さに合わせて 500 まで（src/run.js の MAX_DEPTH）。

## 共通のきまり

- PR の作り方・マージの仕方は satou-aaaaa/shared-workflows の `routines/pr.md`、全体のきまりは `routines/common.md` に従う。
- CI の部品は shared-workflows の共通部品を呼ぶ（検査は node-test.yml、秘密の検査は secret-scan.yml）。リポジトリ側の .github/workflows には呼び出しと設定値だけを書く。
- Claude 以外の AI・人が作業するときは、shared-workflows の `routines/tool-map.md` と `routines/without-claude.md` を読む。
