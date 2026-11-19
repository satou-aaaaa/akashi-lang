# expect: E304
fn show(console: Console, x: Int) -> Unit do print(to: console, value: x) end
fn main(console: Console) -> Unit do
  let u: List[Unit] = map(list: [1], func: show)
  print(to: console, value: 1)
end
