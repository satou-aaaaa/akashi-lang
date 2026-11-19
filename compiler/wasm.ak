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
  Func(params: [127], results: [127], locals: [127], body: asm(text: "localGet 0 i32 1073741824 i32GtU if EMPTY i32 $r513 call $fail end globalGet $heap localSet 1 globalGet $heap localGet 0 i32Add i32 3 i32Add i32 -4 i32And globalSet $heap globalGet $heap localGet 1 i32LtU if EMPTY i32 $r513 call $fail end block EMPTY loop EMPTY globalGet $heap memorySize i32 16 i32Shl i32LtU brIf 1 memorySize memoryGrow i32 -1 i32Eq if EMPTY i32 1 memoryGrow i32 -1 i32Eq if EMPTY i32 $r513 call $fail end end br 0 end end localGet 1 end", syms: s)),
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
      k == "list" then list_code(p: p, cg: cg, scope: scope, e: e)
      k == "match" then match_code(p: p, cg: cg, scope: scope, e: e, t: t)
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
    op == "++" then call_gen(p: p, code: l ++ r, g: list_cat_fn(p: p, cg: cg))
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
    k == "List" then call_gen(p: p, code: a ++ b, g: eq_list_fn(p: p, cg: cg, t: t, where: where))
    k == "Dict" then call_gen(p: p, code: a ++ b, g: eq_dict_fn(p: p, cg: cg, t: t, where: where))
    k == "Data" then call_gen(p: p, code: a ++ b, g: eq_data_fn(p: p, cg: cg, t: t, where: where))
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
    k == "Str" then call_gen(p: p, code: code, g: quote_fn(p: p, cg: cg))
    k == "Html" then BC(code: code, cg: cg)
    k == "Sql" then call_gen(p: p, code: code, g: show_sql_fn(p: p, cg: cg))
    k == "Int" then BC(code: code ++ pasm(p: p, text: "call $itoa"), cg: cg)
    k == "Bool" then bool_show(p: p, cg: cg, code: code)
    k == "Unit" or k == "Var" or k == "Err" then unit_show(p: p, cg: cg, code: code)
    k == "List" then call_gen(p: p, code: code, g: show_list_fn(p: p, cg: cg, t: t, where: where))
    k == "Dict" then call_gen(p: p, code: code, g: show_dict_fn(p: p, cg: cg, t: t, where: where))
    k == "Data" then call_gen(p: p, code: code, g: show_data_fn(p: p, cg: cg, t: t, where: where))
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
    case None then if dict_has(dict: pg_variants(p: p), key: name) then ctor_code(p: p, cg: cg, scope: scope, e: e) else builtin_code(p: p, cg: cg, scope: scope, e: e) end
  end
end

# case を作る：欄の値を、型に書いた欄の順に作る
fn ctor_code(p: Prog, cg: Cg, scope: Dict[Int], e: Node) -> BC
  ensures true
  example bc_code(b: ctor_code(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "call", text: "None", kids: []))) == [65, 48]
do
  match fold(list: n_kids(n: cvar_node(v: cvar_of(p: p, name: n_text(n: e)))), init: CF(p: p, scope: scope, e: e, out: [], cg: cg), func: cf_step)
    case CF(p: _, scope: _, e: _, out: fs, cg: cg2) then mk_data(p: p, cg: cg2, t: ty_of(p: p, e: e), vname: n_text(n: e), fields: fs, where: e)
  end
end

type CF
  case CF(p: Prog, scope: Dict[Int], e: Node, out: List[List[Int]], cg: Cg)
end

fn cf_step(acc: CF, f: Node) -> CF
  ensures true
  example cf_step(acc: CF(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "A", kids: [bare(kind: "arg", text: "x", kids: [bare(kind: "int", text: "1", kids: [])])]), out: [], cg: cg_new()), f: bare(kind: "field", text: "x", kids: [])) == CF(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "A", kids: [bare(kind: "arg", text: "x", kids: [bare(kind: "int", text: "1", kids: [])])]), out: [[66, 1]], cg: cg_new())
do
  match acc
    case CF(p: p, scope: sc, e: e, out: o, cg: cg) then cf_put(acc: acc, v: cg_expr(p: p, cg: cg, scope: sc, e: arg_value(e: e, name: n_text(n: f))))
  end
end

fn cf_put(acc: CF, v: BC) -> CF
  ensures true
  example cf_put(acc: CF(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), out: [], cg: cg_new()), v: BC(code: [1], cg: cg_new())) == CF(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), out: [[1]], cg: cg_new())
do
  match acc
    case CF(p: p, scope: sc, e: e, out: o, cg: _) then CF(p: p, scope: sc, e: e, out: append(list: o, item: bc_code(b: v)), cg: bc_cg(b: v))
  end
end

# コードのあとで、作った手伝いの関数を呼ぶ
fn call_gen(p: Prog, code: List[Int], g: At) -> BC
  ensures true
  example bc_code(b: call_gen(p: prog_empty(), code: [1], g: At(at: 3, cg: cg_new()))) == [1, 16, 3]
do
  BC(code: code ++ pasm(p: p, text: "call " ++ n2s(n: at_at(a: g))), cg: at_cg(a: g))
end

fn builtin_code(p: Prog, cg: Cg, scope: Dict[Int], e: Node) -> BC
  ensures true
  example bc_code(b: builtin_code(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "call", text: "nope", kids: []))) == []
do
  let name: Str = n_text(n: e)
  when
    name == "str_len" then bc_then(b: cg_expr(p: p, cg: cg, scope: scope, e: arg_value(e: e, name: "text")), more: pasm(p: p, text: "call $strlen"))
    name == "to_str" or name == "print" then show_call(p: p, cg: cg, scope: scope, e: e, v: arg_value(e: e, name: "value"))
    in_table(table: " len get at range append concat map filter fold find any all reverse take drop sort sum max min ", word: name) then list_builtin(p: p, cg: cg, scope: scope, e: e)
    in_table(table: " chars split join contains starts_with ends_with lines html html_text html_join sql trim parse_int slice code_of char_of ", word: name) then text_builtin(p: p, cg: cg, scope: scope, e: e)
    in_table(table: " dict dict_put dict_get dict_has dict_remove dict_keys dict_values dict_size ", word: name) then dict_builtin(p: p, cg: cg, scope: scope, e: e)
    in_table(table: " read_text write_text write_bytes ", word: name) then file_builtin(p: p, cg: cg, scope: scope, e: e)
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

# ---- 型ごとの手伝いの関数（src/wasm.js の gen） ----
# 番号を先に取ってから中身を作る（中で別の手伝いの関数を作ると、その番号は後ろになる）。同じ鍵には1つだけ

type GenOpen
  case GenOpen(at: Int, found: Bool, slot: Int, saved: List[Int], saved_n: Int, params: List[Int], results: List[Int], cg: Cg)
end

fn cg_gen_idx(cg: Cg) -> Dict[Int]
  ensures true
  example dict_size(dict: cg_gen_idx(cg: cg_new())) == 0
do
  match cg
    case Cg(data: _, strings: _, data_end: _, tags: _, gens: _, gen_idx: gi, locals: _, nparams: _, err: _) then gi
  end
end

fn cg_set_gens(cg: Cg, gens: List[Func], gen_idx: Dict[Int]) -> Cg
  ensures cg_gens(cg: result) == gens
  example cg_gens(cg: cg_set_gens(cg: cg_new(), gens: [], gen_idx: no_ints())) == []
do
  match cg
    case Cg(data: d, strings: s, data_end: de, tags: t, gens: _, gen_idx: _, locals: l, nparams: np, err: e) then Cg(data: d, strings: s, data_end: de, tags: t, gens: gens, gen_idx: gen_idx, locals: l, nparams: np, err: e)
  end
end

fn pg_decls(p: Prog) -> Dict[Node]
  ensures true
  example dict_size(dict: pg_decls(p: prog_empty())) == 0
do
  match p
    case Prog(fns: _, fn_nodes: _, variants: _, decls: d, syms: _, gen_base: _, types: _, all_types: _) then d
  end
end

fn gen_open(p: Prog, cg: Cg, key: Str, params: List[Int], results: List[Int]) -> GenOpen
  ensures true
  example go_at(g: gen_open(p: prog_empty(), cg: cg_new(), key: "k", params: [127], results: [127])) == 0
  example go_found(g: gen_open(p: prog_empty(), cg: go_cg(g: gen_open(p: prog_empty(), cg: cg_new(), key: "k", params: [127], results: [127])), key: "k", params: [127], results: [127]))
do
  match dict_get(dict: cg_gen_idx(cg: cg), key: key)
    case Some(value: i) then GenOpen(at: i, found: true, slot: 0, saved: [], saved_n: 0, params: params, results: results, cg: cg)
    case None then gen_new(p: p, cg: cg, key: key, params: params, results: results)
  end
end

fn gen_new(p: Prog, cg: Cg, key: Str, params: List[Int], results: List[Int]) -> GenOpen
  ensures true
  example go_at(g: gen_new(p: prog_empty(), cg: cg_new(), key: "k", params: [], results: [])) == 0
do
  let slot: Int = len(list: cg_gens(cg: cg))
  let gat: Int = pg_gen_base(p: p) + slot
  let cg2: Cg = cg_set_gens(cg: cg, gens: append(list: cg_gens(cg: cg), item: Func(params: params, results: results, locals: [], body: [])), gen_idx: dict_put(dict: cg_gen_idx(cg: cg), key: key, value: gat))
  GenOpen(at: gat, found: false, slot: slot, saved: cg_locals(cg: cg), saved_n: cg_nparams(cg: cg), params: params, results: results, cg: cg_frame(cg: cg2, nparams: len(list: params), locals: []))
end

fn go_at(g: GenOpen) -> Int
  ensures true
  example go_at(g: GenOpen(at: 4, found: true, slot: 0, saved: [], saved_n: 0, params: [], results: [], cg: cg_new())) == 4
do
  match g
    case GenOpen(at: a, found: _, slot: _, saved: _, saved_n: _, params: _, results: _, cg: _) then a
  end
end

fn go_found(g: GenOpen) -> Bool
  ensures true
  example go_found(g: GenOpen(at: 4, found: true, slot: 0, saved: [], saved_n: 0, params: [], results: [], cg: cg_new()))
do
  match g
    case GenOpen(at: _, found: f, slot: _, saved: _, saved_n: _, params: _, results: _, cg: _) then f
  end
end

fn go_cg(g: GenOpen) -> Cg
  ensures true
  example go_cg(g: GenOpen(at: 4, found: true, slot: 0, saved: [], saved_n: 0, params: [], results: [], cg: cg_new())) == cg_new()
do
  match g
    case GenOpen(at: _, found: _, slot: _, saved: _, saved_n: _, params: _, results: _, cg: c) then c
  end
end

# 中身を入れて、作っていた関数の局所変数に戻す
fn gen_close(g: GenOpen, body: BC) -> At
  ensures true
  example at_at(a: gen_close(g: gen_open(p: prog_empty(), cg: cg_new(), key: "k", params: [], results: []), body: BC(code: [], cg: cg_new()))) == 0
do
  match g
    case GenOpen(at: gat, found: _, slot: slot, saved: sv, saved_n: sn, params: ps, results: rs, cg: _) then At(at: gat, cg: gen_put(cg: bc_cg(b: body), slot: slot, f: Func(params: ps, results: rs, locals: cg_locals(cg: bc_cg(b: body)), body: bc_code(b: body) ++ [11]), saved: sv, saved_n: sn))
  end
end

fn gen_put(cg: Cg, slot: Int, f: Func, saved: List[Int], saved_n: Int) -> Cg
  ensures true
  example cg_gens(cg: gen_put(cg: cg_set_gens(cg: cg_new(), gens: [Func(params: [], results: [], locals: [], body: [])], gen_idx: no_ints()), slot: 0, f: Func(params: [], results: [], locals: [], body: [11]), saved: [], saved_n: 0)) == [Func(params: [], results: [], locals: [], body: [11])]
do
  let gs: List[Func] = cg_gens(cg: cg)
  let put: List[Func] = if slot < 0 then gs else concat(lists: [take(list: gs, count: slot), [f], drop(list: gs, count: slot + 1)]) end
  cg_frame(cg: cg_set_gens(cg: cg, gens: put, gen_idx: cg_gen_idx(cg: cg)), nparams: saved_n, locals: saved)
end

# 作りはじめた手伝いの関数の局所変数を決める（中身を文字で書くもの）
fn gen_locals(cg: Cg, ts: List[Int]) -> Cg
  ensures cg_locals(cg: result) == ts
  example cg_locals(cg: gen_locals(cg: cg_new(), ts: [127])) == [127]
do
  cg_frame(cg: cg, nparams: cg_nparams(cg: cg), locals: ts)
end

# 同じ型の局所変数を n 個
fn i32s(n: Int) -> List[Int]
  ensures true
  example i32s(n: 2) == [127, 127]
do
  map(list: range(from: 0, to: n), func: i32_of)
end

fn i32_of(i: Int) -> Int
  ensures result == 127
  example i32_of(i: 3) == 127
do
  127 + 0 * i
end

# ---- 命令の文字の部品（src/wasm.js の forEach・elemAddr など） ----

# i を 0 から n-1 まで回す
fn each_t(i: Int, n: Int, body: Str) -> Str
  ensures true
  example each_t(i: 1, n: 2, body: "nop") == "i32 0 localSet 1 block EMPTY loop EMPTY localGet 1 localGet 2 i32GeU brIf 1 nop localGet 1 i32 1 i32Add localSet 1 br 0 end end"
do
  "i32 0 localSet " ++ n2s(n: i) ++ " block EMPTY loop EMPTY localGet " ++ n2s(n: i) ++ " localGet " ++ n2s(n: n) ++ " i32GeU brIf 1 " ++ body ++ " localGet " ++ n2s(n: i) ++ " i32 1 i32Add localSet " ++ n2s(n: i) ++ " br 0 end end"
end

fn each_b(p: Prog, i: Int, n: Int, body: List[Int]) -> List[Int]
  ensures true
  example each_b(p: prog_empty(), i: 0, n: 1, body: []) == pasm(p: prog_empty(), text: each_t(i: 0, n: 1, body: ""))
do
  concat(lists: [pasm(p: p, text: "i32 0 localSet " ++ n2s(n: i) ++ " block EMPTY loop EMPTY localGet " ++ n2s(n: i) ++ " localGet " ++ n2s(n: n) ++ " i32GeU brIf 1"), body, pasm(p: p, text: "localGet " ++ n2s(n: i) ++ " i32 1 i32Add localSet " ++ n2s(n: i) ++ " br 0 end end")])
end

# リスト l の i 番めの要素の場所から 8 を引いたもの
fn elem_t(l: Int, i: Int) -> Str
  ensures true
  example elem_t(l: 0, i: 2) == "localGet 0 localGet 2 i32 8 i32Mul i32Add"
do
  "localGet " ++ n2s(n: l) ++ " localGet " ++ n2s(n: i) ++ " i32 8 i32Mul i32Add"
end

# 辞書 d の i 番めの組の場所から 8 を引いたもの
fn entry_t(d: Int, i: Int) -> Str
  ensures true
  example entry_t(d: 0, i: 2) == "localGet 0 localGet 2 i32 16 i32Mul i32Add"
do
  "localGet " ++ n2s(n: d) ++ " localGet " ++ n2s(n: i) ++ " i32 16 i32Mul i32Add"
end

# 長さ（局所変数 n）のリストを作り、局所変数 l に入れる。r513 は「R513 out of memory」の置き場所
fn new_list_t(r513: Int, n: Int, l: Int) -> Str
  ensures true
  example str_len(text: new_list_t(r513: 48, n: 1, l: 2)) > 0
do
  "localGet " ++ n2s(n: n) ++ " i32 134217728 i32GtU if EMPTY i32 " ++ n2s(n: r513) ++ " call $fail end localGet " ++ n2s(n: n) ++ " i32 8 i32Mul i32 8 i32Add call $alloc localTee " ++ n2s(n: l) ++ " localGet " ++ n2s(n: n) ++ " i32Store 0"
end

# 要素を n 個写す（どれも 8 バイト）
fn copy_t(dst: Int, dst_at: Str, src: Int, src_at: Str, n: Str) -> Str
  ensures true
  example copy_t(dst: 1, dst_at: "i32 0", src: 0, src_at: "i32 0", n: "localGet 2") == "localGet 1 i32 8 i32Add i32 0 i32 8 i32Mul i32Add localGet 0 i32 8 i32Add i32 0 i32 8 i32Mul i32Add localGet 2 i32 8 i32Mul memoryCopy"
do
  "localGet " ++ n2s(n: dst) ++ " i32 8 i32Add " ++ dst_at ++ " i32 8 i32Mul i32Add localGet " ++ n2s(n: src) ++ " i32 8 i32Add " ++ src_at ++ " i32 8 i32Mul i32Add " ++ n ++ " i32 8 i32Mul memoryCopy"
end

# 「R513 out of memory」の置き場所
fn r513_at(cg: Cg) -> At
  ensures true
  example at_at(a: r513_at(cg: cg_new())) == 48
do
  cg_str(cg: cg, text: "R513 out of memory")
end

# ---- メモリの欄（src/wasm.js の slot・loadAt・storeAt） ----

fn slot_of(p: Prog, cg: Cg, t: Ty, where: Node) -> At
  ensures true
  example at_at(a: slot_of(p: prog_empty(), cg: cg_new(), t: tk(k: "Int"), where: bare(kind: "x", text: "", kids: []))) == 126
do
  let v: Int = val_ty(t: t)
  if v == -1 then At(at: 0, cg: unsupported(cg: cg, what: "values of type " ++ type_str(t: t), n: where)) else At(at: v, cg: cg) end
end

fn load_at(p: Prog, cg: Cg, t: Ty, addr: List[Int], off: Int, where: Node) -> BC
  ensures true
  example bc_code(b: load_at(p: prog_empty(), cg: cg_new(), t: tk(k: "Int"), addr: [1], off: 8, where: bare(kind: "x", text: "", kids: []))) == [1, 41, 3, 8]
do
  let s: At = slot_of(p: p, cg: cg, t: t, where: where)
  when
    at_at(a: s) == 0 then BC(code: [], cg: at_cg(a: s))
    at_at(a: s) == 126 then BC(code: addr ++ pasm(p: p, text: "i64Load " ++ n2s(n: off)), cg: at_cg(a: s))
    else BC(code: addr ++ pasm(p: p, text: "i32Load " ++ n2s(n: off)), cg: at_cg(a: s))
  end
end

fn store_at(p: Prog, cg: Cg, t: Ty, addr: List[Int], value: List[Int], off: Int, where: Node) -> BC
  ensures true
  example bc_code(b: store_at(p: prog_empty(), cg: cg_new(), t: tk(k: "Unit"), addr: [1], value: [2], off: 8, where: bare(kind: "x", text: "", kids: []))) == [2]
do
  let s: At = slot_of(p: p, cg: cg, t: t, where: where)
  when
    at_at(a: s) == 0 then BC(code: value, cg: at_cg(a: s))
    at_at(a: s) == 126 then BC(code: concat(lists: [addr, value, pasm(p: p, text: "i64Store " ++ n2s(n: off))]), cg: at_cg(a: s))
    else BC(code: concat(lists: [addr, value, pasm(p: p, text: "i32Store " ++ n2s(n: off))]), cg: at_cg(a: s))
  end
end

# ---- 型と case ----

fn cvar_of(p: Prog, name: Str) -> CVar
  ensures true
  example cvar_index(v: cvar_of(p: prog_empty(), name: "x")) == 0
do
  match dict_get(dict: pg_variants(p: p), key: name)
    case Some(value: v) then v
    case None then CVar(decl: "", index: 0, node: bare(kind: "case", text: name, kids: []))
  end
end

fn cvar_node(v: CVar) -> Node
  ensures true
  example n_text(n: cvar_node(v: CVar(decl: "A", index: 0, node: bare(kind: "case", text: "B", kids: [])))) == "B"
do
  match v
    case CVar(decl: _, index: _, node: n) then n
  end
end

# 型 t の値の、case の欄の型（Option[T] の T を置きかえたもの）
fn field_types(p: Prog, t: Ty, vname: Str) -> List[Ty]
  ensures true
  example field_types(p: prog_empty(), t: tk(k: "Int"), vname: "x") == []
do
  let arg: Ty = if ty_args(t: t) == [] then Ty(k: "Var", name: "", args: []) else ty_arg0(t: t) end
  match fold(list: n_kids(n: cvar_node(v: cvar_of(p: p, name: vname))), init: FTs(subst: dict(keys: ["T"], values: [arg]), out: []), func: fty_step)
    case FTs(subst: _, out: o) then o
  end
end

type FTs
  case FTs(subst: Dict[Ty], out: List[Ty])
end

fn fty_step(acc: FTs, f: Node) -> FTs
  ensures true
  example fty_step(acc: FTs(subst: dict(keys: [], values: []), out: []), f: bare(kind: "field", text: "a", kids: [bare(kind: "t", text: "Int", kids: [])])) == FTs(subst: dict(keys: [], values: []), out: [tk(k: "Int")])
do
  match acc
    case FTs(subst: s, out: o) then FTs(subst: s, out: append(list: o, item: from_ast(n: first_kid(n: f), subst: s)))
  end
end

# case を作る（欄のコードはもう作ってある）。欄の無い case は1つだけ置いたものを使う
fn mk_data(p: Prog, cg: Cg, t: Ty, vname: Str, fields: List[List[Int]], where: Node) -> BC
  ensures true
  example bc_code(b: mk_data(p: prog_empty(), cg: cg_new(), t: tk(k: "Int"), vname: "None", fields: [], where: bare(kind: "x", text: "", kids: []))) == [65, 48]
do
  let v: CVar = cvar_of(p: p, name: vname)
  if fields == [] then tag_code(p: p, cg: cg, v: v) else
    let pl: At = cg_local(cg: cg, t: 127)
    let head: List[Int] = pasm(p: p, text: "i32 " ++ n2s(n: 8 + 8 * len(list: fields)) ++ " call $alloc localTee " ++ n2s(n: at_at(a: pl)) ++ " i32 " ++ n2s(n: cvar_index(v: v)) ++ " i32Store 0")
    match fold(list: fields, init: MD(p: p, fts: field_types(p: p, t: t, vname: vname), pl: at_at(a: pl), j: 0, where: where, b: BC(code: head, cg: at_cg(a: pl))), func: md_step)
      case MD(p: _, fts: _, pl: x, j: _, where: _, b: b) then bc_then(b: b, more: pasm(p: p, text: "localGet " ++ n2s(n: x)))
    end
  end
end

type MD
  case MD(p: Prog, fts: List[Ty], pl: Int, j: Int, where: Node, b: BC)
end

fn md_step(acc: MD, code: List[Int]) -> MD
  ensures true
  example bc_code(b: md_b(m: md_step(acc: MD(p: prog_empty(), fts: [tk(k: "Unit")], pl: 0, j: 0, where: bare(kind: "x", text: "", kids: []), b: BC(code: [], cg: cg_new())), code: [7]))) == [7]
