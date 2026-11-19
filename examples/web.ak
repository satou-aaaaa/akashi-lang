# 外から来た文字（名前やコメント）を HTML と SQL に入れる。型紙は書いたままの文字だけで、値は values から差し込む
# HTML の穴に入るのは Html だけ。Str は text() を通すと自動でエスケープされる
fn row(name: Str) -> Html
  ensures true
  example to_str(value: row(name: "<b>")) == "<li>&lt;b&gt;</li>"
do
  html(template: "<li>{}</li>", values: [html_text(value: name)])
end

fn page(names: List[Str]) -> Html
  ensures true
  example to_str(value: page(names: ["a"])) == "<ul><li>a</li></ul>"
do
  html(template: "<ul>{}</ul>", values: [html_join(parts: map(list: names, func: row))])
end

fn find_user(name: Str) -> Sql
  ensures true
  example to_str(value: find_user(name: "x")) == "SELECT id FROM users WHERE name = ? -- params: [\"x\"]"
do
  sql(template: "SELECT id FROM users WHERE name = ?", values: [name])
end

fn main(console: Console) -> Unit
do
  let names: List[Str] = ["Alice", "<script>alert(1)</script>"]
  print(to: console, value: page(names: names))
  print(to: console, value: find_user(name: "x' OR '1'='1"))
end
