// 実行。requires / ensures は毎回の呼び出しで確かめる。example は check のときに全部回す。
import { AkashiError, diag } from './errors.js';

const MAX_DEPTH = 500; // JS の呼び出しの深さに収まる数（約800で JS が先にあふれる）。長いくり返しは range と fold で書く

export function show(v, nested = false) {
  if (v === null) return '()';
  if (Array.isArray(v)) return `[${v.map((x) => show(x, true)).join(', ')}]`;
  if (typeof v === 'string') return nested ? JSON.stringify(v) : v;
  if (typeof v === 'object' && v.fnref) return `<fn ${v.fnref}>`;
  return String(v);
}

function equal(a, b) {
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((x, i) => equal(x, b[i]));
  return a === b;
}

export class Machine {
  constructor(program, out = (s) => process.stdout.write(s)) {
    this.fns = new Map(program.fns.map((f) => [f.name, f]));
    this.out = out;
    this.depth = 0;
  }

  fail(code, msg, pos, fix, extra) { throw new AkashiError(diag(code, msg, pos, fix, extra)); }

  int(v, pos) {
    if (!Number.isSafeInteger(v)) this.fail('R504', 'integer overflow', pos, 'Int is limited to ±9007199254740991; keep numbers smaller');
    return v;
  }

  callFn(name, args, pos) {
    const f = this.fns.get(name);
    if (!f) return this.builtin(name, args, pos);
    if (++this.depth > MAX_DEPTH) this.fail('R505', `recursion deeper than ${MAX_DEPTH} calls in '${name}'`, pos, 'check that the recursion reaches its base case; use fold or range for long loops');
    try {
      const env = new Map(f.params.map((p) => [p.name, args[p.name]]));
      const argText = f.params.map((p) => `${p.name}=${show(args[p.name], true)}`).join(', ');
      for (const r of f.requires) {
        if (this.eval(r.expr, env) !== true) {
          this.fail('R500', `requires of '${name}' failed: ${r.src} (with ${argText || 'no arguments'})`, pos, `the caller must pass values that satisfy '${r.src}'; check the caller, not ${name}`);
        }
      }
      const result = this.block(f.body, env);
      const envR = new Map(env);
      if (!envR.has('result')) envR.set('result', result);
      for (const en of f.ensures) {
        if (this.eval(en.expr, envR) !== true) {
          this.fail('R501', `ensures of '${name}' failed: ${en.src} (result=${show(result, true)}${argText ? `, ${argText}` : ''})`, f.pos, `the body of ${name} breaks its promise; fix the body (or the ensures if the promise is wrong)`);
        }
      }
      return result;
    } finally {
      this.depth--;
    }
  }

  builtin(name, a, pos) {
    switch (name) {
      case 'print': this.out(`${show(a.value)}\n`); return null;
      case 'len': return a.list.length;
      case 'str_len': return [...a.text].length;
      case 'to_str': return show(a.value);
      case 'range': {
        if (a.to - a.from > 1_000_000) this.fail('R504', 'range is too large', pos, 'keep ranges under 1,000,000 items');
        const r = [];
        for (let i = a.from; i < a.to; i++) r.push(i);
        return r;
      }
      case 'get':
        if (a.index < 0 || a.index >= a.list.length) this.fail('R506', `index ${a.index} is out of range for a list of length ${a.list.length}`, pos, 'check 0 <= index and index < len(list: ...) before calling get');
        return a.list[a.index];
      case 'append': return [...a.list, a.item];
      case 'map': return a.list.map((x) => this.apply(a.func, [x], pos));
      case 'filter': return a.list.filter((x) => this.apply(a.func, [x], pos) === true);
      case 'fold': return a.list.reduce((acc, x) => this.apply(a.func, [acc, x], pos), a.init);
      default: throw new Error(`internal: unknown function ${name}`);
    }
  }

  apply(ref, values, pos) {
    const f = this.fns.get(ref.fnref);
    const args = Object.fromEntries(f.params.map((p, i) => [p.name, values[i]]));
    return this.callFn(f.name, args, pos);
  }

  block(b, env) {
    const scope = new Map(env);
    for (const l of b.lets) {
      if (l.k === 'do') this.eval(l.expr, scope);
      else scope.set(l.name, this.eval(l.value, scope));
    }
    return this.eval(b.result, scope);
  }

  eval(e, env) {
    switch (e.k) {
      case 'int': return this.int(e.v, e.pos);
      case 'str': case 'bool': return e.v;
      case 'unit': return null;
      case 'var': return env.has(e.name) ? env.get(e.name) : { fnref: e.name };
      case 'list': return e.items.map((x) => this.eval(x, env));
      case 'un': {
        const v = this.eval(e.arg, env);
        return e.op === 'not' ? !v : this.int(-v, e.pos);
      }
      case 'if': return this.eval(e.cond, env) ? this.block(e.thenB, env) : this.block(e.elseB, env);
      case 'call': {
        const args = {};
        for (const a of e.args) args[a.name] = this.eval(a.value, env);
        return this.callFn(e.name, args, e.pos);
      }
      case 'bin': {
        if (e.op === 'and') return this.eval(e.left, env) && this.eval(e.right, env);
        if (e.op === 'or') return this.eval(e.left, env) || this.eval(e.right, env);
        const l = this.eval(e.left, env);
        const r = this.eval(e.right, env);
        switch (e.op) {
          case '+': return this.int(l + r, e.pos);
          case '-': return this.int(l - r, e.pos);
          case '*': return this.int(l * r, e.pos);
          case '/': case '%':
            if (r === 0) this.fail('R503', 'division by zero', e.pos, 'check the divisor first: if d == 0 then ... else ... end, or add requires d != 0');
            return e.op === '/' ? Math.trunc(l / r) : l % r;
          case '<': return l < r;
          case '<=': return l <= r;
          case '>': return l > r;
          case '>=': return l >= r;
          case '==': return equal(l, r);
          case '!=': return !equal(l, r);
          case '++': return Array.isArray(l) ? [...l, ...r] : l + r;
          default: throw new Error(`internal: unknown op ${e.op}`);
        }
      }
      default: throw new Error(`internal: unknown node ${e.k}`);
    }
  }

  // example を1つ回す。== の形なら、左の実際の値も見せる
  example(fnName, ex) {
    const e = ex.expr;
    if (e.k === 'bin' && e.op === '==') {
      const got = this.eval(e.left, new Map());
      const want = this.eval(e.right, new Map());
      if (!equal(got, want)) {
        this.fail('R502', `example of '${fnName}' failed: ${ex.src} (left side gave ${show(got, true)}, expected ${show(want, true)})`, e.pos, `either the body of ${fnName} or this example is wrong; fix the one that disagrees with the intent`, { actual: show(got, true), expected: show(want, true) });
      }
      return;
    }
    if (this.eval(e, new Map()) !== true) {
      this.fail('R502', `example of '${fnName}' failed: ${ex.src}`, e.pos, `either the body of ${fnName} or this example is wrong`);
    }
  }
}
