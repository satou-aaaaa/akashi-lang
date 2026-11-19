# Akashi のコード生成を Akashi で書いたもの（セルフホストの段階5）。src/wasm.js と1バイトも違わない .wasm を書き出す。
# 命令は、src/wasm.js の op の名前をそのまま並べた文字で書き、asm がバイトにする（例："localGet 0 i32Load 0 call $alloc"）。
# $名前 は記号の表（手伝いの関数の番号・大域変数・文字の置き場所）から引く。
# 文字の定数・手伝いの関数・局所変数を足す順が JS と同じになるように、状態（Cg）を受け取って新しい状態を返す。
use "check.ak"

# ---- バイトの書き方 ----

fn uleb(n: Int) -> List[Int]
  requires n >= 0
  ensures len(list: result) >= 1
  example uleb(n: 624485) == [229, 142, 38]
  example uleb(n: 0) == [0]
do
  if n < 128 then [n] else [n % 128 + 128] ++ uleb(n: n / 128) end
end

# 符号つき（負の数も）。src/wasm.js の sleb と同じ
fn sleb(n: Int) -> List[Int]
  ensures len(list: result) >= 1
  example sleb(n: -1) == [127]
  example sleb(n: 64) == [192, 0]
  example sleb(n: -123456) == [192, 187, 120]
do
  let b: Int = (n % 128 + 128) % 128
  let v: Int = if n >= 0 then n / 128 else 0 - (0 - n - 1) / 128 - 1 end
  if (v == 0 and b < 64) or (v == -1 and b >= 64) then [b] else [b + 128] ++ sleb(n: v) end
end

# 文字を UTF-8 のバイトにする
fn utf8(text: Str) -> List[Int]
  ensures len(list: result) >= str_len(text: text)
  example utf8(text: "aé😀") == [97, 195, 169, 240, 159, 152, 128]
do
  concat(lists: map(list: chars(text: text), func: utf8_char))
end

fn utf8_char(c: Str) -> List[Int]
  ensures true
  example utf8_char(c: "é") == [195, 169]
  example utf8_char(c: "") == []
do
  if str_len(text: c) != 1 then [] else
    let n: Int = code_of(char: c)
    when
      n < 128 then [n]
      n < 2048 then [192 + n / 64, 128 + n % 64]
      n < 65536 then [224 + n / 4096, 128 + n / 64 % 64, 128 + n % 64]
      else [240 + n / 262144, 128 + n / 4096 % 64, 128 + n / 64 % 64, 128 + n % 64]
    end
  end
end

fn wname(text: Str) -> List[Int]
  ensures true
  example wname(text: "ab") == [2, 97, 98]
do
  uleb(n: len(list: utf8(text: text))) ++ utf8(text: text)
end

fn wvec(items: List[List[Int]]) -> List[Int]
  ensures true
  example wvec(items: [[1], [2, 3]]) == [2, 1, 2, 3]
do
  uleb(n: len(list: items)) ++ concat(lists: items)
end

fn wsection(id: Int, body: List[Int]) -> List[Int]
  requires id >= 0
  ensures true
  example wsection(id: 1, body: [7]) == [1, 1, 7]
do
  [id] ++ uleb(n: len(list: body)) ++ body
end

# 4 バイト（小さい方から）
fn u32le(n: Int) -> List[Int]
  ensures len(list: result) == 4
  example u32le(n: 258) == [2, 1, 0, 0]
do
  let m: Int = (n % 4294967296 + 4294967296) % 4294967296
  [m % 256, m / 256 % 256, m / 65536 % 256, m / 16777216 % 256]
end

# ---- 命令を文字で書く（asm） ----

# 命令のバイト（即値の前まで）。知らない名前は []
fn op_code(op: Str) -> List[Int]
  ensures true
  example op_code(op: "i64Add") == [124]
  example op_code(op: "memoryCopy") == [252, 10, 0, 0]
do
  when
    op == "unreachable" then [0]
    op == "block" then [2]
    op == "loop" then [3]
    op == "if" then [4]
    op == "else" then [5]
    op == "end" then [11]
    op == "br" then [12]
    op == "brIf" then [13]
    op == "return" then [15]
    op == "call" then [16]
    op == "drop" then [26]
    op == "select" then [27]
    op == "localGet" then [32]
    op == "localSet" then [33]
    op == "localTee" then [34]
    op == "globalGet" then [35]
    op == "globalSet" then [36]
    op == "i32Load" then [40, 2]
    op == "i64Load" then [41, 3]
    op == "i32Load8u" then [45, 0]
    op == "i32Store" then [54, 2]
    op == "i64Store" then [55, 3]
    op == "i32Store8" then [58, 0]
    op == "memorySize" then [63, 0]
    op == "memoryGrow" then [64, 0]
    op == "i32" then [65]
    op == "i64" then [66]
    else op_code2(op: op)
  end
end

fn op_code2(op: Str) -> List[Int]
  ensures true
  example op_code2(op: "i32Eqz") == [69]
  example op_code2(op: "nope") == []
do
  when
    op == "i32Eqz" then [69]
    op == "i32Eq" then [70]
    op == "i32Ne" then [71]
    op == "i32LtS" then [72]
    op == "i32LtU" then [73]
    op == "i32GtS" then [74]
    op == "i32GtU" then [75]
    op == "i32LeU" then [77]
    op == "i32GeS" then [78]
    op == "i32GeU" then [79]
    op == "i64Eqz" then [80]
    op == "i64Eq" then [81]
    op == "i64Ne" then [82]
    op == "i64LtS" then [83]
    op == "i64GtS" then [85]
    op == "i64LeS" then [87]
    op == "i64GeS" then [89]
    op == "i32Add" then [106]
    op == "i32Sub" then [107]
    op == "i32Mul" then [108]
    op == "i32And" then [113]
    op == "i32Or" then [114]
    op == "i32Xor" then [115]
    op == "i32Shl" then [116]
    op == "i32ShrU" then [118]
    op == "i64Add" then [124]
    op == "i64Sub" then [125]
    op == "i64Mul" then [126]
    op == "i64DivS" then [127]
    op == "i64DivU" then [128]
    op == "i64RemS" then [129]
    op == "i64RemU" then [130]
    op == "i32WrapI64" then [167]
    op == "i64ExtendI32U" then [173]
    op == "memoryCopy" then [252, 10, 0, 0]
    else []
  end
end

# 即値の種類：u（uleb）・s（sleb）・t（ブロックの型）・""（無し）
fn op_imm(op: Str) -> Str
  ensures true
  example op_imm(op: "i64") == "s"
  example op_imm(op: "i64Add") == ""
do
  when
    op == "i32" or op == "i64" then "s"
    op == "block" or op == "loop" or op == "if" then "t"
    in_table(table: " br brIf call localGet localSet localTee globalGet globalSet i32Load i64Load i32Load8u i32Store i64Store i32Store8 ", word: op) then "u"
    else ""
  end
end

# asm の途中：記号の表・出したバイト・即値を待っている命令・まちがい
type Asm
  case Asm(syms: Dict[Int], out: List[List[Int]], want: Str, bad: Str)
end

# 命令の文字をバイトにする。まちがいがあれば bad に書く（テストで見つける）
fn asm_run(text: Str, syms: Dict[Int]) -> Asm
  ensures true
  example asm_run(text: "localGet 0 i64 -1 if I64 call $f end", syms: dict(keys: ["f"], values: [7])) == Asm(syms: dict(keys: ["f"], values: [7]), out: [[32], [0], [66], [127], [4], [126], [16], [7], [11]], want: "", bad: "")
do
  fold(list: filter(list: split(text: text, by: " "), func: not_blank), init: Asm(syms: syms, out: [], want: "", bad: ""), func: asm_step)
end

fn not_blank(s: Str) -> Bool
  ensures true
  example not not_blank(s: "")
do
  s != ""
end

fn asm(text: Str, syms: Dict[Int]) -> List[Int]
  ensures true
  example asm(text: "i32 8 call $alloc", syms: dict(keys: ["alloc"], values: [12])) == [65, 8, 16, 12]
do
  match asm_run(text: text, syms: syms)
    case Asm(syms: _, out: o, want: _, bad: _) then concat(lists: o)
  end
end

fn asm_step(a: Asm, word: Str) -> Asm
  ensures true
  example asm_step(a: Asm(syms: dict(keys: [], values: []), out: [], want: "", bad: ""), word: "end") == Asm(syms: dict(keys: [], values: []), out: [[11]], want: "", bad: "")
do
  match a
    case Asm(syms: syms, out: o, want: w, bad: b) then if w == "" then asm_op(syms: syms, o: o, b: b, word: word) else Asm(syms: syms, out: append(list: o, item: imm_bytes(kind: op_imm(op: w), value: imm_value(syms: syms, word: word))), want: "", bad: if imm_known(syms: syms, word: word) then b else b ++ " " ++ word end) end
  end
end

fn asm_op(syms: Dict[Int], o: List[List[Int]], b: Str, word: Str) -> Asm
  ensures true
  example asm_op(syms: dict(keys: [], values: []), o: [], b: "", word: "x") == Asm(syms: dict(keys: [], values: []), out: [], want: "", bad: " x")
do
  let code: List[Int] = op_code(op: word)
  if code == [] then Asm(syms: syms, out: o, want: "", bad: b ++ " " ++ word) else Asm(syms: syms, out: append(list: o, item: code), want: if op_imm(op: word) == "" then "" else word end, bad: b) end
end

fn imm_known(syms: Dict[Int], word: Str) -> Bool
  ensures true
  example imm_known(syms: dict(keys: [], values: []), word: "-3")
  example not imm_known(syms: dict(keys: [], values: []), word: "$x")
do
  when
    starts_with(text: word, prefix: "$") then dict_has(dict: syms, key: slice(text: word, from: 1, to: str_len(text: word)))
    word == "EMPTY" or word == "I32" or word == "I64" then true
    else parse_int(text: word) != None
  end
end

fn imm_value(syms: Dict[Int], word: Str) -> Int
  ensures true
  example imm_value(syms: dict(keys: [], values: []), word: "I64") == 126
  example imm_value(syms: dict(keys: ["a"], values: [5]), word: "$a") == 5
do
  when
    word == "EMPTY" then 64
    word == "I32" then 127
    word == "I64" then 126
    starts_with(text: word, prefix: "$") then
    match dict_get(dict: syms, key: slice(text: word, from: 1, to: str_len(text: word)))
      case Some(value: v) then v
      case None then 0
    end
    else
    match parse_int(text: word)
      case Some(value: v) then v
      case None then 0
    end
  end
