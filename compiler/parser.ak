# Akashi の構文解析を Akashi で書いたもの（セルフホストの段階5）。src/parse.js の parse と同じ木を作る。
# 木はどこも Node 1つの形（種類・文字・位置・子）。種類の一覧は docs/compiler.md「構文解析の木」。
# くり返し（引数の並び・ブロックの行など）は再帰でなく fold で回す（深さ 500 の上限があるため）。
#   回す数を 4・8・16… と倍にしていき、終わったあとの回は何もしない。再帰の深さは入れ子の深さだけになる。
# 失敗は最初の1つで止め、"E100 行:列 説明" の形で返す（src/parse.js と同じ番号・位置・説明）。
use "lexer.ak"

type Node
  case Node(kind: Str, text: Str, line: Int, col: Int, kids: List[Node])
end

# 読む材料：字句の並び（最後に eof）・自分で作った型の名前（このファイルと use で読んだファイル）・元の文の行（約束の文を切り出すため）
type Ps
  case Ps(toks: List[Token], user: List[Str], lines: List[Str])
end

# 1つ読んだ結果：木・次に読む字句の番号・失敗（"" なら成功）
type Parsed
  case Parsed(node: Node, pos: Int, err: Str)
end

# くり返しの途中。kind で何を読むかを分ける。stop はブロックを終える言葉や、続ける記号の表（空白で区切る）
type Loop
  case Loop(ps: Ps, kind: Str, pos: Int, items: List[Node], done: Bool, err: Str, stop: Str)
end

# ---- 字句を見る ----

fn eof_token() -> Token
  ensures true
  example eof_token() == Token(kind: "eof", text: "", line: 1, col: 1, end_col: 1)
do
  Token(kind: "eof", text: "", line: 1, col: 1, end_col: 1)
end

fn toks_of(ps: Ps) -> List[Token]
  ensures true
  example len(list: toks_of(ps: ps_of(text: "a b"))) == 3
do
  match ps
    case Ps(toks: ts, user: _, lines: _) then ts
  end
end

# i 番目の字句。範囲の外なら最後の字句（eof）
fn tok(ps: Ps, i: Int) -> Token
  ensures true
  example t_kind(t: tok(ps: ps_of(text: "x"), i: 9)) == "eof"
  example t_text(t: tok(ps: ps_of(text: "x"), i: 0)) == "x"
do
  let ts: List[Token] = toks_of(ps: ps)
  let n: Int = len(list: ts)
  match at(list: ts, index: if i < n then i else n - 1 end)
    case Some(value: t) then t
    case None then eof_token()
  end
end

fn t_kind(t: Token) -> Str
  ensures true
  example t_kind(t: eof_token()) == "eof"
do
  match t
    case Token(kind: k, text: _, line: _, col: _, end_col: _) then k
  end
end

fn t_text(t: Token) -> Str
  ensures true
  example t_text(t: Token(kind: "id", text: "x", line: 1, col: 1, end_col: 2)) == "x"
do
  match t
    case Token(kind: _, text: x, line: _, col: _, end_col: _) then x
  end
end

fn t_line(t: Token) -> Int
  ensures true
  example t_line(t: Token(kind: "id", text: "x", line: 3, col: 1, end_col: 2)) == 3
do
  match t
    case Token(kind: _, text: _, line: l, col: _, end_col: _) then l
  end
end

fn t_col(t: Token) -> Int
  ensures true
  example t_col(t: Token(kind: "id", text: "x", line: 3, col: 4, end_col: 5)) == 4
do
  match t
    case Token(kind: _, text: _, line: _, col: c, end_col: _) then c
  end
end

fn t_end(t: Token) -> Int
  ensures true
  example t_end(t: Token(kind: "id", text: "x", line: 3, col: 4, end_col: 5)) == 5
do
  match t
    case Token(kind: _, text: _, line: _, col: _, end_col: e) then e
  end
end

fn is_kind(ps: Ps, pos: Int, kind: Str) -> Bool
  ensures true
  example is_kind(ps: ps_of(text: "x"), pos: 0, kind: "id")
do
  t_kind(t: tok(ps: ps, i: pos)) == kind
end

fn is_op(ps: Ps, pos: Int, v: Str) -> Bool
  ensures true
  example is_op(ps: ps_of(text: "( x"), pos: 0, v: "(")
  example not is_op(ps: ps_of(text: "\"(\""), pos: 0, v: "(")
do
  is_kind(ps: ps, pos: pos, kind: "op") and t_text(t: tok(ps: ps, i: pos)) == v
end

fn is_kw(ps: Ps, pos: Int, v: Str) -> Bool
  ensures true
  example is_kw(ps: ps_of(text: "end"), pos: 0, v: "end")
do
  is_kind(ps: ps, pos: pos, kind: "kw") and t_text(t: tok(ps: ps, i: pos)) == v
end

# 記号か言葉で、表（" + - "）にあるもの
fn is_one_of(ps: Ps, pos: Int, table: Str) -> Bool
  ensures true
  example is_one_of(ps: ps_of(text: "a + b"), pos: 1, table: " + - ")
  example not is_one_of(ps: ps_of(text: "\"+\""), pos: 0, table: " + - ")
do
  let k: Str = t_kind(t: tok(ps: ps, i: pos))
  (k == "op" or k == "kw") and in_table(table: table, word: t_text(t: tok(ps: ps, i: pos)))
end

# ---- 木を作る ----

fn node(kind: Str, text: Str, t: Token, kids: List[Node]) -> Node
  ensures true
  example node(kind: "var", text: "x", t: eof_token(), kids: []) == Node(kind: "var", text: "x", line: 1, col: 1, kids: [])
do
  Node(kind: kind, text: text, line: t_line(t: t), col: t_col(t: t), kids: kids)
end

# 位置の無いもの（型・ブロック・約束の文など）
fn bare(kind: Str, text: Str, kids: List[Node]) -> Node
  ensures true
  example bare(kind: "block", text: "", kids: []) == Node(kind: "block", text: "", line: 0, col: 0, kids: [])
do
  Node(kind: kind, text: text, line: 0, col: 0, kids: kids)
end

fn n_kind(n: Node) -> Str
  ensures true
  example n_kind(n: bare(kind: "t", text: "Int", kids: [])) == "t"
do
  match n
    case Node(kind: k, text: _, line: _, col: _, kids: _) then k
  end
end

fn n_text(n: Node) -> Str
  ensures true
  example n_text(n: bare(kind: "t", text: "Int", kids: [])) == "Int"
do
  match n
    case Node(kind: _, text: x, line: _, col: _, kids: _) then x
  end
end

fn n_kids(n: Node) -> List[Node]
  ensures true
  example n_kids(n: bare(kind: "t", text: "List", kids: [bare(kind: "t", text: "Int", kids: [])])) == [bare(kind: "t", text: "Int", kids: [])]
do
  match n
    case Node(kind: _, text: _, line: _, col: _, kids: ks) then ks
  end
end

fn first_kid(n: Node) -> Node
  ensures true
  example first_kid(n: bare(kind: "x", text: "", kids: [])) == bare(kind: "none", text: "", kids: [])
do
  match at(list: n_kids(n: n), index: 0)
    case Some(value: k) then k
    case None then bare(kind: "none", text: "", kids: [])
  end
end

# ---- 読んだ結果 ----

fn ok(n: Node, pos: Int) -> Parsed
  ensures true
  example ok(n: bare(kind: "unit", text: "", kids: []), pos: 1) == Parsed(node: bare(kind: "unit", text: "", kids: []), pos: 1, err: "")
do
  Parsed(node: n, pos: pos, err: "")
end

fn r_node(r: Parsed) -> Node
  ensures true
  example n_kind(n: r_node(r: ok(n: bare(kind: "unit", text: "", kids: []), pos: 1))) == "unit"
do
  match r
    case Parsed(node: n, pos: _, err: _) then n
  end
end

fn r_at(r: Parsed) -> Int
  ensures true
  example r_at(r: ok(n: bare(kind: "unit", text: "", kids: []), pos: 1)) == 1
do
  match r
    case Parsed(node: _, pos: a, err: _) then a
  end
end

fn r_err(r: Parsed) -> Str
  ensures true
  example r_err(r: ok(n: bare(kind: "unit", text: "", kids: []), pos: 1)) == ""
do
  match r
    case Parsed(node: _, pos: _, err: e) then e
  end
end

fn bad(r: Parsed) -> Bool
  ensures true
  example not bad(r: ok(n: bare(kind: "unit", text: "", kids: []), pos: 1))
do
  r_err(r: r) != ""
end

