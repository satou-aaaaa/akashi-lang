// コンパイラ：検査を通った Akashi を WebAssembly（WASI preview1 のコマンド）のバイナリに直接書き出す。
// 外の部品（LLVM・Binaryen など）は使わない。バイナリの形は WebAssembly Core Specification の「Binary Format」の章のとおり。
// 意味の正はインタプリタ（src/run.js）。同じプログラムの出力・終わりのコード・エラー番号が一致することを test/compile.test.js が毎回比べる。
//
// 段階1（今）で扱えるもの：Int・Bool・Str・Unit、関数・再帰、let、if・when、requires・ensures、
//   print・to_str・str_len、+ - * / %、比較、and・or・not、++（Str）。
// それ以外を使うと E600（コンパイラがまだ扱えない）。そのプログラムは akashi run（インタプリタ）で動かす。
//
// 値の表し方：Int は i64、Bool は i32（0/1）、Str は i32（メモリ上の [長さ u32][UTF-8 のバイト] の先頭）、Unit は値なし。
// 鍵（Console）は実行時には何も渡さない（検査で使い方を確かめ終わっているので、消してよい）。
import { diag } from './errors.js';
import { prune } from './check.js';

const MAX = 9007199254740991n; // インタプリタの Int の上限（Number.MAX_SAFE_INTEGER）と同じ
const MAX_DEPTH = 500; // src/run.js と同じ

// ---- バイトの書き方 ----
const I32 = 0x7f;
const I64 = 0x7e;
const EMPTY = 0x40;

function uleb(n) {
  const out = [];
  do {
    let b = n & 0x7f;
    n >>>= 7;
    if (n !== 0) b |= 0x80;
    out.push(b);
  } while (n !== 0);
  return out;
}

function sleb(n) {
  let v = BigInt(n);
  const out = [];
  for (;;) {
    const b = Number(v & 0x7fn);
    v >>= 7n;
    const done = (v === 0n && (b & 0x40) === 0) || (v === -1n && (b & 0x40) !== 0);
    out.push(done ? b : b | 0x80);
    if (done) return out;
  }
}

const utf8 = (s) => [...new TextEncoder().encode(s)];
const name = (s) => [...uleb(utf8(s).length), ...utf8(s)];
const vec = (items) => [...uleb(items.length), ...items.flat()];
const section = (id, body) => [id, ...uleb(body.length), ...body];

// 命令（使う分だけ）
const op = {
  unreachable: [0x00], block: (t) => [0x02, t], loop: (t) => [0x03, t], if: (t) => [0x04, t], else: [0x05], end: [0x0b],
  br: (d) => [0x0c, ...uleb(d)], brIf: (d) => [0x0d, ...uleb(d)], return: [0x0f], call: (i) => [0x10, ...uleb(i)], drop: [0x1a],
  localGet: (i) => [0x20, ...uleb(i)], localSet: (i) => [0x21, ...uleb(i)], localTee: (i) => [0x22, ...uleb(i)],
  globalGet: (i) => [0x23, ...uleb(i)], globalSet: (i) => [0x24, ...uleb(i)],
  i32Load: (off = 0) => [0x28, 2, ...uleb(off)], i32Load8u: (off = 0) => [0x2d, 0, ...uleb(off)],
  i32Store: (off = 0) => [0x36, 2, ...uleb(off)], i32Store8: (off = 0) => [0x3a, 0, ...uleb(off)],
  memorySize: [0x3f, 0], memoryGrow: [0x40, 0],
  i32: (n) => [0x41, ...sleb(n)], i64: (n) => [0x42, ...sleb(n)],
  i32Eqz: [0x45], i32Eq: [0x46], i32Ne: [0x47], i32LtU: [0x49], i32GtU: [0x4b], i32GeU: [0x4f],
  i64Eqz: [0x50], i64Eq: [0x51], i64Ne: [0x52], i64LtS: [0x53], i64GtS: [0x55], i64LeS: [0x57], i64GeS: [0x59],
  i32Add: [0x6a], i32Sub: [0x6b], i32Mul: [0x6c], i32And: [0x71], i32Or: [0x72], i32Xor: [0x73], i32Shl: [0x74],
  i64Add: [0x7c], i64Sub: [0x7d], i64Mul: [0x7e], i64DivS: [0x7f], i64DivU: [0x80], i64RemS: [0x81], i64RemU: [0x82],
  i32WrapI64: [0xa7], i64ExtendI32U: [0xad],
  memoryCopy: [0xfc, ...uleb(10), 0, 0],
};

