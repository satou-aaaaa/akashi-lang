# Akashi の字句解析を Akashi で書いたもの（セルフホストの段階5のはじめ）。src/parse.js の lex と同じ字句を作る。
# 文字を1つずつ fold で読み、状態（Lex）を次の状態にする。再帰は使わない（深さ 500 の上限があるため）。
# 位置（行・列）は文字（コードポイント）で数える。
type Token
  case Token(kind: Str, text: Str, line: Int, col: Int)
end

# mode：none（字句の外）・num・id・str・esc（文字の中の \ の後）・op（2文字の記号かもしれない）・dot（数の後の .）・comment
# err が "" でなければ、そこで止まっている（"E100 1:5 ..." の形）
type Lex
  case Lex(mode: Str, buf: Str, at_line: Int, at_col: Int, line: Int, col: Int, toks: List[Token], err: Str)
end

fn is_digit(c: Str) -> Bool
  ensures true
  example is_digit(c: "7")
  example not is_digit(c: "a")
do
  str_len(text: c) == 1 and contains(text: "0123456789", part: c)
end

fn is_letter(c: Str) -> Bool
  ensures true
  example is_letter(c: "_")
  example not is_letter(c: "1")
do
  str_len(text: c) == 1 and contains(text: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_", part: c)
end

# 空白で区切った表に、その言葉がまるごとあるか
fn in_table(table: Str, word: Str) -> Bool
  ensures true
  example in_table(table: " a bc ", word: "bc")
  example not in_table(table: " a bc ", word: "b")
do
  word != "" and not contains(text: word, part: " ") and contains(text: table, part: " " ++ word ++ " ")
end

fn is_keyword(word: Str) -> Bool
  ensures true
  example is_keyword(word: "match")
  example not is_keyword(word: "matches")
do
  in_table(table: " fn do end let if then else when type case match use requires ensures example effects and or not true false ", word: word)
end

fn fail_at(st: Lex, code: Str, line: Int, col: Int, message: Str) -> Lex
  ensures true
  example fail_at(st: start_state(), code: "E100", line: 1, col: 2, message: "x") == Lex(mode: "none", buf: "", at_line: 1, at_col: 1, line: 1, col: 1, toks: [], err: "E100 1:2 x")
do
  match st
    case Lex(mode: m, buf: b, at_line: al, at_col: ac, line: l, col: c, toks: ts, err: _) then Lex(mode: m, buf: b, at_line: al, at_col: ac, line: l, col: c, toks: ts, err: code ++ " " ++ to_str(value: line) ++ ":" ++ to_str(value: col) ++ " " ++ message)
  end
end

fn start_state() -> Lex
  ensures true
  example start_state() == Lex(mode: "none", buf: "", at_line: 1, at_col: 1, line: 1, col: 1, toks: [], err: "")
do
  Lex(mode: "none", buf: "", at_line: 1, at_col: 1, line: 1, col: 1, toks: [], err: "")
end

# 今の字句（buf）を kind として出し、mode を none にする
fn emit(st: Lex, kind: Str) -> Lex
  ensures true
  example emit(st: Lex(mode: "id", buf: "x", at_line: 1, at_col: 1, line: 1, col: 2, toks: [], err: ""), kind: "id") == Lex(mode: "none", buf: "", at_line: 1, at_col: 1, line: 1, col: 2, toks: [Token(kind: "id", text: "x", line: 1, col: 1)], err: "")
do
  match st
    case Lex(mode: _, buf: b, at_line: al, at_col: ac, line: l, col: c, toks: ts, err: e) then Lex(mode: "none", buf: "", at_line: al, at_col: ac, line: l, col: c, toks: append(list: ts, item: Token(kind: kind, text: b, line: al, col: ac)), err: e)
  end
end

# 1文字読んで進む（mode と buf を変える）。改行なら次の行の1列目
fn take_char(st: Lex, c: Str, mode: Str, buf: Str) -> Lex
  ensures true
  example take_char(st: start_state(), c: "\n", mode: "none", buf: "") == Lex(mode: "none", buf: "", at_line: 1, at_col: 1, line: 2, col: 1, toks: [], err: "")
do
  match st
    case Lex(mode: _, buf: _, at_line: al, at_col: ac, line: l, col: col, toks: ts, err: e) then if c == "\n" then Lex(mode: mode, buf: buf, at_line: al, at_col: ac, line: l + 1, col: 1, toks: ts, err: e) else Lex(mode: mode, buf: buf, at_line: al, at_col: ac, line: l, col: col + 1, toks: ts, err: e) end
  end
end

# 字句の始まりを今の位置にして、1文字読む
fn begin(st: Lex, c: Str, mode: Str, buf: Str) -> Lex
  ensures true
  example begin(st: start_state(), c: "a", mode: "id", buf: "a") == Lex(mode: "id", buf: "a", at_line: 1, at_col: 1, line: 1, col: 2, toks: [], err: "")
do
  match st
    case Lex(mode: m, buf: b, at_line: _, at_col: _, line: l, col: col, toks: ts, err: e) then take_char(st: Lex(mode: m, buf: b, at_line: l, at_col: col, line: l, col: col, toks: ts, err: e), c: c, mode: mode, buf: buf)
  end
end

fn mode_of(st: Lex) -> Str
  ensures true
  example mode_of(st: start_state()) == "none"
do
  match st
    case Lex(mode: m, buf: _, at_line: _, at_col: _, line: _, col: _, toks: _, err: _) then m
  end
end

fn buf_of(st: Lex) -> Str
  ensures true
  example buf_of(st: start_state()) == ""
do
  match st
    case Lex(mode: _, buf: b, at_line: _, at_col: _, line: _, col: _, toks: _, err: _) then b
  end
end

fn err_of(st: Lex) -> Str
  ensures true
  example err_of(st: start_state()) == ""
do
  match st
    case Lex(mode: _, buf: _, at_line: _, at_col: _, line: _, col: _, toks: _, err: e) then e
  end
end

fn here(st: Lex) -> List[Int]
  ensures len(list: result) == 2
  example here(st: start_state()) == [1, 1]
do
  match st
    case Lex(mode: _, buf: _, at_line: _, at_col: _, line: l, col: c, toks: _, err: _) then [l, c]
  end
end

fn started(st: Lex) -> List[Int]
  ensures len(list: result) == 2
  example started(st: start_state()) == [1, 1]
do
  match st
    case Lex(mode: _, buf: _, at_line: al, at_col: ac, line: _, col: _, toks: _, err: _) then [al, ac]
  end
end

# 字句の外で1文字を見る
fn start_token(st: Lex, c: Str) -> Lex
  ensures true
  example mode_of(st: start_token(st: start_state(), c: "#")) == "comment"
  example err_of(st: start_token(st: start_state(), c: "{")) == "E100 1:1 unexpected character '{'"
do
  when
    c == " " or c == "\t" or c == char_of(code: 13) or c == "\n" then take_char(st: st, c: c, mode: "none", buf: "")
    c == "#" then take_char(st: st, c: c, mode: "comment", buf: "")
    is_digit(c: c) then begin(st: st, c: c, mode: "num", buf: c)
    is_letter(c: c) then begin(st: st, c: c, mode: "id", buf: c)
    c == "\"" then begin(st: st, c: c, mode: "str", buf: "")
    in_table(table: " - = ! < > + ", word: c) then begin(st: st, c: c, mode: "op", buf: c)
    in_table(table: " * / % ( ) [ ] , : ", word: c) then emit(st: begin(st: st, c: c, mode: "op", buf: c), kind: "op")
    else fail_at(st: st, code: "E100", line: get(list: here(st: st), index: 0), col: get(list: here(st: st), index: 1), message: "unexpected character '" ++ c ++ "'")
  end
end

# 1文字ぶん進める（fold の func）
fn step(st: Lex, c: Str) -> Lex
  ensures true
  example buf_of(st: step(st: begin(st: start_state(), c: "a", mode: "id", buf: "a"), c: "b")) == "ab"
do
  let mode: Str = mode_of(st: st)
  let buf: Str = buf_of(st: st)
  when
    err_of(st: st) != "" then st
    mode == "comment" then if c == "\n" then take_char(st: st, c: c, mode: "none", buf: "") else take_char(st: st, c: c, mode: "comment", buf: "") end
    mode == "str" then step_str(st: st, c: c, buf: buf)
    mode == "esc" then step_esc(st: st, c: c, buf: buf)
    mode == "num" then step_num(st: st, c: c, buf: buf)
    mode == "dot" then if is_digit(c: c) then fail_at(st: st, code: "E101", line: get(list: started(st: st), index: 0), col: get(list: started(st: st), index: 1), message: "decimal numbers are not supported") else dot_error(st: st) end
    mode == "id" then if is_letter(c: c) or is_digit(c: c) then take_char(st: st, c: c, mode: "id", buf: buf ++ c) else start_token(st: emit(st: st, kind: if is_keyword(word: buf) then "kw" else "id" end), c: c) end
    mode == "op" then step_op(st: st, c: c, buf: buf)
    else start_token(st: st, c: c)
  end
end

fn step_str(st: Lex, c: Str, buf: Str) -> Lex
  ensures true
  example buf_of(st: step_str(st: start_state(), c: "x", buf: "a")) == "ax"
do
  when
    c == "\"" then emit(st: take_char(st: st, c: c, mode: "str", buf: buf), kind: "str")
    c == "\\" then take_char(st: st, c: c, mode: "esc", buf: buf)
    c == "\n" then fail_at(st: st, code: "E100", line: get(list: started(st: st), index: 0), col: get(list: started(st: st), index: 1), message: "string is not closed on this line")
    else take_char(st: st, c: c, mode: "str", buf: buf ++ c)
  end
end

fn step_esc(st: Lex, c: Str, buf: Str) -> Lex
  ensures true
  example buf_of(st: step_esc(st: start_state(), c: "n", buf: "")) == "\n"
do
  when
    c == "n" then take_char(st: st, c: c, mode: "str", buf: buf ++ "\n")
    c == "t" then take_char(st: st, c: c, mode: "str", buf: buf ++ "\t")
    c == "\"" or c == "\\" then take_char(st: st, c: c, mode: "str", buf: buf ++ c)
    else fail_at(st: st, code: "E100", line: get(list: here(st: st), index: 0), col: get(list: here(st: st), index: 1) - 1, message: "unknown escape '\\" ++ c ++ "'")
  end
end

fn step_num(st: Lex, c: Str, buf: Str) -> Lex
  ensures true
  example buf_of(st: step_num(st: start_state(), c: "1", buf: "2")) == "21"
do
  when
    is_digit(c: c) then take_char(st: st, c: c, mode: "num", buf: buf ++ c)
    c == "." then take_char(st: st, c: c, mode: "dot", buf: buf)
    is_letter(c: c) then fail_at(st: st, code: "E100", line: get(list: started(st: st), index: 0), col: get(list: started(st: st), index: 1), message: "a number cannot be followed by letters: '" ++ buf ++ c ++ "'")
    else start_token(st: emit(st: st, kind: "int"), c: c)
  end
end

fn step_op(st: Lex, c: Str, buf: Str) -> Lex
  ensures true
  example buf_of(st: step_op(st: start_state(), c: "=", buf: "=")) == ""
do
  when
    in_table(table: " -> == != <= >= ++ ", word: buf ++ c) then emit(st: take_char(st: st, c: c, mode: "op", buf: buf ++ c), kind: "op")
    buf == "!" then fail_at(st: st, code: "E100", line: get(list: started(st: st), index: 0), col: get(list: started(st: st), index: 1), message: "unexpected character '!'")
    else start_token(st: emit(st: st, kind: "op"), c: c)
  end
end

# 数の後の . で、続きが数字でないとき：. は字句にならない（位置は . のところ。今の位置の1つ前）
fn dot_error(st: Lex) -> Lex
  ensures true
  example err_of(st: dot_error(st: take_char(st: start_state(), c: ".", mode: "dot", buf: "1"))) == "E100 1:1 unexpected character '.'"
do
  fail_at(st: st, code: "E100", line: get(list: here(st: st), index: 0), col: get(list: here(st: st), index: 1) - 1, message: "unexpected character '.'")
end

# 終わりまで読んだあと：途中の字句を出す
fn finish(st: Lex) -> Lex
  ensures true
  example err_of(st: finish(st: begin(st: start_state(), c: "\"", mode: "str", buf: ""))) == "E100 1:1 string is not closed"
do
  let mode: Str = mode_of(st: st)
  when
    err_of(st: st) != "" then st
    mode == "num" then emit(st: st, kind: "int")
    mode == "dot" then dot_error(st: st)
    mode == "id" then emit(st: st, kind: if is_keyword(word: buf_of(st: st)) then "kw" else "id" end)
    mode == "op" then if buf_of(st: st) == "!" then fail_at(st: st, code: "E100", line: get(list: started(st: st), index: 0), col: get(list: started(st: st), index: 1), message: "unexpected character '!'") else emit(st: st, kind: "op") end
    mode == "str" or mode == "esc" then fail_at(st: st, code: "E100", line: get(list: started(st: st), index: 0), col: get(list: started(st: st), index: 1), message: "string is not closed")
    else st
  end
end

# 字句の並び。読めなければ Err（"E100 行:列 説明"）
fn lex(text: Str) -> Result[List[Token]]
  ensures true
  example lex(text: "let x") == Ok(value: [Token(kind: "kw", text: "let", line: 1, col: 1), Token(kind: "id", text: "x", line: 1, col: 5)])
  example lex(text: "1.5") == Err(message: "E101 1:1 decimal numbers are not supported")
do
  let st: Lex = finish(st: fold(list: chars(text: text), init: start_state(), func: step))
  match st
    case Lex(mode: _, buf: _, at_line: _, at_col: _, line: _, col: _, toks: ts, err: e) then if e == "" then Ok(value: ts) else Err(message: e) end
  end
end
