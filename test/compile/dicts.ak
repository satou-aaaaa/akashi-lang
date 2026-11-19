fn count_words(text: Str) -> Dict[Int]
  ensures dict_size(dict: result) <= len(list: split(text: text, by: " "))
  example count_words(text: "a b a") == dict(keys: ["b", "a"], values: [1, 2])
do
  fold(list: split(text: text, by: " "), init: dict(keys: [], values: []), func: bump)
end

fn bump(d: Dict[Int], word: Str) -> Dict[Int]
  ensures dict_has(dict: result, key: word)
  example bump(d: dict(keys: [], values: []), word: "x") == dict(keys: ["x"], values: [1])
do
  match dict_get(dict: d, key: word)
    case Some(value: n) then dict_put(dict: d, key: word, value: n + 1)
    case None then dict_put(dict: d, key: word, value: 1)
  end
end

fn main(console: Console) -> Unit
do
  let d: Dict[Int] = count_words(text: "b a c a b a é 😀 z")
  print(to: console, value: d)
  print(to: console, value: dict_keys(dict: d))
  print(to: console, value: dict_values(dict: d))
  print(to: console, value: dict_size(dict: dict_remove(dict: d, key: "a")))
  print(to: console, value: dict_has(dict: d, key: "z"))
  print(to: console, value: to_str(value: d) ++ "!")
  print(to: console, value: [d])
  print(to: console, value: dict_get(dict: d, key: "a"))
  print(to: console, value: d == dict(keys: ["c", "b", "a"], values: [1, 2, 3]))
  nested(console: console)
end

fn nested(console: Console) -> Unit
do
  let inner: Dict[List[Str]] = dict(keys: ["x", "y"], values: [["1", "2"], []])
  let outer: Dict[Dict[List[Str]]] = dict_put(dict: dict(keys: [], values: []), key: "in", value: inner)
  print(to: console, value: outer)
  print(to: console, value: dict_get(dict: outer, key: "out"))
  print(to: console, value: dict_values(dict: dict_remove(dict: inner, key: "x")))
  print(to: console, value: dict(keys: ["t"], values: [true]) == dict(keys: ["t"], values: [true]))
  print(to: console, value: dict(keys: ["s"], values: [Some(value: "q\"")]))
end
