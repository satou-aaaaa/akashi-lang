// 字句解析と構文解析。文法は docs/SPEC.md。
// 構文の失敗は最初の1つで止める（AI は1つずつ直すほうが確実なため）。
import { AkashiError, diag, suggest } from './errors.js';

const KEYWORDS = new Set([
  'fn', 'do', 'end', 'let', 'if', 'then', 'else', 'when', 'type', 'case', 'match',
  'requires', 'ensures', 'example', 'effects',
  'and', 'or', 'not', 'true', 'false',
]);
const TWO_CHAR_OPS = ['->', '==', '!=', '<=', '>=', '++'];
const ONE_CHAR_OPS = '+-*/%<>=()[],:';
export const CAPABILITY_TYPES = ['Console', 'Folder'];
// Html・Sql は「組み立て済みで安全」な値。決まった型紙（文字の書きこみ）に値を差し込む html()・sql() でしか作れない
export const SAFE_TYPES = ['Html', 'Sql'];
// Option・Result は組み込みの「自分で作る型」。null と、見落とされる例外の代わり（docs/PROBLEMS.md）
export const BUILTIN_DATA = ['Option', 'Result'];
export const TYPE_NAMES = ['Int', 'Bool', 'Str', 'Unit', 'List', ...BUILTIN_DATA, ...SAFE_TYPES, ...CAPABILITY_TYPES];
const isUpper = (w) => /^[A-Z]/.test(w);

export function lex(src) {
  const toks = [];
  let i = 0;
  let line = 1;
  let col = 1;
  const adv = (n = 1) => {
    for (let k = 0; k < n; k++) {
      if (src[i] === '\n') { line++; col = 1; } else col++;
      i++;
    }
  };
  const fail = (code, msg, pos, fix) => { throw new AkashiError(diag(code, msg, pos, fix)); };

  while (i < src.length) {
    const c = src[i];
    if (c === ' ' || c === '\t' || c === '\r' || c === '\n') { adv(); continue; }
    if (c === '#') { while (i < src.length && src[i] !== '\n') adv(); continue; }
    const pos = { line, col, offset: i };
    if (/[0-9]/.test(c)) {
      let j = i;
      while (j < src.length && /[0-9]/.test(src[j])) j++;
      if (src[j] === '.' && /[0-9]/.test(src[j + 1] ?? '')) {
        fail('E101', 'decimal numbers are not supported', pos, 'use Int only (for example 3 instead of 3.0); scale values yourself, e.g. cents instead of dollars');
      }
      if (/[A-Za-z_]/.test(src[j] ?? '')) fail('E100', `a number cannot be followed by letters: '${src.slice(i, j + 1)}'`, pos, 'put a space or operator between the number and the name');
      const text = src.slice(i, j);
      toks.push({ t: 'int', v: Number(text), pos, end: j });
      adv(j - i);
      continue;
    }
    if (/[A-Za-z_]/.test(c)) {
      let j = i;
      while (j < src.length && /[A-Za-z0-9_]/.test(src[j])) j++;
      const w = src.slice(i, j);
      toks.push({ t: KEYWORDS.has(w) ? 'kw' : 'id', v: w, pos, end: j });
      adv(j - i);
      continue;
    }
    if (c === '"') {
      let j = i + 1;
      let s = '';
      while (j < src.length && src[j] !== '"') {
        if (src[j] === '\n') fail('E100', 'string is not closed on this line', pos, 'close the string with " before the end of the line; write \\n for a newline');
        if (src[j] === '\\') {
          const e = src[j + 1];
          const map = { n: '\n', t: '\t', '"': '"', '\\': '\\' };
          if (!(e in map)) fail('E100', `unknown escape '\\${e ?? ''}'`, { line, col: col + (j - i), offset: j }, 'only \\n \\t \\" \\\\ are allowed');
          s += map[e];
          j += 2;
        } else {
          s += src[j];
          j++;
        }
      }
      if (j >= src.length) fail('E100', 'string is not closed', pos, 'add a closing "');
      toks.push({ t: 'str', v: s, pos, end: j + 1 });
      adv(j + 1 - i);
      continue;
    }
    const two = src.slice(i, i + 2);
    if (TWO_CHAR_OPS.includes(two)) {
      toks.push({ t: 'op', v: two, pos, end: i + 2 });
      adv(2);
      continue;
    }
    if (ONE_CHAR_OPS.includes(c)) {
      toks.push({ t: 'op', v: c, pos, end: i + 1 });
      adv();
      continue;
    }
    const hint = { '{': 'blocks use do ... end, not { }', '}': 'blocks use do ... end, not { }', ';': 'statements are separated by new lines; remove the ;', '&': 'use and', '|': 'use or', '!': 'use not (or != for "not equal")', '.': 'there are no methods; call functions with named arguments, e.g. len(list: xs)', "'": 'strings use double quotes "..."' };
    fail('E100', `unexpected character '${c}'`, pos, hint[c] ?? 'remove this character');
  }
  toks.push({ t: 'eof', pos: { line, col, offset: i }, end: i });
  return toks;
}

