# 変更履歴

版の決め方：試作のあいだは 0.x。言語の決まりが変わる（前に通ったプログラムが通らなくなる）ときは、2つめの数を上げる。
形は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) にならう。

## 0.6.0 — 2026-11-19

### 足した
- 遊べるページ（`index.html`・`playground/`）：ブラウザだけで検査・実行・Wasm で実行・整える。外へは通信しない（CSP で止める）。Folder の鍵は渡さない。コードは URL の # にだけ入れて共有。
- 処理系を Node の部品を使わない `src/core.js` と、Node だけの `src/index.js`・`src/folder.js` に分けた（ブラウザでも同じ処理系を動かすため）。
- `akashi fmt`：書式を決まった形に整える（意味は変えない・2回かけても同じ、をテストで確かめる）。
- ライセンスを MIT にした。
- コンパイラ（段階1）：`akashi build` で WebAssembly（WASI のコマンド）に0から書き出す。`akashi wasm` で動かす。Int・Bool・Str・Unit・関数・再帰・let・if・when・requires・ensures・print・to_str・str_len。ほかは E600。
- インタプリタとコンパイラの答えを比べるテスト（見本と、自動で作った式 300 個）。
- 使う道具の決まり：依存ゼロをテストで守る。CodeQL の指摘・保守切れの Node・脆弱な依存で CI を止める。Dependabot。
- 説明書き：[コンパイラ](docs/compiler.md)（しくみ・調べたこと・セルフホストまでの段階）、[安全の仕組み](docs/security.md) に「使う道具の決まり」。

## 0.5.0 — 2026-11-19

### 足した
- 自分で作る型（`type ... case ... end`）と、漏れの無い `match`（E210・E211・E212）。
- 組み込みの `Option[T]`・`Result[T]`。`parse_int`・`at`・`find`。
- 自動の試しが、自分で作る型の値も作る。
- 説明書きを Diátaxis の4種類に分けて整えた（入門・やり方集・言語の決まり・解説）。`llms.txt`・`akashi spec`。

### 変えた
- `read_text` は `Result[Str]` を返す（ファイルが無いときは `Err`）。R508 は廃止。

## 0.4.0 — 2026-11-19

### 足した
- `when`（いくつもの場合分けを end 1つで）。
- check のたびに、自動で作った入力で ensures を試す（R511・R512）。

## 0.3.0 — 2026-11-19

### 足した
- `Html`・`Sql`：書いたままの型紙＋値でしか作れない（E310・E311・R510）。

## 0.2.0 — 2026-11-19

### 変えた
- 副作用の宣言（effects）をやめ、鍵（Console・Folder）を引数で渡す形にした（E300・E309・R507・R509）。

## 0.1.0 — 2026-11-19

### 足した
- 最初の版：型・名前つき引数・約束（requires・ensures・example）・番号つきのエラーと直し方。
