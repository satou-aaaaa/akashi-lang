# compiler/check.ak を試す入口：渡したフォルダの main のファイルを、use をたどって全部読み、型の検査をしてエラーを1行ずつ出す（無ければ ok）
# main のファイルの名前は main.txt に書く（無ければ main.ak）。use のパスは src/modules.js と同じ決まりで読む
# テストが src/core.js の analyze（parseProgram ＋ check）と比べる
use "files.ak"

fn main(console: Console, folder: Folder) -> Unit
do
  print(to: console, value: check_loaded(got: load_program(folder: folder, main_name: main_name_in(folder: folder))))
end

fn check_loaded(got: Loaded) -> Str
  ensures true
  example check_loaded(got: Loaded(items: [], err: "E100 1:1 x")) == "E100 1:1 x"
  example check_loaded(got: Loaded(items: items_of(file: "", program: program_of(text: "fn main(console: Console) -> Unit do print(to: console, value: 1) end")), err: "")) == "ok"
do
  match got
    case Loaded(items: items, err: e) then if e != "" then e else show_diags(ds: check_program(items: items)) end
  end
end

fn show_diags(ds: List[Diag]) -> Str
  ensures true
  example show_diags(ds: []) == "ok"
do
  if ds == [] then "ok" else join(parts: map(list: ds, func: show_diag), by: "\n") end
end