end

fn imm_bytes(kind: Str, value: Int) -> List[Int]
  ensures true
  example imm_bytes(kind: "s", value: -1) == [127]
  example imm_bytes(kind: "t", value: 64) == [64]
do
  when
    kind == "s" then sleb(n: value)
    kind == "t" then [value]
    else uleb(n: if value < 0 then 0 else value end)
  end
end

# 数を文字にして asm に入れる
fn n2s(n: Int) -> Str
  ensures true
  example n2s(n: -4) == "-4"
do
  to_str(value: n)
end

# ---- 値の型（src/wasm.js の valType） ----
# 126 は i64、127 は i32、0 は値なし（Unit・まだ決まらない型）、-1 はまだ扱えない型

fn val_ty(t: Ty) -> Int
  ensures result >= -1
  example val_ty(t: tk(k: "Int")) == 126
  example val_ty(t: t_list(of: tk(k: "Int"))) == 127
  example val_ty(t: tk(k: "Unit")) == 0
do
  let k: Str = ty_k(t: t)
  when
    k == "Int" then 126
    in_table(table: " Bool Str List Dict Data Html Sql ", word: k) then 127
    k == "Unit" or k == "Var" or k == "Err" then 0
    else -1
  end
end

# 書いた型（木 t）の valType
fn val_ast(n: Node) -> Int
  ensures result >= -1
  example val_ast(n: bare(kind: "t", text: "Bool", kids: [])) == 127
do
  val_ty(t: from_ast(n: n, subst: no_subst()))
end

fn is_cap_node(n: Node) -> Bool
  ensures true
  example is_cap_node(n: bare(kind: "t", text: "Console", kids: []))
do
  in_table(table: " Console Folder OutFolder ", word: n_text(n: n))
end

# ---- コンパイルの状態 ----

# 手伝いの関数（型ごとに作るもの）と、利用者の関数の形
type Func
  case Func(params: List[Int], results: List[Int], locals: List[Int], body: List[Int])
end

# data：文字の定数を並べたバイト（DATA_START = 48 から）・strings：文字 → 置き場所・tags：欄の無い case の置き場所
# gens：作った手伝いの関数・gen_idx：鍵 → 番号・locals：いま作っている関数の局所変数・nparams：その引数の数・err：扱えないもの（E600）
type Cg
  case Cg(data: List[Int], strings: Dict[Int], data_end: Int, tags: Dict[Int], gens: List[Func], gen_idx: Dict[Int], locals: List[Int], nparams: Int, err: Str)
end

fn cg_new() -> Cg
  ensures true
  example cg_data_end(cg: cg_new()) == 48
do
  Cg(data: [], strings: no_ints(), data_end: 48, tags: no_ints(), gens: [], gen_idx: no_ints(), locals: [], nparams: 0, err: "")
end

fn no_ints() -> Dict[Int]
  ensures dict_size(dict: result) == 0
  example dict_size(dict: no_ints()) == 0
do
  dict(keys: [], values: [])
end

fn cg_data_end(cg: Cg) -> Int
  ensures true
  example cg_data_end(cg: cg_new()) == 48
do
  match cg
    case Cg(data: _, strings: _, data_end: d, tags: _, gens: _, gen_idx: _, locals: _, nparams: _, err: _) then d
  end
end

fn cg_data(cg: Cg) -> List[Int]
  ensures true
  example cg_data(cg: cg_new()) == []
do
  match cg
    case Cg(data: d, strings: _, data_end: _, tags: _, gens: _, gen_idx: _, locals: _, nparams: _, err: _) then d
  end
end

fn cg_err(cg: Cg) -> Str
  ensures true
  example cg_err(cg: cg_new()) == ""
do
  match cg
    case Cg(data: _, strings: _, data_end: _, tags: _, gens: _, gen_idx: _, locals: _, nparams: _, err: e) then e
  end
end

fn cg_gens(cg: Cg) -> List[Func]
  ensures true
  example cg_gens(cg: cg_new()) == []
do
  match cg
    case Cg(data: _, strings: _, data_end: _, tags: _, gens: g, gen_idx: _, locals: _, nparams: _, err: _) then g
  end
end

fn cg_locals(cg: Cg) -> List[Int]
  ensures true
  example cg_locals(cg: cg_new()) == []
do
  match cg
    case Cg(data: _, strings: _, data_end: _, tags: _, gens: _, gen_idx: _, locals: l, nparams: _, err: _) then l
  end
end

fn cg_nparams(cg: Cg) -> Int
  ensures true
  example cg_nparams(cg: cg_new()) == 0
do
  match cg
    case Cg(data: _, strings: _, data_end: _, tags: _, gens: _, gen_idx: _, locals: _, nparams: n, err: _) then n
  end
end

# 新しい関数を作りはじめる（局所変数を空にする）
fn cg_frame(cg: Cg, nparams: Int, locals: List[Int]) -> Cg
  ensures cg_nparams(cg: result) == nparams
  example cg_locals(cg: cg_frame(cg: cg_new(), nparams: 2, locals: [127])) == [127]
do
  match cg
    case Cg(data: d, strings: s, data_end: de, tags: t, gens: g, gen_idx: gi, locals: _, nparams: _, err: e) then Cg(data: d, strings: s, data_end: de, tags: t, gens: g, gen_idx: gi, locals: locals, nparams: nparams, err: e)
  end
end

# 扱えないものを覚える（最初の1つだけ。src/wasm.js の E600 と同じ文）
fn unsupported(cg: Cg, what: Str, n: Node) -> Cg
  ensures true
  example cg_err(cg: unsupported(cg: cg_new(), what: "x", n: Node(kind: "var", text: "", line: 2, col: 3, kids: []))) == "E600 2:3 the compiler does not support x yet"
do
  match cg
    case Cg(data: d, strings: s, data_end: de, tags: t, gens: g, gen_idx: gi, locals: l, nparams: np, err: e) then Cg(data: d, strings: s, data_end: de, tags: t, gens: g, gen_idx: gi, locals: l, nparams: np, err: if e != "" then e else "E600 " ++ to_str(value: n_line(n: n)) ++ ":" ++ to_str(value: n_col(n: n)) ++ " the compiler does not support " ++ what ++ " yet" end)
  end
end

# 置き場所と状態
type At
  case At(at: Int, cg: Cg)
end

fn at_at(a: At) -> Int
  ensures true
  example at_at(a: At(at: 3, cg: cg_new())) == 3
do
  match a
    case At(at: x, cg: _) then x
  end
end

fn at_cg(a: At) -> Cg
  ensures true
  example at_cg(a: At(at: 3, cg: cg_new())) == cg_new()
do
  match a
    case At(at: _, cg: c) then c
  end
end

# 文字の定数を置き、その場所を返す（同じ文字は1つにまとめる。4 の倍数にそろえる）
fn cg_str(cg: Cg, text: Str) -> At
  ensures true
  example at_at(a: cg_str(cg: cg_new(), text: "ab")) == 48
  example cg_data_end(cg: at_cg(a: cg_str(cg: cg_new(), text: "ab"))) == 56
do
  match cg
    case Cg(data: d, strings: s, data_end: de, tags: t, gens: g, gen_idx: gi, locals: l, nparams: np, err: e) then
      match dict_get(dict: s, key: text)
        case Some(value: a) then At(at: a, cg: cg)
        case None then put_str(cg: cg, bytes: utf8(text: text), text: text)
      end
  end
end

fn put_str(cg: Cg, bytes: List[Int], text: Str) -> At
  ensures true
  example at_at(a: put_str(cg: cg_new(), bytes: [97], text: "a")) == 48
do
  match cg
    case Cg(data: d, strings: s, data_end: de, tags: t, gens: g, gen_idx: gi, locals: l, nparams: np, err: e) then At(at: de, cg: Cg(data: concat(lists: [d, u32le(n: len(list: bytes)), bytes, zeros(n: pad4(n: 4 + len(list: bytes)))]), strings: dict_put(dict: s, key: text, value: de), data_end: de + 4 + len(list: bytes) + pad4(n: 4 + len(list: bytes)), tags: t, gens: g, gen_idx: gi, locals: l, nparams: np, err: e))
  end
end

# n を 4 の倍数にするのに足す数
fn pad4(n: Int) -> Int
  ensures result >= 0 and result < 4
  example pad4(n: 5) == 3
do
  (4 - (n % 4 + 4) % 4) % 4
end

fn zeros(n: Int) -> List[Int]
  ensures true
  example zeros(n: 2) == [0, 0]
do
  map(list: range(from: 0, to: n), func: zero_of)
end

fn zero_of(i: Int) -> Int
  ensures result == 0
  example zero_of(i: 5) == 0
do
  0 * i
end

# 局所変数を1つ足し、その番号を返す
fn cg_local(cg: Cg, t: Int) -> At
  ensures true
  example cg_local(cg: cg_frame(cg: cg_new(), nparams: 1, locals: []), t: 126) == At(at: 1, cg: cg_frame(cg: cg_new(), nparams: 1, locals: [126]))
do
  match cg
    case Cg(data: d, strings: s, data_end: de, tags: tg, gens: g, gen_idx: gi, locals: l, nparams: np, err: e) then At(at: np + len(list: l), cg: Cg(data: d, strings: s, data_end: de, tags: tg, gens: g, gen_idx: gi, locals: append(list: l, item: t), nparams: np, err: e))
  end
end

# 欄の無い case は、データの節に1つだけ置いて使い回す（8 の倍数にそろえる）
fn cg_tag(cg: Cg, index: Int) -> At
  ensures true
  example at_at(a: cg_tag(cg: cg_new(), index: 1)) == 48
do
  match cg
    case Cg(data: d, strings: s, data_end: de, tags: tg, gens: g, gen_idx: gi, locals: l, nparams: np, err: e) then
      match dict_get(dict: tg, key: to_str(value: index))
        case Some(value: a) then At(at: a, cg: cg)
        case None then At(at: de + pad8(n: de), cg: Cg(data: concat(lists: [d, zeros(n: pad8(n: de)), [index % 256, index / 256 % 256, 0, 0, 0, 0, 0, 0]]), strings: s, data_end: de + pad8(n: de) + 8, tags: dict_put(dict: tg, key: to_str(value: index), value: de + pad8(n: de)), gens: g, gen_idx: gi, locals: l, nparams: np, err: e))
      end
  end
