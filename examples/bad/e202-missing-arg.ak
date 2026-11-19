# expect: E202
fn area(w: Int, h: Int) -> Int ensures result >= 0 example area(w: 2) == 0 do w * h end
