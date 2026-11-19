# use "lib/words.ak" で読まれる部品。main は書かない（E115）
fn count_words(text: Str) -> Dict[Int]
  ensures dict_size(dict: result) <= len(list: split(text: text, by: " "))
  example count_words(text: "a b a") == dict(keys: ["a", "b"], values: [2, 1])
do
  fold(list: split(text: text, by: " "), init: dict(keys: [], values: []), func: add_word)
end

fn add_word(counts: Dict[Int], word: Str) -> Dict[Int]
  ensures dict_has(dict: result, key: word)
  example add_word(counts: dict(keys: [], values: []), word: "x") == dict(keys: ["x"], values: [1])
do
  match dict_get(dict: counts, key: word)
    case Some(value: n) then dict_put(dict: counts, key: word, value: n + 1)
    case None then dict_put(dict: counts, key: word, value: 1)
  end
end