end

fn pad8(n: Int) -> Int
  ensures result >= 0 and result < 8
  example pad8(n: 52) == 4
do
  (8 - (n % 8 + 8) % 8) % 8
end

# ---- コードと状態 ----

type BC
  case BC(code: List[Int], cg: Cg)
end

fn bc_code(b: BC) -> List[Int]
  ensures true
  example bc_code(b: BC(code: [1], cg: cg_new())) == [1]
do
  match b
    case BC(code: c, cg: _) then c
  end
end

fn bc_cg(b: BC) -> Cg
  ensures true
  example bc_cg(b: BC(code: [1], cg: cg_new())) == cg_new()
do
  match b
    case BC(code: _, cg: c) then c
  end
end

# コードの後ろに足す
fn bc_then(b: BC, more: List[Int]) -> BC
  ensures true
  example bc_code(b: bc_then(b: BC(code: [1], cg: cg_new()), more: [2])) == [1, 2]
do
  match b
    case BC(code: c, cg: g) then BC(code: c ++ more, cg: g)
  end
end

# コードの前に足す
fn bc_after(before: List[Int], b: BC) -> BC
  ensures true
  example bc_code(b: bc_after(before: [0], b: BC(code: [1], cg: cg_new()))) == [0, 1]
do
  match b
    case BC(code: c, cg: g) then BC(code: before ++ c, cg: g)
  end
end

# ---- プログラムの表 ----

# case：どの型の何番めか・case の木
type CVar
  case CVar(decl: Str, index: Int, node: Node)
end

# fns：利用者の関数（書いた順）・fn_nodes：名前 → 木・variants：case の名前 → CVar・decls：型の名前 → 型の木（組み込みの Option・Result も）
# syms：asm の記号（手伝いの関数・取り込み・大域変数の番号）・gen_base：型ごとの手伝いの関数の始まりの番号・types：いま作っている関数の式の型
type Prog
  case Prog(fns: List[Node], fn_nodes: Dict[Node], variants: Dict[CVar], decls: Dict[Node], syms: Dict[Int], gen_base: Int, types: Dict[Ty], all_types: List[FnTypes])
end

fn pg_syms(p: Prog) -> Dict[Int]
  ensures true
  example dict_size(dict: pg_syms(p: prog_empty())) == 0
do
  match p
    case Prog(fns: _, fn_nodes: _, variants: _, decls: _, syms: s, gen_base: _, types: _, all_types: _) then s
  end
end

fn pg_fn_nodes(p: Prog) -> Dict[Node]
  ensures true
  example dict_size(dict: pg_fn_nodes(p: prog_empty())) == 0
do
  match p
    case Prog(fns: _, fn_nodes: f, variants: _, decls: _, syms: _, gen_base: _, types: _, all_types: _) then f
  end
end

fn pg_variants(p: Prog) -> Dict[CVar]
  ensures true
  example dict_size(dict: pg_variants(p: prog_empty())) == 0
do
  match p
    case Prog(fns: _, fn_nodes: _, variants: v, decls: _, syms: _, gen_base: _, types: _, all_types: _) then v
  end
end

fn pg_types(p: Prog) -> Dict[Ty]
  ensures true
  example dict_size(dict: pg_types(p: prog_empty())) == 0
do
  match p
    case Prog(fns: _, fn_nodes: _, variants: _, decls: _, syms: _, gen_base: _, types: t, all_types: _) then t
  end
end

fn prog_empty() -> Prog
  ensures true
  example pg_types(p: prog_empty()) == dict(keys: [], values: [])
do
  Prog(fns: [], fn_nodes: dict(keys: [], values: []), variants: dict(keys: [], values: []), decls: dict(keys: [], values: []), syms: no_ints(), gen_base: 0, types: dict(keys: [], values: []), all_types: [])
end

# 関数 name を作るあいだの表（その関数の式の型を入れる）
fn prog_in(p: Prog, name: Str) -> Prog
  ensures true
  example pg_types(p: prog_in(p: prog_empty(), name: "f")) == dict(keys: [], values: [])
do
  match p
    case Prog(fns: f, fn_nodes: fnn, variants: v, decls: d, syms: s, gen_base: g, types: _, all_types: alls) then Prog(fns: f, fn_nodes: fnn, variants: v, decls: d, syms: s, gen_base: g, types: types_of(every: alls, name: name), all_types: alls)
  end
end

fn types_of(every: List[FnTypes], name: Str) -> Dict[Ty]
  ensures true
  example types_of(every: [FnTypes(name: "f", types: dict(keys: ["a"], values: [Ty(k: "Int", name: "", args: [])]))], name: "f") == dict(keys: ["a"], values: [Ty(k: "Int", name: "", args: [])])
  example types_of(every: [], name: "f") == dict(keys: [], values: [])
do
  match fold(list: every, init: TyPick(name: name, out: dict(keys: [], values: []), found: false), func: pick_types)
    case TyPick(name: _, out: o, found: _) then o
  end
end

type TyPick
  case TyPick(name: Str, out: Dict[Ty], found: Bool)
end

# 同じ名前の関数は、最初のもの（検査が調べたもの）
fn pick_types(acc: TyPick, f: FnTypes) -> TyPick
  ensures true
  example pick_types(acc: TyPick(name: "f", out: dict(keys: [], values: []), found: true), f: FnTypes(name: "f", types: dict(keys: ["a"], values: [Ty(k: "Int", name: "", args: [])]))) == TyPick(name: "f", out: dict(keys: [], values: []), found: true)
do
  match acc
    case TyPick(name: n, out: o, found: fd) then
      match f
        case FnTypes(name: fname, types: ts) then if not fd and fname == n then TyPick(name: n, out: ts, found: true) else acc end
      end
  end
end

# 式の型（検査が覚えたもの。無ければまだ決まらない型）
fn ty_of(p: Prog, e: Node) -> Ty
  ensures true
  example ty_of(p: prog_empty(), e: bare(kind: "int", text: "1", kids: [])) == Ty(k: "Var", name: "", args: [])
do
  match dict_get(dict: pg_types(p: p), key: node_key(n: e))
    case Some(value: t) then t
    case None then Ty(k: "Var", name: "", args: [])
  end
end

# 記号の表を引く（無ければ 0）
fn sym(p: Prog, name: Str) -> Int
  ensures true
  example sym(p: prog_empty(), name: "alloc") == 0
do
  match dict_get(dict: pg_syms(p: p), key: name)
    case Some(value: v) then v
    case None then 0
  end
end

# asm に、表の記号と、足した記号を渡す
fn pasm(p: Prog, text: Str) -> List[Int]
  ensures true
  example pasm(p: prog_empty(), text: "i32 1") == [65, 1]
do
  asm(text: text, syms: pg_syms(p: p))
end

# 「行:列: 番号 説明」の文を置き、fail を呼ぶ（src/wasm.js の failAt）
fn emit_fail(p: Prog, cg: Cg, code: Str, message: Str, n: Node) -> BC
  ensures true
  example bc_code(b: emit_fail(p: prog_empty(), cg: cg_new(), code: "R503", message: "m", n: bare(kind: "x", text: "", kids: []))) == [65, 48, 16, 0]
do
  let s: At = cg_str(cg: cg, text: to_str(value: n_line(n: n)) ++ ":" ++ to_str(value: n_col(n: n)) ++ ": " ++ code ++ " " ++ message)
  BC(code: pasm(p: p, text: "i32 " ++ n2s(n: at_at(a: s)) ++ " call $fail"), cg: at_cg(a: s))
end

# ---- 手伝いの関数（実行時の部品。src/wasm.js の helpers と同じ順・同じ中身） ----

fn helper_names() -> List[Str]
  ensures len(list: result) == 11
  example get(list: helper_names(), index: 0) == "alloc"
do
  ["alloc", "write", "fail", "chk", "mul", "concat", "itoa", "streq", "strlen", "enter", "leave"]
end

# |x| を局所変数 to に入れる
fn abs_asm(from: Int, to: Int) -> Str
  ensures true
  example abs_asm(from: 0, to: 2) == " localGet 0 i64 0 i64LtS if I64 i64 0 localGet 0 i64Sub else localGet 0 end localSet 2 "
do
  let f: Str = n2s(n: from)
  " localGet " ++ f ++ " i64 0 i64LtS if I64 i64 0 localGet " ++ f ++ " i64Sub else localGet " ++ f ++ " end localSet " ++ n2s(n: to) ++ " "
end

type Funcs
  case Funcs(funcs: List[Func], cg: Cg)
end

fn helpers(p: Prog, cg: Cg) -> Funcs
  ensures true
  example len(list: funcs_of(f: helpers(p: prog_empty(), cg: cg_new()))) == 11