// ---- 対応していないもの ----
class Unsupported extends Error {
  constructor(what, pos) { super(what); this.what = what; this.pos = pos; }
}

const SUPPORTED_BUILTINS = ['print', 'to_str', 'str_len'];

function valType(t) {
  t = prune(t);
  switch (t.k) {
    case 'Int': return I64;
    case 'Bool': case 'Str': return I32;
    case 'Unit': return null;
    default: return undefined;
  }
}

// ---- メモリの配置 ----
// 0..15: fd_write の iovec、16..47: 数を文字にするときの作業場、48..: 文字の定数、その後ろ: ヒープ（増える一方。プログラムは短く終わる前提）
const IOV = 0;
const SCRATCH = 16;
const DATA_START = 48;

export function compile(program, file = '<input>') {
  try {
    return { ok: true, bytes: new Uint8Array(new Compiler(program, file).module()), diagnostics: [] };
  } catch (e) {
    if (e instanceof Unsupported) {
      return {
        ok: false,
        diagnostics: [diag('E600', `the compiler does not support ${e.what} yet`, e.pos, 'run this program with akashi run (the interpreter), or keep to Int, Bool, Str, functions, if / when and print for akashi build (see docs/compiler.md)')],
      };
    }
    throw e;
  }
}

class Compiler {
  constructor(program, file) {
    this.program = program;
    this.file = file;
    this.data = []; // 定数の文字の並び
    this.strings = new Map(); // 文字 → 置き場所
    this.dataEnd = DATA_START;
  }

  // 文字の定数を置き、その場所を返す（同じ文字は1つにまとめる）
  str(s) {
    if (this.strings.has(s)) return this.strings.get(s);
    const bytes = utf8(s);
    const at = this.dataEnd;
    const len = bytes.length;
    this.data.push(...[len & 0xff, (len >> 8) & 0xff, (len >> 16) & 0xff, (len >>> 24) & 0xff], ...bytes);
    this.dataEnd += 4 + len;
    while (this.dataEnd % 4) { this.data.push(0); this.dataEnd++; }
    this.strings.set(s, at);
    return at;
  }

  // エラーの文（インタプリタと同じ番号。場所は「行:列」）
  failAt(code, message, pos) {
    return [...op.i32(this.str(`${pos?.line ?? 0}:${pos?.col ?? 0}: ${code} ${message}`)), ...op.call(this.h.fail)];
  }

