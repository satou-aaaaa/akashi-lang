# Akashi（あかし）

**AI が書いても、間違えにくく、危なくなりにくい** 小さなプログラミング言語の試作です。

名前は「証（あかし）」から。関数ごとに「約束（ensures）」と「見本（example）」を書き、処理系が毎回それを確かめます。

```akashi
type Light
  case Red
  case Yellow
  case Green
end

fn can_go(light: Light) -> Bool
  ensures true
  example can_go(light: Green) == true
do
  match light
    case Red then false
    case Yellow then false
    case Green then true
  end
end

fn main(console: Console) -> Unit
do
  print(to: console, value: can_go(light: Green))
end
```

## なぜ作ったか

- AI がコードを書く時代になりましたが、今の言語は「人が気をつけて書く」ことを前提にしています。null の見落とし、エラーの無視、文字列をつないで作る SQL などは、AI もよく間違えます。
- Akashi は、その種の誤りを**書けない形**にし、書いてしまっても**動かす前に**、番号と「次にどう書けば通るか」をつけて知らせます。AI はそれを読んで自分で直せます。
- どの言語のどんな問題を、どう防ぐのか（防がないのか）は [設計の根拠](docs/DESIGN.md) に表でまとめています。

## 特長

| | |
| --- | --- |
| null が無い・例外が無い | `Option`・`Result` と、漏れの無い `match` |
| 外に触る権利は鍵で渡す | 鍵（`Console`・`Folder`）を引数で受け取った関数だけが画面やファイルに触れる |
| 注入できない HTML・SQL | 書いたままの型紙＋値でしか作れない |
| 約束を毎回確かめる | `requires`・`ensures`・`example`。check のたびに自動の入力でも試す |
| エラーは番号つきで直し方つき | `--json` で AI が読める形でも出せる |
| 書き方は1つ | 引数は名前つき・型は必ず書く・暗黙の変換無し・名前の使い回し無し |

## すぐ試す

Node.js 22 だけで動きます（入れるものはありません）。

```bash
git clone https://github.com/satou-aaaaa/akashi-lang.git
cd akashi-lang
node bin/akashi.js run examples/hello.ak                      # hello, akashi
node bin/akashi.js check examples/types.ak                    # 検査と見本と自動の試し
node bin/akashi.js check examples/bad/e210-missing-case.ak    # わざと間違えた見本：直し方が出る
node bin/akashi.js run examples/read_file.ak --allow-read examples/files   # 読んでよいフォルダを1つ渡す
node bin/akashi.js build examples/gcd.ak -o gcd.wasm         # WebAssembly にコンパイル（0から書き出す。段階1）
node bin/akashi.js wasm gcd.wasm                              # コンパイルしたものを動かす
node bin/akashi.js spec                                       # AI に貼る短い仕様
npm test
```

## 説明書き

読む目的に合わせて分けています（[Diátaxis](https://diataxis.fr/) の考え方）。

| 目的 | 文書 |
| --- | --- |
| はじめて触る | [入門：はじめての Akashi](docs/tutorial.md) |
| 決まった作業をする | [やり方集](docs/howto.md)（AI に書かせる・エラーを直す・ファイルを読む・HTML/SQL を作る など） |
| 決まりを調べる | [言語の決まり](docs/reference.md)・[エラー番号の一覧](docs/ERRORS.md) |
| AI に教える | [SPEC.md](docs/SPEC.md)（英語・短く。プロンプトに貼る）・[llms.txt](llms.txt)（AI 向けの入口） |
| しくみを知る | [安全の仕組み](docs/security.md)（使う道具の決まりも）・[設計の根拠](docs/DESIGN.md)（今の言語の問題点の表・AI が書きやすい言語の調べ・出典）・[コンパイラ](docs/compiler.md)（WebAssembly への書き出しと、セルフホストまでの段階） |

## 今の状態（v0.5）

- できる：Int・Bool・Str・List・Option・Result・自分で作る型、関数・再帰、if・when・match、map・filter・fold・find、約束の検査と自動の試し、鍵（画面・フォルダの読み込み）、注入できない HTML・SQL、エラーの JSON 出力。
- コンパイラ（段階1）：Int・Bool・Str・関数・if・when・約束を WebAssembly に0から書き出す。インタプリタと同じ答えかを毎回比べる。
- まだ無い：小数、ファイルの書き込み・通信、部品（モジュール）、並行処理。コンパイラはリスト・型がまだ（段階2）。
- 依存はゼロです。CodeQL・依存の脆弱性・Node の保守の確かめを CI で毎回回し、見つかったら PR を止めます。
- 試作です。言語の決まりは、版が上がると変わることがあります。

## 開発する人へ

[AGENTS.md](AGENTS.md) に決まりと確認の手順があります。
