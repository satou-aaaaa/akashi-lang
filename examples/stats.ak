# リストの合計・平均（切り捨て）・偶数だけ。ループは無く、map / filter / fold を使う
fn add(acc: Int, x: Int) -> Int
  ensures result == acc + x
  example add(acc: 1, x: 2) == 3
do
  acc + x
end

fn sum(xs: List[Int]) -> Int
  ensures len(list: xs) > 0 or result == 0
  example sum(xs: [1, 2, 3]) == 6
  example sum(xs: []) == 0
do
  fold(list: xs, init: 0, func: add)
end

fn mean(xs: List[Int]) -> Int
  requires len(list: xs) > 0
  ensures true
  example mean(xs: [2, 4, 9]) == 5
do
  sum(xs: xs) / len(list: xs)
end

fn is_even(x: Int) -> Bool
  ensures result == (x % 2 == 0)
  example is_even(x: 4)
  example not is_even(x: 3)
do
  x % 2 == 0
end

fn main() -> Unit
  effects io
do
  let data: List[Int] = [3, 8, 1, 6, 10]
  let evens: List[Int] = filter(list: data, func: is_even)
  print(value: "sum = " ++ to_str(value: sum(xs: data)))
  print(value: "mean = " ++ to_str(value: mean(xs: data)))
  print(value: evens)
end
