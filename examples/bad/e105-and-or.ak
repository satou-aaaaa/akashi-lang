# expect: E105
fn f(a: Bool, b: Bool, c: Bool) -> Bool ensures true example f(a: true, b: true, c: true) do a and b or c end
