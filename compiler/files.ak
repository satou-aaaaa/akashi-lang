# プログラムのファイルを読む：main のファイルから use をたどって全部のファイルを読み、構文解析して部品（Item）の並びにする
# use のパスは src/modules.js と同じ決まり（E113・E114・E115 も同じ）。型の検査（check_main.ak）とコンパイル（build_main.ak）が使う
use "check.ak"

# 読んだ結果：全部のファイルの部品と、止まったときのエラー（"" なら止まっていない）
type Loaded
  case Loaded(items: List[Item], err: Str)
end

# フォルダの main_name のファイルから読む
fn load_program(folder: Folder, main_name: Str) -> Loaded
do
  match read_text(from: folder, path: main_name)
    case Ok(value: text) then parse_files(got: gather(folder: folder, files: [SrcFile(name: "", text: text)], k: 0, err: first_lex_error(name: "", text: text)))
    case Err(message: m) then Loaded(items: [], err: "cannot read: " ++ m)
  end
end

# main のファイルの名前：main.txt に書いたもの（無ければ main.ak）
fn main_name_in(folder: Folder) -> Str
do
  match read_text(from: folder, path: "main.txt")
    case Ok(value: t) then trim(text: t)
    case Err(message: _) then "main.ak"
  end
end

# 全部のファイルを構文解析する（型の名前は全部のファイルのものを渡す）
fn parse_files(got: Gathered) -> Loaded
  ensures true
  example parse_files(got: Gathered(files: [], err: "E100 1:1 x")) == Loaded(items: [], err: "E100 1:1 x")
do
  match got
    case Gathered(files: fs, err: e) then if e != "" then Loaded(items: [], err: e) else
      match fold(list: fs, init: Parsing(types: concat(lists: map(list: map(list: fs, func: sf_toks), func: type_names)), items: [], err: ""), func: parse_step)
        case Parsing(types: _, items: items, err: pe) then Loaded(items: items, err: pe)
      end
    end
  end
end

# 読んだファイル：名前（main のファイルは ""）・中身・字句
type SrcFile
  case SrcFile(name: Str, text: Str)
end

# 読み終わったファイルと、止まったときのエラー（"" なら止まっていない）
type Gathered
  case Gathered(files: List[SrcFile], err: Str)
end

fn sf_name(f: SrcFile) -> Str
  ensures true
  example sf_name(f: SrcFile(name: "a.ak", text: "")) == "a.ak"
do
  match f
    case SrcFile(name: n, text: _) then n
  end
end

fn sf_text(f: SrcFile) -> Str
  ensures true
  example sf_text(f: SrcFile(name: "", text: "x")) == "x"
do
  match f
    case SrcFile(name: _, text: t) then t
  end
end

fn sf_toks(f: SrcFile) -> List[Token]
  ensures true
  example len(list: sf_toks(f: SrcFile(name: "", text: "x"))) == 1
do
  match f
    case SrcFile(name: _, text: t) then lex_ok(text: t)
  end
end

# エラーの文の前に、どのファイルかを付ける（main のファイルなら付けない）
fn in_file(name: Str, message: Str) -> Str
  ensures true
  example in_file(name: "a.ak", message: "E100 1:1 x") == "a.ak: E100 1:1 x"
  example in_file(name: "", message: "E100 1:1 x") == "E100 1:1 x"
do
  if name == "" then message else name ++ ": " ++ message end
end

fn first_lex_error(name: Str, text: Str) -> Str
  ensures true
  example first_lex_error(name: "a.ak", text: "1.5") == "a.ak: E101 1:1 decimal numbers are not supported"
  example first_lex_error(name: "", text: "x") == ""
do
  match lex(text: text)
    case Ok(value: _) then ""
    case Err(message: m) then in_file(name: name, message: m)
  end
end

fn sf_at(files: List[SrcFile], k: Int) -> SrcFile
  ensures true
  example sf_name(f: sf_at(files: [], k: 0)) == ""
do
  match at(list: files, index: k)
    case Some(value: f) then f
    case None then SrcFile(name: "", text: "")
  end
end

# use の行：パスと位置
type UseLine
  case UseLine(path: Str, line: Int, col: Int)
end

