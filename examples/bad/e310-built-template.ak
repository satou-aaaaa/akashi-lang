# expect: E310
fn find_user(name: Str) -> Sql
  ensures true
  example find_user(name: "a") == find_user(name: "a")
do
  sql(template: "SELECT * FROM users WHERE name = '" ++ name ++ "'", values: [])
end
