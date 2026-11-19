# expect: E201
fn greet(name: Str) -> Str ensures true example greet(name: "a") == "hi a" do "hi " + name end
