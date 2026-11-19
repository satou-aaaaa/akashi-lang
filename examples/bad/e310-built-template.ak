# expect: E310
fn find(name: Str) -> Sql
  ensures true
  example find(name: "a") == find(name: "a")
do
  sql(template: "SELECT * FROM users WHERE name = '" ++ name ++ "'", values: [])
end
