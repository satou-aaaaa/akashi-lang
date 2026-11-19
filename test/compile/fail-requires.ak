fn half(n: Int) -> Int
  requires n % 2 == 0
  ensures result * 2 == n
  example half(n: 4) == 2
do
  n / 2
end

fn main(console: Console) -> Unit
do
  print(to: console, value: half(n: 8))
  print(to: console, value: half(n: 3))
end