do
  match acc
    case MD(p: p, fts: fts, pl: pl, j: j, where: w, b: b) then MD(p: p, fts: fts, pl: pl, j: j + 1, where: w, b: bc_after(before: bc_code(b: b), b: store_at(p: p, cg: bc_cg(b: b), t: ty_at(xs: fts, i: j), addr: pasm(p: p, text: "localGet " ++ n2s(n: pl)), value: code, off: 8 + 8 * j, where: w)))
  end
end

fn md_b(m: MD) -> BC
  ensures true
  example bc_code(b: md_b(m: MD(p: prog_empty(), fts: [], pl: 0, j: 0, where: bare(kind: "x", text: "", kids: []), b: BC(code: [1], cg: cg_new())))) == [1]
do
  match m
    case MD(p: _, fts: _, pl: _, j: _, where: _, b: b) then b
  end
end

# リストを書いたもの [a, b, ...]
fn list_code(p: Prog, cg: Cg, scope: Dict[Int], e: Node) -> BC
  ensures true
  example len(list: bc_code(b: list_code(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "list", text: "", kids: [])))) > 0
do
  let pl: At = cg_local(cg: cg, t: 127)
  let n: Int = len(list: n_kids(n: e))
  let head: List[Int] = pasm(p: p, text: "i32 " ++ n2s(n: 8 + 8 * n) ++ " call $alloc localTee " ++ n2s(n: at_at(a: pl)) ++ " i32 " ++ n2s(n: n) ++ " i32Store 0")
  match fold(list: n_kids(n: e), init: LI(p: p, scope: scope, elem: ty_arg0(t: ty_of(p: p, e: e)), pl: at_at(a: pl), j: 0, b: BC(code: head, cg: at_cg(a: pl))), func: li_step)
    case LI(p: _, scope: _, elem: _, pl: x, j: _, b: b) then bc_then(b: b, more: pasm(p: p, text: "localGet " ++ n2s(n: x)))
  end
end

type LI
  case LI(p: Prog, scope: Dict[Int], elem: Ty, pl: Int, j: Int, b: BC)
end

fn li_step(acc: LI, x: Node) -> LI
  ensures true
  example li_step(acc: LI(p: prog_empty(), scope: no_ints(), elem: tk(k: "Unit"), pl: 0, j: 0, b: BC(code: [], cg: cg_new())), x: bare(kind: "unit", text: "", kids: [])) == LI(p: prog_empty(), scope: no_ints(), elem: tk(k: "Unit"), pl: 0, j: 1, b: BC(code: [], cg: cg_new()))
do
  match acc
    case LI(p: p, scope: sc, elem: el, pl: pl, j: j, b: b) then LI(p: p, scope: sc, elem: el, pl: pl, j: j + 1, b: li_put(p: p, b: b, el: el, pl: pl, j: j, v: cg_expr(p: p, cg: bc_cg(b: b), scope: sc, e: x), x: x))
  end
end

fn li_put(p: Prog, b: BC, el: Ty, pl: Int, j: Int, v: BC, x: Node) -> BC
  ensures true
  example bc_code(b: li_put(p: prog_empty(), b: BC(code: [1], cg: cg_new()), el: tk(k: "Unit"), pl: 0, j: 0, v: BC(code: [], cg: cg_new()), x: bare(kind: "unit", text: "", kids: []))) == [1]
do
  bc_after(before: bc_code(b: b), b: store_at(p: p, cg: bc_cg(b: v), t: el, addr: pasm(p: p, text: "localGet " ++ n2s(n: pl)), value: bc_code(b: v), off: 8 + 8 * j, where: x))
end

# ---- match：case の番号を見て、欄を名前に入れてから値を作る ----

fn match_code(p: Prog, cg: Cg, scope: Dict[Int], e: Node, t: Int) -> BC
  ensures true
  example bc_code(b: match_code(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "match", text: "", kids: [bare(kind: "unit", text: "", kids: [])]), t: 0)) == [33, 0]
do
  let s: At = cg_local(cg: cg, t: 127)
  let subj: BC = cg_expr(p: p, cg: at_cg(a: s), scope: scope, e: first_kid(n: e))
  let arms: List[Node] = drop(list: n_kids(n: e), count: 1)
  let start: BC = BC(code: bc_code(b: subj) ++ pasm(p: p, text: "localSet " ++ n2s(n: at_at(a: s))), cg: bc_cg(b: subj))
  match fold(list: arms, init: MC(p: p, scope: scope, st: ty_of(p: p, e: first_kid(n: e)), s: at_at(a: s), t: t, left: len(list: arms), b: start), func: mc_step)
    case MC(p: _, scope: _, st: _, s: _, t: _, left: _, b: b) then bc_then(b: b, more: pasm(p: p, text: ends(n: len(list: arms) - 1)))
  end
end

fn ends(n: Int) -> Str
  ensures true
  example ends(n: 2) == "end end"
do
  join(parts: map(list: range(from: 0, to: n), func: end_word), by: " ")
end

fn end_word(i: Int) -> Str
  ensures true
  example end_word(i: 0) == "end"
do
  if i < 0 then "end" else "end" end
end

type MC
  case MC(p: Prog, scope: Dict[Int], st: Ty, s: Int, t: Int, left: Int, b: BC)
end

fn mc_step(acc: MC, a: Node) -> MC
  ensures true
  example mc_left(m: mc_step(acc: MC(p: prog_empty(), scope: no_ints(), st: tk(k: "Int"), s: 0, t: 0, left: 1, b: BC(code: [], cg: cg_new())), a: bare(kind: "arm", text: "A", kids: [bare(kind: "at", text: "A", kids: []), bare(kind: "unit", text: "", kids: [])]))) == 0
do
  match acc
    case MC(p: p, scope: sc, st: st, s: s, t: t, left: left, b: b) then MC(p: p, scope: sc, st: st, s: s, t: t, left: left - 1, b: mc_arm(p: p, b: b, scope: sc, st: st, s: s, t: t, last: left <= 1, a: a))
  end
end

fn mc_left(m: MC) -> Int
  ensures true
  example mc_left(m: MC(p: prog_empty(), scope: no_ints(), st: tk(k: "Int"), s: 0, t: 0, left: 3, b: BC(code: [], cg: cg_new()))) == 3
do
  match m
    case MC(p: _, scope: _, st: _, s: _, t: _, left: l, b: _) then l
  end
end

# 最後の case は調べずに作る。ほかは「番号が同じなら この case、違えば次」
fn mc_arm(p: Prog, b: BC, scope: Dict[Int], st: Ty, s: Int, t: Int, last: Bool, a: Node) -> BC
  ensures true
  example bc_code(b: mc_arm(p: prog_empty(), b: BC(code: [], cg: cg_new()), scope: no_ints(), st: tk(k: "Int"), s: 0, t: 0, last: true, a: bare(kind: "arm", text: "A", kids: [bare(kind: "at", text: "A", kids: []), bare(kind: "unit", text: "", kids: [])]))) == []
do
  let head: List[Int] = if last then [] else pasm(p: p, text: "localGet " ++ n2s(n: s) ++ " i32Load 0 i32 " ++ n2s(n: cvar_index(v: cvar_of(p: p, name: n_text(n: a)))) ++ " i32Eq if " ++ block_ty(t: t)) end
  let body: BC = arm_code(p: p, cg: bc_cg(b: b), scope: scope, st: st, s: s, a: a)
  BC(code: concat(lists: [bc_code(b: b), head, bc_code(b: body), if last then [] else pasm(p: p, text: "else") end]), cg: bc_cg(b: body))
end

fn arm_code(p: Prog, cg: Cg, scope: Dict[Int], st: Ty, s: Int, a: Node) -> BC
  ensures true
  example bc_code(b: arm_code(p: prog_empty(), cg: cg_new(), scope: no_ints(), st: tk(k: "Int"), s: 0, a: bare(kind: "arm", text: "A", kids: [bare(kind: "at", text: "A", kids: []), bare(kind: "unit", text: "", kids: [])]))) == []
do
  let binds: List[Node] = drop_last_node(xs: drop(list: n_kids(n: a), count: 1))
  let fields: List[Node] = n_kids(n: cvar_node(v: cvar_of(p: p, name: n_text(n: a))))
  match fold(list: binds, init: AB(p: p, fts: field_types(p: p, t: st, vname: n_text(n: a)), fields: fields, s: s, scope: scope, b: BC(code: [], cg: cg)), func: ab_step)
    case AB(p: _, fts: _, fields: _, s: _, scope: inner, b: b) then bc_after(before: bc_code(b: b), b: cg_expr(p: p, cg: bc_cg(b: b), scope: inner, e: last_kid(n: a)))
  end
end

type AB
  case AB(p: Prog, fts: List[Ty], fields: List[Node], s: Int, scope: Dict[Int], b: BC)
end

fn ab_step(acc: AB, bd: Node) -> AB
  ensures true
  example ab_step(acc: AB(p: prog_empty(), fts: [], fields: [], s: 0, scope: no_ints(), b: BC(code: [], cg: cg_new())), bd: bare(kind: "bind", text: "value _", kids: [])) == AB(p: prog_empty(), fts: [], fields: [], s: 0, scope: no_ints(), b: BC(code: [], cg: cg_new()))
do
  match acc
    case AB(p: p, fts: fts, fields: fs, s: s, scope: sc, b: b) then if word_of(text: n_text(n: bd), i: 1) == "_" then acc else bind_slot(acc: acc, bd: bd, j: field_index(fields: fs, name: word_of(text: n_text(n: bd), i: 0))) end
  end
end

fn bind_slot(acc: AB, bd: Node, j: Int) -> AB
  ensures true
  example bind_slot(acc: AB(p: prog_empty(), fts: [tk(k: "Unit")], fields: [], s: 0, scope: no_ints(), b: BC(code: [], cg: cg_new())), bd: bare(kind: "bind", text: "value v", kids: []), j: 0) == AB(p: prog_empty(), fts: [tk(k: "Unit")], fields: [], s: 0, scope: dict(keys: ["v"], values: [-1]), b: BC(code: [], cg: cg_new()))
do
  match acc
    case AB(p: p, fts: fts, fields: fs, s: s, scope: sc, b: b) then
      match slot_of(p: p, cg: bc_cg(b: b), t: ty_at(xs: fts, i: j), where: bd)
        case At(at: vt, cg: cg1) then if vt == 0 then AB(p: p, fts: fts, fields: fs, s: s, scope: dict_put(dict: sc, key: word_of(text: n_text(n: bd), i: 1), value: -1), b: BC(code: bc_code(b: b), cg: cg1)) else bind_load(acc: acc, bd: bd, j: j, idx: cg_local(cg: cg1, t: vt)) end
      end
  end
end

fn bind_load(acc: AB, bd: Node, j: Int, idx: At) -> AB
  ensures true
  example ab_scope(a: bind_load(acc: AB(p: prog_empty(), fts: [tk(k: "Int")], fields: [], s: 0, scope: no_ints(), b: BC(code: [], cg: cg_new())), bd: bare(kind: "bind", text: "value v", kids: []), j: 0, idx: At(at: 1, cg: cg_new()))) == dict(keys: ["v"], values: [1])
do
  match acc
    case AB(p: p, fts: fts, fields: fs, s: s, scope: sc, b: b) then AB(p: p, fts: fts, fields: fs, s: s, scope: dict_put(dict: sc, key: word_of(text: n_text(n: bd), i: 1), value: at_at(a: idx)), b: bc_then(b: bc_after(before: bc_code(b: b), b: load_at(p: p, cg: at_cg(a: idx), t: ty_at(xs: fts, i: j), addr: pasm(p: p, text: "localGet " ++ n2s(n: s)), off: 8 + 8 * j, where: bd)), more: pasm(p: p, text: "localSet " ++ n2s(n: at_at(a: idx)))))
  end
end

fn ab_scope(a: AB) -> Dict[Int]
  ensures true
  example ab_scope(a: AB(p: prog_empty(), fts: [], fields: [], s: 0, scope: no_ints(), b: BC(code: [], cg: cg_new()))) == no_ints()
do
  match a
    case AB(p: _, fts: _, fields: _, s: _, scope: sc, b: _) then sc
  end
end

# 空白で区切った i 番めの語（無ければ ""）
fn word_of(text: Str, i: Int) -> Str
  ensures true
  example word_of(text: "value v", i: 1) == "v"
  example word_of(text: "value", i: 3) == ""
do
  let ws: List[Str] = split(text: text, by: " ")
  if i >= 0 and i < len(list: ws) then get(list: ws, index: i) else "" end
end

# 名前 name の欄の番号（無ければ -1）
fn field_index(fields: List[Node], name: Str) -> Int
  ensures result >= -1
  example field_index(fields: [bare(kind: "field", text: "a", kids: []), bare(kind: "field", text: "b", kids: [])], name: "b") == 1
do
  match fold(list: fields, init: FI(name: name, i: 0, found: -1), func: fi_step)
    case FI(name: _, i: _, found: f) then f
  end
end

type FI
  case FI(name: Str, i: Int, found: Int)
end

fn fi_step(acc: FI, f: Node) -> FI
  ensures true
  example fi_step(acc: FI(name: "a", i: 0, found: -1), f: bare(kind: "field", text: "a", kids: [])) == FI(name: "a", i: 1, found: 0)
do
  match acc
    case FI(name: n, i: i, found: fd) then FI(name: n, i: i + 1, found: if fd < 0 and n_text(n: f) == n then i else fd end)
  end
end

# ---- 表示と比べる（型ごとの手伝いの関数） ----

fn show_list_fn(p: Prog, cg: Cg, t: Ty, where: Node) -> At
  ensures true
  example at_at(a: show_list_fn(p: prog_empty(), cg: cg_new(), t: t_list(of: tk(k: "Int")), where: bare(kind: "x", text: "", kids: []))) == 0
do
  let g: GenOpen = gen_open(p: p, cg: cg, key: "show " ++ type_str(t: t), params: [127], results: [127])
  if go_found(g: g) then At(at: go_at(g: g), cg: cg) else gen_close(g: g, body: show_list_body(p: p, cg: gen_locals(cg: go_cg(g: g), ts: i32s(n: 3)), t: t, where: where)) end
end

# 要素の文字を並びに集めてから join でつなぐ（局所変数 1 = 数・2 = i・3 = 並び）
fn show_list_body(p: Prog, cg: Cg, t: Ty, where: Node) -> BC
  ensures true
  example len(list: bc_code(b: show_list_body(p: prog_empty(), cg: cg_new(), t: t_list(of: tk(k: "Int")), where: bare(kind: "x", text: "", kids: [])))) > 0
do
  let r: At = r513_at(cg: cg)
  let ld: BC = load_at(p: p, cg: at_cg(a: r), t: ty_arg0(t: t), addr: pasm(p: p, text: elem_t(l: 0, i: 2)), off: 8, where: where)
  let sh: BC = show_code(p: p, cg: bc_cg(b: ld), t: ty_arg0(t: t), code: bc_code(b: ld), nested: true, where: where)
  let tail: BC = wrap_join(p: p, cg: bc_cg(b: sh), parts: 3, open: "[", close: "]")
  BC(code: concat(lists: [pasm(p: p, text: "localGet 0 i32Load 0 localSet 1 " ++ new_list_t(r513: at_at(a: r), n: 1, l: 3)), each_b(p: p, i: 2, n: 1, body: concat(lists: [pasm(p: p, text: elem_t(l: 3, i: 2)), bc_code(b: sh), pasm(p: p, text: "i32Store 8")])), bc_code(b: tail)]), cg: bc_cg(b: tail))
end

# open ＋ join(並び, ", ") ＋ close
fn wrap_join(p: Prog, cg: Cg, parts: Int, open: Str, close: Str) -> BC
  ensures true
  example len(list: bc_code(b: wrap_join(p: prog_empty(), cg: cg_new(), parts: 3, open: "[", close: "]"))) > 0
do
  let a: At = cg_str(cg: cg, text: open)
  let c: At = cg_str(cg: at_cg(a: a), text: ", ")
  let j: At = join_fn(p: p, cg: at_cg(a: c))
  let z: At = cg_str(cg: at_cg(a: j), text: close)
  BC(code: pasm(p: p, text: "i32 " ++ n2s(n: at_at(a: a)) ++ " localGet " ++ n2s(n: parts) ++ " i32 " ++ n2s(n: at_at(a: c)) ++ " call " ++ n2s(n: at_at(a: j)) ++ " call $concat i32 " ++ n2s(n: at_at(a: z)) ++ " call $concat"), cg: at_cg(a: z))
end

fn show_data_fn(p: Prog, cg: Cg, t: Ty, where: Node) -> At
  ensures true
  example at_at(a: show_data_fn(p: prog_empty(), cg: cg_new(), t: t_data(name: "A", args: []), where: bare(kind: "x", text: "", kids: []))) == 0
do
  let g: GenOpen = gen_open(p: p, cg: cg, key: "show " ++ type_str(t: t), params: [127], results: [127])
  if go_found(g: g) then At(at: go_at(g: g), cg: cg) else gen_close(g: g, body: bc_then(b: sd_b(s: fold(list: decl_cases(p: p, name: ty_name(t: t)), init: SD(p: p, t: t, where: where, b: BC(code: [], cg: gen_locals(cg: go_cg(g: g), ts: [127]))), func: sd_step)), more: pasm(p: p, text: "unreachable"))) end
end

# 型 name の case の木（書いた順）
fn decl_cases(p: Prog, name: Str) -> List[Node]
  ensures true
  example decl_cases(p: prog_empty(), name: "A") == []
do
  match dict_get(dict: pg_decls(p: p), key: name)
    case Some(value: d) then n_kids(n: d)
    case None then []
  end
end

type SD
  case SD(p: Prog, t: Ty, where: Node, b: BC)
end

fn sd_b(s: SD) -> BC
  ensures true
  example bc_code(b: sd_b(s: SD(p: prog_empty(), t: tk(k: "Int"), where: bare(kind: "x", text: "", kids: []), b: BC(code: [1], cg: cg_new())))) == [1]
do
  match s
    case SD(p: _, t: _, where: _, b: b) then b
  end
end

# case ごとに：番号が同じなら「名前(欄: 値, ...)」を作って返す（局所変数 1 に足していく）
fn sd_step(acc: SD, v: Node) -> SD
  ensures true
  example len(list: bc_code(b: sd_b(s: sd_step(acc: SD(p: prog_empty(), t: tk(k: "Int"), where: bare(kind: "x", text: "", kids: []), b: BC(code: [], cg: cg_new())), v: bare(kind: "case", text: "A", kids: []))))) > 0
do
  match acc
    case SD(p: p, t: t, where: w, b: b) then SD(p: p, t: t, where: w, b: bc_after(before: bc_code(b: b), b: sd_case(p: p, cg: bc_cg(b: b), t: t, where: w, v: v)))
  end
end

fn sd_case(p: Prog, cg: Cg, t: Ty, where: Node, v: Node) -> BC
  ensures true
  example len(list: bc_code(b: sd_case(p: prog_empty(), cg: cg_new(), t: tk(k: "Int"), where: bare(kind: "x", text: "", kids: []), v: bare(kind: "case", text: "A", kids: [])))) > 0
do
  let head: List[Int] = pasm(p: p, text: "localGet 0 i32Load 0 i32 " ++ n2s(n: cvar_index(v: cvar_of(p: p, name: n_text(n: v)))) ++ " i32Eq if EMPTY")
  if n_kids(n: v) == [] then
    let s: At = cg_str(cg: cg, text: n_text(n: v))
    BC(code: head ++ pasm(p: p, text: "i32 " ++ n2s(n: at_at(a: s)) ++ " return end"), cg: at_cg(a: s))
  else
    let s: At = cg_str(cg: cg, text: n_text(n: v) ++ "(")
    let fs: SF = fold(list: n_kids(n: v), init: SF(p: p, fts: field_types(p: p, t: t, vname: n_text(n: v)), where: where, j: 0, b: BC(code: head ++ pasm(p: p, text: "i32 " ++ n2s(n: at_at(a: s)) ++ " localSet 1"), cg: at_cg(a: s))), func: sf_step)
    let c: At = cg_str(cg: bc_cg(b: sf_b(s: fs)), text: ")")
    BC(code: bc_code(b: sf_b(s: fs)) ++ pasm(p: p, text: "localGet 1 i32 " ++ n2s(n: at_at(a: c)) ++ " call $concat localSet 1 localGet 1 return end"), cg: at_cg(a: c))
  end
end

type SF
  case SF(p: Prog, fts: List[Ty], where: Node, j: Int, b: BC)
end

fn sf_b(s: SF) -> BC
  ensures true
  example bc_code(b: sf_b(s: SF(p: prog_empty(), fts: [], where: bare(kind: "x", text: "", kids: []), j: 0, b: BC(code: [1], cg: cg_new())))) == [1]
do
  match s
    case SF(p: _, fts: _, where: _, j: _, b: b) then b
  end
end

fn sf_step(acc: SF, f: Node) -> SF
  ensures true
  example len(list: bc_code(b: sf_b(s: sf_step(acc: SF(p: prog_empty(), fts: [tk(k: "Int")], where: bare(kind: "x", text: "", kids: []), j: 0, b: BC(code: [], cg: cg_new())), f: bare(kind: "field", text: "a", kids: []))))) > 0
do
  match acc
    case SF(p: p, fts: fts, where: w, j: j, b: b) then SF(p: p, fts: fts, where: w, j: j + 1, b: bc_after(before: bc_code(b: b), b: sf_field(p: p, cg: bc_cg(b: b), t: ty_at(xs: fts, i: j), where: w, j: j, name: n_text(n: f))))
  end
end

fn sf_field(p: Prog, cg: Cg, t: Ty, where: Node, j: Int, name: Str) -> BC
  ensures true
  example len(list: bc_code(b: sf_field(p: prog_empty(), cg: cg_new(), t: tk(k: "Int"), where: bare(kind: "x", text: "", kids: []), j: 0, name: "a"))) > 0
do
  let s: At = cg_str(cg: cg, text: if j > 0 then ", " ++ name ++ ": " else name ++ ": " end)
  let ld: BC = load_at(p: p, cg: at_cg(a: s), t: t, addr: pasm(p: p, text: "localGet 0"), off: 8 + 8 * j, where: where)
  let sh: BC = show_code(p: p, cg: bc_cg(b: ld), t: t, code: bc_code(b: ld), nested: true, where: where)
  BC(code: concat(lists: [pasm(p: p, text: "localGet 1 i32 " ++ n2s(n: at_at(a: s)) ++ " call $concat localSet 1 localGet 1"), bc_code(b: sh), pasm(p: p, text: "call $concat localSet 1")]), cg: bc_cg(b: sh))
end

fn show_dict_fn(p: Prog, cg: Cg, t: Ty, where: Node) -> At
  ensures true
  example at_at(a: show_dict_fn(p: prog_empty(), cg: cg_new(), t: Ty(k: "Dict", name: "", args: [tk(k: "Int")]), where: bare(kind: "x", text: "", kids: []))) == 0
