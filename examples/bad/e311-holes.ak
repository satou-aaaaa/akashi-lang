# expect: E311
fn greet(name: Str) -> Html ensures true example greet(name: "a") == greet(name: "a") do
  html(template: "<p>{} and {}</p>", values: [html_text(value: name)])
end
