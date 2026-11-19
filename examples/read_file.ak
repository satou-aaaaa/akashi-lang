# ファイルを読むプログラム。読んでよいのは実行するときに --allow-read で渡したフォルダの中だけ
# read_text は Result[Str] を返す。読めなかったとき（Err）も書かないと検査が通らない
# grant: examples/files
fn count_lines(text: Str) -> Int
  ensures result >= 0
  example count_lines(text: "a\nb\n") == 2
  example count_lines(text: "") == 0
do
  len(list: lines(text: text))
end

fn main(console: Console, folder: Folder) -> Unit
do
  match read_text(from: folder, path: "fruits.txt")
    case Ok(value: text) then show_lines(console: console, text: text)
    case Err(message: why) then print(to: console, value: "could not read: " ++ why)
  end
  match read_text(from: folder, path: "nothing.txt")
    case Ok(value: _) then print(to: console, value: "unexpected")
    case Err(message: why2) then print(to: console, value: "could not read: " ++ why2)
  end
end

fn show_lines(console: Console, text: Str) -> Unit
do
  print(to: console, value: lines(text: text))
  print(to: console, value: "lines = " ++ to_str(value: count_lines(text: text)))
end