type UseScan
  case UseScan(toks: List[Token], out: List[UseLine], stop: Bool)
end

# ファイルのはじめの use "パス" を集める（src/parse.js の scan と同じ）
fn uses_of(toks: List[Token]) -> List[UseLine]
  ensures true
  example uses_of(toks: lex_ok(text: "use \"a.ak\" use \"b.ak\" fn")) == [UseLine(path: "a.ak", line: 1, col: 1), UseLine(path: "b.ak", line: 1, col: 12)]
  example uses_of(toks: lex_ok(text: "fn use \"a.ak\"")) == []
do
  match fold(list: range(from: 0, to: len(list: toks) / 2), init: UseScan(toks: toks, out: [], stop: false), func: use_step)
    case UseScan(toks: _, out: o, stop: _) then o
  end
end

fn use_step(s: UseScan, i: Int) -> UseScan
  ensures true
  example use_step(s: UseScan(toks: [], out: [], stop: false), i: 0) == UseScan(toks: [], out: [], stop: true)
do
  match s
    case UseScan(toks: ts, out: o, stop: stop) then if stop then s else use_at(ts: ts, o: o, a: at(list: ts, index: 2 * i), b: at(list: ts, index: 2 * i + 1)) end
  end
end

fn use_at(ts: List[Token], o: List[UseLine], a: Option[Token], b: Option[Token]) -> UseScan
  ensures true
  example use_at(ts: [], o: [], a: None, b: None) == UseScan(toks: [], out: [], stop: true)
do
  match a
    case Some(value: x) then
      match b
        case Some(value: y) then if t_kind(t: x) == "kw" and t_text(t: x) == "use" and t_kind(t: y) == "str" then UseScan(toks: ts, out: append(list: o, item: UseLine(path: t_text(t: y), line: t_line(t: x), col: t_col(t: x))), stop: false) else UseScan(toks: ts, out: o, stop: true) end
        case None then UseScan(toks: ts, out: o, stop: true)
      end
    case None then UseScan(toks: ts, out: o, stop: true)
  end
end

# 使う側のファイル from と use のパスから、main のフォルダからの相対パスを作る。だめなら ""（src/modules.js の resolveUse と同じ）
fn resolve_use(from: Str, path: Str) -> Str
  ensures true
  example resolve_use(from: "main.ak", path: "lib/a.ak") == "lib/a.ak"
  example resolve_use(from: "lib/a.ak", path: "./b.ak") == "lib/b.ak"
  example resolve_use(from: "main.ak", path: "../a.ak") == ""
  example resolve_use(from: "main.ak", path: "C:x.ak") == ""
do
  let parts: List[Str] = drop_last(xs: split(text: from, by: "/")) ++ split(text: path, by: "/")
  if not ends_with(text: path, suffix: ".ak") or starts_with(text: path, prefix: "/") or contains(text: path, part: "\\") or contains(text: path, part: char_of(code: 0)) or is_drive(path: path) or any(list: parts, func: bad_part) then "" else join(parts: filter(list: parts, func: not_dot), by: "/") end
end

fn drop_last(xs: List[Str]) -> List[Str]
  ensures true
  example drop_last(xs: ["a", "b"]) == ["a"]
  example drop_last(xs: []) == []
do
  reverse(list: drop(list: reverse(list: xs), count: 1))
end

fn bad_part(p: Str) -> Bool
  ensures true
  example bad_part(p: "..")
do
  p == ".." or p == ""
end

fn not_dot(p: Str) -> Bool
  ensures true
  example not not_dot(p: ".")
do
  p != "."
end

# C: のような、ドライブの文字で始まるか
fn is_drive(path: Str) -> Bool
  ensures true
  example is_drive(path: "c:a.ak")
  example not is_drive(path: "ab.ak")
do
  str_len(text: path) >= 2 and slice(text: path, from: 1, to: 2) == ":" and is_ascii_letter(c: slice(text: path, from: 0, to: 1))
end