do
  let g: GenOpen = gen_open(p: p, cg: cg, key: "show " ++ type_str(t: t), params: [127], results: [127])
  if go_found(g: g) then At(at: go_at(g: g), cg: cg) else gen_close(g: g, body: show_dict_body(p: p, cg: gen_locals(cg: go_cg(g: g), ts: i32s(n: 3)), t: t, where: where)) end
end

# 「"鍵": 値」を並びに集めて join（局所変数 1 = 数・2 = i・3 = 並び）
fn show_dict_body(p: Prog, cg: Cg, t: Ty, where: Node) -> BC
  ensures true
  example len(list: bc_code(b: show_dict_body(p: prog_empty(), cg: cg_new(), t: Ty(k: "Dict", name: "", args: [tk(k: "Int")]), where: bare(kind: "x", text: "", kids: [])))) > 0
do
  let r: At = r513_at(cg: cg)
  let q: At = quote_fn(p: p, cg: at_cg(a: r))
  let colon: At = cg_str(cg: at_cg(a: q), text: ": ")
  let ld: BC = load_at(p: p, cg: at_cg(a: colon), t: ty_arg0(t: t), addr: pasm(p: p, text: entry_t(d: 0, i: 2)), off: 16, where: where)
  let sh: BC = show_code(p: p, cg: bc_cg(b: ld), t: ty_arg0(t: t), code: bc_code(b: ld), nested: true, where: where)
  let tail: BC = wrap_join(p: p, cg: bc_cg(b: sh), parts: 3, open: "{", close: "}")
  let one: List[Int] = concat(lists: [pasm(p: p, text: elem_t(l: 3, i: 2) ++ " " ++ entry_t(d: 0, i: 2) ++ " i32Load 8 call " ++ n2s(n: at_at(a: q)) ++ " i32 " ++ n2s(n: at_at(a: colon)) ++ " call $concat"), bc_code(b: sh), pasm(p: p, text: "call $concat i32Store 8")])
  BC(code: concat(lists: [pasm(p: p, text: "localGet 0 i32Load 0 localSet 1 " ++ new_list_t(r513: at_at(a: r), n: 1, l: 3)), each_b(p: p, i: 2, n: 1, body: one), bc_code(b: tail)]), cg: bc_cg(b: tail))
end

fn eq_list_fn(p: Prog, cg: Cg, t: Ty, where: Node) -> At
  ensures true
  example at_at(a: eq_list_fn(p: prog_empty(), cg: cg_new(), t: t_list(of: tk(k: "Int")), where: bare(kind: "x", text: "", kids: []))) == 0
do
  let g: GenOpen = gen_open(p: p, cg: cg, key: "eq " ++ type_str(t: t), params: [127, 127], results: [127])
  if go_found(g: g) then At(at: go_at(g: g), cg: cg) else gen_close(g: g, body: eq_list_body(p: p, cg: gen_locals(cg: go_cg(g: g), ts: i32s(n: 2)), t: t, where: where)) end
end

# 長さが違えば偽。要素を順に比べる（局所変数 2 = 数・3 = i）
fn eq_list_body(p: Prog, cg: Cg, t: Ty, where: Node) -> BC
  ensures true
  example len(list: bc_code(b: eq_list_body(p: prog_empty(), cg: cg_new(), t: t_list(of: tk(k: "Int")), where: bare(kind: "x", text: "", kids: [])))) > 0
do
  let el: Ty = ty_arg0(t: t)
  let la: BC = load_at(p: p, cg: cg, t: el, addr: pasm(p: p, text: elem_t(l: 0, i: 3)), off: 8, where: where)
  let lb: BC = load_at(p: p, cg: bc_cg(b: la), t: el, addr: pasm(p: p, text: elem_t(l: 1, i: 3)), off: 8, where: where)
  let eq: BC = eq_code(p: p, cg: bc_cg(b: lb), t: el, a: bc_code(b: la), b: bc_code(b: lb), where: where)
  BC(code: concat(lists: [pasm(p: p, text: "localGet 0 i32Load 0 localTee 2 localGet 1 i32Load 0 i32Ne if EMPTY i32 0 return end"), each_b(p: p, i: 3, n: 2, body: bc_code(b: eq) ++ pasm(p: p, text: "i32Eqz if EMPTY i32 0 return end")), pasm(p: p, text: "i32 1")]), cg: bc_cg(b: eq))
end

fn eq_dict_fn(p: Prog, cg: Cg, t: Ty, where: Node) -> At
  ensures true
  example at_at(a: eq_dict_fn(p: prog_empty(), cg: cg_new(), t: Ty(k: "Dict", name: "", args: [tk(k: "Int")]), where: bare(kind: "x", text: "", kids: []))) == 0
do
  let g: GenOpen = gen_open(p: p, cg: cg, key: "eq " ++ type_str(t: t), params: [127, 127], results: [127])
  if go_found(g: g) then At(at: go_at(g: g), cg: cg) else gen_close(g: g, body: eq_dict_body(p: p, cg: gen_locals(cg: go_cg(g: g), ts: i32s(n: 2)), t: t, where: where)) end
end

# 数が違えば偽。組を順に、鍵と値を比べる（局所変数 2 = 数・3 = i）
fn eq_dict_body(p: Prog, cg: Cg, t: Ty, where: Node) -> BC
  ensures true
  example len(list: bc_code(b: eq_dict_body(p: prog_empty(), cg: cg_new(), t: Ty(k: "Dict", name: "", args: [tk(k: "Int")]), where: bare(kind: "x", text: "", kids: [])))) > 0
do
  let el: Ty = ty_arg0(t: t)
  let la: BC = load_at(p: p, cg: cg, t: el, addr: pasm(p: p, text: entry_t(d: 0, i: 3)), off: 16, where: where)
  let lb: BC = load_at(p: p, cg: bc_cg(b: la), t: el, addr: pasm(p: p, text: entry_t(d: 1, i: 3)), off: 16, where: where)
  let eq: BC = eq_code(p: p, cg: bc_cg(b: lb), t: el, a: bc_code(b: la), b: bc_code(b: lb), where: where)
  let no: Str = " i32Eqz if EMPTY i32 0 return end "
  BC(code: concat(lists: [pasm(p: p, text: "localGet 0 i32Load 0 localTee 2 localGet 1 i32Load 0 i32Ne if EMPTY i32 0 return end"), each_b(p: p, i: 3, n: 2, body: concat(lists: [pasm(p: p, text: entry_t(d: 0, i: 3) ++ " i32Load 8 " ++ entry_t(d: 1, i: 3) ++ " i32Load 8 call $streq" ++ no), bc_code(b: eq), pasm(p: p, text: no)])), pasm(p: p, text: "i32 1")]), cg: bc_cg(b: eq))
end

fn eq_data_fn(p: Prog, cg: Cg, t: Ty, where: Node) -> At
  ensures true
  example at_at(a: eq_data_fn(p: prog_empty(), cg: cg_new(), t: t_data(name: "A", args: []), where: bare(kind: "x", text: "", kids: []))) == 0
do
  let g: GenOpen = gen_open(p: p, cg: cg, key: "eq " ++ type_str(t: t), params: [127, 127], results: [127])
  if go_found(g: g) then At(at: go_at(g: g), cg: cg) else gen_close(g: g, body: bc_then(b: sd_b(s: fold(list: decl_cases(p: p, name: ty_name(t: t)), init: SD(p: p, t: t, where: where, b: BC(code: pasm(p: p, text: "localGet 0 i32Load 0 localGet 1 i32Load 0 i32Ne if EMPTY i32 0 return end"), cg: go_cg(g: g))), func: ed_step)), more: pasm(p: p, text: "i32 1"))) end
end

# 欄のある case ごとに：番号が同じなら、欄を順に比べる
fn ed_step(acc: SD, v: Node) -> SD
  ensures true
  example ed_step(acc: SD(p: prog_empty(), t: tk(k: "Int"), where: bare(kind: "x", text: "", kids: []), b: BC(code: [], cg: cg_new())), v: bare(kind: "case", text: "A", kids: [])) == SD(p: prog_empty(), t: tk(k: "Int"), where: bare(kind: "x", text: "", kids: []), b: BC(code: [], cg: cg_new()))
do
  match acc
    case SD(p: p, t: t, where: w, b: b) then if n_kids(n: v) == [] then acc else SD(p: p, t: t, where: w, b: bc_then(b: sf_b(s: fold(list: field_types(p: p, t: t, vname: n_text(n: v)), init: SF(p: p, fts: [], where: w, j: 0, b: bc_then(b: b, more: pasm(p: p, text: "localGet 0 i32Load 0 i32 " ++ n2s(n: cvar_index(v: cvar_of(p: p, name: n_text(n: v)))) ++ " i32Eq if EMPTY"))), func: ef_step)), more: pasm(p: p, text: "end"))) end
  end
end

fn ef_step(acc: SF, ft: Ty) -> SF
  ensures true
  example len(list: bc_code(b: sf_b(s: ef_step(acc: SF(p: prog_empty(), fts: [], where: bare(kind: "x", text: "", kids: []), j: 0, b: BC(code: [], cg: cg_new())), ft: tk(k: "Int"))))) > 0
do
  match acc
    case SF(p: p, fts: fts, where: w, j: j, b: b) then SF(p: p, fts: fts, where: w, j: j + 1, b: bc_after(before: bc_code(b: b), b: ef_field(p: p, cg: bc_cg(b: b), t: ft, where: w, j: j)))
  end
end

fn ef_field(p: Prog, cg: Cg, t: Ty, where: Node, j: Int) -> BC
  ensures true
  example len(list: bc_code(b: ef_field(p: prog_empty(), cg: cg_new(), t: tk(k: "Int"), where: bare(kind: "x", text: "", kids: []), j: 0))) > 0
do
  let la: BC = load_at(p: p, cg: cg, t: t, addr: pasm(p: p, text: "localGet 0"), off: 8 + 8 * j, where: where)
  let lb: BC = load_at(p: p, cg: bc_cg(b: la), t: t, addr: pasm(p: p, text: "localGet 1"), off: 8 + 8 * j, where: where)
  bc_then(b: eq_code(p: p, cg: bc_cg(b: lb), t: t, a: bc_code(b: la), b: bc_code(b: lb), where: where), more: pasm(p: p, text: "i32Eqz if EMPTY i32 0 return end"))
end

# ---- 中身の決まった手伝いの関数（文字で書く） ----

# JSON.stringify と同じ形で "" でくくる（局所変数 1 = 長さ・2 = i・3 = 結果・4 = 書く場所・5 = バイト）
fn quote_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: quote_fn(p: prog_empty(), cg: cg_new())) == 0
do
  let g: GenOpen = gen_open(p: p, cg: cg, key: "quote", params: [127], results: [127])
  if go_found(g: g) then At(at: go_at(g: g), cg: cg) else gen_close(g: g, body: BC(code: pasm(p: p, text: quote_text()), cg: gen_locals(cg: go_cg(g: g), ts: i32s(n: 5)))) end
end

fn q_put(code: Str) -> Str
  ensures true
  example q_put(code: "i32 34") == "localGet 4 i32 34 i32Store8 0 localGet 4 i32 1 i32Add localSet 4"
do
  "localGet 4 " ++ code ++ " i32Store8 0 localGet 4 i32 1 i32Add localSet 4"
end

fn q_hex(code: Str) -> Str
  ensures true
  example str_len(text: q_hex(code: "localGet 5")) > 0
do
  code ++ " localTee 5 i32 10 i32LtU if I32 localGet 5 i32 48 i32Add else localGet 5 i32 87 i32Add end"
end

fn q_esc(c: Int, ch: Int) -> Str
  ensures true
  example str_len(text: q_esc(c: 8, ch: 98)) > 0
do
  "localGet 5 i32 " ++ n2s(n: c) ++ " i32Eq if EMPTY " ++ q_put(code: "i32 92") ++ " " ++ q_put(code: "i32 " ++ n2s(n: ch)) ++ " br 2 end"
end

fn quote_text() -> Str
  ensures str_len(text: result) > 0
  example str_len(text: quote_text()) > 100
do
  let byte: Str = "localGet 0 localGet 2 i32Add i32Load8u 4 localSet 5"
  let one: Str = join(parts: ["block EMPTY", byte, "localGet 5 i32 34 i32Eq if EMPTY", q_put(code: "i32 92"), q_put(code: "i32 34"), "br 1 end", "localGet 5 i32 92 i32Eq if EMPTY", q_put(code: "i32 92"), q_put(code: "i32 92"), "br 1 end", "localGet 5 i32 32 i32GeU if EMPTY", q_put(code: "localGet 5"), "br 1 end", "block EMPTY", q_esc(c: 8, ch: 98), q_esc(c: 9, ch: 116), q_esc(c: 10, ch: 110), q_esc(c: 12, ch: 102), q_esc(c: 13, ch: 114), q_put(code: "i32 92"), q_put(code: "i32 117"), q_put(code: "i32 48"), q_put(code: "i32 48"), byte, q_put(code: q_hex(code: "localGet 5 i32 4 i32ShrU")), byte, q_put(code: q_hex(code: "localGet 5 i32 15 i32And")), "end end"], by: " ")
  join(parts: ["localGet 0 i32Load 0 localSet 1", "localGet 1 i32 6 i32Mul i32 6 i32Add call $alloc localSet 3", "localGet 3 i32 4 i32Add localSet 4", q_put(code: "i32 34"), each_t(i: 2, n: 1, body: one), q_put(code: "i32 34"), "localGet 3 localGet 4 localGet 3 i32Sub i32 4 i32Sub i32Store 0 localGet 3"], by: " ")
end

# join(並び, 区切り)：長さを先に数えて1回で確保する（局所変数 2 = 数・3 = i・4 = 全体・5 = 結果・6 = 書く場所・7 = 一切れ）
fn join_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: join_fn(p: prog_empty(), cg: cg_new())) == 0
do
  let g: GenOpen = gen_open(p: p, cg: cg, key: "join", params: [127, 127], results: [127])
  if go_found(g: g) then At(at: go_at(g: g), cg: cg) else gen_close(g: g, body: BC(code: pasm(p: p, text: join_text()), cg: gen_locals(cg: go_cg(g: g), ts: i32s(n: 6)))) end
end

fn j_put(code: Str) -> Str
  ensures true
  example str_len(text: j_put(code: "localGet 1")) > 0
do
  code ++ " localSet 7 localGet 6 localGet 7 i32 4 i32Add localGet 7 i32Load 0 memoryCopy localGet 6 localGet 7 i32Load 0 i32Add localSet 6"
end

fn join_text() -> Str
  ensures str_len(text: result) > 0
  example str_len(text: join_text()) > 100
do
  join(parts: ["localGet 0 i32Load 0 localSet 2 i32 0 localSet 4", each_t(i: 3, n: 2, body: "localGet 3 if EMPTY localGet 4 localGet 1 i32Load 0 i32Add localSet 4 end localGet 4 " ++ elem_t(l: 0, i: 3) ++ " i32Load 8 i32Load 0 i32Add localSet 4"), "localGet 4 i32 4 i32Add call $alloc localTee 5 localGet 4 i32Store 0", "localGet 5 i32 4 i32Add localSet 6", each_t(i: 3, n: 2, body: "localGet 3 if EMPTY " ++ j_put(code: "localGet 1") ++ " end " ++ j_put(code: elem_t(l: 0, i: 3) ++ " i32Load 8")), "localGet 5"], by: " ")
end

# リスト ++ リスト（局所変数 2 = 長さ・3 = 結果）
fn list_cat_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: list_cat_fn(p: prog_empty(), cg: cg_new())) == 0
do
  let g: GenOpen = gen_open(p: p, cg: cg, key: "list ++", params: [127, 127], results: [127])
  if go_found(g: g) then At(at: go_at(g: g), cg: cg) else list_cat_close(p: p, g: g, r: r513_at(cg: gen_locals(cg: go_cg(g: g), ts: i32s(n: 2)))) end
end

fn list_cat_close(p: Prog, g: GenOpen, r: At) -> At
  ensures true
  example at_at(a: list_cat_close(p: prog_empty(), g: gen_open(p: prog_empty(), cg: cg_new(), key: "k", params: [], results: []), r: At(at: 48, cg: cg_new()))) == 0
do
  gen_close(g: g, body: BC(code: pasm(p: p, text: join(parts: ["localGet 0 i32Load 0 localGet 1 i32Load 0 i32Add localSet 2", new_list_t(r513: at_at(a: r), n: 2, l: 3), copy_t(dst: 3, dst_at: "i32 0", src: 0, src_at: "i32 0", n: "localGet 0 i32Load 0"), copy_t(dst: 3, dst_at: "localGet 0 i32Load 0", src: 1, src_at: "i32 0", n: "localGet 1 i32Load 0"), "localGet 3"], by: " ")), cg: at_cg(a: r)))
end

# concat(lists:)：長さを先に足して1回だけ確保する（局所変数 1 = 数・2 = i・3 = 全体・4 = 結果・5 = 書いた数・6 = 中のリスト）
fn concat_lists_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: concat_lists_fn(p: prog_empty(), cg: cg_new())) == 0
do
  let g: GenOpen = gen_open(p: p, cg: cg, key: "concat lists", params: [127], results: [127])
  if go_found(g: g) then At(at: go_at(g: g), cg: cg) else concat_lists_close(p: p, g: g, r: r513_at(cg: gen_locals(cg: go_cg(g: g), ts: i32s(n: 6)))) end
end

fn concat_lists_close(p: Prog, g: GenOpen, r: At) -> At
  ensures true
  example at_at(a: concat_lists_close(p: prog_empty(), g: gen_open(p: prog_empty(), cg: cg_new(), key: "k", params: [], results: []), r: At(at: 48, cg: cg_new()))) == 0
do
  gen_close(g: g, body: BC(code: pasm(p: p, text: join(parts: ["localGet 0 i32Load 0 localSet 1 i32 0 localSet 3", each_t(i: 2, n: 1, body: "localGet 3 " ++ elem_t(l: 0, i: 2) ++ " i32Load 8 i32Load 0 i32Add localSet 3"), new_list_t(r513: at_at(a: r), n: 3, l: 4), "i32 0 localSet 5", each_t(i: 2, n: 1, body: elem_t(l: 0, i: 2) ++ " i32Load 8 localSet 6 " ++ copy_t(dst: 4, dst_at: "localGet 5", src: 6, src_at: "i32 0", n: "localGet 6 i32Load 0") ++ " localGet 5 localGet 6 i32Load 0 i32Add localSet 5"), "localGet 4"], by: " ")), cg: at_cg(a: r)))
end

# sort：下から組み上げるマージソート（局所変数 1 = 数・2 = a・3 = b・4 = 幅・5 = lo・6 = mid・7 = hi・8 = i・9 = j・10 = k・11 = 左から取るか）
fn sort_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: sort_fn(p: prog_empty(), cg: cg_new())) == 0
do
  let g: GenOpen = gen_open(p: p, cg: cg, key: "sort", params: [127], results: [127])
  if go_found(g: g) then At(at: go_at(g: g), cg: cg) else sort_close(p: p, g: g, r: r513_at(cg: gen_locals(cg: go_cg(g: g), ts: i32s(n: 11)))) end
end

fn s_min(x: Str, y: Str) -> Str
  ensures true
  example s_min(x: "a", y: "b") == "a b a b i32LtU select"
do
  x ++ " " ++ y ++ " " ++ x ++ " " ++ y ++ " i32LtU select"
end

fn s_inc(v: Int) -> Str
  ensures true
  example s_inc(v: 8) == "localGet 8 i32 1 i32Add localSet 8"
do
  "localGet " ++ n2s(n: v) ++ " i32 1 i32Add localSet " ++ n2s(n: v)
end

fn sort_close(p: Prog, g: GenOpen, r: At) -> At
  ensures true
  example at_at(a: sort_close(p: prog_empty(), g: gen_open(p: prog_empty(), cg: cg_new(), key: "k", params: [], results: []), r: At(at: 48, cg: cg_new()))) == 0
do
  let r5: Int = at_at(a: r)
  let merge: Str = join(parts: [
  "localGet 5 localSet 8 localGet 6 localSet 9 localGet 5 localSet 10 block EMPTY loop EMPTY localGet 10 localGet 7 i32GeU brIf 1",
  "localGet 9 localGet 7 i32GeU localGet 8 localGet 6 i32LtU if I32", elem_t(l: 2, i: 8), "i64Load 8", elem_t(l: 2, i: 9), "i64Load 8 i64LeS else i32 0 end",
  "i32Or localGet 8 localGet 6 i32LtU i32And localSet 11", elem_t(l: 3, i: 10),
  "localGet 11 if I64", elem_t(l: 2, i: 8), "i64Load 8", s_inc(v: 8), "else", elem_t(l: 2, i: 9), "i64Load 8", s_inc(v: 9), "end i64Store 8", s_inc(v: 10),
  "br 0 end end"
  ], by: " ")
  gen_close(g: g, body: BC(code: pasm(p: p, text: join(parts: [
  "localGet 0 i32Load 0 localSet 1", new_list_t(r513: r5, n: 1, l: 2), copy_t(dst: 2, dst_at: "i32 0", src: 0, src_at: "i32 0", n: "localGet 1"), new_list_t(r513: r5, n: 1, l: 3),
  "i32 1 localSet 4 block EMPTY loop EMPTY localGet 4 localGet 1 i32GeU brIf 1 i32 0 localSet 5 block EMPTY loop EMPTY localGet 5 localGet 1 i32GeU brIf 1",
  s_min(x: "localGet 5 localGet 4 i32Add", y: "localGet 1"), "localSet 6", s_min(x: "localGet 6 localGet 4 i32Add", y: "localGet 1"), "localSet 7",
  merge, "localGet 7 localSet 5 br 0 end end", copy_t(dst: 2, dst_at: "i32 0", src: 3, src_at: "i32 0", n: "localGet 1"), "localGet 4 i32 1 i32Shl localSet 4 br 0 end end localGet 2"
  ], by: " ")), cg: at_cg(a: r)))
end

# ---- リストの組み込み（src/wasm.js の listBuiltin） ----
# どれも始めに局所変数 L（リスト）・n（長さ）・i を取り、list: があればそれを先に作る（JS と同じ順。len と sort は list: をもう一度作る）

type LB
  case LB(p: Prog, scope: Dict[Int], e: Node, el: Ty, l: Int, n: Int, i: Int, set: List[Int])
end

fn list_builtin(p: Prog, cg: Cg, scope: Dict[Int], e: Node) -> BC
  ensures true
  example len(list: bc_code(b: list_builtin(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "call", text: "len", kids: [bare(kind: "arg", text: "list", kids: [bare(kind: "list", text: "", kids: [])])])))) > 0
