# Akashi の型の検査を Akashi で書いたもの（セルフホストの段階5）。src/check.js の check と同じエラーを、同じ順に出す。
# 型は Ty（種類・名前・中の型）。型変数は番号の名前を持ち、何に決まったかは St の subst（辞書）に書く。
# JS の版は型変数を書きかえるが、ここでは値を変えられないので、St を受け取って新しい St を返す。
# くり返しは fold で回す。fold の func は外の値を持てないので、要るものは全部「途中の状態」の値に入れて渡す。
use "parser.ak"

# k：Int・Bool・Str・Unit・Html・Sql・Console・Folder・OutFolder・List・Dict・Data・Fn・Var・Err
# List・Dict は args[0] が中の型。Data は name が型の名前。Fn は args の最後が戻りの型。Var は name が番号
type Ty
  case Ty(k: Str, name: Str, args: List[Ty])
end

type Diag
  case Diag(file: Str, code: Str, line: Int, col: Int, message: Str)
end

# 検査の途中：型変数の決まり・次の型変数の番号・見つけたエラー
type St
  case St(subst: Dict[Ty], next: Int, diags: List[Diag], file: Str)
end

type TS
  case TS(ty: Ty, st: St)
end

type UR
  case UR(ok: Bool, st: St)
end

# 型の決まり：名前・型の引数（Option・Result は T）・case の木・自分で作った型か
type TInfo
  case TInfo(name: Str, params: List[Str], cases: List[Node], user: Bool)
end

type VInfo
  case VInfo(type_name: Str, case_node: Node)
end

# 検査の場：型・case・関数の表と、いま見ている関数の名前・場所（body・requires・ensures・example）
type Cx
  case Cx(types: Dict[TInfo], variants: Dict[VInfo], fns: Dict[Node], fn_name: Str, place: Str)
end

# 名前の表。order は足した順（E300 の「持っている鍵」を JS と同じく先に足したものから選ぶため）
type Env
  case Env(vars: Dict[Ty], order: List[Str])
end

# 関数の形：引数の名前と型・戻りの型・case を作る呼び出しか
type Sig
  case Sig(names: List[Str], tys: List[Ty], ret: Ty, ctor: Bool)
end

# ---- 型を作る・見る ----

fn tk(k: Str) -> Ty
  ensures true
  example tk(k: "Int") == Ty(k: "Int", name: "", args: [])
do
  Ty(k: k, name: "", args: [])
end

fn t_err() -> Ty
  ensures true
  example ty_k(t: t_err()) == "Err"
do
  tk(k: "Err")
end

fn t_list(of: Ty) -> Ty
  ensures true
  example ty_k(t: t_list(of: tk(k: "Int"))) == "List"
do
  Ty(k: "List", name: "", args: [of])
end

fn t_data(name: Str, args: List[Ty]) -> Ty
  ensures true
  example ty_name(t: t_data(name: "Shape", args: [])) == "Shape"
do
  Ty(k: "Data", name: name, args: args)
end

fn t_fn(params: List[Ty], ret: Ty) -> Ty
  ensures true
  example len(list: ty_args(t: t_fn(params: [tk(k: "Int")], ret: tk(k: "Bool")))) == 2
do
  Ty(k: "Fn", name: "", args: append(list: params, item: ret))
end

fn ty_k(t: Ty) -> Str
  ensures true
  example ty_k(t: tk(k: "Str")) == "Str"
do
  match t
    case Ty(k: k, name: _, args: _) then k
  end
end

fn ty_name(t: Ty) -> Str
  ensures true
  example ty_name(t: t_data(name: "A", args: [])) == "A"
do
  match t
    case Ty(k: _, name: x, args: _) then x
  end
end

fn ty_args(t: Ty) -> List[Ty]
  ensures true
  example ty_args(t: tk(k: "Int")) == []
do
  match t
    case Ty(k: _, name: _, args: xs) then xs
  end
end

fn ty_arg0(t: Ty) -> Ty
  ensures true
  example ty_arg0(t: t_list(of: tk(k: "Int"))) == tk(k: "Int")
  example ty_arg0(t: tk(k: "Int")) == t_err()
do
  match at(list: ty_args(t: t), index: 0)
    case Some(value: x) then x
    case None then t_err()
  end
end

# ---- 検査の状態 ----

fn st_new() -> St
  ensures true
  example st_new() == St(subst: dict(keys: [], values: []), next: 1, diags: [], file: "")
do
  St(subst: dict(keys: [], values: []), next: 1, diags: [], file: "")
end

fn st_in(st: St, file: Str) -> St
  ensures true
  example st_in(st: st_new(), file: "a.ak") == St(subst: dict(keys: [], values: []), next: 1, diags: [], file: "a.ak")
do
  match st
    case St(subst: s, next: n, diags: ds, file: _) then St(subst: s, next: n, diags: ds, file: file)
  end
end

fn st_subst(st: St) -> Dict[Ty]
  ensures true
  example dict_size(dict: st_subst(st: st_new())) == 0
do
  match st
    case St(subst: s, next: _, diags: _, file: _) then s
  end
end

fn st_next(st: St) -> Int
  ensures true
  example st_next(st: st_new()) == 1
do
  match st
    case St(subst: _, next: n, diags: _, file: _) then n
  end
end

fn st_diags(st: St) -> List[Diag]
  ensures true
  example st_diags(st: st_new()) == []
do
  match st
    case St(subst: _, next: _, diags: ds, file: _) then ds
  end
end

# 型変数を1つ作る
fn fresh(st: St) -> TS
  ensures true
  example fresh(st: st_new()) == TS(ty: Ty(k: "Var", name: "1", args: []), st: St(subst: dict(keys: [], values: []), next: 2, diags: [], file: ""))
do
  match st
    case St(subst: s, next: n, diags: ds, file: f) then TS(ty: Ty(k: "Var", name: to_str(value: n), args: []), st: St(subst: s, next: n + 1, diags: ds, file: f))
  end
end

# 木 n の位置でエラーを足す
fn report(st: St, code: Str, n: Node, message: Str) -> St
  ensures true
  example st_diags(st: report(st: st_new(), code: "E200", n: Node(kind: "var", text: "x", line: 2, col: 3, kids: []), message: "m")) == [Diag(file: "", code: "E200", line: 2, col: 3, message: "m")]
do
  match st
    case St(subst: s, next: n2, diags: ds, file: f) then St(subst: s, next: n2, diags: append(list: ds, item: Diag(file: f, code: code, line: n_line(n: n), col: n_col(n: n), message: message)), file: f)
  end
end

fn diag_count(st: St) -> Int
  ensures result >= 0
  example diag_count(st: st_new()) == 0
do
  len(list: st_diags(st: st))
end

fn ts_ty(r: TS) -> Ty
  ensures true
  example ts_ty(r: TS(ty: tk(k: "Int"), st: st_new())) == tk(k: "Int")
do
  match r
    case TS(ty: t, st: _) then t
  end
end

fn ts_st(r: TS) -> St
  ensures true
  example ts_st(r: TS(ty: tk(k: "Int"), st: st_new())) == st_new()
do
  match r
    case TS(ty: _, st: s) then s
  end
end

fn ur_ok(r: UR) -> Bool
  ensures true
  example ur_ok(r: UR(ok: true, st: st_new()))
do
  match r
    case UR(ok: o, st: _) then o
  end
end

fn ur_st(r: UR) -> St
  ensures true
  example ur_st(r: UR(ok: true, st: st_new())) == st_new()
do
  match r
    case UR(ok: _, st: s) then s
  end
end

# ---- 型変数をたどる・合わせる ----

# 決まっている型変数を、決まった型までたどる
fn prune(st: St, t: Ty) -> Ty
  ensures true
  example prune(st: st_new(), t: tk(k: "Int")) == tk(k: "Int")
do
  if ty_k(t: t) != "Var" then t else
    match dict_get(dict: st_subst(st: st), key: ty_name(t: t))
      case Some(value: u) then prune(st: st, t: u)
      case None then t
    end
  end
end

type Occ
  case Occ(st: St, id: Str, found: Bool)
end

# 型変数 id が t の中に出てくるか（出てくれば合わせられない：無限の型になる）
fn occurs(st: St, id: Str, t: Ty) -> Bool
  ensures true
  example occurs(st: st_new(), id: "1", t: t_list(of: Ty(k: "Var", name: "1", args: [])))
  example not occurs(st: st_new(), id: "1", t: tk(k: "Int"))
do
  let p: Ty = prune(st: st, t: t)
  if ty_k(t: p) == "Var" then ty_name(t: p) == id else
    match fold(list: ty_args(t: p), init: Occ(st: st, id: id, found: false), func: occurs_step)
      case Occ(st: _, id: _, found: f) then f
    end
  end
end

fn occurs_step(o: Occ, t: Ty) -> Occ
  ensures true
  example occurs_step(o: Occ(st: st_new(), id: "1", found: true), t: tk(k: "Int")) == Occ(st: st_new(), id: "1", found: true)
do
  match o
    case Occ(st: st, id: id, found: f) then Occ(st: st, id: id, found: f or occurs(st: st, id: id, t: t))
  end
end

# 2つの型を同じにする（型変数を決める）。合わなければ ok が false（途中で決めた型変数はそのまま。JS と同じ）
fn unify(st: St, a: Ty, b: Ty) -> UR
  ensures true
  example ur_ok(r: unify(st: st_new(), a: tk(k: "Int"), b: Ty(k: "Var", name: "9", args: [])))
  example not ur_ok(r: unify(st: st_new(), a: tk(k: "Int"), b: tk(k: "Str")))
do
  let pa: Ty = prune(st: st, t: a)
  let pb: Ty = prune(st: st, t: b)
  when
    ty_k(t: pa) == "Err" or ty_k(t: pb) == "Err" then UR(ok: true, st: st)
    ty_k(t: pa) == "Var" then bind_var(st: st, v: pa, t: pb)
    ty_k(t: pb) == "Var" then bind_var(st: st, v: pb, t: pa)
    ty_k(t: pa) != ty_k(t: pb) then UR(ok: false, st: st)
    ty_k(t: pa) == "Data" and ty_name(t: pa) != ty_name(t: pb) then UR(ok: false, st: st)
    len(list: ty_args(t: pa)) != len(list: ty_args(t: pb)) then UR(ok: false, st: st)
    else unify_all(st: st, xs: ty_args(t: pa), ys: ty_args(t: pb))
  end
end

fn bind_var(st: St, v: Ty, t: Ty) -> UR
  ensures true
  example ur_ok(r: bind_var(st: st_new(), v: Ty(k: "Var", name: "1", args: []), t: tk(k: "Int")))
do
  when
    ty_k(t: t) == "Var" and ty_name(t: t) == ty_name(t: v) then UR(ok: true, st: st)
    occurs(st: st, id: ty_name(t: v), t: t) then UR(ok: false, st: st)
    else
    match st
      case St(subst: s, next: n, diags: ds, file: f) then UR(ok: true, st: St(subst: dict_put(dict: s, key: ty_name(t: v), value: t), next: n, diags: ds, file: f))
    end
  end
end

type UZ
  case UZ(ok: Bool, st: St, xs: List[Ty], ys: List[Ty])
end

# 中の型を順に合わせる。1つ合わなければそこで止める
fn unify_all(st: St, xs: List[Ty], ys: List[Ty]) -> UR
  ensures true
  example ur_ok(r: unify_all(st: st_new(), xs: [], ys: []))
do
  match fold(list: range(from: 0, to: len(list: xs)), init: UZ(ok: true, st: st, xs: xs, ys: ys), func: unify_step)
    case UZ(ok: o, st: s, xs: _, ys: _) then UR(ok: o, st: s)
  end
end

fn unify_step(z: UZ, i: Int) -> UZ
  ensures true
  example unify_step(z: UZ(ok: false, st: st_new(), xs: [], ys: []), i: 0) == UZ(ok: false, st: st_new(), xs: [], ys: [])
do
  match z
    case UZ(ok: o, st: st, xs: xs, ys: ys) then if not o then z else
      let r: UR = unify(st: st, a: ty_at(xs: xs, i: i), b: ty_at(xs: ys, i: i))
      UZ(ok: ur_ok(r: r), st: ur_st(r: r), xs: xs, ys: ys)
    end
  end
end

fn ty_at(xs: List[Ty], i: Int) -> Ty
  ensures true
  example ty_at(xs: [], i: 0) == t_err()
do
  match at(list: xs, index: i)
    case Some(value: x) then x
    case None then t_err()
  end
end

# ---- 型を文字にする（エラー文。JS の typeStr と同じ） ----

type TyAcc
  case TyAcc(st: St, out: List[Ty])
end

# 決まっている型変数を、全部決まった型に置きかえる
fn zonk(st: St, t: Ty) -> Ty
  ensures true
  example zonk(st: st_new(), t: t_list(of: tk(k: "Int"))) == t_list(of: tk(k: "Int"))
do
  let p: Ty = prune(st: st, t: t)
  match fold(list: ty_args(t: p), init: TyAcc(st: st, out: []), func: zonk_step)
    case TyAcc(st: _, out: xs) then Ty(k: ty_k(t: p), name: ty_name(t: p), args: xs)
  end
end

fn zonk_step(acc: TyAcc, t: Ty) -> TyAcc
  ensures true
  example zonk_step(acc: TyAcc(st: st_new(), out: []), t: tk(k: "Int")) == TyAcc(st: st_new(), out: [tk(k: "Int")])
do
  match acc
    case TyAcc(st: st, out: xs) then TyAcc(st: st, out: append(list: xs, item: zonk(st: st, t: t)))
  end
end

fn type_str(t: Ty) -> Str
  ensures true
  example type_str(t: t_fn(params: [tk(k: "Int"), Ty(k: "Var", name: "1", args: [])], ret: t_data(name: "Option", args: [t_list(of: tk(k: "Str"))]))) == "fn(Int, T) -> Option[List[Str]]"
do
  let k: Str = ty_k(t: t)
  let xs: List[Ty] = ty_args(t: t)
  when
    k == "List" or k == "Dict" then k ++ "[" ++ type_str(t: ty_arg0(t: t)) ++ "]"
    k == "Fn" then "fn(" ++ join(parts: map(list: reverse(list: drop(list: reverse(list: xs), count: 1)), func: type_str), by: ", ") ++ ") -> " ++ type_str(t: ty_at(xs: xs, i: len(list: xs) - 1))
    k == "Data" then if xs == [] then ty_name(t: t) else ty_name(t: t) ++ "[" ++ join(parts: map(list: xs, func: type_str), by: ", ") ++ "]" end
    k == "Var" then "T"
    k == "Err" then "?"
    else k
  end
end

# エラー文に入れる型
fn show_ty(st: St, t: Ty) -> Str
  ensures true
  example show_ty(st: st_new(), t: tk(k: "Int")) == "Int"
do
  type_str(t: zonk(st: st, t: t))
end

# ---- 書いた型（木）から Ty へ ----

fn base_types() -> Str
  ensures true
  example in_table(table: base_types(), word: "Html")
do
  " Int Bool Str Unit Html Sql Console Folder OutFolder "
end

