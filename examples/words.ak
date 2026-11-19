# 標準の道具で文を数える：分ける・数える・並べる・つなぐ
fn word_count(text: Str) -> Int
  ensures result >= 0
  example word_count(text: "a b  c") == 3
  example word_count(text: "") == 0
do
  len(list: filter(list: split(text: trim(text: text), by: " "), func: not_empty))
end

fn not_empty(s: Str) -> Bool
  ensures result == (s != "")
  example not_empty(s: "x")
do
  s != ""
end

fn word_size(s: Str) -> Int
  ensures result >= 0
  example word_size(s: "abc") == 3
do
  str_len(text: s)
end

fn main(console: Console) -> Unit
do
  let text: Str = "  the quick brown fox jumps  "
  let words: List[Str] = filter(list: split(text: trim(text: text), by: " "), func: not_empty)
  let sizes: List[Int] = map(list: words, func: word_size)
  print(to: console, value: word_count(text: text))
  print(to: console, value: join(parts: reverse(list: words), by: " "))
  print(to: console, value: sort(list: sizes))
  print(to: console, value: [sum(list: sizes), len(list: take(list: words, count: 2))])
  match max(list: sizes)
    case Some(value: m) then print(to: console, value: "longest = " ++ to_str(value: m))
    case None then print(to: console, value: "no words")
  end
end