do
  let lv: Node = arg_value(e: e, name: "list")
  let l: At = cg_local(cg: cg, t: 127)
  let n: At = cg_local(cg: at_cg(a: l), t: 127)
  let i: At = cg_local(cg: at_cg(a: n), t: 127)
  let set: BC = if n_kind(n: lv) == "none" then BC(code: [], cg: at_cg(a: i)) else bc_then(b: cg_expr(p: p, cg: at_cg(a: i), scope: scope, e: lv), more: pasm(p: p, text: "localTee " ++ n2s(n: at_at(a: l)) ++ " i32Load 0 localSet " ++ n2s(n: at_at(a: n)))) end
  lb_go(b: LB(p: p, scope: scope, e: e, el: ty_arg0(t: ty_of(p: p, e: lv)), l: at_at(a: l), n: at_at(a: n), i: at_at(a: i), set: bc_code(b: set)), cg: bc_cg(b: set))
end

fn lb_go(b: LB, cg: Cg) -> BC
  ensures true
  example bc_code(b: lb_go(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "nope", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new())) == []
do
  let name: Str = n_text(n: lb_e(b: b))
  when
    name == "len" then bc_then(b: lb_arg(b: b, cg: cg, name: "list"), more: pasm(p: lb_p(b: b), text: "i32Load 0 i64ExtendI32U"))
    name == "get" or name == "at" then lb_get(b: b, ix: cg_local(cg: cg, t: 126))
    name == "range" then lb_range(b: b, cg: cg)
    name == "append" then lb_append(b: b, cg: cg)
    name == "concat" then lb_call(b: b, a: lb_arg(b: b, cg: cg, name: "lists"), f: "concat lists")
    name == "map" then lb_map(b: b, pl: cg_local(cg: cg, t: 127))
    name == "filter" then lb_filter(b: b, cg: cg)
    name == "fold" then lb_fold(b: b, cg: cg)
    name == "find" or name == "any" or name == "all" then lb_find(b: b, cg: cg)
    name == "reverse" then lb_reverse(b: b, pl: cg_local(cg: cg, t: 127))
    name == "take" or name == "drop" then lb_take(b: b, cg: cg)
    name == "sort" then lb_call(b: b, a: lb_arg(b: b, cg: cg, name: "list"), f: "sort")
    name == "sum" then lb_sum(b: b, acc: cg_local(cg: cg, t: 126))
    name == "max" or name == "min" then lb_max(b: b, cg: cg)
    else BC(code: [], cg: unsupported(cg: cg, what: "the built-in function " ++ name, n: lb_e(b: b)))
  end
end

fn lb_p(b: LB) -> Prog
  ensures true
  example lb_p(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: [])) == prog_empty()
do
  match b
    case LB(p: p, scope: _, e: _, el: _, l: _, n: _, i: _, set: _) then p
  end
end

fn lb_e(b: LB) -> Node
  ensures true
  example n_kind(n: lb_e(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []))) == "x"
do
  match b
    case LB(p: _, scope: _, e: e, el: _, l: _, n: _, i: _, set: _) then e
  end
end

fn lb_el(b: LB) -> Ty
  ensures true
  example lb_el(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: [])) == tk(k: "Int")
do
  match b
    case LB(p: _, scope: _, e: _, el: el, l: _, n: _, i: _, set: _) then el
  end
end

fn lb_l(b: LB) -> Int
  ensures true
  example lb_l(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: [])) == 0
do
  match b
    case LB(p: _, scope: _, e: _, el: _, l: l, n: _, i: _, set: _) then l
  end
end

fn lb_n(b: LB) -> Int
  ensures true
  example lb_n(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: [])) == 1
do
  match b
    case LB(p: _, scope: _, e: _, el: _, l: _, n: n, i: _, set: _) then n
  end
end

fn lb_i(b: LB) -> Int
  ensures true
  example lb_i(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: [])) == 2
do
  match b
    case LB(p: _, scope: _, e: _, el: _, l: _, n: _, i: i, set: _) then i
  end
end

fn lb_set(b: LB) -> List[Int]
  ensures true
  example lb_set(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: [5])) == [5]
do
  match b
    case LB(p: _, scope: _, e: _, el: _, l: _, n: _, i: _, set: s) then s
  end
end

fn lb_arg(b: LB, cg: Cg, name: Str) -> BC
  ensures true
  example bc_code(b: lb_arg(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "f", kids: [bare(kind: "arg", text: "x", kids: [bare(kind: "int", text: "1", kids: [])])]), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new(), name: "x")) == [66, 1]
do
  match b
    case LB(p: p, scope: sc, e: e, el: _, l: _, n: _, i: _, set: _) then cg_expr(p: p, cg: cg, scope: sc, e: arg_value(e: e, name: name))
  end
end

# リストの i 番めの要素を読む
fn lb_item(b: LB, cg: Cg) -> BC
  ensures true
  example bc_code(b: lb_item(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), el: tk(k: "Unit"), l: 0, n: 1, i: 2, set: []), cg: cg_new())) == []
do
  load_at(p: lb_p(b: b), cg: cg, t: lb_el(b: b), addr: pasm(p: lb_p(b: b), text: elem_t(l: lb_l(b: b), i: lb_i(b: b))), off: 8, where: lb_e(b: b))
end

# func: に渡した関数を呼ぶ（いちばん外の関数の名前だけ）
fn lb_fn(b: LB, cg: Cg) -> BC
  ensures true
  example bc_code(b: lb_fn(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "map", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new())) == []
do
  let v: Node = arg_value(e: lb_e(b: b), name: "func")
  if n_kind(n: v) == "var" and dict_has(dict: pg_fn_nodes(p: lb_p(b: b)), key: n_text(n: v)) then BC(code: pasm(p: lb_p(b: b), text: "call $fn:" ++ n_text(n: v)), cg: cg) else BC(code: [], cg: unsupported(cg: cg, what: "passing this as a function", n: v)) end
end

fn lb_fail(b: LB, cg: Cg, code: Str, message: Str) -> BC
  ensures true
  example len(list: bc_code(b: lb_fail(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new(), code: "R506", message: "m"))) > 0
do
  emit_fail(p: lb_p(b: b), cg: cg, code: code, message: message, n: lb_e(b: b))
end

fn lb_t(b: LB, text: Str) -> List[Int]
  ensures true
  example lb_t(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), text: "i32 1") == [65, 1]
do
  pasm(p: lb_p(b: b), text: text)
end

fn lb_call(b: LB, a: BC, f: Str) -> BC
  ensures true
  example len(list: bc_code(b: lb_call(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), a: BC(code: [], cg: cg_new()), f: "sort"))) == 2
do
  let g: At = if f == "sort" then sort_fn(p: lb_p(b: b), cg: bc_cg(b: a)) else concat_lists_fn(p: lb_p(b: b), cg: bc_cg(b: a)) end
  BC(code: bc_code(b: a) ++ lb_t(b: b, text: "call " ++ n2s(n: at_at(a: g))), cg: at_cg(a: g))
end

fn lb_get(b: LB, ix: At) -> BC
  ensures true
  example len(list: bc_code(b: lb_get(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "get", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), ix: At(at: 3, cg: cg_new())))) > 0
do
  let x: Str = n2s(n: at_at(a: ix))
  let val: BC = load_at(p: lb_p(b: b), cg: at_cg(a: ix), t: lb_el(b: b), addr: lb_t(b: b, text: "localGet " ++ n2s(n: lb_l(b: b)) ++ " localGet " ++ x ++ " i32WrapI64 i32 8 i32Mul i32Add"), off: 8, where: lb_e(b: b))
  let idx: BC = lb_arg(b: b, cg: bc_cg(b: val), name: "index")
  let head: List[Int] = concat(lists: [lb_set(b: b), bc_code(b: idx), lb_t(b: b, text: "localSet " ++ x ++ " localGet " ++ x ++ " i64 0 i64LtS localGet " ++ x ++ " localGet " ++ n2s(n: lb_n(b: b)) ++ " i64ExtendI32U i64GeS i32Or")])
  if n_text(n: lb_e(b: b)) == "get" then
    let fl: BC = lb_fail(b: b, cg: bc_cg(b: idx), code: "R506", message: "index is out of range")
    BC(code: concat(lists: [head, lb_t(b: b, text: "if EMPTY"), bc_code(b: fl), lb_t(b: b, text: "end"), bc_code(b: val)]), cg: bc_cg(b: fl))
  else
    let none: BC = mk_data(p: lb_p(b: b), cg: bc_cg(b: idx), t: ty_of(p: lb_p(b: b), e: lb_e(b: b)), vname: "None", fields: [], where: lb_e(b: b))
    let some: BC = mk_data(p: lb_p(b: b), cg: bc_cg(b: none), t: ty_of(p: lb_p(b: b), e: lb_e(b: b)), vname: "Some", fields: [bc_code(b: val)], where: lb_e(b: b))
    BC(code: concat(lists: [head, lb_t(b: b, text: "if I32"), bc_code(b: none), lb_t(b: b, text: "else"), bc_code(b: some), lb_t(b: b, text: "end")]), cg: bc_cg(b: some))
  end
end

fn lb_range(b: LB, cg: Cg) -> BC
  ensures true
  example len(list: bc_code(b: lb_range(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "range", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new()))) > 0
do
  let fr: At = cg_local(cg: cg, t: 126)
  let d: At = cg_local(cg: at_cg(a: fr), t: 126)
  let pl: At = cg_local(cg: at_cg(a: d), t: 127)
  let from: BC = lb_arg(b: b, cg: at_cg(a: pl), name: "from")
  let to: BC = lb_arg(b: b, cg: bc_cg(b: from), name: "to")
  let fl: BC = lb_fail(b: b, cg: bc_cg(b: to), code: "R504", message: "range is too large")
  let r: At = r513_at(cg: bc_cg(b: fl))
  let f: Str = n2s(n: at_at(a: fr))
  let ds: Str = n2s(n: at_at(a: d))
  let n: Str = n2s(n: lb_n(b: b))
  let i: Str = n2s(n: lb_i(b: b))
  BC(code: concat(lists: [bc_code(b: from), lb_t(b: b, text: "localSet " ++ f), bc_code(b: to), lb_t(b: b, text: "localGet " ++ f ++ " i64Sub localTee " ++ ds ++ " i64 1000000 i64GtS if EMPTY"), bc_code(b: fl), lb_t(b: b, text: join(parts: ["end localGet", ds, "i64 0 i64LtS if I32 i32 0 else localGet", ds, "i32WrapI64 end localSet", n, new_list_t(r513: at_at(a: r), n: lb_n(b: b), l: at_at(a: pl)), each_t(i: lb_i(b: b), n: lb_n(b: b), body: elem_t(l: at_at(a: pl), i: lb_i(b: b)) ++ " localGet " ++ f ++ " localGet " ++ i ++ " i64ExtendI32U i64Add i64Store 8"), "localGet", n2s(n: at_at(a: pl))], by: " "))]), cg: at_cg(a: r))
end

fn lb_append(b: LB, cg: Cg) -> BC
  ensures true
  example len(list: bc_code(b: lb_append(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "append", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new()))) > 0
do
  let pl: At = cg_local(cg: cg, t: 127)
  let m: At = cg_local(cg: at_cg(a: pl), t: 127)
  let r: At = r513_at(cg: at_cg(a: m))
  let item: BC = lb_arg(b: b, cg: at_cg(a: r), name: "item")
  let ps: Str = n2s(n: at_at(a: pl))
  let n: Str = n2s(n: lb_n(b: b))
  let st: BC = store_at(p: lb_p(b: b), cg: bc_cg(b: item), t: lb_el(b: b), addr: lb_t(b: b, text: "localGet " ++ ps ++ " localGet " ++ n ++ " i32 8 i32Mul i32Add"), value: bc_code(b: item), off: 8, where: lb_e(b: b))
  BC(code: concat(lists: [lb_set(b: b), lb_t(b: b, text: join(parts: ["localGet", n, "i32 1 i32Add localSet", n2s(n: at_at(a: m)), new_list_t(r513: at_at(a: r), n: at_at(a: m), l: at_at(a: pl)), copy_t(dst: at_at(a: pl), dst_at: "i32 0", src: lb_l(b: b), src_at: "i32 0", n: "localGet " ++ n)], by: " ")), bc_code(b: st), lb_t(b: b, text: "localGet " ++ ps)]), cg: bc_cg(b: st))
end

fn lb_map(b: LB, pl: At) -> BC
  ensures true
  example len(list: bc_code(b: lb_map(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "map", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), pl: At(at: 3, cg: cg_new())))) > 0
do
  let r: At = r513_at(cg: at_cg(a: pl))
  let it: BC = lb_item(b: b, cg: at_cg(a: r))
  let f: BC = lb_fn(b: b, cg: bc_cg(b: it))
  let st: BC = store_at(p: lb_p(b: b), cg: bc_cg(b: f), t: ty_arg0(t: ty_of(p: lb_p(b: b), e: lb_e(b: b))), addr: lb_t(b: b, text: elem_t(l: at_at(a: pl), i: lb_i(b: b))), value: bc_code(b: it) ++ bc_code(b: f), off: 8, where: lb_e(b: b))
  BC(code: concat(lists: [lb_set(b: b), lb_t(b: b, text: new_list_t(r513: at_at(a: r), n: lb_n(b: b), l: at_at(a: pl))), each_b(p: lb_p(b: b), i: lb_i(b: b), n: lb_n(b: b), body: bc_code(b: st)), lb_t(b: b, text: "localGet " ++ n2s(n: at_at(a: pl)))]), cg: bc_cg(b: st))
end

fn lb_filter(b: LB, cg: Cg) -> BC
  ensures true
  example len(list: bc_code(b: lb_filter(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "filter", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new()))) > 0
do
  let pl: At = cg_local(cg: cg, t: 127)
  let k: At = cg_local(cg: at_cg(a: pl), t: 127)
  let r: At = r513_at(cg: at_cg(a: k))
  let it: BC = lb_item(b: b, cg: at_cg(a: r))
  let f: BC = lb_fn(b: b, cg: bc_cg(b: it))
  let it2: BC = lb_item(b: b, cg: bc_cg(b: f))
  let st: BC = store_at(p: lb_p(b: b), cg: bc_cg(b: it2), t: lb_el(b: b), addr: lb_t(b: b, text: elem_t(l: at_at(a: pl), i: at_at(a: k))), value: bc_code(b: it2), off: 8, where: lb_e(b: b))
  let ps: Str = n2s(n: at_at(a: pl))
  let ks: Str = n2s(n: at_at(a: k))
  let one: List[Int] = concat(lists: [bc_code(b: it), bc_code(b: f), lb_t(b: b, text: "if EMPTY"), bc_code(b: st), lb_t(b: b, text: "localGet " ++ ks ++ " i32 1 i32Add localSet " ++ ks ++ " end")])
  BC(code: concat(lists: [lb_set(b: b), lb_t(b: b, text: new_list_t(r513: at_at(a: r), n: lb_n(b: b), l: at_at(a: pl)) ++ " i32 0 localSet " ++ ks), each_b(p: lb_p(b: b), i: lb_i(b: b), n: lb_n(b: b), body: one), lb_t(b: b, text: "localGet " ++ ps ++ " localGet " ++ ks ++ " i32Store 0 localGet " ++ ps)]), cg: bc_cg(b: st))
end

fn lb_fold(b: LB, cg: Cg) -> BC
  ensures true
  example len(list: bc_code(b: lb_fold(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "fold", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new()))) > 0
do
  let s: At = slot_of(p: lb_p(b: b), cg: cg, t: ty_of(p: lb_p(b: b), e: lb_e(b: b)), where: lb_e(b: b))
  if at_at(a: s) == 0 then
    let init: BC = lb_arg(b: b, cg: at_cg(a: s), name: "init")
    let it: BC = lb_item(b: b, cg: bc_cg(b: init))
    let f: BC = lb_fn(b: b, cg: bc_cg(b: it))
    BC(code: concat(lists: [lb_set(b: b), bc_code(b: init), each_b(p: lb_p(b: b), i: lb_i(b: b), n: lb_n(b: b), body: bc_code(b: it) ++ bc_code(b: f))]), cg: bc_cg(b: f))
  else
    let acc: At = cg_local(cg: at_cg(a: s), t: at_at(a: s))
    let init: BC = lb_arg(b: b, cg: at_cg(a: acc), name: "init")
    let it: BC = lb_item(b: b, cg: bc_cg(b: init))
    let f: BC = lb_fn(b: b, cg: bc_cg(b: it))
    let a: Str = n2s(n: at_at(a: acc))
    BC(code: concat(lists: [lb_set(b: b), bc_code(b: init), lb_t(b: b, text: "localSet " ++ a), each_b(p: lb_p(b: b), i: lb_i(b: b), n: lb_n(b: b), body: concat(lists: [lb_t(b: b, text: "localGet " ++ a), bc_code(b: it), bc_code(b: f), lb_t(b: b, text: "localSet " ++ a)])), lb_t(b: b, text: "localGet " ++ a)]), cg: bc_cg(b: f))
  end
end

# find・any・all：block(結果) > block > loop > if の中から、結果の block へは br 3
fn lb_find(b: LB, cg: Cg) -> BC
  ensures true
  example len(list: bc_code(b: lb_find(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "any", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new()))) > 0
do
  let name: Str = n_text(n: lb_e(b: b))
  let hit: BC = if name == "find" then mk_data(p: lb_p(b: b), cg: bc_cg(b: lb_item(b: b, cg: cg)), t: ty_of(p: lb_p(b: b), e: lb_e(b: b)), vname: "Some", fields: [bc_code(b: lb_item(b: b, cg: cg))], where: lb_e(b: b)) else BC(code: lb_t(b: b, text: if name == "any" then "i32 1" else "i32 0" end), cg: cg) end
  let miss: BC = if name == "find" then mk_data(p: lb_p(b: b), cg: bc_cg(b: hit), t: ty_of(p: lb_p(b: b), e: lb_e(b: b)), vname: "None", fields: [], where: lb_e(b: b)) else BC(code: lb_t(b: b, text: if name == "any" then "i32 0" else "i32 1" end), cg: bc_cg(b: hit)) end
  let it: BC = lb_item(b: b, cg: bc_cg(b: miss))
  let f: BC = lb_fn(b: b, cg: bc_cg(b: it))
  let test: List[Int] = concat(lists: [bc_code(b: it), bc_code(b: f), if name == "all" then lb_t(b: b, text: "i32Eqz") else [] end])
  BC(code: concat(lists: [lb_set(b: b), lb_t(b: b, text: "block I32"), each_b(p: lb_p(b: b), i: lb_i(b: b), n: lb_n(b: b), body: concat(lists: [test, lb_t(b: b, text: "if EMPTY"), bc_code(b: hit), lb_t(b: b, text: "br 3 end")])), bc_code(b: miss), lb_t(b: b, text: "end")]), cg: bc_cg(b: f))
end

fn lb_reverse(b: LB, pl: At) -> BC
  ensures true
  example len(list: bc_code(b: lb_reverse(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "reverse", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), pl: At(at: 3, cg: cg_new())))) > 0
do
  let r: At = r513_at(cg: at_cg(a: pl))
  let ld: BC = load_at(p: lb_p(b: b), cg: at_cg(a: r), t: lb_el(b: b), addr: lb_t(b: b, text: join(parts: ["localGet", n2s(n: lb_l(b: b)), "localGet", n2s(n: lb_n(b: b)), "i32 1 i32Sub localGet", n2s(n: lb_i(b: b)), "i32Sub i32 8 i32Mul i32Add"], by: " ")), off: 8, where: lb_e(b: b))
  let st: BC = store_at(p: lb_p(b: b), cg: bc_cg(b: ld), t: lb_el(b: b), addr: lb_t(b: b, text: elem_t(l: at_at(a: pl), i: lb_i(b: b))), value: bc_code(b: ld), off: 8, where: lb_e(b: b))
  BC(code: concat(lists: [lb_set(b: b), lb_t(b: b, text: new_list_t(r513: at_at(a: r), n: lb_n(b: b), l: at_at(a: pl))), each_b(p: lb_p(b: b), i: lb_i(b: b), n: lb_n(b: b), body: bc_code(b: st)), lb_t(b: b, text: "localGet " ++ n2s(n: at_at(a: pl)))]), cg: bc_cg(b: st))
end

fn lb_take(b: LB, cg: Cg) -> BC
  ensures true
  example len(list: bc_code(b: lb_take(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "take", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new()))) > 0
do
  let c: At = cg_local(cg: cg, t: 126)
  let k: At = cg_local(cg: at_cg(a: c), t: 127)
  let pl: At = cg_local(cg: at_cg(a: k), t: 127)
  let m: At = cg_local(cg: at_cg(a: pl), t: 127)
  let r: At = r513_at(cg: at_cg(a: m))
  let cnt: BC = lb_arg(b: b, cg: at_cg(a: r), name: "count")
  let fl: BC = lb_fail(b: b, cg: bc_cg(b: cnt), code: "R506", message: "count is negative")
  let cs: Str = n2s(n: at_at(a: c))
  let ks: Str = n2s(n: at_at(a: k))
  let ms: Str = n2s(n: at_at(a: m))
  let n: Str = n2s(n: lb_n(b: b))
  let clamp: Str = join(parts: ["localGet", cs, "localGet", n, "i64ExtendI32U i64GtS if I32 localGet", n, "else localGet", cs, "i32WrapI64 end localSet", ks], by: " ")
  let body: Str = if n_text(n: lb_e(b: b)) == "take" then join(parts: ["localGet", ks, "localSet", ms, new_list_t(r513: at_at(a: r), n: at_at(a: m), l: at_at(a: pl)), copy_t(dst: at_at(a: pl), dst_at: "i32 0", src: lb_l(b: b), src_at: "i32 0", n: "localGet " ++ ms)], by: " ") else join(parts: ["localGet", n, "localGet", ks, "i32Sub localSet", ms, new_list_t(r513: at_at(a: r), n: at_at(a: m), l: at_at(a: pl)), copy_t(dst: at_at(a: pl), dst_at: "i32 0", src: lb_l(b: b), src_at: "localGet " ++ ks, n: "localGet " ++ ms)], by: " ") end
  BC(code: concat(lists: [lb_set(b: b), bc_code(b: cnt), lb_t(b: b, text: "localTee " ++ cs ++ " i64 0 i64LtS if EMPTY"), bc_code(b: fl), lb_t(b: b, text: "end " ++ clamp ++ " " ++ body ++ " localGet " ++ n2s(n: at_at(a: pl)))]), cg: bc_cg(b: fl))
end

fn lb_sum(b: LB, acc: At) -> BC
  ensures true
  example len(list: bc_code(b: lb_sum(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "sum", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), acc: At(at: 3, cg: cg_new())))) > 0
do
  let it: BC = lb_item(b: b, cg: at_cg(a: acc))
  let a: Str = n2s(n: at_at(a: acc))
  BC(code: concat(lists: [lb_set(b: b), lb_t(b: b, text: "i64 0 localSet " ++ a), each_b(p: lb_p(b: b), i: lb_i(b: b), n: lb_n(b: b), body: concat(lists: [lb_t(b: b, text: "localGet " ++ a), bc_code(b: it), lb_t(b: b, text: "i64Add call $chk localSet " ++ a)])), lb_t(b: b, text: "localGet " ++ a)]), cg: bc_cg(b: it))
end

fn lb_max(b: LB, cg: Cg) -> BC
  ensures true
  example len(list: bc_code(b: lb_max(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "max", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new()))) > 0
