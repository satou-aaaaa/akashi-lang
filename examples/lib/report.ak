# 部品から部品を使ってもよい（同じファイルは1回だけ読む）
use "words.ak"

fn summary(text: Str) -> Str
  ensures true
  example summary(text: "b a b") == "a, b (2 words)"
do
  let counts: Dict[Int] = count_words(text: text)
  join(parts: dict_keys(dict: counts), by: ", ") ++ " (" ++ to_str(value: dict_size(dict: counts)) ++ " words)"
end
