# やり方集

決まった作業のやり方を、目的ごとに並べます。言語をはじめて触るときは、先に [入門](tutorial.md) を読んでください。

- [AI に Akashi を書かせる](#ai-に-akashi-を書かせる)
- [エラーを直す](#エラーを直す)
- [ファイルを読む](#ファイルを読む)
- [HTML と SQL を安全に作る](#html-と-sql-を安全に作る)
- [無いかもしれない値・失敗するかもしれない処理を書く](#無いかもしれない値失敗するかもしれない処理を書く)
- [型に場合を足す](#型に場合を足す)
- [長いくり返しを書く](#長いくり返しを書く)
- [書式を整える](#書式を整える)
- [処理系にエラー番号を足す（開発する人向け）](#処理系にエラー番号を足す開発する人向け)

---

## AI に Akashi を書かせる

1. 仕様を出して、AI のプロンプトの先頭に貼ります。

   ```bash
   node bin/akashi.js spec
   ```

2. 続けて、作ってほしいものを書きます。たとえば：

   ```text
   Write an Akashi program. Read numbers (one per line) from "scores.txt"
   and print their sum. Skip lines that are not numbers.
   ```

3. 返ってきたコードを `.ak` に保存して、検査します。

   ```bash
   node bin/akashi.js check answer.ak --json
   ```

4. `ok` が `false` なら、出てきた JSON をそのまま AI に渡して「fix のとおり直して」と頼みます。`diagnostics` の1つ1つに、番号（`code`）・場所（`line`・`col`）・直し方（`fix`）が入っています。
5. `ok: ...` が出たら、`run` で動かします。

こつ：

- 仕様は全部貼ります。Akashi は学習データにほとんど無い言語なので、仕様を読ませないと書けません（[設計の根拠 2.1](DESIGN.md#21-わかったこと)）。
- リポジトリごと AI に読ませるときは、入口の [`llms.txt`](../llms.txt) を最初に読ませます。

## エラーを直す

エラーは次の形で出ます。

```text
answer.ak:12:3: E210 match on Light misses Yellow
  fix: add case Yellow then <value>. ...
```

- `12:3` は行と列です。
- `E` で始まる番号は動かす前の検査、`R` で始まる番号は動かしたときに見つかったものです。
- `fix:` の行に、次にどう書けば通るかが書いてあります。まずこれに従います。
- 番号の意味と見本は [エラー番号の一覧](ERRORS.md) にあります。`node bin/akashi.js explain E210` でも名前を引けます。
- エラーが続けていくつも出たときは、上から直します。上のエラーが下のエラーの原因になっていることがあります。

## ファイルを読む

1. `main` に `folder: Folder` を足します。
2. `read_text` は `Result[Str]` を返すので、`match` で `Ok` と `Err` の両方を書きます。

```akashi
fn main(console: Console, folder: Folder) -> Unit
do
  match read_text(from: folder, path: "data/input.txt")
    case Ok(value: text) then print(to: console, value: len(list: lines(text: text)))
    case Err(message: why) then print(to: console, value: "error: " ++ why)
  end
end
```

3. 動かすときに、読んでよいフォルダを1つ渡します。

   ```bash
   node bin/akashi.js run count.ak --allow-read ./mydata
   ```

- パスは、渡したフォルダから見た相対パスで書きます。`..`・絶対パス・リンク（中を指していても）は R507 で止まります。
- 鍵を渡さずに動かすと R509 で止まります。

## ファイルに書く

1. `main` に `out: OutFolder` を足します（読む鍵 Folder とは別の鍵です）。
2. `write_text` は `Result[Unit]` を返すので、`match` で `Ok` と `Err` の両方を書きます。

```akashi
fn main(console: Console, out: OutFolder) -> Unit
do
  match write_text(to: out, path: "report.txt", text: "total: 3\n")
    case Ok(value: _) then print(to: console, value: "saved")
    case Err(message: why) then print(to: console, value: "error: " ++ why)
  end
end
```

3. 動かすときに、書いてよいフォルダを1つ渡します。読むフォルダと同じでも別でもかまいません。

   ```bash
   node bin/akashi.js run save.ak --allow-write ./out
   ```

- ファイルが無ければ作り、あればまるごと書きかえます。足して書く・消す・フォルダを作ることはできません（要るなら、読んで足して書き直します）。
- 親のフォルダが無いときは `Err` です。

## HTML と SQL を安全に作る

外から来た文字（入力された名前など）を HTML や SQL に入れるときは、文字をつながず、**型紙**と**値**を分けて書きます。

```akashi
fn greeting(name: Str) -> Html
  ensures true
  example to_str(value: greeting(name: "<b>")) == "<p>Hello, &lt;b&gt;</p>"
do
  html(template: "<p>Hello, {}</p>", values: [html_text(value: name)])
end

fn by_name(name: Str) -> Sql
  ensures true
  example to_str(value: by_name(name: "a")) == "SELECT id FROM users WHERE name = ? -- params: [\"a\"]"
do
  sql(template: "SELECT id FROM users WHERE name = ?", values: [name])
end

fn main(console: Console) -> Unit
do
  print(to: console, value: greeting(name: "<script>"))
  print(to: console, value: by_name(name: "x' OR '1'='1"))
end
```

- 型紙（`template:`）は、コードに書いたままの文字にします。`++` でつないで作ると E310 です。
- 穴（HTML は `{}`、SQL は `?`）の数と値の数をそろえます（E311）。
- HTML の穴に入れる文字は `html_text` を通します。`< > & " '` が自動で置きかわります。
- いくつかの `Html` をつなぐときは `html_join(parts: [...])` を使います。
- まだ守れないこと：`href`・`src` に外から来た URL を入れること（`javascript:` が入りうる）。くわしくは [安全の仕組み](security.md#まだ守れないこと)。

## 無いかもしれない値・失敗するかもしれない処理を書く

- 「見つからないかもしれない」なら、`Option[T]` を返します。見つかったら `Some(value: x)`、無ければ `None`。
- 「失敗するかもしれない」なら、`Result[T]` を返します。うまくいけば `Ok(value: x)`、だめなら `Err(message: "理由")`。

```akashi
fn safe_div(a: Int, b: Int) -> Result[Int]
  ensures true
  example safe_div(a: 7, b: 2) == Ok(value: 3)
  example safe_div(a: 1, b: 0) == Err(message: "divided by zero")
do
  if b == 0 then Err(message: "divided by zero") else Ok(value: a / b) end
end

fn main(console: Console) -> Unit
do
  match safe_div(a: 10, b: 0)
    case Ok(value: q) then print(to: console, value: q)
    case Err(message: why) then print(to: console, value: why)
  end
end
```

`requires b != 0` と `Result` のどちらにするかの目安：

- 呼ぶ側が**必ず**守れる・守るべきこと（プログラムの誤り）なら `requires`。
- 外から来た値など、呼ぶ側にもどうにもならないことがあるなら `Result`。

## 型に場合を足す

1. `type` に `case` の行を足します。
2. `check` します。その型を `match` している場所が全部 E210 で出ます。
3. 出た場所に、新しい場合の行を足していきます。`fix:` に書くべき行が出ています。

`else` や `_` で「それ以外」をまとめる書き方は無いので、足し忘れは起きません。

## 長いくり返しを書く

再帰は 500 段までです（R505）。長いくり返しは `range` と `fold` で書きます。

```akashi
fn add_square(acc: Int, i: Int) -> Int
  ensures true
  example add_square(acc: 1, i: 2) == 5
do
  acc + i * i
end

fn main(console: Console) -> Unit
do
  print(to: console, value: fold(list: range(from: 1, to: 10001), init: 0, func: add_square))
end
```

## 書式を整える

```bash
node bin/akashi.js fmt answer.ak            # その場で整える
node bin/akashi.js fmt --check answer.ak    # 書きかえずに確かめる（整っていなければ 1 で終わる）
```

- AI が書いたコードは、検査の前に整えておくと、差分が読みやすくなります。
- 構文の誤りがあるファイルは整えません（E1xx を出します）。
- このリポジトリの `.ak` と説明書きのコードは、テストが「整っているか」を確かめます。

## 処理系にエラー番号を足す（開発する人向け）

1. `src/errors.js` の `CODES` に、新しい番号と短い名前を足します。今ある番号の意味は変えません。
2. 検査（`src/check.js`）か実行（`src/run.js`）で、その番号の診断を出します。`fix` には、次にどう書けば通るかを、貼れるコードで書きます。
3. `examples/bad/<番号>-<名前>.ak` を作り、1行目に `# expect: <番号>` を書きます。
4. `node scripts/gen-errors.mjs` で [ERRORS.md](ERRORS.md) を作り直します。
5. `npm test` を通します（見本が無い番号・古い ERRORS.md・`fix` の無い診断は、テストが落とします）。
6. 言語の決まりが変わるなら、[SPEC.md](SPEC.md)（英語・短く）と [言語の決まり](reference.md)（日本語）を同じ PR で直します。