# subst：組み込みの型の引数（"T"）が何か。組み込みの型の木では、型の引数を "?T" と書く
fn from_ast(n: Node, subst: Dict[Ty]) -> Ty
  ensures true
  example from_ast(n: bare(kind: "t", text: "List", kids: [bare(kind: "t", text: "Shape", kids: [])]), subst: dict(keys: [], values: [])) == t_list(of: t_data(name: "Shape", args: []))
do
  let name: Str = n_text(n: n)
  when
    starts_with(text: name, prefix: "@") then t_data(name: slice(text: name, from: 1, to: str_len(text: name)), args: [])
    name == "List" or name == "Dict" then Ty(k: name, name: "", args: [from_ast(n: first_kid(n: n), subst: subst)])
    name == "Option" or name == "Result" then t_data(name: name, args: [from_ast(n: first_kid(n: n), subst: subst)])
    name == "?T" then
    match dict_get(dict: subst, key: "T")
      case Some(value: t) then t
      case None then t_err()
    end
    in_table(table: base_types(), word: name) then tk(k: name)
    else t_data(name: name, args: [])
  end
end

fn is_cap_ty(t: Ty) -> Bool
  ensures true
  example is_cap_ty(t: tk(k: "Folder"))
do
  in_table(table: " Console Folder OutFolder ", word: ty_k(t: t))
end

fn is_cap(st: St, t: Ty) -> Bool
  ensures true
  example not is_cap(st: st_new(), t: tk(k: "Int"))
do
  is_cap_ty(t: prune(st: st, t: t))
end

# 権利が中にあるか（書いた型から作った、型変数の無い型に使う）
fn has_cap(t: Ty) -> Bool
  ensures true
  example has_cap(t: t_list(of: tk(k: "Console")))
  example not has_cap(t: t_data(name: "Option", args: [tk(k: "Int")]))
do
  let k: Str = ty_k(t: t)
  is_cap_ty(t: t) or ((k == "List" or k == "Dict") and has_cap(t: ty_arg0(t: t))) or (k == "Data" and any(list: ty_args(t: t), func: has_cap))
end

# ---- 木を見る ----

fn kid_at(n: Node, i: Int) -> Node
  ensures true
  example n_kind(n: kid_at(n: bare(kind: "x", text: "", kids: []), i: 3)) == "none"
do
  match at(list: n_kids(n: n), index: i)
    case Some(value: k) then k
    case None then bare(kind: "none", text: "", kids: [])
  end
end

fn last_kid(n: Node) -> Node
  ensures true
  example n_kind(n: last_kid(n: bare(kind: "x", text: "", kids: [bare(kind: "a", text: "", kids: []), bare(kind: "b", text: "", kids: [])]))) == "b"
do
  kid_at(n: n, i: len(list: n_kids(n: n)) - 1)
end

fn kid_names(ns: List[Node]) -> List[Str]
  ensures len(list: result) == len(list: ns)
  example kid_names(ns: [bare(kind: "x", text: "a", kids: [])]) == ["a"]
do
  map(list: ns, func: n_text)
end

fn has_str(xs: List[Str], x: Str) -> Bool
  ensures true
  example has_str(xs: ["a", "b"], x: "b")
  example not has_str(xs: [], x: "a")
do
  fold(list: xs, init: Hit(want: x, found: false), func: hit_step) == Hit(want: x, found: true)
end

type Hit
  case Hit(want: Str, found: Bool)
end

fn hit_step(h: Hit, x: Str) -> Hit
  ensures true
  example hit_step(h: Hit(want: "a", found: false), x: "a") == Hit(want: "a", found: true)
do
  match h
    case Hit(want: w, found: f) then Hit(want: w, found: f or x == w)
  end
end

# ---- 名前の表 ----

fn env_new() -> Env
  ensures true
  example env_names(env: env_new()) == []
do
  Env(vars: dict(keys: [], values: []), order: [])
end

fn env_names(env: Env) -> List[Str]
  ensures true
  example env_names(env: env_set(env: env_new(), name: "b", t: tk(k: "Int"))) == ["b"]
do
  match env
    case Env(vars: _, order: o) then o
  end
end

fn env_get(env: Env, name: Str) -> Option[Ty]
  ensures true
  example env_get(env: env_new(), name: "x") == None
do
  match env
    case Env(vars: v, order: _) then dict_get(dict: v, key: name)
  end
end

fn env_has(env: Env, name: Str) -> Bool
  ensures true
  example env_has(env: env_set(env: env_new(), name: "x", t: tk(k: "Int")), name: "x")
do
  match env
    case Env(vars: v, order: _) then dict_has(dict: v, key: name)
  end
end

fn env_set(env: Env, name: Str, t: Ty) -> Env
  ensures true
  example env_get(env: env_set(env: env_new(), name: "x", t: tk(k: "Int")), name: "x") == Some(value: tk(k: "Int"))
do
  match env
    case Env(vars: v, order: o) then Env(vars: dict_put(dict: v, key: name, value: t), order: if dict_has(dict: v, key: name) then o else append(list: o, item: name) end)
  end
end

fn env_type(env: Env, name: Str) -> Ty
  ensures true
  example env_type(env: env_new(), name: "x") == t_err()
do
  match env_get(env: env, name: name)
    case Some(value: t) then t
    case None then t_err()
  end
end

type EnvAcc
  case EnvAcc(st: St, from: Env, out: Env, cap: Str, found: Str)
end

# 権利でない名前だけの表（requires・ensures・example の中では権利を使えない）
fn env_pure(st: St, env: Env) -> Env
  ensures true
  example env_names(env: env_pure(st: st_new(), env: env_set(env: env_new(), name: "c", t: tk(k: "Console")))) == []
do
  match fold(list: env_names(env: env), init: EnvAcc(st: st, from: env, out: env_new(), cap: "", found: ""), func: pure_step)
    case EnvAcc(st: _, from: _, out: o, cap: _, found: _) then o
  end
end

fn pure_step(acc: EnvAcc, name: Str) -> EnvAcc
  ensures true
  example pure_step(acc: EnvAcc(st: st_new(), from: env_new(), out: env_new(), cap: "", found: ""), name: "x") == EnvAcc(st: st_new(), from: env_new(), out: env_set(env: env_new(), name: "x", t: t_err()), cap: "", found: "")
do
  match acc
    case EnvAcc(st: st, from: f, out: o, cap: c, found: fd) then if is_cap(st: st, t: env_type(env: f, name: name)) then acc else EnvAcc(st: st, from: f, out: env_set(env: o, name: name, t: env_type(env: f, name: name)), cap: c, found: fd) end
  end
end

# 表のうち、先に足したもので、種類が cap の権利を持つ名前（無ければ ""）
fn env_find_cap(st: St, env: Env, cap: Str) -> Str
  ensures true
  example env_find_cap(st: st_new(), env: env_set(env: env_new(), name: "c", t: tk(k: "Console")), cap: "Console") == "c"
do
  match fold(list: env_names(env: env), init: EnvAcc(st: st, from: env, out: env, cap: cap, found: ""), func: find_cap_step)
    case EnvAcc(st: _, from: _, out: _, cap: _, found: f) then f
  end
end

fn find_cap_step(acc: EnvAcc, name: Str) -> EnvAcc
  ensures true
  example find_cap_step(acc: EnvAcc(st: st_new(), from: env_new(), out: env_new(), cap: "Console", found: "x"), name: "y") == EnvAcc(st: st_new(), from: env_new(), out: env_new(), cap: "Console", found: "x")
do
  match acc
    case EnvAcc(st: st, from: f, out: o, cap: c, found: fd) then if fd == "" and ty_k(t: prune(st: st, t: env_type(env: f, name: name))) == c then EnvAcc(st: st, from: f, out: o, cap: c, found: name) else acc end
  end
end

# ---- 検査の場 ----

fn cx_types(cx: Cx) -> Dict[TInfo]
  ensures true
  example dict_size(dict: cx_types(cx: cx_empty())) == 0
do
  match cx
    case Cx(types: t, variants: _, fns: _, fn_name: _, place: _) then t
  end
end

fn cx_variants(cx: Cx) -> Dict[VInfo]
  ensures true
  example dict_size(dict: cx_variants(cx: cx_empty())) == 0
do
  match cx
    case Cx(types: _, variants: v, fns: _, fn_name: _, place: _) then v
  end
end

fn cx_fns(cx: Cx) -> Dict[Node]
  ensures true
  example dict_size(dict: cx_fns(cx: cx_empty())) == 0
do
  match cx
    case Cx(types: _, variants: _, fns: f, fn_name: _, place: _) then f
  end
end

fn cx_fn_name(cx: Cx) -> Str
  ensures true
  example cx_fn_name(cx: cx_empty()) == ""
do
  match cx
    case Cx(types: _, variants: _, fns: _, fn_name: n, place: _) then n
  end
end

fn cx_place(cx: Cx) -> Str
  ensures true
  example cx_place(cx: cx_empty()) == "body"
do
  match cx
    case Cx(types: _, variants: _, fns: _, fn_name: _, place: p) then p
  end
end

fn cx_empty() -> Cx
  ensures true
  example cx_fn_name(cx: cx_empty()) == ""
do
  Cx(types: dict(keys: [], values: []), variants: dict(keys: [], values: []), fns: dict(keys: [], values: []), fn_name: "", place: "body")
end

fn cx_at(cx: Cx, fn_name: Str, place: Str) -> Cx
  ensures true
  example cx_place(cx: cx_at(cx: cx_empty(), fn_name: "f", place: "ensures")) == "ensures"
do
  match cx
    case Cx(types: t, variants: v, fns: f, fn_name: _, place: _) then Cx(types: t, variants: v, fns: f, fn_name: fn_name, place: place)
  end
end

# 名前が使われているか（変数・関数・組み込み・case）。名前は隠さない・使い回さない
fn taken(cx: Cx, env: Env, name: Str) -> Bool
  ensures true
  example taken(cx: cx_empty(), env: env_new(), name: "print")
  example not taken(cx: cx_empty(), env: env_new(), name: "total")
do
  env_has(env: env, name: name) or dict_has(dict: cx_fns(cx: cx), key: name) or is_builtin(name: name) or dict_has(dict: cx_variants(cx: cx), key: name)
end

# ---- 組み込みの関数の形 ----
# 書き方：「引数: 型, … -> 戻りの型」。a・b は呼ぶたびに新しくなる型変数。Fn[引数…, 戻り]

fn builtin_text(name: Str) -> Str
  ensures true
  example builtin_text(name: "len") == "list: List[a] -> Int"
  example builtin_text(name: "nope") == ""
do
  when
    name == "print" then "to: Console, value: a -> Unit"
    name == "read_text" then "from: Folder, path: Str -> Result[Str]"
    name == "write_text" then "to: OutFolder, path: Str, text: Str -> Result[Unit]"
    name == "write_bytes" then "to: OutFolder, path: Str, bytes: List[Int] -> Result[Unit]"
    name == "parse_int" then "text: Str -> Option[Int]"
    name == "lines" then "text: Str -> List[Str]"
    name == "html" then "template: Str, values: List[Html] -> Html"
    name == "html_text" then "value: Str -> Html"
    name == "html_join" then "parts: List[Html] -> Html"
    name == "sql" then "template: Str, values: List[Str] -> Sql"
    name == "len" then "list: List[a] -> Int"
    name == "str_len" then "text: Str -> Int"
    name == "slice" then "text: Str, from: Int, to: Int -> Str"
    name == "code_of" then "char: Str -> Int"
    name == "char_of" then "code: Int -> Str"
    name == "to_str" then "value: a -> Str"
    name == "range" then "from: Int, to: Int -> List[Int]"
    name == "get" then "list: List[a], index: Int -> a"
    name == "at" then "list: List[a], index: Int -> Option[a]"
    name == "find" then "list: List[a], func: Fn[a, Bool] -> Option[a]"
    name == "any" or name == "all" then "list: List[a], func: Fn[a, Bool] -> Bool"
    name == "reverse" then "list: List[a] -> List[a]"
    name == "take" or name == "drop" then "list: List[a], count: Int -> List[a]"
    name == "sort" then "list: List[Int] -> List[Int]"
    name == "sum" then "list: List[Int] -> Int"
    name == "max" or name == "min" then "list: List[Int] -> Option[Int]"
    name == "chars" then "text: Str -> List[Str]"
    name == "split" then "text: Str, by: Str -> List[Str]"
    name == "join" then "parts: List[Str], by: Str -> Str"
    name == "contains" then "text: Str, part: Str -> Bool"
    name == "starts_with" then "text: Str, prefix: Str -> Bool"
    name == "ends_with" then "text: Str, suffix: Str -> Bool"
    name == "trim" then "text: Str -> Str"
    name == "append" then "list: List[a], item: a -> List[a]"
    name == "concat" then "lists: List[List[a]] -> List[a]"
    name == "map" then "list: List[a], func: Fn[a, b] -> List[b]"
    name == "filter" then "list: List[a], func: Fn[a, Bool] -> List[a]"
    name == "fold" then "list: List[a], init: b, func: Fn[b, a, b] -> b"
    name == "dict" then "keys: List[Str], values: List[a] -> Dict[a]"
    name == "dict_put" then "dict: Dict[a], key: Str, value: a -> Dict[a]"
    name == "dict_get" then "dict: Dict[a], key: Str -> Option[a]"
    name == "dict_has" then "dict: Dict[a], key: Str -> Bool"
    name == "dict_remove" then "dict: Dict[a], key: Str -> Dict[a]"
    name == "dict_keys" then "dict: Dict[a] -> List[Str]"
    name == "dict_values" then "dict: Dict[a] -> List[a]"
    name == "dict_size" then "dict: Dict[a] -> Int"
    else ""
  end
end

fn is_builtin(name: Str) -> Bool
  ensures true
  example is_builtin(name: "fold")
do
  builtin_text(name: name) != ""
end

type TyAt
  case TyAt(t: Ty, pos: Int)
end

# 組み込みの形の文字を読む。a・b は型変数 base・base+1
fn read_ty(toks: List[Token], pos: Int, base: Int) -> TyAt
  ensures true
  example read_ty(toks: lex_ok(text: "List[a]"), pos: 0, base: 5) == TyAt(t: t_list(of: Ty(k: "Var", name: "5", args: [])), pos: 4)
do
  let name: Str = tok_text(toks: toks, i: pos)
  let has_args: Bool = tok_text(toks: toks, i: pos + 1) == "["
  let args: TyList = if has_args then read_ty_args(toks: toks, pos: pos + 2, base: base, acc: []) else TyList(ts: [], pos: pos + 1) end
  match args
    case TyList(ts: xs, pos: p) then TyAt(t: when
      name == "a" then Ty(k: "Var", name: to_str(value: base), args: [])
      name == "b" then Ty(k: "Var", name: to_str(value: base + 1), args: [])
      name == "List" or name == "Dict" or name == "Fn" then Ty(k: name, name: "", args: xs)
      name == "Option" or name == "Result" then t_data(name: name, args: xs)
      else tk(k: name)
    end, pos: p)
  end
end

type TyList
  case TyList(ts: List[Ty], pos: Int)
end

# [ の後ろの型の並び（, で区切り、] で終わる）
fn read_ty_args(toks: List[Token], pos: Int, base: Int, acc: List[Ty]) -> TyList
  ensures true
  example read_ty_args(toks: lex_ok(text: "Int]"), pos: 0, base: 1, acc: []) == TyList(ts: [tk(k: "Int")], pos: 2)