do
  let acc: At = cg_local(cg: cg, t: 126)
  let x: At = cg_local(cg: at_cg(a: acc), t: 126)
  let none: BC = mk_data(p: lb_p(b: b), cg: at_cg(a: x), t: ty_of(p: lb_p(b: b), e: lb_e(b: b)), vname: "None", fields: [], where: lb_e(b: b))
  let it: BC = lb_item(b: b, cg: bc_cg(b: none))
  let a: Str = n2s(n: at_at(a: acc))
  let xs: Str = n2s(n: at_at(a: x))
  let some: BC = mk_data(p: lb_p(b: b), cg: bc_cg(b: it), t: ty_of(p: lb_p(b: b), e: lb_e(b: b)), vname: "Some", fields: [lb_t(b: b, text: "localGet " ++ a)], where: lb_e(b: b))
  let better: Str = if n_text(n: lb_e(b: b)) == "max" then "i64GtS" else "i64LtS" end
  BC(code: concat(lists: [lb_set(b: b), lb_t(b: b, text: "localGet " ++ n2s(n: lb_n(b: b)) ++ " i32Eqz if I32"), bc_code(b: none), lb_t(b: b, text: "else localGet " ++ n2s(n: lb_l(b: b)) ++ " i64Load 8 localSet " ++ a), each_b(p: lb_p(b: b), i: lb_i(b: b), n: lb_n(b: b), body: concat(lists: [bc_code(b: it), lb_t(b: b, text: "localTee " ++ xs ++ " localGet " ++ a ++ " " ++ better ++ " if EMPTY localGet " ++ xs ++ " localSet " ++ a ++ " end")])), bc_code(b: some), lb_t(b: b, text: "end")]), cg: bc_cg(b: some))
end

# ---- 文字で書く手伝いの関数の共通の部品 ----
# needs は中身を作るときに順に置くもの（「記号|種類|値」。種類 s は文字の定数・t は欄の無い case・g は手伝いの関数）。text の $記号 で引く

type Need
  case Need(p: Prog, syms: Dict[Int], cg: Cg)
end

fn sym_gen(p: Prog, cg: Cg, key: Str, params: List[Int], results: List[Int], locals: List[Int], needs: List[Str], text: Str) -> At
  ensures true
  example at_at(a: sym_gen(p: prog_empty(), cg: cg_new(), key: "k", params: [], results: [], locals: [], needs: ["A|s|x"], text: "i32 $A")) == 0
do
  let g: GenOpen = gen_open(p: p, cg: cg, key: key, params: params, results: results)
  if go_found(g: g) then At(at: go_at(g: g), cg: cg) else sym_close(p: p, g: g, nd: fold(list: needs, init: Need(p: p, syms: pg_syms(p: p), cg: gen_locals(cg: go_cg(g: g), ts: locals)), func: need_step), text: text) end
end

fn sym_close(p: Prog, g: GenOpen, nd: Need, text: Str) -> At
  ensures true
  example at_at(a: sym_close(p: prog_empty(), g: gen_open(p: prog_empty(), cg: cg_new(), key: "k", params: [], results: []), nd: Need(p: prog_empty(), syms: no_ints(), cg: cg_new()), text: "i32 1")) == 0
do
  match nd
    case Need(p: _, syms: s, cg: c) then gen_close(g: g, body: BC(code: asm(text: text, syms: s), cg: c))
  end
end

fn need_step(acc: Need, spec: Str) -> Need
  ensures true
  example need_step(acc: Need(p: prog_empty(), syms: no_ints(), cg: cg_new()), spec: "A|t|1") == Need(p: prog_empty(), syms: dict(keys: ["A"], values: [48]), cg: at_cg(a: cg_tag(cg: cg_new(), index: 1)))
do
  match acc
    case Need(p: p, syms: s, cg: c) then need_put(acc: acc, name: word_sep(text: spec, by: "|", i: 0), a: need_at(p: p, cg: c, kind: word_sep(text: spec, by: "|", i: 1), value: word_sep(text: spec, by: "|", i: 2)))
  end
end

fn need_put(acc: Need, name: Str, a: At) -> Need
  ensures true
  example need_put(acc: Need(p: prog_empty(), syms: no_ints(), cg: cg_new()), name: "A", a: At(at: 5, cg: cg_new())) == Need(p: prog_empty(), syms: dict(keys: ["A"], values: [5]), cg: cg_new())
do
  match acc
    case Need(p: p, syms: s, cg: _) then Need(p: p, syms: dict_put(dict: s, key: name, value: at_at(a: a)), cg: at_cg(a: a))
  end
end

fn need_at(p: Prog, cg: Cg, kind: Str, value: Str) -> At
  ensures true
  example at_at(a: need_at(p: prog_empty(), cg: cg_new(), kind: "s", value: "x")) == 48
do
  when
    kind == "s" then cg_str(cg: cg, text: value)
    kind == "t" then cg_tag(cg: cg, index: int_or_zero(text: value))
    kind == "g" then named_gen(p: p, cg: cg, name: value)
    else At(at: 0, cg: cg)
  end
end

fn int_or_zero(text: Str) -> Int
  ensures true
  example int_or_zero(text: "12") == 12
  example int_or_zero(text: "x") == 0
do
  match parse_int(text: text)
    case Some(value: v) then v
    case None then 0
  end
end

# by で区切った i 番め（無ければ ""）
fn word_sep(text: Str, by: Str, i: Int) -> Str
  ensures true
  example word_sep(text: "a|b|c d", by: "|", i: 2) == "c d"
  example word_sep(text: "a", by: "", i: 0) == ""
do
  if by == "" then "" else
    let ws: List[Str] = split(text: text, by: by)
    if i >= 0 and i < len(list: ws) then get(list: ws, index: i) else "" end
  end
end

# 中で作る手伝いの関数（名前で）
fn named_gen(p: Prog, cg: Cg, name: Str) -> At
  ensures true
  example at_at(a: named_gen(p: prog_empty(), cg: cg_new(), name: "nope")) == 0
do
  when
    name == "quote" then quote_fn(p: p, cg: cg)
    name == "str cmp" then str_cmp_fn(p: p, cg: cg)
    name == "dict find" then dict_find_fn(p: p, cg: cg)
    name == "path ok" then path_ok_fn(p: p, cg: cg)
    name == "link on the way" then link_fn(p: p, cg: cg)
    else At(at: 0, cg: cg)
  end
end

fn r513_need() -> Str
  ensures true
  example r513_need() == "R513|s|R513 out of memory"
do
  "R513|s|R513 out of memory"
end

# ---- 辞書（[数 u32][pad][鍵 Str の場所 8 バイト][値 8 バイト]... 鍵のバイト順） ----

# 文字のバイト順の比べ：a < b なら -1、同じなら 0、a > b なら 1（局所変数 2 = a の長さ・3 = b の長さ・4 = 短いほう・5 = i・6・7 = バイト）
fn str_cmp_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: str_cmp_fn(p: prog_empty(), cg: cg_new())) == 0
do
  sym_gen(p: p, cg: cg, key: "str cmp", params: [127, 127], results: [127], locals: i32s(n: 6), needs: [], text: join(parts: ["localGet 0 i32Load 0 localSet 2 localGet 1 i32Load 0 localSet 3 localGet 2 localGet 3 localGet 2 localGet 3 i32LtU select localSet 4", each_t(i: 5, n: 4, body: "localGet 0 localGet 5 i32Add i32Load8u 4 localTee 6 localGet 1 localGet 5 i32Add i32Load8u 4 localTee 7 i32Ne if EMPTY i32 -1 i32 1 localGet 6 localGet 7 i32LtU select return end"), "localGet 2 localGet 3 i32LtU if I32 i32 -1 else localGet 2 localGet 3 i32GtU end"], by: " "))
end

# 鍵を探す（二分探索）。あればその番号、無ければ -(入れる場所) - 1（局所変数 2 = lo・3 = hi・4 = mid・5 = 比べた結果）
fn dict_find_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: dict_find_fn(p: prog_empty(), cg: cg_new())) == 0
do
  sym_gen(p: p, cg: cg, key: "dict find", params: [127, 127], results: [127], locals: i32s(n: 4), needs: ["SC|g|str cmp"], text: "i32 0 localSet 2 localGet 0 i32Load 0 localSet 3 block EMPTY loop EMPTY localGet 2 localGet 3 i32GeU brIf 1 localGet 2 localGet 3 i32Add i32 1 i32ShrU localSet 4 " ++ entry_t(d: 0, i: 4) ++ " i32Load 8 localGet 1 call $SC localTee 5 i32Eqz if EMPTY localGet 4 return end localGet 5 i32 0 i32LtS if EMPTY localGet 4 i32 1 i32Add localSet 2 else localGet 4 localSet 3 end br 0 end end i32 -1 localGet 2 i32Sub")
end

fn new_dict_t(n: Int, d: Int) -> Str
  ensures true
  example new_dict_t(n: 1, d: 2) == "localGet 1 i32 16 i32Mul i32 8 i32Add call $alloc localTee 2 localGet 1 i32Store 0"
do
  "localGet " ++ n2s(n: n) ++ " i32 16 i32Mul i32 8 i32Add call $alloc localTee " ++ n2s(n: d) ++ " localGet " ++ n2s(n: n) ++ " i32Store 0"
end

fn copy_entries_t(dst: Int, dst_at: Str, src: Int, src_at: Str, cnt: Str) -> Str
  ensures true
  example str_len(text: copy_entries_t(dst: 1, dst_at: "i32 0", src: 0, src_at: "i32 0", cnt: "localGet 2")) > 0
do
  "localGet " ++ n2s(n: dst) ++ " i32 8 i32Add " ++ dst_at ++ " i32 16 i32Mul i32Add localGet " ++ n2s(n: src) ++ " i32 8 i32Add " ++ src_at ++ " i32 16 i32Mul i32Add " ++ cnt ++ " i32 16 i32Mul memoryCopy"
end

# put(d, key, 値の 8 バイト) -> 新しい辞書（局所変数 3 = 見つけた番号・4 = 数・5 = 新しい数・6 = 新しい辞書・7 = 入れる場所）
fn dict_put_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: dict_put_fn(p: prog_empty(), cg: cg_new())) == 0
do
  sym_gen(p: p, cg: cg, key: "dict put", params: [127, 127, 126], results: [127], locals: i32s(n: 5), needs: ["DF|g|dict find"], text: join(parts: ["localGet 0 localGet 1 call $DF localSet 3 localGet 0 i32Load 0 localSet 4 localGet 3 i32 0 i32GeS if EMPTY", new_dict_t(n: 4, d: 6), copy_entries_t(dst: 6, dst_at: "i32 0", src: 0, src_at: "i32 0", cnt: "localGet 4"), "localGet 3 localSet 7 else i32 -1 localGet 3 i32Sub localSet 7 localGet 4 i32 1 i32Add localSet 5", new_dict_t(n: 5, d: 6), copy_entries_t(dst: 6, dst_at: "i32 0", src: 0, src_at: "i32 0", cnt: "localGet 7"), copy_entries_t(dst: 6, dst_at: "localGet 7 i32 1 i32Add", src: 0, src_at: "localGet 7", cnt: "localGet 4 localGet 7 i32Sub"), "end", entry_t(d: 6, i: 7), "localGet 1 i32Store 8", entry_t(d: 6, i: 7), "localGet 2 i64Store 16 localGet 6"], by: " "))
end

# 局所変数 2 = 見つけた番号・3 = 数・4 = 新しい数・5 = 新しい辞書
fn dict_remove_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: dict_remove_fn(p: prog_empty(), cg: cg_new())) == 0
do
  sym_gen(p: p, cg: cg, key: "dict remove", params: [127, 127], results: [127], locals: i32s(n: 4), needs: ["DF|g|dict find"], text: join(parts: ["localGet 0 localGet 1 call $DF localTee 2 i32 0 i32LtS if EMPTY localGet 0 return end localGet 0 i32Load 0 localTee 3 i32 1 i32Sub localSet 4", new_dict_t(n: 4, d: 5), copy_entries_t(dst: 5, dst_at: "i32 0", src: 0, src_at: "i32 0", cnt: "localGet 2"), copy_entries_t(dst: 5, dst_at: "localGet 2", src: 0, src_at: "localGet 2 i32 1 i32Add", cnt: "localGet 4 localGet 2 i32Sub"), "localGet 5"], by: " "))
end

# dict(keys, values)。数が合わなければ -1、鍵が重なれば 0（局所変数 2 = 数・3 = i・4 = 入れた数・5 = 辞書・6 = 見つけた番号・7 = 入れる場所・8 = 鍵）
fn dict_of_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: dict_of_fn(p: prog_empty(), cg: cg_new())) == 0
do
  sym_gen(p: p, cg: cg, key: "dict of", params: [127, 127], results: [127], locals: i32s(n: 7), needs: ["DF|g|dict find"], text: join(parts: ["localGet 0 i32Load 0 localTee 2 localGet 1 i32Load 0 i32Ne if EMPTY i32 -1 return end", new_dict_t(n: 2, d: 5), "localGet 5 i32 0 i32Store 0 i32 0 localSet 4", each_t(i: 3, n: 2, body: join(parts: [elem_t(l: 0, i: 3), "i32Load 8 localSet 8 localGet 5 localGet 8 call $DF localTee 6 i32 0 i32GeS if EMPTY i32 0 return end i32 -1 localGet 6 i32Sub localSet 7", copy_entries_t(dst: 5, dst_at: "localGet 7 i32 1 i32Add", src: 5, src_at: "localGet 7", cnt: "localGet 4 localGet 7 i32Sub"), entry_t(d: 5, i: 7), "localGet 8 i32Store 8", entry_t(d: 5, i: 7), elem_t(l: 1, i: 3), "i64Load 8 i64Store 16 localGet 4 i32 1 i32Add localSet 4 localGet 5 localGet 4 i32Store 0"], by: " ")), "localGet 5"], by: " "))
end

# 値を 8 バイトの i64 にする（i32 の値は下の 4 バイトに）
fn bits_code(p: Prog, cg: Cg, t: Ty, code: List[Int], where: Node) -> BC
  ensures true
  example bc_code(b: bits_code(p: prog_empty(), cg: cg_new(), t: tk(k: "Int"), code: [1], where: bare(kind: "x", text: "", kids: []))) == [1]
do
  let s: At = slot_of(p: p, cg: cg, t: t, where: where)
  when
    at_at(a: s) == 0 then BC(code: code ++ pasm(p: p, text: "i64 0"), cg: at_cg(a: s))
    at_at(a: s) == 126 then BC(code: code, cg: at_cg(a: s))
    else BC(code: code ++ pasm(p: p, text: "i64ExtendI32U"), cg: at_cg(a: s))
  end
end

# 辞書の組み込み。始めに局所変数 d・n・i・p・f を取る（JS と同じ）
fn dict_builtin(p: Prog, cg: Cg, scope: Dict[Int], e: Node) -> BC
  ensures true
  example len(list: bc_code(b: dict_builtin(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "call", text: "dict_size", kids: [])))) > 0
do
  let d: At = cg_local(cg: cg, t: 127)
  let c5: Cg = at_cg(a: cg_local(cg: at_cg(a: cg_local(cg: at_cg(a: cg_local(cg: at_cg(a: cg_local(cg: at_cg(a: d), t: 127)), t: 127)), t: 127)), t: 127))
  let b: LB = LB(p: p, scope: scope, e: e, el: ty_arg0(t: ty_of(p: p, e: arg_value(e: e, name: "dict"))), l: at_at(a: d), n: at_at(a: d) + 1, i: at_at(a: d) + 2, set: [])
  let name: Str = n_text(n: e)
  when
    name == "dict" then db_dict(b: b, cg: c5)
    name == "dict_put" then db_put(b: b, cg: c5)
    name == "dict_remove" then db_two(b: b, cg: c5, f: "remove")
    name == "dict_has" then db_two(b: b, cg: c5, f: "has")
    name == "dict_size" then bc_then(b: lb_arg(b: b, cg: c5, name: "dict"), more: pasm(p: p, text: "i32Load 0 i64ExtendI32U"))
    name == "dict_get" then db_get(b: b, cg: c5)
    name == "dict_keys" or name == "dict_values" then db_keys(b: b, cg: c5)
    else BC(code: [], cg: unsupported(cg: c5, what: "the built-in function " ++ name, n: e))
  end
end

fn db_dict(b: LB, cg: Cg) -> BC
  ensures true
  example len(list: bc_code(b: db_dict(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "dict", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new()))) > 0
do
  let ks: BC = lb_arg(b: b, cg: cg, name: "keys")
  let vs: BC = lb_arg(b: b, cg: bc_cg(b: ks), name: "values")
  let g: At = dict_of_fn(p: lb_p(b: b), cg: bc_cg(b: vs))
  let f1: BC = lb_fail(b: b, cg: at_cg(a: g), code: "R506", message: "dict got a different number of keys and values")
  let f2: BC = lb_fail(b: b, cg: bc_cg(b: f1), code: "R506", message: "a key appears twice in dict")
  let ps: Str = n2s(n: lb_l(b: b) + 3)
  BC(code: concat(lists: [bc_code(b: ks), bc_code(b: vs), lb_t(b: b, text: "call " ++ n2s(n: at_at(a: g)) ++ " localTee " ++ ps ++ " i32 -1 i32Eq if EMPTY"), bc_code(b: f1), lb_t(b: b, text: "end localGet " ++ ps ++ " i32Eqz if EMPTY"), bc_code(b: f2), lb_t(b: b, text: "end localGet " ++ ps)]), cg: bc_cg(b: f2))
end

fn db_put(b: LB, cg: Cg) -> BC
  ensures true
  example len(list: bc_code(b: db_put(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "dict_put", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new()))) > 0
do
  let dv: BC = lb_arg(b: b, cg: cg, name: "dict")
  let kv: BC = lb_arg(b: b, cg: bc_cg(b: dv), name: "key")
  let vv: BC = lb_arg(b: b, cg: bc_cg(b: kv), name: "value")
  let bits: BC = bits_code(p: lb_p(b: b), cg: bc_cg(b: vv), t: lb_el(b: b), code: bc_code(b: vv), where: lb_e(b: b))
  let g: At = dict_put_fn(p: lb_p(b: b), cg: bc_cg(b: bits))
  BC(code: concat(lists: [bc_code(b: dv), bc_code(b: kv), bc_code(b: bits), lb_t(b: b, text: "call " ++ n2s(n: at_at(a: g)))]), cg: at_cg(a: g))
end

fn db_two(b: LB, cg: Cg, f: Str) -> BC
  ensures true
  example len(list: bc_code(b: db_two(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "dict_has", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new(), f: "has"))) > 0
do
  let dv: BC = lb_arg(b: b, cg: cg, name: "dict")
  let kv: BC = lb_arg(b: b, cg: bc_cg(b: dv), name: "key")
  let g: At = if f == "remove" then dict_remove_fn(p: lb_p(b: b), cg: bc_cg(b: kv)) else dict_find_fn(p: lb_p(b: b), cg: bc_cg(b: kv)) end
  BC(code: concat(lists: [bc_code(b: dv), bc_code(b: kv), lb_t(b: b, text: "call " ++ n2s(n: at_at(a: g)) ++ if f == "has" then " i32 0 i32GeS" else "" end)]), cg: at_cg(a: g))
end

fn db_get(b: LB, cg: Cg) -> BC
  ensures true
  example len(list: bc_code(b: db_get(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "dict_get", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new()))) > 0
do
  let dv: BC = lb_arg(b: b, cg: cg, name: "dict")
  let kv: BC = lb_arg(b: b, cg: bc_cg(b: dv), name: "key")
  let g: At = dict_find_fn(p: lb_p(b: b), cg: bc_cg(b: kv))
  let none: BC = mk_data(p: lb_p(b: b), cg: at_cg(a: g), t: ty_of(p: lb_p(b: b), e: lb_e(b: b)), vname: "None", fields: [], where: lb_e(b: b))
  let d: Int = lb_l(b: b)
  let ps: Str = n2s(n: d + 3)
  let fs: Str = n2s(n: d + 4)
  BC(code: concat(lists: [bc_code(b: dv), lb_t(b: b, text: "localTee " ++ n2s(n: d)), bc_code(b: kv), lb_t(b: b, text: "call " ++ n2s(n: at_at(a: g)) ++ " localTee " ++ fs ++ " i32 0 i32LtS if I32"), bc_code(b: none), lb_t(b: b, text: "else i32 16 call $alloc localTee " ++ ps ++ " i32 " ++ n2s(n: cvar_index(v: cvar_of(p: lb_p(b: b), name: "Some"))) ++ " i32Store 0 localGet " ++ ps ++ " " ++ entry_t(d: d, i: d + 4) ++ " i64Load 16 i64Store 8 localGet " ++ ps ++ " end")]), cg: bc_cg(b: none))
end

fn db_keys(b: LB, cg: Cg) -> BC
  ensures true
  example len(list: bc_code(b: db_keys(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "dict_keys", kids: []), el: tk(k: "Int"), l: 0, n: 1, i: 2, set: []), cg: cg_new()))) > 0
do
  let dv: BC = lb_arg(b: b, cg: cg, name: "dict")
  let r: At = r513_at(cg: bc_cg(b: dv))
  let d: Int = lb_l(b: b)
  let off: Str = if n_text(n: lb_e(b: b)) == "dict_keys" then "8" else "16" end
  BC(code: bc_code(b: dv) ++ lb_t(b: b, text: join(parts: ["localTee", n2s(n: d), "i32Load 0 localSet", n2s(n: d + 1), new_list_t(r513: at_at(a: r), n: d + 1, l: d + 3), each_t(i: d + 2, n: d + 1, body: elem_t(l: d + 3, i: d + 2) ++ " " ++ entry_t(d: d, i: d + 2) ++ " i64Load " ++ off ++ " i64Store 8"), "localGet", n2s(n: d + 3)], by: " ")), cg: at_cg(a: r))
end

# ---- 文字の手伝いの関数 ----

# s の at バイトめから始まる文字が、JavaScript の trim が消す空白なら、そのバイト数。違えば 0（局所変数 2 = 先頭のバイト・3 = コード・4 = バイト数）
fn ws_at_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: ws_at_fn(p: prog_empty(), cg: cg_new())) == 0
do
  sym_gen(p: p, cg: cg, key: "ws at", params: [127, 127], results: [127], locals: i32s(n: 3), needs: [], text: ws_text())
end

fn ws_byte(k: Int) -> Str
  ensures true
  example ws_byte(k: 1) == "localGet 0 localGet 1 i32Add i32Load8u 5"
do
  "localGet 0 localGet 1 i32Add i32Load8u " ++ n2s(n: 4 + k)
end

fn ws_in(lo: Int, hi: Int) -> Str
  ensures true
  example ws_in(lo: 9, hi: 13) == "localGet 3 i32 9 i32Sub i32 5 i32LtU"
do
  "localGet 3 i32 " ++ n2s(n: lo) ++ " i32Sub i32 " ++ n2s(n: hi - lo + 1) ++ " i32LtU"
end