  module() {
    const p = this.program;
    if (p.types?.length) throw new Unsupported('type declarations', p.types[0].pos);
    const main = p.fns.find((f) => f.name === 'main');
    if (!main) throw new Unsupported('a program without main', { line: 1, col: 1 });
    for (const prm of main.params) if (prm.type.k !== 'Console') throw new Unsupported(`the capability ${prm.type.k}`, prm.pos);

    // 関数の番号：0..1 は取り込み、続いて手伝いの関数、続いて利用者の関数、最後に _start
    this.types = [];
    const typeIndex = (params, results) => {
      const key = JSON.stringify([params, results]);
      let i = this.types.findIndex((t) => t.key === key);
      if (i < 0) { i = this.types.length; this.types.push({ key, bytes: [0x60, ...vec(params.map((x) => [x])), ...vec(results.map((x) => [x]))] }); }
      return i;
    };
    const imports = [
      { mod: 'wasi_snapshot_preview1', name: 'fd_write', type: typeIndex([I32, I32, I32, I32], [I32]) },
      { mod: 'wasi_snapshot_preview1', name: 'proc_exit', type: typeIndex([I32], []) },
    ];
    const IMP = { fdWrite: 0, procExit: 1 };
    const helperNames = ['alloc', 'write', 'fail', 'chk', 'mul', 'concat', 'itoa', 'streq', 'strlen', 'enter', 'leave'];
    this.h = Object.fromEntries(helperNames.map((n, i) => [n, imports.length + i]));
    const userBase = imports.length + helperNames.length;
    this.fnIndex = new Map(p.fns.map((f, i) => [f.name, userBase + i]));
    const startIndex = userBase + p.fns.length;
    const G = { heap: 0, depth: 1 };
    this.G = G;

    // 利用者の関数を先に作る（文字の定数を集めて、ヒープの始まりを決めるため）
    const userFns = p.fns.map((f) => this.fn(f));
    const helpers = this.helpers(IMP, G);
    const start = { type: typeIndex([], []), locals: [], body: [...op.call(this.fnIndex.get('main')), ...op.end] };

    const funcs = [
      ...helpers.map((x) => ({ ...x, type: typeIndex(x.params, x.results) })),
      ...userFns.map((x) => ({ ...x, type: typeIndex(x.params, x.results) })),
      start,
    ];
    const heapStart = (this.dataEnd + 7) & ~7;
    const pages = Math.max(1, Math.ceil(heapStart / 65536) + 1);

    const code = (f) => {
      const locals = [];
      for (const t of f.locals) {
        if (locals.length && locals[locals.length - 1][1] === t) locals[locals.length - 1][0]++;
        else locals.push([1, t]);
      }
      const body = [...vec(locals.map(([n, t]) => [...uleb(n), t])), ...f.body];
      return [...uleb(body.length), ...body];
    };

    return [
      0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
      ...section(1, vec(this.types.map((t) => t.bytes))),
      ...section(2, vec(imports.map((im) => [...name(im.mod), ...name(im.name), 0x00, ...uleb(im.type)]))),
      ...section(3, vec(funcs.map((f) => uleb(f.type)))),
      ...section(5, vec([[0x00, ...uleb(pages)]])),
      ...section(6, vec([
        [I32, 0x01, ...op.i32(heapStart), ...op.end], // ヒープの次の空き
        [I32, 0x01, ...op.i32(0), ...op.end], // 呼び出しの深さ
      ])),
      ...section(7, vec([
        [...name('memory'), 0x02, ...uleb(0)],
        [...name('_start'), 0x00, ...uleb(startIndex)],
      ])),
      ...section(10, vec(funcs.map(code))),
      ...section(11, vec([[0x00, ...op.i32(DATA_START), ...op.end, ...vec(this.data.map((b) => [b]))]])),
    ];
  }