do
  let one: TyAt = read_ty(toks: toks, pos: pos, base: base)
  match one
    case TyAt(t: t, pos: p) then if tok_text(toks: toks, i: p) == "," then read_ty_args(toks: toks, pos: p + 1, base: base, acc: append(list: acc, item: t)) else TyList(ts: append(list: acc, item: t), pos: p + 1) end
  end
end

fn tok_text(toks: List[Token], i: Int) -> Str
  ensures true
  example tok_text(toks: [], i: 0) == ""
do
  match at(list: toks, index: i)
    case Some(value: t) then t_text(t: t)
    case None then ""
  end
end

fn lex_ok(text: Str) -> List[Token]
  ensures true
  example len(list: lex_ok(text: "a b")) == 2
do
  match lex(text: text)
    case Ok(value: ts) then ts
    case Err(message: _) then []
  end
end

# 引数の並び（名前: 型, …）と -> の後ろの戻りの型
fn read_sig(toks: List[Token], pos: Int, base: Int, names: List[Str], tys: List[Ty]) -> Sig
  ensures true
  example read_sig(toks: lex_ok(text: "text: Str -> Int"), pos: 0, base: 1, names: [], tys: []) == Sig(names: ["text"], tys: [tk(k: "Str")], ret: tk(k: "Int"), ctor: false)
do
  let one: TyAt = read_ty(toks: toks, pos: pos + 2, base: base)
  match one
    case TyAt(t: t, pos: p) then if tok_text(toks: toks, i: p) == "," then read_sig(toks: toks, pos: p + 1, base: base, names: append(list: names, item: tok_text(toks: toks, i: pos)), tys: append(list: tys, item: t)) else Sig(names: append(list: names, item: tok_text(toks: toks, i: pos)), tys: append(list: tys, item: t), ret: tyat_t(r: read_ty(toks: toks, pos: p + 1, base: base)), ctor: false) end
  end
end

fn tyat_t(r: TyAt) -> Ty
  ensures true
  example tyat_t(r: TyAt(t: tk(k: "Int"), pos: 0)) == tk(k: "Int")
do
  match r
    case TyAt(t: t, pos: _) then t
  end
end

type SigSt
  case SigSt(sig: Sig, st: St)
end

# 組み込みの関数の形。型変数を2つぶん新しくする
fn builtin_sig(st: St, name: Str) -> SigSt
  ensures true
  example builtin_sig(st: st_new(), name: "len") == SigSt(sig: Sig(names: ["list"], tys: [t_list(of: Ty(k: "Var", name: "1", args: []))], ret: tk(k: "Int"), ctor: false), st: St(subst: dict(keys: [], values: []), next: 3, diags: [], file: ""))
do
  match st
    case St(subst: s, next: n, diags: ds, file: f) then SigSt(sig: read_sig(toks: lex_ok(text: builtin_text(name: name)), pos: 0, base: n, names: [], tys: []), st: St(subst: s, next: n + 2, diags: ds, file: f))
  end
end

fn sig_names(s: Sig) -> List[Str]
  ensures true
  example sig_names(s: Sig(names: ["a"], tys: [], ret: t_err(), ctor: false)) == ["a"]
do
  match s
    case Sig(names: n, tys: _, ret: _, ctor: _) then n
  end
end

fn sig_tys(s: Sig) -> List[Ty]
  ensures true
  example sig_tys(s: Sig(names: [], tys: [tk(k: "Int")], ret: t_err(), ctor: false)) == [tk(k: "Int")]
do
  match s
    case Sig(names: _, tys: t, ret: _, ctor: _) then t
  end
end

fn sig_ret(s: Sig) -> Ty
  ensures true
  example sig_ret(s: Sig(names: [], tys: [], ret: tk(k: "Int"), ctor: false)) == tk(k: "Int")
do
  match s
    case Sig(names: _, tys: _, ret: r, ctor: _) then r
  end
end

fn sig_ctor(s: Sig) -> Bool
  ensures true
  example sig_ctor(s: Sig(names: [], tys: [], ret: t_err(), ctor: true))
do
  match s
    case Sig(names: _, tys: _, ret: _, ctor: c) then c
  end
end

# 引数 name の型（無ければ Err）。have は見つかったか
fn sig_param(s: Sig, name: Str) -> Ty
  ensures true
  example sig_param(s: Sig(names: ["x"], tys: [tk(k: "Int")], ret: t_err(), ctor: false), name: "x") == tk(k: "Int")
do
  ty_at(xs: sig_tys(s: s), i: index_of(xs: sig_names(s: s), x: name))
end

type Idx
  case Idx(want: Str, at_i: Int, found: Int)
end

# 最初に出てくる位置（無ければ -1）
fn index_of(xs: List[Str], x: Str) -> Int
  ensures result >= -1
  example index_of(xs: ["a", "b", "b"], x: "b") == 1
  example index_of(xs: [], x: "b") == -1
do
  match fold(list: xs, init: Idx(want: x, at_i: 0, found: -1), func: index_step)
    case Idx(want: _, at_i: _, found: f) then f
  end
end

fn index_step(acc: Idx, x: Str) -> Idx
  ensures true
  example index_step(acc: Idx(want: "a", at_i: 0, found: -1), x: "a") == Idx(want: "a", at_i: 1, found: 0)
do
  match acc
    case Idx(want: w, at_i: i, found: f) then Idx(want: w, at_i: i + 1, found: if f == -1 and x == w then i else f end)
  end
end

# 自分で書いた関数の形
fn fn_sig(f: Node) -> Sig
  ensures true
  example sig_names(s: fn_sig(f: bare(kind: "fn", text: "f", kids: []))) == []
do
  let params: List[Node] = n_kids(n: kid_at(n: f, i: 0))
  Sig(names: kid_names(ns: params), tys: map(list: params, func: param_ty), ret: from_ast(n: kid_at(n: f, i: 1), subst: no_subst()), ctor: false)
end

fn param_ty(p: Node) -> Ty
  ensures true
  example param_ty(p: bare(kind: "param", text: "x", kids: [bare(kind: "t", text: "Int", kids: [])])) == tk(k: "Int")
do
  from_ast(n: first_kid(n: p), subst: no_subst())
end

fn no_subst() -> Dict[Ty]
  ensures dict_size(dict: result) == 0
  example no_subst() == dict(keys: [], values: [])
do
  dict(keys: [], values: [])
end

# ---- 型と case の表を作る ----

fn builtin_type_nodes() -> List[Node]
  ensures len(list: result) == 2
  example n_text(n: get(list: builtin_type_nodes(), index: 0)) == "Option"
do
  let tv: Node = bare(kind: "t", text: "?T", kids: [])
  [bare(kind: "type", text: "Option", kids: [bare(kind: "case", text: "Some", kids: [bare(kind: "field", text: "value", kids: [tv])]), bare(kind: "case", text: "None", kids: [])]), bare(kind: "type", text: "Result", kids: [bare(kind: "case", text: "Ok", kids: [bare(kind: "field", text: "value", kids: [tv])]), bare(kind: "case", text: "Err", kids: [bare(kind: "field", text: "message", kids: [bare(kind: "t", text: "Str", kids: [])])])])]
end

type Setup
  case Setup(cx: Cx, st: St, user: Bool, tname: Str, seen: List[Str])
end

fn setup_cx(s: Setup) -> Cx
  ensures true
  example setup_cx(s: Setup(cx: cx_empty(), st: st_new(), user: false, tname: "", seen: [])) == cx_empty()
do
  match s
    case Setup(cx: c, st: _, user: _, tname: _, seen: _) then c
  end
end

fn setup_st(s: Setup) -> St
  ensures true
  example setup_st(s: Setup(cx: cx_empty(), st: st_new(), user: false, tname: "", seen: [])) == st_new()
do
  match s
    case Setup(cx: _, st: st, user: _, tname: _, seen: _) then st
  end
end

fn setup_with(s: Setup, cx: Cx, st: St) -> Setup
  ensures true
  example setup_st(s: setup_with(s: Setup(cx: cx_empty(), st: st_new(), user: true, tname: "", seen: []), cx: cx_empty(), st: st_new())) == st_new()
do
  match s
    case Setup(cx: _, st: _, user: u, tname: t, seen: sn) then Setup(cx: cx, st: st, user: u, tname: t, seen: sn)
  end
end

# 型を1つ表に入れる（名前の重なりは E203。自分の型の欄に権利があれば E309）
fn add_type(s: Setup, t: Node) -> Setup
  ensures true
  example dict_has(dict: cx_types(cx: setup_cx(s: add_type(s: Setup(cx: cx_empty(), st: st_new(), user: true, tname: "", seen: []), t: bare(kind: "type", text: "A", kids: [])))), key: "A")
do
  match s
    case Setup(cx: cx, st: st, user: user, tname: _, seen: _) then if dict_has(dict: cx_types(cx: cx), key: n_text(n: t)) or (user and in_table(table: " Int Bool Str Unit List Dict Html Sql Console Folder OutFolder ", word: n_text(n: t))) then Setup(cx: cx, st: report(st: st, code: "E203", n: t, message: "type '" ++ n_text(n: t) ++ "' is already defined"), user: user, tname: "", seen: []) else
      let info: TInfo = TInfo(name: n_text(n: t), params: if user then [] else ["T"] end, cases: n_kids(n: t), user: user)
      let added: Cx = match cx
        case Cx(types: ts, variants: vs, fns: fs, fn_name: f, place: p) then Cx(types: dict_put(dict: ts, key: n_text(n: t), value: info), variants: vs, fns: fs, fn_name: f, place: p)
      end
      fold(list: n_kids(n: t), init: Setup(cx: added, st: st, user: user, tname: n_text(n: t), seen: []), func: add_case)
    end
  end
end

fn add_case(s: Setup, v: Node) -> Setup
  ensures true
  example dict_has(dict: cx_variants(cx: setup_cx(s: add_case(s: Setup(cx: cx_empty(), st: st_new(), user: true, tname: "A", seen: []), v: bare(kind: "case", text: "B", kids: [])))), key: "B")
do
  match s
    case Setup(cx: cx, st: st, user: user, tname: tn, seen: _) then
      match dict_get(dict: cx_variants(cx: cx), key: n_text(n: v))
        case Some(value: old) then Setup(cx: cx, st: report(st: st, code: "E203", n: v, message: "case '" ++ n_text(n: v) ++ "' is already used" ++ if type_is_user(cx: cx, name: vinfo_type(v: old)) then "" else " (built-in)" end), user: user, tname: tn, seen: [])
        case None then add_new_case(cx: cx, st: st, user: user, tname: tn, v: v)
      end
  end
end

fn add_new_case(cx: Cx, st: St, user: Bool, tname: Str, v: Node) -> Setup
  ensures true
  example dict_has(dict: cx_variants(cx: setup_cx(s: add_new_case(cx: cx_empty(), st: st_new(), user: true, tname: "A", v: bare(kind: "case", text: "B", kids: [])))), key: "B")
do
  let added: Cx = match cx
    case Cx(types: ts, variants: vs, fns: fs, fn_name: f, place: p) then Cx(types: ts, variants: dict_put(dict: vs, key: n_text(n: v), value: VInfo(type_name: tname, case_node: v)), fns: fs, fn_name: f, place: p)
  end
  let done: Setup = fold(list: n_kids(n: v), init: Setup(cx: added, st: st, user: user, tname: n_text(n: v), seen: []), func: add_field)
  Setup(cx: setup_cx(s: done), st: setup_st(s: done), user: user, tname: tname, seen: [])
end

# 欄を1つ見る（tname は case の名前）
fn add_field(s: Setup, f: Node) -> Setup
  ensures true
  example diag_count(st: setup_st(s: add_field(s: Setup(cx: cx_empty(), st: st_new(), user: true, tname: "B", seen: ["x"]), f: bare(kind: "field", text: "x", kids: [bare(kind: "t", text: "Int", kids: [])])))) == 1
do
  match s
    case Setup(cx: cx, st: st, user: user, tname: vn, seen: seen) then Setup(cx: cx, st: field_diags(st: st, user: user, vn: vn, seen: seen, f: f), user: user, tname: vn, seen: append(list: seen, item: n_text(n: f)))
  end
end

fn field_diags(st: St, user: Bool, vn: Str, seen: List[Str], f: Node) -> St
  ensures true
  example field_diags(st: st_new(), user: true, vn: "B", seen: [], f: bare(kind: "field", text: "x", kids: [bare(kind: "t", text: "Int", kids: [])])) == st_new()
do
  let st2: St = if has_str(xs: seen, x: n_text(n: f)) then report(st: st, code: "E203", n: f, message: "field '" ++ n_text(n: f) ++ "' appears twice in case " ++ vn) else st end
  if user and has_cap(t: from_ast(n: first_kid(n: f), subst: no_subst())) then report(st: st2, code: "E309", n: f, message: "field '" ++ n_text(n: f) ++ "' of " ++ vn ++ " holds a capability") else st2 end
end

fn vinfo_type(v: VInfo) -> Str
  ensures true
  example vinfo_type(v: VInfo(type_name: "A", case_node: bare(kind: "case", text: "B", kids: []))) == "A"
do
  match v
    case VInfo(type_name: t, case_node: _) then t
  end
end

fn vinfo_case(v: VInfo) -> Node
  ensures true
  example n_text(n: vinfo_case(v: VInfo(type_name: "A", case_node: bare(kind: "case", text: "B", kids: [])))) == "B"
do
  match v
    case VInfo(type_name: _, case_node: c) then c
  end
end

fn type_is_user(cx: Cx, name: Str) -> Bool
  ensures true
  example not type_is_user(cx: cx_empty(), name: "Option")
do
  match dict_get(dict: cx_types(cx: cx), key: name)
    case Some(value: t) then tinfo_user(t: t)
    case None then false
  end
end

fn tinfo_user(t: TInfo) -> Bool
  ensures true
  example tinfo_user(t: TInfo(name: "A", params: [], cases: [], user: true))
do
  match t
    case TInfo(name: _, params: _, cases: _, user: u) then u
  end
end

fn tinfo(cx: Cx, name: Str) -> TInfo
  ensures true
  example tinfo(cx: cx_empty(), name: "X") == TInfo(name: "X", params: [], cases: [], user: false)
do
  match dict_get(dict: cx_types(cx: cx), key: name)
    case Some(value: t) then t
    case None then TInfo(name: name, params: [], cases: [], user: false)
  end
end

fn tinfo_cases(t: TInfo) -> List[Node]
  ensures true
  example tinfo_cases(t: TInfo(name: "X", params: [], cases: [], user: false)) == []
do
  match t
    case TInfo(name: _, params: _, cases: cs, user: _) then cs
  end
end

# 関数を1つ表に入れる（名前の重なりは E203）
fn add_fn(s: Setup, f: Node) -> Setup
  ensures true
  example dict_has(dict: cx_fns(cx: setup_cx(s: add_fn(s: Setup(cx: cx_empty(), st: st_new(), user: true, tname: "", seen: []), f: bare(kind: "fn", text: "f", kids: [])))), key: "f")
