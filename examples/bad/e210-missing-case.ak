# expect: E210
type Light
  case Red
  case Yellow
  case Green
end

fn can_go(light: Light) -> Bool
  ensures true
  example can_go(light: Green) == true
do
  match light
    case Red then false
    case Green then true
  end
end
