# expect: R501
fn abs(x: Int) -> Int ensures result >= 0 example abs(x: 0) == 0 do x end
fn main(console: Console) -> Unit do print(to: console, value: abs(x: -5)) end
