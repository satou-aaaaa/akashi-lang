fn tell(console: Console, n: Int) -> Int
  ensures result > 0
do
  print(to: console, value: n)
  n
end

fn main(console: Console) -> Unit
do
  print(to: console, value: tell(console: console, n: 0))
end
