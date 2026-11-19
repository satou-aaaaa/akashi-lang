# expect: R510
fn main(console: Console) -> Unit do
  let names: List[Html] = [html_text(value: "a"), html_text(value: "b")]
  print(to: console, value: html(template: "<p>{}</p>", values: names))
end
