fn main(console: Console) -> Unit
do
  print(to: console, value: parse_int(text: "42"))
  print(to: console, value: parse_int(text: "  -17\n"))
  print(to: console, value: parse_int(text: "-0"))
  print(to: console, value: parse_int(text: "007"))
  print(to: console, value: parse_int(text: ""))
  print(to: console, value: parse_int(text: "-"))
  print(to: console, value: parse_int(text: "1 2"))
  print(to: console, value: parse_int(text: "+5"))
  print(to: console, value: parse_int(text: "１２"))
  print(to: console, value: parse_int(text: "9007199254740991"))
  print(to: console, value: parse_int(text: "-9007199254740991"))
  print(to: console, value: parse_int(text: "9007199254740992"))
  print(to: console, value: parse_int(text: "99999999999999999999999"))
  print(to: console, value: parse_int(text: "　12　"))
  print(to: console, value: "[" ++ trim(text: " \t a b \n") ++ "]")
  print(to: console, value: "[" ++ trim(text: "  x　﻿") ++ "]")
  print(to: console, value: "[" ++ trim(text: "   ") ++ "]")
  print(to: console, value: "[" ++ trim(text: "あいう") ++ "]")
end