fn ws_is(c: Int) -> Str
  ensures true
  example ws_is(c: 32) == "localGet 3 i32 32 i32Eq"
do
  "localGet 3 i32 " ++ n2s(n: c) ++ " i32Eq"
end

fn ws_text() -> Str
  ensures str_len(text: result) > 0
  example str_len(text: ws_text()) > 100
do
  let c1: Str = ws_byte(k: 1) ++ " i32 63 i32And"
  let c2: Str = ws_byte(k: 2) ++ " i32 63 i32And"
  let tests: Str = join(parts: [ws_in(lo: 9, hi: 13), ws_is(c: 32), "i32Or", ws_is(c: 160), "i32Or", ws_is(c: 5760), "i32Or", ws_in(lo: 8192, hi: 8202), "i32Or", ws_is(c: 8232), "i32Or", ws_is(c: 8233), "i32Or", ws_is(c: 8239), "i32Or", ws_is(c: 8287), "i32Or", ws_is(c: 12288), "i32Or", ws_is(c: 65279), "i32Or"], by: " ")
  join(parts: [ws_byte(k: 0), "localTee 2 i32 128 i32LtU if EMPTY localGet 2 localSet 3 i32 1 localSet 4 else localGet 2 i32 224 i32LtU if EMPTY localGet 2 i32 31 i32And i32 6 i32Shl", c1, "i32Or localSet 3 i32 2 localSet 4 else localGet 2 i32 240 i32LtU if EMPTY localGet 2 i32 15 i32And i32 12 i32Shl", c1, "i32 6 i32Shl i32Or", c2, "i32Or localSet 3 i32 3 localSet 4 else i32 -1 localSet 3 i32 4 localSet 4 end end end", tests, "if I32 localGet 4 else i32 0 end"], by: " ")
end

# 前後の空白を消した新しい文字（局所変数 1 = 始め・2 = 終わり・3 = 最後の文字の始まり・4 = バイト数・5 = 結果）
fn trim_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: trim_fn(p: prog_empty(), cg: cg_new())) == 1
do
  let ws: At = ws_at_fn(p: p, cg: cg)
  let w: Str = n2s(n: at_at(a: ws))
  sym_gen(p: p, cg: at_cg(a: ws), key: "trim", params: [127], results: [127], locals: i32s(n: 5), needs: [], text: "localGet 0 i32Load 0 localSet 2 block EMPTY loop EMPTY localGet 1 localGet 2 i32GeU brIf 1 localGet 0 localGet 1 call " ++ w ++ " localTee 4 i32Eqz brIf 1 localGet 1 localGet 4 i32Add localSet 1 br 0 end end block EMPTY loop EMPTY localGet 2 localGet 1 i32LeU brIf 1 localGet 2 i32 1 i32Sub localSet 3 block EMPTY loop EMPTY localGet 0 localGet 3 i32Add i32Load8u 4 i32 192 i32And i32 128 i32Ne brIf 1 localGet 3 i32 1 i32Sub localSet 3 br 0 end end localGet 0 localGet 3 call " ++ w ++ " i32Eqz brIf 1 localGet 3 localSet 2 br 0 end end localGet 2 localGet 1 i32Sub localTee 4 i32 4 i32Add call $alloc localTee 5 localGet 4 i32Store 0 localGet 5 i32 4 i32Add localGet 0 i32 4 i32Add localGet 1 i32Add localGet 4 memoryCopy localGet 5")
end

# 前後の空白を消して、-? と数字だけなら Some(数)。±MAX を超えるなら None
# 局所変数 1 = 消した文字・2 = 長さ・3 = i・4 = 負か・5 = 数字・6 = 数（i64）・7 = 結果
fn parse_int_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: parse_int_fn(p: prog_empty(), cg: cg_new())) == 2
do
  let tr: At = trim_fn(p: p, cg: cg)
  let none: Str = "i32 $NONE return"
  sym_gen(p: p, cg: at_cg(a: tr), key: "parse_int", params: [127], results: [127], locals: [127, 127, 127, 127, 127, 126, 127], needs: ["NONE|t|" ++ n2s(n: cvar_index(v: cvar_of(p: p, name: "None")))], text: join(parts: ["localGet 0 call", n2s(n: at_at(a: tr)), "localTee 1 i32Load 0 localTee 2 i32Eqz if EMPTY", none, "end localGet 1 i32Load8u 4 i32 45 i32Eq localTee 4 localSet 3 localGet 3 localGet 2 i32GeU if EMPTY", none, "end block EMPTY loop EMPTY localGet 3 localGet 2 i32GeU brIf 1 localGet 1 localGet 3 i32Add i32Load8u 4 i32 48 i32Sub localTee 5 i32 9 i32GtU if EMPTY", none, "end localGet 6 i64 10 i64Mul localGet 5 i64ExtendI32U i64Add localTee 6 i64 9007199254740991 i64GtS if EMPTY", none, "end localGet 3 i32 1 i32Add localSet 3 br 0 end end i32 16 call $alloc localTee 7 i32", n2s(n: cvar_index(v: cvar_of(p: p, name: "Some"))), "i32Store 0 localGet 7 localGet 4 if I64 i64 0 localGet 6 i64Sub else localGet 6 end i64Store 8 localGet 7"], by: " "))
end

# s の中で、at バイトめから part が続いていれば 1（局所変数 3 = part の長さ・4 = k）
fn match_at_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: match_at_fn(p: prog_empty(), cg: cg_new())) == 0
do
  sym_gen(p: p, cg: cg, key: "match at", params: [127, 127, 127], results: [127], locals: i32s(n: 2), needs: [], text: join(parts: ["localGet 2 i32Load 0 localSet 3 localGet 1 i32 0 i32LtS localGet 1 localGet 3 i32Add localGet 0 i32Load 0 i32GtU i32Or if EMPTY i32 0 return end", each_t(i: 4, n: 3, body: "localGet 0 localGet 1 i32Add localGet 4 i32Add i32Load8u 4 localGet 2 localGet 4 i32Add i32Load8u 4 i32Ne if EMPTY i32 0 return end"), "i32 1"], by: " "))
end

# s の from バイトめから後ろで、part が最初に出てくる場所。無ければ -1（局所変数 3 = 最後に調べる場所）
fn index_of_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: index_of_fn(p: prog_empty(), cg: cg_new())) == 1
do
  let ma: At = match_at_fn(p: p, cg: cg)
  sym_gen(p: p, cg: at_cg(a: ma), key: "index of", params: [127, 127, 127], results: [127], locals: [127], needs: [], text: "localGet 0 i32Load 0 localGet 1 i32Load 0 i32Sub localSet 3 block EMPTY loop EMPTY localGet 2 localGet 3 i32GtS brIf 1 localGet 0 localGet 2 localGet 1 call " ++ n2s(n: at_at(a: ma)) ++ " if EMPTY localGet 2 return end localGet 2 i32 1 i32Add localSet 2 br 0 end end i32 -1")
end

# s の from から to（バイト）を切り出した新しい文字（局所変数 3 = 結果）
fn slice_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: slice_fn(p: prog_empty(), cg: cg_new())) == 0
do
  let n: Str = "localGet 2 localGet 1 i32Sub"
  sym_gen(p: p, cg: cg, key: "slice", params: [127, 127, 127], results: [127], locals: [127], needs: [], text: join(parts: [n, "i32 4 i32Add call $alloc localTee 3", n, "i32Store 0 localGet 3 i32 4 i32Add localGet 0 i32 4 i32Add localGet 1 i32Add", n, "memoryCopy localGet 3"], by: " "))
end

# split(text, by)：JavaScript の split と同じく、左から重ならないように切る
# 局所変数 2 = いくつ・3 = 見つけた場所・4 = 探しはじめ・5 = 結果・6 = 入れた数
fn split_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: split_fn(p: prog_empty(), cg: cg_new())) == 3
do
  let io: At = index_of_fn(p: p, cg: cg)
  let sl: At = slice_fn(p: p, cg: at_cg(a: io))
  let next: Str = "localGet 0 localGet 1 localGet 4 call " ++ n2s(n: at_at(a: io)) ++ " localSet 3"
  let adv: Str = "localGet 3 localGet 1 i32Load 0 i32Add localSet 4"
  let s: Str = n2s(n: at_at(a: sl))
  sym_gen(p: p, cg: at_cg(a: sl), key: "split", params: [127, 127], results: [127], locals: i32s(n: 5), needs: [r513_need()], text: join(parts: ["i32 1 localSet 2 i32 0 localSet 4 block EMPTY loop EMPTY", next, "localGet 3 i32 0 i32LtS brIf 1 localGet 2 i32 1 i32Add localSet 2", adv, "br 0 end end", new_list_t_sym(n: 2, l: 5), "i32 0 localSet 4 i32 0 localSet 6 block EMPTY loop EMPTY", next, "localGet 3 i32 0 i32LtS brIf 1", elem_t(l: 5, i: 6), "localGet 0 localGet 4 localGet 3 call", s, "i32Store 8 localGet 6 i32 1 i32Add localSet 6", adv, "br 0 end end", elem_t(l: 5, i: 6), "localGet 0 localGet 4 localGet 0 i32Load 0 call", s, "i32Store 8 localGet 5"], by: " "))
end

# new_list_t の、R513 の場所を記号 $R513 で書くもの
fn new_list_t_sym(n: Int, l: Int) -> Str
  ensures true
  example str_len(text: new_list_t_sym(n: 1, l: 2)) > 0
do
  "localGet " ++ n2s(n: n) ++ " i32 134217728 i32GtU if EMPTY i32 $R513 call $fail end localGet " ++ n2s(n: n) ++ " i32 8 i32Mul i32 8 i32Add call $alloc localTee " ++ n2s(n: l) ++ " localGet " ++ n2s(n: n) ++ " i32Store 0"
end

# 1文字ずつのリスト（局所変数 1 = 長さ・2 = i・3 = 数・4 = 結果・5 = バイト・6 = その文字のバイト数）
fn chars_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: chars_fn(p: prog_empty(), cg: cg_new())) == 1
do
  let sl: At = slice_fn(p: p, cg: cg)
  sym_gen(p: p, cg: at_cg(a: sl), key: "chars", params: [127], results: [127], locals: i32s(n: 6), needs: [r513_need()], text: join(parts: ["localGet 0 i32Load 0 localSet 1", chars_walk(body: "localGet 3 i32 1 i32Add localSet 3"), new_list_t_sym(n: 3, l: 4), "i32 0 localSet 3", chars_walk(body: elem_t(l: 4, i: 3) ++ " localGet 0 localGet 2 localGet 2 localGet 6 i32Add call " ++ n2s(n: at_at(a: sl)) ++ " i32Store 8 localGet 3 i32 1 i32Add localSet 3"), "localGet 4"], by: " "))
end

fn chars_walk(body: Str) -> Str
  ensures true
  example str_len(text: chars_walk(body: "")) > 0
do
  "i32 0 localSet 2 block EMPTY loop EMPTY localGet 2 localGet 1 i32GeU brIf 1 localGet 0 localGet 2 i32Add i32Load8u 4 localTee 5 i32 128 i32LtU if I32 i32 1 else localGet 5 i32 224 i32LtU if I32 i32 2 else localGet 5 i32 240 i32LtU if I32 i32 3 else i32 4 end end end localSet 6 " ++ body ++ " localGet 2 localGet 6 i32Add localSet 2 br 0 end end"
end

# lines：空なら []。\r\n を \n にそろえ、最後の \n を1つ落としてから \n で切る（局所変数 1 = 長さ・2 = i・3 = 書く場所・4 = 結果・5 = バイト）
fn lines_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: lines_fn(p: prog_empty(), cg: cg_new())) == 4
do
  let sp: At = split_fn(p: p, cg: cg)
  let b0: Str = "localGet 0 localGet 2 i32Add i32Load8u 4"
  let b1: Str = "localGet 0 localGet 2 i32Add i32Load8u 5"
  sym_gen(p: p, cg: at_cg(a: sp), key: "lines", params: [127], results: [127], locals: i32s(n: 5), needs: [r513_need(), "NL|s|\n"], text: join(parts: ["localGet 0 i32Load 0 localTee 1 i32Eqz if EMPTY i32 0 localSet 1", new_list_t_sym(n: 1, l: 4), "localGet 4 return end localGet 1 i32 4 i32Add call $alloc localTee 4 localGet 1 i32Store 0 localGet 4 i32 4 i32Add localSet 3", each_t(i: 2, n: 1, body: "block EMPTY " ++ b0 ++ " localTee 5 i32 13 i32Eq localGet 2 i32 1 i32Add localGet 1 i32LtU i32And if EMPTY " ++ b1 ++ " i32 10 i32Eq brIf 1 end localGet 3 localGet 5 i32Store8 0 localGet 3 i32 1 i32Add localSet 3 end"), "localGet 3 localGet 4 i32 4 i32Add i32Sub localSet 1 localGet 1 if EMPTY localGet 3 i32 1 i32Sub i32Load8u 0 i32 10 i32Eq if EMPTY localGet 1 i32 1 i32Sub localSet 1 end end localGet 4 localGet 1 i32Store 0 localGet 4 i32 $NL call", n2s(n: at_at(a: sp))], by: " "))
end

# html_text：& < > " ' を置きかえた新しい文字（局所変数 1 = 長さ・2 = i・3 = 結果・4 = 書く場所・5 = バイト）
fn escape_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: escape_fn(p: prog_empty(), cg: cg_new())) == 0
do
  let one: Str = join(parts: ["block EMPTY localGet 0 localGet 2 i32Add i32Load8u 4 localSet 5", esc_t(c: 38, text: "&amp;"), esc_t(c: 60, text: "&lt;"), esc_t(c: 62, text: "&gt;"), esc_t(c: 34, text: "&quot;"), esc_t(c: 39, text: "&#39;"), "localGet 4 localGet 5 i32Store8 0 localGet 4 i32 1 i32Add localSet 4 end"], by: " ")
  sym_gen(p: p, cg: cg, key: "escape html", params: [127], results: [127], locals: i32s(n: 5), needs: [], text: join(parts: ["localGet 0 i32Load 0 localSet 1 localGet 1 i32 6 i32Mul i32 4 i32Add call $alloc localSet 3 localGet 3 i32 4 i32Add localSet 4", each_t(i: 2, n: 1, body: one), "localGet 3 localGet 4 localGet 3 i32Sub i32 4 i32Sub i32Store 0 localGet 3"], by: " "))
end

fn esc_t(c: Int, text: Str) -> Str
  ensures true
  example str_len(text: esc_t(c: 38, text: "&amp;")) > 0
do
  "localGet 5 i32 " ++ n2s(n: c) ++ " i32Eq if EMPTY " ++ join(parts: map(list: utf8(text: text), func: esc_byte), by: " ") ++ " br 1 end"
end

fn esc_byte(c: Int) -> Str
  ensures true
  example esc_byte(c: 38) == "localGet 4 i32 38 i32Store8 0 localGet 4 i32 1 i32Add localSet 4"
do
  "localGet 4 i32 " ++ n2s(n: c) ++ " i32Store8 0 localGet 4 i32 1 i32Add localSet 4"
end

# Sql の表示：型紙 -- params: ["a","b"]（局所変数 1 = 数・2 = i・3 = つないだ文字・4 = 値の並び）
fn show_sql_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: show_sql_fn(p: prog_empty(), cg: cg_new())) == 0
do
  sym_gen(p: p, cg: cg, key: "show Sql", params: [127], results: [127], locals: i32s(n: 4), needs: ["S1|s| -- params: [", "C|s|,", "Q|g|quote", "RB|s|]"], text: join(parts: ["localGet 0 i32Load 0 localSet 3", sql_cat(code: "i32 $S1"), "localGet 0 i32Load 4 localTee 4 i32Load 0 localSet 1", each_t(i: 2, n: 1, body: "localGet 2 if EMPTY " ++ sql_cat(code: "i32 $C") ++ " end " ++ sql_cat(code: elem_t(l: 4, i: 2) ++ " i32Load 8 call $Q")), sql_cat(code: "i32 $RB"), "localGet 3"], by: " "))
end

fn sql_cat(code: Str) -> Str
  ensures true
  example sql_cat(code: "i32 1") == "localGet 3 i32 1 call $concat localSet 3"
do
  "localGet 3 " ++ code ++ " call $concat localSet 3"
end

# 文字の from 文字めが何バイトめか。範囲の外なら -1（局所変数 2 = 長さ・3 = バイトの場所・4 = 文字の数（i64）・5 = バイト）
fn cp_offset_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: cp_offset_fn(p: prog_empty(), cg: cg_new())) == 0
do
  sym_gen(p: p, cg: cg, key: "cp offset", params: [127, 126], results: [127], locals: [127, 127, 126, 127], needs: [], text: "localGet 1 i64 0 i64LtS if EMPTY i32 -1 return end localGet 0 i32Load 0 localSet 2 block EMPTY loop EMPTY localGet 4 localGet 1 i64Eq if EMPTY localGet 3 return end localGet 3 localGet 2 i32GeU brIf 1 localGet 3 i32 1 i32Add localSet 3 block EMPTY loop EMPTY localGet 3 localGet 2 i32GeU brIf 1 localGet 0 localGet 3 i32Add i32Load8u 4 localTee 5 i32 192 i32And i32 128 i32Ne brIf 1 localGet 3 i32 1 i32Add localSet 3 br 0 end end localGet 4 i64 1 i64Add localSet 4 br 0 end end i32 -1")
end

# 1文字の文字から、その文字のコード。1文字でなければ -1（局所変数 1 = 長さ・2 = 先頭のバイト・3 = バイト数）
fn code_of_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: code_of_fn(p: prog_empty(), cg: cg_new())) == 0
do
  let c1: Str = "localGet 0 i32Load8u 5 i32 63 i32And"
  let c2: Str = "localGet 0 i32Load8u 6 i32 63 i32And"
  let c3: Str = "localGet 0 i32Load8u 7 i32 63 i32And"
  sym_gen(p: p, cg: cg, key: "code of", params: [127], results: [126], locals: i32s(n: 3), needs: [], text: join(parts: ["localGet 0 i32Load 0 localTee 1 i32Eqz if EMPTY i64 -1 return end localGet 0 i32Load8u 4 localTee 2 i32 128 i32LtU if I32 i32 1 else localGet 2 i32 224 i32LtU if I32 i32 2 else localGet 2 i32 240 i32LtU if I32 i32 3 else i32 4 end end end localTee 3 localGet 1 i32Ne if EMPTY i64 -1 return end localGet 3 i32 1 i32Eq if EMPTY localGet 2 i64ExtendI32U return end localGet 3 i32 2 i32Eq if EMPTY localGet 2 i32 31 i32And i32 6 i32Shl", c1, "i32Or i64ExtendI32U return end localGet 3 i32 3 i32Eq if EMPTY localGet 2 i32 15 i32And i32 12 i32Shl", c1, "i32 6 i32Shl i32Or", c2, "i32Or i64ExtendI32U return end localGet 2 i32 7 i32And i32 18 i32Shl", c1, "i32 12 i32Shl i32Or", c2, "i32 6 i32Shl i32Or", c3, "i32Or i64ExtendI32U"], by: " "))
end

# コードから1文字の文字（UTF-8 で 1〜4 バイト）（局所変数 1 = コード・2 = 結果）
fn char_of_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: char_of_fn(p: prog_empty(), cg: cg_new())) == 0
do
  sym_gen(p: p, cg: cg, key: "char of", params: [126], results: [127], locals: i32s(n: 2), needs: [], text: join(parts: ["localGet 0 i32WrapI64 localSet 1 localGet 1 i32 128 i32LtU if EMPTY", co_mk(n: 1), co_put(k: 0, code: "localGet 1"), "localGet 2 return end localGet 1 i32 2048 i32LtU if EMPTY", co_mk(n: 2), co_put(k: 0, code: co_bits(sh: 6, mask: 31, lead: 192)), co_put(k: 1, code: co_bits(sh: 0, mask: 63, lead: 128)), "localGet 2 return end localGet 1 i32 65536 i32LtU if EMPTY", co_mk(n: 3), co_put(k: 0, code: co_bits(sh: 12, mask: 15, lead: 224)), co_put(k: 1, code: co_bits(sh: 6, mask: 63, lead: 128)), co_put(k: 2, code: co_bits(sh: 0, mask: 63, lead: 128)), "localGet 2 return end", co_mk(n: 4), co_put(k: 0, code: co_bits(sh: 18, mask: 7, lead: 240)), co_put(k: 1, code: co_bits(sh: 12, mask: 63, lead: 128)), co_put(k: 2, code: co_bits(sh: 6, mask: 63, lead: 128)), co_put(k: 3, code: co_bits(sh: 0, mask: 63, lead: 128)), "localGet 2"], by: " "))
end

fn co_mk(n: Int) -> Str
  ensures true
  example co_mk(n: 1) == "i32 5 call $alloc localTee 2 i32 1 i32Store 0"
do
  "i32 " ++ n2s(n: 4 + n) ++ " call $alloc localTee 2 i32 " ++ n2s(n: n) ++ " i32Store 0"
end

fn co_put(k: Int, code: Str) -> Str
  ensures true
  example co_put(k: 0, code: "x") == "localGet 2 x i32Store8 4"
do
  "localGet 2 " ++ code ++ " i32Store8 " ++ n2s(n: 4 + k)
end

fn co_bits(sh: Int, mask: Int, lead: Int) -> Str
  ensures true
  example co_bits(sh: 0, mask: 63, lead: 128) == "localGet 1 i32 63 i32And i32 128 i32Or"
do
  "localGet 1 " ++ if sh > 0 then "i32 " ++ n2s(n: sh) ++ " i32ShrU " else "" end ++ "i32 " ++ n2s(n: mask) ++ " i32And i32 " ++ n2s(n: lead) ++ " i32Or"
end

# ---- 文字の組み込み ----

fn text_builtin(p: Prog, cg: Cg, scope: Dict[Int], e: Node) -> BC
  ensures true
  example len(list: bc_code(b: text_builtin(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "call", text: "chars", kids: [])))) > 0
do
  let b: LB = LB(p: p, scope: scope, e: e, el: tk(k: "Int"), l: 0, n: 0, i: 0, set: [])
  let name: Str = n_text(n: e)
  when
    name == "chars" then tb_one(b: b, a: lb_arg(b: b, cg: cg, name: "text"), f: "chars")
    name == "split" then tb_split(b: b, by: cg_local(cg: cg, t: 127))
    name == "join" then tb_join(b: b, cg: cg, first: "parts", second: "by")
    name == "contains" then tb_contains(b: b, cg: cg)
    name == "starts_with" or name == "ends_with" then tb_starts(b: b, cg: cg)
    name == "lines" then tb_one(b: b, a: lb_arg(b: b, cg: cg, name: "text"), f: "lines")
    name == "html_text" then tb_one(b: b, a: lb_arg(b: b, cg: cg, name: "value"), f: "escape html")
    name == "html_join" then tb_join(b: b, cg: cg, first: "parts", second: "")
    name == "html" or name == "sql" then tb_template(b: b, vs: cg_local(cg: cg, t: 127))
    name == "trim" then tb_one(b: b, a: lb_arg(b: b, cg: cg, name: "text"), f: "trim")
    name == "parse_int" then tb_one(b: b, a: lb_arg(b: b, cg: cg, name: "text"), f: "parse_int")
    name == "slice" then tb_slice(b: b, cg: cg)
    name == "code_of" then tb_code_of(b: b, c: cg_local(cg: cg, t: 126))
    name == "char_of" then tb_char_of(b: b, c: cg_local(cg: cg, t: 126))
    else BC(code: [], cg: unsupported(cg: cg, what: "the built-in function " ++ name, n: e))
  end
