// 型・名前・引数・副作用・約束の検査。エラーはまとめて返す（1回の実行で直せるものを全部見せる）。
import { diag, suggest } from './errors.js';

export const INT = { k: 'Int' };
export const BOOL = { k: 'Bool' };
export const STR = { k: 'Str' };
export const UNIT = { k: 'Unit' };
const ERR = { k: 'Err' };
export const CONSOLE = { k: 'Console' };
export const FOLDER = { k: 'Folder' };
// 書く権利は読む権利と別の鍵（読むだけのプログラムに書く力を持たせない）
export const OUT_FOLDER = { k: 'OutFolder' };
export const HTML = { k: 'Html' };
export const SQL = { k: 'Sql' };
// 型紙の穴の数（html は {}、sql は ?）
export const HOLE = { html: '{}', sql: '?' };
export const countHoles = (template, hole) => template.split(hole).length - 1;
// 権利（ケーパビリティ）の型。値を作る方法は無く、main が受け取って引数で渡すだけ
const CAPS = ['Console', 'Folder', 'OutFolder'];
const isCap = (t) => CAPS.includes(prune(t).k);
const hasCap = (t) => { t = prune(t); return isCap(t) || ((t.k === 'List' || t.k === 'Dict') && hasCap(t.of)) || (t.k === 'Data' && t.args.some(hasCap)); };
const List = (of) => ({ k: 'List', of });
// 辞書。鍵は Str だけ（選び方を1つにする）。鍵の順（コードポイント順）に並ぶので、回す順はいつも同じ
const Dict = (of) => ({ k: 'Dict', of });
const Data = (name, args = []) => ({ k: 'Data', name, args });
const Option = (of) => Data('Option', [of]);
const Result = (of) => Data('Result', [of]);
// 組み込みの型。T は使うときの型に置きかわる
const T = { k: 'Param', name: 'T' };
export const BUILTIN_TYPES = [
  { name: 'Option', params: ['T'], variants: [{ name: 'Some', fields: [{ name: 'value', type: T }] }, { name: 'None', fields: [] }] },
  { name: 'Result', params: ['T'], variants: [{ name: 'Ok', fields: [{ name: 'value', type: T }] }, { name: 'Err', fields: [{ name: 'message', type: { k: 'Str' } }] }] },
];
const Fn = (params, ret) => ({ k: 'Fn', params, ret });
let varId = 0;
const fresh = () => ({ k: 'Var', id: ++varId, ref: null });

export function prune(t) {
  while (t.k === 'Var' && t.ref) t = t.ref;
  return t;
}

function occurs(v, t) {
  t = prune(t);
  if (t === v) return true;
  if (t.k === 'List' || t.k === 'Dict') return occurs(v, t.of);
  if (t.k === 'Fn') return t.params.some((p) => occurs(v, p)) || occurs(v, t.ret);
  if (t.k === 'Data') return t.args.some((x) => occurs(v, x));
  return false;
}

function unify(a, b) {
  a = prune(a);
  b = prune(b);
  if (a.k === 'Err' || b.k === 'Err') return true;
  if (a.k === 'Var') { if (a !== b) { if (occurs(a, b)) return false; a.ref = b; } return true; }
  if (b.k === 'Var') return unify(b, a);
  if (a.k !== b.k) return false;
  if (a.k === 'List' || a.k === 'Dict') return unify(a.of, b.of);
  if (a.k === 'Data') return a.name === b.name && a.args.every((x, i) => unify(x, b.args[i]));
  if (a.k === 'Fn') {
    if (a.params.length !== b.params.length) return false;
    return a.params.every((p, i) => unify(p, b.params[i])) && unify(a.ret, b.ret);
  }
  return true;
}

export function typeStr(t) {
  t = prune(t);
  if (t.k === 'List') return `List[${typeStr(t.of)}]`;
  if (t.k === 'Dict') return `Dict[${typeStr(t.of)}]`;
  if (t.k === 'Fn') return `fn(${t.params.map(typeStr).join(', ')}) -> ${typeStr(t.ret)}`;
  if (t.k === 'Data') return t.args.length ? `${t.name}[${t.args.map(typeStr).join(', ')}]` : t.name;
  if (t.k === 'Var') return 'T';
  if (t.k === 'Err') return '?';
  return t.k;
}

