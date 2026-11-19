# 設計の根拠

Akashi の決まりが「なぜその形なのか」を、調べたことと出典つきでまとめます。
使い方は [入門](tutorial.md)、決まりの全部は [言語の決まり](reference.md) にあります。

もくじ

1. [今の言語の問題点と、Akashi の答え](#1-今の言語の問題点と-akashi-の答え)
2. [AI が書きやすく読みやすい言語とは](#2-ai-が書きやすく読みやすい言語とは)
3. [これまでに決めたことと根拠](#3-これまでに決めたことと根拠)
4. [説明書きの作り方](#4-説明書きの作り方)
5. [出典](#5-出典)

注意：ここに挙げた研究の数字は、それぞれの論文の条件での結果です。Akashi 自身の効果は、6問の小さな比べっこ（下の 2.6）しか測っていません。

---

## 1. 今の言語の問題点と、Akashi の答え

Python・JavaScript・Java・C/C++・Go・Rust などでよく問題になることを、「入れた」「入れなかった」に分けて並べます。
「入れた」は v0.5 までに処理系と検査で守っているもの、「入れなかった」は理由があって見送ったもの、または後回しにしたものです。

### 入れた

| 問題 | 起きやすい言語 | 何が起きるか（根拠） | Akashi の答え |
| --- | --- | --- | --- |
| null（値が無いこと）の見落とし | Java・C#・JavaScript・Python・Go | null を発明した Hoare 自身が「10億ドルの誤り」と呼んだ。値があるつもりで使って落ちる [1] | **null が無い**。無いかもしれない値は `Option[T]`（`Some` か `None`）で、`match` で `None` の場合を書かないと検査が通らない（E210）。`null` と書くと、`Option` を使うよう直し方を出す |
| 例外・エラーの見落とし | Java・Python・JavaScript・Go（`err` を無視できる） | 分散システムの重大な障害の 92% は、知らされていたエラーの扱い誤りが原因。その 3 分の 1 は「無視」「TODO のまま」など単純な誤り [2] | **例外が無い**。失敗しうる操作は `Result[T]`（`Ok` か `Err`）を返し、`Err` の場合も書かないと通らない。値を捨てる行も E201 で止まる（結果を無視できない）。ファイルが無いときの `read_text` も `Err` を返すようにした（R508 を廃止） |
| 場合分けの抜け・落ち | C・C++・Java（`switch` の break 忘れ、default 無し） | break を忘れた次の場合への落ち込み（CWE-484）、場合の抜け（CWE-478） [3][4] | `match` は**型のどの場合も1回ずつ**書く。落ち込みは無い。何でも受ける `else`・`_` も無い（E211）ので、あとで場合を足すと、直すべき `match` が全部エラーで見つかる |
| 暗黙の型変換 | JavaScript（`"1" + 1`）・C（整数の昇格）・PHP | 型が勝手に変わり、思わぬ値になる。JavaScript の実地調査では大半は無害だったが、誤りの元になる使い方も残っていた [5] | **変換しない**。`+` は Int だけ、文字をつなぐのは `++`、数を文字にするのは `to_str`。違う型どうしの比較も E201 |
| 整数のあふれ | C・C++（未定義動作）・Java・Go（黙って回る） | 計算があふれて小さな数や負の数になり、大きさの確かめをすり抜ける（CWE-190） [6] | あふれたら**止める**（R504）。黙って回らない |
| メモリの壊れ | C・C++ | 解放後の使用・範囲外の書き込み。NSA・CISA はメモリ安全な言語への移行を勧める [7] | ポインタ・解放・範囲外の読み書きが無い。リストの範囲外は `at` で `None`、`get` なら R506 で止まる |
| データの取り合い（並行の競合） | Go・Java・C++ | Go の実プロジェクトの並行バグ 171 件のうち、半分は止まる系（デッドロックなど）、半分は取り合い系。チャネルでも 58% の止まる系バグが起きていた [8] | **値を書きかえない・並行に動かさない**。名前は1回だけ決め、リストも新しいものを作る。取り合いが起きる場所が無い |
| 注入（SQL・HTML・eval） | どの言語でも（文字列をつないで作るとき） | CWE Top 25（2025）の1位 XSS・2位 SQL 注入・10位 コード注入 [9] | `Html`・`Sql` は**書いたままの型紙＋値**でしか作れない（E310・E311）。文字からコードを動かす `eval` は無い。くわしくは [安全の仕組み](security.md) |
| どこからでも外に触れる権利 | ほとんどの言語（どの関数もファイルや通信を使える） | 依存した部品が乗っ取られると、その部品も全部の権利を持つ。CWE Top 25 の「認可の抜け」「パスの乗っ取り」 [9][10] | 外に触る権利は**鍵（Console・Folder）を引数で渡したときだけ**。鍵は main だけが受け取り、作れない・しまえない（E300・E309）。ファイルは渡したフォルダの中だけ（R507） |
| リンクで決めた場所の外へ出る | どの言語でも（ファイルを開く関数がリンクをたどる）。WASI の実装にも、外へたどれるものがある | Node の node:wasi は「ファイルの sandbox を備えず、抜けられる」と公式に書いている [27]。Akashi でも v0.12 まで、node:wasi の上では段の途中のリンクで外を読めた | リンクは中を指していてもたどらない（R507）。読む鍵 Folder と書く鍵 OutFolder を分ける。コンパイルしたプログラムは、実行する側の sandbox に頼らず、開ける前に段ごとにリンクを調べる |
| 浮動小数点の誤差 | ほぼ全部（`0.1 + 0.2 != 0.3`） | 2進の小数は 0.1 を正確に表せない [11] | 小数は**まだ無い**（E101）。お金などは「円」「銭」の整数で書く。入れるなら2進でなく10進の小数にする（下の「入れなかった」） |
| 文字の長さの数え違い | JavaScript・Java（UTF-16 の単位で数える） | 絵文字などは `length` が 2 になる [12] | `str_len`・`chars`・`slice`・`code_of` は、どれも文字（コードポイント）で数える。バイトや UTF-16 の位置は表に出さないので、絵文字の途中で切ることが無い。範囲の外は黙って縮めずに R506 で止める |
| 辞書の回る順のぶれ | Go（map）・Python 3.6 より前の dict | Go の仕様は「map を回る順は決めず、回すたびに同じとも限らない」とする [26]。出力やテストが実行ごとに変わる | `Dict` の鍵は Str だけ。いつも鍵の順（コードポイント順）に並ぶので、`dict_keys`・表示・`==` は毎回同じ。同じ鍵を2回渡す `dict` は黙って上書きせず R506 |
| 演算の強さの思い込み | C・JavaScript・Python | `a and b or c` や `0 < x < 10` の読み違い | `and` と `or` を混ぜるときは括弧（E105）、比較はつなげない（E106） |
| 名前の上書き・取り違え | JavaScript（`var`）・Python | 同じ名前を別の意味で使い直して取り違える | 名前は1回だけ（E203）。引数は名前つき・宣言の順（E206・E207） |

### 入れなかった（見送った・後回し）

| 問題・仕組み | 起きやすい言語 | 入れなかった理由 |
| --- | --- | --- |
| 依存の乗っ取り（サプライチェーン） | npm・PyPI・C の配布物（xz の裏口 [13]） | 処理系そのものは**依存ゼロ**にし、テストで守る（[使う道具の決まり](security.md#使う道具の決まり脆弱なものは使わない)）。言語の側には**まだ部品（モジュール）の仕組みが無い**ので、入れる場所が無い。入れるときは「部品は中身の指紋（ハッシュ）で固定する」「部品には鍵を明示して渡す（勝手に外に触れない）」の2つを必ず入れる。今でも鍵の仕組みで、部品が持てる権利は渡したものだけになる |
| 並行処理（スレッド・チャネル） | Go・Java・Rust | 並行処理はまだ入れない。上の Go の調査で、チャネルでも止まる系のバグが多かった [8] ので、入れるなら「始めた処理は必ず同じ範囲で終わる」形（構造化並行）にする |
| 例外（try / catch） | Java・Python・JavaScript | 見落としやすい（[2]）ので**入れない**と決めた。`Result` と `match` に一本化 |
| 何でも受ける場合分け（`else`・`_`） | Rust・Swift・Scala（使える） | 書くのは楽だが、あとで場合を足したときに抜けが見えなくなるので**入れない**と決めた |
| 10進の小数（Decimal） | — | 必要になったら入れる。2進の浮動小数点は入れない予定 |
| 自分で作る型の型引数（`Tree[T]` など） | — | 後回し。組み込みの `Option[T]`・`Result[T]` だけ型引数を持てる |
| 欄を名前で取り出す（`p.x`） | — | 後回し。今は `match` で取り出す。書き方を1つにしておくため、入れるなら名前つきの関数の形にする |
| 漸進的な型（型を書かなくてもよい） | Python・TypeScript | **入れない**。型を書かせるほうが AI の誤りが減る（[14]） |
| マクロ・演算子の上書き | C・C++・Rust・Python | **入れない**。同じことに書き方が何通りもできると、AI も人も読み違えるため |
| 文字の正規化（「が」と「か＋゛」を同じに扱う） | — | 後回し |
| URL 属性（`href`・`src`）の検査 | — | 後回し。今は `javascript:` の URL を入れられてしまうので、外から来た値を URL 属性に入れない（[安全の仕組み](security.md)） |
| 長い処理の打ち切り（時間・メモリ） | — | 再帰の深さ（500）とリストの大きさ（100万）だけ。時間の上限は後回し |

---

## 2. AI が書きやすく読みやすい言語とは

### 2.1 わかったこと

| 調べたこと | わかったこと | 出典 |
| --- | --- | --- |
| 学習データの量 | 公開コードの集まり（The Stack）で Python は約 64GB、OCaml は約 1GB、Racket は約 0.5GB。データが少ない言語は、そのまま学習を長くしてもほとんど伸びなかった。テストで確かめた変換データを足すと、OCaml の1回正解率が 6.9% から 19.9% に上がった | [15] |
| なじみの薄い言語での AI の動き | 同じ問題でも、OCaml では Python の 1.28〜1.69 倍の出力トークンを使った。増えた分はコードの長さではなく、同じ失敗のくり返し（堂々めぐり）と、Python で試してから書き直す動きだった | [16] |
| AI が書いたコードの誤りの種類 | 一番多いのは文法でなく**中身の誤り**。中身の誤りのうち一番多いのは「端の場合の確かめ忘れ」（HumanEval+ で 54.4%）。実行時の誤りで多いのは関数の使い方の誤り（型の取り違えなど） | [17] |
| 整形にかかるトークン | 字下げ・空白・改行を取りのぞくと、入力のトークンが平均 24.5% 減り、正解率はほぼ変わらなかった。字下げに意味がある Python では 6.5% しか減らない | [18] |
| エラー文の書き方 | GPT-4 が書きなおしたエラー説明は、初心者の直す速さを 6 問中 1 問でしか上げなかった。人が手で書いた説明は 5 問で速かった。好まれることと、役に立つことは別だった | [19] |
| 型で絞って書かせる | 型に合わない書き方を出力の途中で止めると、コンパイルエラーが半分以下になり、正しさも上がった | [14] |
| 範囲を絞った言語 | 範囲を絞った言語は、初めて見るモデルでも説明を読むだけで書け、複数手順の課題で Python より正しかった（作者自身の測定） | [20] |

### 2.2 Akashi に入れたこと

| わかったこと | Akashi に入れたこと |
| --- | --- |
| 学習データが無い言語は、説明を文脈に入れないと書けない | 英語の短い仕様 [SPEC.md](SPEC.md) を、AI のプロンプトに貼れる長さに保つ。`akashi spec` で表示できる。リポジトリの入口に、AI 向けの案内 [`llms.txt`](../llms.txt) を置いた（llms.txt の提案 [21] の形） |
| なじみの薄い言語では堂々めぐりが起きる | 言葉はよく使われる言語からそのまま借りる（`fn`・`let`・`if`・`match`・`case`・`Some`・`None`・`Ok`・`Err`）。エラーには「次にどう書けば通るか」を、そのまま貼れるコードで出す（例：`add case Yellow then <value>`）。同じ誤りに同じ番号を出し、番号の意味は変えない |
| 端の場合の確かめ忘れが一番多い | `match` は全部の場合を書かないと通らない。`ensures` を、自動で作った数百の入力で毎回試し、破れた入力を一番小さい形で見せる（R511）。v0.5 から、自分で作る型の値も自動で作る |
| 関数の使い方の誤りが多い | 引数は名前つき・宣言の順。型は実行前に全部確かめる |
| 整形のトークンは削れる | Akashi の字下げには意味が無いので、AI に読ませるときは整形を取りのぞいてよい（意味は変わらない） |
| AI が書きなおしたエラー文は役に立たないことがある | エラーの直し方は、番号ごとに**人が書いて**テストで確かめる（`examples/bad/` の見本と [ERRORS.md](ERRORS.md)）。AI に言いかえさせない |
| 型で絞ると誤りが減る | 型を必ず書く。漸進的な型にはしない |

### 2.3 入れなかったこと

| 案 | 理由 |
| --- | --- |
| 記号を減らしてトークンをもっと減らす（`fn` を記号にするなど） | なじみが減ると、上の堂々めぐりが増える。トークンの節約より、読み違えないことを取った |
| 引数の名前を省けるようにする | トークンは減るが、同じ型の引数の取り違えが型検査で見つからなくなる |
| AI にエラー文を言いかえさせる | 上の [19] のとおり、速く直せるとは限らない |

### 2.4 まだ弱いところ

- 学習データが無いことは、仕様を貼っても完全には埋まらない。6問の比べっこで、1回で正解したのは Akashi 4問、Python 5問だった（v0.4、小さいモデル）。
- 名前つきの引数や `ensures` で、同じ処理でも Python より長くなる（トークンが増える）。

---

## 3. これまでに決めたことと根拠

| 決めたこと | 根拠 |
| --- | --- |
| 型を必ず書き、実行前に検査する | 型で絞ると LLM のコンパイルエラーが半分以下になった [14] |
| できることを絞り、書き方を1つにする（ループ無し・暗黙の変換無し・名前の再利用無し） | 範囲を絞った言語は、初めて見るモデルでも説明だけで書けた [20] |
| 約束（requires・ensures・example）を必須にし、エラーに決まった番号と直し方を付ける | LLM 向けの言語 Vera が、契約の必須化と番号つきの直し方を JSON で返す作りで、初見のモデルが正しく書けたと報告 [22] |
| 外に触る権利は鍵として引数で渡す | 渡された鍵でしか外に触れない WASI の作り [10] |
| HTML・SQL は型紙＋値だけ | 安全な部品しか使えないようにする Google の Safe Coding [23] |
| check のたびに、自動で作った入力で ensures を試す | 契約を答え合わせに使う乱数テストは、人の書いたテストで見つからない誤りを見つける [24] |
| 場合分けは `when` で end 1つ | 小さい AI での比べっこで、入れ子の if の end の数え間違いが2問あった |
| null・例外の代わりに `Option`・`Result` と漏れの無い `match` | 上の 1 の表（[1][2][3][4]） |

---

## 4. 説明書きの作り方

説明書きは **Diátaxis**（ダイアタクシス）の考え方で分けました。読む人の目的によって、文書を4種類に分けます [25]。

| 種類 | 目的 | Akashi の文書 |
| --- | --- | --- |
| チュートリアル（学ぶ） | 手を動かしながら覚える | [入門](tutorial.md) |
| ハウツー（する） | 決まった作業をやりとげる | [やり方集](howto.md) |
| リファレンス（調べる） | 正確な決まりを引く | [言語の決まり](reference.md)・[エラー番号の一覧](ERRORS.md)・[AI に貼る仕様](SPEC.md) |
| 解説（わかる） | なぜそうなっているかを理解する | [安全の仕組み](security.md)・[コンパイラ](compiler.md)・この文書 |

ほかに決めたこと：

- 日本語を主にする。AI に貼る仕様（SPEC.md）とエラー文は英語にする（学習データの多い言葉で、短く書けるため）。
- 説明書きの中の ```` ```akashi ```` のコードは、テストが全部 `akashi check` に通す。説明書きが古くなると落ちる。
- エラー番号の一覧は、見本（`examples/bad/`）から作り直す。手で直さない。

---

## 5. 出典

1. Tony Hoare, "Null References: The Billion Dollar Mistake", QCon London 2009. https://www.infoq.com/presentations/Null-References-The-Billion-Dollar-Mistake-Tony-Hoare/
2. Ding Yuan ほか, "Simple Testing Can Prevent Most Critical Failures", OSDI 2014（解説：https://blog.acolyer.org/2016/10/06/simple-testing-can-prevent-most-critical-failures/ ）。https://www.usenix.org/conference/osdi14/technical-sessions/presentation/yuan
3. CWE-484: Omitted Break Statement in Switch. https://cwe.mitre.org/data/definitions/484.html
4. CWE-478: Missing Default Case in Multiple Condition Expression. https://cwe.mitre.org/data/definitions/478.html
5. Michael Pradel, Koushik Sen, "The Good, the Bad, and the Ugly: An Empirical Study of Implicit Type Conversions in JavaScript", ECOOP 2015. https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ECOOP.2015.519
6. CWE-190: Integer Overflow or Wraparound. https://cwe.mitre.org/data/definitions/190.html
7. CISA ほか, "Memory Safe Languages: Reducing Vulnerabilities in Modern Software Development". https://www.cisa.gov/resources-tools/resources/memory-safe-languages-reducing-vulnerabilities-modern-software-development
8. Tengfei Tu ほか, "Understanding Real-World Concurrency Bugs in Go", ASPLOS 2019（解説：https://blog.acolyer.org/2019/05/17/understanding-real-world-concurrency-bugs-in-go/ ）
9. CWE Top 25 Most Dangerous Software Weaknesses (2025). https://cwe.mitre.org/top25/archive/2025/2025_cwe_top25.html
10. WASI Design Principles. https://github.com/WebAssembly/WASI/blob/main/docs/DesignPrinciples.md
11. Python Tutorial, "Floating-Point Arithmetic: Issues and Limitations". https://docs.python.org/3/tutorial/floatingpoint.html
12. MDN, "String: length". https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/length
13. CVE-2024-3094（xz の裏口）. https://nvd.nist.gov/vuln/detail/CVE-2024-3094
14. Niels Mündler ほか, "Type-Constrained Code Generation with Language Models", PLDI 2025. https://arxiv.org/abs/2504.09246
15. Federico Cassano ほか, "Knowledge Transfer from High-Resource to Low-Resource Programming Languages for Code LLMs"（MultiPL-T）. https://arxiv.org/abs/2308.09895
16. "Tokenmaxxing"（言語ごとのコーディングエージェントの動きとトークン）. https://arxiv.org/abs/2607.22807
17. Shihan Dou ほか, "What's Wrong with Your Code Generated by Large Language Models?". https://arxiv.org/abs/2407.06153
18. "The Hidden Cost of Readability: How Code Formatting Silently Consumes Your LLM Budget". https://arxiv.org/abs/2508.13666
19. Eddie Antonio Santos, Brett A. Becker, "Not the Silver Bullet: LLM-enhanced Programming Error Messages are Ineffective in Practice". https://arxiv.org/abs/2409.18661
20. Anka. https://arxiv.org/abs/2512.23214
21. Jeremy Howard, "/llms.txt — a proposal to provide information to help LLMs use websites", Answer.AI, 2024. https://answer.ai/posts/2024-09-03-llmstxt
22. Vera. https://github.com/aallan/vera
23. Google Research, "Safe Coding: Rigorous Modular Reasoning about Software Safety". https://research.google/pubs/safe-coding-rigorous-modular-reasoning-about-software-safety-extended-version/
24. Yi Wei, Carlo A. Furia, Bertrand Meyer ほか, "The Search for the Laws of Automatic Random Testing". https://arxiv.org/abs/1211.3257
25. Diátaxis（Daniele Procida）. https://diataxis.fr/ ／ Canonical での採用：https://ubuntu.com/blog/diataxis-a-new-foundation-for-canonical-documentation
26. The Go Programming Language Specification, "For statements with range clause". https://go.dev/ref/spec#For_range
27. Node.js v22 documentation, "WASI" (Security). https://nodejs.org/docs/latest-v22.x/api/wasi.html