do
  let nl: At = cg_str(cg: cg, text: "\n")
  let r504: At = cg_str(cg: at_cg(a: nl), text: "R504 integer overflow")
  let r505: At = cg_str(cg: at_cg(a: r504), text: "R505 recursion deeper than 500 calls")
  let r513: At = cg_str(cg: at_cg(a: r505), text: "R513 out of memory")
  let s: Dict[Int] = dict_put(dict: dict_put(dict: dict_put(dict: dict_put(dict: pg_syms(p: p), key: "nl4", value: at_at(a: nl) + 4), key: "r504", value: at_at(a: r504)), key: "r505", value: at_at(a: r505)), key: "r513", value: at_at(a: r513))
  let big: Str = "9007199254740991"
  Funcs(funcs: [
  Func(params: [127], results: [127], locals: [127], body: asm(text: "localGet 0 i32 1073741824 i32GtU if EMPTY i32 $r513 call $fail end globalGet $heap localSet 1 globalGet $heap localGet 0 i32Add i32 3 i32Add i32 -4 i32And globalSet $heap globalGet $heap localGet 1 i32LtU if EMPTY i32 $r513 call $fail end block EMPTY loop EMPTY globalGet $heap memorySize i32 16 i32Shl i32LtU brIf 1 i32 1 memoryGrow i32 -1 i32Eq if EMPTY i32 $r513 call $fail end br 0 end end localGet 1 end", syms: s)),
  Func(params: [127, 127, 127], results: [], locals: [], body: asm(text: "i32 0 localGet 1 i32 4 i32Add i32Store 0 i32 0 localGet 1 i32Load 0 i32Store 4 i32 0 i32 $nl4 i32Store 8 i32 0 i32 1 i32Store 12 localGet 0 i32 0 i32 1 localGet 2 i32Add i32 32 call $fdWrite drop end", syms: s)),
  Func(params: [127], results: [], locals: [], body: asm(text: "i32 2 localGet 0 i32 1 call $write i32 1 call $procExit unreachable end", syms: s)),
  Func(params: [126], results: [126], locals: [], body: asm(text: "localGet 0 i64 " ++ big ++ " i64GtS localGet 0 i64 -" ++ big ++ " i64LtS i32Or if EMPTY i32 $r504 call $fail end localGet 0 end", syms: s)),
  Func(params: [126, 126], results: [126], locals: [126, 126], body: asm(text: "localGet 0 i64Eqz localGet 1 i64Eqz i32Or if EMPTY i64 0 return end" ++ abs_asm(from: 0, to: 2) ++ abs_asm(from: 1, to: 3) ++ "localGet 3 i64 " ++ big ++ " localGet 2 i64DivU i64GtS if EMPTY i32 $r504 call $fail end localGet 0 localGet 1 i64Mul end", syms: s)),
  Func(params: [127, 127], results: [127], locals: [127, 127, 127], body: asm(text: "localGet 0 i32Load 0 localSet 2 localGet 1 i32Load 0 localSet 3 localGet 2 localGet 3 i32Add i32 4 i32Add call $alloc localSet 4 localGet 4 localGet 2 localGet 3 i32Add i32Store 0 localGet 4 i32 4 i32Add localGet 0 i32 4 i32Add localGet 2 memoryCopy localGet 4 i32 4 i32Add localGet 2 i32Add localGet 1 i32 4 i32Add localGet 3 memoryCopy localGet 4 end", syms: s)),
  Func(params: [126], results: [127], locals: [126, 127, 127, 127], body: asm(text: "localGet 0 i64 0 i64LtS localSet 3" ++ abs_asm(from: 0, to: 1) ++ "i32 48 localSet 2 loop EMPTY localGet 2 i32 1 i32Sub localTee 2 localGet 1 i64 10 i64RemU i32WrapI64 i32 48 i32Add i32Store8 0 localGet 1 i64 10 i64DivU localTee 1 i64Eqz i32Eqz brIf 0 end localGet 3 if EMPTY localGet 2 i32 1 i32Sub localTee 2 i32 45 i32Store8 0 end i32 48 localGet 2 i32Sub i32 4 i32Add call $alloc localSet 4 localGet 4 i32 48 localGet 2 i32Sub i32Store 0 localGet 4 i32 4 i32Add localGet 2 i32 48 localGet 2 i32Sub memoryCopy localGet 4 end", syms: s)),
  Func(params: [127, 127], results: [127], locals: [127, 127], body: asm(text: "localGet 0 i32Load 0 localTee 2 localGet 1 i32Load 0 i32Ne if EMPTY i32 0 return end i32 0 localSet 3 block EMPTY loop EMPTY localGet 3 localGet 2 i32GeU brIf 1 localGet 0 localGet 3 i32Add i32Load8u 4 localGet 1 localGet 3 i32Add i32Load8u 4 i32Ne if EMPTY i32 0 return end localGet 3 i32 1 i32Add localSet 3 br 0 end end i32 1 end", syms: s)),
  Func(params: [127], results: [126], locals: [127, 127, 126], body: asm(text: "localGet 0 i32Load 0 localSet 1 block EMPTY loop EMPTY localGet 2 localGet 1 i32GeU brIf 1 localGet 0 localGet 2 i32Add i32Load8u 4 i32 192 i32And i32 128 i32Ne i64ExtendI32U localGet 3 i64Add localSet 3 localGet 2 i32 1 i32Add localSet 2 br 0 end end localGet 3 end", syms: s)),
  Func(params: [], results: [], locals: [], body: asm(text: "globalGet $depth i32 1 i32Add globalSet $depth globalGet $depth i32 500 i32GtU if EMPTY i32 $r505 call $fail end end", syms: s)),
  Func(params: [], results: [], locals: [], body: asm(text: "globalGet $depth i32 1 i32Sub globalSet $depth end", syms: s))
  ], cg: at_cg(a: r513))
end

fn funcs_of(f: Funcs) -> List[Func]
  ensures true
  example funcs_of(f: Funcs(funcs: [], cg: cg_new())) == []
do
  match f
    case Funcs(funcs: fs, cg: _) then fs
  end
end

fn funcs_cg(f: Funcs) -> Cg
  ensures true
  example funcs_cg(f: Funcs(funcs: [], cg: cg_new())) == cg_new()
do
  match f
    case Funcs(funcs: _, cg: c) then c
  end
end

# ---- 利用者の関数 ----

# 引数を並べる途中：引数の型・名前 → 局所変数の番号（-1 は値の無いもの）
type PS
  case PS(params: List[Int], scope: Dict[Int], cg: Cg)
end

fn param_slot(s: PS, prm: Node) -> PS
  ensures true
  example param_slot(s: PS(params: [], scope: no_ints(), cg: cg_new()), prm: bare(kind: "param", text: "x", kids: [bare(kind: "t", text: "Int", kids: [])])) == PS(params: [126], scope: dict(keys: ["x"], values: [0]), cg: cg_new())
do
  match s
    case PS(params: ps, scope: sc, cg: cg) then
      if is_cap_node(n: first_kid(n: prm)) then s else
        let t: Int = val_ast(n: first_kid(n: prm))
        when
          t == -1 then PS(params: ps, scope: sc, cg: unsupported(cg: cg, what: "parameters of type " ++ type_str(t: from_ast(n: first_kid(n: prm), subst: no_subst())), n: prm))
          t == 0 then PS(params: ps, scope: dict_put(dict: sc, key: n_text(n: prm), value: -1), cg: cg)
          else PS(params: append(list: ps, item: t), scope: dict_put(dict: sc, key: n_text(n: prm), value: len(list: ps)), cg: cg)
        end
      end
  end
end

type FC
  case FC(func: Func, cg: Cg)
end

fn fc_func(r: FC) -> Func
  ensures true
  example fc_func(r: FC(func: Func(params: [], results: [], locals: [], body: []), cg: cg_new())) == Func(params: [], results: [], locals: [], body: [])
do
  match r
    case FC(func: f, cg: _) then f
  end
end

fn fc_cg(r: FC) -> Cg
  ensures true
  example fc_cg(r: FC(func: Func(params: [], results: [], locals: [], body: []), cg: cg_new())) == cg_new()
do
  match r
    case FC(func: _, cg: c) then c
  end
end

fn gen_fn(p0: Prog, cg: Cg, f: Node) -> FC
  ensures true
  example func_body(f: fc_func(r: gen_fn(p0: prog_empty(), cg: cg_new(), f: get(list: fns_of(text: "fn f() -> Int do 1 end"), index: 0)))) == [16, 0, 66, 1, 16, 0, 11]
do
  let p: Prog = prog_in(p: p0, name: n_text(n: f))
  match fold(list: n_kids(n: kid_at(n: f, i: 0)), init: PS(params: [], scope: no_ints(), cg: cg), func: param_slot)
    case PS(params: ps, scope: sc, cg: cg1) then
      gen_fn_body(p: p, cg: cg_frame(cg: if val_ast(n: kid_at(n: f, i: 1)) == -1 then unsupported(cg: cg1, what: "functions that return " ++ type_str(t: from_ast(n: kid_at(n: f, i: 1), subst: no_subst())), n: f) else cg1 end, nparams: len(list: ps), locals: []), f: f, params: ps, scope: sc)
  end
end

fn func_body(f: Func) -> List[Int]
  ensures true
  example func_body(f: Func(params: [], results: [], locals: [], body: [11])) == [11]
do
  match f
    case Func(params: _, results: _, locals: _, body: b) then b
  end
end

fn gen_fn_body(p: Prog, cg: Cg, f: Node, params: List[Int], scope: Dict[Int]) -> FC
  ensures true
  example func_body(f: fc_func(r: gen_fn_body(p: prog_empty(), cg: cg_new(), f: get(list: fns_of(text: "fn f() -> Unit do () end"), index: 0), params: [], scope: no_ints()))) == [16, 0, 16, 0, 11]
do
  let ret: Int = val_ast(n: kid_at(n: f, i: 1))
  let req: BC = gs_bc(g: fold(list: n_kids(n: kid_at(n: f, i: 2)), init: GS(p: p, scope: scope, f: f, b: BC(code: pasm(p: p, text: "call $enter"), cg: cg)), func: req_step))
  let body: BC = bc_after(before: bc_code(b: req), b: cg_block(p: p, cg: bc_cg(b: req), scope: scope, b: kid_at(n: f, i: 5)))
  let ens: BC = gen_ensures(p: p, b: body, scope: scope, f: f, ret: ret)
  let done: BC = bc_then(b: ens, more: pasm(p: p, text: "call $leave end"))
  FC(func: Func(params: params, results: if ret <= 0 then [] else [ret] end, locals: cg_locals(cg: bc_cg(b: done)), body: bc_code(b: done)), cg: bc_cg(b: done))
end

# 約束を順に足す途中
type GS
  case GS(p: Prog, scope: Dict[Int], f: Node, b: BC)
end

fn gs_bc(g: GS) -> BC
  ensures true
  example bc_code(b: gs_bc(g: GS(p: prog_empty(), scope: no_ints(), f: bare(kind: "fn", text: "f", kids: []), b: BC(code: [1], cg: cg_new())))) == [1]
do
  match g
    case GS(p: _, scope: _, f: _, b: b) then b
  end
end

# requires：偽なら R500（場所は約束の式）
fn req_step(g: GS, c: Node) -> GS
  ensures true
  example bc_code(b: gs_bc(g: req_step(g: GS(p: prog_empty(), scope: no_ints(), f: bare(kind: "fn", text: "f", kids: []), b: BC(code: [], cg: cg_new())), c: bare(kind: "clause", text: "true", kids: [bare(kind: "bool", text: "true", kids: [])])))) == [65, 1, 69, 4, 64, 65, 48, 16, 0, 11]
do
  match g
    case GS(p: p, scope: sc, f: f, b: b) then GS(p: p, scope: sc, f: f, b: check_clause(p: p, b: b, scope: sc, e: first_kid(n: c), code: "R500", message: "requires of '" ++ n_text(n: f) ++ "' failed: " ++ n_text(n: c), where: first_kid(n: c)))
  end
end