do
  let name: Str = n_text(n: f)
  match s
    case Setup(cx: cx, st: st, user: u, tname: tn, seen: sn) then if dict_has(dict: cx_fns(cx: cx), key: name) or is_builtin(name: name) or dict_has(dict: cx_variants(cx: cx), key: name) then Setup(cx: cx, st: report(st: st, code: "E203", n: f, message: "function '" ++ name ++ "' is already defined" ++ when
        is_builtin(name: name) then " (built-in)"
        dict_has(dict: cx_variants(cx: cx), key: name) then " (as a case of a type)"
        else ""
      end), user: u, tname: tn, seen: sn) else
      match cx
        case Cx(types: ts, variants: vs, fns: fs, fn_name: fnm, place: p) then Setup(cx: Cx(types: ts, variants: vs, fns: dict_put(dict: fs, key: name, value: f), fn_name: fnm, place: p), st: st, user: u, tname: tn, seen: append(list: sn, item: name))
      end
    end
  end
end

# ---- case を使うときの型 ----

type Inst
  case Inst(self: Ty, subst: Dict[Ty], st: St)
end

# 型の T を新しい型変数にして、その型（self）と置きかえ（subst）を返す
fn instantiate(st: St, info: TInfo) -> Inst
  ensures true
  example instantiate(st: st_new(), info: TInfo(name: "A", params: [], cases: [], user: true)) == Inst(self: t_data(name: "A", args: []), subst: no_subst(), st: st_new())
do
  match info
    case TInfo(name: name, params: ps, cases: _, user: _) then if ps == [] then Inst(self: t_data(name: name, args: []), subst: no_subst(), st: st) else
      let v: TS = fresh(st: st)
      Inst(self: t_data(name: name, args: [ts_ty(r: v)]), subst: dict(keys: ["T"], values: [ts_ty(r: v)]), st: ts_st(r: v))
    end
  end
end

fn inst_self(i: Inst) -> Ty
  ensures true
  example inst_self(i: Inst(self: tk(k: "Int"), subst: no_subst(), st: st_new())) == tk(k: "Int")
do
  match i
    case Inst(self: s, subst: _, st: _) then s
  end
end

fn inst_st(i: Inst) -> St
  ensures true
  example inst_st(i: Inst(self: tk(k: "Int"), subst: no_subst(), st: st_new())) == st_new()
do
  match i
    case Inst(self: _, subst: _, st: s) then s
  end
end

fn inst_subst(i: Inst) -> Dict[Ty]
  ensures true
  example inst_subst(i: Inst(self: tk(k: "Int"), subst: no_subst(), st: st_new())) == no_subst()
do
  match i
    case Inst(self: _, subst: s, st: _) then s
  end
end

# case の書き方（エラーの直し方に使う）
fn has_fields(v: Node) -> Bool
  ensures true
  example not has_fields(v: bare(kind: "case", text: "A", kids: []))
do
  n_kids(n: v) != []
end

# ---- 式 ----

# 木 e の型を調べる
fn expr(cx: Cx, env: Env, st: St, e: Node) -> TS
  ensures true
  example ts_ty(r: expr(cx: cx_empty(), env: env_new(), st: st_new(), e: bare(kind: "int", text: "1", kids: []))) == tk(k: "Int")
do
  let k: Str = n_kind(n: e)
  when
    k == "int" then TS(ty: tk(k: "Int"), st: st)
    k == "str" then TS(ty: tk(k: "Str"), st: st)
    k == "bool" then TS(ty: tk(k: "Bool"), st: st)
    k == "unit" then TS(ty: tk(k: "Unit"), st: st)
    k == "var" then var_expr(cx: cx, env: env, st: st, e: e)
    k == "list" then list_expr(cx: cx, env: env, st: st, e: e)
    k == "un" then un_expr(cx: cx, env: env, st: st, e: e)
    k == "bin" then bin_expr(cx: cx, env: env, st: st, e: e)
    k == "if" then if_expr(cx: cx, env: env, st: st, e: e)
    k == "call" then call_expr(cx: cx, env: env, st: st, e: e)
    k == "match" then match_expr(cx: cx, env: env, st: st, e: e)
    else TS(ty: t_err(), st: report(st: st, code: "E000", n: e, message: "internal: unknown node " ++ k))
  end
end

fn fail_ts(st: St, code: Str, n: Node, message: Str) -> TS
  ensures true
  example ts_ty(r: fail_ts(st: st_new(), code: "E200", n: bare(kind: "x", text: "", kids: []), message: "m")) == t_err()
do
  TS(ty: t_err(), st: report(st: st, code: code, n: n, message: message))
end

fn var_expr(cx: Cx, env: Env, st: St, e: Node) -> TS
  ensures true
  example ts_ty(r: var_expr(cx: cx_empty(), env: env_set(env: env_new(), name: "x", t: tk(k: "Int")), st: st_new(), e: bare(kind: "var", text: "x", kids: []))) == tk(k: "Int")
do
  let name: Str = n_text(n: e)
  match env_get(env: env, name: name)
    case Some(value: t) then TS(ty: t, st: st)
    case None then
      match dict_get(dict: cx_variants(cx: cx), key: name)
        case Some(value: vi) then if has_fields(v: vinfo_case(v: vi)) then fail_ts(st: st, code: "E202", n: e, message: "case '" ++ name ++ "' has fields and must be called with them") else
          let inst: Inst = instantiate(st: st, info: tinfo(cx: cx, name: vinfo_type(v: vi)))
          TS(ty: inst_self(i: inst), st: inst_st(i: inst))
        end
        case None then var_fallback(cx: cx, st: st, e: e, name: name)
      end
  end
end

fn var_fallback(cx: Cx, st: St, e: Node, name: Str) -> TS
  ensures true
  example ts_ty(r: var_fallback(cx: cx_empty(), st: st_new(), e: bare(kind: "var", text: "nil", kids: []), name: "nil")) == t_err()
do
  when
    in_table(table: " null nil undefined None_ ", word: name) then fail_ts(st: st, code: "E200", n: e, message: "there is no '" ++ name ++ "'")
    dict_has(dict: cx_fns(cx: cx), key: name) then
    fn_value(st: st, e: e, name: name, s: fn_sig(f: fn_node(cx: cx, name: name)))
    is_builtin(name: name) then fail_ts(st: st, code: "E201", n: e, message: "built-in '" ++ name ++ "' cannot be passed as a value")
    else fail_ts(st: st, code: "E200", n: e, message: "unknown name '" ++ name ++ "'")
  end
end

fn fn_value(st: St, e: Node, name: Str, s: Sig) -> TS
  ensures true
  example ts_ty(r: fn_value(st: st_new(), e: bare(kind: "var", text: "f", kids: []), name: "f", s: Sig(names: [], tys: [], ret: tk(k: "Int"), ctor: false))) == t_fn(params: [], ret: tk(k: "Int"))
do
  if any(list: sig_tys(s: s), func: is_cap_ty) then fail_ts(st: st, code: "E304", n: e, message: "'" ++ name ++ "' takes a capability and cannot be passed as a value") else TS(ty: t_fn(params: sig_tys(s: s), ret: sig_ret(s: s)), st: st) end
end

fn fn_node(cx: Cx, name: Str) -> Node
  ensures true
  example n_kind(n: fn_node(cx: cx_empty(), name: "f")) == "none"
do
  match dict_get(dict: cx_fns(cx: cx), key: name)
    case Some(value: f) then f
    case None then bare(kind: "none", text: "", kids: [])
  end
end

# 並びを回す途中（cx・env は変わらない。ty は今の型、n は何番目か、ok は続けるか）
type W
  case W(cx: Cx, env: Env, st: St, ty: Ty, n: Int, ok: Bool)
end

fn w_st(w: W) -> St
  ensures true
  example w_st(w: W(cx: cx_empty(), env: env_new(), st: st_new(), ty: t_err(), n: 0, ok: true)) == st_new()
do
  match w
    case W(cx: _, env: _, st: s, ty: _, n: _, ok: _) then s
  end
end

fn w_ty(w: W) -> Ty
  ensures true
  example w_ty(w: W(cx: cx_empty(), env: env_new(), st: st_new(), ty: t_err(), n: 0, ok: true)) == t_err()
do
  match w
    case W(cx: _, env: _, st: _, ty: t, n: _, ok: _) then t
  end
end

fn w_env(w: W) -> Env
  ensures true
  example w_env(w: W(cx: cx_empty(), env: env_new(), st: st_new(), ty: t_err(), n: 0, ok: true)) == env_new()
do
  match w
    case W(cx: _, env: e, st: _, ty: _, n: _, ok: _) then e
  end
end

fn w_ok(w: W) -> Bool
  ensures true
  example w_ok(w: W(cx: cx_empty(), env: env_new(), st: st_new(), ty: t_err(), n: 0, ok: true))
do
  match w
    case W(cx: _, env: _, st: _, ty: _, n: _, ok: o) then o
  end
end

fn list_expr(cx: Cx, env: Env, st: St, e: Node) -> TS
  ensures true
  example show_list(r: list_expr(cx: cx_empty(), env: env_new(), st: st_new(), e: bare(kind: "list", text: "", kids: [bare(kind: "int", text: "1", kids: [])]))) == "List[Int]"
do
  let item: TS = fresh(st: st)
  let done: W = fold(list: n_kids(n: e), init: W(cx: cx, env: env, st: ts_st(r: item), ty: ts_ty(r: item), n: 0, ok: true), func: list_item)
  TS(ty: t_list(of: ts_ty(r: item)), st: w_st(w: done))
end

fn show_list(r: TS) -> Str
  ensures true
  example show_list(r: TS(ty: tk(k: "Int"), st: st_new())) == "Int"
do
  show_ty(st: ts_st(r: r), t: ts_ty(r: r))
end

fn list_item(w: W, it: Node) -> W
  ensures true
  example w_ok(w: list_item(w: W(cx: cx_empty(), env: env_new(), st: st_new(), ty: tk(k: "Int"), n: 0, ok: true), it: bare(kind: "int", text: "1", kids: [])))
do
  match w
    case W(cx: cx, env: env, st: st, ty: item, n: idx, ok: o) then W(cx: cx, env: env, st: list_item_st(cx: cx, env: env, st: st, item: item, idx: idx, it: it), ty: item, n: idx + 1, ok: o)
  end
end

fn list_item_st(cx: Cx, env: Env, st: St, item: Ty, idx: Int, it: Node) -> St
  ensures true
  example list_item_st(cx: cx_empty(), env: env_new(), st: st_new(), item: tk(k: "Int"), idx: 0, it: bare(kind: "int", text: "1", kids: [])) == st_new()
do
  let r: TS = expr(cx: cx, env: env, st: st, e: it)
  let t: Ty = ts_ty(r: r)
  let st2: St = if is_cap(st: ts_st(r: r), t: t) then report(st: ts_st(r: r), code: "E309", n: it, message: "capabilities cannot be put in a list") else ts_st(r: r) end
  let u: UR = unify(st: st2, a: item, b: t)
  if ur_ok(r: u) then ur_st(r: u) else report(st: ur_st(r: u), code: "E201", n: it, message: "list item " ++ to_str(value: idx + 1) ++ " is " ++ show_ty(st: ur_st(r: u), t: t) ++ " but earlier items are " ++ show_ty(st: ur_st(r: u), t: item)) end
end

fn un_expr(cx: Cx, env: Env, st: St, e: Node) -> TS
  ensures true
  example ts_ty(r: un_expr(cx: cx_empty(), env: env_new(), st: st_new(), e: bare(kind: "un", text: "-", kids: [bare(kind: "int", text: "1", kids: [])]))) == tk(k: "Int")
do
  let r: TS = expr(cx: cx, env: env, st: st, e: first_kid(n: e))
  let want: Ty = if n_text(n: e) == "not" then tk(k: "Bool") else tk(k: "Int") end
  let u: UR = unify(st: ts_st(r: r), a: want, b: ts_ty(r: r))
  TS(ty: want, st: if ur_ok(r: u) then ur_st(r: u) else report(st: ur_st(r: u), code: "E201", n: e, message: "'" ++ n_text(n: e) ++ "' needs " ++ type_str(t: want) ++ " but got " ++ show_ty(st: ur_st(r: u), t: ts_ty(r: r))) end)
end

fn if_expr(cx: Cx, env: Env, st: St, e: Node) -> TS
  ensures true
  example ts_ty(r: if_expr(cx: cx_empty(), env: env_new(), st: st_new(), e: bare(kind: "if", text: "", kids: [bare(kind: "bool", text: "true", kids: []), bare(kind: "block", text: "", kids: [bare(kind: "int", text: "1", kids: [])]), bare(kind: "block", text: "", kids: [bare(kind: "int", text: "2", kids: [])])]))) == tk(k: "Int")
do
  let c: TS = expr(cx: cx, env: env, st: st, e: kid_at(n: e, i: 0))
  let uc: UR = unify(st: ts_st(r: c), a: tk(k: "Bool"), b: ts_ty(r: c))
  let st1: St = if ur_ok(r: uc) then ur_st(r: uc) else report(st: ur_st(r: uc), code: "E201", n: e, message: "if condition must be Bool but is " ++ show_ty(st: ur_st(r: uc), t: ts_ty(r: c))) end
  let a: TS = check_block(cx: cx, env: env, st: st1, b: kid_at(n: e, i: 1))
  let b: TS = check_block(cx: cx, env: env, st: ts_st(r: a), b: kid_at(n: e, i: 2))
  let u: UR = unify(st: ts_st(r: b), a: ts_ty(r: a), b: ts_ty(r: b))
  if ur_ok(r: u) then TS(ty: ts_ty(r: a), st: ur_st(r: u)) else fail_ts(st: ur_st(r: u), code: "E201", n: e, message: "the then branch gives " ++ show_ty(st: ur_st(r: u), t: ts_ty(r: a)) ++ " but the else branch gives " ++ show_ty(st: ur_st(r: u), t: ts_ty(r: b))) end
end

# ---- 演算子 ----

type BinSt
  case BinSt(st: St, bad: Bool)
end

# want に合わなければ E201（side は left・right）
fn need(st: BinSt, e: Node, want: Ty, t: Ty, side: Str) -> BinSt
  ensures true
  example need(st: BinSt(st: st_new(), bad: false), e: bare(kind: "bin", text: "+", kids: []), want: tk(k: "Int"), t: tk(k: "Int"), side: "left") == BinSt(st: st_new(), bad: false)
do
  match st
    case BinSt(st: s, bad: b) then need_in(s: s, b: b, e: e, want: want, t: t, side: side)
  end
end

fn need_in(s: St, b: Bool, e: Node, want: Ty, t: Ty, side: Str) -> BinSt
  ensures true
  example need_in(s: st_new(), b: false, e: bare(kind: "bin", text: "+", kids: []), want: tk(k: "Int"), t: tk(k: "Int"), side: "left") == BinSt(st: st_new(), bad: false)
do
  let u: UR = unify(st: s, a: want, b: t)
  if ur_ok(r: u) then BinSt(st: ur_st(r: u), bad: b) else BinSt(st: report(st: ur_st(r: u), code: "E201", n: e, message: "'" ++ n_text(n: e) ++ "' needs " ++ type_str(t: want) ++ " on the " ++ side ++ " but got " ++ show_ty(st: ur_st(r: u), t: t)), bad: true) end