end

# 値を作ってから、名前の手伝いの関数を呼ぶ
fn tb_one(b: LB, a: BC, f: Str) -> BC
  ensures true
  example len(list: bc_code(b: tb_one(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), el: tk(k: "Int"), l: 0, n: 0, i: 0, set: []), a: BC(code: [], cg: cg_new()), f: "trim"))) == 2
do
  call_gen(p: lb_p(b: b), code: bc_code(b: a), g: text_gen(p: lb_p(b: b), cg: bc_cg(b: a), name: f))
end

fn text_gen(p: Prog, cg: Cg, name: Str) -> At
  ensures true
  example at_at(a: text_gen(p: prog_empty(), cg: cg_new(), name: "nope")) == 0
do
  when
    name == "chars" then chars_fn(p: p, cg: cg)
    name == "lines" then lines_fn(p: p, cg: cg)
    name == "escape html" then escape_fn(p: p, cg: cg)
    name == "trim" then trim_fn(p: p, cg: cg)
    name == "parse_int" then parse_int_fn(p: p, cg: cg)
    name == "split" then split_fn(p: p, cg: cg)
    name == "join" then join_fn(p: p, cg: cg)
    name == "index of" then index_of_fn(p: p, cg: cg)
    name == "match at" then match_at_fn(p: p, cg: cg)
    name == "code of" then code_of_fn(p: p, cg: cg)
    name == "char of" then char_of_fn(p: p, cg: cg)
    else At(at: 0, cg: cg)
  end
end

fn tb_split(b: LB, by: At) -> BC
  ensures true
  example len(list: bc_code(b: tb_split(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "split", kids: []), el: tk(k: "Int"), l: 0, n: 0, i: 0, set: []), by: At(at: 0, cg: cg_new())))) > 0
do
  let t: BC = lb_arg(b: b, cg: at_cg(a: by), name: "text")
  let y: BC = lb_arg(b: b, cg: bc_cg(b: t), name: "by")
  let fl: BC = lb_fail(b: b, cg: bc_cg(b: y), code: "R506", message: "split needs a non-empty separator")
  let g: At = split_fn(p: lb_p(b: b), cg: bc_cg(b: fl))
  let ys: Str = n2s(n: at_at(a: by))
  BC(code: concat(lists: [bc_code(b: t), bc_code(b: y), lb_t(b: b, text: "localTee " ++ ys ++ " i32Load 0 i32Eqz if EMPTY"), bc_code(b: fl), lb_t(b: b, text: "end localGet " ++ ys ++ " call " ++ n2s(n: at_at(a: g)))]), cg: at_cg(a: g))
end

# join(parts, by)。html_join は by が "" の文字
fn tb_join(b: LB, cg: Cg, first: Str, second: Str) -> BC
  ensures true
  example len(list: bc_code(b: tb_join(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "html_join", kids: []), el: tk(k: "Int"), l: 0, n: 0, i: 0, set: []), cg: cg_new(), first: "parts", second: ""))) > 0
do
  let a: BC = lb_arg(b: b, cg: cg, name: first)
  let s: BC = if second == "" then str_code(p: lb_p(b: b), cg: bc_cg(b: a), text: "") else lb_arg(b: b, cg: bc_cg(b: a), name: second) end
  call_gen(p: lb_p(b: b), code: bc_code(b: a) ++ bc_code(b: s), g: join_fn(p: lb_p(b: b), cg: bc_cg(b: s)))
end

fn tb_contains(b: LB, cg: Cg) -> BC
  ensures true
  example len(list: bc_code(b: tb_contains(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "contains", kids: []), el: tk(k: "Int"), l: 0, n: 0, i: 0, set: []), cg: cg_new()))) > 0
do
  let t: BC = lb_arg(b: b, cg: cg, name: "text")
  let x: BC = lb_arg(b: b, cg: bc_cg(b: t), name: "part")
  let g: At = index_of_fn(p: lb_p(b: b), cg: bc_cg(b: x))
  BC(code: concat(lists: [bc_code(b: t), bc_code(b: x), lb_t(b: b, text: "i32 0 call " ++ n2s(n: at_at(a: g)) ++ " i32 0 i32GeS")]), cg: at_cg(a: g))
end

fn tb_starts(b: LB, cg: Cg) -> BC
  ensures true
  example len(list: bc_code(b: tb_starts(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "starts_with", kids: []), el: tk(k: "Int"), l: 0, n: 0, i: 0, set: []), cg: cg_new()))) > 0
do
  let tl: At = cg_local(cg: cg, t: 127)
  let xl: At = cg_local(cg: at_cg(a: tl), t: 127)
  let starts: Bool = n_text(n: lb_e(b: b)) == "starts_with"
  let t: BC = lb_arg(b: b, cg: at_cg(a: xl), name: "text")
  let x: BC = lb_arg(b: b, cg: bc_cg(b: t), name: if starts then "prefix" else "suffix" end)
  let g: At = match_at_fn(p: lb_p(b: b), cg: bc_cg(b: x))
  let ts: Str = n2s(n: at_at(a: tl))
  let xs: Str = n2s(n: at_at(a: xl))
  let where: Str = if starts then "localGet " ++ ts ++ " i32 0" else "localGet " ++ ts ++ " localGet " ++ ts ++ " i32Load 0 localGet " ++ xs ++ " i32Load 0 i32Sub" end
  BC(code: concat(lists: [bc_code(b: t), lb_t(b: b, text: "localSet " ++ ts), bc_code(b: x), lb_t(b: b, text: "localSet " ++ xs ++ " " ++ where ++ " localGet " ++ xs ++ " call " ++ n2s(n: at_at(a: g)))]), cg: at_cg(a: g))
end

# html・sql：型紙は書いたままの文字なので、穴の数はコンパイルのときにわかる
fn tb_template(b: LB, vs: At) -> BC
  ensures true
  example len(list: bc_code(b: tb_template(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "html", kids: []), el: tk(k: "Int"), l: 0, n: 0, i: 0, set: []), vs: At(at: 0, cg: cg_new())))) > 0
do
  let is_html: Bool = n_text(n: lb_e(b: b)) == "html"
  let hole: Str = if is_html then "{}" else "?" end
  let tmpl: Str = n_text(n: arg_value(e: lb_e(b: b), name: "template"))
  let parts: List[Str] = split(text: tmpl, by: hole)
  let holes: Int = len(list: parts) - 1
  let v: BC = lb_arg(b: b, cg: at_cg(a: vs), name: "values")
  let fl: BC = lb_fail(b: b, cg: bc_cg(b: v), code: "R510", message: "the template has " ++ n2s(n: holes) ++ " hole(s) '" ++ hole ++ "' but a different number of values were given")
  let ys: Str = n2s(n: at_at(a: vs))
  let check: List[Int] = concat(lists: [bc_code(b: v), lb_t(b: b, text: "localTee " ++ ys ++ " i32Load 0 i32 " ++ n2s(n: holes) ++ " i32Ne if EMPTY"), bc_code(b: fl), lb_t(b: b, text: "end")])
  if is_html then
    let e0: At = cg_str(cg: bc_cg(b: fl), text: "")
    let p0: At = cg_str(cg: at_cg(a: e0), text: ttl_first(parts: parts))
    match fold(list: drop(list: parts, count: 1), init: HT(p: lb_p(b: b), vs: at_at(a: vs), i: 0, b: BC(code: check ++ lb_t(b: b, text: "i32 " ++ n2s(n: at_at(a: e0)) ++ " i32 " ++ n2s(n: at_at(a: p0)) ++ " call $concat"), cg: at_cg(a: p0))), func: ht_step)
      case HT(p: _, vs: _, i: _, b: done) then done
    end
  else
    let pl: At = cg_local(cg: bc_cg(b: fl), t: 127)
    let s: At = cg_str(cg: at_cg(a: pl), text: tmpl)
    let ps: Str = n2s(n: at_at(a: pl))
    BC(code: check ++ lb_t(b: b, text: "i32 8 call $alloc localTee " ++ ps ++ " i32 " ++ n2s(n: at_at(a: s)) ++ " i32Store 0 localGet " ++ ps ++ " localGet " ++ ys ++ " i32Store 4 localGet " ++ ps), cg: at_cg(a: s))
  end
end

fn ttl_first(parts: List[Str]) -> Str
  ensures true
  example ttl_first(parts: []) == ""
do
  if parts == [] then "" else get(list: parts, index: 0) end
end

type HT
  case HT(p: Prog, vs: Int, i: Int, b: BC)
end

fn ht_step(acc: HT, part: Str) -> HT
  ensures true
  example len(list: bc_code(b: ht_b(h: ht_step(acc: HT(p: prog_empty(), vs: 0, i: 0, b: BC(code: [], cg: cg_new())), part: "x")))) > 0
do
  match acc
    case HT(p: p, vs: vs, i: i, b: b) then HT(p: p, vs: vs, i: i + 1, b: ht_part(p: p, b: b, vs: vs, i: i, s: cg_str(cg: bc_cg(b: b), text: part)))
  end
end

fn ht_part(p: Prog, b: BC, vs: Int, i: Int, s: At) -> BC
  ensures true
  example len(list: bc_code(b: ht_part(p: prog_empty(), b: BC(code: [], cg: cg_new()), vs: 0, i: 0, s: At(at: 48, cg: cg_new())))) > 0
do
  BC(code: bc_code(b: b) ++ pasm(p: p, text: "localGet " ++ n2s(n: vs) ++ " i32Load " ++ n2s(n: 8 + 8 * i) ++ " call $concat i32 " ++ n2s(n: at_at(a: s)) ++ " call $concat"), cg: at_cg(a: s))
end

fn ht_b(h: HT) -> BC
  ensures true
  example bc_code(b: ht_b(h: HT(p: prog_empty(), vs: 0, i: 0, b: BC(code: [1], cg: cg_new())))) == [1]
do
  match h
    case HT(p: _, vs: _, i: _, b: b) then b
  end
end

# slice：文字の番号をバイトの場所にしてから切り出す。範囲の外なら R506
fn tb_slice(b: LB, cg: Cg) -> BC
  ensures true
  example len(list: bc_code(b: tb_slice(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "slice", kids: []), el: tk(k: "Int"), l: 0, n: 0, i: 0, set: []), cg: cg_new()))) > 0
do
  let t: At = cg_local(cg: cg, t: 127)
  let c4: Cg = at_cg(a: cg_local(cg: at_cg(a: cg_local(cg: at_cg(a: cg_local(cg: at_cg(a: cg_local(cg: at_cg(a: t), t: 127)), t: 127)), t: 126)), t: 126))
  let k: Int = at_at(a: t)
  let tv: BC = lb_arg(b: b, cg: c4, name: "text")
  let fv: BC = lb_arg(b: b, cg: bc_cg(b: tv), name: "from")
  let uv: BC = lb_arg(b: b, cg: bc_cg(b: fv), name: "to")
  let co: At = cp_offset_fn(p: lb_p(b: b), cg: bc_cg(b: uv))
  let fl: BC = lb_fail(b: b, cg: at_cg(a: co), code: "R506", message: "slice is out of range")
  let sl: At = slice_fn(p: lb_p(b: b), cg: bc_cg(b: fl))
  let c: Str = n2s(n: at_at(a: co))
  let ts: Str = n2s(n: k)
  let a: Str = n2s(n: k + 1)
  let z: Str = n2s(n: k + 2)
  let f: Str = n2s(n: k + 3)
  let u: Str = n2s(n: k + 4)
  BC(code: concat(lists: [bc_code(b: tv), lb_t(b: b, text: "localSet " ++ ts), bc_code(b: fv), lb_t(b: b, text: "localSet " ++ f), bc_code(b: uv), lb_t(b: b, text: join(parts: ["localSet", u, "localGet", ts, "localGet", f, "call", c, "localSet", a, "localGet", ts, "localGet", u, "call", c, "localSet", z, "localGet", a, "i32 0 i32LtS localGet", z, "i32 0 i32LtS i32Or localGet", f, "localGet", u, "i64GtS i32Or if EMPTY"], by: " ")), bc_code(b: fl), lb_t(b: b, text: join(parts: ["end localGet", ts, "localGet", a, "localGet", z, "call", n2s(n: at_at(a: sl))], by: " "))]), cg: at_cg(a: sl))
end

fn tb_code_of(b: LB, c: At) -> BC
  ensures true
  example len(list: bc_code(b: tb_code_of(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "code_of", kids: []), el: tk(k: "Int"), l: 0, n: 0, i: 0, set: []), c: At(at: 0, cg: cg_new())))) > 0
do
  let a: BC = lb_arg(b: b, cg: at_cg(a: c), name: "char")
  let g: At = code_of_fn(p: lb_p(b: b), cg: bc_cg(b: a))
  let fl: BC = lb_fail(b: b, cg: at_cg(a: g), code: "R506", message: "code_of needs exactly one character")
  let cs: Str = n2s(n: at_at(a: c))
  BC(code: concat(lists: [bc_code(b: a), lb_t(b: b, text: "call " ++ n2s(n: at_at(a: g)) ++ " localTee " ++ cs ++ " i64 0 i64LtS if EMPTY"), bc_code(b: fl), lb_t(b: b, text: "end localGet " ++ cs)]), cg: bc_cg(b: fl))
end

fn tb_char_of(b: LB, c: At) -> BC
  ensures true
  example len(list: bc_code(b: tb_char_of(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "char_of", kids: []), el: tk(k: "Int"), l: 0, n: 0, i: 0, set: []), c: At(at: 0, cg: cg_new())))) > 0
do
  let a: BC = lb_arg(b: b, cg: at_cg(a: c), name: "code")
  let fl: BC = lb_fail(b: b, cg: bc_cg(b: a), code: "R506", message: "not a character code")
  let g: At = char_of_fn(p: lb_p(b: b), cg: bc_cg(b: fl))
  let cs: Str = n2s(n: at_at(a: c))
  BC(code: concat(lists: [bc_code(b: a), lb_t(b: b, text: join(parts: ["localTee", cs, "i64 0 i64LtS localGet", cs, "i64 1114111 i64GtS i32Or localGet", cs, "i64 55296 i64GeS localGet", cs, "i64 57343 i64LeS i32And i32Or if EMPTY"], by: " ")), bc_code(b: fl), lb_t(b: b, text: "end localGet " ++ cs ++ " call " ++ n2s(n: at_at(a: g)))]), cg: at_cg(a: g))
end

# ---- ファイル（Folder・OutFolder。WASI の preopen の「read」「write」） ----

# パスの確かめ（インタプリタの checkPath と同じ）。strict（書くとき）は空の段と . の段も 0
# 局所変数 2 = 長さ・3 = i・4 = 段の始まり・5 = バイト・6 = 段の長さ
fn path_ok_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: path_ok_fn(p: prog_empty(), cg: cg_new())) == 0
do
  sym_gen(p: p, cg: cg, key: "path ok", params: [127, 127], results: [127], locals: i32s(n: 5), needs: [], text: join(parts: ["localGet 0 i32Load 0 localSet 2 localGet 2 i32Eqz if EMPTY i32 0 return end", po_byte(pos: "i32 0"), "i32 47 i32Eq if EMPTY i32 0 return end localGet 2 i32 2 i32GeU if EMPTY", po_byte(pos: "i32 1"), "i32 58 i32Eq", po_byte(pos: "i32 0"), "i32 32 i32Or i32 97 i32Sub i32 26 i32LtU i32And if EMPTY i32 0 return end end i32 0 localSet 4 i32 0 localSet 3 block EMPTY loop EMPTY localGet 3 localGet 2 i32Eq if I32 i32 1 else", po_byte(pos: "localGet 3"), "localTee 5 i32 92 i32Eq localGet 5 i32Eqz i32Or if EMPTY i32 0 return end localGet 5 i32 47 i32Eq end if EMPTY localGet 3 localGet 4 i32Sub localTee 6 i32 2 i32Eq if EMPTY", po_byte(pos: "localGet 4"), "i32 46 i32Eq", po_byte(pos: "localGet 4 i32 1 i32Add"), "i32 46 i32Eq i32And if EMPTY i32 0 return end end localGet 1 if EMPTY localGet 6 i32Eqz if EMPTY i32 0 return end localGet 6 i32 1 i32Eq if EMPTY", po_byte(pos: "localGet 4"), "i32 46 i32Eq if EMPTY i32 0 return end end end localGet 3 i32 1 i32Add localSet 4 end localGet 3 localGet 2 i32GeU brIf 1 localGet 3 i32 1 i32Add localSet 3 br 0 end end i32 1"], by: " "))
end

fn po_byte(pos: Str) -> Str
  ensures true
  example po_byte(pos: "i32 0") == "localGet 0 i32 0 i32Add i32Load8u 4"
do
  "localGet 0 " ++ pos ++ " i32Add i32Load8u 4"
end

# パスの段を前から1つずつ、リンクをたどらずに調べ、リンクがあれば 1（局所変数 2 = 長さ・3 = i・4 = 調べた結果を置く場所）
fn link_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: link_fn(p: prog_empty(), cg: cg_new())) == 0
do
  sym_gen(p: p, cg: cg, key: "link on the way", params: [127, 127], results: [127], locals: i32s(n: 3), needs: [], text: join(parts: ["i32 64 call $alloc localSet 4 localGet 1 i32Load 0 localSet 2", each_t(i: 3, n: 2, body: "localGet 1 localGet 3 i32Add i32Load8u 4 i32 47 i32Eq if EMPTY " ++ link_stat(size: "localGet 3") ++ " end"), link_stat(size: "localGet 2"), "i32 0"], by: " "))
end

fn link_stat(size: Str) -> Str
  ensures true
  example str_len(text: link_stat(size: "localGet 3")) > 0
do
  "localGet 0 i32 0 localGet 1 i32 4 i32Add " ++ size ++ " localGet 4 call $pathFilestat if EMPTY i32 0 return end localGet 4 i32Load8u 16 i32 7 i32Eq if EMPTY i32 1 return end"
end

# 正しい UTF-8 なら 1（局所変数 1 = 長さ・2 = i・3 = バイト・4 = 続きの数・5・6 = 2バイトめの範囲・7 = k）
fn utf8_ok_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: utf8_ok_fn(p: prog_empty(), cg: cg_new())) == 0
do
  let rules: Str = join(parts: [u8_rule(a: 194, z: 223, nd: 1, l: 128, h: 191), u8_rule(a: 224, z: 224, nd: 2, l: 160, h: 191), u8_rule(a: 225, z: 236, nd: 2, l: 128, h: 191), u8_rule(a: 237, z: 237, nd: 2, l: 128, h: 159), u8_rule(a: 238, z: 239, nd: 2, l: 128, h: 191), u8_rule(a: 240, z: 240, nd: 3, l: 144, h: 191), u8_rule(a: 241, z: 243, nd: 3, l: 128, h: 191), u8_rule(a: 244, z: 244, nd: 3, l: 128, h: 143), "i32 0 return end end end end end end end end"], by: " ")
  sym_gen(p: p, cg: cg, key: "utf8 ok", params: [127], results: [127], locals: i32s(n: 7), needs: [], text: join(parts: ["localGet 0 i32Load 0 localSet 1 block EMPTY loop EMPTY localGet 2 localGet 1 i32GeU brIf 1", po_byte(pos: "localGet 2"), "localTee 3 i32 128 i32LtU if EMPTY localGet 2 i32 1 i32Add localSet 2 br 1 end", rules, "localGet 2 localGet 4 i32Add localGet 1 i32GeU if EMPTY i32 0 return end", po_byte(pos: "localGet 2 i32 1 i32Add"), "localTee 3 localGet 5 i32LtU localGet 3 localGet 6 i32GtU i32Or if EMPTY i32 0 return end i32 2 localSet 7 block EMPTY loop EMPTY localGet 7 localGet 4 i32GtU brIf 1", po_byte(pos: "localGet 2 localGet 7 i32Add"), "i32 192 i32And i32 128 i32Ne if EMPTY i32 0 return end localGet 7 i32 1 i32Add localSet 7 br 0 end end localGet 2 localGet 4 i32Add i32 1 i32Add localSet 2 br 0 end end i32 1"], by: " "))
end

fn u8_rule(a: Int, z: Int, nd: Int, l: Int, h: Int) -> Str
  ensures true
  example u8_rule(a: 194, z: 223, nd: 1, l: 128, h: 191) == "localGet 3 i32 194 i32Sub i32 30 i32LtU if EMPTY i32 1 localSet 4 i32 128 localSet 5 i32 191 localSet 6 else"
do
  join(parts: ["localGet 3 i32", n2s(n: a), "i32Sub i32", n2s(n: z - a + 1), "i32LtU if EMPTY i32", n2s(n: nd), "localSet 4 i32", n2s(n: l), "localSet 5 i32", n2s(n: h), "localSet 6 else"], by: " ")
end

# Err(message: "'" ++ パス ++ 後ろ) を作って返す（局所変数 tmp・Err の番号）
fn file_err(tmp: Int, err: Int, pre: Str, post: Str) -> Str
  ensures true
  example str_len(text: file_err(tmp: 6, err: 1, pre: "$Q", post: "$NE")) > 0
do
  join(parts: ["i32 16 call $alloc localTee", n2s(n: tmp), "i32", n2s(n: err), "i32Store 0 localGet", n2s(n: tmp), "i32", pre, "localGet 0 call $concat i32", post, "call $concat i32Store 8 localGet", n2s(n: tmp), "return"], by: " ")
end