# ensures：偽なら R501（場所は関数）
fn ens_step(g: GS, c: Node) -> GS
  ensures true
  example bc_code(b: gs_bc(g: ens_step(g: GS(p: prog_empty(), scope: no_ints(), f: bare(kind: "fn", text: "f", kids: []), b: BC(code: [], cg: cg_new())), c: bare(kind: "clause", text: "true", kids: [bare(kind: "bool", text: "true", kids: [])])))) == [65, 1, 69, 4, 64, 65, 48, 16, 0, 11]
do
  match g
    case GS(p: p, scope: sc, f: f, b: b) then GS(p: p, scope: sc, f: f, b: check_clause(p: p, b: b, scope: sc, e: first_kid(n: c), code: "R501", message: "ensures of '" ++ n_text(n: f) ++ "' failed: " ++ n_text(n: c), where: f))
  end
end

fn check_clause(p: Prog, b: BC, scope: Dict[Int], e: Node, code: Str, message: Str, where: Node) -> BC
  ensures true
  example bc_code(b: check_clause(p: prog_empty(), b: BC(code: [], cg: cg_new()), scope: no_ints(), e: bare(kind: "bool", text: "false", kids: []), code: "R500", message: "m", where: bare(kind: "x", text: "", kids: []))) == [65, 0, 69, 4, 64, 65, 48, 16, 0, 11]
do
  let v: BC = cg_expr(p: p, cg: bc_cg(b: b), scope: scope, e: e)
  let fl: BC = emit_fail(p: p, cg: bc_cg(b: v), code: code, message: message, n: where)
  BC(code: concat(lists: [bc_code(b: b), bc_code(b: v), pasm(p: p, text: "i32Eqz if EMPTY"), bc_code(b: fl), pasm(p: p, text: "end")]), cg: bc_cg(b: fl))
end

fn gen_ensures(p: Prog, b: BC, scope: Dict[Int], f: Node, ret: Int) -> BC
  ensures true
  example bc_code(b: gen_ensures(p: prog_empty(), b: BC(code: [1], cg: cg_new()), scope: no_ints(), f: bare(kind: "fn", text: "f", kids: []), ret: 126)) == [1]
do
  let ens: List[Node] = n_kids(n: kid_at(n: f, i: 3))
  when
    ens == [] then b
    ret <= 0 then gs_bc(g: fold(list: ens, init: GS(p: p, scope: scope, f: f, b: b), func: ens_step))
    else ens_result(p: p, b: b, scope: scope, f: f, ens: ens, res: cg_local(cg: bc_cg(b: b), t: ret))
  end
end

# 戻りの値を局所変数 result に入れてから ensures を調べ、値を戻す
fn ens_result(p: Prog, b: BC, scope: Dict[Int], f: Node, ens: List[Node], res: At) -> BC
  ensures true
  example bc_code(b: ens_result(p: prog_empty(), b: BC(code: [], cg: cg_new()), scope: no_ints(), f: bare(kind: "fn", text: "f", kids: []), ens: [], res: At(at: 0, cg: cg_new()))) == [33, 0, 32, 0]
do
  let sc2: Dict[Int] = if dict_has(dict: scope, key: "result") then scope else dict_put(dict: scope, key: "result", value: at_at(a: res)) end
  bc_then(b: gs_bc(g: fold(list: ens, init: GS(p: p, scope: sc2, f: f, b: BC(code: bc_code(b: b) ++ pasm(p: p, text: "localSet " ++ n2s(n: at_at(a: res))), cg: at_cg(a: res))), func: ens_step)), more: pasm(p: p, text: "localGet " ++ n2s(n: at_at(a: res))))
end

# ---- ブロック ----

# 行を順に作る途中：名前 → 局所変数
type BS
  case BS(p: Prog, scope: Dict[Int], b: BC)
end

fn cg_block(p: Prog, cg: Cg, scope: Dict[Int], b: Node) -> BC
  ensures true
  example bc_code(b: cg_block(p: prog_empty(), cg: cg_new(), scope: no_ints(), b: bare(kind: "block", text: "", kids: [bare(kind: "unit", text: "", kids: [])]))) == []
do
  match fold(list: drop_last_node(xs: n_kids(n: b)), init: BS(p: p, scope: scope, b: BC(code: [], cg: cg)), func: line_code)
    case BS(p: _, scope: sc, b: done) then bc_after(before: bc_code(b: done), b: cg_expr(p: p, cg: bc_cg(b: done), scope: sc, e: last_kid(n: b)))
  end
end

fn drop_last_node(xs: List[Node]) -> List[Node]
  ensures true
  example drop_last_node(xs: []) == []
do
  reverse(list: drop(list: reverse(list: xs), count: 1))
end

fn line_code(s: BS, l: Node) -> BS
  ensures true
  example line_code(s: BS(p: prog_empty(), scope: no_ints(), b: BC(code: [], cg: cg_new())), l: bare(kind: "do", text: "", kids: [bare(kind: "unit", text: "", kids: [])])) == BS(p: prog_empty(), scope: no_ints(), b: BC(code: [], cg: cg_new()))
do
  match s
    case BS(p: p, scope: sc, b: b) then if n_kind(n: l) == "do" then BS(p: p, scope: sc, b: bc_after(before: bc_code(b: b), b: cg_expr(p: p, cg: bc_cg(b: b), scope: sc, e: first_kid(n: l)))) else let_code(p: p, scope: sc, b: b, l: l) end
  end
end

fn let_code(p: Prog, scope: Dict[Int], b: BC, l: Node) -> BS
  ensures true
  example let_code(p: prog_empty(), scope: no_ints(), b: BC(code: [], cg: cg_new()), l: bare(kind: "let", text: "x", kids: [bare(kind: "t", text: "Unit", kids: []), bare(kind: "unit", text: "", kids: [])])) == BS(p: prog_empty(), scope: dict(keys: ["x"], values: [-1]), b: BC(code: [], cg: cg_new()))
do
  let t: Int = val_ast(n: kid_at(n: l, i: 0))
  let cg1: Cg = if t == -1 then unsupported(cg: bc_cg(b: b), what: "let of type " ++ type_str(t: from_ast(n: kid_at(n: l, i: 0), subst: no_subst())), n: l) else bc_cg(b: b) end
  let v: BC = cg_expr(p: p, cg: cg1, scope: scope, e: kid_at(n: l, i: 1))
  if t <= 0 then BS(p: p, scope: dict_put(dict: scope, key: n_text(n: l), value: -1), b: BC(code: bc_code(b: b) ++ bc_code(b: v), cg: bc_cg(b: v))) else
    let idx: At = cg_local(cg: bc_cg(b: v), t: t)
    BS(p: p, scope: dict_put(dict: scope, key: n_text(n: l), value: at_at(a: idx)), b: BC(code: concat(lists: [bc_code(b: b), bc_code(b: v), pasm(p: p, text: "localSet " ++ n2s(n: at_at(a: idx)))]), cg: at_cg(a: idx)))
  end
end

# ---- 式 ----

fn cg_expr(p: Prog, cg: Cg, scope: Dict[Int], e: Node) -> BC
  ensures true
  example bc_code(b: cg_expr(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "int", text: "5", kids: []))) == [66, 5]
do
  let t: Int = val_ty(t: ty_of(p: p, e: e))
  let k: Str = n_kind(n: e)
  if t == -1 then BC(code: [], cg: unsupported(cg: cg, what: "values of type " ++ type_str(t: ty_of(p: p, e: e)), n: e)) else
    when
      k == "int" then BC(code: pasm(p: p, text: "i64 " ++ n_text(n: e)), cg: cg)
      k == "bool" then BC(code: pasm(p: p, text: if n_text(n: e) == "true" then "i32 1" else "i32 0" end), cg: cg)
      k == "str" then str_code(p: p, cg: cg, text: n_text(n: e))
      k == "unit" then BC(code: [], cg: cg)
      k == "var" then var_code(p: p, cg: cg, scope: scope, e: e)
      k == "un" then un_code(p: p, cg: cg, scope: scope, e: e)
      k == "if" then if_code(p: p, cg: cg, scope: scope, e: e, t: t)
      k == "bin" then bin_code(p: p, cg: cg, scope: scope, e: e)
      k == "call" then call_code(p: p, cg: cg, scope: scope, e: e)
      else BC(code: [], cg: unsupported(cg: cg, what: "'" ++ k ++ "' expressions", n: e))
    end
  end
end

fn str_code(p: Prog, cg: Cg, text: Str) -> BC
  ensures true
  example bc_code(b: str_code(p: prog_empty(), cg: cg_new(), text: "a")) == [65, 48]
do
  let s: At = cg_str(cg: cg, text: text)
  BC(code: pasm(p: p, text: "i32 " ++ n2s(n: at_at(a: s))), cg: at_cg(a: s))
end

fn var_code(p: Prog, cg: Cg, scope: Dict[Int], e: Node) -> BC
  ensures true
  example bc_code(b: var_code(p: prog_empty(), cg: cg_new(), scope: dict(keys: ["x"], values: [2]), e: bare(kind: "var", text: "x", kids: []))) == [32, 2]
do
  match dict_get(dict: scope, key: n_text(n: e))
    case Some(value: i) then BC(code: if i < 0 then [] else pasm(p: p, text: "localGet " ++ n2s(n: i)) end, cg: cg)
    case None then
      match dict_get(dict: pg_variants(p: p), key: n_text(n: e))
        case Some(value: v) then tag_code(p: p, cg: cg, v: v)
        case None then BC(code: [], cg: unsupported(cg: cg, what: "'" ++ n_text(n: e) ++ "' as a value", n: e))
      end
  end
end

fn cvar_index(v: CVar) -> Int
  ensures true
  example cvar_index(v: CVar(decl: "A", index: 2, node: bare(kind: "case", text: "B", kids: []))) == 2
do
  match v
    case CVar(decl: _, index: i, node: _) then i
  end
end

fn tag_code(p: Prog, cg: Cg, v: CVar) -> BC
  ensures true
  example bc_code(b: tag_code(p: prog_empty(), cg: cg_new(), v: CVar(decl: "A", index: 0, node: bare(kind: "case", text: "B", kids: [])))) == [65, 48]
do
  let a: At = cg_tag(cg: cg, index: cvar_index(v: v))
  BC(code: pasm(p: p, text: "i32 " ++ n2s(n: at_at(a: a))), cg: at_cg(a: a))
end

