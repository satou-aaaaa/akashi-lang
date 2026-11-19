# expect: E112
fn size(n: Int) -> Str ensures true example size(n: 1) == "small" do
  when
    n < 10 then "small"
    n < 100 then "medium"
  end
end
