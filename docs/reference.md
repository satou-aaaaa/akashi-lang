# 言語の決まり（v0.5）

Akashi の決まりを全部並べます。調べるための文書です。覚えるには [入門](tutorial.md)、理由は [設計の根拠](DESIGN.md) を見てください。
AI に貼る英語の短い版は [SPEC.md](SPEC.md) です。両方は同じ中身にそろえます。

- [プログラムの形](#プログラムの形)
- [関数](#関数)
- [型](#型)
- [自分で作る型と match](#自分で作る型と-match)
- [名前](#名前)
- [呼び出し](#呼び出し)
- [式](#式)
- [鍵（ケーパビリティ）](#鍵ケーパビリティ)
- [HTML と SQL](#html-と-sql)
- [組み込み関数](#組み込み関数)
- [検査と実行](#検査と実行)
- [コマンド](#コマンド)

---

## プログラムの形

- プログラムは、関数（`fn`）と型（`type`）を並べたものです。順番は自由です。
- `run` は `main` を呼びます。
- コメントは `#` から行の終わりまでです。
- 字下げや改行の数に意味はありません（読みやすさのためだけ）。

## 関数

```text
fn 名前(引数: 型, 引数: 型) -> 返す型
  requires 条件      # 0個以上。呼ぶ側が守ること
  ensures 条件       # 純粋な関数には1つ以上。result で答えを指せる
  example 条件       # 純粋な関数には1つ以上。呼び方と答え
do
  let 名前: 型 = 式   # 0行以上。let の行か、Unit を返す式（print など）の行
  式                  # 最後の行が、関数の値
end
```

- 返す型は必ず書きます（E102）。何も返さないなら `-> Unit`。
- `requires`・`ensures`・`example` は `-> 型` と `do` のあいだに、好きな順で書きます。
- **純粋な関数**：鍵（`Console`・`Folder`）を引数に取らず、`main` でもない関数。`ensures`（E401）と `example`（E402）が要ります。何も約束できないときだけ `ensures true` と書きます。
- 鍵を引数に取る関数と `main` には、`ensures`・`example` は要りません。
- `main` は鍵だけを引数に取り（同じ型は1つずつ）、`Unit` を返します（E303）。
- `requires`・`ensures`・`example` の中では鍵を使えません。
- 本体の途中の行が `Unit` 以外の値を返すとエラーです（E201）。値は `let` で受けるか、最後の行にします。

## 型

| 型 | 中身 | 書き方 |
| --- | --- | --- |
| `Int` | 整数（±9007199254740991 まで。あふれたら R504） | `42`、`-7` |
| `Bool` | 真偽 | `true`、`false` |
| `Str` | 文字列 | `"hi\n"`（使える `\` は `\n \t \" \\`） |
| `Unit` | 値が無いこと | `()` |
| `List[T]` | 同じ型の並び | `[1, 2, 3]`、`[]` |
| `Option[T]` | 無いかもしれない値 | `Some(value: x)`、`None` |
| `Result[T]` | 失敗するかもしれない結果 | `Ok(value: x)`、`Err(message: "理由")` |
| `Html` | 組み立て済みの HTML | `html(...)`・`html_text(...)`・`html_join(...)` だけで作る |
| `Sql` | 組み立て済みの SQL と値 | `sql(...)` だけで作る |
| `Console` | 画面に出す鍵 | 作れない。`main` が受け取る |
| `Folder` | フォルダを読む鍵 | 作れない。`main` が受け取る |
| 自分で作る型 | 下を見る | `type 名前 ... end` |

- 小数はありません（E101）。null もありません。
- 型は勝手に変わりません。違う型を混ぜるとエラーです（E201）。
- `[]` の中身の型は、`let` の型や引数の型から決まります。

## 自分で作る型と match

### 型を作る

```text
type 型の名前
  case 場合の名前(欄: 型, 欄: 型)
  case 欄の無い場合の名前
end
```

- 型の名前と場合の名前は大文字で始めます。
- 場合の名前は、プログラム全体で1つずつです（`Some`・`None`・`Ok`・`Err` も使用済み）。関数の名前とも重ねられません（E203）。
- 場合が1つだけの型は、レコード（いくつかの値の組）として使えます。
- 型は自分自身を欄に持てます（木の形など）。
- 欄に鍵は入れられません（E309）。
- 型引数（`Tree[T]` など）は、まだ自分では作れません。

### 値を作る

- 欄のある場合は、関数のように名前つき・宣言の順で：`Rect(width: 2, height: 3)`
- 欄の無い場合は名前だけ：`Dot`
- `==` は欄を1つずつ比べます。`print` は `Rect(width: 2, height: 3)` の形で出します。

### match

```text
match 式
  case 場合(欄: 新しい名前, 欄: _) then 値
  case 欄の無い場合 then 値
end
```

- 型の**どの場合も1回ずつ**書きます。抜けは E210、ほかの型の場合・同じ場合の2回目・`else`・`_` は E211 です。
- 欄は全部、宣言の順に書きます（E212）。値を使う欄には新しい名前を、使わない欄には `_` を書きます。
- 新しい名前も、名前の決まり（使い回さない）に従います。
- どの行も同じ型の値を返します。
- `Option`・`Result` の値は、`match` でしか中身を取り出せません。

## 名前

- 名前は英字・数字・`_` です。数字では始められません。
- `let` には型を書きます（E103）。
- 同じ関数の中で、同じ名前を2回決められません。引数・`let`・`match` の名前・関数名・組み込み関数名・場合の名前と重ねるのもだめです（E203）。
- 書きかえ（代入）はありません。

## 呼び出し

- 引数は**全部名前つき**（E206）、**宣言の順**（E207）です。自分の関数も組み込み関数も同じです。
- 足りない・多すぎる・2回書いた引数は E202 です。
- `map`・`filter`・`fold`・`find` の `func:` には、純粋な関数の**名前**を渡します。その関数の引数は順番で渡されます。鍵を取る関数は渡せません（E304）。組み込み関数も直接は渡せません。

## 式

| 種類 | 書き方 |
| --- | --- |
| 四則（Int だけ） | `+ - * / %`。`/` は 0 の方向に切り捨て。0 で割ると R503 |
| つなぐ（Str か List） | `"a" ++ "b"`、`[1] ++ [2]` |
| 比べる | `==`・`!=`（両側が同じ型）、`<`・`<=`・`>`・`>=`（Int） |
| 論理 | `and`・`or`・`not`。`and` と `or` を混ぜるときは括弧（E105）。比較はつなげない（E106）：`0 <= x and x < 10` |
| if | `if 条件 then 値 else 値 end`。`else` は必ず（E107）。`if` ごとに `end` |
| when | 下を見る |
| match | 上を見る |

```text
when
  条件 then 値
  条件 then 値
  else 値
end
```

`when` は上から順に調べ、最初に成り立った行の値になります。`else` は必ず書きます（E112）。

## 鍵（ケーパビリティ）

| 鍵 | できること | 渡されるとき |
| --- | --- | --- |
| `Console` | `print(to: console, value: x)` | いつも |
| `Folder` | `read_text(from: folder, path: "a.txt")`。読むだけ。渡したフォルダの中だけ | `--allow-read <フォルダ>` を付けて動かしたときだけ |

- 鍵を受け取れるのは `main` だけです。ほかの関数には引数で渡します。
- 鍵を持たない関数で鍵の要る関数を呼ぶと E300 です。直し方に、引数の足し方が出ます。
- 鍵は `let` にしまえず、返せず、リストや型の欄に入れられず、比べられません（E309）。

## HTML と SQL

| 呼び方 | 返す型 | 決まり |
| --- | --- | --- |
| `html(template: "...", values: [...])` | Html | 型紙は書いたままの文字（E310）。穴 `{}` と値の数をそろえる（E311・R510）。値は `List[Html]` |
| `html_text(value: s)` | Html | `< > & " '` を置きかえる |
| `html_join(parts: xs)` | Html | Html をつなぐ |
| `sql(template: "...", values: [...])` | Sql | 型紙は書いたままの文字。穴 `?` と値の数をそろえる。値は文と別に持つ |

- `Html`・`Sql` は `++` でつなげません。
- 文字からコードを動かす `eval` はありません。

## 組み込み関数

| 呼び方 | 型・働き |
| --- | --- |
| `print(to: console, value: x)` | 何でも → Unit。画面に1行出す（鍵 Console が要る） |
| `read_text(from: folder, path: p)` | Result[Str]。無い・フォルダ・UTF-8 でないときは Err（鍵 Folder が要る） |
| `lines(text: s)` | List[Str]。行に分ける（`\r\n` も可、最後の改行は数えない） |
| `parse_int(text: s)` | Option[Int]。前後の空白は無視。整数でなければ None |
| `len(list: xs)` | Int |
| `str_len(text: s)` | Int。文字（コードポイント）の数 |
| `slice(text: s, from: a, to: b)` | Str。a 文字目から b 文字目の手前まで（文字はコードポイントで数える）。`0 <= a <= b <= str_len` でないと R506 |
| `code_of(char: c)` | Int。1文字の文字コード（コードポイント）。1文字でないと R506 |
| `char_of(code: n)` | Str。文字コードから1文字。0〜1114111 でない・サロゲート（55296〜57343）だと R506 |
| `to_str(value: x)` | Str |
| `range(from: a, to: b)` | List[Int]。a から b-1 まで（100万個まで） |
| `at(list: xs, index: i)` | Option[T]。範囲の外なら None |
| `get(list: xs, index: i)` | T。範囲の外なら R506。`i < len(list: xs)` を確かめてから使う |
| `find(list: xs, func: f)` | Option[T]。f が true になる最初の要素 |
| `append(list: xs, item: x)` | List[T]。新しいリストを返す |
| `map(list: xs, func: f)` | List[U]。f: fn(T) -> U |
| `filter(list: xs, func: f)` | List[T]。f: fn(T) -> Bool |
| `fold(list: xs, init: z, func: f)` | f: fn(たまった値, 要素) -> たまった値 |
| `any(list: xs, func: f)`・`all(list: xs, func: f)` | Bool。f が true になる要素が1つでもあるか・全部か |
| `reverse(list: xs)` | List[T]。逆の順 |
| `take(list: xs, count: n)`・`drop(list: xs, count: n)` | List[T]。はじめの n 個・はじめの n 個を除いた残り。n が長さより大きければ全部・空。n が負なら R506 |
| `sort(list: xs)` | List[Int]。小さい順 |
| `sum(list: xs)` | Int。合計（あふれたら R504） |
| `max(list: xs)`・`min(list: xs)` | Option[Int]。空なら None |
| `chars(text: s)` | List[Str]。1文字（コードポイント）ずつ |
| `split(text: s, by: sep)` | List[Str]。sep で分ける（sep が空なら R506。1文字ずつは chars） |
| `join(parts: xs, by: sep)` | Str。sep をはさんでつなぐ |
| `contains(text: s, part: p)`・`starts_with(text: s, prefix: p)`・`ends_with(text: s, suffix: p)` | Bool |
| `trim(text: s)` | Str。前後の空白と改行を取る |
| `html`・`html_text`・`html_join`・`sql` | 上の「HTML と SQL」 |

## 検査と実行

`check` がすること（上から順に）：

1. 文法（E1xx）。最初の1つで止まります。
2. 型・名前・引数・鍵・約束の有無（E2xx〜E4xx）。見つかったものを全部出します。
3. 全部の `example` を動かします（R502）。
4. 純粋な関数に、型に合う入力を自動で作って渡し、`requires` を満たすのに `ensures` が破れる（R511）・落ちる（R512）入力を探します。種は固定なので毎回同じ結果です。見つかったら、一番小さい形にして見せます。

`run` は `check` が通ったときだけ `main` を動かします。動かしているあいだも、呼び出しのたびに `requires`（R500）と `ensures`（R501）を確かめます。再帰は 500 段まで（R505）。

## コマンド

```bash
node bin/akashi.js check file.ak [--json]
node bin/akashi.js run file.ak [--json] [--allow-read <フォルダ>]
node bin/akashi.js build file.ak [-o out.wasm] [--json]
node bin/akashi.js wasm out.wasm [--allow-read <folder>]
node bin/akashi.js fmt file.ak [--check]
node bin/akashi.js explain E210
node bin/akashi.js spec
```

- `build` は、`check` が通ったプログラムを WebAssembly にします。まだ扱えない書き方は E600 です（[コンパイラ](compiler.md)）。
- `wasm` は、コンパイルしたものを動かします。渡すのは画面と標準エラーで、`--allow-read` を付けたときだけ、そのフォルダを読むことを許します。
- `fmt` は、書式を決まった形に整えます（字下げは空白2つ、語のあいだの空白、空行は1つまで、fn と type のあいだに空行1つ）。行の分け方とコメントは変えません。`--check` は書きかえずに、整っていないファイルを知らせます。

- 終わりのコードは、通れば 0、エラーなら 1、使い方の誤りなら 2 です。
- `--json` では `{ ok, diagnostics: [{ code, kind, message, line, col, fix }], ... }` を出します。この形は変えません。