  // ---- 手伝いの関数（実行時の部品）。どれも小さく、インタプリタの同じ働きに合わせる ----
  helpers(IMP, G) {
    const h = this.h;
    const nl = this.str('\n');
    const r504 = this.str('R504 integer overflow');
    const r505 = this.str(`R505 recursion deeper than ${MAX_DEPTH} calls`);
    return [
      { // alloc(n) -> 場所。4 の倍数にそろえ、足りなければメモリを増やす
        params: [I32], results: [I32], locals: [I32],
        body: [
          ...op.globalGet(G.heap), ...op.localSet(1),
          ...op.globalGet(G.heap), ...op.localGet(0), ...op.i32Add, ...op.i32(3), ...op.i32Add, ...op.i32(-4), ...op.i32And, ...op.globalSet(G.heap),
          ...op.block(EMPTY), ...op.loop(EMPTY),
          ...op.globalGet(G.heap), ...op.memorySize, ...op.i32(16), ...op.i32Shl, ...op.i32LtU, ...op.brIf(1),
          ...op.i32(1), ...op.memoryGrow, ...op.i32(-1), ...op.i32Eq, ...op.if(EMPTY), ...op.unreachable, ...op.end,
          ...op.br(0), ...op.end, ...op.end,
          ...op.localGet(1), ...op.end,
        ],
      },
      { // write(fd, str, 改行するか)
        params: [I32, I32, I32], results: [], locals: [],
        body: [
          ...op.i32(IOV), ...op.localGet(1), ...op.i32(4), ...op.i32Add, ...op.i32Store(0),
          ...op.i32(IOV), ...op.localGet(1), ...op.i32Load(0), ...op.i32Store(4),
          ...op.i32(IOV), ...op.i32(nl + 4), ...op.i32Store(8),
          ...op.i32(IOV), ...op.i32(1), ...op.i32Store(12),
          ...op.localGet(0), ...op.i32(IOV), ...op.i32(1), ...op.localGet(2), ...op.i32Add, ...op.i32(IOV + 32 - 16 + 16), ...op.call(IMP.fdWrite), ...op.drop,
          ...op.end,
        ],
      },
      { // fail(文) : 文を標準エラーに出して、終わりのコード 1 で止める
        params: [I32], results: [], locals: [],
        body: [...op.i32(2), ...op.localGet(0), ...op.i32(1), ...op.call(h.write), ...op.i32(1), ...op.call(IMP.procExit), ...op.unreachable, ...op.end],
      },
      { // chk(x) : ±MAX を超えたら R504
        params: [I64], results: [I64], locals: [],
        body: [
          ...op.localGet(0), ...op.i64(MAX), ...op.i64GtS, ...op.localGet(0), ...op.i64(-MAX), ...op.i64LtS, ...op.i32Or,
          ...op.if(EMPTY), ...op.i32(r504), ...op.call(h.fail), ...op.end,
          ...op.localGet(0), ...op.end,
        ],
      },
      { // mul(a, b) : かける前に、あふれないかを確かめる（|b| > MAX / |a| ならあふれる）
        params: [I64, I64], results: [I64], locals: [I64, I64],
        body: [
          ...op.localGet(0), ...op.i64Eqz, ...op.localGet(1), ...op.i64Eqz, ...op.i32Or, ...op.if(EMPTY), ...op.i64(0), ...op.return, ...op.end,
          ...abs(0, 2), ...abs(1, 3),
          ...op.localGet(3), ...op.i64(MAX), ...op.localGet(2), ...op.i64DivU, ...op.i64GtS,
          ...op.if(EMPTY), ...op.i32(r504), ...op.call(h.fail), ...op.end,
          ...op.localGet(0), ...op.localGet(1), ...op.i64Mul, ...op.end,
        ],
      },
      { // concat(a, b) -> 新しい文字
        params: [I32, I32], results: [I32], locals: [I32, I32, I32],
        body: [
          ...op.localGet(0), ...op.i32Load(0), ...op.localSet(2),
          ...op.localGet(1), ...op.i32Load(0), ...op.localSet(3),
          ...op.localGet(2), ...op.localGet(3), ...op.i32Add, ...op.i32(4), ...op.i32Add, ...op.call(h.alloc), ...op.localSet(4),
          ...op.localGet(4), ...op.localGet(2), ...op.localGet(3), ...op.i32Add, ...op.i32Store(0),
          ...op.localGet(4), ...op.i32(4), ...op.i32Add, ...op.localGet(0), ...op.i32(4), ...op.i32Add, ...op.localGet(2), ...op.memoryCopy,
          ...op.localGet(4), ...op.i32(4), ...op.i32Add, ...op.localGet(2), ...op.i32Add, ...op.localGet(1), ...op.i32(4), ...op.i32Add, ...op.localGet(3), ...op.memoryCopy,
          ...op.localGet(4), ...op.end,
        ],
      },
      { // itoa(x) -> 10進の文字。作業場の後ろから数字を書き、最後に新しい文字へ写す
        params: [I64], results: [I32], locals: [I64, I32, I32, I32],
        // locals: 1 = |x|、2 = 書く場所、3 = 負か、4 = 結果
        body: [
          ...op.localGet(0), ...op.i64(0), ...op.i64LtS, ...op.localSet(3),
          ...abs(0, 1),
          ...op.i32(SCRATCH + 32), ...op.localSet(2),
          ...op.loop(EMPTY),
          ...op.localGet(2), ...op.i32(1), ...op.i32Sub, ...op.localTee(2),
          ...op.localGet(1), ...op.i64(10), ...op.i64RemU, ...op.i32WrapI64, ...op.i32(48), ...op.i32Add, ...op.i32Store8(0),
          ...op.localGet(1), ...op.i64(10), ...op.i64DivU, ...op.localTee(1), ...op.i64Eqz, ...op.i32Eqz, ...op.brIf(0),
          ...op.end,
          ...op.localGet(3), ...op.if(EMPTY),
          ...op.localGet(2), ...op.i32(1), ...op.i32Sub, ...op.localTee(2), ...op.i32(45), ...op.i32Store8(0),
          ...op.end,
          ...op.i32(SCRATCH + 32), ...op.localGet(2), ...op.i32Sub, ...op.i32(4), ...op.i32Add, ...op.call(h.alloc), ...op.localSet(4),
          ...op.localGet(4), ...op.i32(SCRATCH + 32), ...op.localGet(2), ...op.i32Sub, ...op.i32Store(0),
          ...op.localGet(4), ...op.i32(4), ...op.i32Add, ...op.localGet(2), ...op.i32(SCRATCH + 32), ...op.localGet(2), ...op.i32Sub, ...op.memoryCopy,
          ...op.localGet(4), ...op.end,
        ],
      },
      { // streq(a, b) -> 同じなら 1
        params: [I32, I32], results: [I32], locals: [I32, I32],
        body: [
          ...op.localGet(0), ...op.i32Load(0), ...op.localTee(2), ...op.localGet(1), ...op.i32Load(0), ...op.i32Ne, ...op.if(EMPTY), ...op.i32(0), ...op.return, ...op.end,
          ...op.i32(0), ...op.localSet(3),
          ...op.block(EMPTY), ...op.loop(EMPTY),
          ...op.localGet(3), ...op.localGet(2), ...op.i32GeU, ...op.brIf(1),
          ...op.localGet(0), ...op.localGet(3), ...op.i32Add, ...op.i32Load8u(4), ...op.localGet(1), ...op.localGet(3), ...op.i32Add, ...op.i32Load8u(4), ...op.i32Ne,
          ...op.if(EMPTY), ...op.i32(0), ...op.return, ...op.end,
          ...op.localGet(3), ...op.i32(1), ...op.i32Add, ...op.localSet(3), ...op.br(0),
          ...op.end, ...op.end,
          ...op.i32(1), ...op.end,
        ],
      },
      { // strlen(s) -> 文字（コードポイント）の数。UTF-8 の続きのバイト（10xxxxxx）は数えない
        params: [I32], results: [I64], locals: [I32, I32, I64],
        body: [
          ...op.localGet(0), ...op.i32Load(0), ...op.localSet(1),
          ...op.block(EMPTY), ...op.loop(EMPTY),
          ...op.localGet(2), ...op.localGet(1), ...op.i32GeU, ...op.brIf(1),
          ...op.localGet(0), ...op.localGet(2), ...op.i32Add, ...op.i32Load8u(4), ...op.i32(0xc0), ...op.i32And, ...op.i32(0x80), ...op.i32Ne,
          ...op.i64ExtendI32U, ...op.localGet(3), ...op.i64Add, ...op.localSet(3),
          ...op.localGet(2), ...op.i32(1), ...op.i32Add, ...op.localSet(2), ...op.br(0),
          ...op.end, ...op.end,
          ...op.localGet(3), ...op.end,
        ],
      },
      { // enter() : 呼び出しの深さを1つ増やす（MAX_DEPTH を超えたら R505）
        params: [], results: [], locals: [],
        body: [
          ...op.globalGet(G.depth), ...op.i32(1), ...op.i32Add, ...op.globalSet(G.depth),
          ...op.globalGet(G.depth), ...op.i32(MAX_DEPTH), ...op.i32GtU, ...op.if(EMPTY), ...op.i32(r505), ...op.call(h.fail), ...op.end,
          ...op.end,
        ],
      },
      { // leave()
        params: [], results: [], locals: [],
        body: [...op.globalGet(G.depth), ...op.i32(1), ...op.i32Sub, ...op.globalSet(G.depth), ...op.end],
      },
    ];
  }

