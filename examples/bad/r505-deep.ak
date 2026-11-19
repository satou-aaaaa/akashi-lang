# expect: R505
fn loop(n: Int) -> Int ensures true example loop(n: 0) == 0 do if n == 0 then 0 else loop(n: n + 1) end end
fn main(console: Console) -> Unit do print(to: console, value: loop(n: 1)) end
