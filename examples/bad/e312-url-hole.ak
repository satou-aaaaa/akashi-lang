# expect: E312
fn link(url: Str) -> Html ensures true example link(url: "a") == link(url: "a") do
  html(template: "<a href=\"{}\">open</a>", values: [html_text(value: url)])
end