function show(tok) {
  if (tok.t === 'eof') return 'end of file';
  if (tok.t === 'str') return `"${tok.v}"`;
  return `'${tok.v}'`;
}

class Parser {
  constructor(src, toks) {
    this.src = src;
    this.toks = toks;
    this.i = 0;
    // 型の名前は先に集める（宣言より前の関数でも使えるように）
    this.userTypes = toks.flatMap((t, i) => (t.t === 'kw' && t.v === 'type' && toks[i + 1]?.t === 'id' ? [toks[i + 1].v] : []));
    this.typeNames = [...TYPE_NAMES, ...this.userTypes];
  }
  peek(k = 0) { return this.toks[Math.min(this.i + k, this.toks.length - 1)]; }
  is(t, v) { const x = this.peek(); return x.t === t && (v === undefined || x.v === v); }
  isOp(v) { return this.is('op', v); }
  isKw(v) { return this.is('kw', v); }
  next() { return this.toks[this.i++]; }
  lastEnd() { return this.toks[this.i - 1].end; }
  fail(expected, fix, code = 'E100', tok = this.peek()) {
    throw new AkashiError(diag(code, `expected ${expected} but found ${show(tok)}`, tok.pos, fix));
  }
  expectOp(v, fix) { if (!this.isOp(v)) this.fail(`'${v}'`, fix ?? `write '${v}' here`); return this.next(); }
  expectKw(v, fix) { if (!this.isKw(v)) this.fail(`'${v}'`, fix ?? `write '${v}' here`); return this.next(); }
  expectId(what, fix) {
    if (!this.is('id')) {
      const tok = this.peek();
      if (tok.t === 'kw') this.fail(what, `'${tok.v}' is a reserved word; choose another name`);
      this.fail(what, fix ?? `write ${what} here`);
    }
    return this.next();
  }
  text(startOffset) { return this.src.slice(startOffset, this.lastEnd()); }

  program() {
    const fns = [];
    const types = [];
    while (!this.is('eof')) {
      if (this.isKw('type')) { types.push(this.typeDecl()); continue; }
      if (this.isKw('end')) {
        throw new AkashiError(diag('E108', "extra 'end'", this.peek().pos, 'every if ... then ... else ... end and every fn ... do ... end needs exactly one end. An else if is a new if inside else, so it needs its own end too: count one end per if'));
      }
      if (!this.isKw('fn')) this.fail("'fn' or 'type'", 'every top-level item is a function (fn name(arg: Type) -> Type ... do ... end) or a type (type Name case A(x: Int) case B end)');
      fns.push(this.fn());
    }
    return { fns, types };
  }

