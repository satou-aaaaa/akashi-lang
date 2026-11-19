# expect: R501
# (functions with capabilities are not tried with generated inputs, so this one is only caught while running)
fn report_abs(console: Console, x: Int) -> Int ensures result >= 0 do
  print(to: console, value: x)
  x
end

fn main(console: Console) -> Unit do print(to: console, value: report_abs(console: console, x: -5)) end