  // ---- 利用者の関数 ----
  fn(f) {
    const params = [];
    const locals = [];
    const scope = new Map();
    for (const prm of f.params) {
      if (prm.type.k === 'Console') continue; // 鍵は消す
      const t = valType(prm.type);
      if (!t) throw new Unsupported(`parameters of type ${prm.type.k}`, prm.pos);
      scope.set(prm.name, { index: params.length, type: t });
      params.push(t);
    }
    const ret = valType(f.ret);
    if (ret === undefined) throw new Unsupported(`functions that return ${f.ret.k}`, f.pos);
    const ctx = {
      local: (t) => { locals.push(t); return params.length + locals.length - 1; },
    };
    const body = [];
    body.push(...op.call(this.h.enter));
    for (const r of f.requires) {
      body.push(...this.expr(r.expr, scope, ctx), ...op.i32Eqz, ...op.if(EMPTY), ...this.failAt('R500', `requires of '${f.name}' failed: ${r.src}`, r.expr.pos), ...op.end);
    }
    body.push(...this.block(f.body, scope, ctx));
    if (f.ensures.length) {
      if (ret === null) {
        for (const en of f.ensures) body.push(...this.ensure(f, en, scope, ctx));
      } else {
        const res = ctx.local(ret);
        body.push(...op.localSet(res));
        const scope2 = new Map(scope);
        if (!scope2.has('result')) scope2.set('result', { index: res, type: ret });
        for (const en of f.ensures) body.push(...this.ensure(f, en, scope2, ctx));
        body.push(...op.localGet(res));
      }
    }
    body.push(...op.call(this.h.leave), ...op.end);
    // leave は値の上でも呼べる（値に触らない）ので、最後の値はそのまま返る
    return { params, results: ret === null ? [] : [ret], locals, body };
  }

