# Akashi（あかし）

AI（LLM）が書きやすく、間違えにくく、間違えても自分で直しやすいように作った、小さなプログラミング言語の試作です。
名前は「証（あかし）」から。関数ごとに「約束（ensures）」と「見本（example）」を書き、処理系がそれを確かめます。

```
fn gcd(a: Int, b: Int) -> Int
  requires a >= 0 and b >= 0
  ensures result >= 0
  example gcd(a: 12, b: 18) == 6
do
  if b == 0 then a else gcd(a: b, b: a % b) end
end
```

## 使い方

Node.js 22 だけで動きます（入れるものはありません）。

```bash
node bin/akashi.js check examples/gcd.ak          # 型・名前・副作用・約束の検査と、全部の example
node bin/akashi.js run examples/fizzbuzz.ak       # 検査が通ったら main を動かす
node bin/akashi.js run examples/read_file.ak --allow-read examples/files   # 読んでよいフォルダを1つだけ渡す
node bin/akashi.js check examples/bad/e206-positional.ak --json   # エラーを JSON で（AI が読む用）
npm test
```

言語の説明は [docs/SPEC.md](docs/SPEC.md)（AI に貼る用。英語で短く）、エラーの一覧は [docs/ERRORS.md](docs/ERRORS.md)。

## なぜこの形か（調べたことと出典）

| 決めたこと | 根拠 |
| --- | --- |
| 型を必ず書き、実行前に検査する | 型で絞ると LLM のコンパイルエラーが半分以下になり、正しさも上がった（[Type-Constrained Code Generation, Mündler ら, PLDI 2025](https://arxiv.org/abs/2504.09246)） |
| できることを絞り、書き方を1つにする（ループ無し・暗黙の変換無し・名前の再利用無し） | 範囲を絞った言語は、初めて見るモデルでも説明だけで覚え、複数手順の課題で Python より大きく正しかった（[Anka, arXiv 2512.23214](https://arxiv.org/abs/2512.23214)） |
| 約束（requires・ensures）と副作用（effects）を必須にし、エラーに決まった番号と直し方を付ける | LLM 向けに作られた言語 [Vera](https://github.com/aallan/vera) が、契約の必須化・副作用の宣言・番号つきの直し方を JSON で返す作りで、初見のモデルが正しく書けたと報告 |
| 外に触る権利（画面・ファイル）は「鍵」として引数で渡す。鍵は main だけが受け取り、作ることも保存することもできない。ファイルは渡したフォルダの中だけ読める | 外の物は渡された鍵（ハンドル）でしか触れず、どこからでも触れる権利を持たせない、という WASI の作り（[WASI Design Principles](https://github.com/WebAssembly/WASI/blob/main/docs/DesignPrinciples.md)）。CWE Top 25（2025）の4位「認可の抜け」・6位「パスの乗っ取り」を言語の仕組みで減らす（[CWE Top 25](https://cwe.mitre.org/top25/archive/2025/2025_cwe_top25.html)） |
| HTML と SQL は「書いたままの型紙＋差し込む値」でしか作れない。外から来た文字は自動でエスケープ（HTML）か、文と別の値（SQL）になり、形を変えられない。文字からコードを動かす eval は無い | CWE Top 25（2025）の1位 XSS・2位 SQL 注入・10位 コード注入。型で安全な部品だけを使わせる Google の「Safe Coding」の考え方（[Safe Coding, Google Research](https://research.google/pubs/safe-coding-rigorous-modular-reasoning-about-software-safety-extended-version/)） |
| メモリを直接触る仕組み（ポインタ・null・解放）を持たない | NSA・CISA がメモリ安全な言語への移行を勧めている（[CISA の手引き](https://www.cisa.gov/resources-tools/resources/memory-safe-languages-reducing-vulnerabilities-modern-software-development)） |
| check のたびに、純粋な関数へ自動で作った入力を何百も渡し、requires を満たすのに ensures が破れる・落ちる入力を、いちばん小さい形で見せる | 契約（requires・ensures）を答え合わせに使う自動の乱数テストは、人が書いたテストで見つからない誤りを見つける（[Wei・Furia・Meyer ら, The Search for the Laws of Automatic Random Testing](https://arxiv.org/abs/1211.3257)）。性質で試す QuickCheck と同じ考え方 |
| 場合分けは `when` で end 1つ | 小さい AI での比べっこで、入れ子の if の end の数え間違いが2問あった |
| 引数は必ず名前つき・宣言の順 | 引数の取り違えは型が同じだと型検査で見つからないため（Akashi 独自の工夫。効果はまだ測っていない） |
| `and` と `or` を混ぜるときは括弧、比較はつなげない | 演算の強さの思い込みによる書き間違いを、文法で止める（同上） |

注意：Anka と Vera の数字は作者自身の測定です。Akashi の効果はまだ測っていません。

## 今の状態（v0.4）

- できる：Int・Bool・Str・List、関数・再帰、if、map・filter・fold、約束の検査、example の自動実行、エラーの JSON 出力、権利の鍵（Console・Folder）、注入できない HTML・SQL の組み立て、when、自動で作った入力での約束の試し。
- まだ無い：自分で作る型（レコード・列挙）、小数、ファイルや通信、モジュール。
- 次にやるとよいこと：同じ課題を Akashi と Python で AI に書かせ、1回で通る割合と、直すまでの回数を比べる。