fn un_code(p: Prog, cg: Cg, scope: Dict[Int], e: Node) -> BC
  ensures true
  example bc_code(b: un_code(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "un", text: "not", kids: [bare(kind: "bool", text: "true", kids: [])]))) == [65, 1, 69]
do
  let v: BC = cg_expr(p: p, cg: cg, scope: scope, e: first_kid(n: e))
  if n_text(n: e) == "not" then bc_then(b: v, more: pasm(p: p, text: "i32Eqz")) else bc_then(b: bc_after(before: pasm(p: p, text: "i64 0"), b: v), more: pasm(p: p, text: "i64Sub")) end
end

# ブロックの型（値なしは EMPTY）
fn block_ty(t: Int) -> Str
  ensures true
  example block_ty(t: 0) == "EMPTY"
  example block_ty(t: 126) == "I64"
do
  when
    t == 126 then "I64"
    t == 127 then "I32"
    else "EMPTY"
  end
end

fn if_code(p: Prog, cg: Cg, scope: Dict[Int], e: Node, t: Int) -> BC
  ensures true
  example bc_code(b: if_code(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "if", text: "", kids: [bare(kind: "bool", text: "true", kids: []), bare(kind: "block", text: "", kids: [bare(kind: "unit", text: "", kids: [])]), bare(kind: "block", text: "", kids: [bare(kind: "unit", text: "", kids: [])])]), t: 0)) == [65, 1, 4, 64, 5, 11]
do
  let c: BC = cg_expr(p: p, cg: cg, scope: scope, e: kid_at(n: e, i: 0))
  let a: BC = cg_block(p: p, cg: bc_cg(b: c), scope: scope, b: kid_at(n: e, i: 1))
  let b: BC = cg_block(p: p, cg: bc_cg(b: a), scope: scope, b: kid_at(n: e, i: 2))
  BC(code: concat(lists: [bc_code(b: c), pasm(p: p, text: "if " ++ block_ty(t: t)), bc_code(b: a), pasm(p: p, text: "else"), bc_code(b: b), pasm(p: p, text: "end")]), cg: bc_cg(b: b))
end

# 2つの式を順に作る
type Two
  case Two(a: List[Int], b: List[Int], cg: Cg)
end

fn two(p: Prog, cg: Cg, scope: Dict[Int], x: Node, y: Node) -> Two
  ensures true
  example two(p: prog_empty(), cg: cg_new(), scope: no_ints(), x: bare(kind: "int", text: "1", kids: []), y: bare(kind: "int", text: "2", kids: [])) == Two(a: [66, 1], b: [66, 2], cg: cg_new())
do
  let l: BC = cg_expr(p: p, cg: cg, scope: scope, e: x)
  let r: BC = cg_expr(p: p, cg: bc_cg(b: l), scope: scope, e: y)
  Two(a: bc_code(b: l), b: bc_code(b: r), cg: bc_cg(b: r))
end

fn bin_code(p: Prog, cg: Cg, scope: Dict[Int], e: Node) -> BC
  ensures true
  example bc_code(b: bin_code(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "bin", text: "<", kids: [bare(kind: "int", text: "1", kids: []), bare(kind: "int", text: "2", kids: [])]))) == [66, 1, 66, 2, 83]
do
  let op: Str = n_text(n: e)
  if op == "/" or op == "%" then div_code(p: p, cg: cg, scope: scope, e: e) else
    match two(p: p, cg: cg, scope: scope, x: kid_at(n: e, i: 0), y: kid_at(n: e, i: 1))
      case Two(a: l, b: r, cg: cg2) then bin_two(p: p, cg: cg2, e: e, l: l, r: r)
    end
  end
end

fn bin_two(p: Prog, cg: Cg, e: Node, l: List[Int], r: List[Int]) -> BC
  ensures true
  example bc_code(b: bin_two(p: prog_empty(), cg: cg_new(), e: bare(kind: "bin", text: "and", kids: []), l: [1], r: [2])) == [1, 4, 127, 2, 5, 65, 0, 11]
do
  let op: Str = n_text(n: e)
  when
    op == "and" then BC(code: concat(lists: [l, pasm(p: p, text: "if I32"), r, pasm(p: p, text: "else i32 0 end")]), cg: cg)
    op == "or" then BC(code: concat(lists: [l, pasm(p: p, text: "if I32 i32 1 else"), r, pasm(p: p, text: "end")]), cg: cg)
    op == "+" then BC(code: concat(lists: [l, r, pasm(p: p, text: "i64Add call $chk")]), cg: cg)
    op == "-" then BC(code: concat(lists: [l, r, pasm(p: p, text: "i64Sub call $chk")]), cg: cg)
    op == "*" then BC(code: concat(lists: [l, r, pasm(p: p, text: "call $mul")]), cg: cg)
    op == "<" then BC(code: concat(lists: [l, r, pasm(p: p, text: "i64LtS")]), cg: cg)
    op == "<=" then BC(code: concat(lists: [l, r, pasm(p: p, text: "i64LeS")]), cg: cg)
    op == ">" then BC(code: concat(lists: [l, r, pasm(p: p, text: "i64GtS")]), cg: cg)
    op == ">=" then BC(code: concat(lists: [l, r, pasm(p: p, text: "i64GeS")]), cg: cg)
    op == "==" then eq_code(p: p, cg: cg, t: ty_of(p: p, e: kid_at(n: e, i: 0)), a: l, b: r, where: e)
    op == "!=" then bc_then(b: eq_code(p: p, cg: cg, t: ty_of(p: p, e: kid_at(n: e, i: 0)), a: l, b: r, where: e), more: pasm(p: p, text: "i32Eqz"))
    op == "++" and ty_k(t: ty_of(p: p, e: kid_at(n: e, i: 0))) == "Str" then BC(code: concat(lists: [l, r, pasm(p: p, text: "call $concat")]), cg: cg)
    else BC(code: [], cg: unsupported(cg: cg, what: "the operator " ++ op ++ " here", n: e))
  end
end

# / と %：0 で割るなら R503（局所変数を先に取る。src/wasm.js と同じ順）
fn div_code(p: Prog, cg: Cg, scope: Dict[Int], e: Node) -> BC
  ensures true
  example len(list: bc_code(b: div_code(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "bin", text: "/", kids: [bare(kind: "int", text: "1", kids: []), bare(kind: "int", text: "2", kids: [])])))) > 0
do
  let b: At = cg_local(cg: cg, t: 126)
  match two(p: p, cg: at_cg(a: b), scope: scope, x: kid_at(n: e, i: 0), y: kid_at(n: e, i: 1))
    case Two(a: l, b: r, cg: cg2) then div_rest(p: p, b: at_at(a: b), l: l, r: r, fl: emit_fail(p: p, cg: cg2, code: "R503", message: "division by zero", n: e), op: n_text(n: e))
  end
end

fn div_rest(p: Prog, b: Int, l: List[Int], r: List[Int], fl: BC, op: Str) -> BC
  ensures true
  example len(list: bc_code(b: div_rest(p: prog_empty(), b: 0, l: [], r: [], fl: BC(code: [], cg: cg_new()), op: "/"))) > 0
do
  BC(code: concat(lists: [l, r, pasm(p: p, text: "localTee " ++ n2s(n: b) ++ " i64Eqz if EMPTY"), bc_code(b: fl), pasm(p: p, text: "end localGet " ++ n2s(n: b) ++ if op == "/" then " i64DivS" else " i64RemS" end)]), cg: bc_cg(b: fl))
end

# == （中身まで比べる）
fn eq_code(p: Prog, cg: Cg, t: Ty, a: List[Int], b: List[Int], where: Node) -> BC
  ensures true
  example bc_code(b: eq_code(p: prog_empty(), cg: cg_new(), t: tk(k: "Int"), a: [1], b: [2], where: bare(kind: "x", text: "", kids: []))) == [1, 2, 81]
do
  let k: Str = ty_k(t: t)
  when
    k == "Int" then BC(code: concat(lists: [a, b, pasm(p: p, text: "i64Eq")]), cg: cg)
    k == "Bool" or k == "Html" or k == "Sql" then BC(code: concat(lists: [a, b, pasm(p: p, text: "i32Eq")]), cg: cg)
    k == "Str" then BC(code: concat(lists: [a, b, pasm(p: p, text: "call $streq")]), cg: cg)
    k == "Unit" or k == "Var" or k == "Err" then BC(code: concat(lists: [a, b, pasm(p: p, text: "i32 1")]), cg: cg)
    else BC(code: [], cg: unsupported(cg: cg, what: "comparing values of type " ++ type_str(t: t), n: where))
  end
end

# 表示（print・to_str と同じ形）
fn show_code(p: Prog, cg: Cg, t: Ty, code: List[Int], nested: Bool, where: Node) -> BC
  ensures true
  example bc_code(b: show_code(p: prog_empty(), cg: cg_new(), t: tk(k: "Int"), code: [1], nested: false, where: bare(kind: "x", text: "", kids: []))) == [1, 16, 0]
do
  let k: Str = ty_k(t: t)
  when
    k == "Str" and not nested then BC(code: code, cg: cg)
    k == "Html" then BC(code: code, cg: cg)
    k == "Int" then BC(code: code ++ pasm(p: p, text: "call $itoa"), cg: cg)
    k == "Bool" then bool_show(p: p, cg: cg, code: code)
    k == "Unit" or k == "Var" or k == "Err" then unit_show(p: p, cg: cg, code: code)
    else BC(code: [], cg: unsupported(cg: cg, what: "showing values of type " ++ type_str(t: t), n: where))
  end
end

fn unit_show(p: Prog, cg: Cg, code: List[Int]) -> BC
  ensures true
  example bc_code(b: unit_show(p: prog_empty(), cg: cg_new(), code: [])) == [65, 48]
do
  let s: At = cg_str(cg: cg, text: "()")
  BC(code: code ++ pasm(p: p, text: "i32 " ++ n2s(n: at_at(a: s))), cg: at_cg(a: s))
end

fn bool_show(p: Prog, cg: Cg, code: List[Int]) -> BC
  ensures true
  example len(list: bc_code(b: bool_show(p: prog_empty(), cg: cg_new(), code: []))) > 0
do
  let t: At = cg_str(cg: cg, text: "true")
  let f: At = cg_str(cg: at_cg(a: t), text: "false")
  BC(code: code ++ pasm(p: p, text: "if I32 i32 " ++ n2s(n: at_at(a: t)) ++ " else i32 " ++ n2s(n: at_at(a: f)) ++ " end"), cg: at_cg(a: f))
