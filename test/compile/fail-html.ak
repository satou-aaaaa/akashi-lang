fn main(console: Console) -> Unit
do
  let parts: List[Html] = [html_text(value: "a"), html_text(value: "b")]
  print(to: console, value: html(template: "<p>{}</p>", values: parts))
end
