# expect: R509
fn main(console: Console, folder: Folder) -> Unit do
  print(to: console, value: read_text(from: folder, path: "fruits.txt"))
end
