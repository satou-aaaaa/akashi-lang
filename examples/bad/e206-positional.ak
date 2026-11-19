# expect: E206
fn area(w: Int, h: Int) -> Int ensures result >= 0 example area(2, 3) == 6 do w * h end