  // type Shape
  //   case Circle(radius: Int)
  //   case Empty
  // end
  typeDecl() {
    const pos = this.next().pos;
    const nameTok = this.expectId('a type name');
    if (!isUpper(nameTok.v)) this.fail('a type name starting with a capital letter', `write type ${nameTok.v[0].toUpperCase()}${nameTok.v.slice(1)}`, 'E100', nameTok);
    const variants = [];
    while (this.isKw('case')) {
      this.next();
      const v = this.expectId('a case name');
      if (!isUpper(v.v)) this.fail('a case name starting with a capital letter', `write case ${v.v[0].toUpperCase()}${v.v.slice(1)}`, 'E100', v);
      const fields = [];
      if (this.isOp('(')) {
        this.next();
        for (;;) {
          const f = this.expectId('a field name');
          this.expectOp(':', `every field needs a type: ${f.v}: Int`);
          fields.push({ name: f.v, type: this.type(), pos: f.pos });
          if (this.isOp(',')) { this.next(); continue; }
          break;
        }
        this.expectOp(')', 'close the field list with )');
      }
      variants.push({ name: v.v, fields, pos: v.pos });
    }
    if (variants.length === 0) this.fail("'case'", `list the cases: type ${nameTok.v} case A(x: Int) case B end (a record is a type with one case)`);
    this.expectKw('end', `close the type ${nameTok.v} with end`);
    return { name: nameTok.v, variants, pos };
  }

  fn() {
    const pos = this.next().pos;
    const name = this.expectId('a function name').v;
    this.expectOp('(', `write the parameter list: fn ${name}(x: Int) -> Int`);
    const params = [];
    if (!this.isOp(')')) {
      for (;;) {
        const p = this.expectId('a parameter name');
        this.expectOp(':', `every parameter needs a type: ${p.v}: Int`);
        params.push({ name: p.v, type: this.type(), pos: p.pos });
        if (this.isOp(',')) { this.next(); continue; }
        break;
      }
    }
    this.expectOp(')');
    if (!this.isOp('->')) this.fail("'->' and a return type", 'every function declares its return type, e.g. -> Int; write -> Unit when it returns nothing', 'E102');
    this.next();
    const ret = this.type();
    const fn = { name, params, ret, pos, requires: [], ensures: [], examples: [] };
    for (;;) {
      if (this.isKw('requires')) { this.next(); fn.requires.push(this.clause()); continue; }
      if (this.isKw('ensures')) { this.next(); fn.ensures.push(this.clause()); continue; }
      if (this.isKw('example')) { this.next(); fn.examples.push(this.clause()); continue; }
      if (this.isKw('effects')) {
        throw new AkashiError(diag('E305', "'effects' is not used: authority is passed as capability parameters", this.peek().pos, `remove the effects line and take the capability as a parameter, e.g. fn ${name}(console: Console, ...) -> ...; call print(to: console, value: ...)`));
      }
      break;
    }
    this.expectKw('do', `after the signature and clauses (requires / ensures / example) write do, then the body, then end`);
    fn.body = this.block(['end']);
    this.expectKw('end', `close the body of ${name} with end`);
    return fn;
  }

  // requires / ensures / example の式。失敗を見せるために元の文字列を持たせる
  clause() {
    const start = this.peek().pos.offset;
    const e = this.expr();
    return { expr: e, src: this.text(start) };
  }

  type() {
    const tok = this.peek();
    const names = this.typeNames;
    if (!this.is('id')) this.fail('a type', `types are ${names.join(', ')}; lists are written List[Int]`, 'E104');
    this.next();
    if (!names.includes(tok.v)) {
      const s = suggest(tok.v, names);
      const nullish = ['Null', 'None', 'Nil', 'Maybe', 'Optional', 'null', 'nil'].includes(tok.v);
      throw new AkashiError(diag('E104', `unknown type '${tok.v}'`, tok.pos, nullish ? 'there is no null; a value that may be missing has type Option[T] (Some(value: x) or None)' : s ? `did you mean ${s}? (types: ${names.join(', ')})` : `types are ${names.join(', ')}; lists are written List[Int]; declare your own with type Name case ... end`));
    }
    if (BUILTIN_DATA.includes(tok.v)) {
      this.expectOp('[', `write the value type: ${tok.v}[Int]`);
      const of = this.type();
      this.expectOp(']', `close the value type: ${tok.v}[Int]`);
      return { k: 'Data', name: tok.v, args: [of] };
    }
    if (this.userTypes.includes(tok.v)) return { k: 'Data', name: tok.v, args: [] };
    if (tok.v === 'List') {
      this.expectOp('[', 'write the item type: List[Int]');
      const of = this.type();
      this.expectOp(']', 'close the item type: List[Int]');
      return { k: 'List', of };
    }
    return { k: tok.v };
  }

