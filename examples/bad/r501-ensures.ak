# expect: R501
fn abs(x: Int) -> Int ensures result >= 0 example abs(x: 0) == 0 do x end
fn main() -> Unit effects io do print(value: abs(x: -5)) end
