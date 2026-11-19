# compiler/lexer.ak を試す入口：渡したフォルダの input.ak を字句に分けて、1行に1つずつ出す（テストが src/parse.js の lex と比べる）
use "lexer.ak"

fn main(console: Console, folder: Folder) -> Unit
do
  match read_text(from: folder, path: "input.ak")
    case Ok(value: text) then print(to: console, value: show_tokens(toks: lex(text: text)))
    case Err(message: m) then print(to: console, value: "cannot read: " ++ m)
  end
end

fn show_tokens(toks: Result[List[Token]]) -> Str
  ensures true
  example show_tokens(toks: Err(message: "E100 1:1 x")) == "error E100 1:1 x"
do
  match toks
    case Ok(value: ts) then join(parts: map(list: ts, func: show_token), by: "\n")
    case Err(message: m) then "error " ++ m
  end
end

fn show_token(t: Token) -> Str
  ensures true
  example show_token(t: Token(kind: "id", text: "x", line: 1, col: 2, end_col: 3)) == "Token(kind: \"id\", text: \"x\", line: 1, col: 2, end_col: 3)"
do
  to_str(value: t)
end
