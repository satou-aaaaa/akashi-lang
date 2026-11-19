// 型・名前・引数・副作用・約束の検査。エラーはまとめて返す（1回の実行で直せるものを全部見せる）。
import { diag, suggest } from './errors.js';

export const INT = { k: 'Int' };
export const BOOL = { k: 'Bool' };
export const STR = { k: 'Str' };
export const UNIT = { k: 'Unit' };
const ERR = { k: 'Err' }; // 先のエラーの続きで出る2つめのエラーを止める
const List = (of) => ({ k: 'List', of });
const Fn = (params, ret) => ({ k: 'Fn', params, ret });
let varId = 0;
const fresh = () => ({ k: 'Var', id: ++varId, ref: null });

function prune(t) {
  while (t.k === 'Var' && t.ref) t = t.ref;
  return t;
}

function occurs(v, t) {
  t = prune(t);
  if (t === v) return true;
  if (t.k === 'List') return occurs(v, t.of);
  if (t.k === 'Fn') return t.params.some((p) => occurs(v, p)) || occurs(v, t.ret);
  return false;
}

function unify(a, b) {
  a = prune(a);
  b = prune(b);
  if (a.k === 'Err' || b.k === 'Err') return true;
  if (a.k === 'Var') { if (a !== b) { if (occurs(a, b)) return false; a.ref = b; } return true; }
  if (b.k === 'Var') return unify(b, a);
  if (a.k !== b.k) return false;
  if (a.k === 'List') return unify(a.of, b.of);
  if (a.k === 'Fn') {
    if (a.params.length !== b.params.length) return false;
    return a.params.every((p, i) => unify(p, b.params[i])) && unify(a.ret, b.ret);
  }
  return true;
}

export function typeStr(t) {
  t = prune(t);
  if (t.k === 'List') return `List[${typeStr(t.of)}]`;
  if (t.k === 'Fn') return `fn(${t.params.map(typeStr).join(', ')}) -> ${typeStr(t.ret)}`;
  if (t.k === 'Var') return 'T';
  if (t.k === 'Err') return '?';
  return t.k;
}

// 組み込み関数。呼ぶたびに型変数を新しくする。引数はすべて名前つき。
export const BUILTINS = {
  print: () => ({ params: [['value', fresh()]], ret: UNIT, effects: ['io'] }),
  len: () => ({ params: [['list', List(fresh())]], ret: INT, effects: [] }),
  str_len: () => ({ params: [['text', STR]], ret: INT, effects: [] }),
  to_str: () => ({ params: [['value', fresh()]], ret: STR, effects: [] }),
  range: () => ({ params: [['from', INT], ['to', INT]], ret: List(INT), effects: [] }),
  get: () => { const a = fresh(); return { params: [['list', List(a)], ['index', INT]], ret: a, effects: [] }; },
  append: () => { const a = fresh(); return { params: [['list', List(a)], ['item', a]], ret: List(a), effects: [] }; },
  map: () => { const a = fresh(); const b = fresh(); return { params: [['list', List(a)], ['func', Fn([a], b)]], ret: List(b), effects: [] }; },
  filter: () => { const a = fresh(); return { params: [['list', List(a)], ['func', Fn([a], BOOL)]], ret: List(a), effects: [] }; },
  fold: () => { const a = fresh(); const b = fresh(); return { params: [['list', List(a)], ['init', b], ['func', Fn([b, a], b)]], ret: b, effects: [] }; },
};

function fromAst(t) {
  return t.k === 'List' ? List(fromAst(t.of)) : { k: t.k };
}

function callTemplate(name, params) {
  return `${name}(${params.map(([n]) => `${n}: ...`).join(', ')})`;
}