// 組み込み関数。呼ぶたびに型変数を新しくする。引数はすべて名前つき。
export const BUILTINS = {
  print: () => ({ params: [['to', CONSOLE], ['value', fresh()]], ret: UNIT }),
  // 失敗しうる操作は Result を返す。match で Err も書かないと通らない（例外の見落としを無くす）
  read_text: () => ({ params: [['from', FOLDER], ['path', STR]], ret: Result(STR) }),
  // 書く：まるごと書きかえる。親フォルダが無い・フォルダを指すなら Err（作る・消すことはしない）
  write_text: () => ({ params: [['to', OUT_FOLDER], ['path', STR], ['text', STR]], ret: Result(UNIT) }),
  // バイトの並びを書く（.wasm など文字でないファイル）。どれも 0〜255 でないと R506
  write_bytes: () => ({ params: [['to', OUT_FOLDER], ['path', STR], ['bytes', List(INT)]], ret: Result(UNIT) }),
  parse_int: () => ({ params: [['text', STR]], ret: Option(INT) }),
  lines: () => ({ params: [['text', STR]], ret: List(STR) }),
  html: () => ({ params: [['template', STR], ['values', List(HTML)]], ret: HTML }),
  html_text: () => ({ params: [['value', STR]], ret: HTML }),
  html_join: () => ({ params: [['parts', List(HTML)]], ret: HTML }),
  sql: () => ({ params: [['template', STR], ['values', List(STR)]], ret: SQL }),
  len: () => ({ params: [['list', List(fresh())]], ret: INT }),
  str_len: () => ({ params: [['text', STR]], ret: INT }),
  // 文字（コードポイント）単位で切り出す・数にする・数から作る（字句解析を Akashi で書くため。docs/compiler.md 段階4）
  slice: () => ({ params: [['text', STR], ['from', INT], ['to', INT]], ret: STR }),
  code_of: () => ({ params: [['char', STR]], ret: INT }),
  char_of: () => ({ params: [['code', INT]], ret: STR }),
  to_str: () => ({ params: [['value', fresh()]], ret: STR }),
  range: () => ({ params: [['from', INT], ['to', INT]], ret: List(INT) }),
  get: () => { const a = fresh(); return { params: [['list', List(a)], ['index', INT]], ret: a }; },
  at: () => { const a = fresh(); return { params: [['list', List(a)], ['index', INT]], ret: Option(a) }; },
  find: () => { const a = fresh(); return { params: [['list', List(a)], ['func', Fn([a], BOOL)]], ret: Option(a) }; },
  // 標準の道具（v0.7）。どれも値を返すだけで、外には触らない。文字は文字（コードポイント）単位で数える
  any: () => { const a = fresh(); return { params: [['list', List(a)], ['func', Fn([a], BOOL)]], ret: BOOL }; },
  all: () => { const a = fresh(); return { params: [['list', List(a)], ['func', Fn([a], BOOL)]], ret: BOOL }; },
  reverse: () => { const a = fresh(); return { params: [['list', List(a)]], ret: List(a) }; },
  take: () => { const a = fresh(); return { params: [['list', List(a)], ['count', INT]], ret: List(a) }; },
  drop: () => { const a = fresh(); return { params: [['list', List(a)], ['count', INT]], ret: List(a) }; },
  sort: () => ({ params: [['list', List(INT)]], ret: List(INT) }),
  sum: () => ({ params: [['list', List(INT)]], ret: INT }),
  max: () => ({ params: [['list', List(INT)]], ret: Option(INT) }),
  min: () => ({ params: [['list', List(INT)]], ret: Option(INT) }),
  chars: () => ({ params: [['text', STR]], ret: List(STR) }),
  split: () => ({ params: [['text', STR], ['by', STR]], ret: List(STR) }),
  join: () => ({ params: [['parts', List(STR)], ['by', STR]], ret: STR }),
  contains: () => ({ params: [['text', STR], ['part', STR]], ret: BOOL }),
  starts_with: () => ({ params: [['text', STR], ['prefix', STR]], ret: BOOL }),
  ends_with: () => ({ params: [['text', STR], ['suffix', STR]], ret: BOOL }),
  trim: () => ({ params: [['text', STR]], ret: STR }),
  append: () => { const a = fresh(); return { params: [['list', List(a)], ['item', a]], ret: List(a) }; },
  map: () => { const a = fresh(); const b = fresh(); return { params: [['list', List(a)], ['func', Fn([a], b)]], ret: List(b) }; },
  filter: () => { const a = fresh(); return { params: [['list', List(a)], ['func', Fn([a], BOOL)]], ret: List(a) }; },
  fold: () => { const a = fresh(); const b = fresh(); return { params: [['list', List(a)], ['init', b], ['func', Fn([b, a], b)]], ret: b }; },
  // 辞書（v0.12）。どれも新しい辞書を返し、元は変えない。鍵が重なる dict は R506 で止める（黙って上書きしない）
  dict: () => { const a = fresh(); return { params: [['keys', List(STR)], ['values', List(a)]], ret: Dict(a) }; },
  dict_put: () => { const a = fresh(); return { params: [['dict', Dict(a)], ['key', STR], ['value', a]], ret: Dict(a) }; },
  dict_get: () => { const a = fresh(); return { params: [['dict', Dict(a)], ['key', STR]], ret: Option(a) }; },
  dict_has: () => ({ params: [['dict', Dict(fresh())], ['key', STR]], ret: BOOL }),
  dict_remove: () => { const a = fresh(); return { params: [['dict', Dict(a)], ['key', STR]], ret: Dict(a) }; },
  dict_keys: () => ({ params: [['dict', Dict(fresh())]], ret: List(STR) }),
  dict_values: () => { const a = fresh(); return { params: [['dict', Dict(a)]], ret: List(a) }; },
  dict_size: () => ({ params: [['dict', Dict(fresh())]], ret: INT }),
};

