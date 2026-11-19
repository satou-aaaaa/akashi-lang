# expect: E200
fn double(x: Int) -> Int ensures result == x * 2 example double(x: 2) == 4 do x * 2 end
fn main(console: Console) -> Unit do print(to: console, value: dubble(x: 3)) end
