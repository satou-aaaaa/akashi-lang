// 自動の試し：純粋な関数に、型に合う入力をたくさん作って渡し、requires を満たすのに
// ensures が破れる（R511）・落ちる（R512）ものを探す。example だけでは見落とす場合を拾う。
// 種は固定（毎回同じ入力。結果がぶれない）。いちばん小さい反例を探して見せる。
import { AkashiError, diag } from './errors.js';
import { Machine, OutOfBudget, show, cmpKey } from './run.js';
import { BUILTIN_TYPES } from './check.js';

const TRIES = 200;
const STEP_BUDGET = 20000;

function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const EDGE_INTS = [0, 1, -1, 2, -2, 10, -10, 100, -100];
const EDGE_STRS = ['', 'a', ' ', 'ab', '<&>', '"\'', 'あ', '\n'];

// 自分で作る型：case を1つ選んで欄を作る。深くなったら欄の無い case（無ければ打ち切り）
class TooDeep extends Error {}
const subst = (t, s) => (t.k === 'Param' ? s[t.name] : t.k === 'List' || t.k === 'Dict' ? { k: t.k, of: subst(t.of, s) } : t.k === 'Data' ? { ...t, args: t.args.map((x) => subst(x, s)) } : t);

function gen(type, r, size, types, depth = 0) {
  switch (type.k) {
    case 'Data': {
      const ty = types.get(type.name);
      const s = Object.fromEntries(ty.params.map((p, i) => [p, type.args[i]]));
      let vs = ty.variants;
      if (depth > 3) { vs = vs.filter((v) => v.fields.every((f) => f.type.k !== 'Data' && f.type.k !== 'List' && f.type.k !== 'Dict')); if (!vs.length) throw new TooDeep(); }
      const v = vs[Math.floor(r() * vs.length)];
      return { tag: v.name, fields: Object.fromEntries(v.fields.map((f) => [f.name, gen(subst(f.type, s), r, size, types, depth + 1)])) };
    }
    case 'Int': return r() < 0.3 ? EDGE_INTS[Math.floor(r() * EDGE_INTS.length)] : Math.floor(r() * (2 * size + 1)) - size;
    case 'Bool': return r() < 0.5;
    case 'Str': {
      if (r() < 0.4) return EDGE_STRS[Math.floor(r() * EDGE_STRS.length)];
      const n = Math.floor(r() * 6);
      let s = '';
      for (let i = 0; i < n; i++) s += 'abcxyz09 <'[Math.floor(r() * 10)];
      return s;
    }
    case 'List': {
      const n = Math.floor(r() * 6);
      return Array.from({ length: n }, () => gen(type.of, r, size, types, depth + 1));
    }
    case 'Dict': {
      const n = Math.floor(r() * 4);
      const m = new Map();
      for (let i = 0; i < n; i++) m.set(gen({ k: 'Str' }, r, size, types, depth + 1), gen(type.of, r, size, types, depth + 1));
      return { dict: [...m].sort((x, y) => cmpKey(x[0], y[0])) };
    }
    default: return undefined;
  }
}

// 作れる型か（自分で作る型は欄が全部作れるとき。同じ型をたどり直したら作れるとみなす）
function generatable(t, types, seen = new Set()) {
  if (['Int', 'Bool', 'Str'].includes(t.k)) return true;
  if (t.k === 'List' || t.k === 'Dict') return generatable(t.of, types, seen);
  if (t.k === 'Data') {
    const key = JSON.stringify(t);
    if (seen.has(key)) return true;
    const ty = types.get(t.name);
    if (!ty) return false;
    const s = Object.fromEntries(ty.params.map((p, i) => [p, t.args[i]]));
    const next = new Set([...seen, key]);
    return ty.variants.every((v) => v.fields.every((f) => generatable(subst(f.type, s), types, next)));
  }
  return false;
}

