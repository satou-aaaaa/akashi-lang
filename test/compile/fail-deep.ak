fn down(console: Console, n: Int) -> Int
do
  if n == 0 then 0 else down(console: console, n: n - 1) end
end

fn main(console: Console) -> Unit
do
  print(to: console, value: down(console: console, n: 498))
  print(to: console, value: down(console: console, n: 600))
end
