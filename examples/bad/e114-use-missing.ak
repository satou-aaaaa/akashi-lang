# expect: E114
use "lib/missing.ak"

fn main(console: Console) -> Unit
do
  print(to: console, value: 1)
end