# 失敗を、その字句の位置で作る
fn fail_tok(t: Token, code: Str, message: Str) -> Parsed
  ensures true
  example r_err(r: fail_tok(t: eof_token(), code: "E107", message: "x")) == "E107 1:1 x"
do
  Parsed(node: bare(kind: "none", text: "", kids: []), pos: 0, err: code ++ " " ++ to_str(value: t_line(t: t)) ++ ":" ++ to_str(value: t_col(t: t)) ++ " " ++ message)
end

fn show_tok(t: Token) -> Str
  ensures true
  example show_tok(t: eof_token()) == "end of file"
  example show_tok(t: Token(kind: "str", text: "a", line: 1, col: 1, end_col: 4)) == "\"a\""
  example show_tok(t: Token(kind: "op", text: ")", line: 1, col: 1, end_col: 2)) == "')'"
do
  when
    t_kind(t: t) == "eof" then "end of file"
    t_kind(t: t) == "str" then "\"" ++ t_text(t: t) ++ "\""
    else "'" ++ t_text(t: t) ++ "'"
  end
end

# 「expected ～ but found ～」の失敗
fn expected(ps: Ps, pos: Int, what: Str, code: Str) -> Parsed
  ensures true
  example r_err(r: expected(ps: ps_of(text: "x"), pos: 0, what: "'('", code: "E100")) == "E100 1:1 expected '(' but found 'x'"
do
  let t: Token = tok(ps: ps, i: pos)
  fail_tok(t: t, code: code, message: "expected " ++ what ++ " but found " ++ show_tok(t: t))
end

fn expect_op(ps: Ps, pos: Int, v: Str) -> Parsed
  ensures true
  example r_at(r: expect_op(ps: ps_of(text: ")"), pos: 0, v: ")")) == 1
  example bad(r: expect_op(ps: ps_of(text: "x"), pos: 0, v: ")"))
do
  if is_op(ps: ps, pos: pos, v: v) then ok(n: bare(kind: "none", text: "", kids: []), pos: pos + 1) else expected(ps: ps, pos: pos, what: "'" ++ v ++ "'", code: "E100") end
end

fn expect_kw(ps: Ps, pos: Int, v: Str) -> Parsed
  ensures true
  example r_at(r: expect_kw(ps: ps_of(text: "end"), pos: 0, v: "end")) == 1
do
  if is_kw(ps: ps, pos: pos, v: v) then ok(n: bare(kind: "none", text: "", kids: []), pos: pos + 1) else expected(ps: ps, pos: pos, what: "'" ++ v ++ "'", code: "E100") end
end

# 名前を1つ読む（木は "name"）
fn expect_id(ps: Ps, pos: Int, what: Str) -> Parsed
  ensures true
  example r_node(r: expect_id(ps: ps_of(text: "x"), pos: 0, what: "a name")) == Node(kind: "name", text: "x", line: 1, col: 1, kids: [])
  example r_err(r: expect_id(ps: ps_of(text: "end"), pos: 0, what: "a name")) == "E100 1:1 expected a name but found 'end'"
do
  let t: Token = tok(ps: ps, i: pos)
  if t_kind(t: t) == "id" then ok(n: node(kind: "name", text: t_text(t: t), t: t, kids: []), pos: pos + 1) else expected(ps: ps, pos: pos, what: what, code: "E100") end
end

fn is_upper(word: Str) -> Bool
  ensures true
  example is_upper(word: "Shape")
  example not is_upper(word: "shape")
