# ほかのファイルの関数を使う（use）。パスは、このファイルからの相対パス
use "lib/words.ak"
use "lib/report.ak"

fn main(console: Console) -> Unit
do
  let text: Str = "the cat and the dog"
  print(to: console, value: count_words(text: text))
  print(to: console, value: summary(text: text))
end
