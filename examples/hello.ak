# いちばん小さいプログラム。画面に出す権利（Console）は main が受け取り、使う関数へ引数で渡す
fn main(console: Console) -> Unit
do
  print(to: console, value: "hello, akashi")
end
