# expect: E212
type Shape
  case Rect(width: Int, height: Int)
end

fn width_of(shape: Shape) -> Int
  ensures true
  example width_of(shape: Rect(width: 2, height: 3)) == 2
do
  match shape
    case Rect(width: w) then w
  end
end