export function fromAst(t, subst = {}) {
  if (t.k === 'List') return List(fromAst(t.of, subst));
  if (t.k === 'Dict') return Dict(fromAst(t.of, subst));
  if (t.k === 'Data') return Data(t.name, t.args.map((x) => fromAst(x, subst)));
  if (t.k === 'Param') return subst[t.name];
  return { k: t.k };
}

function callTemplate(name, params) {
  return `${name}(${params.map(([n]) => `${n}: ...`).join(', ')})`;
}

export function check(program) {
  const diags = [];
  const err = (code, msg, pos, fix) => diags.push(diag(code, msg, pos, fix));
  const fns = new Map();
  // 型と case の表。variants: case の名前 → { type, variant }
  const types = new Map();
  const variants = new Map();
  for (const ty of [...BUILTIN_TYPES, ...(program.types ?? []).map((x) => ({ ...x, params: [], user: true }))]) {
    if (types.has(ty.name) || (ty.user && ['Int', 'Bool', 'Str', 'Unit', 'List', 'Dict', 'Html', 'Sql', 'Console', 'Folder', 'OutFolder'].includes(ty.name))) {
      err('E203', `type '${ty.name}' is already defined`, ty.pos, 'give the type a different name');
      continue;
    }
    types.set(ty.name, ty);
    for (const v of ty.variants) {
      if (variants.has(v.name)) {
        err('E203', `case '${v.name}' is already used${variants.get(v.name).type.user ? '' : ' (built-in)'}`, v.pos, `case names are unique across all types; rename it, e.g. ${ty.name}${v.name}`);
        continue;
      }
      variants.set(v.name, { type: ty, variant: v });
      const seen = new Set();
      for (const f of v.fields) {
        if (seen.has(f.name)) err('E203', `field '${f.name}' appears twice in case ${v.name}`, f.pos, 'give each field its own name');
        seen.add(f.name);
        if (ty.user && hasCap(fromAst(f.type))) err('E309', `field '${f.name}' of ${v.name} holds a capability`, f.pos, 'capabilities cannot be stored in data; pass them as parameters');
      }
    }
  }
  // case を使うときの型：型の T を新しい型変数にして、その型と各欄の型を返す
  const instantiate = (ty) => {
    const subst = Object.fromEntries(ty.params.map((p) => [p, fresh()]));
    return { self: Data(ty.name, ty.params.map((p) => subst[p])), subst };
  };
  const caseTemplate = (v) => (v.fields.length ? `${v.name}(${v.fields.map((f) => `${f.name}: _`).join(', ')})` : v.name);

  for (const f of program.fns) {
    if (fns.has(f.name) || f.name in BUILTINS || variants.has(f.name)) {
      err('E203', `function '${f.name}' is already defined${f.name in BUILTINS ? ' (built-in)' : variants.has(f.name) ? ' (as a case of a type)' : ''}`, f.pos, 'give the function a different name; names are never reused');
      continue;
    }
    fns.set(f.name, f);
  }

  const sigOf = (f) => ({
    params: f.params.map((p) => [p.name, fromAst(p.type)]),
    ret: fromAst(f.ret),
  });

  const allNames = (env) => [...env.keys(), ...fns.keys(), ...Object.keys(BUILTINS), ...variants.keys()];
  const taken = (scope, name) => scope.has(name) || fns.has(name) || name in BUILTINS || variants.has(name);

  function checkBlock(block, env, ctx) {
    const scope = new Map(env);
    for (const l of block.lets) {
      if (l.k === 'do') {
        const t = expr(l.expr, scope, ctx);
        if (!unify(UNIT, t)) err('E201', `this line gives ${typeStr(t)} but its value is thrown away`, l.pos, 'only Unit expressions (like print) can stand alone; keep the value with let name: Type = ..., or make it the last line');
        continue;
      }
      if (taken(scope, l.name)) {
        err('E203', `the name '${l.name}' is already used`, l.pos, `names cannot be reused or shadowed; pick a new name such as ${l.name}2 or a more specific one`);
      }
      const want = fromAst(l.type);
      if (hasCap(want)) err('E309', `let ${l.name} holds a capability (${typeStr(want)})`, l.pos, 'capabilities cannot be stored; pass the parameter itself, e.g. print(to: console, ...)');
      const got = expr(l.value, scope, ctx);
      if (!unify(want, got)) {
        err('E201', `let ${l.name} is declared ${typeStr(want)} but the value is ${typeStr(got)}`, l.pos, `change the declared type to ${typeStr(got)} or change the value`);
      }
      scope.set(l.name, want);
    }
    return expr(block.result, scope, ctx);
  }

  // 式の型を節に残す（コンパイラが使う。型変数は prune で引く）
  function expr(e, env, ctx) {
    const t = exprType(e, env, ctx);
    e.ty = t;
    return t;
  }

  function exprType(e, env, ctx) {
    switch (e.k) {
      case 'int': return INT;
      case 'str': return STR;
      case 'bool': return BOOL;
      case 'unit': return UNIT;
      case 'var': {
        if (env.has(e.name)) return env.get(e.name);
        if (variants.has(e.name)) {
          const { type, variant } = variants.get(e.name);
          if (variant.fields.length) {
            err('E202', `case '${e.name}' has fields and must be called with them`, e.pos, `write ${caseTemplate(variant).replace(/_/g, '...')}`);
            return ERR;
          }
          return instantiate(type).self;
        }
        if (['null', 'nil', 'undefined', 'None_'].includes(e.name)) {
          err('E200', `there is no '${e.name}'`, e.pos, 'a value that may be missing has type Option[T]: write None, and Some(value: x) when there is one');
          return ERR;
        }
        if (fns.has(e.name)) {
          const s = sigOf(fns.get(e.name));
          if (s.params.some(([, t]) => isCap(t))) {
            err('E304', `'${e.name}' takes a capability and cannot be passed as a value`, e.pos, 'only pure functions (no Console / Folder parameters) can be passed to map / filter / fold');
            return ERR;
          }
          return Fn(s.params.map(([, t]) => t), s.ret);
        }
        if (e.name in BUILTINS) {
          err('E201', `built-in '${e.name}' cannot be passed as a value`, e.pos, `wrap it in your own pure function and pass that function's name`);
          return ERR;
        }
        const s = suggest(e.name, allNames(env));
        err('E200', `unknown name '${e.name}'`, e.pos, s ? `did you mean '${s}'?` : 'define it with let, or add it as a parameter');
        return ERR;
      }
      case 'list': {
        const item = fresh();
        e.items.forEach((it, idx) => {
          const t = expr(it, env, ctx);
          if (isCap(t)) err('E309', 'capabilities cannot be put in a list', it.pos ?? e.pos, 'pass the capability itself as an argument instead');
          if (!unify(item, t)) err('E201', `list item ${idx + 1} is ${typeStr(t)} but earlier items are ${typeStr(item)}`, it.pos ?? e.pos, 'all items in a list must have the same type');
        });
        return List(item);
      }
      case 'un': {
        const t = expr(e.arg, env, ctx);
        const want = e.op === 'not' ? BOOL : INT;
        if (!unify(want, t)) err('E201', `'${e.op}' needs ${typeStr(want)} but got ${typeStr(t)}`, e.pos, e.op === 'not' ? 'not works only on Bool; compare first, e.g. not (x == 0)' : 'minus works only on Int');
        return want;
      }
      case 'bin': return binary(e, env, ctx);
      case 'if': {
        const c = expr(e.cond, env, ctx);
        if (!unify(BOOL, c)) err('E201', `if condition must be Bool but is ${typeStr(c)}`, e.pos, 'compare explicitly, e.g. if n != 0 then ... (there is no truthiness)');
        const a = checkBlock(e.thenB, env, ctx);
        const b = checkBlock(e.elseB, env, ctx);
        if (!unify(a, b)) {
          err('E201', `the then branch gives ${typeStr(a)} but the else branch gives ${typeStr(b)}`, e.pos, 'both branches of if must give the same type');
          return ERR;
        }
        return a;
      }
      case 'call': return call(e, env, ctx);
      case 'match': return matchExpr(e, env, ctx);
      default: throw new Error(`internal: unknown node ${e.k}`);
    }
  }

  // match：どの case も1回ずつ。欄は宣言の順に全部書く（使わない欄は _）
  function matchExpr(e, env, ctx) {
    const st = expr(e.subject, env, ctx);
    let pt = prune(st);
    if (pt.k === 'Var') {
      const first = variants.get(e.arms[0].variant);
      if (first) { unify(pt, instantiate(first.type).self); pt = prune(st); }
    }
    if (pt.k !== 'Data') {
      if (pt.k !== 'Err') err('E201', `match needs a value of a declared type (or Option / Result) but got ${typeStr(st)}`, e.pos, 'to choose by a condition on Int, Str or Bool, use when ... then ... else ... end');
      return ERR;
    }
    const ty = types.get(pt.name);
    const subst = Object.fromEntries(ty.params.map((p, i) => [p, pt.args[i]]));
    const seen = new Set();
    let out = fresh();
    let outOk = true;
    for (const arm of e.arms) {
      const found = variants.get(arm.variant);
      const scope = new Map(env);
      if (!found || found.type !== ty) {
        const s = suggest(arm.variant, ty.variants.map((v) => v.name));
        err('E211', found ? `case '${arm.variant}' belongs to ${found.type.name}, not ${ty.name}` : arm.variant === '_' ? "'_' cannot be a case: there is no catch-all" : `${ty.name} has no case '${arm.variant}'`, arm.vpos,
          `the cases of ${ty.name} are ${ty.variants.map((v) => v.name).join(', ')}${s ? `; did you mean ${s}?` : ''}. Write one line for each`);
      } else if (seen.has(arm.variant)) {
        err('E211', `case '${arm.variant}' is written twice`, arm.vpos, 'keep one line per case');
      } else {
        seen.add(arm.variant);
        const v = found.variant;
        const want = v.fields.map((f) => f.name);
        const got = arm.binds.map((b) => b.field);
        if (want.join(',') !== got.join(',')) {
          err('E212', `the pattern for ${v.name} must list its fields (${want.join(', ') || 'none'}) in order`, arm.vpos, `write case ${caseTemplate(v)} then <value>; put a new name instead of _ for each field you use`);
        }
        for (const b of arm.binds) {
          const field = v.fields.find((x) => x.name === b.field);
          if (b.name === '_') continue;
          if (taken(scope, b.name)) err('E203', `the name '${b.name}' is already used`, b.pos, `names cannot be reused or shadowed; pick a new name such as ${b.name}2`);
          scope.set(b.name, field ? fromAst(field.type, subst) : ERR); // 欄の名前が違っても、続きの E200 は出さない
        }
      }
      const t = expr(arm.value, scope, ctx);
      if (outOk && !unify(out, t)) {
        err('E201', `case ${arm.variant} gives ${typeStr(t)} but earlier cases give ${typeStr(out)}`, arm.pos, 'every case of match must give the same type');
        outOk = false;
      }
    }
    const missing = ty.variants.filter((v) => !seen.has(v.name));
    const unknownArm = e.arms.some((a) => variants.get(a.variant)?.type !== ty);
    if (missing.length && !unknownArm) {
      err('E210', `match on ${ty.name} misses ${missing.map((v) => v.name).join(', ')}`, e.pos,
        `add ${missing.map((v) => `case ${caseTemplate(v)} then <value>`).join(' and ')}. Every case must be handled (there is no catch-all, so a new case later is never silently ignored)`);
    }
    return outOk ? out : ERR;
  }

  function binary(e, env, ctx) {
    const l = expr(e.left, env, ctx);
    const r = expr(e.right, env, ctx);
    let bad = false;
    const need = (want, t, side) => {
      if (!unify(want, t)) {
        bad = true;
        const fix = e.op === '+' && prune(t).k === 'Str'
          ? 'use ++ to join strings; + is only for Int'
          : e.op === '+' && prune(t).k === 'List'
            ? 'use ++ to join lists, or append(list: xs, item: x) to add one item'
            : `convert first, e.g. to_str(value: x) for Str; Akashi never converts types automatically`;
        err('E201', `'${e.op}' needs ${typeStr(want)} on the ${side} but got ${typeStr(t)}`, e.pos, fix);
      }
    };
    switch (e.op) {
      case '+': case '-': case '*': case '/': case '%':
        need(INT, l, 'left'); need(INT, r, 'right'); return bad ? ERR : INT;
      case '<': case '<=': case '>': case '>=':
        need(INT, l, 'left'); need(INT, r, 'right'); return BOOL;
      case 'and': case 'or':
        need(BOOL, l, 'left'); need(BOOL, r, 'right'); return BOOL;
      case '==': case '!=':
        if (!unify(l, r)) err('E201', `cannot compare ${typeStr(l)} with ${typeStr(r)}`, e.pos, 'both sides of == and != must have the same type');
        if (prune(l).k === 'Fn') err('E201', 'functions cannot be compared', e.pos, 'compare the results of calling them instead');
        if (isCap(l)) err('E309', 'capabilities cannot be compared', e.pos, 'capabilities are only passed along as arguments');
        return BOOL;
      case '++': {
        const pl = prune(l);
        if (pl.k !== 'Str' && pl.k !== 'List' && pl.k !== 'Var' && pl.k !== 'Err') {
          const fix = pl.k === 'Html' ? 'join Html pieces with html_join(parts: [a, b]); never turn them back into Str to join'
            : pl.k === 'Sql' ? 'write the whole query as one sql(template: "...", values: [...]); queries are never joined from pieces'
              : 'for Int use +; to put a number in text use to_str(value: n) ++ "..."';
          err('E201', `'++' joins Str or List but the left side is ${typeStr(l)}`, e.pos, fix);
          return ERR;
        }
        if (!unify(l, r)) {
          err('E201', `'++' needs the same type on both sides but got ${typeStr(l)} and ${typeStr(r)}`, e.pos, prune(l).k === 'Str' ? 'convert the other side with to_str(value: ...)' : 'both lists must have the same item type');
          return ERR;
        }
        return l;
      }
      default: throw new Error(`internal: unknown op ${e.op}`);
    }
  }

  function call(e, env, ctx) {
    let sig;
    if (variants.has(e.name)) {
      const { type, variant } = variants.get(e.name);
      const { self, subst } = instantiate(type);
      if (!variant.fields.length) {
        err('E202', `case '${e.name}' has no fields`, e.pos, `write ${e.name} without ( )`);
        return self;
      }
      sig = { params: variant.fields.map((f) => [f.name, fromAst(f.type, subst)]), ret: self, ctor: true };
    } else if (fns.has(e.name)) sig = sigOf(fns.get(e.name));
    else if (e.name in BUILTINS) sig = BUILTINS[e.name]();
    else {
      const s = suggest(e.name, [...fns.keys(), ...Object.keys(BUILTINS)]);
      err('E200', `unknown function '${e.name}'`, e.pos, s ? `did you mean '${s}'?` : `define it with fn ${e.name}(...) -> Type ... do ... end`);
      e.args.forEach((a) => expr(a.value, env, ctx));
      return ERR;
    }
    const template = callTemplate(e.name, sig.params);
    if (e.name in HOLE) {
      const t = e.args.find((a) => a.name === 'template');
      if (t && t.value.k !== 'str') {
        err('E310', `the template of ${e.name} must be written as a literal string`, t.pos,
          `write the fixed part in quotes and put outside values in values: e.g. ${e.name}(template: "${e.name === 'html' ? '<p>{}</p>' : 'SELECT * FROM users WHERE name = ?'}", values: [name]). Never build the template from other strings`);
      }
      const v = e.args.find((a) => a.name === 'values');
      if (t && t.value.k === 'str' && v && v.value.k === 'list') {
        const holes = countHoles(t.value.v, HOLE[e.name]);
        if (holes !== v.value.items.length) {
          err('E311', `the template has ${holes} hole(s) '${HOLE[e.name]}' but ${v.value.items.length} value(s) are given`, v.pos, `give exactly one value per '${HOLE[e.name]}' in the same order`);
        }
      }
    }
    const names = sig.params.map(([n]) => n);

    let argsOk = true;
    if (e.args.some((a) => a.name === null)) {
      err('E206', `arguments to '${e.name}' must be named`, e.pos, `write ${template}`);
      argsOk = false;
    } else {
      const given = e.args.map((a) => a.name);
      const dup = given.find((n, i) => given.indexOf(n) !== i);
      const missing = names.filter((n) => !given.includes(n));
      const extra = given.filter((n) => !names.includes(n));
      if (dup) { err('E202', `argument '${dup}' is given twice`, e.pos, `write ${template}`); argsOk = false; }
      for (const n of extra) {
        const s = suggest(n, missing.length ? missing : names);
        err('E202', `'${e.name}' has no parameter '${n}'`, e.pos, s ? `did you mean '${s}'? write ${template}` : `write ${template}`);
        argsOk = false;
      }
      for (const n of missing) { err('E202', `missing argument '${n}' for '${e.name}'`, e.pos, `write ${template}`); argsOk = false; }
      if (argsOk && given.some((n, i) => n !== names[i])) {
        err('E207', `arguments to '${e.name}' are out of order`, e.pos, `write them in the declared order: ${template}`);
      }
    }
    for (const a of e.args) {
      const p = a.name !== null && sig.params.find(([n]) => n === a.name);
      if (p && isCap(p[1]) && a.value.k === 'var' && !env.has(a.value.name)) {
        const capType = prune(p[1]).k;
        const own = [...env.entries()].find(([, t]) => prune(t).k === capType);
        const where = ctx.where === 'body' ? `fn ${ctx.fn}` : `this ${ctx.where}`;
        err('E300', `'${e.name}' needs a ${capType} but ${where} was not given one${own ? ` (it has '${own[0]}')` : ''}`, a.pos,
          ctx.where !== 'body' ? `${ctx.where} must be pure and cannot use capabilities; remove the call to ${e.name}`
            : own ? `pass the one you have: ${a.name}: ${own[0]}`
              : `add a parameter ${capType.toLowerCase()}: ${capType} to fn ${ctx.fn} and pass it from the caller (main receives it)`);
        continue;
      }
      const t = expr(a.value, env, ctx);
      if (sig.ctor && isCap(t)) { err('E309', `capabilities cannot be stored in ${e.name}`, a.pos, 'pass the capability itself as an argument instead'); continue; }
      if (!argsOk || a.name === null) continue;
      const want = p[1];
      if (!unify(want, t)) {
        const fix = prune(want).k === 'Fn' ? `pass the name of a pure function of type ${typeStr(want)}`
          : typeStr(want) === 'List[Html]' ? 'turn each Str into Html with html_text(value: s) (it escapes < > & " \'), e.g. values: [html_text(value: name)]'
            : `pass a ${typeStr(want)}`;
        err('E201', `argument '${a.name}' of '${e.name}' must be ${typeStr(want)} but got ${typeStr(t)}`, a.pos, fix);
      }
    }
    return sig.ret;
  }

  for (const f of fns.values()) {
    const caps = f.params.filter((p) => isCap(fromAst(p.type)));
    const pure = caps.length === 0 && f.name !== 'main'; // main は入口なので約束と見本は要らない
    for (const p of f.params) {
      const t = fromAst(p.type);
      if (!isCap(t) && hasCap(t)) err('E309', `parameter '${p.name}' puts a capability inside ${typeStr(t)}`, p.pos, `take the capability directly: ${p.name}: ${typeStr(t).replace(/^List\[(.*)\]$/, '$1')}`);
    }
    if (hasCap(fromAst(f.ret))) err('E309', `fn ${f.name} returns a capability`, f.pos, 'capabilities cannot be returned; only main receives them and passes them down as arguments');
    const sample = callTemplate(f.name, f.params.map((p) => [p.name]));
    if (f.name === 'main') {
      const kinds = f.params.map((p) => fromAst(p.type).k);
      if (f.ret.k !== 'Unit' || f.params.some((p) => !isCap(fromAst(p.type))) || new Set(kinds).size !== kinds.length) {
        err('E303', 'main may only take capabilities (each type once) and must return Unit', f.pos, 'write fn main(console: Console) -> Unit do ... end; add folder: Folder only if the program reads files, out: OutFolder only if it writes files');
      }
    }

    const env = new Map();
    for (const p of f.params) {
      if (taken(env, p.name)) {
        err('E203', `parameter name '${p.name}' is already used`, p.pos, 'give the parameter a different name');
      }
      env.set(p.name, fromAst(p.type));
    }
    const pureCtx = (where) => ({ where, fn: f.name });
    // 約束（requires / ensures）の中では権利を使えない
    const envPure = new Map([...env].filter(([, t]) => !isCap(t)));
    for (const r of f.requires) {
      const t = expr(r.expr, envPure, pureCtx('requires'));
      if (!unify(BOOL, t)) err('E201', `requires must be Bool but is ${typeStr(t)}`, r.expr.pos, 'write a condition, e.g. requires n >= 0');
    }
    const ret = fromAst(f.ret);
    const before = diags.length;
    const got = checkBlock(f.body, env, { where: 'body', fn: f.name });
    if (!unify(ret, got)) {
      err('E201', `fn ${f.name} must return ${typeStr(ret)} but its body gives ${typeStr(got)}`, f.body.result.pos ?? f.pos, `make the last expression of the body a ${typeStr(ret)}, or change -> ${typeStr(ret)}`);
    }
    // 本体が権利を求めて E300 になった関数は、純粋のつもりではないので約束・見本の催促（E401・E402）は出さない
    const needsCap = diags.slice(before).some((d) => d.code === 'E300');
    if (!needsCap) {
      if (pure && f.ensures.length === 0) {
        err('E401', `pure function '${f.name}' has no ensures`, f.pos, `add a promise about the result before do, e.g. ensures result >= 0 (write ensures true only if nothing can be promised)`);
      }
      if (pure && f.examples.length === 0) {
        err('E402', `pure function '${f.name}' has no example`, f.pos, `add at least one example before do, e.g. example ${sample.replace(/\.\.\./g, '<value>')} == <expected>`);
      }
    }
    const envR = new Map(envPure);
    if (!envR.has('result')) envR.set('result', ret);
    for (const en of f.ensures) {
      const t = expr(en.expr, envR, pureCtx('ensures'));
      if (!unify(BOOL, t)) err('E201', `ensures must be Bool but is ${typeStr(t)}`, en.expr.pos, 'write a condition about result, e.g. ensures result >= 0');
    }
    for (const ex of f.examples) {
      const t = expr(ex.expr, new Map(), pureCtx('example'));
      if (!unify(BOOL, t)) err('E201', `example must be Bool but is ${typeStr(t)}`, ex.expr.pos, `write a call and its expected value: example ${sample.replace(/\.\.\./g, '<value>')} == <expected>`);
    }
  }
  diags.sort((a, b) => a.line - b.line || a.col - b.col);
  return diags;
}
