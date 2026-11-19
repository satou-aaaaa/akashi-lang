# expect: R500
fn half(n: Int) -> Int requires n % 2 == 0 ensures true example half(n: 4) == 2 do n / 2 end
fn main() -> Unit effects io do print(value: half(n: 3)) end
