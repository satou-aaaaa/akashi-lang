# compiler/parser.ak を試す入口：渡したフォルダの input.ak を読んで木を1行で出す（テストが src/parse.js の parse と比べる）
# types.txt があれば、use で読むほかのファイルで決めた型の名前（空白で区切る）として渡す
use "parser.ak"

fn main(console: Console, folder: Folder) -> Unit
do
  let other: List[Str] = match read_text(from: folder, path: "types.txt")
    case Ok(value: t) then filter(list: split(text: trim(text: t), by: " "), func: not_empty)
    case Err(message: _) then []
  end
  match read_text(from: folder, path: "input.ak")
    case Ok(value: text) then print(to: console, value: show_tree(tree: parse(text: text, other_types: other)))
    case Err(message: m) then print(to: console, value: "cannot read: " ++ m)
  end
end

fn not_empty(s: Str) -> Bool
  ensures true
  example not not_empty(s: "")
do
  s != ""
end

fn show_tree(tree: Result[Node]) -> Str
  ensures true
  example show_tree(tree: Err(message: "E100 1:1 x")) == "error E100 1:1 x"
do
  match tree
    case Ok(value: n) then to_str(value: n)
    case Err(message: m) then "error " ++ m
  end
end
