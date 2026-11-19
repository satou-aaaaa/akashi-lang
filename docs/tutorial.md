# 入門：はじめての Akashi

30分ほどで、Akashi の考え方をひととおり手で試します。上から順に進めてください。
決まりを全部知りたいときは [言語の決まり](reference.md)、なぜその形なのかは [設計の根拠](DESIGN.md) を見てください。

用意するもの：Node.js 22。このリポジトリを手元に置いて、その中で動かします。

```bash
node bin/akashi.js run examples/hello.ak
```

`hello, akashi` と出れば準備はできています。

---

## 1. 画面に出す

`hello.ak` というファイルを作って、次のように書きます。

```akashi
fn main(console: Console) -> Unit
do
  print(to: console, value: "hello")
  print(to: console, value: 1 + 2)
end
```

```bash
node bin/akashi.js run hello.ak
```

ここで覚えること：

- プログラムは `main` から動きます。
- `console: Console` は「画面に出してよい」という**鍵**です。`print` はこの鍵がないと呼べません。鍵を受け取れるのは `main` だけです。
- 引数は必ず名前つきで書きます（`to:`・`value:`）。`print(console, "hello")` は E206 になります。
- 関数は `-> 型` で返す型を書きます。何も返さないときは `Unit` です。

## 2. 関数と約束

自分で関数を作ります。鍵を受け取らない関数（**純粋な関数**）には、約束（`ensures`）と見本（`example`）を書く決まりです。

```akashi
fn double(n: Int) -> Int
  ensures result == n * 2
  example double(n: 3) == 6
  example double(n: 0) == 0
do
  n * 2
end

fn main(console: Console) -> Unit
do
  print(to: console, value: double(n: 21))
end
```

```bash
node bin/akashi.js check double.ak
```

```text
ok: 2/2 examples passed, 200 generated inputs kept every ensures
```

- `ensures`：答え（`result`）について、いつでも成り立つこと。
- `example`：呼び方と、その答え。`check` のたびに全部動かします。
- `check` は、さらに**自動で作った入力を200個**渡して、`ensures` が破れないかを試します。

わざと間違えてみましょう。本体を `n * 2 + 1` にすると、`check` は見本の誤り（R502）を、どちらが正しいかの手がかりとともに出します。

## 3. 呼ぶ側が守ること（requires）

「0 で割らない」のように、**呼ぶ側**が守るべきことは `requires` に書きます。

```akashi
fn half_of(total: Int, people: Int) -> Int
  requires people > 0
  ensures result * people <= total or total < 0
  example half_of(total: 10, people: 2) == 5
do
  total / people
end

fn main(console: Console) -> Unit
do
  print(to: console, value: half_of(total: 9, people: 2))
end
```

`half_of(total: 9, people: 0)` と呼ぶと、動かしたときに R500（requires が守られていない）で止まり、「呼んだ側を直す」と教えてくれます。

## 4. 場合分け（if と when）

`if` は値を返す式で、`else` が必ず要ります。場合が3つ以上なら、`when` で `end` を1つにします。

```akashi
fn label(n: Int) -> Str
  ensures str_len(text: result) > 0
  example label(n: 15) == "FizzBuzz"
  example label(n: 9) == "Fizz"
  example label(n: 7) == "7"
do
  when
    n % 15 == 0 then "FizzBuzz"
    n % 3 == 0 then "Fizz"
    n % 5 == 0 then "Buzz"
    else to_str(value: n)
  end
end

fn main(console: Console) -> Unit
do
  print(to: console, value: map(list: range(from: 1, to: 16), func: label))
end
```

- ループ（for・while）はありません。くり返しは `range`・`map`・`filter`・`fold` か、再帰で書きます。
- `map` の `func:` には、自分で作った純粋な関数の**名前**を渡します。

## 5. 自分で作る型と match

いくつかの「場合」を持つ型を、自分で作れます。

```akashi
type Light
  case Red
  case Yellow
  case Green
end

fn can_go(light: Light) -> Bool
  ensures true
  example can_go(light: Green) == true
  example can_go(light: Red) == false
do
  match light
    case Red then false
    case Yellow then false
    case Green then true
  end
end

fn main(console: Console) -> Unit
do
  print(to: console, value: can_go(light: Yellow))
end
```

