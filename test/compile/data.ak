type Shape
  case Circle(radius: Int)
  case Rect(width: Int, height: Int)
  case Dot
end

type Tree
  case Leaf
  case Node(left: Tree, value: Int, right: Tree)
end

type Named
  case Named(name: Str, tags: List[Str], next: Option[Int])
end

fn area(shape: Shape) -> Int
  ensures true
  example area(shape: Dot) == 0
do
  match shape
    case Circle(radius: r) then 3 * r * r
    case Rect(width: w, height: h) then w * h
    case Dot then 0
  end
end

fn insert(tree: Tree, x: Int) -> Tree
  ensures true
  example insert(tree: Leaf, x: 1) == Node(left: Leaf, value: 1, right: Leaf)
do
  match tree
    case Leaf then Node(left: Leaf, value: x, right: Leaf)
    case Node(left: l, value: v, right: r) then
      if x < v then Node(left: insert(tree: l, x: x), value: v, right: r) else Node(left: l, value: v, right: insert(tree: r, x: x)) end
  end
end

fn add_to(tree: Tree, x: Int) -> Tree
  ensures true
  example add_to(tree: Leaf, x: 2) == Node(left: Leaf, value: 2, right: Leaf)
do
  insert(tree: tree, x: x)
end

fn total(tree: Tree) -> Int
  ensures true
  example total(tree: Leaf) == 0
do
  match tree
    case Leaf then 0
    case Node(left: l, value: v, right: r) then total(tree: l) + v + total(tree: r)
  end
end

fn safe_div(a: Int, b: Int) -> Result[Int]
  ensures true
  example safe_div(a: 6, b: 3) == Ok(value: 2)
do
  if b == 0 then Err(message: "divide by \"zero\"") else Ok(value: a / b) end
end

fn describe(r: Result[Int]) -> Str
  ensures true
  example describe(r: Ok(value: 1)) == "ok 1"
do
  match r
    case Ok(value: v) then "ok " ++ to_str(value: v)
    case Err(message: m) then "error: " ++ m
  end
end

fn main(console: Console) -> Unit
do
  let shapes: List[Shape] = [Circle(radius: 2), Rect(width: 3, height: 4), Dot]
  print(to: console, value: shapes)
  print(to: console, value: map(list: shapes, func: area))
  let t: Tree = fold(list: [5, 2, 8, 1, 9, 3], init: Leaf, func: add_to)
  print(to: console, value: t)
  print(to: console, value: total(tree: t))
  print(to: console, value: safe_div(a: 7, b: 2))
  print(to: console, value: safe_div(a: 7, b: 0))
  print(to: console, value: describe(r: safe_div(a: 9, b: 3)))
  print(to: console, value: describe(r: safe_div(a: 9, b: 0)))
  print(to: console, value: Named(name: "x", tags: ["a", "b"], next: None))
  print(to: console, value: Named(name: "y", tags: [], next: Some(value: -3)))
  print(to: console, value: Some(value: Some(value: "s")))
  print(to: console, value: Dot == Dot)
  print(to: console, value: Circle(radius: 1) == Circle(radius: 1))
  print(to: console, value: Circle(radius: 1) == Circle(radius: 2))
  print(to: console, value: Circle(radius: 1) == Dot)
  print(to: console, value: t == t)
  print(to: console, value: Some(value: [1]) == Some(value: [1]))
  print(to: console, value: to_str(value: Ok(value: "v")))
end