  // ブロック = 行の並び。let の行、Unit の式の行（print など）、最後に値の式が1つ
  block(terminators) {
    const lets = [];
    const atEnd = () => terminators.some((t) => this.isKw(t));
    for (;;) {
      if (this.isKw('let')) {
        const pos = this.next().pos;
        const name = this.expectId('a name after let').v;
        if (!this.isOp(':')) this.fail("':' and a type", `write the type: let ${name}: Int = ...`, 'E103');
        this.next();
        const type = this.type();
        this.expectOp('=', `write = and the value: let ${name}: ... = value`);
        lets.push({ k: 'let', name, type, value: this.expr(), pos });
        continue;
      }
      if (atEnd()) {
        this.fail('an expression', 'a block ends with one expression: its value. Write the value as the last line (use () for Unit)');
      }
      const e = this.expr();
      if (atEnd()) return { lets, result: e };
      lets.push({ k: 'do', expr: e, pos: e.pos });
    }
  }

  expr() { return this.logic(); }

  logic() {
    let left = this.compare();
    if (this.isKw('and') || this.isKw('or')) {
      const op = this.peek().v;
      while (this.isKw(op)) {
        const pos = this.next().pos;
        const right = this.compare();
        left = { k: 'bin', op, left, right, pos };
      }
      if (this.isKw('and') || this.isKw('or')) {
        throw new AkashiError(diag('E105', `'and' and 'or' are mixed without parentheses`, this.peek().pos, `add parentheses to show the grouping, e.g. (a and b) or c`));
      }
    }
    return left;
  }

  compare() {
    const left = this.add();
    const ops = ['==', '!=', '<', '<=', '>', '>='];
    if (ops.some((o) => this.isOp(o))) {
      const tok = this.next();
      const right = this.add();
      if (ops.some((o) => this.isOp(o))) {
        throw new AkashiError(diag('E106', 'comparisons cannot be chained', this.peek().pos, 'split it with and, e.g. 0 <= x and x < 10'));
      }
      return { k: 'bin', op: tok.v, left, right, pos: tok.pos };
    }
    return left;
  }

  add() {
    let left = this.mul();
    while (this.isOp('+') || this.isOp('-') || this.isOp('++')) {
      const tok = this.next();
      left = { k: 'bin', op: tok.v, left, right: this.mul(), pos: tok.pos };
    }
    return left;
  }

  mul() {
    let left = this.unary();
    while (this.isOp('*') || this.isOp('/') || this.isOp('%')) {
      const tok = this.next();
      left = { k: 'bin', op: tok.v, left, right: this.unary(), pos: tok.pos };
    }
    return left;
  }

  unary() {
    if (this.isKw('not') || this.isOp('-')) {
      const tok = this.next();
      return { k: 'un', op: tok.v, arg: this.unary(), pos: tok.pos };
    }
    return this.primary();
  }