end

# ---- 呼び出し ----

fn arg_value(e: Node, name: Str) -> Node
  ensures true
  example n_kind(n: arg_value(e: bare(kind: "call", text: "f", kids: []), name: "x")) == "none"
do
  first_kid(n: find_arg(args: n_kids(n: e), name: name))
end

# 引数を順に作る途中
type AS
  case AS(p: Prog, scope: Dict[Int], e: Node, b: BC)
end

fn as_bc(a: AS) -> BC
  ensures true
  example bc_code(b: as_bc(a: AS(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "f", kids: []), b: BC(code: [], cg: cg_new())))) == []
do
  match a
    case AS(p: _, scope: _, e: _, b: b) then b
  end
end

# 引数 prm の値（鍵は消す）
fn param_arg(s: AS, prm: Node) -> AS
  ensures true
  example param_arg(s: AS(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "f", kids: []), b: BC(code: [], cg: cg_new())), prm: bare(kind: "param", text: "c", kids: [bare(kind: "t", text: "Console", kids: [])])) == AS(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "f", kids: []), b: BC(code: [], cg: cg_new()))
do
  match s
    case AS(p: p, scope: sc, e: e, b: b) then if is_cap_node(n: first_kid(n: prm)) then s else AS(p: p, scope: sc, e: e, b: bc_after(before: bc_code(b: b), b: cg_expr(p: p, cg: bc_cg(b: b), scope: sc, e: arg_value(e: e, name: n_text(n: prm))))) end
  end
end

fn call_code(p: Prog, cg: Cg, scope: Dict[Int], e: Node) -> BC
  ensures true
  example bc_code(b: call_code(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "call", text: "str_len", kids: [bare(kind: "arg", text: "text", kids: [bare(kind: "str", text: "", kids: [])])]))) == [65, 48, 16, 0]
do
  let name: Str = n_text(n: e)
  match dict_get(dict: pg_fn_nodes(p: p), key: name)
    case Some(value: f) then bc_then(b: as_bc(a: fold(list: n_kids(n: kid_at(n: f, i: 0)), init: AS(p: p, scope: scope, e: e, b: BC(code: [], cg: cg)), func: param_arg)), more: pasm(p: p, text: "call $fn:" ++ name))
    case None then builtin_code(p: p, cg: cg, scope: scope, e: e)
  end
end

fn builtin_code(p: Prog, cg: Cg, scope: Dict[Int], e: Node) -> BC
  ensures true
  example bc_code(b: builtin_code(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "call", text: "nope", kids: []))) == []
do
  let name: Str = n_text(n: e)
  when
    name == "str_len" then bc_then(b: cg_expr(p: p, cg: cg, scope: scope, e: arg_value(e: e, name: "text")), more: pasm(p: p, text: "call $strlen"))
    name == "to_str" or name == "print" then show_call(p: p, cg: cg, scope: scope, e: e, v: arg_value(e: e, name: "value"))
    else BC(code: [], cg: unsupported(cg: cg, what: "the built-in function " ++ name, n: e))
  end
end

fn show_call(p: Prog, cg: Cg, scope: Dict[Int], e: Node, v: Node) -> BC
  ensures true
  example bc_code(b: show_call(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "call", text: "to_str", kids: []), v: bare(kind: "unit", text: "", kids: []))) == [65, 48]
do
  let code: BC = cg_expr(p: p, cg: cg, scope: scope, e: v)
  let s: BC = show_code(p: p, cg: bc_cg(b: code), t: ty_of(p: p, e: v), code: bc_code(b: code), nested: false, where: v)
  if n_text(n: e) == "to_str" then s else BC(code: concat(lists: [pasm(p: p, text: "i32 1"), bc_code(b: s), pasm(p: p, text: "i32 1 call $write")]), cg: bc_cg(b: s)) end
end

# ---- モジュール全体（src/wasm.js の module と同じ並び） ----

# 型の表（関数の形を重ねずに並べる）
type TT
  case TT(types: List[List[Int]], at: Int)
end

fn func_type(params: List[Int], results: List[Int]) -> List[Int]
  ensures true
  example func_type(params: [127], results: []) == [96, 1, 127, 0]
do
  [96] ++ uleb(n: len(list: params)) ++ params ++ uleb(n: len(list: results)) ++ results
end

# 形の番号（無ければ足す）
fn type_index(types: List[List[Int]], t: List[Int]) -> TT
  ensures true
  example type_index(types: [[1]], t: [2]) == TT(types: [[1], [2]], at: 1)
  example type_index(types: [[1], [2]], t: [2]) == TT(types: [[1], [2]], at: 1)
do
  match fold(list: types, init: Find(want: t, i: 0, found: -1), func: find_step)
    case Find(want: _, i: _, found: f) then if f >= 0 then TT(types: types, at: f) else TT(types: append(list: types, item: t), at: len(list: types)) end
  end
end

type Find
  case Find(want: List[Int], i: Int, found: Int)
end

fn find_step(f: Find, x: List[Int]) -> Find
  ensures true
  example find_step(f: Find(want: [1], i: 0, found: -1), x: [1]) == Find(want: [1], i: 1, found: 0)
do
  match f
    case Find(want: w, i: i, found: fd) then Find(want: w, i: i + 1, found: if fd < 0 and x == w then i else fd end)
  end
end

# 関数ごとに型の番号を付ける途中
type TI
  case TI(types: List[List[Int]], out: List[Int])
end

fn index_func(t: TI, f: Func) -> TI
  ensures true
  example index_func(t: TI(types: [], out: []), f: Func(params: [], results: [], locals: [], body: [])) == TI(types: [[96, 0, 0]], out: [0])
do
  match t
    case TI(types: ts, out: o) then
      match type_index(types: ts, t: func_type(params: func_params(f: f), results: func_results(f: f)))
        case TT(types: ts2, at: a) then TI(types: ts2, out: append(list: o, item: a))
      end
  end
end

fn func_params(f: Func) -> List[Int]
  ensures true
  example func_params(f: Func(params: [1], results: [], locals: [], body: [])) == [1]
do
  match f
    case Func(params: ps, results: _, locals: _, body: _) then ps
  end
end

fn func_results(f: Func) -> List[Int]
  ensures true
  example func_results(f: Func(params: [], results: [1], locals: [], body: [])) == [1]
do
  match f
    case Func(params: _, results: rs, locals: _, body: _) then rs
  end
end

# 関数の本体のバイト（局所変数は、同じ型が続くものをまとめる）
fn code_entry(f: Func) -> List[Int]
  ensures true
  example code_entry(f: Func(params: [], results: [], locals: [127, 127, 126], body: [11])) == [6, 2, 2, 127, 1, 126, 11]
do
  match f
    case Func(params: _, results: _, locals: ls, body: b) then
      match fold(list: ls, init: Runs(out: [], last: 0, count: 0), func: run_step)
        case Runs(out: o, last: l, count: c) then with_size(bytes: wvec(items: if c > 0 then append(list: o, item: uleb(n: c) ++ [l]) else o end) ++ b)
      end
  end
end

fn with_size(bytes: List[Int]) -> List[Int]
  ensures true
  example with_size(bytes: [1, 2]) == [2, 1, 2]
do
  uleb(n: len(list: bytes)) ++ bytes
end

type Runs
  case Runs(out: List[List[Int]], last: Int, count: Int)
end

fn run_step(r: Runs, t: Int) -> Runs
  ensures true
  example run_step(r: Runs(out: [], last: 127, count: 1), t: 127) == Runs(out: [], last: 127, count: 2)
do
  match r
    case Runs(out: o, last: l, count: c) then if c > 0 and t == l then Runs(out: o, last: l, count: c + 1) else Runs(out: if c > 0 then append(list: o, item: uleb(n: c) ++ [l]) else o end, last: t, count: 1) end
  end
end

# コンパイルの答え：バイトか、エラーの文（"E600 行:列 …"）
type Built
  case Built(bytes: List[Int], err: Str)
end

# 型の検査を通ったプログラムを .wasm のバイトにする
fn compile_typed(typed: Typed) -> Built
  ensures true
  example compile_typed(typed: Typed(diags: [], fns: [], items: [])) == Built(bytes: [], err: "E600 1:1 the compiler does not support a program without main yet")
do
  match typed
    case Typed(diags: _, fns: tys, items: items) then compile_items(fns: map(list: filter(list: items, func: item_is_fn), func: item_node), types: map(list: filter(list: items, func: item_is_type), func: item_node), tys: tys)
  end
end

fn compile_items(fns: List[Node], types: List[Node], tys: List[FnTypes]) -> Built
  ensures true
  example compile_items(fns: [], types: [], tys: []) == Built(bytes: [], err: "E600 1:1 the compiler does not support a program without main yet")
do
  match find(list: fns, func: is_main_fn_node)
    case None then Built(bytes: [], err: "E600 1:1 the compiler does not support a program without main yet")
    case Some(value: m) then
      match find(list: n_kids(n: kid_at(n: m, i: 0)), func: not_cap_param)
        case Some(value: prm) then Built(bytes: [], err: "E600 " ++ to_str(value: n_line(n: prm)) ++ ":" ++ to_str(value: n_col(n: prm)) ++ " the compiler does not support the parameter " ++ n_text(n: prm) ++ " of main yet")
        case None then if any(list: n_kids(n: kid_at(n: m, i: 0)), func: is_file_param) then Built(bytes: [], err: "E600 1:1 the compiler does not support Folder and OutFolder yet (Akashi compiler)") else compile_main(p: make_prog(fns: fns, types: types, tys: tys, nimports: 2)) end
      end
  end
end

fn is_main_fn_node(n: Node) -> Bool
  ensures true
  example is_main_fn_node(n: bare(kind: "fn", text: "main", kids: []))
do
  n_text(n: n) == "main"
end

fn not_cap_param(p: Node) -> Bool
  ensures true
  example not_cap_param(p: bare(kind: "param", text: "x", kids: [bare(kind: "t", text: "Int", kids: [])]))
do
  not is_cap_node(n: first_kid(n: p))
end

fn is_file_param(p: Node) -> Bool
  ensures true
  example is_file_param(p: bare(kind: "param", text: "f", kids: [bare(kind: "t", text: "Folder", kids: [])]))
do
  n_text(n: first_kid(n: p)) == "Folder" or n_text(n: first_kid(n: p)) == "OutFolder"
end