end

fn bin_expr(cx: Cx, env: Env, st: St, e: Node) -> TS
  ensures true
  example ts_ty(r: bin_expr(cx: cx_empty(), env: env_new(), st: st_new(), e: bare(kind: "bin", text: "<", kids: [bare(kind: "int", text: "1", kids: []), bare(kind: "int", text: "2", kids: [])]))) == tk(k: "Bool")
do
  let l: TS = expr(cx: cx, env: env, st: st, e: kid_at(n: e, i: 0))
  let r: TS = expr(cx: cx, env: env, st: ts_st(r: l), e: kid_at(n: e, i: 1))
  let op: Str = n_text(n: e)
  let lt: Ty = ts_ty(r: l)
  let rt: Ty = ts_ty(r: r)
  let s0: BinSt = BinSt(st: ts_st(r: r), bad: false)
  when
    in_table(table: " + - * / % ", word: op) then bin_done(r: need(st: need(st: s0, e: e, want: tk(k: "Int"), t: lt, side: "left"), e: e, want: tk(k: "Int"), t: rt, side: "right"), ty_ok: tk(k: "Int"), fail_err: true)
    in_table(table: " < <= > >= ", word: op) then bin_done(r: need(st: need(st: s0, e: e, want: tk(k: "Int"), t: lt, side: "left"), e: e, want: tk(k: "Int"), t: rt, side: "right"), ty_ok: tk(k: "Bool"), fail_err: false)
    op == "and" or op == "or" then bin_done(r: need(st: need(st: s0, e: e, want: tk(k: "Bool"), t: lt, side: "left"), e: e, want: tk(k: "Bool"), t: rt, side: "right"), ty_ok: tk(k: "Bool"), fail_err: false)
    op == "==" or op == "!=" then eq_expr(st: ts_st(r: r), e: e, l: lt, r: rt)
    else concat_expr(st: ts_st(r: r), e: e, l: lt, r: rt)
  end
end

fn bin_done(r: BinSt, ty_ok: Ty, fail_err: Bool) -> TS
  ensures true
  example ts_ty(r: bin_done(r: BinSt(st: st_new(), bad: true), ty_ok: tk(k: "Int"), fail_err: true)) == t_err()
do
  match r
    case BinSt(st: s, bad: b) then TS(ty: if b and fail_err then t_err() else ty_ok end, st: s)
  end
end

fn eq_expr(st: St, e: Node, l: Ty, r: Ty) -> TS
  ensures ts_ty(r: result) == tk(k: "Bool")
  example ts_ty(r: eq_expr(st: st_new(), e: bare(kind: "bin", text: "==", kids: []), l: tk(k: "Int"), r: tk(k: "Int"))) == tk(k: "Bool")
do
  let u: UR = unify(st: st, a: l, b: r)
  let st1: St = if ur_ok(r: u) then ur_st(r: u) else report(st: ur_st(r: u), code: "E201", n: e, message: "cannot compare " ++ show_ty(st: ur_st(r: u), t: l) ++ " with " ++ show_ty(st: ur_st(r: u), t: r)) end
  let st2: St = if ty_k(t: prune(st: st1, t: l)) == "Fn" then report(st: st1, code: "E201", n: e, message: "functions cannot be compared") else st1 end
  TS(ty: tk(k: "Bool"), st: if is_cap(st: st2, t: l) then report(st: st2, code: "E309", n: e, message: "capabilities cannot be compared") else st2 end)
end

fn concat_expr(st: St, e: Node, l: Ty, r: Ty) -> TS
  ensures true
  example ts_ty(r: concat_expr(st: st_new(), e: bare(kind: "bin", text: "++", kids: []), l: tk(k: "Int"), r: tk(k: "Int"))) == t_err()
do
  if not in_table(table: " Str List Var Err ", word: ty_k(t: prune(st: st, t: l))) then fail_ts(st: st, code: "E201", n: e, message: "'++' joins Str or List but the left side is " ++ show_ty(st: st, t: l)) else
    let u: UR = unify(st: st, a: l, b: r)
    if ur_ok(r: u) then TS(ty: l, st: ur_st(r: u)) else fail_ts(st: ur_st(r: u), code: "E201", n: e, message: "'++' needs the same type on both sides but got " ++ show_ty(st: ur_st(r: u), t: l) ++ " and " ++ show_ty(st: ur_st(r: u), t: r)) end
  end
end

# ---- 呼び出し ----

fn call_expr(cx: Cx, env: Env, st: St, e: Node) -> TS
  ensures true
  example ts_ty(r: call_expr(cx: cx_empty(), env: env_new(), st: st_new(), e: bare(kind: "call", text: "str_len", kids: [bare(kind: "arg", text: "text", kids: [bare(kind: "str", text: "a", kids: [])])]))) == tk(k: "Int")
do
  let name: Str = n_text(n: e)
  match dict_get(dict: cx_variants(cx: cx), key: name)
    case Some(value: vi) then ctor_call(cx: cx, env: env, e: e, vi: vi, inst: instantiate(st: st, info: tinfo(cx: cx, name: vinfo_type(v: vi))))
    case None then when
      dict_has(dict: cx_fns(cx: cx), key: name) then call_with(cx: cx, env: env, st: st, e: e, sig: fn_sig(f: fn_node(cx: cx, name: name)))
      is_builtin(name: name) then
      match builtin_sig(st: st, name: name)
        case SigSt(sig: s, st: st2) then call_with(cx: cx, env: env, st: st2, e: e, sig: s)
      end
      else TS(ty: t_err(), st: w_st(w: fold(list: n_kids(n: e), init: W(cx: cx, env: env, st: report(st: st, code: "E200", n: e, message: "unknown function '" ++ name ++ "'"), ty: t_err(), n: 0, ok: true), func: arg_only)))
    end
  end
end

fn ctor_call(cx: Cx, env: Env, e: Node, vi: VInfo, inst: Inst) -> TS
  ensures true
  example ts_ty(r: ctor_call(cx: cx_empty(), env: env_new(), e: bare(kind: "call", text: "A", kids: []), vi: VInfo(type_name: "T", case_node: bare(kind: "case", text: "A", kids: [])), inst: Inst(self: t_data(name: "T", args: []), subst: no_subst(), st: st_new()))) == t_data(name: "T", args: [])
do
  if not has_fields(v: vinfo_case(v: vi)) then TS(ty: inst_self(i: inst), st: report(st: inst_st(i: inst), code: "E202", n: e, message: "case '" ++ n_text(n: e) ++ "' has no fields")) else call_with(cx: cx, env: env, st: inst_st(i: inst), e: e, sig: ctor_sig(v: vinfo_case(v: vi), self: inst_self(i: inst), subst: inst_subst(i: inst))) end
end

# 知らない関数の引数も、中のエラーを見せるために調べる
fn arg_only(w: W, a: Node) -> W
  ensures true
  example w_st(w: arg_only(w: W(cx: cx_empty(), env: env_new(), st: st_new(), ty: t_err(), n: 0, ok: true), a: bare(kind: "arg", text: "x", kids: [bare(kind: "int", text: "1", kids: [])]))) == st_new()
do
  match w
    case W(cx: cx, env: env, st: st, ty: t, n: n, ok: o) then W(cx: cx, env: env, st: ts_st(r: expr(cx: cx, env: env, st: st, e: first_kid(n: a))), ty: t, n: n, ok: o)
  end
end

fn ctor_sig(v: Node, self: Ty, subst: Dict[Ty]) -> Sig
  ensures true
  example sig_ctor(s: ctor_sig(v: bare(kind: "case", text: "A", kids: []), self: t_err(), subst: no_subst()))
do
  Sig(names: kid_names(ns: n_kids(n: v)), tys: field_tys_out(acc: fold(list: n_kids(n: v), init: FieldTys(subst: subst, out: []), func: field_ty_step)), ret: self, ctor: true)
end

type FieldTys
  case FieldTys(subst: Dict[Ty], out: List[Ty])
end

fn field_tys_out(acc: FieldTys) -> List[Ty]
  ensures true
  example field_tys_out(acc: FieldTys(subst: no_subst(), out: [])) == []
do
  match acc
    case FieldTys(subst: _, out: xs) then xs
  end
end

fn field_ty_step(acc: FieldTys, f: Node) -> FieldTys
  ensures true
  example field_ty_step(acc: FieldTys(subst: no_subst(), out: []), f: bare(kind: "field", text: "x", kids: [bare(kind: "t", text: "Int", kids: [])])) == FieldTys(subst: no_subst(), out: [tk(k: "Int")])
do
  match acc
    case FieldTys(subst: s, out: xs) then FieldTys(subst: s, out: append(list: xs, item: from_ast(n: first_kid(n: f), subst: s)))
  end
end

fn arg_name(a: Node) -> Str
  ensures true
  example arg_name(a: bare(kind: "arg", text: "x", kids: [])) == "x"
do
  n_text(n: a)
end

fn find_arg(args: List[Node], name: Str) -> Node
  ensures true
  example n_kind(n: find_arg(args: [], name: "x")) == "none"
do
  match at(list: args, index: index_of(xs: map(list: args, func: arg_name), x: name))
    case Some(value: a) then a
    case None then bare(kind: "none", text: "", kids: [])
  end
end

# 型紙（html・sql）の穴の数
fn count_holes(text: Str, hole: Str) -> Int
  ensures result >= 0
  example count_holes(text: "<p>{}</p>{}", hole: "{}") == 2
do
  if hole == "" then 0 else len(list: split(text: text, by: hole)) - 1 end
end

# html・sql の型紙は書いたままの文字で（E310）、穴と値の数が同じ（E311）
fn template_check(st: St, e: Node) -> St
  ensures true
  example diag_count(st: template_check(st: st_new(), e: bare(kind: "call", text: "html", kids: [bare(kind: "arg", text: "template", kids: [bare(kind: "var", text: "t", kids: [])])]))) == 1
do
  let name: Str = n_text(n: e)
  let hole: Str = if name == "html" then "{}" else "?" end
  let t: Node = find_arg(args: n_kids(n: e), name: "template")
  let v: Node = find_arg(args: n_kids(n: e), name: "values")
  let st1: St = if n_kind(n: t) != "none" and n_kind(n: first_kid(n: t)) != "str" then report(st: st, code: "E310", n: t, message: "the template of " ++ name ++ " must be written as a literal string") else st end
  if n_kind(n: t) != "none" and n_kind(n: first_kid(n: t)) == "str" and n_kind(n: v) != "none" and n_kind(n: first_kid(n: v)) == "list" and count_holes(text: n_text(n: first_kid(n: t)), hole: hole) != len(list: n_kids(n: first_kid(n: v))) then report(st: st1, code: "E311", n: v, message: "the template has " ++ to_str(value: count_holes(text: n_text(n: first_kid(n: t)), hole: hole)) ++ " hole(s) '" ++ hole ++ "' but " ++ to_str(value: len(list: n_kids(n: first_kid(n: v)))) ++ " value(s) are given") else st1 end
end

type ArgCk
  case ArgCk(st: St, ok: Bool, given: List[Str], names: List[Str], fname: Str, e: Node)
end

fn argck_st(a: ArgCk) -> St
  ensures true
  example argck_st(a: ArgCk(st: st_new(), ok: true, given: [], names: [], fname: "f", e: bare(kind: "x", text: "", kids: []))) == st_new()
do
  match a
    case ArgCk(st: s, ok: _, given: _, names: _, fname: _, e: _) then s
  end
end

fn argck_ok(a: ArgCk) -> Bool
  ensures true
  example argck_ok(a: ArgCk(st: st_new(), ok: true, given: [], names: [], fname: "f", e: bare(kind: "x", text: "", kids: [])))
do
  match a
    case ArgCk(st: _, ok: o, given: _, names: _, fname: _, e: _) then o
  end
end

# 名前の無い引数・重なり・知らない名前・足りない名前・順番（JS と同じ順に調べる）
fn check_arg_names(st: St, e: Node, names: List[Str]) -> ArgCk
  ensures true
  example argck_ok(a: check_arg_names(st: st_new(), e: bare(kind: "call", text: "f", kids: [bare(kind: "arg", text: "x", kids: [])]), names: ["x"]))
do
  let name: Str = n_text(n: e)
  let given: List[Str] = map(list: n_kids(n: e), func: arg_name)
  if has_str(xs: given, x: "") then ArgCk(st: report(st: st, code: "E206", n: e, message: "arguments to '" ++ name ++ "' must be named"), ok: false, given: given, names: names, fname: name, e: e) else
    let dup: Str = first_dup(xs: given)
    let s1: ArgCk = if dup != "" then ArgCk(st: report(st: st, code: "E202", n: e, message: "argument '" ++ dup ++ "' is given twice"), ok: false, given: given, names: names, fname: name, e: e) else ArgCk(st: st, ok: true, given: given, names: names, fname: name, e: e) end
    let s2: ArgCk = fold(list: given, init: s1, func: extra_step)
    let s3: ArgCk = fold(list: names, init: s2, func: missing_step)
    if argck_ok(a: s3) and given != names then ArgCk(st: report(st: argck_st(a: s3), code: "E207", n: e, message: "arguments to '" ++ name ++ "' are out of order"), ok: true, given: given, names: names, fname: name, e: e) else s3 end
  end
end

type Dup
  case Dup(seen: List[Str], found: Str)
end

# 2回目に出てきた最初の名前（無ければ ""）
fn first_dup(xs: List[Str]) -> Str
  ensures true
  example first_dup(xs: ["a", "b", "a", "b"]) == "a"
  example first_dup(xs: ["a"]) == ""
do
  match fold(list: xs, init: Dup(seen: [], found: ""), func: dup_step)
    case Dup(seen: _, found: f) then f
  end
end

fn dup_step(d: Dup, x: Str) -> Dup
  ensures true
  example dup_step(d: Dup(seen: ["a"], found: ""), x: "a") == Dup(seen: ["a", "a"], found: "a")
do
  match d
    case Dup(seen: s, found: f) then Dup(seen: append(list: s, item: x), found: if f == "" and has_str(xs: s, x: x) then x else f end)
  end
end

fn extra_step(a: ArgCk, n: Str) -> ArgCk
  ensures true
  example argck_ok(a: extra_step(a: ArgCk(st: st_new(), ok: true, given: ["x"], names: ["x"], fname: "f", e: bare(kind: "x", text: "", kids: [])), n: "x"))
do
  match a
    case ArgCk(st: s, ok: o, given: g, names: ns, fname: f, e: e) then if has_str(xs: ns, x: n) then a else ArgCk(st: report(st: s, code: "E202", n: e, message: "'" ++ f ++ "' has no parameter '" ++ n ++ "'"), ok: false, given: g, names: ns, fname: f, e: e) end
  end
end

fn missing_step(a: ArgCk, n: Str) -> ArgCk
  ensures true
  example not argck_ok(a: missing_step(a: ArgCk(st: st_new(), ok: true, given: [], names: ["x"], fname: "f", e: bare(kind: "x", text: "", kids: [])), n: "x"))
