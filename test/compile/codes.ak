fn code(c: Str) -> Int
  requires str_len(text: c) == 1
  ensures true
  example code(c: "a") == 97
do
  code_of(char: c)
end

fn main(console: Console) -> Unit
do
  let t: Str = "aé𝄞あ😀b"
  print(to: console, value: slice(text: t, from: 0, to: 0))
  print(to: console, value: slice(text: t, from: 1, to: 4))
  print(to: console, value: slice(text: t, from: 0, to: 6))
  print(to: console, value: slice(text: t, from: 6, to: 6))
  print(to: console, value: map(list: chars(text: t), func: code))
  print(to: console, value: join(parts: map(list: [0, 127, 128, 2047, 2048, 65535, 65536, 1114111, 12354], func: char_of_), by: "|"))
  print(to: console, value: str_len(text: char_of(code: 0)))
end

fn char_of_(n: Int) -> Str
  requires n >= 0 and n <= 1114111 and (n < 55296 or n > 57343)
  ensures str_len(text: result) == 1
  example char_of_(n: 97) == "a"
do
  char_of(code: n)
end