  ensure(f, en, scope, ctx) {
    return [...this.expr(en.expr, scope, ctx), ...op.i32Eqz, ...op.if(EMPTY), ...this.failAt('R501', `ensures of '${f.name}' failed: ${en.src}`, f.pos), ...op.end];
  }

  block(b, scope, ctx) {
    const inner = new Map(scope);
    const out = [];
    for (const l of b.lets) {
      if (l.k === 'do') {
        out.push(...this.expr(l.expr, inner, ctx));
        continue;
      }
      const t = valType(l.type);
      if (t === undefined) throw new Unsupported(`let of type ${l.type.k}`, l.pos);
      const code = this.expr(l.value, inner, ctx);
      if (t === null) { out.push(...code); continue; }
      const idx = ctx.local(t);
      out.push(...code, ...op.localSet(idx));
      inner.set(l.name, { index: idx, type: t });
    }
    out.push(...this.expr(b.result, inner, ctx));
    return out;
  }

  expr(e, scope, ctx) {
    const t = valType(e.ty);
    if (t === undefined) throw new Unsupported(`values of type ${prune(e.ty).k}`, e.pos);
    switch (e.k) {
      case 'int': return op.i64(e.v);
      case 'bool': return op.i32(e.v ? 1 : 0);
      case 'str': return op.i32(this.str(e.v));
      case 'unit': return [];
      case 'var': {
        const v = scope.get(e.name);
        if (!v) throw new Unsupported(`'${e.name}' as a value`, e.pos);
        return op.localGet(v.index);
      }
      case 'un':
        return e.op === 'not'
          ? [...this.expr(e.arg, scope, ctx), ...op.i32Eqz]
          : [...op.i64(0), ...this.expr(e.arg, scope, ctx), ...op.i64Sub];
      case 'if': {
        return [...this.expr(e.cond, scope, ctx), ...op.if(t ?? EMPTY), ...this.block(e.thenB, scope, ctx), ...op.else, ...this.block(e.elseB, scope, ctx), ...op.end];
      }
      case 'bin': return this.binary(e, scope, ctx);
      case 'call': return this.call(e, scope, ctx);
      default: throw new Unsupported(`'${e.k}' expressions`, e.pos);
    }
  }

