# expect: E300
fn shout(s: Str) -> Unit ensures true example shout(s: "a") == () do print(value: s) end
