fn label(n: Int) -> Str
  requires n >= 1
  ensures str_len(text: result) >= 1
  example label(n: 3) == "Fizz"
  example label(n: 10) == "Buzz"
  example label(n: 30) == "FizzBuzz"
  example label(n: 7) == "7"
do
  when
    n % 15 == 0 then "FizzBuzz"
    n % 3 == 0 then "Fizz"
    n % 5 == 0 then "Buzz"
    else to_str(value: n)
  end
end

fn main(console: Console) -> Unit
do
  print(to: console, value: map(list: range(from: 1, to: 16), func: label))
end
