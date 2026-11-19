# expect: E211
fn or_zero(x: Option[Int]) -> Int
  ensures true
  example or_zero(x: None) == 0
do
  match x
    case Some(value: n) then n
    else 0
  end
end
