# Akashi で書いたコンパイラの入口：渡したフォルダの main のファイル（main.txt に名前。無ければ main.ak）を、use をたどって読み、
# 型を調べて .wasm にし、書くフォルダに out.wasm として書く。出すのは ok か、エラーの文（1行ずつ）
use "files.ak"
use "wasm.ak"

fn main(console: Console, folder: Folder, out: OutFolder) -> Unit
do
  match build_loaded(got: load_program(folder: folder, main_name: main_name_in(folder: folder)))
    case Built(bytes: bs, err: e) then if e != "" then print(to: console, value: e) else
      match write_bytes(to: out, path: "out.wasm", bytes: bs)
        case Ok(value: _) then print(to: console, value: "ok")
        case Err(message: m) then print(to: console, value: "cannot write: " ++ m)
      end
    end
  end
end

fn build_loaded(got: Loaded) -> Built
  ensures true
  example build_loaded(got: Loaded(items: [], err: "E100 1:1 x")) == Built(bytes: [], err: "E100 1:1 x")
do
  match got
    case Loaded(items: items, err: e) then if e != "" then Built(bytes: [], err: e) else build_checked(typed: check_all(items: items)) end
  end
end

fn build_checked(typed: Typed) -> Built
  ensures true
  example build_checked(typed: Typed(diags: [Diag(file: "", code: "E200", line: 1, col: 2, message: "m")], fns: [], items: [])) == Built(bytes: [], err: "E200 1:2 m")
do
  match typed
    case Typed(diags: ds, fns: _, items: _) then if ds != [] then Built(bytes: [], err: join(parts: map(list: ds, func: show_diag), by: "\n")) else compile_typed(typed: typed) end
  end
end
