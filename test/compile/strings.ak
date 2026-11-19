fn shout(s: Str) -> Str
  ensures true
  example shout(s: "a") == "a!"
do
  s ++ "!"
end

fn main(console: Console) -> Unit
do
  print(to: console, value: chars(text: "aあ😀b"))
  print(to: console, value: chars(text: ""))
  print(to: console, value: split(text: "a,b,,c", by: ","))
  print(to: console, value: split(text: "", by: ","))
  print(to: console, value: split(text: ",a,", by: ","))
  print(to: console, value: split(text: "aaa", by: "aa"))
  print(to: console, value: split(text: "日本の本", by: "本"))
  print(to: console, value: join(parts: ["x", "y", "z"], by: ", "))
  print(to: console, value: join(parts: [], by: "-"))
  print(to: console, value: join(parts: map(list: ["a", "b"], func: shout), by: ""))
  print(to: console, value: contains(text: "hello", part: "ll"))
  print(to: console, value: contains(text: "hello", part: ""))
  print(to: console, value: contains(text: "", part: "a"))
  print(to: console, value: contains(text: "abc", part: "abcd"))
  print(to: console, value: starts_with(text: "hello", prefix: "he"))
  print(to: console, value: starts_with(text: "he", prefix: "hello"))
  print(to: console, value: ends_with(text: "hello", suffix: "llo"))
  print(to: console, value: ends_with(text: "hello", suffix: ""))
  print(to: console, value: ends_with(text: "lo", suffix: "hello"))
  print(to: console, value: lines(text: "a\nb\n"))
  print(to: console, value: lines(text: ""))
  print(to: console, value: lines(text: "\n"))
  print(to: console, value: lines(text: "x\n\ny"))
  print(to: console, value: html(template: "<p>{} & {}</p>", values: [html_text(value: "<a href=\"x\">'&'</a>"), html_join(parts: [])]))
  print(to: console, value: [html_text(value: "<i>")])
  print(to: console, value: html(template: "<br>", values: []))
  print(to: console, value: sql(template: "SELECT * FROM t WHERE a = ? AND b = ?", values: ["x\"y", "1"]))
  print(to: console, value: sql(template: "SELECT 1", values: []))
  print(to: console, value: to_str(value: html_text(value: "a")))
end
