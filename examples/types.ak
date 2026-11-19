# 自分で作る型（type）と、漏れの無い場合分け（match）。null の代わりに Option を使う
type Shape
  case Circle(radius: Int)
  case Rect(width: Int, height: Int)
  case Dot
end

fn area(shape: Shape) -> Int
  ensures result >= 0
  example area(shape: Rect(width: 2, height: 3)) == 6
  example area(shape: Dot) == 0
do
  match shape
    case Circle(radius: r) then 3 * r * r
    case Rect(width: w, height: h) then if w < 0 or h < 0 then 0 else w * h end
    case Dot then 0
  end
end

fn first_number(texts: List[Str]) -> Option[Int]
  ensures true
  example first_number(texts: ["x", "42"]) == Some(value: 42)
  example first_number(texts: []) == None
do
  let nums: List[Option[Int]] = map(list: texts, func: to_int)
  let found: Option[Option[Int]] = find(list: nums, func: is_some)
  match found
    case Some(value: n) then n
    case None then None
  end
end

fn to_int(text: Str) -> Option[Int]
  ensures true
  example to_int(text: "7") == Some(value: 7)
do
  parse_int(text: text)
end

fn is_some(x: Option[Int]) -> Bool
  ensures true
  example is_some(x: None) == false
do
  match x
    case Some(value: _) then true
    case None then false
  end
end

fn main(console: Console) -> Unit do
  print(to: console, value: area(shape: Circle(radius: 2)))
  print(to: console, value: first_number(texts: ["a", "-5", "9"]))
  print(to: console, value: [Dot, Rect(width: 1, height: 2)])
end
