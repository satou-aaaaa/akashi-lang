# expect: E200
fn double(x: Int) -> Int ensures result == x * 2 example double(x: 2) == 4 do x * 2 end
fn main() -> Unit effects io do print(value: dubble(x: 3)) end