# k 番目のファイルから順に、use で読むファイルを足していく（読めないものは E113・E114 で止める）
fn gather(folder: Folder, files: List[SrcFile], k: Int, err: Str) -> Gathered
do
  if err != "" or k >= len(list: files) then Gathered(files: files, err: err) else
    let f: SrcFile = sf_at(files: files, k: k)
    let got: Gathered = add_uses(folder: folder, files: files, from: sf_name(f: f), uses: uses_of(toks: sf_toks(f: f)), i: 0)
    match got
      case Gathered(files: fs, err: e) then gather(folder: folder, files: fs, k: k + 1, err: e)
    end
  end
end

fn add_uses(folder: Folder, files: List[SrcFile], from: Str, uses: List[UseLine], i: Int) -> Gathered
do
  match at(list: uses, index: i)
    case None then Gathered(files: files, err: "")
    case Some(value: u) then
      match u
        case UseLine(path: p, line: l, col: c) then add_one(folder: folder, files: files, from: from, uses: uses, i: i, path: p, place: to_str(value: l) ++ ":" ++ to_str(value: c))
      end
  end
end

fn add_one(folder: Folder, files: List[SrcFile], from: Str, uses: List[UseLine], i: Int, path: Str, place: Str) -> Gathered
do
  let rel: Str = resolve_use(from: if from == "" then "main.ak" else from end, path: path)
  when
    rel == "" then Gathered(files: files, err: in_file(name: from, message: "E113 " ++ place ++ " use path '" ++ path ++ "' is not allowed"))
    has_str(xs: map(list: files, func: sf_name), x: rel) then add_uses(folder: folder, files: files, from: from, uses: uses, i: i + 1)
    else
    match read_text(from: folder, path: rel)
      case Err(message: _) then Gathered(files: files, err: in_file(name: from, message: "E114 " ++ place ++ " used file '" ++ rel ++ "' was not found"))
      case Ok(value: text) then if first_lex_error(name: rel, text: text) != "" then Gathered(files: files, err: first_lex_error(name: rel, text: text)) else add_uses(folder: folder, files: append(list: files, item: SrcFile(name: rel, text: text)), from: from, uses: uses, i: i + 1) end
    end
  end
end

type Parsing
  case Parsing(types: List[Str], items: List[Item], err: Str)
end

fn parse_step(p: Parsing, f: SrcFile) -> Parsing
  ensures true
  example parse_step(p: Parsing(types: [], items: [], err: "x"), f: SrcFile(name: "", text: "")) == Parsing(types: [], items: [], err: "x")
do
  match p
    case Parsing(types: ts, items: its, err: e) then if e != "" then p else
      match parse(text: sf_text(f: f), other_types: ts)
        case Err(message: m) then Parsing(types: ts, items: its, err: in_file(name: sf_name(f: f), message: m))
        case Ok(value: prog) then Parsing(types: ts, items: its ++ items_of(file: sf_name(f: f), program: prog), err: used_main(name: sf_name(f: f), prog: prog))
      end
    end
  end
end

# use で読んだファイルに main があれば E115
fn used_main(name: Str, prog: Node) -> Str
  ensures true
  example used_main(name: "a.ak", prog: bare(kind: "program", text: "", kids: [Node(kind: "fn", text: "main", line: 2, col: 1, kids: [])])) == "a.ak: E115 2:1 the used file 'a.ak' has a main function"
  example used_main(name: "", prog: bare(kind: "program", text: "", kids: [Node(kind: "fn", text: "main", line: 2, col: 1, kids: [])])) == ""
do
  match find(list: n_kids(n: prog), func: is_main_fn)
    case Some(value: m) then if name == "" then "" else in_file(name: name, message: "E115 " ++ to_str(value: n_line(n: m)) ++ ":" ++ to_str(value: n_col(n: m)) ++ " the used file '" ++ name ++ "' has a main function") end
    case None then ""
  end
end

fn is_main_fn(n: Node) -> Bool
  ensures true
  example is_main_fn(n: bare(kind: "fn", text: "main", kids: []))
do
  n_kind(n: n) == "fn" and n_text(n: n) == "main"
end

fn is_ascii_letter(c: Str) -> Bool
  ensures true
  example is_ascii_letter(c: "Z")
  example not is_ascii_letter(c: "é")
do
  str_len(text: c) == 1 and ((code_of(char: c) >= 65 and code_of(char: c) <= 90) or (code_of(char: c) >= 97 and code_of(char: c) <= 122))
end