  binary(e, scope, ctx) {
    const L = () => this.expr(e.left, scope, ctx);
    const R = () => this.expr(e.right, scope, ctx);
    const lt = prune(e.left.ty).k;
    switch (e.op) {
      case 'and': return [...L(), ...op.if(I32), ...R(), ...op.else, ...op.i32(0), ...op.end];
      case 'or': return [...L(), ...op.if(I32), ...op.i32(1), ...op.else, ...R(), ...op.end];
      case '+': return [...L(), ...R(), ...op.i64Add, ...op.call(this.h.chk)];
      case '-': return [...L(), ...R(), ...op.i64Sub, ...op.call(this.h.chk)];
      case '*': return [...L(), ...R(), ...op.call(this.h.mul)];
      case '/': case '%': {
        const b = ctx.local(I64);
        return [
          ...L(), ...R(), ...op.localTee(b), ...op.i64Eqz,
          ...op.if(EMPTY), ...this.failAt('R503', 'division by zero', e.pos), ...op.end,
          ...op.localGet(b), ...(e.op === '/' ? op.i64DivS : op.i64RemS),
        ];
      }
      case '<': return [...L(), ...R(), ...op.i64LtS];
      case '<=': return [...L(), ...R(), ...op.i64LeS];
      case '>': return [...L(), ...R(), ...op.i64GtS];
      case '>=': return [...L(), ...R(), ...op.i64GeS];
      case '==': case '!=': {
        let eq;
        if (lt === 'Int') eq = [...L(), ...R(), ...op.i64Eq];
        else if (lt === 'Bool') eq = [...L(), ...R(), ...op.i32Eq];
        else if (lt === 'Str') eq = [...L(), ...R(), ...op.call(this.h.streq)];
        else throw new Unsupported(`comparing values of type ${lt}`, e.pos);
        return e.op === '==' ? eq : [...eq, ...op.i32Eqz];
      }
      case '++':
        if (lt !== 'Str') throw new Unsupported('joining lists', e.pos);
        return [...L(), ...R(), ...op.call(this.h.concat)];
      default: throw new Unsupported(`the operator ${e.op}`, e.pos);
    }
  }

  call(e, scope, ctx) {
    const arg = (n) => e.args.find((a) => a.name === n);
    if (this.fnIndex.has(e.name)) {
      const f = this.program.fns.find((x) => x.name === e.name);
      const out = [];
      for (const prm of f.params) {
        if (prm.type.k === 'Console') continue;
        out.push(...this.expr(arg(prm.name).value, scope, ctx));
      }
      return [...out, ...op.call(this.fnIndex.get(e.name))];
    }
    if (!SUPPORTED_BUILTINS.includes(e.name)) throw new Unsupported(`the built-in function ${e.name}`, e.pos);
    if (e.name === 'str_len') return [...this.expr(arg('text').value, scope, ctx), ...op.call(this.h.strlen)];
    const v = arg('value').value;
    const s = this.showStr(v, scope, ctx);
    if (e.name === 'to_str') return s;
    return [...op.i32(1), ...s, ...op.i32(1), ...op.call(this.h.write)]; // print
  }

  // 値を、print・to_str と同じ形の文字にする
  showStr(v, scope, ctx) {
    const k = prune(v.ty).k;
    const code = this.expr(v, scope, ctx);
    switch (k) {
      case 'Str': return code;
      case 'Int': return [...code, ...op.call(this.h.itoa)];
      case 'Bool': return [...code, ...op.if(I32), ...op.i32(this.str('true')), ...op.else, ...op.i32(this.str('false')), ...op.end];
      case 'Unit': return [...code, ...op.i32(this.str('()'))];
      default: throw new Unsupported(`showing values of type ${k}`, v.pos);
    }
  }
}

// |x| を局所変数 to に入れる（x は ±MAX の中なので、符号を反転してもあふれない）
function abs(from, to) {
  return [
    ...op.localGet(from), ...op.i64(0), ...op.i64LtS,
    ...op.if(I64), ...op.i64(0), ...op.localGet(from), ...op.i64Sub, ...op.else, ...op.localGet(from), ...op.end,
    ...op.localSet(to),
  ];
}
