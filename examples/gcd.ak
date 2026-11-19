# 最大公約数。requires は呼ぶ側への約束、ensures は結果の約束、example は動く見本（check で全部回る）
fn gcd(a: Int, b: Int) -> Int
  requires a >= 0 and b >= 0
  ensures result >= 0
  example gcd(a: 12, b: 18) == 6
  example gcd(a: 7, b: 0) == 7
do
  if b == 0 then a else gcd(a: b, b: a % b) end
end

fn main(console: Console) -> Unit
do
  print(to: console, value: gcd(a: 1071, b: 462))
end
