# コンパイラ

Akashi のプログラムを **WebAssembly**（`.wasm`）に変えるコンパイラの説明です。
外の部品（LLVM・Binaryen など）は使わず、WebAssembly のバイト列を**0から自分で書き出します**。依存はゼロです。

- [使い方](#使い方)
- [しくみ](#しくみ)
- [正しさの守り方](#正しさの守り方)
- [なぜ WebAssembly か（調べたこと）](#なぜ-webassembly-か調べたこと)
- [セルフホストまでの段階](#セルフホストまでの段階)
- [出典](#出典)

---

## 使い方

```bash
node bin/akashi.js build examples/gcd.ak -o gcd.wasm   # 検査（見本・自動の試しも）が通ったら .wasm を書き出す
node bin/akashi.js wasm gcd.wasm                       # 動かす（渡すのは画面と標準エラーだけ）
wasmtime gcd.wasm                                      # wasmtime など、ほかの WASI の実行環境でも動く
```

- `build` は、`check` が通ったプログラムだけをコンパイルします。
- まだ扱えない書き方を使うと **E600** になります。そのプログラムは `akashi run`（インタプリタ）で動かしてください。
- 終わりのコードは、通れば 0、実行時のエラーなら 1 です。エラーの文は標準エラーに `行:列: 番号 説明` の形で出ます。

### 今（段階1）扱えるもの

| 扱える | まだ扱えない（E600） |
| --- | --- |
| Int・Bool・Str・Unit | List・Option・Result・自分で作る型・match |
| 関数・再帰・let・if・when | map・filter・fold・find・range など、リストの関数 |
| requires・ensures（毎回確かめる） | Folder（ファイルを読む）・Html・Sql |
| print・to_str・str_len | |
| `+ - * / %`・比較・`and or not`・`++`（Str） | |

## しくみ

```text
.ak ──字句・構文解析──▶ 木 ──型の検査・見本・自動の試し──▶ 型つきの木 ──src/wasm.js──▶ .wasm
       (src/parse.js)           (src/check.js ほか)                       (バイト列を直接書く)
```

- **値の表し方**：Int は 64 ビット整数（i64）、Bool は 0/1（i32）、Str はメモリ上の「長さ（4バイト）＋UTF-8 のバイト」の先頭の場所（i32）、Unit は値なし。
- **鍵（Console）は消える**：鍵の使い方は検査で確かめ終わっているので、実行時には何も渡しません。
- **外とのつながりは2つだけ**：WASI の `fd_write`（画面と標準エラーに書く）と `proc_exit`（終わる）だけを取り込みます。ファイル・時計・乱数・通信は取り込まないので、コンパイルしたプログラムはそれらに触れません（テストが取り込みの一覧を確かめます）。
- **実行時の部品**も WebAssembly で書いています（`src/wasm.js` の `helpers`）：メモリの確保、文字の連結・比較・長さ、数を文字にする、あふれの確かめ、かけ算のあふれの確かめ、呼び出しの深さ、エラーで止める。
- **インタプリタと同じ意味**にそろえています：Int は ±9007199254740991 を超えたら R504、0 で割ったら R503、再帰は 500 段まで（R505）、requires（R500）・ensures（R501）は毎回確かめる。
- バイナリの形は WebAssembly の仕様書の「Binary Format」の章のとおりです（型・取り込み・関数・メモリ・大域変数・書き出し・コード・データの各節）。

## 正しさの守り方

意味の正はインタプリタ（`src/run.js`）です。コンパイラはそれと**同じ答え**を出さなければいけません。`test/compile.test.js` が毎回比べます。

1. `examples/*.ak` と `test/compile/*.ak` を、インタプリタとコンパイラの両方で動かし、**出力・終わりのコード・エラー番号**が一致するかを比べる。`test/compile/` には、あふれ・0 割り・requires と ensures の破れ・深すぎる再帰など、境目の見本を置いている。
2. **自動で作った式 300 個**（大きな数・負の数・0 割りを含む）を両方で動かして比べる（差分テスト）。種は固定なので、毎回同じ式で試す。
3. できた `.wasm` が正しい WebAssembly か（`WebAssembly.validate`）、取り込みが2つだけかを確かめる。
4. `test/compile/` の見本がコンパイルできなくなったら落とす（黙って E600 で飛ばさない）。

## なぜ WebAssembly か（調べたこと）

| 調べたこと | わかったこと | Akashi では |
| --- | --- | --- |
| 動かす場所の安全 | WebAssembly は、取り込んだ関数を通してしか外に触れない作り（サンドボックス）。WASI も「渡されたものだけ使える」考え方 [2][3] | 鍵の考えと同じ。取り込みを最小（2つ）にした |
| どこで動くか | ブラウザ・Node.js・wasmtime などで同じ `.wasm` が動く | 遊べるページ（ブラウザ）でも同じものを動かせる |
| WasmGC・末尾呼び出し | ごみ集め（WasmGC）と末尾呼び出しは主要なブラウザで使えるようになった。Node.js 22 でも WasmGC が既定で使える [4][5][6] | 段階2（リスト・型）で WasmGC を使う。段階3で末尾呼び出しを使い、再帰の深さの上限をゆるめる |
| 先行例：AssemblyScript | TypeScript に似た言語。WebAssembly の最適化の部品 Binaryen を使って書き出す [7] | Binaryen は使わず、0から書く（依存ゼロの方針） |
| 先行例：Grain | WebAssembly のために作られた関数型の言語。WasmGC への移行も進めている [8][4] | 型と match の考え方が近い。段階2の参考にする |
| 先行例：MoonBit | WebAssembly を第一の出力先にした言語。小さく速いバイナリを出す [9] | 同じく WebAssembly を第一の出力先にした |
| 作り方の定番 | 自分の言語で自分のコンパイラを書き（セルフホスト）、出来たコンパイラで自分をもう一度コンパイルして、結果が一致するかを確かめる（GCC の3段の立ち上げ） [10] | 下の段階5・6 |

## セルフホストまでの段階

最終の目標は「**Akashi のコンパイラを Akashi で書く**」ことです。

| 段階 | やること | 終わりの目印 |
| --- | --- | --- |
| 1（済み） | Int・Bool・Str・関数・if・約束を、WebAssembly に0から書き出す。インタプリタとの差分テスト | `examples/` のうち、リストを使わないものが全部同じ答え |
| 2 | List・Option・Result・自分で作る型・match・map/filter/fold・Html/Sql。値はメモリに置き、ごみ集めは WasmGC を使う | `examples/` の全部（ファイル以外）が同じ答え |
| 3 | Folder（WASI の `path_open`。渡したフォルダだけを開ける）。末尾呼び出し（`return_call`）で長い再帰 | `read_file.ak` が wasmtime の `--dir` で動く |
| 4 | コンパイラを書くのに要る道具を言語に足す：文字を1文字ずつ見る・切り出す、バイトの並び（Bytes）、辞書（名前→値）、ファイルに書く鍵、複数のファイル（部品） | 字句解析を Akashi で書ける |
| 5 | Akashi でコンパイラを書く（`compiler/*.ak`）。今の JS のコンパイラ（段階0）でそれをコンパイルして `akashic.wasm`（段階1）を作る | `akashic.wasm` が `examples/` を正しくコンパイルする |
| 6 | `akashic.wasm` で自分をコンパイルして段階2を作り、段階1と**1バイトも違わない**ことを確かめる（不動点） | テストで毎回確かめる。JS のコンパイラは「種」として残し、別の道で作った結果と比べる（[11]） |

段階4で足す道具は、コンパイラのためだけでなく、ふつうのプログラムにも役に立つものを選びます。足すたびに [設計の根拠](DESIGN.md) の表と [言語の決まり](reference.md) を直します。

## 出典

1. WebAssembly Core Specification, "Binary Format". https://webassembly.github.io/spec/core/binary/index.html
2. WebAssembly, "Security". https://webassembly.org/docs/security/
3. WASI Design Principles. https://github.com/WebAssembly/WASI/blob/main/docs/DesignPrinciples.md
4. V8, "A new way to bring garbage collected programming languages efficiently to WebAssembly". https://v8.dev/blog/wasm-gc-porting
5. web.dev, "WasmGC and Wasm tail call optimizations are now Baseline Newly available". https://web.dev/blog/wasmgc-wasm-tail-call-optimizations-baseline
6. Node.js 22 release announcement. https://nodejs.org/en/blog/announcements/v22-release-announce
7. AssemblyScript. https://www.assemblyscript.org/
8. The New Stack, "Meet Grain, the High-Level Language Optimized for WebAssembly". https://thenewstack.io/meet-grain-the-high-level-language-optimized-for-webassembly/
9. The New Stack, "Introduction to MoonBit, a New Language Toolchain for Wasm". https://thenewstack.io/introduction-to-moonbit-a-new-language-toolchain-for-wasm/
10. GCC, "Building"（3段の立ち上げ bootstrap と、段階2・3の比べ合わせ）. https://gcc.gnu.org/install/build.html
11. David A. Wheeler, "Countering Trusting Trust through Diverse Double-Compiling". https://dwheeler.com/trusting-trust/