# write_text(path, text) -> Result[Unit] の場所。パスがおかしければ 0、外を指すなら 1
# 局所変数 2 = エラーの番号・3 = fd・4 = 書いた数・5 = 長さ・6 = 作る値
fn write_text_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: write_text_fn(p: prog_empty(), cg: cg_new())) == 0
do
  let err: Int = cvar_index(v: cvar_of(p: p, name: "Err"))
  let cant: Str = file_err(tmp: 6, err: err, pre: "$Q", post: "$CW")
  sym_gen(p: p, cg: cg, key: "write_text", params: [127, 127], results: [127], locals: i32s(n: 5), needs: ["Q|s|'", "CW|s|' could not be written", "PO|g|path ok", "LW|g|link on the way", "FO|s|the folder of '", "NE|s|' does not exist", "NF|s|' is not a file"], text: join(parts: ["localGet 0 i32 1 call $PO i32Eqz if EMPTY i32 0 return end globalGet $writeFd localGet 0 call $LW if EMPTY i32 1 return end globalGet $writeFd i32 0 localGet 0 i32 4 i32Add localGet 0 i32Load 0 i32 9 i64 64 i64 0 i32 0 i32 16 call $pathOpen localTee 2 if EMPTY localGet 2 i32 76 i32Eq localGet 2 i32 63 i32Eq i32Or localGet 2 i32 32 i32Eq i32Or if EMPTY i32 1 return end localGet 2 i32 44 i32Eq if EMPTY", file_err(tmp: 6, err: err, pre: "$FO", post: "$NE"), "end localGet 2 i32 31 i32Eq if EMPTY", file_err(tmp: 6, err: err, pre: "$Q", post: "$NF"), "end", cant, "end i32 16 i32Load 0 localSet 3 i32 0 localSet 4 localGet 1 i32Load 0 localSet 5 block EMPTY loop EMPTY localGet 4 localGet 5 i32GeU brIf 1 i32 0 localGet 1 i32 4 i32Add localGet 4 i32Add i32Store 0 i32 0 localGet 5 localGet 4 i32Sub i32Store 4 localGet 3 i32 0 i32 1 i32 24 call $fdWrite i32 24 i32Load 0 i32Eqz i32Or if EMPTY localGet 3 call $fdClose drop", cant, "end localGet 4 i32 24 i32Load 0 i32Add localSet 4 br 0 end end localGet 3 call $fdClose if EMPTY", cant, "end i32 16 call $alloc localTee 6 i32", n2s(n: cvar_index(v: cvar_of(p: p, name: "Ok"))), "i32Store 0 localGet 6"], by: " "))
end

# read_text(path) -> Result[Str] の場所。パスがおかしければ 0、外を指すなら 1
# 局所変数 1 = 長さ・2 = エラーの番号・3 = fd・4 = 読む場所・5 = 取った大きさ・6 = 読んだ数・7 = 一度に読んだ数・8 = 作る値
fn read_text_fn(p: Prog, cg: Cg) -> At
  ensures true
  example at_at(a: read_text_fn(p: prog_empty(), cg: cg_new())) == 2
do
  let uo: At = utf8_ok_fn(p: p, cg: cg)
  let sl: At = slice_fn(p: p, cg: at_cg(a: uo))
  let err: Int = cvar_index(v: cvar_of(p: p, name: "Err"))
  let nf: Str = file_err(tmp: 8, err: err, pre: "$Q", post: "$NF")
  let bad_utf: Str = file_err(tmp: 8, err: err, pre: "$Q", post: "$UTF")
  sym_gen(p: p, cg: at_cg(a: sl), key: "read_text", params: [127], results: [127], locals: i32s(n: 8), needs: ["PO|g|path ok", "LW|g|link on the way", "Q|s|'", "DNE|s|' does not exist", "NF|s|' is not a file", "UTF|s|' could not be read as UTF-8 text"], text: join(parts: ["localGet 0 i32Load 0 localSet 1 localGet 0 i32 0 call $PO i32Eqz if EMPTY i32 0 return end globalGet $readFd localGet 0 call $LW if EMPTY i32 1 return end globalGet $readFd i32 0 localGet 0 i32 4 i32Add localGet 1 i32 0 i64 2097154 i64 0 i32 0 i32 16 call $pathOpen localTee 2 if EMPTY localGet 2 i32 76 i32Eq localGet 2 i32 63 i32Eq i32Or if EMPTY i32 1 return end localGet 2 i32 44 i32Eq if EMPTY", file_err(tmp: 8, err: err, pre: "$Q", post: "$DNE"), "end localGet 2 i32 31 i32Eq localGet 2 i32 54 i32Eq i32Or if EMPTY", nf, "end", bad_utf, "end i32 16 i32Load 0 localSet 3 i32 64 call $alloc localSet 7 localGet 3 localGet 7 call $fdFilestat localGet 7 i32Load8u 16 i32 4 i32Ne i32Or if EMPTY localGet 3 call $fdClose drop", nf, "end i32 65540 call $alloc localSet 4 i32 65536 localSet 5 block EMPTY loop EMPTY localGet 6 localGet 5 i32Eq if EMPTY i32 65536 call $alloc drop localGet 5 i32 65536 i32Add localSet 5 end i32 0 localGet 4 i32 4 i32Add localGet 6 i32Add i32Store 0 i32 0 localGet 5 localGet 6 i32Sub i32Store 4 localGet 3 i32 0 i32 1 i32 24 call $fdRead localTee 2 if EMPTY localGet 3 call $fdClose drop localGet 2 i32 31 i32Eq if EMPTY", nf, "end", bad_utf, "end i32 24 i32Load 0 localTee 7 i32Eqz brIf 1 localGet 6 localGet 7 i32Add localSet 6 br 0 end end localGet 3 call $fdClose drop localGet 4 localGet 6 i32Store 0 localGet 4 call", n2s(n: at_at(a: uo)), "i32Eqz if EMPTY", bad_utf, "end localGet 6 i32 3 i32GeU if EMPTY localGet 4 i32Load8u 4 i32 239 i32Eq localGet 4 i32Load8u 5 i32 187 i32Eq i32And localGet 4 i32Load8u 6 i32 191 i32Eq i32And if EMPTY localGet 4 i32 3 localGet 6 call", n2s(n: at_at(a: sl)), "localSet 4 end end i32 16 call $alloc localTee 8 i32", n2s(n: cvar_index(v: cvar_of(p: p, name: "Ok"))), "i32Store 0 localGet 8 localGet 4 i32Store 8 localGet 8"], by: " "))
end

# read_text・write_text・write_bytes
fn file_builtin(p: Prog, cg: Cg, scope: Dict[Int], e: Node) -> BC
  ensures true
  example len(list: bc_code(b: file_builtin(p: prog_empty(), cg: cg_new(), scope: no_ints(), e: bare(kind: "call", text: "read_text", kids: [])))) > 0
do
  let b: LB = LB(p: p, scope: scope, e: e, el: tk(k: "Int"), l: 0, n: 0, i: 0, set: [])
  let r: At = cg_local(cg: cg, t: 127)
  if n_text(n: e) == "read_text" then
    let path: BC = lb_arg(b: b, cg: at_cg(a: r), name: "path")
    let g: At = read_text_fn(p: p, cg: bc_cg(b: path))
    file_done(b: b, r: at_at(a: r), code: bc_code(b: path), g: g, first: "the path is not inside the folder")
  else
    let c5: Cg = at_cg(a: cg_local(cg: at_cg(a: cg_local(cg: at_cg(a: cg_local(cg: at_cg(a: cg_local(cg: at_cg(a: r), t: 127)), t: 127)), t: 127)), t: 127))
    let bl: At = cg_local(cg: c5, t: 126)
    let data: BC = if n_text(n: e) == "write_text" then lb_arg(b: b, cg: at_cg(a: bl), name: "text") else bytes_code(b: b, cg: at_cg(a: bl), k: at_at(a: r) + 1) end
    let path: BC = lb_arg(b: b, cg: bc_cg(b: data), name: "path")
    let g: At = write_text_fn(p: p, cg: bc_cg(b: path))
    file_done(b: b, r: at_at(a: r), code: bc_code(b: path) ++ bc_code(b: data), g: g, first: "the path is not a plain file path inside the folder")
  end
end

fn file_done(b: LB, r: Int, code: List[Int], g: At, first: Str) -> BC
  ensures true
  example len(list: bc_code(b: file_done(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "x", text: "", kids: []), el: tk(k: "Int"), l: 0, n: 0, i: 0, set: []), r: 0, code: [], g: At(at: 3, cg: cg_new()), first: "x"))) > 0
do
  let f1: BC = lb_fail(b: b, cg: at_cg(a: g), code: "R507", message: first)
  let f2: BC = lb_fail(b: b, cg: bc_cg(b: f1), code: "R507", message: "the path goes through a link")
  let rs: Str = n2s(n: r)
  BC(code: concat(lists: [code, lb_t(b: b, text: "call " ++ n2s(n: at_at(a: g)) ++ " localTee " ++ rs ++ " i32Eqz if EMPTY"), bc_code(b: f1), lb_t(b: b, text: "end localGet " ++ rs ++ " i32 1 i32Eq if EMPTY"), bc_code(b: f2), lb_t(b: b, text: "end localGet " ++ rs)]), cg: bc_cg(b: f2))
end

# write_bytes：Int のリストを、Str と同じ形（長さ＋バイト）にする。0〜255 でなければ R506（局所変数 k = L・k+1 = n・k+2 = i・k+3 = 結果・k+4 = バイト）
fn bytes_code(b: LB, cg: Cg, k: Int) -> BC
  ensures true
  example len(list: bc_code(b: bytes_code(b: LB(p: prog_empty(), scope: no_ints(), e: bare(kind: "call", text: "write_bytes", kids: []), el: tk(k: "Int"), l: 0, n: 0, i: 0, set: []), cg: cg_new(), k: 1))) > 0
do
  let xs: BC = lb_arg(b: b, cg: cg, name: "bytes")
  let fl: BC = lb_fail(b: b, cg: bc_cg(b: xs), code: "R506", message: "a byte is not between 0 and 255")
  let l: Str = n2s(n: k)
  let n: Str = n2s(n: k + 1)
  let buf: Str = n2s(n: k + 3)
  let x: Str = n2s(n: k + 4)
  let one: List[Int] = concat(lists: [lb_t(b: b, text: join(parts: [elem_t(l: k, i: k + 2), "i64Load 8 localTee", x, "i64 0 i64LtS localGet", x, "i64 255 i64GtS i32Or if EMPTY"], by: " ")), bc_code(b: fl), lb_t(b: b, text: join(parts: ["end localGet", buf, "localGet", n2s(n: k + 2), "i32Add localGet", x, "i32WrapI64 i32Store8 4"], by: " "))])
  BC(code: concat(lists: [bc_code(b: xs), lb_t(b: b, text: join(parts: ["localTee", l, "i32Load 0 localSet", n, "localGet", n, "i32 4 i32Add call $alloc localTee", buf, "localGet", n, "i32Store 0"], by: " ")), each_b(p: lb_p(b: b), i: k + 2, n: k + 1, body: one), lb_t(b: b, text: "localGet " ++ buf)]), cg: bc_cg(b: fl))
end

# 始めに、渡されたフォルダを名前で探す（fd 3 から。読むのは「read」、書くのは「write」という名前のもの）
fn find_preopens_text() -> Str
  ensures str_len(text: result) > 0
  example str_len(text: find_preopens_text()) > 100
do
  "i32 3 localSet 0 block EMPTY loop EMPTY localGet 0 i32 16 call $prestat brIf 1 localGet 0 i32 64 i32GtU brIf 1 i32 16 i32Load8u 0 i32Eqz i32 16 i32Load 4 i32 8 i32LeU i32And if EMPTY i32 24 i64 0 i64Store 0 localGet 0 i32 24 i32 16 i32Load 4 call $prestatName i32Eqz if EMPTY i32 16 i32Load 4 i32 4 i32Eq i32 24 i32Load 0 i32 1684104562 i32Eq i32And globalGet $readFd i32 0 i32LtS i32And if EMPTY localGet 0 globalSet $readFd end i32 16 i32Load 4 i32 5 i32Eq i32 24 i32Load 0 i32 1953067639 i32Eq i32And i32 24 i32Load8u 4 i32 101 i32Eq i32And globalGet $writeFd i32 0 i32LtS i32And if EMPTY localGet 0 globalSet $writeFd end end end localGet 0 i32 1 i32Add localSet 0 br 0 end end"
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
        case None then compile_with(fns: fns, types: types, tys: tys, folder: param_of(params: n_kids(n: kid_at(n: m, i: 0)), ty: "Folder"), out: param_of(params: n_kids(n: kid_at(n: m, i: 0)), ty: "OutFolder"))
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

# 型が ty の最初の引数（無ければ kind が none）
fn param_of(params: List[Node], ty: Str) -> Node
  ensures true
  example n_text(n: param_of(params: [bare(kind: "param", text: "f", kids: [bare(kind: "t", text: "Folder", kids: [])])], ty: "Folder")) == "f"
  example n_kind(n: param_of(params: [], ty: "Folder")) == "none"
do
  match fold(list: params, init: bare(kind: "none", text: ty, kids: []), func: param_pick)
    case Node(kind: k, text: t, line: l, col: c, kids: ks) then Node(kind: k, text: t, line: l, col: c, kids: ks)
  end
end

fn param_pick(acc: Node, prm: Node) -> Node
  ensures true
  example n_text(n: param_pick(acc: bare(kind: "none", text: "Folder", kids: []), prm: bare(kind: "param", text: "f", kids: [bare(kind: "t", text: "Folder", kids: [])]))) == "f"
do
  if n_kind(n: acc) == "none" and n_text(n: first_kid(n: prm)) == n_text(n: acc) then prm else acc end
end

# 取り込み：記号・WASI の名前・形
type Imp
  case Imp(key: Str, name: Str, params: List[Int], results: List[Int])
end

# ファイルに触るのは、main が Folder か OutFolder を受け取るときだけ。そのときも要るものだけを取り込む
fn import_list(folder: Bool, out: Bool) -> List[Imp]
  ensures len(list: result) >= 2
  example len(list: import_list(folder: false, out: false)) == 2
  example len(list: import_list(folder: true, out: false)) == 9
  example len(list: import_list(folder: false, out: true)) == 7
do
  let base: List[Imp] = [Imp(key: "fdWrite", name: "fd_write", params: [127, 127, 127, 127], results: [127]), Imp(key: "procExit", name: "proc_exit", params: [127], results: [])]
  let files: List[Imp] = [Imp(key: "prestat", name: "fd_prestat_get", params: [127, 127], results: [127]), Imp(key: "prestatName", name: "fd_prestat_dir_name", params: [127, 127, 127], results: [127]), Imp(key: "pathFilestat", name: "path_filestat_get", params: [127, 127, 127, 127, 127], results: [127]), Imp(key: "pathOpen", name: "path_open", params: [127, 127, 127, 127, 127, 126, 126, 127, 127], results: [127])]
  let reads: List[Imp] = [Imp(key: "fdFilestat", name: "fd_filestat_get", params: [127, 127], results: [127]), Imp(key: "fdRead", name: "fd_read", params: [127, 127, 127, 127], results: [127])]
  if folder or out then concat(lists: [base, files, if folder then reads else [] end, [Imp(key: "fdClose", name: "fd_close", params: [127], results: [127])]]) else base end
end

fn imp_func(m: Imp) -> Func
  ensures true
  example imp_func(m: Imp(key: "a", name: "b", params: [127], results: [])) == Func(params: [127], results: [], locals: [], body: [])
do
  match m
    case Imp(key: _, name: _, params: ps, results: rs) then Func(params: ps, results: rs, locals: [], body: [])
  end
end

fn imp_key(m: Imp) -> Str
  ensures true
  example imp_key(m: Imp(key: "a", name: "b", params: [127], results: [])) == "a"
do
  match m
    case Imp(key: k, name: _, params: _, results: _) then k
  end
end

fn imp_name(m: Imp) -> Str
  ensures true
  example imp_name(m: Imp(key: "a", name: "b", params: [127], results: [])) == "b"
do
  match m
    case Imp(key: _, name: n, params: _, results: _) then n
  end
end

fn pg_with_syms(p: Prog, syms: Dict[Int]) -> Prog
  ensures pg_syms(p: result) == syms
  example pg_syms(p: pg_with_syms(p: prog_empty(), syms: dict(keys: ["a"], values: [1]))) == dict(keys: ["a"], values: [1])
do
  match p
    case Prog(fns: f, fn_nodes: fnn, variants: v, decls: d, syms: _, gen_base: g, types: t, all_types: alls) then Prog(fns: f, fn_nodes: fnn, variants: v, decls: d, syms: syms, gen_base: g, types: t, all_types: alls)
  end
end

fn compile_with(fns: List[Node], types: List[Node], tys: List[FnTypes], folder: Node, out: Node) -> Built
  ensures true
  example compile_with(fns: [], types: [], tys: [], folder: bare(kind: "none", text: "", kids: []), out: bare(kind: "none", text: "", kids: [])) != Built(bytes: [], err: "x")
do
  let imps: List[Imp] = import_list(folder: n_kind(n: folder) != "none", out: n_kind(n: out) != "none")
  let p0: Prog = make_prog(fns: fns, types: types, tys: tys, nimports: len(list: imps))
  let syms: Dict[Int] = add_syms(d: pg_syms(p: p0), prefix: "", names: map(list: imps, func: imp_key), start: 0)
  compile_main(p: pg_with_syms(p: p0, syms: syms), folder: folder, out: out, imps: imps)
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

fn big0(n: Int) -> Int
  ensures result >= 0
  example big0(n: -3) == 0
do
  if n < 0 then 0 else n end
end

# 取り込みの節の中身（at は、それぞれの形の番号）
fn imp_bytes(imps: List[Imp], tidx: List[Int]) -> List[List[Int]]
  ensures len(list: result) == len(list: imps)
  example imp_bytes(imps: [Imp(key: "a", name: "b", params: [], results: [])], tidx: [3]) == [wname(text: "wasi_snapshot_preview1") ++ wname(text: "b") ++ [0, 3]]
do
  match fold(list: imps, init: IB(at: tidx, i: 0, out: []), func: ib_step)
    case IB(at: _, i: _, out: o) then o
  end
end

type IB
  case IB(at: List[Int], i: Int, out: List[List[Int]])
end

fn ib_step(acc: IB, m: Imp) -> IB
  ensures true
  example ib_step(acc: IB(at: [], i: 0, out: []), m: Imp(key: "a", name: "b", params: [], results: [])) == IB(at: [], i: 1, out: [wname(text: "wasi_snapshot_preview1") ++ wname(text: "b") ++ [0, 0]])
do
  match acc
    case IB(at: ts, i: i, out: o) then IB(at: ts, i: i + 1, out: append(list: o, item: wname(text: "wasi_snapshot_preview1") ++ wname(text: imp_name(m: m)) ++ [0] ++ uleb(n: if i >= 0 and i < len(list: ts) then big0(n: get(list: ts, index: i)) else 0 end)))
  end
end

fn compile_main(p: Prog, folder: Node, out: Node, imps: List[Imp]) -> Built
  ensures true
  example compile_main(p: prog_empty(), folder: bare(kind: "none", text: "", kids: []), out: bare(kind: "none", text: "", kids: []), imps: []) != Built(bytes: [], err: "x")
do
  let users: UF = fold(list: pg_fns(p: p), init: UF(p: p, funcs: [], cg: cg_new()), func: user_fn_step)
  match users
    case UF(p: _, funcs: ufs, cg: cg1) then
      match helpers(p: p, cg: cg1)
        case Funcs(funcs: hfs, cg: cg2) then start_and_build(p: p, hfs: hfs, ufs: ufs, imps: imps, g: grant_code(p: p, cg: cg2, folder: folder, out: out))
      end
  end
end

# 渡されたフォルダを探し、要るのに無ければ R509（JS と同じく、手伝いの関数の文字の後ろ）
fn grant_code(p: Prog, cg: Cg, folder: Node, out: Node) -> BC
  ensures true
  example grant_code(p: prog_empty(), cg: cg_new(), folder: bare(kind: "none", text: "", kids: []), out: bare(kind: "none", text: "", kids: [])) == BC(code: [], cg: cg_new())
do
  if n_kind(n: folder) == "none" and n_kind(n: out) == "none" then BC(code: [], cg: cg) else
    let f1: BC = if n_kind(n: folder) == "none" then BC(code: [], cg: cg) else grant_check(p: p, fl: emit_fail(p: p, cg: cg, code: "R509", message: "main asks for a Folder ('" ++ n_text(n: folder) ++ "') but none was granted", n: folder), fd: "readFd") end
    let f2: BC = if n_kind(n: out) == "none" then BC(code: [], cg: bc_cg(b: f1)) else grant_check(p: p, fl: emit_fail(p: p, cg: bc_cg(b: f1), code: "R509", message: "main asks for an OutFolder ('" ++ n_text(n: out) ++ "') but none was granted", n: out), fd: "writeFd") end
    BC(code: concat(lists: [pasm(p: p, text: find_preopens_text()), bc_code(b: f1), bc_code(b: f2)]), cg: bc_cg(b: f2))
  end
end

fn grant_check(p: Prog, fl: BC, fd: Str) -> BC
  ensures true
  example len(list: bc_code(b: grant_check(p: prog_empty(), fl: BC(code: [], cg: cg_new()), fd: "readFd"))) > 0
do
  BC(code: concat(lists: [pasm(p: p, text: "globalGet $" ++ fd ++ " i32 0 i32LtS if EMPTY"), bc_code(b: fl), pasm(p: p, text: "end")]), cg: bc_cg(b: fl))
end

fn start_and_build(p: Prog, hfs: List[Func], ufs: List[Func], imps: List[Imp], g: BC) -> Built
  ensures true
  example start_and_build(p: prog_empty(), hfs: [], ufs: [], imps: [], g: BC(code: [], cg: unsupported(cg: cg_new(), what: "x", n: bare(kind: "x", text: "", kids: [])))) == Built(bytes: [], err: "E600 0:0 the compiler does not support x yet")
do
  let cg: Cg = bc_cg(b: g)
  let start: Func = Func(params: [], results: [], locals: if bc_code(b: g) == [] then [] else [127] end, body: bc_code(b: g) ++ pasm(p: p, text: "call $fn:main end"))
  if cg_err(cg: cg) != "" then Built(bytes: [], err: cg_err(cg: cg)) else Built(bytes: assemble(p: p, imps: imps, hfuncs: hfs, users: ufs, start: start, cg: cg), err: "") end
end

# バイトを並べる。型の表は、取り込み・_start・手伝い・利用者・型ごとの手伝いの順に作る（src/wasm.js と同じ）
fn assemble(p: Prog, imps: List[Imp], hfuncs: List[Func], users: List[Func], start: Func, cg: Cg) -> List[Int]
  ensures true
  example len(list: assemble(p: prog_empty(), imps: import_list(folder: false, out: false), hfuncs: [], users: [], start: Func(params: [], results: [], locals: [], body: [11]), cg: cg_new())) > 8
do
  let it: TI = fold(list: map(list: imps, func: imp_func), init: TI(types: [], out: []), func: index_func)
  let start_t: TT = type_index(types: ti_types(t: it), t: func_type(params: [], results: []))
  let funcs: List[Func] = concat(lists: [hfuncs, users, [start], cg_gens(cg: cg)])
  let ti: TI = fold(list: concat(lists: [hfuncs, users]), init: TI(types: match start_t
    case TT(types: ts, at: _) then ts
  end, out: []), func: index_func)
  let ti2: TI = fold(list: cg_gens(cg: cg), init: ti_with(t: ti, x: tt_at(t: start_t)), func: index_func)
  let heap: Int = (cg_data_end(cg: cg) + 7) / 8 * 8
  let start_index: Int = len(list: imps) + 11 + len(list: users)
  concat(lists: [
  [0, 97, 115, 109, 1, 0, 0, 0],
  wsection(id: 1, body: wvec(items: ti_types(t: ti2))),
  wsection(id: 2, body: wvec(items: imp_bytes(imps: imps, tidx: ti_out(t: it)))),
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
