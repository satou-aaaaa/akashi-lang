# expect: E309
fn main(console: Console) -> Unit do
  let c: Console = console
  print(to: c, value: 1)
end