do
  match a
    case ArgCk(st: s, ok: o, given: g, names: ns, fname: f, e: e) then if has_str(xs: g, x: n) then a else ArgCk(st: report(st: s, code: "E202", n: e, message: "missing argument '" ++ n ++ "' for '" ++ f ++ "'"), ok: false, given: g, names: ns, fname: f, e: e) end
  end
end

# 引数を1つずつ調べる途中
type AW
  case AW(cx: Cx, env: Env, st: St, sig: Sig, fname: Str, ok: Bool)
end

fn call_with(cx: Cx, env: Env, st: St, e: Node, sig: Sig) -> TS
  ensures true
  example ts_ty(r: call_with(cx: cx_empty(), env: env_new(), st: st_new(), e: bare(kind: "call", text: "f", kids: []), sig: Sig(names: [], tys: [], ret: tk(k: "Int"), ctor: false))) == tk(k: "Int")
do
  let name: Str = n_text(n: e)
  let st1: St = if name == "html" or name == "sql" then template_check(st: st, e: e) else st end
  let names_ck: ArgCk = check_arg_names(st: st1, e: e, names: sig_names(s: sig))
  match fold(list: n_kids(n: e), init: AW(cx: cx, env: env, st: argck_st(a: names_ck), sig: sig, fname: name, ok: argck_ok(a: names_ck)), func: arg_step)
    case AW(cx: _, env: _, st: s, sig: _, fname: _, ok: _) then TS(ty: sig_ret(s: sig), st: s)
  end
end

fn arg_step(w: AW, a: Node) -> AW
  ensures true
  example arg_step(w: AW(cx: cx_empty(), env: env_new(), st: st_new(), sig: Sig(names: ["x"], tys: [tk(k: "Int")], ret: t_err(), ctor: false), fname: "f", ok: true), a: bare(kind: "arg", text: "x", kids: [bare(kind: "int", text: "1", kids: [])])) == AW(cx: cx_empty(), env: env_new(), st: st_new(), sig: Sig(names: ["x"], tys: [tk(k: "Int")], ret: t_err(), ctor: false), fname: "f", ok: true)
do
  match w
    case AW(cx: cx, env: env, st: st, sig: sig, fname: fname, ok: go) then AW(cx: cx, env: env, st: arg_st(cx: cx, env: env, st: st, sig: sig, fname: fname, go: go, a: a), sig: sig, fname: fname, ok: go)
  end
end

fn arg_st(cx: Cx, env: Env, st: St, sig: Sig, fname: Str, go: Bool, a: Node) -> St
  ensures true
  example arg_st(cx: cx_empty(), env: env_new(), st: st_new(), sig: Sig(names: ["x"], tys: [tk(k: "Int")], ret: t_err(), ctor: false), fname: "f", go: true, a: bare(kind: "arg", text: "x", kids: [bare(kind: "int", text: "1", kids: [])])) == st_new()
do
  let aname: Str = n_text(n: a)
  let has_p: Bool = aname != "" and has_str(xs: sig_names(s: sig), x: aname)
  let want: Ty = sig_param(s: sig, name: aname)
  let value: Node = first_kid(n: a)
  if has_p and is_cap(st: st, t: want) and n_kind(n: value) == "var" and not env_has(env: env, name: n_text(n: value)) then cap_missing(cx: cx, env: env, st: st, a: a, fname: fname, cap: ty_k(t: prune(st: st, t: want))) else
    let r: TS = expr(cx: cx, env: env, st: st, e: value)
    let t: Ty = ts_ty(r: r)
    when
      sig_ctor(s: sig) and is_cap(st: ts_st(r: r), t: t) then report(st: ts_st(r: r), code: "E309", n: a, message: "capabilities cannot be stored in " ++ fname)
      not go or aname == "" then ts_st(r: r)
      else arg_type(st: ts_st(r: r), a: a, fname: fname, want: want, t: t)
    end
  end
end

fn arg_type(st: St, a: Node, fname: Str, want: Ty, t: Ty) -> St
  ensures true
  example arg_type(st: st_new(), a: bare(kind: "arg", text: "x", kids: []), fname: "f", want: tk(k: "Int"), t: tk(k: "Int")) == st_new()
do
  let u: UR = unify(st: st, a: want, b: t)
  if ur_ok(r: u) then ur_st(r: u) else report(st: ur_st(r: u), code: "E201", n: a, message: "argument '" ++ n_text(n: a) ++ "' of '" ++ fname ++ "' must be " ++ show_ty(st: ur_st(r: u), t: want) ++ " but got " ++ show_ty(st: ur_st(r: u), t: t)) end
end

# 権利を渡していない呼び出し（E300）
fn cap_missing(cx: Cx, env: Env, st: St, a: Node, fname: Str, cap: Str) -> St
  ensures true
  example diag_count(st: cap_missing(cx: cx_empty(), env: env_new(), st: st_new(), a: bare(kind: "arg", text: "to", kids: []), fname: "print", cap: "Console")) == 1
do
  let own: Str = env_find_cap(st: st, env: env, cap: cap)
  let where: Str = if cx_place(cx: cx) == "body" then "fn " ++ cx_fn_name(cx: cx) else "this " ++ cx_place(cx: cx) end
  report(st: st, code: "E300", n: a, message: "'" ++ fname ++ "' needs a " ++ cap ++ " but " ++ where ++ " was not given one" ++ if own != "" then " (it has '" ++ own ++ "')" else "" end)
end

# ---- match ----

type MW
  case MW(cx: Cx, env: Env, st: St, info: TInfo, subst: Dict[Ty], seen: List[Str], out: Ty, out_ok: Bool)
end

fn match_expr(cx: Cx, env: Env, st: St, e: Node) -> TS
  ensures true
  example ts_ty(r: match_expr(cx: cx_empty(), env: env_new(), st: st_new(), e: bare(kind: "match", text: "", kids: [bare(kind: "int", text: "1", kids: [])]))) == t_err()
do
  let subj: TS = expr(cx: cx, env: env, st: st, e: kid_at(n: e, i: 0))
  let arms: List[Node] = drop(list: n_kids(n: e), count: 1)
  let first: Str = n_text(n: kid_at(n: e, i: 1))
  let st1: St = if ty_k(t: prune(st: ts_st(r: subj), t: ts_ty(r: subj))) == "Var" and dict_has(dict: cx_variants(cx: cx), key: first) then unify_first(cx: cx, st: ts_st(r: subj), t: ts_ty(r: subj), first: first) else ts_st(r: subj) end
  let pt: Ty = prune(st: st1, t: ts_ty(r: subj))
  if ty_k(t: pt) != "Data" then TS(ty: t_err(), st: if ty_k(t: pt) != "Err" then report(st: st1, code: "E201", n: e, message: "match needs a value of a declared type (or Option / Result) but got " ++ show_ty(st: st1, t: ts_ty(r: subj))) else st1 end) else
    let info: TInfo = tinfo(cx: cx, name: ty_name(t: pt))
    let subst: Dict[Ty] = if ty_args(t: pt) == [] then no_subst() else dict(keys: ["T"], values: [ty_arg0(t: pt)]) end
    let out: TS = fresh(st: st1)
    match fold(list: arms, init: MW(cx: cx, env: env, st: ts_st(r: out), info: info, subst: subst, seen: [], out: ts_ty(r: out), out_ok: true), func: arm_step)
      case MW(cx: _, env: _, st: s, info: _, subst: _, seen: seen, out: o, out_ok: good) then TS(ty: if good then o else t_err() end, st: match_missing(cx: cx, st: s, e: e, info: info, seen: seen, arms: arms))
    end
  end
end

fn unify_first(cx: Cx, st: St, t: Ty, first: Str) -> St
  ensures true
  example unify_first(cx: cx_empty(), st: st_new(), t: tk(k: "Int"), first: "X") == st_new()
do
  match dict_get(dict: cx_variants(cx: cx), key: first)
    case Some(value: vi) then unify_inst(t: t, inst: instantiate(st: st, info: tinfo(cx: cx, name: vinfo_type(v: vi))))
    case None then st
  end
end

fn unify_inst(t: Ty, inst: Inst) -> St
  ensures true
  example unify_inst(t: t_err(), inst: Inst(self: tk(k: "Int"), subst: no_subst(), st: st_new())) == st_new()
do
  ur_st(r: unify(st: inst_st(i: inst), a: t, b: inst_self(i: inst)))
end

fn case_names(info: TInfo) -> List[Str]
  ensures true
  example case_names(info: TInfo(name: "A", params: [], cases: [bare(kind: "case", text: "B", kids: [])], user: true)) == ["B"]
do
  kid_names(ns: tinfo_cases(t: info))
end

fn tinfo_name(info: TInfo) -> Str
  ensures true
  example tinfo_name(info: TInfo(name: "A", params: [], cases: [], user: true)) == "A"
do
  match info
    case TInfo(name: n, params: _, cases: _, user: _) then n
  end
end

fn arm_step(w: MW, arm: Node) -> MW
  ensures true
  example arm_step(w: MW(cx: cx_empty(), env: env_new(), st: st_new(), info: TInfo(name: "A", params: [], cases: [], user: true), subst: no_subst(), seen: [], out: t_err(), out_ok: false), arm: bare(kind: "arm", text: "B", kids: [bare(kind: "at", text: "B", kids: []), bare(kind: "int", text: "1", kids: [])])) == MW(cx: cx_empty(), env: env_new(), st: report(st: st_new(), code: "E211", n: bare(kind: "at", text: "B", kids: []), message: "A has no case 'B'"), info: TInfo(name: "A", params: [], cases: [], user: true), subst: no_subst(), seen: [], out: t_err(), out_ok: false)
do
  match w
    case MW(cx: cx, env: env, st: st, info: info, subst: subst, seen: seen, out: out, out_ok: out_ok) then arm_in(cx: cx, env: env, st: st, info: info, subst: subst, seen: seen, out: out, out_ok: out_ok, arm: arm)
  end
end

fn arm_in(cx: Cx, env: Env, st: St, info: TInfo, subst: Dict[Ty], seen: List[Str], out: Ty, out_ok: Bool, arm: Node) -> MW
  ensures true
  example arm_in(cx: cx_empty(), env: env_new(), st: st_new(), info: TInfo(name: "A", params: [], cases: [], user: true), subst: no_subst(), seen: ["B"], out: t_err(), out_ok: false, arm: bare(kind: "arm", text: "C", kids: [bare(kind: "at", text: "C", kids: []), bare(kind: "int", text: "1", kids: [])])) == MW(cx: cx_empty(), env: env_new(), st: report(st: st_new(), code: "E211", n: bare(kind: "at", text: "C", kids: []), message: "A has no case 'C'"), info: TInfo(name: "A", params: [], cases: [], user: true), subst: no_subst(), seen: ["B"], out: t_err(), out_ok: false)
do
  let v: Str = n_text(n: arm)
  let vpos: Node = kid_at(n: arm, i: 0)
  let binds: List[Node] = reverse(list: drop(list: reverse(list: drop(list: n_kids(n: arm), count: 1)), count: 1))
  let value: Node = last_kid(n: arm)
  let tname: Str = tinfo_name(info: info)
  let found: Option[VInfo] = dict_get(dict: cx_variants(cx: cx), key: v)
  let belongs: Bool = match found
    case Some(value: vi) then vinfo_type(v: vi) == tname
    case None then false
  end
  let ck: BW = when
    not belongs then BW(cx: cx, scope: env, st: report(st: st, code: "E211", n: vpos, message: when
      v == "_" and found == None then "'_' cannot be a case: there is no catch-all"
      found != None then "case '" ++ v ++ "' belongs to " ++ found_type(found: found) ++ ", not " ++ tname
      else tname ++ " has no case '" ++ v ++ "'"
    end), fields: [], subst: subst)
    has_str(xs: seen, x: v) then BW(cx: cx, scope: env, st: report(st: st, code: "E211", n: vpos, message: "case '" ++ v ++ "' is written twice"), fields: [], subst: subst)
    else bind_all(cx: cx, env: env, st: st, case_node: found_case(found: found), binds: binds, vpos: vpos, subst: subst)
  end
  let seen2: List[Str] = if belongs and not has_str(xs: seen, x: v) then append(list: seen, item: v) else seen end
  let r: TS = expr(cx: cx, env: bw_scope(w: ck), st: bw_st(w: ck), e: value)
  if not out_ok then MW(cx: cx, env: env, st: ts_st(r: r), info: info, subst: subst, seen: seen2, out: out, out_ok: false) else
    let u: UR = unify(st: ts_st(r: r), a: out, b: ts_ty(r: r))
    if ur_ok(r: u) then MW(cx: cx, env: env, st: ur_st(r: u), info: info, subst: subst, seen: seen2, out: out, out_ok: true) else MW(cx: cx, env: env, st: report(st: ur_st(r: u), code: "E201", n: arm, message: "case " ++ v ++ " gives " ++ show_ty(st: ur_st(r: u), t: ts_ty(r: r)) ++ " but earlier cases give " ++ show_ty(st: ur_st(r: u), t: out)), info: info, subst: subst, seen: seen2, out: out, out_ok: false) end
  end
end

fn bw_scope(w: BW) -> Env
  ensures true
  example bw_scope(w: BW(cx: cx_empty(), scope: env_new(), st: st_new(), fields: [], subst: no_subst())) == env_new()
do
  match w
    case BW(cx: _, scope: s, st: _, fields: _, subst: _) then s
  end
end

fn bw_st(w: BW) -> St
  ensures true
  example bw_st(w: BW(cx: cx_empty(), scope: env_new(), st: st_new(), fields: [], subst: no_subst())) == st_new()
do
  match w
    case BW(cx: _, scope: _, st: s, fields: _, subst: _) then s
  end
end

fn found_type(found: Option[VInfo]) -> Str
  ensures true
  example found_type(found: None) == ""
do
  match found
    case Some(value: vi) then vinfo_type(v: vi)
    case None then ""
  end
end

fn found_case(found: Option[VInfo]) -> Node
  ensures true
  example n_kind(n: found_case(found: None)) == "none"
do
  match found
    case Some(value: vi) then vinfo_case(v: vi)
    case None then bare(kind: "none", text: "", kids: [])
  end
end

# case の欄に名前を付ける途中
type BW
  case BW(cx: Cx, scope: Env, st: St, fields: List[Node], subst: Dict[Ty])
end

# 欄は宣言の順に全部（E212）。名前は新しく（E203）。_ は名前を付けない
fn bind_all(cx: Cx, env: Env, st: St, case_node: Node, binds: List[Node], vpos: Node, subst: Dict[Ty]) -> BW
  ensures true
  example bind_all(cx: cx_empty(), env: env_new(), st: st_new(), case_node: bare(kind: "case", text: "A", kids: []), binds: [], vpos: bare(kind: "at", text: "A", kids: []), subst: no_subst()) == BW(cx: cx_empty(), scope: env_new(), st: st_new(), fields: [], subst: no_subst())
do
  let want: List[Str] = kid_names(ns: n_kids(n: case_node))
  let got: List[Str] = map(list: binds, func: bind_field)
  let st1: St = if want != got then report(st: st, code: "E212", n: vpos, message: "the pattern for " ++ n_text(n: case_node) ++ " must list its fields (" ++ if want == [] then "none" else join(parts: want, by: ", ") end ++ ") in order") else st end
  fold(list: binds, init: BW(cx: cx, scope: env, st: st1, fields: n_kids(n: case_node), subst: subst), func: bind_step)
