# compiler/check.ak が覚えた式の型を見る入口：関数ごとに「関数の名前 鍵 型」を1行ずつ出す（テストが src/check.js の e.ty と比べる）
use "files.ak"

fn main(console: Console, folder: Folder) -> Unit
do
  print(to: console, value: show_typed(got: load_program(folder: folder, main_name: main_name_in(folder: folder))))
end

fn show_typed(got: Loaded) -> Str
  ensures true
  example show_typed(got: Loaded(items: [], err: "E100 1:1 x")) == "E100 1:1 x"
do
  match got
    case Loaded(items: items, err: e) then if e != "" then e else
      match check_all(items: items)
        case Typed(diags: _, fns: fs, items: _) then join(parts: concat(lists: map(list: fs, func: fn_type_lines)), by: "\n")
      end
    end
  end
end

fn fn_type_lines(f: FnTypes) -> List[Str]
  ensures true
  example fn_type_lines(f: FnTypes(name: "f", types: dict(keys: ["int 1:1"], values: [Ty(k: "Int", name: "", args: [])]))) == ["f int 1:1 Int"]
do
  match f
    case FnTypes(name: n, types: ts) then
      match fold(list: dict_keys(dict: ts), init: TLines(name: n, types: ts, out: []), func: type_line)
        case TLines(name: _, types: _, out: o) then o
      end
  end
end

type TLines
  case TLines(name: Str, types: Dict[Ty], out: List[Str])
end

fn type_line(acc: TLines, k: Str) -> TLines
  ensures true
  example type_line(acc: TLines(name: "f", types: dict(keys: [], values: []), out: []), k: "x") == TLines(name: "f", types: dict(keys: [], values: []), out: ["f x ?"])
do
  match acc
    case TLines(name: n, types: ts, out: o) then TLines(name: n, types: ts, out: append(list: o, item: n ++ " " ++ k ++ " " ++ type_str(t: match dict_get(dict: ts, key: k)
      case Some(value: t) then t
      case None then t_err()
    end)))
  end
end
