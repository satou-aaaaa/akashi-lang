# expect: E115
use "lib/has_main.ak"

fn main(console: Console) -> Unit
do
  print(to: console, value: 1)
end
