# expect: R511
fn abs(x: Int) -> Int
  ensures result >= 0
  example abs(x: 3) == 3
do
  x
end