  primary() {
    const tok = this.peek();
    if (tok.t === 'int') { this.next(); return { k: 'int', v: tok.v, pos: tok.pos }; }
    if (tok.t === 'str') { this.next(); return { k: 'str', v: tok.v, pos: tok.pos }; }
    if (this.isKw('true') || this.isKw('false')) { this.next(); return { k: 'bool', v: tok.v === 'true', pos: tok.pos }; }
    if (this.isOp('(')) {
      this.next();
      if (this.isOp(')')) { this.next(); return { k: 'unit', pos: tok.pos }; }
      const e = this.expr();
      this.expectOp(')', 'close the parenthesis');
      return e;
    }
    if (this.isOp('[')) {
      this.next();
      const items = [];
      if (!this.isOp(']')) {
        for (;;) {
          items.push(this.expr());
          if (this.isOp(',')) { this.next(); continue; }
          break;
        }
      }
      this.expectOp(']', 'close the list with ]');
      return { k: 'list', items, pos: tok.pos };
    }
    // when：いくつもの場合分けを end 1つで書く。上から順に調べ、最後は else
    if (this.isKw('when')) {
      this.next();
      const arms = [];
      while (!this.isKw('else')) {
        if (this.isKw('end')) {
          throw new AkashiError(diag('E112', "'when' has no 'else'", this.peek().pos, 'end every when with an else line: else <value>'));
        }
        const cond = this.expr();
        this.expectKw('then', 'each line of when is: condition then value');
        arms.push({ cond, value: this.expr() });
      }
      if (arms.length === 0) this.fail('a condition', 'write at least one line: condition then value');
      this.next();
      let result = this.expr();
      this.expectKw('end', 'close the when with end (after the else line)');
      for (const arm of arms.reverse()) {
        result = { k: 'if', cond: arm.cond, thenB: { lets: [], result: arm.value }, elseB: { lets: [], result }, pos: arm.cond.pos };
      }
      return result;
    }
    // match：自分で作る型の場合分け。どの case も1回ずつ書く（抜けは E210。何でも受ける _ は無い）
    if (this.isKw('match')) {
      this.next();
      const subject = this.expr();
      const arms = [];
      while (this.isKw('case')) {
        const cpos = this.next().pos;
        const v = this.expectId('a case name', 'write case Name(field: name) then value');
        const binds = [];
        if (this.isOp('(')) {
          this.next();
          for (;;) {
            const f = this.expectId('a field name', 'write the field and a new name for its value: case Circle(radius: r) then ...');
            this.expectOp(':', `write ${f.v}: and a new name (or _ to ignore it)`);
            const b = this.expectId('a name for the field value', 'write a new name, or _ to ignore the field');
            binds.push({ field: f.v, name: b.v, pos: b.pos });
            if (this.isOp(',')) { this.next(); continue; }
            break;
          }
          this.expectOp(')', 'close the pattern with )');
        }
        this.expectKw('then', 'each case line is: case Name(field: name) then value');
        arms.push({ variant: v.v, binds, value: this.expr(), pos: cpos, vpos: v.pos });
      }
      if (this.isKw('else')) {
        throw new AkashiError(diag('E211', "'match' has no else", this.peek().pos, 'write one case line per case of the type instead of else; then adding a case later shows every match that must handle it'));
      }
      if (arms.length === 0) this.fail("'case'", 'write the cases: match x case A then ... case B then ... end');
      this.expectKw('end', 'close the match with end');
      return { k: 'match', subject, arms, pos: tok.pos };
    }
    if (this.isKw('if')) {
      this.next();
      const cond = this.expr();
      this.expectKw('then', 'write: if condition then value else value end');
      const thenB = this.block(['else', 'end']);
      if (this.isKw('end')) {
        throw new AkashiError(diag('E107', "'if' has no 'else'", this.peek().pos, 'every if is an expression and needs else: if c then a else b end (use else () when the value is Unit)'));
      }
      this.next();
      const elseB = this.block(['end']);
      this.expectKw('end', 'close the if with end');
      return { k: 'if', cond, thenB, elseB, pos: tok.pos };
    }
    if (tok.t === 'id') {
      this.next();
      if (this.isOp('(')) {
        this.next();
        const args = [];
        if (!this.isOp(')')) {
          for (;;) {
            const a = this.peek();
            if (a.t === 'id' && this.peek(1).t === 'op' && this.peek(1).v === ':') {
              this.next();
              this.next();
              args.push({ name: a.v, value: this.expr(), pos: a.pos });
            } else {
              args.push({ name: null, value: this.expr(), pos: a.pos });
            }
            if (this.isOp(',')) { this.next(); continue; }
            break;
          }
        }
        this.expectOp(')', 'close the argument list with )');
        return { k: 'call', name: tok.v, args, pos: tok.pos };
      }
      return { k: 'var', name: tok.v, pos: tok.pos };
    }
    if (tok.t === 'kw') this.fail('an expression', `'${tok.v}' cannot start an expression here`);
    return this.fail('an expression', 'write a value, a name, a call like f(x: 1), a list [1, 2], or if ... then ... else ... end');
  }
}

export function parse(src) {
  return new Parser(src, lex(src)).program();
}