export function check(program) {
  const diags = [];
  const err = (code, msg, pos, fix) => diags.push(diag(code, msg, pos, fix));
  const fns = new Map();

  for (const f of program.fns) {
    if (fns.has(f.name) || f.name in BUILTINS) {
      err('E203', `function '${f.name}' is already defined${f.name in BUILTINS ? ' (built-in)' : ''}`, f.pos, 'give the function a different name; names are never reused');
      continue;
    }
    fns.set(f.name, f);
  }

  const sigOf = (f) => ({
    params: f.params.map((p) => [p.name, fromAst(p.type)]),
    ret: fromAst(f.ret),
    effects: f.effects.map((e) => e.name),
  });

  const allNames = (env) => [...env.keys(), ...fns.keys(), ...Object.keys(BUILTINS)];

  function checkBlock(block, env, ctx) {
    const scope = new Map(env);
    for (const l of block.lets) {
      if (l.k === 'do') {
        const t = expr(l.expr, scope, ctx);
        if (!unify(UNIT, t)) err('E201', `this line gives ${typeStr(t)} but its value is thrown away`, l.pos, 'only Unit expressions (like print) can stand alone; keep the value with let name: Type = ..., or make it the last line');
        continue;
      }
      if (scope.has(l.name) || fns.has(l.name) || l.name in BUILTINS) {
        err('E203', `the name '${l.name}' is already used`, l.pos, `names cannot be reused or shadowed; pick a new name such as ${l.name}2 or a more specific one`);
      }
      const want = fromAst(l.type);
      const got = expr(l.value, scope, ctx);
      if (!unify(want, got)) {
        err('E201', `let ${l.name} is declared ${typeStr(want)} but the value is ${typeStr(got)}`, l.pos, `change the declared type to ${typeStr(got)} or change the value`);
      }
      scope.set(l.name, want);
    }
    return expr(block.result, scope, ctx);
  }

  function expr(e, env, ctx) {
    switch (e.k) {
      case 'int': return INT;
      case 'str': return STR;
      case 'bool': return BOOL;
      case 'unit': return UNIT;
      case 'var': {
        if (env.has(e.name)) return env.get(e.name);
        if (fns.has(e.name)) {
          const s = sigOf(fns.get(e.name));
          if (s.effects.length) {
            err('E304', `'${e.name}' has effects and cannot be passed as a value`, e.pos, 'only pure functions (no effects) can be passed to map / filter / fold');
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
      default: throw new Error(`internal: unknown node ${e.k}`);
    }
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
        return BOOL;
      case '++': {
        const pl = prune(l);
        if (pl.k !== 'Str' && pl.k !== 'List' && pl.k !== 'Var' && pl.k !== 'Err') {
          err('E201', `'++' joins Str or List but the left side is ${typeStr(l)}`, e.pos, 'for Int use +; to put a number in text use to_str(value: n) ++ "..."');
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
    if (fns.has(e.name)) sig = sigOf(fns.get(e.name));
    else if (e.name in BUILTINS) sig = BUILTINS[e.name]();
    else {
      const s = suggest(e.name, [...fns.keys(), ...Object.keys(BUILTINS)]);
      err('E200', `unknown function '${e.name}'`, e.pos, s ? `did you mean '${s}'?` : `define it with fn ${e.name}(...) -> Type ... do ... end`);
      e.args.forEach((a) => expr(a.value, env, ctx));
      return ERR;
    }
    const template = callTemplate(e.name, sig.params);
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
      const t = expr(a.value, env, ctx);
      if (!argsOk || a.name === null) continue;
      const want = sig.params.find(([n]) => n === a.name)[1];
      if (!unify(want, t)) {
        err('E201', `argument '${a.name}' of '${e.name}' must be ${typeStr(want)} but got ${typeStr(t)}`, a.pos, prune(want).k === 'Fn' ? `pass the name of a pure function of type ${typeStr(want)}` : `pass a ${typeStr(want)}`);
      }
    }
    for (const eff of sig.effects) {
      if (!ctx.effects.includes(eff)) {
        const fix = ctx.where === 'body'
          ? `add 'effects ${eff}' to fn ${ctx.fn} (before do), or move this call into a function that has effects ${eff}`
          : `${ctx.where} must be pure; remove the call to ${e.name}`;
        err('E300', `'${e.name}' has effect ${eff} but ${ctx.where === 'body' ? `fn ${ctx.fn}` : `this ${ctx.where}`} does not allow it`, e.pos, fix);
      }
    }
    return sig.ret;
  }

  for (const f of fns.values()) {
    for (const ef of f.effects) {
      if (ef.name !== 'io') err('E302', `unknown effect '${ef.name}'`, ef.pos, 'the only effect is io (printing). Remove other effects');
    }
    const pure = f.effects.length === 0 && f.name !== 'main'; // main は入口なので約束と見本は要らない
    const sample = callTemplate(f.name, f.params.map((p) => [p.name]));
    if (pure && f.ensures.length === 0) {
      err('E401', `pure function '${f.name}' has no ensures`, f.pos, `add a promise about the result before do, e.g. ensures result >= 0 (write ensures true only if nothing can be promised)`);
    }
    if (pure && f.examples.length === 0) {
      err('E402', `pure function '${f.name}' has no example`, f.pos, `add at least one example before do, e.g. example ${sample.replace(/\.\.\./g, '<value>')} == <expected>`);
    }
    if (f.name === 'main' && (f.params.length > 0 || f.ret.k !== 'Unit')) {
      err('E303', 'main must take no parameters and return Unit', f.pos, 'write fn main() -> Unit effects io do ... end');
    }

    const env = new Map();
    for (const p of f.params) {
      if (env.has(p.name) || fns.has(p.name) || p.name in BUILTINS) {
        err('E203', `parameter name '${p.name}' is already used`, p.pos, 'give the parameter a different name');
      }
      env.set(p.name, fromAst(p.type));
    }
    const pureCtx = (where) => ({ effects: [], where, fn: f.name });
    for (const r of f.requires) {
      const t = expr(r.expr, env, pureCtx('requires'));
      if (!unify(BOOL, t)) err('E201', `requires must be Bool but is ${typeStr(t)}`, r.expr.pos, 'write a condition, e.g. requires n >= 0');
    }
    const ret = fromAst(f.ret);
    const got = checkBlock(f.body, env, { effects: f.effects.map((x) => x.name), where: 'body', fn: f.name });
    if (!unify(ret, got)) {
      err('E201', `fn ${f.name} must return ${typeStr(ret)} but its body gives ${typeStr(got)}`, f.body.result.pos ?? f.pos, `make the last expression of the body a ${typeStr(ret)}, or change -> ${typeStr(ret)}`);
    }
    const envR = new Map(env);
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
