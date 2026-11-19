# expect: R508
# grant: examples/files
fn main(console: Console, folder: Folder) -> Unit do
  print(to: console, value: read_text(from: folder, path: "nothing.txt"))
end