do
  word != "" and contains(text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ", part: slice(text: word, from: 0, to: 1))
end

# ---- くり返し ----

fn loop_new(ps: Ps, kind: Str, pos: Int, stop: Str) -> Loop
  ensures true
  example l_at(st: loop_new(ps: ps_of(text: ""), kind: "args", pos: 2, stop: "")) == 2
do
  Loop(ps: ps, kind: kind, pos: pos, items: [], done: false, err: "", stop: stop)
end

fn l_at(st: Loop) -> Int
  ensures true
  example l_at(st: loop_new(ps: ps_of(text: ""), kind: "args", pos: 2, stop: "")) == 2
do
  match st
    case Loop(ps: _, kind: _, pos: a, items: _, done: _, err: _, stop: _) then a
  end
end

fn l_items(st: Loop) -> List[Node]
  ensures true
  example l_items(st: loop_new(ps: ps_of(text: ""), kind: "args", pos: 2, stop: "")) == []
do
  match st
    case Loop(ps: _, kind: _, pos: _, items: xs, done: _, err: _, stop: _) then xs
  end
end

fn l_err(st: Loop) -> Str
  ensures true
  example l_err(st: loop_new(ps: ps_of(text: ""), kind: "args", pos: 2, stop: "")) == ""
do
  match st
    case Loop(ps: _, kind: _, pos: _, items: _, done: _, err: e, stop: _) then e
  end
end

fn is_over(st: Loop) -> Bool
  ensures true
  example not is_over(st: loop_new(ps: ps_of(text: ""), kind: "args", pos: 2, stop: ""))
do
  match st
    case Loop(ps: _, kind: _, pos: _, items: _, done: d, err: e, stop: _) then d or e != ""
  end
end

# 位置・集めたもの・終わったか・失敗を変える
fn l_set(st: Loop, pos: Int, items: List[Node], done: Bool, err: Str) -> Loop
  ensures true
  example is_over(st: l_set(st: loop_new(ps: ps_of(text: ""), kind: "args", pos: 0, stop: ""), pos: 1, items: [], done: true, err: ""))
do
  match st
    case Loop(ps: ps, kind: k, pos: _, items: _, done: _, err: _, stop: s) then Loop(ps: ps, kind: k, pos: pos, items: items, done: done, err: err, stop: s)
  end
end

fn l_done(st: Loop) -> Loop
  ensures true
  example is_over(st: l_done(st: loop_new(ps: ps_of(text: ""), kind: "args", pos: 0, stop: "")))
do
  l_set(st: st, pos: l_at(st: st), items: l_items(st: st), done: true, err: "")
end

# 読んだものを足して進む（失敗ならそこで止める）
fn l_push(st: Loop, r: Parsed) -> Loop
  ensures true
  example l_at(st: l_push(st: loop_new(ps: ps_of(text: ""), kind: "args", pos: 0, stop: ""), r: ok(n: bare(kind: "unit", text: "", kids: []), pos: 3))) == 3
do
  if bad(r: r) then l_set(st: st, pos: l_at(st: st), items: l_items(st: st), done: true, err: r_err(r: r)) else l_set(st: st, pos: r_at(r: r), items: append(list: l_items(st: st), item: r_node(r: r)), done: false, err: "") end
end

# , で区切った並び：足したあと、, があれば続け、無ければ終わる
fn l_push_sep(st: Loop, ps: Ps, r: Parsed) -> Loop
  ensures true
  example l_at(st: l_push_sep(st: loop_new(ps: ps_of(text: "x , y"), kind: "args", pos: 0, stop: ""), ps: ps_of(text: "x , y"), r: ok(n: bare(kind: "unit", text: "", kids: []), pos: 1))) == 2
do
  let pushed: Loop = l_push(st: st, r: r)
  when
    is_over(st: pushed) then pushed
    is_op(ps: ps, pos: l_at(st: pushed), v: ",") then l_set(st: pushed, pos: l_at(st: pushed) + 1, items: l_items(st: pushed), done: false, err: "")
    else l_done(st: pushed)
  end
end

# 1回ぶん（fold の func）。終わっていれば何もしない
fn loop_step(st: Loop, i: Int) -> Loop
  ensures true
  example is_over(st: loop_step(st: l_done(st: loop_new(ps: ps_of(text: ""), kind: "args", pos: 0, stop: "")), i: 0))
do
  if is_over(st: st) then st else loop_one(st: st) end
end

# 終わるまで回す。回す数を倍にしていく（再帰の深さは並びの長さの log）
fn run_loop(st: Loop, size: Int) -> Loop
  requires size >= 1
  ensures true
  example len(list: l_items(st: run_loop(st: loop_new(ps: ps_of(text: "a, b, c, d, e, f"), kind: "items_e", pos: 0, stop: ""), size: 1))) == 6
do
  let after: Loop = fold(list: range(from: 0, to: size), init: st, func: loop_step)
  if is_over(st: after) then after else run_loop(st: after, size: size * 2) end
end

# くり返しを回して、集めたものを kind の木にする
fn many(ps: Ps, kind: Str, pos: Int, stop: Str, wrap: Str) -> Parsed
  ensures true
  example n_kids(n: r_node(r: many(ps: ps_of(text: "1, 2)"), kind: "items_e", pos: 0, stop: "", wrap: "list"))) == [Node(kind: "int", text: "1", line: 1, col: 1, kids: []), Node(kind: "int", text: "2", line: 1, col: 4, kids: [])]
do
  let st: Loop = run_loop(st: loop_new(ps: ps, kind: kind, pos: pos, stop: stop), size: 4)
  if l_err(st: st) != "" then Parsed(node: bare(kind: "none", text: "", kids: []), pos: l_at(st: st), err: l_err(st: st)) else ok(n: bare(kind: wrap, text: "", kids: l_items(st: st)), pos: l_at(st: st)) end
end

# kind ごとの1回ぶん
fn loop_one(st: Loop) -> Loop
  ensures true
  example l_err(st: loop_one(st: loop_new(ps: ps_of(text: ""), kind: "nope", pos: 0, stop: ""))) == "internal: unknown loop nope"
do
  match st
    case Loop(ps: ps, kind: k, pos: a, items: _, done: _, err: _, stop: s) then when
      k == "uses" then if is_kw(ps: ps, pos: a, v: "use") then l_push(st: st, r: p_use(ps: ps, pos: a)) else l_done(st: st) end
      k == "items" then if is_kind(ps: ps, pos: a, kind: "eof") then l_done(st: st) else l_push(st: st, r: p_item(ps: ps, pos: a)) end
      k == "cases" then if is_kw(ps: ps, pos: a, v: "case") then l_push(st: st, r: p_variant(ps: ps, pos: a)) else l_done(st: st) end
      k == "fields" then l_push_sep(st: st, ps: ps, r: p_typed(ps: ps, pos: a, kind: "field", what: "a field name"))
      k == "params" then l_push_sep(st: st, ps: ps, r: p_typed(ps: ps, pos: a, kind: "param", what: "a parameter name"))
      k == "clauses" then step_clause(st: st, ps: ps, pos: a)
      k == "block" then step_block(st: st, ps: ps, pos: a, stop: s)
      k == "chain" then if is_one_of(ps: ps, pos: a, table: s) then l_push(st: st, r: p_link(ps: ps, pos: a, table: s)) else l_done(st: st) end
      k == "items_e" then l_push_sep(st: st, ps: ps, r: p_expr(ps: ps, pos: a))
      k == "args" then l_push_sep(st: st, ps: ps, r: p_arg(ps: ps, pos: a))
      k == "binds" then l_push_sep(st: st, ps: ps, r: p_bind(ps: ps, pos: a))
      k == "when" then step_when(st: st, ps: ps, pos: a)
      k == "arms" then if is_kw(ps: ps, pos: a, v: "case") then l_push(st: st, r: p_arm(ps: ps, pos: a)) else l_done(st: st) end
      else l_set(st: st, pos: a, items: [], done: true, err: "internal: unknown loop " ++ k)
    end
  end
end

# ---- ファイル ----

# use "x.ak"
fn p_use(ps: Ps, pos: Int) -> Parsed
  ensures true
  example r_node(r: p_use(ps: ps_of(text: "use \"a.ak\""), pos: 0)) == Node(kind: "use", text: "a.ak", line: 1, col: 1, kids: [])
do
  let t: Token = tok(ps: ps, i: pos + 1)
  if t_kind(t: t) == "str" then ok(n: node(kind: "use", text: t_text(t: t), t: tok(ps: ps, i: pos), kids: []), pos: pos + 2) else expected(ps: ps, pos: pos + 1, what: "a file name in quotes", code: "E100") end
end

# fn か type を1つ
fn p_item(ps: Ps, pos: Int) -> Parsed
  ensures true
  example r_err(r: p_item(ps: ps_of(text: "end"), pos: 0)) == "E108 1:1 extra 'end'"
  example r_err(r: p_item(ps: ps_of(text: "use \"a\""), pos: 0)) == "E100 1:1 expected 'fn' or 'type' but found 'use'"
do
  when
    is_kw(ps: ps, pos: pos, v: "use") then expected(ps: ps, pos: pos, what: "'fn' or 'type'", code: "E100")
    is_kw(ps: ps, pos: pos, v: "type") then p_type_decl(ps: ps, pos: pos)
    is_kw(ps: ps, pos: pos, v: "end") then fail_tok(t: tok(ps: ps, i: pos), code: "E108", message: "extra 'end'")
    is_kw(ps: ps, pos: pos, v: "fn") then p_fn(ps: ps, pos: pos)
    else expected(ps: ps, pos: pos, what: "'fn' or 'type'", code: "E100")
  end
end

fn is_use(n: Node) -> Bool
  ensures true
  example is_use(n: bare(kind: "use", text: "", kids: []))
do
  n_kind(n: n) == "use"
end

fn is_type(n: Node) -> Bool
  ensures true
  example is_type(n: bare(kind: "type", text: "", kids: []))
do
  n_kind(n: n) == "type"
end

fn is_fn(n: Node) -> Bool
  ensures true
  example is_fn(n: bare(kind: "fn", text: "", kids: []))
do
  n_kind(n: n) == "fn"
end

# ファイル全体：program の子は use・type・fn の順（src/parse.js の { uses, types, fns } と同じ並び）
fn p_program(ps: Ps) -> Parsed
  ensures true
  example n_kids(n: r_node(r: p_program(ps: ps_of(text: "")))) == []
do
  let uses: Parsed = many(ps: ps, kind: "uses", pos: 0, stop: "", wrap: "uses")
  if bad(r: uses) then uses else
    let items: Parsed = many(ps: ps, kind: "items", pos: r_at(r: uses), stop: "", wrap: "items")
    if bad(r: items) then items else
      let everything: List[Node] = n_kids(n: r_node(r: items))
      ok(n: bare(kind: "program", text: "", kids: join_nodes(a: join_nodes(a: n_kids(n: r_node(r: uses)), b: filter(list: everything, func: is_type)), b: filter(list: everything, func: is_fn))), pos: r_at(r: items))
    end
  end
end

# 2つの並びをつなぐ
fn join_nodes(a: List[Node], b: List[Node]) -> List[Node]
  ensures len(list: result) == len(list: a) + len(list: b)
  example join_nodes(a: [], b: [bare(kind: "x", text: "", kids: [])]) == [bare(kind: "x", text: "", kids: [])]
do
  fold(list: b, init: a, func: add_node)
end

fn add_node(xs: List[Node], x: Node) -> List[Node]
  ensures len(list: result) == len(list: xs) + 1
  example add_node(xs: [], x: bare(kind: "x", text: "", kids: [])) == [bare(kind: "x", text: "", kids: [])]
do
  append(list: xs, item: x)
end

# type Name case A(x: Int) case B end
fn p_type_decl(ps: Ps, pos: Int) -> Parsed
  ensures true
  example n_text(n: r_node(r: p_type_decl(ps: ps_of(text: "type Shape case Dot end"), pos: 0))) == "Shape"
  example r_err(r: p_type_decl(ps: ps_of(text: "type Shape end"), pos: 0)) == "E100 1:12 expected 'case' but found 'end'"
do
  let name: Parsed = expect_id(ps: ps, pos: pos + 1, what: "a type name")
  when
    bad(r: name) then name
    not is_upper(word: n_text(n: r_node(r: name))) then expected(ps: ps, pos: pos + 1, what: "a type name starting with a capital letter", code: "E100")
    else type_rest(ps: ps, pos: pos, name: n_text(n: r_node(r: name)))
  end
end

fn type_rest(ps: Ps, pos: Int, name: Str) -> Parsed
  ensures true
  example bad(r: type_rest(ps: ps_of(text: "type A end"), pos: 0, name: "A"))
do
  let cases: Parsed = many(ps: ps, kind: "cases", pos: pos + 2, stop: "", wrap: "cases")
  when
    bad(r: cases) then cases
    n_kids(n: r_node(r: cases)) == [] then expected(ps: ps, pos: r_at(r: cases), what: "'case'", code: "E100")
    else
    finish_with(ps: ps, r: cases, kw: "end", n: node(kind: "type", text: name, t: tok(ps: ps, i: pos), kids: n_kids(n: r_node(r: cases))))
  end
end

# r の後ろに kw があれば、木 n で成功
fn finish_with(ps: Ps, r: Parsed, kw: Str, n: Node) -> Parsed
  ensures true
  example r_at(r: finish_with(ps: ps_of(text: "end"), r: ok(n: bare(kind: "x", text: "", kids: []), pos: 0), kw: "end", n: bare(kind: "y", text: "", kids: []))) == 1
do
  let e: Parsed = expect_kw(ps: ps, pos: r_at(r: r), v: kw)
  if bad(r: e) then e else ok(n: n, pos: r_at(r: e)) end
end

# case Name(field: Type, ...)
fn p_variant(ps: Ps, pos: Int) -> Parsed
  ensures true
  example r_node(r: p_variant(ps: ps_of(text: "case Dot"), pos: 0)) == Node(kind: "case", text: "Dot", line: 1, col: 6, kids: [])
do
  let v: Parsed = expect_id(ps: ps, pos: pos + 1, what: "a case name")
  when
    bad(r: v) then v
    not is_upper(word: n_text(n: r_node(r: v))) then expected(ps: ps, pos: pos + 1, what: "a case name starting with a capital letter", code: "E100")
    not is_op(ps: ps, pos: pos + 2, v: "(") then ok(n: retag(n: r_node(r: v), kind: "case", kids: []), pos: pos + 2)
    else
    in_parens(ps: ps, r: many(ps: ps, kind: "fields", pos: pos + 3, stop: "", wrap: "fields"), n: r_node(r: v), kind: "case")
  end
end

# 名前の木の種類と子を変える（位置と文字はそのまま）
fn retag(n: Node, kind: Str, kids: List[Node]) -> Node
  ensures true
  example retag(n: bare(kind: "name", text: "x", kids: []), kind: "var", kids: []) == bare(kind: "var", text: "x", kids: [])
do
  match n
    case Node(kind: _, text: x, line: l, col: c, kids: _) then Node(kind: kind, text: x, line: l, col: c, kids: kids)
  end
end

# 並び r の後ろの ) を読み、名前の木 n を kind にして、並びを子にする
fn in_parens(ps: Ps, r: Parsed, n: Node, kind: Str) -> Parsed
  ensures true
  example bad(r: in_parens(ps: ps_of(text: "x"), r: ok(n: bare(kind: "x", text: "", kids: []), pos: 0), n: bare(kind: "x", text: "", kids: []), kind: "case"))
do
  if bad(r: r) then r else
    let close: Parsed = expect_op(ps: ps, pos: r_at(r: r), v: ")")
    if bad(r: close) then close else ok(n: retag(n: n, kind: kind, kids: n_kids(n: r_node(r: r))), pos: r_at(r: close)) end
  end
end

# name: Type（欄と引数）
fn p_typed(ps: Ps, pos: Int, kind: Str, what: Str) -> Parsed
  ensures true
  example r_node(r: p_typed(ps: ps_of(text: "x: Int"), pos: 0, kind: "param", what: "a parameter name")) == Node(kind: "param", text: "x", line: 1, col: 1, kids: [bare(kind: "t", text: "Int", kids: [])])
do
  let name: Parsed = expect_id(ps: ps, pos: pos, what: what)
  if bad(r: name) then name else
    let colon: Parsed = expect_op(ps: ps, pos: pos + 1, v: ":")
    if bad(r: colon) then colon else
      let ty: Parsed = p_type(ps: ps, pos: pos + 2)
      if bad(r: ty) then ty else ok(n: retag(n: r_node(r: name), kind: kind, kids: [r_node(r: ty)]), pos: r_at(r: ty)) end
    end
  end
end

# ---- 型 ----

fn builtin_types() -> Str
  ensures true
  example in_table(table: builtin_types(), word: "OutFolder")
do
  " Int Bool Str Unit List Dict Option Result Html Sql Console Folder OutFolder "
end

fn user_types(ps: Ps) -> Str
  ensures true
  example in_table(table: user_types(ps: ps_of(text: "type A case B end")), word: "A")
do
  match ps
    case Ps(toks: _, user: u, lines: _) then " " ++ join(parts: u, by: " ") ++ " "
  end
end

# Int・List[Int]・Option[Str]・自分で作った型
fn p_type(ps: Ps, pos: Int) -> Parsed
  ensures true
  example r_node(r: p_type(ps: ps_of(text: "List[Option[Int]]"), pos: 0)) == bare(kind: "t", text: "List", kids: [bare(kind: "t", text: "Option", kids: [bare(kind: "t", text: "Int", kids: [])])])
  example r_err(r: p_type(ps: ps_of(text: "Null"), pos: 0)) == "E104 1:1 unknown type 'Null'"
  example r_node(r: p_type(ps: ps_of(text: "type List case A end List"), pos: 5)) == bare(kind: "t", text: "List", kids: [])
do
  let t: Token = tok(ps: ps, i: pos)
  let name: Str = t_text(t: t)
  when
    t_kind(t: t) != "id" then expected(ps: ps, pos: pos, what: "a type", code: "E104")
    not in_table(table: builtin_types(), word: name) and not in_table(table: user_types(ps: ps), word: name) then fail_tok(t: t, code: "E104", message: "unknown type '" ++ name ++ "'")
    in_table(table: " Option Result ", word: name) then type_arg(ps: ps, pos: pos, name: name)
    in_table(table: " List Dict ", word: name) and not in_table(table: user_types(ps: ps), word: name) then type_arg(ps: ps, pos: pos, name: name)
    else ok(n: bare(kind: "t", text: name, kids: []), pos: pos + 1)
  end
end

# Name[T]
fn type_arg(ps: Ps, pos: Int, name: Str) -> Parsed
  ensures true
  example bad(r: type_arg(ps: ps_of(text: "List"), pos: 0, name: "List"))
do
  let open: Parsed = expect_op(ps: ps, pos: pos + 1, v: "[")
  if bad(r: open) then open else
    let inner: Parsed = p_type(ps: ps, pos: pos + 2)
    if bad(r: inner) then inner else
      let close: Parsed = expect_op(ps: ps, pos: r_at(r: inner), v: "]")
      if bad(r: close) then close else ok(n: bare(kind: "t", text: name, kids: [r_node(r: inner)]), pos: r_at(r: close)) end
    end
  end
end

# ---- 関数 ----

# fn name(x: Int) -> Int requires … ensures … example … do … end
# 木：fn の子は params・戻りの型・requires・ensures・examples・本体のブロック
fn p_fn(ps: Ps, pos: Int) -> Parsed
  ensures true
  example n_kind(n: r_node(r: p_fn(ps: ps_of(text: "fn f() -> Int do 1 end"), pos: 0))) == "fn"
  example r_err(r: p_fn(ps: ps_of(text: "fn f() do 1 end"), pos: 0)) == "E102 1:8 expected '->' and a return type but found 'do'"
do
  let name: Parsed = expect_id(ps: ps, pos: pos + 1, what: "a function name")
  if bad(r: name) then name else
    let open: Parsed = expect_op(ps: ps, pos: pos + 2, v: "(")
    if bad(r: open) then open else
      let params: Parsed = if is_op(ps: ps, pos: pos + 3, v: ")") then ok(n: bare(kind: "params", text: "", kids: []), pos: pos + 3) else many(ps: ps, kind: "params", pos: pos + 3, stop: "", wrap: "params") end
      if bad(r: params) then params else
        let close: Parsed = expect_op(ps: ps, pos: r_at(r: params), v: ")")
        when
          bad(r: close) then close
          not is_op(ps: ps, pos: r_at(r: close), v: "->") then expected(ps: ps, pos: r_at(r: close), what: "'->' and a return type", code: "E102")
          else fn_rest(ps: ps, pos: pos, name: n_text(n: r_node(r: name)), params: r_node(r: params), ret: p_type(ps: ps, pos: r_at(r: close) + 1))
        end
      end
    end
  end
end

fn fn_rest(ps: Ps, pos: Int, name: Str, params: Node, ret: Parsed) -> Parsed
  ensures true
  example bad(r: fn_rest(ps: ps_of(text: "x"), pos: 0, name: "f", params: bare(kind: "params", text: "", kids: []), ret: fail_tok(t: eof_token(), code: "E104", message: "x")))
do
  if bad(r: ret) then ret else
    let clauses: Parsed = many(ps: ps, kind: "clauses", pos: r_at(r: ret), stop: "", wrap: "clauses")
    if bad(r: clauses) then clauses else
      let open: Parsed = expect_kw(ps: ps, pos: r_at(r: clauses), v: "do")
      if bad(r: open) then open else
        let body: Parsed = p_block(ps: ps, pos: r_at(r: open), stop: " end ")
        if bad(r: body) then body else
          let cs: List[Node] = n_kids(n: r_node(r: clauses))
          let parts: List[Node] = [params, r_node(r: ret), bare(kind: "requires", text: "", kids: map(list: filter(list: cs, func: is_requires), func: first_kid)), bare(kind: "ensures", text: "", kids: map(list: filter(list: cs, func: is_ensures), func: first_kid)), bare(kind: "examples", text: "", kids: map(list: filter(list: cs, func: is_example), func: first_kid)), r_node(r: body)]
          finish_with(ps: ps, r: body, kw: "end", n: node(kind: "fn", text: name, t: tok(ps: ps, i: pos), kids: parts))
        end
      end
    end
  end
end

fn is_requires(n: Node) -> Bool
  ensures true
  example is_requires(n: bare(kind: "requires", text: "", kids: []))
do
  n_kind(n: n) == "requires"
end

fn is_ensures(n: Node) -> Bool
  ensures true
  example is_ensures(n: bare(kind: "ensures", text: "", kids: []))
do
  n_kind(n: n) == "ensures"
end

fn is_example(n: Node) -> Bool
  ensures true
  example is_example(n: bare(kind: "example", text: "", kids: []))
do
  n_kind(n: n) == "example"
end

# requires・ensures・example を1つ。木は kind（requires など）の下に clause（文字は元の書き方）
fn step_clause(st: Loop, ps: Ps, pos: Int) -> Loop
  ensures true
  example len(list: l_items(st: step_clause(st: loop_new(ps: ps_of(text: "ensures true do"), kind: "clauses", pos: 0, stop: ""), ps: ps_of(text: "ensures true do"), pos: 0))) == 1
do
  let word: Str = t_text(t: tok(ps: ps, i: pos))
  when
    is_kw(ps: ps, pos: pos, v: "effects") then l_push(st: st, r: fail_tok(t: tok(ps: ps, i: pos), code: "E305", message: "'effects' is not used: authority is passed as capability parameters"))
    not is_kind(ps: ps, pos: pos, kind: "kw") or not in_table(table: " requires ensures example ", word: word) then l_done(st: st)
    else l_push(st: st, r: p_clause(ps: ps, pos: pos + 1, kind: word))
  end
end

fn p_clause(ps: Ps, pos: Int, kind: Str) -> Parsed
  ensures true
  example r_node(r: p_clause(ps: ps_of(text: "x  >  0 do"), pos: 0, kind: "requires")) == bare(kind: "requires", text: "", kids: [bare(kind: "clause", text: "x  >  0", kids: [Node(kind: "bin", text: ">", line: 1, col: 4, kids: [Node(kind: "var", text: "x", line: 1, col: 1, kids: []), Node(kind: "int", text: "0", line: 1, col: 7, kids: [])])])])
do
  let e: Parsed = p_expr(ps: ps, pos: pos)
  if bad(r: e) then e else ok(n: bare(kind: kind, text: "", kids: [bare(kind: "clause", text: source_between(ps: ps, from: tok(ps: ps, i: pos), to: tok(ps: ps, i: r_at(r: e) - 1)), kids: [r_node(r: e)])]), pos: r_at(r: e)) end
end

# from の字句の始まりから to の字句の終わりまでの元の文（行をまたぐときは改行も）
fn source_between(ps: Ps, from: Token, to: Token) -> Str
  ensures true
  example source_between(ps: ps_of(text: "a +\n  b c"), from: tok(ps: ps_of(text: "a +\n  b c"), i: 0), to: tok(ps: ps_of(text: "a +\n  b c"), i: 2)) == "a +\n  b"
do
  match ps
    case Ps(toks: _, user: _, lines: ls) then if t_line(t: from) < 1 or t_line(t: to) < t_line(t: from) then "" else if t_line(t: from) == t_line(t: to) then cut(text: line_at(rows: ls, n: t_line(t: from)), from: t_col(t: from) - 1, to: t_end(t: to) - 1) else join(parts: append(list: join_strs(a: [cut(text: line_at(rows: ls, n: t_line(t: from)), from: t_col(t: from) - 1, to: 1000000)], b: take(list: drop(list: ls, count: t_line(t: from)), count: t_line(t: to) - t_line(t: from) - 1)), item: cut(text: line_at(rows: ls, n: t_line(t: to)), from: 0, to: t_end(t: to) - 1)), by: "\n") end end
  end
end

fn line_at(rows: List[Str], n: Int) -> Str
  ensures true
  example line_at(rows: ["a", "b"], n: 2) == "b"
  example line_at(rows: ["a"], n: 5) == ""
do
  match at(list: rows, index: n - 1)
    case Some(value: s) then s
    case None then ""
  end
end

# slice の、範囲を外れても落ちないもの
fn cut(text: Str, from: Int, to: Int) -> Str
  ensures true
  example cut(text: "abc", from: 1, to: 9) == "bc"
  example cut(text: "abc", from: 5, to: 2) == ""
do
  let n: Int = str_len(text: text)
  let a: Int = when
    from < 0 then 0
    from > n then n
    else from
  end
  let b: Int = when
    to < a then a
    to > n then n
    else to
  end
  slice(text: text, from: a, to: b)
end

# ---- ブロック ----

# 行の並び。stop（" end " や " else end "）の言葉の前で終わる。最後の行が値
fn p_block(ps: Ps, pos: Int, stop: Str) -> Parsed
  ensures true
  example n_kids(n: r_node(r: p_block(ps: ps_of(text: "1 end"), pos: 0, stop: " end "))) == [Node(kind: "int", text: "1", line: 1, col: 1, kids: [])]
  example r_err(r: p_block(ps: ps_of(text: "end"), pos: 0, stop: " end ")) == "E100 1:1 expected an expression but found 'end'"
do
  many(ps: ps, kind: "block", pos: pos, stop: stop, wrap: "block")
end

fn step_block(st: Loop, ps: Ps, pos: Int, stop: Str) -> Loop
  ensures true
  example is_over(st: step_block(st: loop_new(ps: ps_of(text: "1 end"), kind: "block", pos: 0, stop: " end "), ps: ps_of(text: "1 end"), pos: 0, stop: " end "))
do
  when
    is_kw(ps: ps, pos: pos, v: "let") then l_push(st: st, r: p_let(ps: ps, pos: pos))
    is_kind(ps: ps, pos: pos, kind: "kw") and in_table(table: stop, word: t_text(t: tok(ps: ps, i: pos))) then l_push(st: st, r: expected(ps: ps, pos: pos, what: "an expression", code: "E100"))
    else block_line(st: st, ps: ps, e: p_expr(ps: ps, pos: pos), stop: stop)
  end
end

# 式の行：ブロックの終わりなら値（そこで終わる）、そうでなければ do の行
fn block_line(st: Loop, ps: Ps, e: Parsed, stop: Str) -> Loop
  ensures true
  example is_over(st: block_line(st: loop_new(ps: ps_of(text: "x"), kind: "block", pos: 0, stop: ""), ps: ps_of(text: "x"), e: fail_tok(t: eof_token(), code: "E100", message: "x"), stop: ""))
do
  let a: Int = r_at(r: e)
  when
    bad(r: e) then l_push(st: st, r: e)
    is_kind(ps: ps, pos: a, kind: "kw") and in_table(table: stop, word: t_text(t: tok(ps: ps, i: a))) then l_done(st: l_push(st: st, r: e))
    else l_push(st: st, r: ok(n: Node(kind: "do", text: "", line: n_line(n: r_node(r: e)), col: n_col(n: r_node(r: e)), kids: [r_node(r: e)]), pos: a))
  end
end

fn n_line(n: Node) -> Int
  ensures true
  example n_line(n: Node(kind: "x", text: "", line: 2, col: 3, kids: [])) == 2
do
  match n
    case Node(kind: _, text: _, line: l, col: _, kids: _) then l
  end
end

fn n_col(n: Node) -> Int
  ensures true
  example n_col(n: Node(kind: "x", text: "", line: 2, col: 3, kids: [])) == 3
do
  match n
    case Node(kind: _, text: _, line: _, col: c, kids: _) then c
  end
end

# let name: Type = value。木 let の子は型と値
fn p_let(ps: Ps, pos: Int) -> Parsed
  ensures true
  example n_kids(n: r_node(r: p_let(ps: ps_of(text: "let x: Int = 1"), pos: 0))) == [bare(kind: "t", text: "Int", kids: []), Node(kind: "int", text: "1", line: 1, col: 14, kids: [])]
  example r_err(r: p_let(ps: ps_of(text: "let x = 1"), pos: 0)) == "E103 1:7 expected ':' and a type but found '='"
do
  let name: Parsed = expect_id(ps: ps, pos: pos + 1, what: "a name after let")
  when
    bad(r: name) then name
    not is_op(ps: ps, pos: pos + 2, v: ":") then expected(ps: ps, pos: pos + 2, what: "':' and a type", code: "E103")
    else let_rest(ps: ps, pos: pos, name: n_text(n: r_node(r: name)), ty: p_type(ps: ps, pos: pos + 3))
  end
end

fn let_rest(ps: Ps, pos: Int, name: Str, ty: Parsed) -> Parsed
  ensures true
  example bad(r: let_rest(ps: ps_of(text: "let x: Int 1"), pos: 0, name: "x", ty: ok(n: bare(kind: "t", text: "Int", kids: []), pos: 4)))
do
  if bad(r: ty) then ty else
    let eq: Parsed = expect_op(ps: ps, pos: r_at(r: ty), v: "=")
    if bad(r: eq) then eq else
      let value: Parsed = p_expr(ps: ps, pos: r_at(r: eq))
      if bad(r: value) then value else ok(n: node(kind: "let", text: name, t: tok(ps: ps, i: pos), kids: [r_node(r: ty), r_node(r: value)]), pos: r_at(r: value)) end
    end
  end
end

# ---- 式 ----

fn p_expr(ps: Ps, pos: Int) -> Parsed
  ensures true
  example n_kind(n: r_node(r: p_expr(ps: ps_of(text: "a and b"), pos: 0))) == "bin"
do
  p_logic(ps: ps, pos: pos)
end

# and・or の並び（混ぜるときはかっこが要る：E105）
fn p_logic(ps: Ps, pos: Int) -> Parsed
  ensures true
  example r_err(r: p_logic(ps: ps_of(text: "a and b or c"), pos: 0)) == "E105 1:9 'and' and 'or' are mixed without parentheses"
do
  let left: Parsed = p_compare(ps: ps, pos: pos)
  let a: Int = r_at(r: left)
  if bad(r: left) or not is_one_of(ps: ps, pos: a, table: " and or ") then left else
    let chain: Parsed = p_chain(ps: ps, left: left, table: " " ++ t_text(t: tok(ps: ps, i: a)) ++ " ")
    if not bad(r: chain) and is_one_of(ps: ps, pos: r_at(r: chain), table: " and or ") then fail_tok(t: tok(ps: ps, i: r_at(r: chain)), code: "E105", message: "'and' and 'or' are mixed without parentheses") else chain end
  end
end

# == != < <= > >=（つなげるのは E106）
fn p_compare(ps: Ps, pos: Int) -> Parsed
  ensures true
  example r_err(r: p_compare(ps: ps_of(text: "0 < x < 9"), pos: 0)) == "E106 1:7 comparisons cannot be chained"
do
  let left: Parsed = p_add(ps: ps, pos: pos)
  let a: Int = r_at(r: left)
  if bad(r: left) or not is_one_of(ps: ps, pos: a, table: " == != < <= > >= ") then left else
    let right: Parsed = p_add(ps: ps, pos: a + 1)
    when
      bad(r: right) then right
      is_one_of(ps: ps, pos: r_at(r: right), table: " == != < <= > >= ") then fail_tok(t: tok(ps: ps, i: r_at(r: right)), code: "E106", message: "comparisons cannot be chained")
      else ok(n: node(kind: "bin", text: t_text(t: tok(ps: ps, i: a)), t: tok(ps: ps, i: a), kids: [r_node(r: left), r_node(r: right)]), pos: r_at(r: right))
    end
  end
end

fn p_add(ps: Ps, pos: Int) -> Parsed
  ensures true
  example n_text(n: r_node(r: p_add(ps: ps_of(text: "1 + 2 - 3"), pos: 0))) == "-"
do
  let left: Parsed = p_mul(ps: ps, pos: pos)
  if bad(r: left) or not is_one_of(ps: ps, pos: r_at(r: left), table: " + - ++ ") then left else p_chain(ps: ps, left: left, table: " + - ++ ") end
end

fn p_mul(ps: Ps, pos: Int) -> Parsed
  ensures true
  example n_text(n: r_node(r: p_mul(ps: ps_of(text: "1 * 2 % 3"), pos: 0))) == "%"
do
  let left: Parsed = p_unary(ps: ps, pos: pos)
  if bad(r: left) or not is_one_of(ps: ps, pos: r_at(r: left), table: " * / % ") then left else p_chain(ps: ps, left: left, table: " * / % ") end
end

# 左から結ぶ並び：left (op right)…。右は表で決まる段（and/or → 比べる、+ → *、* → 単項）
fn p_chain(ps: Ps, left: Parsed, table: Str) -> Parsed
  ensures true
  example n_kids(n: r_node(r: p_chain(ps: ps_of(text: "a + b"), left: ok(n: bare(kind: "var", text: "a", kids: []), pos: 1), table: " + - ++ "))) == [bare(kind: "var", text: "a", kids: []), Node(kind: "var", text: "b", line: 1, col: 5, kids: [])]
do
  let links: Parsed = many(ps: ps, kind: "chain", pos: r_at(r: left), stop: table, wrap: "links")
  if bad(r: links) then links else ok(n: fold(list: n_kids(n: r_node(r: links)), init: r_node(r: left), func: attach), pos: r_at(r: links)) end
end

# op と右の1つ（木は bin で、子は右だけ。attach で左を足す）
fn p_link(ps: Ps, pos: Int, table: Str) -> Parsed
  ensures true
  example n_kids(n: r_node(r: p_link(ps: ps_of(text: "* 2"), pos: 0, table: " * / % "))) == [Node(kind: "int", text: "2", line: 1, col: 3, kids: [])]
do
  let right: Parsed = when
    in_table(table: table, word: "and") or in_table(table: table, word: "or") then p_compare(ps: ps, pos: pos + 1)
    in_table(table: table, word: "+") then p_mul(ps: ps, pos: pos + 1)
    else p_unary(ps: ps, pos: pos + 1)
  end
  let t: Token = tok(ps: ps, i: pos)
  if bad(r: right) then right else ok(n: node(kind: "bin", text: t_text(t: t), t: t, kids: [r_node(r: right)]), pos: r_at(r: right)) end
end

fn attach(left: Node, link: Node) -> Node
  ensures true
  example attach(left: bare(kind: "a", text: "", kids: []), link: bare(kind: "bin", text: "+", kids: [bare(kind: "b", text: "", kids: [])])) == bare(kind: "bin", text: "+", kids: [bare(kind: "a", text: "", kids: []), bare(kind: "b", text: "", kids: [])])
do
  retag(n: link, kind: "bin", kids: [left, first_kid(n: link)])
end

# not x・-x
fn p_unary(ps: Ps, pos: Int) -> Parsed
  ensures true
  example r_node(r: p_unary(ps: ps_of(text: "- 1"), pos: 0)) == Node(kind: "un", text: "-", line: 1, col: 1, kids: [Node(kind: "int", text: "1", line: 1, col: 3, kids: [])])
do
  if is_kw(ps: ps, pos: pos, v: "not") or is_op(ps: ps, pos: pos, v: "-") then
    let arg: Parsed = p_unary(ps: ps, pos: pos + 1)
    if bad(r: arg) then arg else ok(n: node(kind: "un", text: t_text(t: tok(ps: ps, i: pos)), t: tok(ps: ps, i: pos), kids: [r_node(r: arg)]), pos: r_at(r: arg)) end
  else
    p_primary(ps: ps, pos: pos)
  end
end

fn p_primary(ps: Ps, pos: Int) -> Parsed
  ensures true
  example r_node(r: p_primary(ps: ps_of(text: "()"), pos: 0)) == Node(kind: "unit", text: "", line: 1, col: 1, kids: [])
  example r_err(r: p_primary(ps: ps_of(text: "then"), pos: 0)) == "E100 1:1 expected an expression but found 'then'"
do
  let t: Token = tok(ps: ps, i: pos)
  let k: Str = t_kind(t: t)
  when
    k == "int" or k == "str" then ok(n: node(kind: k, text: t_text(t: t), t: t, kids: []), pos: pos + 1)
    is_kw(ps: ps, pos: pos, v: "true") or is_kw(ps: ps, pos: pos, v: "false") then ok(n: node(kind: "bool", text: t_text(t: t), t: t, kids: []), pos: pos + 1)
    is_op(ps: ps, pos: pos, v: "(") then p_paren(ps: ps, pos: pos)
    is_op(ps: ps, pos: pos, v: "[") then p_list(ps: ps, pos: pos)
    is_kw(ps: ps, pos: pos, v: "when") then p_when(ps: ps, pos: pos)
    is_kw(ps: ps, pos: pos, v: "match") then p_match(ps: ps, pos: pos)
    is_kw(ps: ps, pos: pos, v: "if") then p_if(ps: ps, pos: pos)
    k == "id" and is_op(ps: ps, pos: pos + 1, v: "(") then p_call(ps: ps, pos: pos)
    k == "id" then ok(n: node(kind: "var", text: t_text(t: t), t: t, kids: []), pos: pos + 1)
    else expected(ps: ps, pos: pos, what: "an expression", code: "E100")
  end
end

# () か (式)
fn p_paren(ps: Ps, pos: Int) -> Parsed
  ensures true
  example n_kind(n: r_node(r: p_paren(ps: ps_of(text: "(x)"), pos: 0))) == "var"
do
  if is_op(ps: ps, pos: pos + 1, v: ")") then ok(n: node(kind: "unit", text: "", t: tok(ps: ps, i: pos), kids: []), pos: pos + 2) else
    let e: Parsed = p_expr(ps: ps, pos: pos + 1)
    if bad(r: e) then e else
      let close: Parsed = expect_op(ps: ps, pos: r_at(r: e), v: ")")
      if bad(r: close) then close else ok(n: r_node(r: e), pos: r_at(r: close)) end
    end
  end
end

# [a, b]
fn p_list(ps: Ps, pos: Int) -> Parsed
  ensures true
  example len(list: n_kids(n: r_node(r: p_list(ps: ps_of(text: "[1, 2]"), pos: 0)))) == 2
  example n_kids(n: r_node(r: p_list(ps: ps_of(text: "[]"), pos: 0))) == []
do
  let items: Parsed = if is_op(ps: ps, pos: pos + 1, v: "]") then ok(n: bare(kind: "items", text: "", kids: []), pos: pos + 1) else many(ps: ps, kind: "items_e", pos: pos + 1, stop: "", wrap: "items") end
  if bad(r: items) then items else
    let close: Parsed = expect_op(ps: ps, pos: r_at(r: items), v: "]")
    if bad(r: close) then close else ok(n: node(kind: "list", text: "", t: tok(ps: ps, i: pos), kids: n_kids(n: r_node(r: items))), pos: r_at(r: close)) end
  end
end

# f(a: 1, b: 2)。木 call の子は arg（文字は引数の名前。名前の無いものは ""）
fn p_call(ps: Ps, pos: Int) -> Parsed
  ensures true
  example r_node(r: p_call(ps: ps_of(text: "f(x: 1)"), pos: 0)) == Node(kind: "call", text: "f", line: 1, col: 1, kids: [Node(kind: "arg", text: "x", line: 1, col: 3, kids: [Node(kind: "int", text: "1", line: 1, col: 6, kids: [])])])
do
  let args: Parsed = if is_op(ps: ps, pos: pos + 2, v: ")") then ok(n: bare(kind: "args", text: "", kids: []), pos: pos + 2) else many(ps: ps, kind: "args", pos: pos + 2, stop: "", wrap: "args") end
  in_parens(ps: ps, r: args, n: node(kind: "name", text: t_text(t: tok(ps: ps, i: pos)), t: tok(ps: ps, i: pos), kids: []), kind: "call")
end

fn p_arg(ps: Ps, pos: Int) -> Parsed
  ensures true
  example n_text(n: r_node(r: p_arg(ps: ps_of(text: "1"), pos: 0))) == ""
do
  let t: Token = tok(ps: ps, i: pos)
  let named: Bool = t_kind(t: t) == "id" and is_op(ps: ps, pos: pos + 1, v: ":")
  let value: Parsed = p_expr(ps: ps, pos: if named then pos + 2 else pos end)
  if bad(r: value) then value else ok(n: node(kind: "arg", text: if named then t_text(t: t) else "" end, t: t, kids: [r_node(r: value)]), pos: r_at(r: value)) end
end

# if c then … else … end。木 if の子は条件・then のブロック・else のブロック
fn p_if(ps: Ps, pos: Int) -> Parsed
  ensures true
  example r_err(r: p_if(ps: ps_of(text: "if a then 1 end"), pos: 0)) == "E107 1:13 'if' has no 'else'"
do
  let cond: Parsed = p_expr(ps: ps, pos: pos + 1)
  if bad(r: cond) then cond else
    let th: Parsed = expect_kw(ps: ps, pos: r_at(r: cond), v: "then")
    if bad(r: th) then th else
      let yes: Parsed = p_block(ps: ps, pos: r_at(r: th), stop: " else end ")
      when
        bad(r: yes) then yes
        is_kw(ps: ps, pos: r_at(r: yes), v: "end") then fail_tok(t: tok(ps: ps, i: r_at(r: yes)), code: "E107", message: "'if' has no 'else'")
        else if_rest(ps: ps, pos: pos, cond: r_node(r: cond), yes: r_node(r: yes), no: p_block(ps: ps, pos: r_at(r: yes) + 1, stop: " end "))
      end
    end
  end
end

fn if_rest(ps: Ps, pos: Int, cond: Node, yes: Node, no: Parsed) -> Parsed
  ensures true
  example bad(r: if_rest(ps: ps_of(text: "x"), pos: 0, cond: bare(kind: "x", text: "", kids: []), yes: bare(kind: "x", text: "", kids: []), no: ok(n: bare(kind: "x", text: "", kids: []), pos: 0)))
do
  if bad(r: no) then no else finish_with(ps: ps, r: no, kw: "end", n: node(kind: "if", text: "", t: tok(ps: ps, i: pos), kids: [cond, yes, r_node(r: no)])) end
end

# when：いくつもの場合分け。src/parse.js と同じく、入れ子の if の木にする（位置は各条件の位置）
fn p_when(ps: Ps, pos: Int) -> Parsed
  ensures true
  example r_err(r: p_when(ps: ps_of(text: "when a then 1 end"), pos: 0)) == "E112 1:15 'when' has no 'else'"
  example r_err(r: p_when(ps: ps_of(text: "when else 1 end"), pos: 0)) == "E100 1:6 expected a condition but found 'else'"
do
  let arms: Parsed = many(ps: ps, kind: "when", pos: pos + 1, stop: "", wrap: "arms")
  when
    bad(r: arms) then arms
    n_kids(n: r_node(r: arms)) == [] then expected(ps: ps, pos: r_at(r: arms), what: "a condition", code: "E100")
    else when_rest(ps: ps, arms: n_kids(n: r_node(r: arms)), last: p_expr(ps: ps, pos: r_at(r: arms) + 1))
  end
end

fn when_rest(ps: Ps, arms: List[Node], last: Parsed) -> Parsed
  ensures true
  example bad(r: when_rest(ps: ps_of(text: "x"), arms: [], last: ok(n: bare(kind: "x", text: "", kids: []), pos: 0)))
do
  if bad(r: last) then last else
    let close: Parsed = expect_kw(ps: ps, pos: r_at(r: last), v: "end")
    if bad(r: close) then close else ok(n: fold(list: reverse(list: arms), init: r_node(r: last), func: when_if), pos: r_at(r: close)) end
  end
end

# 腕（条件・値）を、残り（else 側）を持つ if にする
fn when_if(rest: Node, arm: Node) -> Node
  ensures n_kind(n: result) == "if"
  example n_kind(n: when_if(rest: bare(kind: "int", text: "1", kids: []), arm: bare(kind: "arm", text: "", kids: [bare(kind: "var", text: "a", kids: []), bare(kind: "int", text: "2", kids: [])]))) == "if"
do
  let cond: Node = first_kid(n: arm)
  let value: Node = match at(list: n_kids(n: arm), index: 1)
    case Some(value: v) then v
    case None then bare(kind: "none", text: "", kids: [])
  end
  Node(kind: "if", text: "", line: n_line(n: cond), col: n_col(n: cond), kids: [cond, bare(kind: "block", text: "", kids: [value]), bare(kind: "block", text: "", kids: [rest])])
end

fn step_when(st: Loop, ps: Ps, pos: Int) -> Loop
  ensures true
  example is_over(st: step_when(st: loop_new(ps: ps_of(text: "else"), kind: "when", pos: 0, stop: ""), ps: ps_of(text: "else"), pos: 0))
do
  when
    is_kw(ps: ps, pos: pos, v: "else") then l_done(st: st)
    is_kw(ps: ps, pos: pos, v: "end") then l_push(st: st, r: fail_tok(t: tok(ps: ps, i: pos), code: "E112", message: "'when' has no 'else'"))
    else l_push(st: st, r: p_when_arm(ps: ps, pos: pos))
  end
end

fn p_when_arm(ps: Ps, pos: Int) -> Parsed
  ensures true
  example len(list: n_kids(n: r_node(r: p_when_arm(ps: ps_of(text: "a then 1"), pos: 0)))) == 2
do
  let cond: Parsed = p_expr(ps: ps, pos: pos)
  if bad(r: cond) then cond else
    let th: Parsed = expect_kw(ps: ps, pos: r_at(r: cond), v: "then")
    if bad(r: th) then th else
      let value: Parsed = p_expr(ps: ps, pos: r_at(r: th))
      if bad(r: value) then value else ok(n: bare(kind: "arm", text: "", kids: [r_node(r: cond), r_node(r: value)]), pos: r_at(r: value)) end
    end
  end
end

# match x case A(f: v) then … end。木 match の子は調べる値と arm（文字は case の名前、位置は case の位置）
# arm の子：at（case の名前の位置）・bind（文字は「欄 名前」）…・値
fn p_match(ps: Ps, pos: Int) -> Parsed
  ensures true
  example r_err(r: p_match(ps: ps_of(text: "match x case A then 1 else 2 end"), pos: 0)) == "E211 1:23 'match' has no else"
do
  let subject: Parsed = p_expr(ps: ps, pos: pos + 1)
  if bad(r: subject) then subject else
    let arms: Parsed = many(ps: ps, kind: "arms", pos: r_at(r: subject), stop: "", wrap: "arms")
    let a: Int = r_at(r: arms)
    when
      bad(r: arms) then arms
      is_kw(ps: ps, pos: a, v: "else") then fail_tok(t: tok(ps: ps, i: a), code: "E211", message: "'match' has no else")
      n_kids(n: r_node(r: arms)) == [] then expected(ps: ps, pos: a, what: "'case'", code: "E100")
      else finish_with(ps: ps, r: arms, kw: "end", n: node(kind: "match", text: "", t: tok(ps: ps, i: pos), kids: join_nodes(a: [r_node(r: subject)], b: n_kids(n: r_node(r: arms)))))
    end
  end
end

fn p_arm(ps: Ps, pos: Int) -> Parsed
  ensures true
  example n_text(n: r_node(r: p_arm(ps: ps_of(text: "case Some(value: v) then v"), pos: 0))) == "Some"
do
  let v: Parsed = expect_id(ps: ps, pos: pos + 1, what: "a case name")
  if bad(r: v) then v else
    let binds: Parsed = if is_op(ps: ps, pos: pos + 2, v: "(") then in_parens(ps: ps, r: many(ps: ps, kind: "binds", pos: pos + 3, stop: "", wrap: "binds"), n: bare(kind: "x", text: "", kids: []), kind: "binds") else ok(n: bare(kind: "binds", text: "", kids: []), pos: pos + 2) end
    if bad(r: binds) then binds else
      let th: Parsed = expect_kw(ps: ps, pos: r_at(r: binds), v: "then")
      if bad(r: th) then th else
        let value: Parsed = p_expr(ps: ps, pos: r_at(r: th))
        if bad(r: value) then value else ok(n: node(kind: "arm", text: n_text(n: r_node(r: v)), t: tok(ps: ps, i: pos), kids: append(list: join_nodes(a: [retag(n: r_node(r: v), kind: "at", kids: [])], b: n_kids(n: r_node(r: binds))), item: r_node(r: value))), pos: r_at(r: value)) end
      end
    end
  end
end

# field: name
fn p_bind(ps: Ps, pos: Int) -> Parsed
  ensures true
  example r_node(r: p_bind(ps: ps_of(text: "value: v"), pos: 0)) == Node(kind: "bind", text: "value v", line: 1, col: 8, kids: [])
do
  let f: Parsed = expect_id(ps: ps, pos: pos, what: "a field name")
  if bad(r: f) then f else
    let colon: Parsed = expect_op(ps: ps, pos: pos + 1, v: ":")
    if bad(r: colon) then colon else
      let b: Parsed = expect_id(ps: ps, pos: pos + 2, what: "a name for the field value")
      if bad(r: b) then b else ok(n: Node(kind: "bind", text: n_text(n: r_node(r: f)) ++ " " ++ n_text(n: r_node(r: b)), line: n_line(n: r_node(r: b)), col: n_col(n: r_node(r: b)), kids: []), pos: pos + 3) end
    end
  end
end

# ---- 入口 ----

# このファイルで決めた型の名前（type の次の名前）
fn type_names(toks: List[Token]) -> List[Str]
  ensures true
  example type_names(toks: toks_of(ps: ps_of(text: "type A case B end type C case D end"))) == ["A", "C"]
do
  match fold(list: toks, init: TypeNames(after_type: false, names: []), func: type_name_step)
    case TypeNames(after_type: _, names: ns) then ns
  end
end

# type の次の名前を集める途中
type TypeNames
  case TypeNames(after_type: Bool, names: List[Str])
end

fn type_name_step(st: TypeNames, t: Token) -> TypeNames
  ensures true
  example type_name_step(st: TypeNames(after_type: true, names: []), t: Token(kind: "id", text: "A", line: 1, col: 6, end_col: 7)) == TypeNames(after_type: false, names: ["A"])
do
  match st
    case TypeNames(after_type: after, names: ns) then TypeNames(after_type: t_kind(t: t) == "kw" and t_text(t: t) == "type", names: if after and t_kind(t: t) == "id" then append(list: ns, item: t_text(t: t)) else ns end)
  end
end

fn join_strs(a: List[Str], b: List[Str]) -> List[Str]
  ensures len(list: result) == len(list: a) + len(list: b)
  example join_strs(a: ["a"], b: ["b"]) == ["a", "b"]
do
  fold(list: b, init: a, func: add_str)
end

fn add_str(xs: List[Str], x: Str) -> List[Str]
  ensures len(list: result) == len(list: xs) + 1
  example add_str(xs: [], x: "a") == ["a"]
do
  append(list: xs, item: x)
end

# 字句と、use で読んだファイルの型の名前から、読む材料を作る
fn make_ps(text: Str, toks: List[Token], other_types: List[Str]) -> Ps
  ensures true
  example len(list: toks_of(ps: make_ps(text: "x", toks: [], other_types: []))) == 1
do
  let rows: List[Str] = split(text: text, by: "\n")
  let last: Str = line_at(rows: rows, n: len(list: rows))
  let n: Int = len(list: rows)
  let eof: Token = Token(kind: "eof", text: "", line: n, col: str_len(text: last) + 1, end_col: str_len(text: last) + 1)
  Ps(toks: append(list: toks, item: eof), user: join_strs(a: type_names(toks: toks), b: other_types), lines: rows)
end

# 例のための近道：字句に分けて材料を作る（分けられなければ空）
fn ps_of(text: Str) -> Ps
  ensures true
  example len(list: toks_of(ps: ps_of(text: "a"))) == 2
do
  match lex(text: text)
    case Ok(value: ts) then make_ps(text: text, toks: ts, other_types: [])
    case Err(message: _) then make_ps(text: "", toks: [], other_types: [])
  end
end

# 1つのファイルを読む。other_types：use で読むほかのファイルで決めた型の名前
fn parse(text: Str, other_types: List[Str]) -> Result[Node]
  ensures true
  example parse(text: "fn f() -> Int do 1 end", other_types: []) == Ok(value: bare(kind: "program", text: "", kids: [Node(kind: "fn", text: "f", line: 1, col: 1, kids: [bare(kind: "params", text: "", kids: []), bare(kind: "t", text: "Int", kids: []), bare(kind: "requires", text: "", kids: []), bare(kind: "ensures", text: "", kids: []), bare(kind: "examples", text: "", kids: []), bare(kind: "block", text: "", kids: [Node(kind: "int", text: "1", line: 1, col: 18, kids: [])])])]))
  example parse(text: "1.5", other_types: []) == Err(message: "E101 1:1 decimal numbers are not supported")
do
  match lex(text: text)
    case Err(message: m) then Err(message: m)
    case Ok(value: ts) then parse_lexed(text: text, toks: ts, other_types: other_types)
  end
end

# 字句に分け終わったものを読む（ファイルを読むときは、字句を1回だけ作って使い回す）
fn parse_lexed(text: Str, toks: List[Token], other_types: List[Str]) -> Result[Node]
  ensures true
  example parse_lexed(text: "1", toks: [Token(kind: "int", text: "1", line: 1, col: 1, end_col: 2)], other_types: []) == Err(message: "E100 1:1 expected 'fn' or 'type' but found '1'")
do
  from_parsed(r: p_program(ps: make_ps(text: text, toks: toks, other_types: other_types)))
end

fn from_parsed(r: Parsed) -> Result[Node]
  ensures true
  example from_parsed(r: fail_tok(t: eof_token(), code: "E100", message: "x")) == Err(message: "E100 1:1 x")
do
  if bad(r: r) then Err(message: r_err(r: r)) else Ok(value: r_node(r: r)) end
end