end

fn bind_field(b: Node) -> Str
  ensures true
  example bind_field(b: bare(kind: "bind", text: "value v", kids: [])) == "value"
do
  get_str(xs: split(text: n_text(n: b), by: " "), i: 0)
end

fn bind_name(b: Node) -> Str
  ensures true
  example bind_name(b: bare(kind: "bind", text: "value v", kids: [])) == "v"
do
  get_str(xs: split(text: n_text(n: b), by: " "), i: 1)
end

fn get_str(xs: List[Str], i: Int) -> Str
  ensures true
  example get_str(xs: ["a"], i: 3) == ""
do
  match at(list: xs, index: i)
    case Some(value: s) then s
    case None then ""
  end
end

fn bind_step(w: BW, b: Node) -> BW
  ensures true
  example bind_step(w: BW(cx: cx_empty(), scope: env_new(), st: st_new(), fields: [], subst: no_subst()), b: bare(kind: "bind", text: "x _", kids: [])) == BW(cx: cx_empty(), scope: env_new(), st: st_new(), fields: [], subst: no_subst())
do
  match w
    case BW(cx: cx, scope: scope, st: st, fields: fields, subst: subst) then if bind_name(b: b) == "_" then w else bind_in(cx: cx, scope: scope, st: st, fields: fields, subst: subst, b: b) end
  end
end

fn bind_in(cx: Cx, scope: Env, st: St, fields: List[Node], subst: Dict[Ty], b: Node) -> BW
  ensures true
  example bw_st(w: bind_in(cx: cx_empty(), scope: env_new(), st: st_new(), fields: [], subst: no_subst(), b: bare(kind: "bind", text: "x y", kids: []))) == st_new()
do
  let name: Str = bind_name(b: b)
  let st1: St = if taken(cx: cx, env: scope, name: name) then report(st: st, code: "E203", n: b, message: "the name '" ++ name ++ "' is already used") else st end
  let field: Node = match at(list: fields, index: index_of(xs: kid_names(ns: fields), x: bind_field(b: b)))
    case Some(value: f) then f
    case None then bare(kind: "none", text: "", kids: [])
  end
  BW(cx: cx, scope: env_set(env: scope, name: name, t: if n_kind(n: field) == "none" then t_err() else from_ast(n: first_kid(n: field), subst: subst) end), st: st1, fields: fields, subst: subst)
end

# 書いていない case（E210）。知らない case があるときは出さない
fn match_missing(cx: Cx, st: St, e: Node, info: TInfo, seen: List[Str], arms: List[Node]) -> St
  ensures true
  example match_missing(cx: cx_empty(), st: st_new(), e: bare(kind: "match", text: "", kids: []), info: TInfo(name: "A", params: [], cases: [], user: true), seen: [], arms: []) == st_new()
do
  let missing: List[Str] = not_in(xs: case_names(info: info), seen: seen)
  let unknown: Bool = has_unknown_arm(cx: cx, tname: tinfo_name(info: info), arms: arms)
  if missing != [] and not unknown then report(st: st, code: "E210", n: e, message: "match on " ++ tinfo_name(info: info) ++ " misses " ++ join(parts: missing, by: ", ")) else st end
end

type NotIn
  case NotIn(seen: List[Str], out: List[Str])
end

# xs のうち seen に無いもの（順はそのまま）
fn not_in(xs: List[Str], seen: List[Str]) -> List[Str]
  ensures len(list: result) <= len(list: xs)
  example not_in(xs: ["a", "b", "c"], seen: ["b"]) == ["a", "c"]
do
  match fold(list: xs, init: NotIn(seen: seen, out: []), func: not_in_step)
    case NotIn(seen: _, out: o) then o
  end
end

fn not_in_step(acc: NotIn, x: Str) -> NotIn
  ensures true
  example not_in_step(acc: NotIn(seen: [], out: []), x: "a") == NotIn(seen: [], out: ["a"])
do
  match acc
    case NotIn(seen: s, out: o) then NotIn(seen: s, out: if has_str(xs: s, x: x) then o else append(list: o, item: x) end)
  end
end

type Unk
  case Unk(cx: Cx, tname: Str, found: Bool)
end

fn has_unknown_arm(cx: Cx, tname: Str, arms: List[Node]) -> Bool
  ensures true
  example not has_unknown_arm(cx: cx_empty(), tname: "A", arms: [])
do
  match fold(list: arms, init: Unk(cx: cx, tname: tname, found: false), func: unknown_step)
    case Unk(cx: _, tname: _, found: f) then f
  end
end

fn unknown_step(u: Unk, arm: Node) -> Unk
  ensures true
  example unknown_step(u: Unk(cx: cx_empty(), tname: "A", found: false), arm: bare(kind: "arm", text: "B", kids: [])) == Unk(cx: cx_empty(), tname: "A", found: true)
do
  match u
    case Unk(cx: cx, tname: t, found: f) then Unk(cx: cx, tname: t, found: f or found_type(found: dict_get(dict: cx_variants(cx: cx), key: n_text(n: arm))) != t)
  end
end

# ---- ブロック ----

fn check_block(cx: Cx, env: Env, st: St, b: Node) -> TS
  ensures true
  example ts_ty(r: check_block(cx: cx_empty(), env: env_new(), st: st_new(), b: bare(kind: "block", text: "", kids: [bare(kind: "int", text: "1", kids: [])]))) == tk(k: "Int")
do
  let kids: List[Node] = n_kids(n: b)
  let w: W = fold(list: reverse(list: drop(list: reverse(list: kids), count: 1)), init: W(cx: cx, env: env, st: st, ty: t_err(), n: 0, ok: true), func: line_step)
  expr(cx: cx, env: w_env(w: w), st: w_st(w: w), e: last_kid(n: b))
end

fn line_step(w: W, l: Node) -> W
  ensures true
  example w_st(w: line_step(w: W(cx: cx_empty(), env: env_new(), st: st_new(), ty: t_err(), n: 0, ok: true), l: bare(kind: "do", text: "", kids: [bare(kind: "unit", text: "", kids: [])]))) == st_new()
do
  match w
    case W(cx: cx, env: env, st: st, ty: t0, n: n0, ok: o) then if n_kind(n: l) == "do" then
        let r: TS = expr(cx: cx, env: env, st: st, e: first_kid(n: l))
        let u: UR = unify(st: ts_st(r: r), a: tk(k: "Unit"), b: ts_ty(r: r))
        W(cx: cx, env: env, st: if ur_ok(r: u) then ur_st(r: u) else report(st: ur_st(r: u), code: "E201", n: l, message: "this line gives " ++ show_ty(st: ur_st(r: u), t: ts_ty(r: r)) ++ " but its value is thrown away") end, ty: t0, n: n0, ok: o)
      else
        let name: Str = n_text(n: l)
        let st1: St = if taken(cx: cx, env: env, name: name) then report(st: st, code: "E203", n: l, message: "the name '" ++ name ++ "' is already used") else st end
        let want: Ty = from_ast(n: kid_at(n: l, i: 0), subst: no_subst())
        let st2: St = if has_cap(t: want) then report(st: st1, code: "E309", n: l, message: "let " ++ name ++ " holds a capability (" ++ type_str(t: want) ++ ")") else st1 end
        let r: TS = expr(cx: cx, env: env, st: st2, e: kid_at(n: l, i: 1))
        let u: UR = unify(st: ts_st(r: r), a: want, b: ts_ty(r: r))
        W(cx: cx, env: env_set(env: env, name: name, t: want), st: if ur_ok(r: u) then ur_st(r: u) else report(st: ur_st(r: u), code: "E201", n: l, message: "let " ++ name ++ " is declared " ++ show_ty(st: ur_st(r: u), t: want) ++ " but the value is " ++ show_ty(st: ur_st(r: u), t: ts_ty(r: r))) end, ty: t0, n: n0, ok: o)
      end
  end
end

# ---- 関数 ----

# 約束（requires・ensures・example）を1つ調べる：Bool でなければ E201
type CW
  case CW(cx: Cx, env: Env, st: St, word: Str)
end

fn clause_step(w: CW, c: Node) -> CW
  ensures true
  example clause_step(w: CW(cx: cx_empty(), env: env_new(), st: st_new(), word: "requires"), c: bare(kind: "clause", text: "true", kids: [bare(kind: "bool", text: "true", kids: [])])) == CW(cx: cx_empty(), env: env_new(), st: st_new(), word: "requires")
do
  match w
    case CW(cx: cx, env: env, st: st, word: word) then CW(cx: cx, env: env, st: clause_st(cx: cx, env: env, st: st, word: word, c: c), word: word)
  end
end

fn clause_st(cx: Cx, env: Env, st: St, word: Str, c: Node) -> St
  ensures true
  example clause_st(cx: cx_empty(), env: env_new(), st: st_new(), word: "requires", c: bare(kind: "clause", text: "true", kids: [bare(kind: "bool", text: "true", kids: [])])) == st_new()
do
  let r: TS = expr(cx: cx, env: env, st: st, e: first_kid(n: c))
  let u: UR = unify(st: ts_st(r: r), a: tk(k: "Bool"), b: ts_ty(r: r))
  if ur_ok(r: u) then ur_st(r: u) else report(st: ur_st(r: u), code: "E201", n: first_kid(n: c), message: word ++ " must be Bool but is " ++ show_ty(st: ur_st(r: u), t: ts_ty(r: r))) end
end

fn check_clauses(cx: Cx, env: Env, st: St, list: List[Node], word: Str) -> St
  ensures true
  example check_clauses(cx: cx_empty(), env: env_new(), st: st_new(), list: [], word: "ensures") == st_new()
do
  match fold(list: list, init: CW(cx: cx, env: env, st: st, word: word), func: clause_step)
    case CW(cx: _, env: _, st: s, word: _) then s
  end
end

type PW
  case PW(cx: Cx, env: Env, st: St)
end

# 引数を表に入れる（名前の重なりは E203）
fn param_step(w: PW, p: Node) -> PW
  ensures true
  example param_step(w: PW(cx: cx_empty(), env: env_new(), st: st_new()), p: bare(kind: "param", text: "x", kids: [bare(kind: "t", text: "Int", kids: [])])) == PW(cx: cx_empty(), env: env_set(env: env_new(), name: "x", t: tk(k: "Int")), st: st_new())
do
  match w
    case PW(cx: cx, env: env, st: st) then PW(cx: cx, env: env_set(env: env, name: n_text(n: p), t: param_ty(p: p)), st: if taken(cx: cx, env: env, name: n_text(n: p)) then report(st: st, code: "E203", n: p, message: "parameter name '" ++ n_text(n: p) ++ "' is already used") else st end)
  end
end

# 引数の型の中に権利を入れていないか（E309）
fn param_cap_step(st: St, p: Node) -> St
  ensures true
  example param_cap_step(st: st_new(), p: bare(kind: "param", text: "x", kids: [bare(kind: "t", text: "Int", kids: [])])) == st_new()
do
  let t: Ty = param_ty(p: p)
  if not is_cap_ty(t: t) and has_cap(t: t) then report(st: st, code: "E309", n: p, message: "parameter '" ++ n_text(n: p) ++ "' puts a capability inside " ++ type_str(t: t)) else st end
end

fn is_cap_param(p: Node) -> Bool
  ensures true
  example is_cap_param(p: bare(kind: "param", text: "c", kids: [bare(kind: "t", text: "Console", kids: [])]))
do
  is_cap_ty(t: param_ty(p: p))
end

fn param_kind(p: Node) -> Str
  ensures true
  example param_kind(p: bare(kind: "param", text: "c", kids: [bare(kind: "t", text: "Console", kids: [])])) == "Console"
do
  ty_k(t: param_ty(p: p))
end

fn is_e300(d: Diag) -> Bool
  ensures true
  example is_e300(d: Diag(file: "", code: "E300", line: 1, col: 1, message: ""))
do
  match d
    case Diag(file: _, code: c, line: _, col: _, message: _) then c == "E300"
  end
end

# 関数を1つ調べる（JS の check の、関数ごとのところと同じ順）
fn check_fn(cx0: Cx, st: St, f: Node) -> St
  ensures true
  example diag_count(st: check_fn(cx0: cx_empty(), st: st_new(), f: get(list: fns_of(text: "fn f() -> Int do 1 end"), index: 0))) == 2
do
  let name: Str = n_text(n: f)
  let cx: Cx = cx_at(cx: cx0, fn_name: name, place: "body")
  let params: List[Node] = n_kids(n: kid_at(n: f, i: 0))
  let pure: Bool = not any(list: params, func: is_cap_param) and name != "main"
  let st1: St = fold(list: params, init: st, func: param_cap_step)
  let ret: Ty = from_ast(n: kid_at(n: f, i: 1), subst: no_subst())
  let st2: St = if has_cap(t: ret) then report(st: st1, code: "E309", n: f, message: "fn " ++ name ++ " returns a capability") else st1 end
  let kinds: List[Str] = map(list: params, func: param_kind)
  let st3: St = if name == "main" and (n_text(n: kid_at(n: f, i: 1)) != "Unit" or not all(list: params, func: is_cap_param) or first_dup(xs: kinds) != "") then report(st: st2, code: "E303", n: f, message: "main may only take capabilities (each type once) and must return Unit") else st2 end
  match fold(list: params, init: PW(cx: cx, env: env_new(), st: st3), func: param_step)
    case PW(cx: _, env: env, st: st4) then check_fn_body(cx: cx, env: env, st4: st4, f: f, ret: ret, pure: pure)
  end
end

fn check_fn_body(cx: Cx, env: Env, st4: St, f: Node, ret: Ty, pure: Bool) -> St
  ensures true
  example diag_count(st: check_fn_body(cx: cx_empty(), env: env_new(), st4: st_new(), f: get(list: fns_of(text: "fn f() -> Int do 1 end"), index: 0), ret: tk(k: "Int"), pure: true)) == 2
do
  let name: Str = n_text(n: f)
  let env_p: Env = env_pure(st: st4, env: env)
  let st5: St = check_clauses(cx: cx_at(cx: cx, fn_name: name, place: "requires"), env: env_p, st: st4, list: n_kids(n: kid_at(n: f, i: 2)), word: "requires")
  let before: Int = diag_count(st: st5)
  let body: Node = kid_at(n: f, i: 5)
  let got: TS = check_block(cx: cx, env: env, st: st5, b: body)
  let u: UR = unify(st: ts_st(r: got), a: ret, b: ts_ty(r: got))
  let st6: St = if ur_ok(r: u) then ur_st(r: u) else report(st: ur_st(r: u), code: "E201", n: last_kid(n: body), message: "fn " ++ name ++ " must return " ++ show_ty(st: ur_st(r: u), t: ret) ++ " but its body gives " ++ show_ty(st: ur_st(r: u), t: ts_ty(r: got))) end
  let needs_cap: Bool = any(list: drop(list: st_diags(st: st6), count: before), func: is_e300)
  let st7: St = if not needs_cap and pure and n_kids(n: kid_at(n: f, i: 3)) == [] then report(st: st6, code: "E401", n: f, message: "pure function '" ++ name ++ "' has no ensures") else st6 end
  let st8: St = if not needs_cap and pure and n_kids(n: kid_at(n: f, i: 4)) == [] then report(st: st7, code: "E402", n: f, message: "pure function '" ++ name ++ "' has no example") else st7 end
  let env_r: Env = if env_has(env: env_p, name: "result") then env_p else env_set(env: env_p, name: "result", t: ret) end
  let st9: St = check_clauses(cx: cx_at(cx: cx, fn_name: name, place: "ensures"), env: env_r, st: st8, list: n_kids(n: kid_at(n: f, i: 3)), word: "ensures")
  check_clauses(cx: cx_at(cx: cx, fn_name: name, place: "example"), env: env_new(), st: st9, list: n_kids(n: kid_at(n: f, i: 4)), word: "example")
