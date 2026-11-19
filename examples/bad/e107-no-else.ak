# expect: E107
fn f(x: Int) -> Int ensures true example f(x: 1) == 1 do if x > 0 then 1 end end
