# expect: R502
fn inc(x: Int) -> Int ensures true example inc(x: 1) == 3 do x + 1 end
