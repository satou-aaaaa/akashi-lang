# ファイルを読むプログラム。読んでよいのは実行するときに --allow-read で渡したフォルダの中だけ
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
  let text: Str = read_text(from: folder, path: "fruits.txt")
  print(to: console, value: lines(text: text))
  print(to: console, value: "lines = " ++ to_str(value: count_lines(text: text)))
end