end

# 例のための近道：1つのファイルの関数の木
fn fns_of(text: Str) -> List[Node]
  ensures true
  example len(list: fns_of(text: "fn f() -> Int do 1 end")) == 1
do
  match parse(text: text, other_types: [])
    case Ok(value: p) then filter(list: n_kids(n: p), func: is_fn)
    case Err(message: _) then []
  end
end

# プログラムの部品（type か fn の木）と、それを書いたファイル（main のファイルは ""）
type Item
  case Item(file: Str, node: Node)
end

fn item_node(it: Item) -> Node
  ensures true
  example n_text(n: item_node(it: Item(file: "", node: bare(kind: "fn", text: "f", kids: [])))) == "f"
do
  match it
    case Item(file: _, node: n) then n
  end
end

fn item_file(it: Item) -> Str
  ensures true
  example item_file(it: Item(file: "a.ak", node: bare(kind: "fn", text: "f", kids: []))) == "a.ak"
do
  match it
    case Item(file: f, node: _) then f
  end
end

# 1つのファイルの木を部品にする
fn items_of(file: Str, program: Node) -> List[Item]
  ensures len(list: result) == len(list: n_kids(n: program))
  example items_of(file: "a.ak", program: bare(kind: "program", text: "", kids: [bare(kind: "fn", text: "f", kids: [])])) == [Item(file: "a.ak", node: bare(kind: "fn", text: "f", kids: []))]
do
  match fold(list: n_kids(n: program), init: ItemAcc(file: file, out: []), func: item_step)
    case ItemAcc(file: _, out: o) then o
  end
end

type ItemAcc
  case ItemAcc(file: Str, out: List[Item])
end

fn item_step(acc: ItemAcc, n: Node) -> ItemAcc
  ensures true
  example item_step(acc: ItemAcc(file: "", out: []), n: bare(kind: "fn", text: "f", kids: [])) == ItemAcc(file: "", out: [Item(file: "", node: bare(kind: "fn", text: "f", kids: []))])
do
  match acc
    case ItemAcc(file: f, out: o) then ItemAcc(file: f, out: append(list: o, item: Item(file: f, node: n)))
  end
end

fn item_is_type(it: Item) -> Bool
  ensures true
  example item_is_type(it: Item(file: "", node: bare(kind: "type", text: "A", kids: [])))
do
  n_kind(n: item_node(it: it)) == "type"
end

fn item_is_fn(it: Item) -> Bool
  ensures true
  example item_is_fn(it: Item(file: "", node: bare(kind: "fn", text: "f", kids: [])))
do
  n_kind(n: item_node(it: it)) == "fn"
end

fn add_type_item(s: Setup, it: Item) -> Setup
  ensures true
  example dict_has(dict: cx_types(cx: setup_cx(s: add_type_item(s: Setup(cx: cx_empty(), st: st_new(), user: true, tname: "", seen: []), it: Item(file: "", node: bare(kind: "type", text: "A", kids: []))))), key: "A")
do
  add_type(s: setup_with(s: s, cx: setup_cx(s: s), st: st_in(st: setup_st(s: s), file: item_file(it: it))), t: item_node(it: it))
end

fn add_fn_item(s: Setup, it: Item) -> Setup
  ensures true
  example dict_has(dict: cx_fns(cx: setup_cx(s: add_fn_item(s: Setup(cx: cx_empty(), st: st_new(), user: true, tname: "", seen: []), it: Item(file: "", node: bare(kind: "fn", text: "f", kids: []))))), key: "f")
do
  add_fn(s: setup_with(s: s, cx: setup_cx(s: s), st: st_in(st: setup_st(s: s), file: item_file(it: it))), f: item_node(it: it))
end

# 関数の名前と、それを最初に書いたファイル
fn first_files(fns: List[Item]) -> Dict[Str]
  ensures true
  example dict_get(dict: first_files(fns: [Item(file: "a.ak", node: bare(kind: "fn", text: "f", kids: [])), Item(file: "b.ak", node: bare(kind: "fn", text: "f", kids: []))]), key: "f") == Some(value: "a.ak")
do
  fold(list: fns, init: dict(keys: [], values: []), func: first_file_step)
end

fn first_file_step(d: Dict[Str], it: Item) -> Dict[Str]
  ensures true
  example dict_size(dict: first_file_step(d: dict(keys: [], values: []), it: Item(file: "", node: bare(kind: "fn", text: "f", kids: [])))) == 1
do
  if dict_has(dict: d, key: n_text(n: item_node(it: it))) then d else dict_put(dict: d, key: n_text(n: item_node(it: it)), value: item_file(it: it)) end
end

type FW
  case FW(cx: Cx, st: St, firsts: Dict[Str])
end

# 表に入った関数だけを調べる（同じ名前の2つめは E203 で、中は調べない。JS と同じ）
fn fn_step(w: FW, it: Item) -> FW
  ensures true
  example fn_step(w: FW(cx: cx_empty(), st: st_new(), firsts: dict(keys: [], values: [])), it: Item(file: "", node: bare(kind: "fn", text: "f", kids: []))) == FW(cx: cx_empty(), st: st_new(), firsts: dict(keys: [], values: []))
do
  let f: Node = item_node(it: it)
  match w
    case FW(cx: cx, st: st, firsts: fs) then if dict_get(dict: fs, key: n_text(n: f)) != Some(value: item_file(it: it)) or not same_node(a: fn_node(cx: cx, name: n_text(n: f)), b: f) then w else FW(cx: cx, st: check_fn(cx0: cx, st: st_in(st: st, file: item_file(it: it)), f: f), firsts: fs) end
  end
end

fn same_node(a: Node, b: Node) -> Bool
  ensures true
  example same_node(a: bare(kind: "fn", text: "f", kids: []), b: bare(kind: "fn", text: "f", kids: []))
do
  n_line(n: a) == n_line(n: b) and n_col(n: a) == n_col(n: b) and n_text(n: a) == n_text(n: b)
end

# ---- 入口 ----

# プログラム全体（全部のファイルの部品）を調べ、エラーを位置の順に返す（同じ位置は見つけた順。JS と同じくファイルは見ない）
fn check_program(items: List[Item]) -> List[Diag]
  ensures true
  example check_program(items: items_of(file: "", program: program_of(text: "fn f() -> Int ensures true example f() == 1 do 1 end"))) == []
  example check_program(items: items_of(file: "", program: program_of(text: "fn main(console: Console) -> Unit do print(to: console, value: x) end"))) == [Diag(file: "", code: "E200", line: 1, col: 64, message: "unknown name 'x'")]
do
  check_marked(items: mark_user_types(items: items))
end

fn check_marked(items: List[Item]) -> List[Diag]
  ensures true
  example check_marked(items: []) == []
do
  let fns: List[Item] = filter(list: items, func: item_is_fn)
  let s0: Setup = fold(list: builtin_type_nodes(), init: Setup(cx: cx_empty(), st: st_new(), user: false, tname: "", seen: []), func: add_type)
  let s1: Setup = fold(list: filter(list: items, func: item_is_type), init: setup_user(s: s0), func: add_type_item)
  let s2: Setup = fold(list: fns, init: s1, func: add_fn_item)
  match fold(list: fns, init: FW(cx: setup_cx(s: s2), st: setup_st(s: s2), firsts: first_files(fns: fns)), func: fn_step)
    case FW(cx: _, st: s, firsts: _) then sort_diags(ds: st_diags(st: s))
  end
end

# 自分で作った型の名前を書いたところ（木 t）を "@名前" にする。src/parse.js と同じく、自分で作った型は
# 組み込みの型と同じ名前でも自分の型として読む（List・Dict も。Option・Result はいつも組み込み）
fn mark_user_types(items: List[Item]) -> List[Item]
  ensures len(list: result) == len(list: items)
  example n_text(n: first_kid(n: first_kid(n: kid_at(n: item_node(it: get(list: mark_user_types(items: items_of(file: "", program: program_of(text: "type Int case A end fn f(x: Int) -> Int do 1 end"))), index: 1)), i: 0)))) == "@Int"
do
  let names: List[Str] = map(list: filter(list: items, func: item_is_type), func: item_name)
  match fold(list: items, init: Marking(names: names, out: []), func: mark_item)
    case Marking(names: _, out: o) then o
  end
end

fn item_name(it: Item) -> Str
  ensures true
  example item_name(it: Item(file: "", node: bare(kind: "type", text: "A", kids: []))) == "A"
do
  n_text(n: item_node(it: it))
end

type Marking
  case Marking(names: List[Str], out: List[Item])
end

fn mark_item(m: Marking, it: Item) -> Marking
  ensures true
  example mark_item(m: Marking(names: [], out: []), it: Item(file: "", node: bare(kind: "x", text: "", kids: []))) == Marking(names: [], out: [Item(file: "", node: bare(kind: "x", text: "", kids: []))])
do
  match m
    case Marking(names: ns, out: o) then Marking(names: ns, out: append(list: o, item: Item(file: item_file(it: it), node: mark_node(n: item_node(it: it), names: ns))))
  end
end

type MarkKids
  case MarkKids(names: List[Str], out: List[Node])
end

fn mark_node(n: Node, names: List[Str]) -> Node
  ensures true
  example mark_node(n: bare(kind: "t", text: "List", kids: []), names: ["List"]) == bare(kind: "t", text: "@List", kids: [])
  example mark_node(n: bare(kind: "t", text: "Option", kids: []), names: ["Option"]) == bare(kind: "t", text: "Option", kids: [])
do
  if n_kind(n: n) == "t" and has_str(xs: names, x: n_text(n: n)) and n_text(n: n) != "Option" and n_text(n: n) != "Result" then retag_text(n: n, text: "@" ++ n_text(n: n)) else
    match fold(list: n_kids(n: n), init: MarkKids(names: names, out: []), func: mark_kid)
      case MarkKids(names: _, out: ks) then Node(kind: n_kind(n: n), text: n_text(n: n), line: n_line(n: n), col: n_col(n: n), kids: ks)
    end
  end
end

fn retag_text(n: Node, text: Str) -> Node
  ensures true
  example n_text(n: retag_text(n: bare(kind: "t", text: "A", kids: []), text: "@A")) == "@A"
do
  Node(kind: n_kind(n: n), text: text, line: n_line(n: n), col: n_col(n: n), kids: n_kids(n: n))
end

fn mark_kid(m: MarkKids, k: Node) -> MarkKids
  ensures true
  example mark_kid(m: MarkKids(names: [], out: []), k: bare(kind: "x", text: "", kids: [])) == MarkKids(names: [], out: [bare(kind: "x", text: "", kids: [])])
do
  match m
    case MarkKids(names: ns, out: o) then MarkKids(names: ns, out: append(list: o, item: mark_node(n: k, names: ns)))
  end
end

fn program_of(text: Str) -> Node
  ensures true
  example len(list: n_kids(n: program_of(text: "fn f() -> Int do 1 end"))) == 1
do
  match parse(text: text, other_types: [])
    case Ok(value: p) then p
    case Err(message: _) then bare(kind: "program", text: "", kids: [])
  end
end

fn setup_user(s: Setup) -> Setup
  ensures true
  example setup_user(s: Setup(cx: cx_empty(), st: st_new(), user: false, tname: "", seen: [])) == Setup(cx: cx_empty(), st: st_new(), user: true, tname: "", seen: [])
do
  match s
    case Setup(cx: c, st: st, user: _, tname: t, seen: sn) then Setup(cx: c, st: st, user: true, tname: t, seen: sn)
  end
end

fn diag_key(d: Diag) -> Int
  ensures true
  example diag_key(d: Diag(file: "", code: "E1", line: 2, col: 3, message: "")) == 2000003
do
  match d
    case Diag(file: _, code: _, line: l, col: c, message: _) then l * 1000000 + c
  end
end

# 位置の順に並べる。同じ位置は見つけた順のまま（JS の sort と同じく安定）
fn sort_diags(ds: List[Diag]) -> List[Diag]
  ensures len(list: result) == len(list: ds)
  example sort_diags(ds: [Diag(file: "", code: "B", line: 2, col: 1, message: ""), Diag(file: "", code: "A", line: 1, col: 1, message: ""), Diag(file: "", code: "C", line: 2, col: 1, message: "")]) == [Diag(file: "", code: "A", line: 1, col: 1, message: ""), Diag(file: "", code: "B", line: 2, col: 1, message: ""), Diag(file: "", code: "C", line: 2, col: 1, message: "")]
do
  fold(list: ds, init: [], func: insert_diag)
end

# 並んだ xs の、キーが d 以下のものの後ろに d を入れる
fn insert_diag(xs: List[Diag], d: Diag) -> List[Diag]
  ensures len(list: result) == len(list: xs) + 1
  example insert_diag(xs: [Diag(file: "", code: "A", line: 1, col: 1, message: ""), Diag(file: "", code: "B", line: 3, col: 1, message: "")], d: Diag(file: "", code: "C", line: 2, col: 1, message: "")) == [Diag(file: "", code: "A", line: 1, col: 1, message: ""), Diag(file: "", code: "C", line: 2, col: 1, message: ""), Diag(file: "", code: "B", line: 3, col: 1, message: "")]
do
  let k: Int = count_le(xs: xs, key: diag_key(d: d))
  concat(lists: [take(list: xs, count: k), [d], drop(list: xs, count: k)])
end

type Le
  case Le(key: Int, n: Int)
end

fn count_le(xs: List[Diag], key: Int) -> Int
  ensures result >= 0
  example count_le(xs: [Diag(file: "", code: "A", line: 1, col: 1, message: "")], key: 1000001) == 1
do
  match fold(list: xs, init: Le(key: key, n: 0), func: le_step)
    case Le(key: _, n: n) then n
  end
end

fn le_step(acc: Le, d: Diag) -> Le
  ensures true
  example le_step(acc: Le(key: 5, n: 0), d: Diag(file: "", code: "A", line: 0, col: 1, message: "")) == Le(key: 5, n: 1)
do
  match acc
    case Le(key: k, n: n) then Le(key: k, n: if diag_key(d: d) <= k then n + 1 else n end)
  end
end

fn show_diag(d: Diag) -> Str
  ensures true
  example show_diag(d: Diag(file: "", code: "E200", line: 1, col: 2, message: "m")) == "E200 1:2 m"
do
  match d
    case Diag(file: f, code: c, line: l, col: col, message: m) then (if f == "" then "" else f ++ ": " end) ++ c ++ " " ++ to_str(value: l) ++ ":" ++ to_str(value: col) ++ " " ++ m
  end
end