# 記号の表と、型・case の表を作る
fn make_prog(fns: List[Node], types: List[Node], tys: List[FnTypes], nimports: Int) -> Prog
  ensures true
  example sym(p: make_prog(fns: [], types: [], tys: [], nimports: 2), name: "alloc") == 2
  example sym(p: make_prog(fns: [bare(kind: "fn", text: "main", kids: [])], types: [], tys: [], nimports: 2), name: "fn:main") == 13
do
  let base: Dict[Int] = dict(keys: ["fdWrite", "procExit", "heap", "depth", "readFd", "writeFd"], values: [0, 1, 0, 1, 2, 3])
  let hs: Dict[Int] = add_syms(d: base, prefix: "", names: helper_names(), start: nimports)
  let all_syms: Dict[Int] = add_syms(d: hs, prefix: "fn:", names: map(list: fns, func: n_text), start: nimports + 11)
  let decl_nodes: List[Node] = builtin_type_nodes() ++ types
  Prog(fns: fns, fn_nodes: fold(list: fns, init: dict(keys: [], values: []), func: put_node), variants: fold(list: decl_nodes, init: dict(keys: [], values: []), func: put_cases), decls: fold(list: decl_nodes, init: dict(keys: [], values: []), func: put_node), syms: all_syms, gen_base: nimports + 11 + len(list: fns) + 1, types: dict(keys: [], values: []), all_types: tys)
end

type SymAcc
  case SymAcc(prefix: Str, at: Int, out: Dict[Int])
end

fn add_syms(d: Dict[Int], prefix: Str, names: List[Str], start: Int) -> Dict[Int]
  ensures true
  example add_syms(d: no_ints(), prefix: "f:", names: ["a", "b"], start: 3) == dict(keys: ["f:a", "f:b"], values: [3, 4])
do
  match fold(list: names, init: SymAcc(prefix: prefix, at: start, out: d), func: sym_step)
    case SymAcc(prefix: _, at: _, out: o) then o
  end
end

fn sym_step(acc: SymAcc, name: Str) -> SymAcc
  ensures true
  example sym_step(acc: SymAcc(prefix: "", at: 1, out: no_ints()), name: "a") == SymAcc(prefix: "", at: 2, out: dict(keys: ["a"], values: [1]))
do
  match acc
    case SymAcc(prefix: px, at: i, out: o) then SymAcc(prefix: px, at: i + 1, out: dict_put(dict: o, key: px ++ name, value: i))
  end
end

fn put_node(d: Dict[Node], n: Node) -> Dict[Node]
  ensures true
  example dict_has(dict: put_node(d: dict(keys: [], values: []), n: bare(kind: "fn", text: "f", kids: [])), key: "f")
do
  if dict_has(dict: d, key: n_text(n: n)) then d else dict_put(dict: d, key: n_text(n: n), value: n) end
end

type CaseAcc
  case CaseAcc(decl: Str, i: Int, out: Dict[CVar])
end

# 型 t の case を、書いた順の番号で表に入れる
fn put_cases(d: Dict[CVar], t: Node) -> Dict[CVar]
  ensures true
  example dict_size(dict: put_cases(d: dict(keys: [], values: []), t: bare(kind: "type", text: "A", kids: [bare(kind: "case", text: "B", kids: []), bare(kind: "case", text: "C", kids: [])]))) == 2
do
  match fold(list: n_kids(n: t), init: CaseAcc(decl: n_text(n: t), i: 0, out: d), func: case_step)
    case CaseAcc(decl: _, i: _, out: o) then o
  end
end

fn case_step(acc: CaseAcc, c: Node) -> CaseAcc
  ensures true
  example case_step(acc: CaseAcc(decl: "A", i: 0, out: dict(keys: [], values: [])), c: bare(kind: "case", text: "B", kids: [])) == CaseAcc(decl: "A", i: 1, out: dict(keys: ["B"], values: [CVar(decl: "A", index: 0, node: bare(kind: "case", text: "B", kids: []))]))
do
  match acc
    case CaseAcc(decl: d, i: i, out: o) then CaseAcc(decl: d, i: i + 1, out: dict_put(dict: o, key: n_text(n: c), value: CVar(decl: d, index: i, node: c)))
  end
end

fn pg_fns(p: Prog) -> List[Node]
  ensures true
  example pg_fns(p: prog_empty()) == []
do
  match p
    case Prog(fns: f, fn_nodes: _, variants: _, decls: _, syms: _, gen_base: _, types: _, all_types: _) then f
  end
end

fn pg_gen_base(p: Prog) -> Int
  ensures true
  example pg_gen_base(p: prog_empty()) == 0
do
  match p
    case Prog(fns: _, fn_nodes: _, variants: _, decls: _, syms: _, gen_base: g, types: _, all_types: _) then g
  end
end

# 利用者の関数を順に作る途中
type UF
  case UF(p: Prog, funcs: List[Func], cg: Cg)
end

fn user_fn_step(u: UF, f: Node) -> UF
  ensures true
  example len(list: uf_funcs(u: user_fn_step(u: UF(p: prog_empty(), funcs: [], cg: cg_new()), f: get(list: fns_of(text: "fn f() -> Int do 1 end"), index: 0)))) == 1
do
  match u
    case UF(p: p, funcs: fs, cg: cg) then
      match gen_fn(p0: p, cg: cg, f: f)
        case FC(func: fn1, cg: cg2) then UF(p: p, funcs: append(list: fs, item: fn1), cg: cg2)
      end
  end
end

fn uf_funcs(u: UF) -> List[Func]
  ensures true
  example uf_funcs(u: UF(p: prog_empty(), funcs: [], cg: cg_new())) == []
do
  match u
    case UF(p: _, funcs: fs, cg: _) then fs
  end
end

# 取り込み（WASI の fd_write・proc_exit）
fn import_bytes(types: List[List[Int]]) -> List[List[Int]]
  ensures len(list: result) == 2
  example len(list: import_bytes(types: [])) == 2
do
  [wname(text: "wasi_snapshot_preview1") ++ wname(text: "fd_write") ++ [0, 0], wname(text: "wasi_snapshot_preview1") ++ wname(text: "proc_exit") ++ [0, 1]]
end

fn compile_main(p: Prog) -> Built
  ensures true
  example compile_main(p: prog_empty()) != Built(bytes: [], err: "x")
do
  let users: UF = fold(list: pg_fns(p: p), init: UF(p: p, funcs: [], cg: cg_new()), func: user_fn_step)
  match users
    case UF(p: _, funcs: ufs, cg: cg1) then
      match helpers(p: p, cg: cg1)
        case Funcs(funcs: hfs, cg: cg2) then if cg_err(cg: cg2) != "" then Built(bytes: [], err: cg_err(cg: cg2)) else Built(bytes: assemble(p: p, hfuncs: hfs, users: ufs, cg: cg2), err: "") end
      end
  end
end

# バイトを並べる。型の表は、取り込み・_start・手伝い・利用者・型ごとの手伝いの順に作る（src/wasm.js と同じ）
fn assemble(p: Prog, hfuncs: List[Func], users: List[Func], cg: Cg) -> List[Int]
  ensures true
  example len(list: assemble(p: prog_empty(), hfuncs: [], users: [], cg: cg_new())) > 8
do
  let t0: List[List[Int]] = [func_type(params: [127, 127, 127, 127], results: [127]), func_type(params: [127], results: [])]
  let start_t: TT = type_index(types: t0, t: func_type(params: [], results: []))
  let start: Func = Func(params: [], results: [], locals: [], body: pasm(p: p, text: "call $fn:main end"))
  let funcs: List[Func] = concat(lists: [hfuncs, users, [start], cg_gens(cg: cg)])
  let ti: TI = fold(list: concat(lists: [hfuncs, users]), init: TI(types: match start_t
    case TT(types: ts, at: _) then ts
  end, out: []), func: index_func)
  let ti2: TI = fold(list: cg_gens(cg: cg), init: ti_with(t: ti, x: tt_at(t: start_t)), func: index_func)
  let heap: Int = (cg_data_end(cg: cg) + 7) / 8 * 8
  let start_index: Int = 2 + 11 + len(list: users)
  concat(lists: [
  [0, 97, 115, 109, 1, 0, 0, 0],
  wsection(id: 1, body: wvec(items: ti_types(t: ti2))),
  wsection(id: 2, body: wvec(items: import_bytes(types: []))),
  wsection(id: 3, body: wvec(items: map(list: ti_out(t: ti2), func: uleb))),
  wsection(id: 5, body: wvec(items: [[0] ++ uleb(n: (heap + 65535) / 65536 + 1)])),
  wsection(id: 6, body: wvec(items: [[127, 1] ++ pasm(p: p, text: "i32 " ++ n2s(n: heap) ++ " end"), [127, 1] ++ pasm(p: p, text: "i32 0 end"), [127, 1] ++ pasm(p: p, text: "i32 -1 end"), [127, 1] ++ pasm(p: p, text: "i32 -1 end")])),
  wsection(id: 7, body: wvec(items: [wname(text: "memory") ++ [2, 0], wname(text: "_start") ++ [0] ++ uleb(n: start_index)])),
  wsection(id: 10, body: wvec(items: map(list: funcs, func: code_entry))),
  wsection(id: 11, body: wvec(items: [[0] ++ pasm(p: p, text: "i32 48 end") ++ wvec(items: map(list: cg_data(cg: cg), func: one_byte))]))
  ])
end

fn one_byte(b: Int) -> List[Int]
  ensures len(list: result) == 1
  example one_byte(b: 7) == [7]
do
  [b]
end

fn tt_at(t: TT) -> Int
  ensures true
  example tt_at(t: TT(types: [], at: 2)) == 2
do
  match t
    case TT(types: _, at: a) then a
  end
end

fn ti_types(t: TI) -> List[List[Int]]
  ensures true
  example ti_types(t: TI(types: [[1]], out: [])) == [[1]]
do
  match t
    case TI(types: ts, out: _) then ts
  end
end

fn ti_out(t: TI) -> List[Int]
  ensures true
  example ti_out(t: TI(types: [], out: [3])) == [3]
do
  match t
    case TI(types: _, out: o) then o
  end
end

# _start の型の番号を、利用者の関数の後ろに入れる
fn ti_with(t: TI, x: Int) -> TI
  ensures true
  example ti_with(t: TI(types: [], out: [1]), x: 0) == TI(types: [], out: [1, 0])
do
  match t
    case TI(types: ts, out: o) then TI(types: ts, out: append(list: o, item: x))
  end
end
