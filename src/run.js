// 実行。requires / ensures は毎回の呼び出しで確かめる。example は check のときに全部回す。
// Node の部品は使わない（ブラウザの遊べるページでも同じものを動かす）。ファイルを読むのは Folder の鍵が持つ read（src/folder.js）
import { AkashiError, diag } from './errors.js';
import { BUILTIN_TYPES } from './check.js';

const MAX_DEPTH = 500; // JS の呼び出しの深さに収まる数（約800で JS が先にあふれる）。長いくり返しは range と fold で書く

const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
const escapeHtml = (x) => x.replace(/[&<>"']/g, (c) => ESC[c]);

const NONE = { tag: 'None', fields: {} };
const some = (value) => ({ tag: 'Some', fields: { value } });
const err = (message) => ({ tag: 'Err', fields: { message } });

export function show(v, nested = false) {
  if (v === null) return '()';
  if (v && v.cap) return `<${v.cap}>`;
  if (v && v.tag !== undefined) {
    const fs = Object.entries(v.fields);
    return fs.length ? `${v.tag}(${fs.map(([k, x]) => `${k}: ${show(x, true)}`).join(', ')})` : v.tag;
  }
  if (v && v.html !== undefined) return v.html;
  if (v && v.sql !== undefined) return `${v.sql} -- params: ${JSON.stringify(v.params)}`;
  if (Array.isArray(v)) return `[${v.map((x) => show(x, true)).join(', ')}]`;
  if (typeof v === 'string') return nested ? JSON.stringify(v) : v;
  if (typeof v === 'object' && v.fnref) return `<fn ${v.fnref}>`;
  return String(v);
}

function equal(a, b) {
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((x, i) => equal(x, b[i]));
  if (a && b && a.tag !== undefined && b.tag !== undefined) return a.tag === b.tag && Object.keys(a.fields).every((k) => equal(a.fields[k], b.fields[k]));
  return a === b;
}

// 自動で作った入力で試すとき、長くかかる回は打ち切って数えない
export class OutOfBudget extends Error {}

export class Machine {
  constructor(program, out = (s) => process.stdout.write(s)) {
    this.fns = new Map(program.fns.map((f) => [f.name, f]));
    this.variants = new Map([...BUILTIN_TYPES, ...(program.types ?? [])].flatMap((t) => t.variants.map((v) => [v.name, v])));
    this.out = out;
    this.depth = 0;
  }

  fail(code, msg, pos, fix, extra) { throw new AkashiError(diag(code, msg, pos, fix, extra)); }

  int(v, pos) {
    if (!Number.isSafeInteger(v)) this.fail('R504', 'integer overflow', pos, 'Int is limited to ±9007199254740991; keep numbers smaller');
    return v;
  }

  callFn(name, args, pos) {
    const v = this.variants.get(name);
    if (v) return { tag: name, fields: Object.fromEntries(v.fields.map((x) => [x.name, args[x.name]])) };
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
      case 'html': {
        const parts = a.template.split('{}');
        this.holes(parts.length - 1, a.values.length, pos, '{}');
        return { html: parts.map((p, i) => (i === 0 ? '' : a.values[i - 1].html) + p).join('') };
      }
      case 'html_text': return { html: escapeHtml(a.value) };
      case 'html_join': return { html: a.parts.map((x) => x.html).join('') };
      case 'sql': {
        this.holes(a.template.split('?').length - 1, a.values.length, pos, '?');
        // 値は文に混ぜず、別に持つ（データベースに渡すときはプレースホルダとして渡す）
        return { sql: a.template, params: [...a.values] };
      }
      case 'read_text': return this.readText(a.from, a.path, pos);
      case 'parse_int': {
        const t = a.text.trim();
        if (!/^-?[0-9]+$/.test(t) || !Number.isSafeInteger(Number(t))) return NONE;
        return some(Number(t) === 0 ? 0 : Number(t));
      }
      case 'at': return a.index >= 0 && a.index < a.list.length ? some(a.list[a.index]) : NONE;
      case 'find': {
        for (const x of a.list) if (this.apply(a.func, [x], pos) === true) return some(x);
        return NONE;
      }
      case 'any': return a.list.some((x) => this.apply(a.func, [x], pos) === true);
      case 'all': return a.list.every((x) => this.apply(a.func, [x], pos) === true);
      case 'reverse': return [...a.list].reverse();
      case 'take': return a.list.slice(0, this.count(a.count, pos));
      case 'drop': return a.list.slice(this.count(a.count, pos));
      case 'sort': return [...a.list].sort((x, y) => x - y);
      case 'sum': return a.list.reduce((s, x) => this.int(s + x, pos), 0);
      case 'max': return a.list.length ? some(Math.max(...a.list)) : NONE;
      case 'min': return a.list.length ? some(Math.min(...a.list)) : NONE;
      case 'chars': return [...a.text];
      case 'split':
        if (a.by === '') this.fail('R506', 'split needs a non-empty separator', pos, 'to split into characters use chars(text: ...)');
        return a.text.split(a.by);
      case 'join': return a.parts.join(a.by);
      case 'contains': return a.text.includes(a.part);
      case 'starts_with': return a.text.startsWith(a.prefix);
      case 'ends_with': return a.text.endsWith(a.suffix);
      case 'trim': return a.text.trim();
      case 'lines': return a.text === '' ? [] : a.text.replace(/\r\n/g, '\n').replace(/\n$/, '').split('\n');
      case 'len': return a.list.length;
      case 'str_len': return [...a.text].length;
      case 'slice': {
        const cps = [...a.text];
        if (!(a.from >= 0 && a.from <= a.to && a.to <= cps.length)) this.fail('R506', `slice from ${a.from} to ${a.to} is out of range for a text of length ${cps.length}`, pos, 'check 0 <= from, from <= to and to <= str_len(text: ...) before calling slice');
        return cps.slice(a.from, a.to).join('');
      }
      case 'code_of': {
        const cps = [...a.char];
        if (cps.length !== 1) this.fail('R506', `code_of needs exactly one character but got ${cps.length}`, pos, 'pass one character, e.g. an item of chars(text: ...)');
        return cps[0].codePointAt(0);
      }
      case 'char_of':
        if (a.code < 0 || a.code > 0x10ffff || (a.code >= 0xd800 && a.code <= 0xdfff)) this.fail('R506', `${a.code} is not a character code`, pos, 'use 0 to 1114111, except 55296 to 57343');
        return String.fromCodePoint(a.code);
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

  // take・drop の数。負の数は書き方の誤りとして止める（黙って 0 にしない）
  count(n, pos) {
    if (n < 0) this.fail('R506', `count ${n} is negative`, pos, 'give a count of 0 or more');
    return n;
  }

  holes(holes, values, pos, mark) {
    if (holes !== values) this.fail('R510', `the template has ${holes} hole(s) '${mark}' but ${values} value(s) were given`, pos, `give exactly one value per '${mark}'`);
  }

  // 読めないとき（無い・フォルダ・文字が読めない）は Err を返す。フォルダの外を指すのは書き方の誤りなので止める（R507）
  // Folder の権利で読めるのは、渡されたフォルダの中だけ（.. や絶対パス、外を指すリンクは止める）
  readText(folder, path, pos) {
    const bad = path === '' || path.startsWith('/') || /^[A-Za-z]:/.test(path) || path.includes('\\') || path.includes('\0') || path.split('/').some((x) => x === '..');
    if (bad) this.fail('R507', `path '${path}' is not inside the folder`, pos, 'use a relative path without .. such as "data/input.txt"');
    const r = folder.read(path); // { text } か { missing } か { escape }
    if (r.escape) this.fail('R507', `path '${path}' points outside the folder (through a link)`, pos, 'read only files that are really inside the folder');
    return r.text !== undefined ? { tag: 'Ok', fields: { value: r.text } } : err(r.missing);
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
    if (this.budget !== undefined && --this.budget < 0) throw new OutOfBudget();
    switch (e.k) {
      case 'int': return this.int(e.v, e.pos);
      case 'str': case 'bool': return e.v;
      case 'unit': return null;
      case 'var':
        if (env.has(e.name)) return env.get(e.name);
        if (this.variants.has(e.name)) return { tag: e.name, fields: {} };
        return { fnref: e.name };
      case 'match': {
        const v = this.eval(e.subject, env);
        const arm = e.arms.find((x) => x.variant === v.tag);
        const scope = new Map(env);
        for (const b of arm.binds) if (b.name !== '_') scope.set(b.name, v.fields[b.field]);
        return this.eval(arm.value, scope);
      }
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