// 反例を小さくする（Int は 0 に近づけ、Str・List は短くする）
function* smaller(v) {
  if (typeof v === 'number' && v !== 0) { yield 0; yield Math.trunc(v / 2); yield v > 0 ? v - 1 : v + 1; }
  if (typeof v === 'string' && v.length) { yield ''; yield v.slice(1); yield v.slice(0, -1); }
  if (Array.isArray(v) && v.length) { yield []; yield v.slice(1); yield v.slice(0, -1); }
  if (v && v.dict && v.dict.length) { yield { dict: [] }; yield { dict: v.dict.slice(1) }; yield { dict: v.dict.slice(0, -1) }; }
  if (v && v.tag !== undefined) {
    for (const [k, x] of Object.entries(v.fields)) for (const y of smaller(x)) yield { tag: v.tag, fields: { ...v.fields, [k]: y } };
  }
}

export function fuzz(program) {
  const diagnostics = [];
  let checked = 0;
  const types = new Map([...BUILTIN_TYPES, ...(program.types ?? []).map((t) => ({ ...t, params: [] }))].map((t) => [t.name, t]));
  for (const f of program.fns) {
    if (f.name === 'main' || f.ensures.length === 0 && f.requires.length === 0) continue;
    if (!f.params.length || !f.params.every((p) => generatable(p.type, types))) continue;
    const r = rng(0xa5a5 ^ f.name.length * 7919);
    // 1回試す。結果：'skip'（requires を満たさない・長すぎる）／'ok'／診断
    const trial = (args) => {
      const m = new Machine(program, () => {});
      m.budget = STEP_BUDGET;
      const env = new Map(Object.entries(args));
      try {
        for (const q of f.requires) if (m.eval(q.expr, env) !== true) return 'skip';
      } catch {
        return 'skip';
      }
      try {
        m.callFn(f.name, args, f.pos);
        return 'ok';
      } catch (e) {
        if (e instanceof OutOfBudget) return 'skip';
        const text = f.params.map((p) => `${p.name}: ${show(args[p.name], true)}`).join(', ');
        const call = `${f.name}(${text})`;
        const okInput = f.requires.length ? 'satisfies requires but' : 'is a valid input (no requires) but';
        if (e instanceof AkashiError && e.diag.code === 'R501' && e.diag.message.startsWith(`ensures of '${f.name}'`)) {
          return diag('R511', `${call} ${okInput} breaks ensures: ${e.diag.message.replace(/^ensures of '[^']*' failed: /, '')}`, f.pos,
            `fix the body of ${f.name} for this input, or add requires that excludes it, or correct the ensures. Add it as an example: example ${call} == ...`, { input: call });
        }
        const inner = e instanceof AkashiError ? `${e.diag.code} ${e.diag.message}` : e instanceof RangeError ? 'R505 recursion too deep' : String(e);
        return diag('R512', `${call} ${okInput} fails: ${inner}`, f.pos,
          `handle this input in ${f.name} (e.g. an if for it), or add a requires that excludes it`, { input: call });
      }
    };
    let found = null;
    let foundArgs = null;
    for (let i = 0; i < TRIES && !found; i++) {
      const size = 5 + i;
      let args;
      try {
        args = Object.fromEntries(f.params.map((p) => [p.name, gen(p.type, r, size, types)]));
      } catch (e) {
        if (e instanceof TooDeep) continue;
        throw e;
      }
      const res = trial(args);
      if (res === 'ok') checked++;
      else if (res !== 'skip') { found = res; foundArgs = args; }
    }
    if (found) {
      // 小さくできるだけ小さくする
      let improved = true;
      while (improved) {
        improved = false;
        for (const p of f.params) {
          for (const v of smaller(foundArgs[p.name])) {
            const args = { ...foundArgs, [p.name]: v };
            const res = trial(args);
            if (res !== 'ok' && res !== 'skip' && res.code === found.code) { found = res; foundArgs = args; improved = true; break; }
          }
          if (improved) break;
        }
      }
      diagnostics.push(found);
    }
  }
  return { diagnostics, checked };
}
