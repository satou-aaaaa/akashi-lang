# expect: E108
fn sign(n: Int) -> Int ensures true example sign(n: 5) == 1 do
  if n > 0 then 1 else 0 end end
end
