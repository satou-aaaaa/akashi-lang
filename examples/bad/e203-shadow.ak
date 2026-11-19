# expect: E203
fn main(console: Console) -> Unit do
  let x: Int = 1
  let x: Int = 2
  print(to: console, value: x)
end
