# expect: E207
fn area(w: Int, h: Int) -> Int ensures result >= 0 example area(h: 3, w: 2) == 6 do w * h end
