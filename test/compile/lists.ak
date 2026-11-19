fn double(x: Int) -> Int
  ensures result == x * 2
  example double(x: 2) == 4
do
  x * 2
end

fn is_big(x: Int) -> Bool
  ensures true
  example is_big(x: 5)
do
  x > 3
end

fn add(acc: Int, x: Int) -> Int
  ensures result == acc + x
  example add(acc: 1, x: 2) == 3
do
  acc + x
end

fn words(n: Int) -> Str
  ensures true
  example words(n: 1) == "1!"
do
  to_str(value: n) ++ "!"
end

fn main(console: Console) -> Unit
do
  let xs: List[Int] = [5, -2, 9, 0, 3, 9, -7]
  print(to: console, value: xs)
  print(to: console, value: len(list: xs))
  print(to: console, value: get(list: xs, index: 2))
  print(to: console, value: at(list: xs, index: 6))
  print(to: console, value: at(list: xs, index: 7))
  print(to: console, value: at(list: xs, index: -1))
  print(to: console, value: range(from: 3, to: 7))
  print(to: console, value: range(from: 7, to: 3))
  print(to: console, value: append(list: xs, item: 100))
  print(to: console, value: map(list: xs, func: double))
  print(to: console, value: map(list: xs, func: words))
  print(to: console, value: filter(list: xs, func: is_big))
  print(to: console, value: fold(list: xs, init: 0, func: add))
  print(to: console, value: find(list: xs, func: is_big))
  print(to: console, value: find(list: [1, 2], func: is_big))
  print(to: console, value: any(list: xs, func: is_big))
  print(to: console, value: all(list: xs, func: is_big))
  print(to: console, value: all(list: [], func: is_big))
  print(to: console, value: reverse(list: xs))
  print(to: console, value: take(list: xs, count: 3))
  print(to: console, value: take(list: xs, count: 30))
  print(to: console, value: drop(list: xs, count: 5))
  print(to: console, value: drop(list: xs, count: 50))
  print(to: console, value: sort(list: xs))
  print(to: console, value: sort(list: []))
  print(to: console, value: sort(list: range(from: 0, to: 0) ++ [3, 1, 2, 1, 3, 0, -1, 8, 4, 4, 2]))
  print(to: console, value: sum(list: xs))
  print(to: console, value: max(list: xs))
  print(to: console, value: min(list: xs))
  print(to: console, value: max(list: []))
  print(to: console, value: xs ++ [1] ++ [])
  print(to: console, value: [[1, 2], [], [3]])
  print(to: console, value: ["a", "q\"uote", "back\\slash", "new\nline", "tab\t", "あ"])
  print(to: console, value: to_str(value: [true, false]))
  print(to: console, value: [(), ()])
  print(to: console, value: [])
  print(to: console, value: [1, 2] == [1, 2])
  print(to: console, value: [1, 2] == [1, 3])
  print(to: console, value: [[1], [2, 3]] != [[1], [2]])
  print(to: console, value: ["a"] == ["a"])
  print(to: console, value: sum(list: map(list: range(from: 0, to: 1000), func: double)))
end
