# expect: E300
fn shout(text: Str) -> Unit do print(to: console, value: text) end
fn main(console: Console) -> Unit do shout(text: "hi") end
