fn shout(s: Str) -> Str
  ensures str_len(text: result) == str_len(text: s) + 1
  example shout(s: "a") == "a!"
do
  s ++ "!"
end

fn main(console: Console) -> Unit
do
  print(to: console, value: shout(s: "hello"))
  print(to: console, value: str_len(text: "あいう😀"))
  print(to: console, value: "n=" ++ to_str(value: -120) ++ " " ++ to_str(value: true))
  print(to: console, value: "ab" == "ab" and "ab" != "abc")
  print(to: console, value: ())
  print(to: console, value: "")
  print(to: console, value: "tab\tquote\"back\\")
end
