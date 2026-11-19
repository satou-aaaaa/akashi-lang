# expect: R512
fn per_item(total: Int, count: Int) -> Int
  ensures true
  example per_item(total: 10, count: 2) == 5
do
  total / count
end
