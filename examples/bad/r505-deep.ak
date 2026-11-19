# expect: R505
fn loop(console: Console, n: Int) -> Int do if n == 0 then 0 else loop(console: console, n: n + 1) end end
fn main(console: Console) -> Unit do print(to: console, value: loop(console: console, n: 1)) end
