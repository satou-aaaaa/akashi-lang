fn safe(a: Int, b: Int) -> Bool
  ensures true
  example safe(a: 1, b: 0) == false
do
  b != 0 and a / b > 0
end

fn grade(n: Int) -> Str
  requires n >= 0
  ensures str_len(text: result) == 1
  example grade(n: 95) == "A"
do
  when
    n >= 90 then "A"
    n >= 70 then "B"
    else "C"
  end
end

fn main(console: Console) -> Unit
do
  print(to: console, value: safe(a: 5, b: 0))
  print(to: console, value: safe(a: 5, b: 2))
  print(to: console, value: true or 1 / 0 == 0)
  print(to: console, value: not (1 < 2))
  print(to: console, value: grade(n: 95) ++ grade(n: 70) ++ grade(n: 3))
  let x: Int = if 2 > 1 then 10 else 20 end
  print(to: console, value: x <= 10 and x >= 10)
end