`case Yellow` の行を消して `check` すると、次のように止まります。

```text
E210 match on Light misses Yellow
  fix: add case Yellow then <value>. ...
```

- `match` は、型の**どの場合も1回ずつ**書きます。「それ以外」（`else` や `_`）はありません。
- だから、あとで `case Blinking` を足すと、直すべき `match` が全部エラーで見つかります。

場合が値（欄）を持つこともできます。

```akashi
type Shape
  case Circle(radius: Int)
  case Rect(width: Int, height: Int)
end

fn area(shape: Shape) -> Int
  ensures true
  example area(shape: Rect(width: 2, height: 3)) == 6
do
  match shape
    case Circle(radius: r) then 3 * r * r
    case Rect(width: w, height: h) then w * h
  end
end

fn main(console: Console) -> Unit
do
  print(to: console, value: [area(shape: Circle(radius: 2)), area(shape: Rect(width: 4, height: 5))])
end
```

- 値を作るときは関数のように、欄を名前つきで書きます：`Rect(width: 2, height: 3)`。
- `match` では欄を全部、宣言の順に書き、使う欄に新しい名前を付けます。使わない欄は `_` にします。

ためしに `ensures true` を `ensures result >= 0` にしてみてください。`check` が `area(shape: Rect(width: -1, height: 1))` のような**一番小さい反例**を見せます（R511）。負の長さを許さないなら `requires` を足します。

## 6. 無いかもしれない値（Option）

Akashi には **null がありません**。無いかもしれない値は `Option[T]` で表します。

```akashi
fn age_or_zero(text: Str) -> Int
  ensures result >= 0
  example age_or_zero(text: "42") == 42
  example age_or_zero(text: "abc") == 0
  example age_or_zero(text: "-3") == 0
do
  match parse_int(text: text)
    case Some(value: n) then if n < 0 then 0 else n end
    case None then 0
  end
end

fn main(console: Console) -> Unit
do
  print(to: console, value: age_or_zero(text: "18"))
end
```

- `parse_int` は、数として読めたら `Some(value: 数)`、読めなければ `None` を返します。
- `parse_int(text: text) + 1` のように、中身を取り出さずに使うと E201 になります。`None` の場合を忘れられません。
- リストの何番目かを取るときも `at(list: xs, index: i)` が `Option` を返します。

## 7. 失敗するかもしれない操作（Result）とファイル

Akashi には**例外がありません**。失敗するかもしれない操作は `Result[T]`（`Ok` か `Err`）を返します。ファイルの読み込みがそうです。

```akashi
fn main(console: Console, folder: Folder) -> Unit
do
  match read_text(from: folder, path: "fruits.txt")
    case Ok(value: text) then print(to: console, value: lines(text: text))
    case Err(message: why) then print(to: console, value: "could not read: " ++ why)
  end
end
```

```bash
node bin/akashi.js run fruits.ak --allow-read examples/files
```

- ファイルを読むには `folder: Folder` という鍵が要ります。鍵は、動かすときに `--allow-read` で渡したフォルダだけを読めます。
- `../` や絶対パスで外に出ようとすると R507 で止まります。
- ファイルが無いときは `Err` になります。`Err` の行を書かないと E210 で通りません。

## 8. AI に書かせる

ここまでの決まりは、英語の短い仕様 [SPEC.md](SPEC.md) にまとまっています。

```bash
node bin/akashi.js spec
```

これを AI に貼り、「Akashi で書いて」と頼みます。エラーが出たら `--json` の出力をそのまま AI に渡すと、`fix` を読んで直します。手順は [やり方集](howto.md#ai-に-akashi-を書かせる) にあります。

## 次に読むもの

- [やり方集](howto.md)：HTML・SQL を安全に作る、エラーを直す など
- [言語の決まり](reference.md)：全部の決まりと組み込み関数
- [安全の仕組み](security.md)：鍵・注入・Option/Result がどう守るか
- [エラー番号の一覧](ERRORS.md)
