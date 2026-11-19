// コンパイラ：検査を通った Akashi を WebAssembly（WASI preview1 のコマンド）のバイナリに直接書き出す。
// 外の部品（LLVM・Binaryen など）は使わない。バイナリの形は WebAssembly Core Specification の「Binary Format」の章のとおり。
// 意味の正はインタプリタ（src/run.js）。同じプログラムの出力・終わりのコード・エラー番号が一致することを test/compile.test.js が毎回比べる。
//
// 扱えるもの：Int・Bool・Str・Unit・List・Option・Result・自分で作る型、関数・再帰、let、if・when・match、requires・ensures、
//   print・to_str・str_len・parse_int・trim・chars・split・join・contains・starts_with・ends_with・lines、
//   html・html_text・html_join・sql（Html は文字と同じ形。Sql は [型紙][値のリスト]）、リストの関数（len・get・at・range・append・map・filter・fold・find・any・all・
//   reverse・take・drop・sort・sum・max・min）、+ - * / %、比較（== は中身まで比べる）、and・or・not、++（Str・List）。
// それ以外を使うと E600（コンパイラがまだ扱えない）。そのプログラムは akashi run（インタプリタ）で動かす。
//
// 値の表し方：Int は i64、Bool は i32（0/1）、Str は i32（メモリ上の [長さ u32][UTF-8 のバイト] の先頭）、Unit は値なし。
//   List は i32（[長さ u32][すき間 u32][要素を 8 バイトずつ]）。型の値（Option・Result・自分で作る型）は i32（[case の番号 u32][すき間 u32][欄を 8 バイトずつ]）。
//   メモリは増える一方（ごみ集めはしない）。プログラムは短く終わる前提。
// 鍵（Console）は実行時には何も渡さない（検査で使い方を確かめ終わっているので、消してよい）。
import { diag } from './errors.js';
import { prune, fromAst, typeStr, BUILTIN_TYPES } from './check.js';

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
  i32Load: (off = 0) => [0x28, 2, ...uleb(off)], i64Load: (off = 0) => [0x29, 3, ...uleb(off)], i64Store: (off = 0) => [0x37, 3, ...uleb(off)], i32Load8u: (off = 0) => [0x2d, 0, ...uleb(off)],
  i32Store: (off = 0) => [0x36, 2, ...uleb(off)], i32Store8: (off = 0) => [0x3a, 0, ...uleb(off)],
  memorySize: [0x3f, 0], memoryGrow: [0x40, 0],
  i32: (n) => [0x41, ...sleb(n)], i64: (n) => [0x42, ...sleb(n)],
  i32Eqz: [0x45], i32Eq: [0x46], i32Ne: [0x47], i32LtS: [0x48], i32LtU: [0x49], i32GtU: [0x4b], i32LeU: [0x4d], i32GeU: [0x4f], i32GtS: [0x4a], i32GeS: [0x4e],
  i64Eqz: [0x50], i64Eq: [0x51], i64Ne: [0x52], i64LtS: [0x53], i64GtS: [0x55], i64LeS: [0x57], i64GeS: [0x59],
  i32Add: [0x6a], i32Sub: [0x6b], i32Mul: [0x6c], i32And: [0x71], i32Or: [0x72], i32Xor: [0x73], i32Shl: [0x74], i32ShrU: [0x76],
  i64Add: [0x7c], i64Sub: [0x7d], i64Mul: [0x7e], i64DivS: [0x7f], i64DivU: [0x80], i64RemS: [0x81], i64RemU: [0x82],
  i32WrapI64: [0xa7], i64ExtendI32U: [0xad],
  memoryCopy: [0xfc, ...uleb(10), 0, 0], select: [0x1b],
};

// ---- 対応していないもの ----
class Unsupported extends Error {
  constructor(what, pos) { super(what); this.what = what; this.pos = pos; }
}

const LIST_BUILTINS = ['len', 'get', 'at', 'range', 'append', 'map', 'filter', 'fold', 'find', 'any', 'all', 'reverse', 'take', 'drop', 'sort', 'sum', 'max', 'min'];
const TEXT_BUILTINS = ['chars', 'split', 'join', 'contains', 'starts_with', 'ends_with', 'lines', 'html', 'html_text', 'html_join', 'sql'];
const DICT_BUILTINS = ['dict', 'dict_put', 'dict_get', 'dict_has', 'dict_remove', 'dict_keys', 'dict_values', 'dict_size'];
const CAPS = ['Console', 'Folder']; // 鍵。実行時には何も渡さない（Folder は WASI の fd 3）
const SUPPORTED_BUILTINS = ['print', 'to_str', 'str_len', 'parse_int', 'trim', 'read_text', 'slice', 'code_of', 'char_of', ...LIST_BUILTINS, ...TEXT_BUILTINS, ...DICT_BUILTINS];

function valType(t) {
  t = prune(t);
  switch (t.k) {
    case 'Int': return I64;
    case 'Bool': case 'Str': case 'List': case 'Dict': case 'Data': case 'Html': case 'Sql': return I32;
    case 'Unit': return null;
    case 'Var': return null; // まだ決まらない型（空のリストの要素など）。値は1つも作られないので、何も置かない
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
        diagnostics: [diag('E600', `the compiler does not support ${e.what} yet`, e.pos, 'run this program with akashi run (the interpreter); docs/compiler.md lists what akashi build supports now')],
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
    // 型と case の表（case の番号は、型に書いた順）
    this.decls = new Map([...BUILTIN_TYPES, ...(program.types ?? [])].map((d) => [d.name, d]));
    this.variantOf = new Map();
    for (const d of this.decls.values()) d.variants.forEach((v, index) => this.variantOf.set(v.name, { decl: d, index, variant: v }));
    // 型ごとに作る手伝いの関数（表示・比べる・並べかえなど）。必要になったものだけ作る
    this.gens = [];
    this.genIdx = new Map();
    this.tagConsts = new Map();
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
    const main = p.fns.find((f) => f.name === 'main');
    if (!main) throw new Unsupported('a program without main', { line: 1, col: 1 });
    for (const prm of main.params) if (!CAPS.includes(prm.type.k)) throw new Unsupported(`the parameter ${prm.name} of main`, prm.pos);
    const folder = main.params.find((x) => x.type.k === 'Folder');

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
    // ファイルを読むのは、main が Folder を受け取るときだけ。そのときも、読むための5つだけを取り込む
    if (folder) {
      for (const [key, nm, params] of [
        ['prestat', 'fd_prestat_get', [I32, I32]],
        ['pathOpen', 'path_open', [I32, I32, I32, I32, I32, I64, I64, I32, I32]],
        ['fdFilestat', 'fd_filestat_get', [I32, I32]],
        ['fdRead', 'fd_read', [I32, I32, I32, I32]],
        ['fdClose', 'fd_close', [I32]],
      ]) {
        IMP[key] = imports.length;
        imports.push({ mod: 'wasi_snapshot_preview1', name: nm, type: typeIndex(params, [I32]) });
      }
    }
    this.imp = IMP;
    const helperNames = ['alloc', 'write', 'fail', 'chk', 'mul', 'concat', 'itoa', 'streq', 'strlen', 'enter', 'leave'];
    this.h = Object.fromEntries(helperNames.map((n, i) => [n, imports.length + i]));
    const userBase = imports.length + helperNames.length;
    this.fnIndex = new Map(p.fns.map((f, i) => [f.name, userBase + i]));
    const startIndex = userBase + p.fns.length;
    this.genBase = startIndex + 1;
    const G = { heap: 0, depth: 1 };
    this.G = G;

    // 利用者の関数を先に作る（文字の定数を集めて、ヒープの始まりを決めるため）
    const userFns = p.fns.map((f) => this.fn(f));
    const helpers = this.helpers(IMP, G);
    // 始めに、フォルダ（fd 3）が渡されているかを確かめる。無ければインタプリタと同じく R509
    const grant = folder
      ? [...op.i32(3), ...op.i32(SCRATCH), ...op.call(IMP.prestat), ...op.if(EMPTY), ...this.failAt('R509', `main asks for a Folder ('${folder.name}') but none was granted`, folder.pos), ...op.end]
      : [];
    const start = { type: typeIndex([], []), locals: [], body: [...grant, ...op.call(this.fnIndex.get('main')), ...op.end] };

    const funcs = [
      ...helpers.map((x) => ({ ...x, type: typeIndex(x.params, x.results) })),
      ...userFns.map((x) => ({ ...x, type: typeIndex(x.params, x.results) })),
      start,
      ...this.gens.map((x) => ({ ...x, type: typeIndex(x.params, x.results) })),
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
      if (CAPS.includes(prm.type.k)) continue; // 鍵は消す
      const t = valType(prm.type);
      if (t === undefined) throw new Unsupported(`parameters of type ${typeStr(fromAst(prm.type))}`, prm.pos);
      if (t === null) { scope.set(prm.name, { index: -1, type: null }); continue; }
      scope.set(prm.name, { index: params.length, type: t });
      params.push(t);
    }
    const ret = valType(f.ret);
    if (ret === undefined) throw new Unsupported(`functions that return ${typeStr(fromAst(f.ret))}`, f.pos);
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
      if (t === undefined) throw new Unsupported(`let of type ${typeStr(fromAst(l.type))}`, l.pos);
      const code = this.expr(l.value, inner, ctx);
      if (t === null) { out.push(...code); inner.set(l.name, { index: -1, type: null }); continue; }
      const idx = ctx.local(t);
      out.push(...code, ...op.localSet(idx));
      inner.set(l.name, { index: idx, type: t });
    }
    out.push(...this.expr(b.result, inner, ctx));
    return out;
  }

  expr(e, scope, ctx) {
    const t = valType(e.ty);
    if (t === undefined) throw new Unsupported(`values of type ${typeStr(e.ty)}`, e.pos);
    switch (e.k) {
      case 'int': return op.i64(e.v);
      case 'bool': return op.i32(e.v ? 1 : 0);
      case 'str': return op.i32(this.str(e.v));
      case 'unit': return [];
      case 'var': {
        const v = scope.get(e.name);
        if (v) return v.type === null ? [] : op.localGet(v.index);
        if (this.variantOf.has(e.name)) return op.i32(this.tagConst(this.variantOf.get(e.name).index)); // 欄の無い case
        throw new Unsupported(`'${e.name}' as a value`, e.pos);
      }
      case 'un':
        return e.op === 'not'
          ? [...this.expr(e.arg, scope, ctx), ...op.i32Eqz]
          : [...op.i64(0), ...this.expr(e.arg, scope, ctx), ...op.i64Sub];
      case 'if': {
        return [...this.expr(e.cond, scope, ctx), ...op.if(t ?? EMPTY), ...this.block(e.thenB, scope, ctx), ...op.else, ...this.block(e.elseB, scope, ctx), ...op.end];
      }
      case 'list': {
        const elem = prune(e.ty).of;
        const p = ctx.local(I32);
        return [
          ...op.i32(8 + 8 * e.items.length), ...op.call(this.h.alloc), ...op.localTee(p), ...op.i32(e.items.length), ...op.i32Store(0),
          ...e.items.flatMap((x, i) => this.storeAt(elem, op.localGet(p), this.expr(x, scope, ctx), 8 + 8 * i, x.pos)),
          ...op.localGet(p),
        ];
      }
      case 'match': return this.match(e, t, scope, ctx);
      case 'bin': return this.binary(e, scope, ctx);
      case 'call': return this.call(e, scope, ctx);
      default: throw new Unsupported(`'${e.k}' expressions`, e.pos);
    }
  }

  // match：case の番号を見て、その case の欄を名前に入れてから値を作る。漏れは検査で無いと確かめ終わっている
  match(e, t, scope, ctx) {
    const st = prune(e.subject.ty);
    const s = ctx.local(I32);
    const arm = (a) => {
      const { variant } = this.variantOf.get(a.variant);
      const fts = this.fieldTypes(st, a.variant);
      const inner = new Map(scope);
      const out = [];
      for (const b of a.binds) {
        if (b.name === '_') continue;
        const j = variant.fields.findIndex((x) => x.name === b.field);
        const vt = this.slot(fts[j], b.pos);
        if (vt === null) { inner.set(b.name, { index: -1, type: null }); continue; }
        const idx = ctx.local(vt);
        out.push(...this.loadAt(fts[j], op.localGet(s), 8 + 8 * j, b.pos), ...op.localSet(idx));
        inner.set(b.name, { index: idx, type: vt });
      }
      return [...out, ...this.expr(a.value, inner, ctx)];
    };
    const arms = e.arms;
    const chain = (i) => (i === arms.length - 1
      ? arm(arms[i])
      : [...op.localGet(s), ...op.i32Load(0), ...op.i32(this.variantOf.get(arms[i].variant).index), ...op.i32Eq,
        ...op.if(t ?? EMPTY), ...arm(arms[i]), ...op.else, ...chain(i + 1), ...op.end]);
    return [...this.expr(e.subject, scope, ctx), ...op.localSet(s), ...chain(0)];
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
        const eq = this.eqCode(e.left.ty, L(), R(), e.pos);
        return e.op === '==' ? eq : [...eq, ...op.i32Eqz];
      }
      case '++':
        if (lt === 'Str') return [...L(), ...R(), ...op.call(this.h.concat)];
        return [...L(), ...R(), ...op.call(this.listConcat())];
      default: throw new Unsupported(`the operator ${e.op}`, e.pos);
    }
  }

  call(e, scope, ctx) {
    const arg = (n) => e.args.find((a) => a.name === n);
    const A = (n) => this.expr(arg(n).value, scope, ctx);
    if (this.fnIndex.has(e.name)) {
      const f = this.program.fns.find((x) => x.name === e.name);
      const out = [];
      for (const prm of f.params) {
        if (CAPS.includes(prm.type.k)) continue;
        out.push(...A(prm.name));
      }
      return [...out, ...op.call(this.fnIndex.get(e.name))];
    }
    if (this.variantOf.has(e.name)) { // case を作る
      const { variant } = this.variantOf.get(e.name);
      return this.mkData(prune(e.ty), e.name, variant.fields.map((x) => A(x.name)), ctx, e.pos);
    }
    if (!SUPPORTED_BUILTINS.includes(e.name)) throw new Unsupported(`the built-in function ${e.name}`, e.pos);
    if (LIST_BUILTINS.includes(e.name)) return this.listBuiltin(e, A, arg, scope, ctx);
    if (TEXT_BUILTINS.includes(e.name)) return this.textBuiltin(e, A, arg, ctx);
    if (DICT_BUILTINS.includes(e.name)) return this.dictBuiltin(e, A, arg, ctx);
    switch (e.name) {
      case 'str_len': return [...A('text'), ...op.call(this.h.strlen)];
      case 'trim': return [...A('text'), ...op.call(this.trimFn())];
      case 'parse_int': return [...A('text'), ...op.call(this.parseIntFn())];
      case 'slice': {
        const [t, a, b] = [ctx.local(I32), ctx.local(I32), ctx.local(I32)];
        const [from, to] = [ctx.local(I64), ctx.local(I64)];
        return [
          ...A('text'), ...op.localSet(t), ...A('from'), ...op.localSet(from), ...A('to'), ...op.localSet(to),
          ...op.localGet(t), ...op.localGet(from), ...op.call(this.cpOffsetFn()), ...op.localSet(a),
          ...op.localGet(t), ...op.localGet(to), ...op.call(this.cpOffsetFn()), ...op.localSet(b),
          ...op.localGet(a), ...op.i32(0), ...op.i32LtS, ...op.localGet(b), ...op.i32(0), ...op.i32LtS, ...op.i32Or, ...op.localGet(from), ...op.localGet(to), ...op.i64GtS, ...op.i32Or,
          ...op.if(EMPTY), ...this.failAt('R506', 'slice is out of range', e.pos), ...op.end,
          ...op.localGet(t), ...op.localGet(a), ...op.localGet(b), ...op.call(this.sliceFn()),
        ];
      }
      case 'code_of': {
        const c = ctx.local(I64);
        return [...A('char'), ...op.call(this.codeOfFn()), ...op.localTee(c), ...op.i64(0), ...op.i64LtS,
          ...op.if(EMPTY), ...this.failAt('R506', 'code_of needs exactly one character', e.pos), ...op.end, ...op.localGet(c)];
      }
      case 'char_of': {
        const c = ctx.local(I64);
        return [
          ...A('code'), ...op.localTee(c), ...op.i64(0), ...op.i64LtS, ...op.localGet(c), ...op.i64(0x10ffff), ...op.i64GtS, ...op.i32Or,
          ...op.localGet(c), ...op.i64(0xd800), ...op.i64GeS, ...op.localGet(c), ...op.i64(0xdfff), ...op.i64LeS, ...op.i32And, ...op.i32Or,
          ...op.if(EMPTY), ...this.failAt('R506', 'not a character code', e.pos), ...op.end,
          ...op.localGet(c), ...op.call(this.charOfFn()),
        ];
      }
      case 'read_text': {
        const r = ctx.local(I32);
        return [
          ...A('path'), ...op.call(this.readTextFn()), ...op.localTee(r), ...op.i32Eqz,
          ...op.if(EMPTY), ...this.failAt('R507', 'the path is not inside the folder', e.pos), ...op.end,
          ...op.localGet(r), ...op.i32(1), ...op.i32Eq,
          ...op.if(EMPTY), ...this.failAt('R507', 'the path points outside the folder (through a link)', e.pos), ...op.end,
          ...op.localGet(r),
        ];
      }
      default: {
        const v = arg('value').value;
        const s = this.showCode(v.ty, this.expr(v, scope, ctx), false, v.pos);
        if (e.name === 'to_str') return s;
        return [...op.i32(1), ...s, ...op.i32(1), ...op.call(this.h.write)]; // print
      }
    }
  }

  // ---- メモリの欄 ----
  // 欄に置くときの型。null は置かない（Unit と、まだ決まらない型。決まらないのは空のリストなど、値が1つも無いときだけ）
  slot(t, pos) {
    t = prune(t);
    if (t.k === 'Var') return null;
    const v = valType(t);
    if (v === undefined) throw new Unsupported(`values of type ${typeStr(t)}`, pos);
    return v;
  }

  loadAt(t, addr, off, pos) {
    const s = this.slot(t, pos);
    if (s === null) return [];
    return [...addr, ...(s === I64 ? op.i64Load(off) : op.i32Load(off))];
  }

  storeAt(t, addr, value, off, pos) {
    const s = this.slot(t, pos);
    if (s === null) return value; // Unit は置かない（式は動かす）
    return [...addr, ...value, ...(s === I64 ? op.i64Store(off) : op.i32Store(off))];
  }

  // 型の値の、case ごとの欄の型（Option[T] の T などを置きかえたもの）
  fieldTypes(t, vname) {
    const { decl, variant } = this.variantOf.get(vname);
    const subst = Object.fromEntries((decl.params ?? []).map((p, i) => [p, t.args?.[i] ?? { k: 'Var' }]));
    return variant.fields.map((f) => fromAst(f.type, subst) ?? { k: 'Var' });
  }

  // 欄の無い case は、データの節に1つだけ置いて使い回す
  tagConst(index) {
    if (this.tagConsts.has(index)) return this.tagConsts.get(index);
    while (this.dataEnd % 8) { this.data.push(0); this.dataEnd++; }
    const at = this.dataEnd;
    this.data.push(index & 0xff, (index >> 8) & 0xff, 0, 0, 0, 0, 0, 0);
    this.dataEnd += 8;
    this.tagConsts.set(index, at);
    return at;
  }

  mkData(t, vname, fields, ctx, pos) {
    const { index } = this.variantOf.get(vname);
    if (!fields.length) return op.i32(this.tagConst(index));
    const fts = this.fieldTypes(t, vname);
    const p = ctx.local(I32);
    return [
      ...op.i32(8 + 8 * fields.length), ...op.call(this.h.alloc), ...op.localTee(p), ...op.i32(index), ...op.i32Store(0),
      ...fields.flatMap((code, j) => this.storeAt(fts[j], op.localGet(p), code, 8 + 8 * j, pos)),
      ...op.localGet(p),
    ];
  }

  // 型ごとの手伝いの関数を作る（同じ型には1つだけ）。build(局所変数を足す関数) が本体を返す
  gen(key, params, results, build) {
    if (this.genIdx.has(key)) return this.genIdx.get(key);
    const idx = this.genBase + this.gens.length;
    this.genIdx.set(key, idx);
    const f = { params, results, locals: [], body: null };
    this.gens.push(f);
    const local = (t) => { f.locals.push(t); return params.length + f.locals.length - 1; };
    f.body = [...build(local), ...op.end];
    return idx;
  }

  // ---- 表示（print・to_str と同じ形。入れ子の Str は "" でくくる） ----
  showCode(t, code, nested, pos) {
    t = prune(t);
    switch (t.k) {
      case 'Str': return nested ? [...code, ...op.call(this.quoteFn())] : code;
      case 'Html': return code; // 入れ子でもそのまま
      case 'Sql': return [...code, ...op.call(this.showSqlFn())];
      case 'Int': return [...code, ...op.call(this.h.itoa)];
      case 'Bool': return [...code, ...op.if(I32), ...op.i32(this.str('true')), ...op.else, ...op.i32(this.str('false')), ...op.end];
      case 'Unit': case 'Var': return [...code, ...op.i32(this.str('()'))];
      case 'List': return [...code, ...op.call(this.showListFn(t, pos))];
      case 'Dict': return [...code, ...op.call(this.showDictFn(t, pos))];
      case 'Data': return [...code, ...op.call(this.showDataFn(t, pos))];
      default: throw new Unsupported(`showing values of type ${typeStr(t)}`, pos);
    }
  }

  showListFn(t, pos) {
    return this.gen(`show ${typeStr(t)}`, [I32], [I32], (local) => {
      const [n, i, acc] = [local(I32), local(I32), local(I32)];
      const cat = (code) => [...op.localGet(acc), ...code, ...op.call(this.h.concat), ...op.localSet(acc)];
      return [
        ...op.i32(this.str('[')), ...op.localSet(acc), ...op.localGet(0), ...op.i32Load(0), ...op.localSet(n),
        ...forEach(i, n, [
          ...op.localGet(i), ...op.if(EMPTY), ...cat(op.i32(this.str(', '))), ...op.end,
          ...cat(this.showCode(t.of, this.loadAt(t.of, elemAddr(0, i), 8, pos), true, pos)),
        ]),
        ...cat(op.i32(this.str(']'))), ...op.localGet(acc),
      ];
    });
  }

  showDataFn(t, pos) {
    return this.gen(`show ${typeStr(t)}`, [I32], [I32], (local) => {
      const acc = local(I32);
      const cat = (code) => [...op.localGet(acc), ...code, ...op.call(this.h.concat), ...op.localSet(acc)];
      const out = [];
      for (const v of this.decls.get(t.name).variants) {
        const { index } = this.variantOf.get(v.name);
        const fts = this.fieldTypes(t, v.name);
        out.push(...op.localGet(0), ...op.i32Load(0), ...op.i32(index), ...op.i32Eq, ...op.if(EMPTY));
        if (!v.fields.length) out.push(...op.i32(this.str(v.name)), ...op.return);
        else {
          out.push(...op.i32(this.str(`${v.name}(`)), ...op.localSet(acc));
          v.fields.forEach((fl, j) => {
            out.push(...cat(op.i32(this.str(`${j ? ', ' : ''}${fl.name}: `))));
            out.push(...cat(this.showCode(fts[j], this.loadAt(fts[j], op.localGet(0), 8 + 8 * j, pos), true, pos)));
          });
          out.push(...cat(op.i32(this.str(')'))), ...op.localGet(acc), ...op.return);
        }
        out.push(...op.end);
      }
      return [...out, ...op.unreachable];
    });
  }

  // JSON.stringify と同じ形で "" でくくる（" と \ と制御文字を置きかえる）
  quoteFn() {
    return this.gen('quote', [I32], [I32], (local) => {
      const [n, i, out, w, b] = [local(I32), local(I32), local(I32), local(I32), local(I32)];
      const put = (code) => [...op.localGet(w), ...code, ...op.i32Store8(0), ...op.localGet(w), ...op.i32(1), ...op.i32Add, ...op.localSet(w)];
      const hex = (code) => [...code, ...op.localTee(b), ...op.i32(10), ...op.i32LtU, ...op.if(I32), ...op.localGet(b), ...op.i32(48), ...op.i32Add, ...op.else, ...op.localGet(b), ...op.i32(87), ...op.i32Add, ...op.end];
      const esc = (c, ch) => [...op.localGet(b), ...op.i32(c), ...op.i32Eq, ...op.if(EMPTY), ...put(op.i32(92)), ...put(op.i32(ch.charCodeAt(0))), ...op.br(2), ...op.end];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localSet(n),
        ...op.localGet(n), ...op.i32(6), ...op.i32Mul, ...op.i32(6), ...op.i32Add, ...op.call(this.h.alloc), ...op.localSet(out),
        ...op.localGet(out), ...op.i32(4), ...op.i32Add, ...op.localSet(w),
        ...put(op.i32(34)),
        ...forEach(i, n, [
          ...op.block(EMPTY),
          ...op.localGet(0), ...op.localGet(i), ...op.i32Add, ...op.i32Load8u(4), ...op.localSet(b),
          // ここから br(2) はこの block の外（次の文字へ）
          ...op.localGet(b), ...op.i32(34), ...op.i32Eq, ...op.if(EMPTY), ...put(op.i32(92)), ...put(op.i32(34)), ...op.br(1), ...op.end,
          ...op.localGet(b), ...op.i32(92), ...op.i32Eq, ...op.if(EMPTY), ...put(op.i32(92)), ...put(op.i32(92)), ...op.br(1), ...op.end,
          ...op.localGet(b), ...op.i32(32), ...op.i32GeU, ...op.if(EMPTY), ...put(op.localGet(b)), ...op.br(1), ...op.end,
          ...op.block(EMPTY),
          ...esc(8, 'b'), ...esc(9, 't'), ...esc(10, 'n'), ...esc(12, 'f'), ...esc(13, 'r'),
          ...put(op.i32(92)), ...put(op.i32(117)), ...put(op.i32(48)), ...put(op.i32(48)),
          ...op.localGet(0), ...op.localGet(i), ...op.i32Add, ...op.i32Load8u(4), ...op.localSet(b),
          ...put(hex([...op.localGet(b), ...op.i32(4), ...op.i32ShrU])),
          ...op.localGet(0), ...op.localGet(i), ...op.i32Add, ...op.i32Load8u(4), ...op.localSet(b),
          ...put(hex([...op.localGet(b), ...op.i32(15), ...op.i32And])),
          ...op.end,
          ...op.end,
        ]),
        ...put(op.i32(34)),
        ...op.localGet(out), ...op.localGet(w), ...op.localGet(out), ...op.i32Sub, ...op.i32(4), ...op.i32Sub, ...op.i32Store(0),
        ...op.localGet(out),
      ];
    });
  }

  // ---- 比べる（== は中身まで） ----
  eqCode(t, a, b, pos) {
    t = prune(t);
    switch (t.k) {
      case 'Int': return [...a, ...b, ...op.i64Eq];
      case 'Bool': return [...a, ...b, ...op.i32Eq];
      case 'Str': return [...a, ...b, ...op.call(this.h.streq)];
      case 'Html': case 'Sql': return [...a, ...b, ...op.i32Eq]; // インタプリタと同じく、同じ値（作ったもの）どうしだけが等しい
      case 'Unit': case 'Var': return [...a, ...b, ...op.i32(1)];
      case 'List': return [...a, ...b, ...op.call(this.eqListFn(t, pos))];
      case 'Dict': return [...a, ...b, ...op.call(this.eqDictFn(t, pos))];
      case 'Data': return [...a, ...b, ...op.call(this.eqDataFn(t, pos))];
      default: throw new Unsupported(`comparing values of type ${typeStr(t)}`, pos);
    }
  }

  eqListFn(t, pos) {
    return this.gen(`eq ${typeStr(t)}`, [I32, I32], [I32], (local) => {
      const [n, i] = [local(I32), local(I32)];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localTee(n), ...op.localGet(1), ...op.i32Load(0), ...op.i32Ne, ...op.if(EMPTY), ...op.i32(0), ...op.return, ...op.end,
        ...forEach(i, n, [
          ...this.eqCode(t.of, this.loadAt(t.of, elemAddr(0, i), 8, pos), this.loadAt(t.of, elemAddr(1, i), 8, pos), pos),
          ...op.i32Eqz, ...op.if(EMPTY), ...op.i32(0), ...op.return, ...op.end,
        ]),
        ...op.i32(1),
      ];
    });
  }

  eqDataFn(t, pos) {
    return this.gen(`eq ${typeStr(t)}`, [I32, I32], [I32], () => {
      const out = [...op.localGet(0), ...op.i32Load(0), ...op.localGet(1), ...op.i32Load(0), ...op.i32Ne, ...op.if(EMPTY), ...op.i32(0), ...op.return, ...op.end];
      for (const v of this.decls.get(t.name).variants) {
        if (!v.fields.length) continue;
        const fts = this.fieldTypes(t, v.name);
        out.push(...op.localGet(0), ...op.i32Load(0), ...op.i32(this.variantOf.get(v.name).index), ...op.i32Eq, ...op.if(EMPTY));
        fts.forEach((ft, j) => out.push(
          ...this.eqCode(ft, this.loadAt(ft, op.localGet(0), 8 + 8 * j, pos), this.loadAt(ft, op.localGet(1), 8 + 8 * j, pos), pos),
          ...op.i32Eqz, ...op.if(EMPTY), ...op.i32(0), ...op.return, ...op.end,
        ));
        out.push(...op.end);
      }
      return [...out, ...op.i32(1)];
    });
  }

  // ---- リスト ----
  // 新しいリスト（長さ n）を作り、その場所を局所変数 p に入れる
  newList(n, p) {
    return [...op.localGet(n), ...op.i32(8), ...op.i32Mul, ...op.i32(8), ...op.i32Add, ...op.call(this.h.alloc), ...op.localTee(p), ...op.localGet(n), ...op.i32Store(0)];
  }

  // 要素を n 個写す（どれも 8 バイト）
  copyElems(dst, dstAt, src, srcAt, n) {
    return [
      ...op.localGet(dst), ...op.i32(8), ...op.i32Add, ...dstAt, ...op.i32(8), ...op.i32Mul, ...op.i32Add,
      ...op.localGet(src), ...op.i32(8), ...op.i32Add, ...srcAt, ...op.i32(8), ...op.i32Mul, ...op.i32Add,
      ...n, ...op.i32(8), ...op.i32Mul, ...op.memoryCopy,
    ];
  }

  listConcat() {
    return this.gen('list ++', [I32, I32], [I32], (local) => {
      const [n, p] = [local(I32), local(I32)];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localGet(1), ...op.i32Load(0), ...op.i32Add, ...op.localSet(n),
        ...this.newList(n, p),
        ...this.copyElems(p, op.i32(0), 0, op.i32(0), [...op.localGet(0), ...op.i32Load(0)]),
        ...this.copyElems(p, [...op.localGet(0), ...op.i32Load(0)], 1, op.i32(0), [...op.localGet(1), ...op.i32Load(0)]),
        ...op.localGet(p),
      ];
    });
  }

  // func: に渡す関数（いちばん外の関数の名前だけ）
  fnRef(v) {
    if (v.k === 'var' && this.fnIndex.has(v.name)) return this.fnIndex.get(v.name);
    throw new Unsupported('passing this as a function', v.pos);
  }

  listBuiltin(e, A, arg, scope, ctx) {
    const pos = e.pos;
    const lt = arg('list') ? prune(arg('list').value.ty) : null;
    const el = lt?.of;
    const L = ctx.local(I32);
    const n = ctx.local(I32);
    const i = ctx.local(I32);
    const setList = arg('list') ? [...A('list'), ...op.localTee(L), ...op.i32Load(0), ...op.localSet(n)] : [];
    const item = () => this.loadAt(el, elemAddr(L, i), 8, pos);
    const callF = (args) => [...args, ...op.call(this.fnRef(arg('func').value))];
    const optT = () => prune(e.ty);
    switch (e.name) {
      case 'len': return [...A('list'), ...op.i32Load(0), ...op.i64ExtendI32U];
      case 'get': case 'at': {
        const ix = ctx.local(I64);
        const out = [...op.localGet(ix), ...op.i64(0), ...op.i64LtS, ...op.localGet(ix), ...op.localGet(n), ...op.i64ExtendI32U, ...op.i64GeS, ...op.i32Or];
        const val = this.loadAt(el, [...op.localGet(L), ...op.localGet(ix), ...op.i32WrapI64, ...op.i32(8), ...op.i32Mul, ...op.i32Add], 8, pos);
        if (e.name === 'get') {
          return [...setList, ...A('index'), ...op.localSet(ix), ...out, ...op.if(EMPTY), ...this.failAt('R506', 'index is out of range', pos), ...op.end, ...val];
        }
        return [...setList, ...A('index'), ...op.localSet(ix), ...out,
          ...op.if(I32), ...this.mkData(optT(), 'None', [], ctx, pos), ...op.else, ...this.mkData(optT(), 'Some', [val], ctx, pos), ...op.end];
      }
      case 'range': {
        const [fr, d, p] = [ctx.local(I64), ctx.local(I64), ctx.local(I32)];
        return [
          ...A('from'), ...op.localSet(fr), ...A('to'), ...op.localGet(fr), ...op.i64Sub, ...op.localTee(d), ...op.i64(1000000), ...op.i64GtS,
          ...op.if(EMPTY), ...this.failAt('R504', 'range is too large', pos), ...op.end,
          ...op.localGet(d), ...op.i64(0), ...op.i64LtS, ...op.if(I32), ...op.i32(0), ...op.else, ...op.localGet(d), ...op.i32WrapI64, ...op.end, ...op.localSet(n),
          ...this.newList(n, p),
          ...forEach(i, n, [...elemAddr(p, i), ...op.localGet(fr), ...op.localGet(i), ...op.i64ExtendI32U, ...op.i64Add, ...op.i64Store(8)]),
          ...op.localGet(p),
        ];
      }
      case 'append': {
        const [p, m] = [ctx.local(I32), ctx.local(I32)];
        return [
          ...setList, ...op.localGet(n), ...op.i32(1), ...op.i32Add, ...op.localSet(m), ...this.newList(m, p),
          ...this.copyElems(p, op.i32(0), L, op.i32(0), op.localGet(n)),
          ...this.storeAt(el, [...op.localGet(p), ...op.localGet(n), ...op.i32(8), ...op.i32Mul, ...op.i32Add], A('item'), 8, pos),
          ...op.localGet(p),
        ];
      }
      case 'map': {
        const p = ctx.local(I32);
        const out = prune(e.ty).of;
        return [...setList, ...this.newList(n, p), ...forEach(i, n, this.storeAt(out, elemAddr(p, i), callF(item()), 8, pos)), ...op.localGet(p)];
      }
      case 'filter': {
        const [p, k] = [ctx.local(I32), ctx.local(I32)];
        return [
          ...setList, ...this.newList(n, p), ...op.i32(0), ...op.localSet(k),
          ...forEach(i, n, [
            ...callF(item()), ...op.if(EMPTY),
            ...this.storeAt(el, elemAddr(p, k), item(), 8, pos),
            ...op.localGet(k), ...op.i32(1), ...op.i32Add, ...op.localSet(k),
            ...op.end,
          ]),
          ...op.localGet(p), ...op.localGet(k), ...op.i32Store(0), ...op.localGet(p),
        ];
      }
      case 'fold': {
        const at = this.slot(e.ty, pos);
        if (at === null) return [...setList, ...A('init'), ...forEach(i, n, callF(item()))]; // 結果が Unit：acc は置かない
        const acc = ctx.local(at);
        return [...setList, ...A('init'), ...op.localSet(acc), ...forEach(i, n, [...callF([...op.localGet(acc), ...item()]), ...op.localSet(acc)]), ...op.localGet(acc)];
      }
      case 'find': case 'any': case 'all': {
        // block(結果) > block > loop > if の中から、結果の block へは br(3)
        const hit = e.name === 'find' ? this.mkData(optT(), 'Some', [item()], ctx, pos) : op.i32(e.name === 'any' ? 1 : 0);
        const miss = e.name === 'find' ? this.mkData(optT(), 'None', [], ctx, pos) : op.i32(e.name === 'any' ? 0 : 1);
        const test = e.name === 'all' ? [...callF(item()), ...op.i32Eqz] : callF(item());
        return [...setList, ...op.block(I32), ...forEach(i, n, [...test, ...op.if(EMPTY), ...hit, ...op.br(3), ...op.end]), ...miss, ...op.end];
      }
      case 'reverse': {
        const p = ctx.local(I32);
        return [
          ...setList, ...this.newList(n, p),
          ...forEach(i, n, this.storeAt(el, elemAddr(p, i), this.loadAt(el, [...op.localGet(L), ...op.localGet(n), ...op.i32(1), ...op.i32Sub, ...op.localGet(i), ...op.i32Sub, ...op.i32(8), ...op.i32Mul, ...op.i32Add], 8, pos), 8, pos)),
          ...op.localGet(p),
        ];
      }
      case 'take': case 'drop': {
        const [c, k, p] = [ctx.local(I64), ctx.local(I32), ctx.local(I32)];
        // k = min(count, len)
        const clamp = [...op.localGet(c), ...op.localGet(n), ...op.i64ExtendI32U, ...op.i64GtS, ...op.if(I32), ...op.localGet(n), ...op.else, ...op.localGet(c), ...op.i32WrapI64, ...op.end, ...op.localSet(k)];
        const m = ctx.local(I32);
        const body = e.name === 'take'
          ? [...op.localGet(k), ...op.localSet(m), ...this.newList(m, p), ...this.copyElems(p, op.i32(0), L, op.i32(0), op.localGet(m))]
          : [...op.localGet(n), ...op.localGet(k), ...op.i32Sub, ...op.localSet(m), ...this.newList(m, p), ...this.copyElems(p, op.i32(0), L, op.localGet(k), op.localGet(m))];
        return [
          ...setList, ...A('count'), ...op.localTee(c), ...op.i64(0), ...op.i64LtS, ...op.if(EMPTY), ...this.failAt('R506', 'count is negative', pos), ...op.end,
          ...clamp, ...body, ...op.localGet(p),
        ];
      }
      case 'sort': return [...A('list'), ...op.call(this.sortFn())];
      case 'sum': {
        const acc = ctx.local(I64);
        return [...setList, ...op.i64(0), ...op.localSet(acc), ...forEach(i, n, [...op.localGet(acc), ...item(), ...op.i64Add, ...op.call(this.h.chk), ...op.localSet(acc)]), ...op.localGet(acc)];
      }
      case 'max': case 'min': {
        const [acc, x] = [ctx.local(I64), ctx.local(I64)];
        const better = e.name === 'max' ? op.i64GtS : op.i64LtS;
        return [
          ...setList, ...op.localGet(n), ...op.i32Eqz,
          ...op.if(I32), ...this.mkData(optT(), 'None', [], ctx, pos),
          ...op.else,
          ...op.localGet(L), ...op.i64Load(8), ...op.localSet(acc),
          ...forEach(i, n, [...item(), ...op.localTee(x), ...op.localGet(acc), ...better, ...op.if(EMPTY), ...op.localGet(x), ...op.localSet(acc), ...op.end]),
          ...this.mkData(optT(), 'Some', [op.localGet(acc)], ctx, pos),
          ...op.end,
        ];
      }
      default: throw new Unsupported(`the built-in function ${e.name}`, pos);
    }
  }

  // ---- 辞書 ----
  // 配置：[数 u32][pad][鍵 Str の場所 8 バイト][値 8 バイト]... 鍵のバイト順（= コードポイント順）に並べ、鍵は重ならない。
  // 値はどの型でも 8 バイトの欄なので、入れる・写すのは型によらない（i64 のまま運ぶ）。表示と == だけ型ごとに作る
  showDictFn(t, pos) {
    return this.gen(`show ${typeStr(t)}`, [I32], [I32], (local) => {
      const [n, i, acc] = [local(I32), local(I32), local(I32)];
      const cat = (code) => [...op.localGet(acc), ...code, ...op.call(this.h.concat), ...op.localSet(acc)];
      return [
        ...op.i32(this.str('{')), ...op.localSet(acc), ...op.localGet(0), ...op.i32Load(0), ...op.localSet(n),
        ...forEach(i, n, [
          ...op.localGet(i), ...op.if(EMPTY), ...cat(op.i32(this.str(', '))), ...op.end,
          ...cat([...entryAddr(0, i), ...op.i32Load(8), ...op.call(this.quoteFn())]),
          ...cat(op.i32(this.str(': '))),
          ...cat(this.showCode(t.of, this.loadAt(t.of, entryAddr(0, i), 16, pos), true, pos)),
        ]),
        ...cat(op.i32(this.str('}'))), ...op.localGet(acc),
      ];
    });
  }

  eqDictFn(t, pos) {
    return this.gen(`eq ${typeStr(t)}`, [I32, I32], [I32], (local) => {
      const [n, i] = [local(I32), local(I32)];
      const no = [...op.i32Eqz, ...op.if(EMPTY), ...op.i32(0), ...op.return, ...op.end];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localTee(n), ...op.localGet(1), ...op.i32Load(0), ...op.i32Ne, ...op.if(EMPTY), ...op.i32(0), ...op.return, ...op.end,
        ...forEach(i, n, [
          ...entryAddr(0, i), ...op.i32Load(8), ...entryAddr(1, i), ...op.i32Load(8), ...op.call(this.h.streq), ...no,
          ...this.eqCode(t.of, this.loadAt(t.of, entryAddr(0, i), 16, pos), this.loadAt(t.of, entryAddr(1, i), 16, pos), pos), ...no,
        ]),
        ...op.i32(1),
      ];
    });
  }

  // 文字のバイト順の比べ：a < b なら -1、同じなら 0、a > b なら 1
  strCmpFn() {
    return this.gen('str cmp', [I32, I32], [I32], (local) => {
      const [la, lb, m, i, x, y] = [local(I32), local(I32), local(I32), local(I32), local(I32), local(I32)];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localSet(la), ...op.localGet(1), ...op.i32Load(0), ...op.localSet(lb),
        ...op.localGet(la), ...op.localGet(lb), ...op.localGet(la), ...op.localGet(lb), ...op.i32LtU, ...op.select, ...op.localSet(m),
        ...forEach(i, m, [
          ...op.localGet(0), ...op.localGet(i), ...op.i32Add, ...op.i32Load8u(4), ...op.localTee(x),
          ...op.localGet(1), ...op.localGet(i), ...op.i32Add, ...op.i32Load8u(4), ...op.localTee(y), ...op.i32Ne,
          ...op.if(EMPTY), ...op.i32(-1), ...op.i32(1), ...op.localGet(x), ...op.localGet(y), ...op.i32LtU, ...op.select, ...op.return, ...op.end,
        ]),
        ...op.localGet(la), ...op.localGet(lb), ...op.i32LtU, ...op.if(I32), ...op.i32(-1), ...op.else, ...op.localGet(la), ...op.localGet(lb), ...op.i32GtU, ...op.end,
      ];
    });
  }

  // 鍵を探す（二分探索）。あればその番号、無ければ -(入れる場所) - 1
  dictFindFn() {
    return this.gen('dict find', [I32, I32], [I32], (local) => {
      const [lo, hi, mid, c] = [local(I32), local(I32), local(I32), local(I32)];
      return [
        ...op.i32(0), ...op.localSet(lo), ...op.localGet(0), ...op.i32Load(0), ...op.localSet(hi),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(lo), ...op.localGet(hi), ...op.i32GeU, ...op.brIf(1),
        ...op.localGet(lo), ...op.localGet(hi), ...op.i32Add, ...op.i32(1), ...op.i32ShrU, ...op.localSet(mid),
        ...entryAddr(0, mid), ...op.i32Load(8), ...op.localGet(1), ...op.call(this.strCmpFn()), ...op.localTee(c), ...op.i32Eqz,
        ...op.if(EMPTY), ...op.localGet(mid), ...op.return, ...op.end,
        ...op.localGet(c), ...op.i32(0), ...op.i32LtS,
        ...op.if(EMPTY), ...op.localGet(mid), ...op.i32(1), ...op.i32Add, ...op.localSet(lo), ...op.else, ...op.localGet(mid), ...op.localSet(hi), ...op.end,
        ...op.br(0), ...op.end, ...op.end,
        ...op.i32(-1), ...op.localGet(lo), ...op.i32Sub,
      ];
    });
  }

  // 新しい辞書（数 n）を作り、その場所を局所変数 p に入れる
  newDict(n, p) {
    return [...op.localGet(n), ...op.i32(16), ...op.i32Mul, ...op.i32(8), ...op.i32Add, ...op.call(this.h.alloc), ...op.localTee(p), ...op.localGet(n), ...op.i32Store(0)];
  }

  // 組を写す（dst の dstAt 番めへ、src の srcAt 番めから cnt 組）
  copyEntries(dst, dstAt, src, srcAt, cnt) {
    return [
      ...op.localGet(dst), ...op.i32(8), ...op.i32Add, ...dstAt, ...op.i32(16), ...op.i32Mul, ...op.i32Add,
      ...op.localGet(src), ...op.i32(8), ...op.i32Add, ...srcAt, ...op.i32(16), ...op.i32Mul, ...op.i32Add,
      ...cnt, ...op.i32(16), ...op.i32Mul, ...op.memoryCopy,
    ];
  }

  // put(d, key, 値の 8 バイト) -> 新しい辞書
  dictPutFn() {
    return this.gen('dict put', [I32, I32, I64], [I32], (local) => {
      const [f, n, m, p, at] = [local(I32), local(I32), local(I32), local(I32), local(I32)];
      const L = (x) => op.localGet(x);
      return [
        ...L(0), ...L(1), ...op.call(this.dictFindFn()), ...op.localSet(f), ...L(0), ...op.i32Load(0), ...op.localSet(n),
        ...L(f), ...op.i32(0), ...op.i32GeS,
        ...op.if(EMPTY),
        ...this.newDict(n, p), ...this.copyEntries(p, op.i32(0), 0, op.i32(0), L(n)), ...L(f), ...op.localSet(at),
        ...op.else,
        ...op.i32(-1), ...L(f), ...op.i32Sub, ...op.localSet(at), ...L(n), ...op.i32(1), ...op.i32Add, ...op.localSet(m),
        ...this.newDict(m, p),
        ...this.copyEntries(p, op.i32(0), 0, op.i32(0), L(at)),
        ...this.copyEntries(p, [...L(at), ...op.i32(1), ...op.i32Add], 0, L(at), [...L(n), ...L(at), ...op.i32Sub]),
        ...op.end,
        ...entryAddr(p, at), ...L(1), ...op.i32Store(8), ...entryAddr(p, at), ...L(2), ...op.i64Store(16),
        ...L(p),
      ];
    });
  }

  dictRemoveFn() {
    return this.gen('dict remove', [I32, I32], [I32], (local) => {
      const [f, n, m, p] = [local(I32), local(I32), local(I32), local(I32)];
      const L = (x) => op.localGet(x);
      return [
        ...L(0), ...L(1), ...op.call(this.dictFindFn()), ...op.localTee(f), ...op.i32(0), ...op.i32LtS, ...op.if(EMPTY), ...L(0), ...op.return, ...op.end,
        ...L(0), ...op.i32Load(0), ...op.localTee(n), ...op.i32(1), ...op.i32Sub, ...op.localSet(m),
        ...this.newDict(m, p),
        ...this.copyEntries(p, op.i32(0), 0, op.i32(0), L(f)),
        ...this.copyEntries(p, L(f), 0, [...L(f), ...op.i32(1), ...op.i32Add], [...L(m), ...L(f), ...op.i32Sub]),
        ...L(p),
      ];
    });
  }

  // dict(keys, values)。数が合わなければ -1、鍵が重なれば 0
  dictOfFn() {
    return this.gen('dict of', [I32, I32], [I32], (local) => {
      const [n, i, c, p, f, at, k] = [local(I32), local(I32), local(I32), local(I32), local(I32), local(I32), local(I32)];
      const L = (x) => op.localGet(x);
      return [
        ...L(0), ...op.i32Load(0), ...op.localTee(n), ...L(1), ...op.i32Load(0), ...op.i32Ne, ...op.if(EMPTY), ...op.i32(-1), ...op.return, ...op.end,
        // n 組ぶんの場所を取り、数は 0 から数える
        ...this.newDict(n, p), ...op.localGet(p), ...op.i32(0), ...op.i32Store(0), ...op.i32(0), ...op.localSet(c),
        ...forEach(i, n, [
          ...elemAddr(0, i), ...op.i32Load(8), ...op.localSet(k),
          ...L(p), ...L(k), ...op.call(this.dictFindFn()), ...op.localTee(f), ...op.i32(0), ...op.i32GeS, ...op.if(EMPTY), ...op.i32(0), ...op.return, ...op.end,
          ...op.i32(-1), ...L(f), ...op.i32Sub, ...op.localSet(at),
          // 後ろを1つずらして場所を空ける（memory.copy は重なってもよい）
          ...this.copyEntries(p, [...L(at), ...op.i32(1), ...op.i32Add], p, L(at), [...L(c), ...L(at), ...op.i32Sub]),
          ...entryAddr(p, at), ...L(k), ...op.i32Store(8), ...entryAddr(p, at), ...elemAddr(1, i), ...op.i64Load(8), ...op.i64Store(16),
          ...L(c), ...op.i32(1), ...op.i32Add, ...op.localSet(c), ...L(p), ...L(c), ...op.i32Store(0),
        ]),
        ...L(p),
      ];
    });
  }

  // 値を 8 バイトの i64 にする（i32 の値は下の 4 バイトに。読むときは型どおり i32 で読む）
  bits(t, code, pos) {
    const s = this.slot(t, pos);
    if (s === null) return [...code, ...op.i64(0)];
    return s === I64 ? code : [...code, ...op.i64ExtendI32U];
  }

  dictBuiltin(e, A, arg, ctx) {
    const pos = e.pos;
    const dt = arg('dict') ? prune(arg('dict').value.ty) : null;
    const [d, n, i, p, f] = [ctx.local(I32), ctx.local(I32), ctx.local(I32), ctx.local(I32), ctx.local(I32)];
    switch (e.name) {
      case 'dict': {
        return [
          ...A('keys'), ...A('values'), ...op.call(this.dictOfFn()), ...op.localTee(p), ...op.i32(-1), ...op.i32Eq,
          ...op.if(EMPTY), ...this.failAt('R506', 'dict got a different number of keys and values', pos), ...op.end,
          ...op.localGet(p), ...op.i32Eqz, ...op.if(EMPTY), ...this.failAt('R506', 'a key appears twice in dict', pos), ...op.end,
          ...op.localGet(p),
        ];
      }
      case 'dict_put': return [...A('dict'), ...A('key'), ...this.bits(dt.of, A('value'), pos), ...op.call(this.dictPutFn())];
      case 'dict_remove': return [...A('dict'), ...A('key'), ...op.call(this.dictRemoveFn())];
      case 'dict_has': return [...A('dict'), ...A('key'), ...op.call(this.dictFindFn()), ...op.i32(0), ...op.i32GeS];
      case 'dict_size': return [...A('dict'), ...op.i32Load(0), ...op.i64ExtendI32U];
      case 'dict_get': {
        const ot = prune(e.ty);
        const some = this.variantOf.get('Some').index;
        return [
          ...A('dict'), ...op.localTee(d), ...A('key'), ...op.call(this.dictFindFn()), ...op.localTee(f), ...op.i32(0), ...op.i32LtS,
          ...op.if(I32), ...this.mkData(ot, 'None', [], ctx, pos),
          ...op.else,
          ...op.i32(16), ...op.call(this.h.alloc), ...op.localTee(p), ...op.i32(some), ...op.i32Store(0),
          ...op.localGet(p), ...entryAddr(d, f), ...op.i64Load(16), ...op.i64Store(8), ...op.localGet(p),
          ...op.end,
        ];
      }
      case 'dict_keys': case 'dict_values': {
        const off = e.name === 'dict_keys' ? 8 : 16;
        return [
          ...A('dict'), ...op.localTee(d), ...op.i32Load(0), ...op.localSet(n), ...this.newList(n, p),
          ...forEach(i, n, [...elemAddr(p, i), ...entryAddr(d, i), ...op.i64Load(off), ...op.i64Store(8)]),
          ...op.localGet(p),
        ];
      }
      default: throw new Unsupported(`the built-in function ${e.name}`, pos);
    }
  }

  // Int のリストを小さい順に並べた新しいリスト（下から上へのマージソート。O(n log n)）
  sortFn() {
    return this.gen('sort', [I32], [I32], (local) => {
      const [n, a, b, w, lo, mid, hi, i, j, k, t] = [local(I32), local(I32), local(I32), local(I32), local(I32), local(I32), local(I32), local(I32), local(I32), local(I32), local(I32)];
      const at = (base, idx) => [...op.localGet(base), ...op.localGet(idx), ...op.i32(8), ...op.i32Mul, ...op.i32Add];
      const min = (x, y) => [...x, ...y, ...x, ...y, ...op.i32LtU, ...op.select];
      const inc = (v) => [...op.localGet(v), ...op.i32(1), ...op.i32Add, ...op.localSet(v)];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localSet(n),
        ...this.newList(n, a), ...this.copyElems(a, op.i32(0), 0, op.i32(0), op.localGet(n)),
        ...this.newList(n, b),
        ...op.i32(1), ...op.localSet(w),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(w), ...op.localGet(n), ...op.i32GeU, ...op.brIf(1),
        ...op.i32(0), ...op.localSet(lo),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(lo), ...op.localGet(n), ...op.i32GeU, ...op.brIf(1),
        ...min([...op.localGet(lo), ...op.localGet(w), ...op.i32Add], op.localGet(n)), ...op.localSet(mid),
        ...min([...op.localGet(mid), ...op.localGet(w), ...op.i32Add], op.localGet(n)), ...op.localSet(hi),
        ...op.localGet(lo), ...op.localSet(i), ...op.localGet(mid), ...op.localSet(j), ...op.localGet(lo), ...op.localSet(k),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(k), ...op.localGet(hi), ...op.i32GeU, ...op.brIf(1),
        // 左から取るのは：右が尽きた、または（左が残っていて）左 <= 右
        ...op.localGet(j), ...op.localGet(hi), ...op.i32GeU,
        ...op.localGet(i), ...op.localGet(mid), ...op.i32LtU,
        ...op.if(I32), ...at(a, i), ...op.i64Load(8), ...at(a, j), ...op.i64Load(8), ...op.i64LeS, ...op.else, ...op.i32(0), ...op.end,
        ...op.i32Or, ...op.localGet(i), ...op.localGet(mid), ...op.i32LtU, ...op.i32And, ...op.localSet(t),
        ...at(b, k),
        ...op.localGet(t), ...op.if(I64), ...at(a, i), ...op.i64Load(8), ...inc(i), ...op.else, ...at(a, j), ...op.i64Load(8), ...inc(j), ...op.end,
        ...op.i64Store(8), ...inc(k),
        ...op.br(0), ...op.end, ...op.end,
        ...op.localGet(hi), ...op.localSet(lo),
        ...op.br(0), ...op.end, ...op.end,
        ...this.copyElems(a, op.i32(0), b, op.i32(0), op.localGet(n)),
        ...op.localGet(w), ...op.i32(1), ...op.i32Shl, ...op.localSet(w),
        ...op.br(0), ...op.end, ...op.end,
        ...op.localGet(a),
      ];
    });
  }

  // ---- 文字 ----
  // s の at バイト目から始まる文字が、JavaScript の trim が消す空白なら、そのバイト数。違えば 0
  wsAtFn() {
    return this.gen('ws at', [I32, I32], [I32], (local) => {
      const [b0, cp, len] = [local(I32), local(I32), local(I32)];
      const byte = (k) => [...op.localGet(0), ...op.localGet(1), ...op.i32Add, ...op.i32Load8u(4 + k)];
      const cont = (k) => [...byte(k), ...op.i32(63), ...op.i32And];
      const shl = (code, s) => [...code, ...op.i32(s), ...op.i32Shl];
      const isIn = (lo, hi) => [...op.localGet(cp), ...op.i32(lo), ...op.i32Sub, ...op.i32(hi - lo + 1), ...op.i32LtU];
      const is = (c) => [...op.localGet(cp), ...op.i32(c), ...op.i32Eq];
      const any = (tests) => tests.reduce((acc, x) => [...acc, ...x, ...op.i32Or]);
      return [
        ...byte(0), ...op.localTee(b0), ...op.i32(0x80), ...op.i32LtU,
        ...op.if(EMPTY), ...op.localGet(b0), ...op.localSet(cp), ...op.i32(1), ...op.localSet(len),
        ...op.else, ...op.localGet(b0), ...op.i32(0xe0), ...op.i32LtU,
        ...op.if(EMPTY), ...shl([...op.localGet(b0), ...op.i32(31), ...op.i32And], 6), ...cont(1), ...op.i32Or, ...op.localSet(cp), ...op.i32(2), ...op.localSet(len),
        ...op.else, ...op.localGet(b0), ...op.i32(0xf0), ...op.i32LtU,
        ...op.if(EMPTY), ...shl([...op.localGet(b0), ...op.i32(15), ...op.i32And], 12), ...shl(cont(1), 6), ...op.i32Or, ...cont(2), ...op.i32Or, ...op.localSet(cp), ...op.i32(3), ...op.localSet(len),
        ...op.else, ...op.i32(-1), ...op.localSet(cp), ...op.i32(4), ...op.localSet(len),
        ...op.end, ...op.end, ...op.end,
        ...any([isIn(9, 13), is(0x20), is(0xa0), is(0x1680), isIn(0x2000, 0x200a), is(0x2028), is(0x2029), is(0x202f), is(0x205f), is(0x3000), is(0xfeff)]),
        ...op.if(I32), ...op.localGet(len), ...op.else, ...op.i32(0), ...op.end,
      ];
    });
  }

  // 前後の空白を消した新しい文字（JavaScript の String.prototype.trim と同じ空白）
  trimFn() {
    const ws = this.wsAtFn();
    return this.gen('trim', [I32], [I32], (local) => {
      const [s, e, j, k, p] = [local(I32), local(I32), local(I32), local(I32), local(I32)];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localSet(e),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(s), ...op.localGet(e), ...op.i32GeU, ...op.brIf(1),
        ...op.localGet(0), ...op.localGet(s), ...op.call(ws), ...op.localTee(k), ...op.i32Eqz, ...op.brIf(1),
        ...op.localGet(s), ...op.localGet(k), ...op.i32Add, ...op.localSet(s), ...op.br(0),
        ...op.end, ...op.end,
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(e), ...op.localGet(s), ...op.i32LeU, ...op.brIf(1),
        // 最後の文字の始まりを探す（続きのバイト 10xxxxxx を戻る）
        ...op.localGet(e), ...op.i32(1), ...op.i32Sub, ...op.localSet(j),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(0), ...op.localGet(j), ...op.i32Add, ...op.i32Load8u(4), ...op.i32(0xc0), ...op.i32And, ...op.i32(0x80), ...op.i32Ne, ...op.brIf(1),
        ...op.localGet(j), ...op.i32(1), ...op.i32Sub, ...op.localSet(j), ...op.br(0),
        ...op.end, ...op.end,
        ...op.localGet(0), ...op.localGet(j), ...op.call(ws), ...op.i32Eqz, ...op.brIf(1),
        ...op.localGet(j), ...op.localSet(e), ...op.br(0),
        ...op.end, ...op.end,
        ...op.localGet(e), ...op.localGet(s), ...op.i32Sub, ...op.localTee(k), ...op.i32(4), ...op.i32Add, ...op.call(this.h.alloc), ...op.localTee(p), ...op.localGet(k), ...op.i32Store(0),
        ...op.localGet(p), ...op.i32(4), ...op.i32Add, ...op.localGet(0), ...op.i32(4), ...op.i32Add, ...op.localGet(s), ...op.i32Add, ...op.localGet(k), ...op.memoryCopy,
        ...op.localGet(p),
      ];
    });
  }

  // 前後の空白を消して、-? と数字だけなら Some(数)。±MAX を超えるなら None（インタプリタと同じ）
  parseIntFn() {
    const trim = this.trimFn();
    const opt = { k: 'Data', name: 'Option', args: [{ k: 'Int' }] };
    return this.gen('parse_int', [I32], [I32], (local) => {
      const [t, n, i, neg, b, acc, p] = [local(I32), local(I32), local(I32), local(I32), local(I32), local(I64), local(I32)];
      const none = [...op.i32(this.tagConst(this.variantOf.get('None').index)), ...op.return];
      return [
        ...op.localGet(0), ...op.call(trim), ...op.localTee(t), ...op.i32Load(0), ...op.localTee(n), ...op.i32Eqz, ...op.if(EMPTY), ...none, ...op.end,
        ...op.localGet(t), ...op.i32Load8u(4), ...op.i32(45), ...op.i32Eq, ...op.localTee(neg), ...op.localSet(i),
        ...op.localGet(i), ...op.localGet(n), ...op.i32GeU, ...op.if(EMPTY), ...none, ...op.end,
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(i), ...op.localGet(n), ...op.i32GeU, ...op.brIf(1),
        ...op.localGet(t), ...op.localGet(i), ...op.i32Add, ...op.i32Load8u(4), ...op.i32(48), ...op.i32Sub, ...op.localTee(b), ...op.i32(9), ...op.i32GtU, ...op.if(EMPTY), ...none, ...op.end,
        ...op.localGet(acc), ...op.i64(10), ...op.i64Mul, ...op.localGet(b), ...op.i64ExtendI32U, ...op.i64Add, ...op.localTee(acc), ...op.i64(MAX), ...op.i64GtS, ...op.if(EMPTY), ...none, ...op.end,
        ...op.localGet(i), ...op.i32(1), ...op.i32Add, ...op.localSet(i), ...op.br(0),
        ...op.end, ...op.end,
        ...this.mkData(opt, 'Some', [[...op.localGet(neg), ...op.if(I64), ...op.i64(0), ...op.localGet(acc), ...op.i64Sub, ...op.else, ...op.localGet(acc), ...op.end]], { local: () => p }, null),
      ];
    });
  }
  // 新しい文字（長さ n バイト、中身はまだ）を作る。場所を局所変数 p に入れる
  newStr(n, p) {
    return [...n, ...op.i32(4), ...op.i32Add, ...op.call(this.h.alloc), ...op.localTee(p), ...n, ...op.i32Store(0)];
  }

  // s の中で、at バイト目から part が続いていれば 1（範囲の外なら 0）
  matchAtFn() {
    return this.gen('match at', [I32, I32, I32], [I32], (local) => {
      const [m, k] = [local(I32), local(I32)];
      return [
        ...op.localGet(2), ...op.i32Load(0), ...op.localSet(m),
        ...op.localGet(1), ...op.i32(0), ...op.i32LtS,
        ...op.localGet(1), ...op.localGet(m), ...op.i32Add, ...op.localGet(0), ...op.i32Load(0), ...op.i32GtU, ...op.i32Or,
        ...op.if(EMPTY), ...op.i32(0), ...op.return, ...op.end,
        ...forEach(k, m, [
          ...op.localGet(0), ...op.localGet(1), ...op.i32Add, ...op.localGet(k), ...op.i32Add, ...op.i32Load8u(4),
          ...op.localGet(2), ...op.localGet(k), ...op.i32Add, ...op.i32Load8u(4), ...op.i32Ne,
          ...op.if(EMPTY), ...op.i32(0), ...op.return, ...op.end,
        ]),
        ...op.i32(1),
      ];
    });
  }

  // s の from バイト目から後ろで、part が最初に出てくる場所。無ければ -1
  indexOfFn() {
    const at = this.matchAtFn();
    return this.gen('index of', [I32, I32, I32], [I32], (local) => {
      const [last] = [local(I32)];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localGet(1), ...op.i32Load(0), ...op.i32Sub, ...op.localSet(last),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(2), ...op.localGet(last), ...op.i32GtS, ...op.brIf(1),
        ...op.localGet(0), ...op.localGet(2), ...op.localGet(1), ...op.call(at), ...op.if(EMPTY), ...op.localGet(2), ...op.return, ...op.end,
        ...op.localGet(2), ...op.i32(1), ...op.i32Add, ...op.localSet(2), ...op.br(0),
        ...op.end, ...op.end,
        ...op.i32(-1),
      ];
    });
  }

  // s の from から to（バイト）を切り出した新しい文字
  sliceFn() {
    return this.gen('slice', [I32, I32, I32], [I32], (local) => {
      const p = local(I32);
      const n = [...op.localGet(2), ...op.localGet(1), ...op.i32Sub];
      return [
        ...this.newStr(n, p),
        ...op.localGet(p), ...op.i32(4), ...op.i32Add, ...op.localGet(0), ...op.i32(4), ...op.i32Add, ...op.localGet(1), ...op.i32Add, ...n, ...op.memoryCopy,
        ...op.localGet(p),
      ];
    });
  }

  // split(text, by)：by は空でないこと（呼ぶ側で確かめる）。JavaScript の split と同じく、左から重ならないように切る
  splitFn() {
    const find = this.indexOfFn();
    const slice = this.sliceFn();
    return this.gen('split', [I32, I32], [I32], (local) => {
      const [n, at, from, p, k] = [local(I32), local(I32), local(I32), local(I32), local(I32)];
      const next = [...op.localGet(0), ...op.localGet(1), ...op.localGet(from), ...op.call(find), ...op.localSet(at)];
      const step = [...op.localGet(at), ...op.localGet(1), ...op.i32Load(0), ...op.i32Add, ...op.localSet(from)];
      return [
        // 1回目：いくつに分かれるかを数える
        ...op.i32(1), ...op.localSet(n), ...op.i32(0), ...op.localSet(from),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...next, ...op.localGet(at), ...op.i32(0), ...op.i32LtS, ...op.brIf(1),
        ...op.localGet(n), ...op.i32(1), ...op.i32Add, ...op.localSet(n), ...step, ...op.br(0),
        ...op.end, ...op.end,
        // 2回目：切り出して入れる
        ...this.newList(n, p), ...op.i32(0), ...op.localSet(from), ...op.i32(0), ...op.localSet(k),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...next, ...op.localGet(at), ...op.i32(0), ...op.i32LtS, ...op.brIf(1),
        ...elemAddr(p, k), ...op.localGet(0), ...op.localGet(from), ...op.localGet(at), ...op.call(slice), ...op.i32Store(8),
        ...op.localGet(k), ...op.i32(1), ...op.i32Add, ...op.localSet(k), ...step, ...op.br(0),
        ...op.end, ...op.end,
        ...elemAddr(p, k), ...op.localGet(0), ...op.localGet(from), ...op.localGet(0), ...op.i32Load(0), ...op.call(slice), ...op.i32Store(8),
        ...op.localGet(p),
      ];
    });
  }

  // 1文字（コードポイント）ずつのリスト
  charsFn() {
    const slice = this.sliceFn();
    return this.gen('chars', [I32], [I32], (local) => {
      const [len, i, n, p, b, w] = [local(I32), local(I32), local(I32), local(I32), local(I32), local(I32)];
      // 先頭のバイトから、その文字のバイト数
      const width = [
        ...op.localGet(0), ...op.localGet(i), ...op.i32Add, ...op.i32Load8u(4), ...op.localTee(b), ...op.i32(0x80), ...op.i32LtU,
        ...op.if(I32), ...op.i32(1), ...op.else,
        ...op.localGet(b), ...op.i32(0xe0), ...op.i32LtU, ...op.if(I32), ...op.i32(2), ...op.else,
        ...op.localGet(b), ...op.i32(0xf0), ...op.i32LtU, ...op.if(I32), ...op.i32(3), ...op.else, ...op.i32(4), ...op.end, ...op.end, ...op.end,
        ...op.localSet(w),
      ];
      const walk = (body) => [
        ...op.i32(0), ...op.localSet(i),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(i), ...op.localGet(len), ...op.i32GeU, ...op.brIf(1),
        ...width, ...body,
        ...op.localGet(i), ...op.localGet(w), ...op.i32Add, ...op.localSet(i), ...op.br(0),
        ...op.end, ...op.end,
      ];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localSet(len),
        ...walk([...op.localGet(n), ...op.i32(1), ...op.i32Add, ...op.localSet(n)]),
        ...this.newList(n, p), ...op.i32(0), ...op.localSet(n),
        ...walk([
          ...elemAddr(p, n), ...op.localGet(0), ...op.localGet(i), ...op.localGet(i), ...op.localGet(w), ...op.i32Add, ...op.call(slice), ...op.i32Store(8),
          ...op.localGet(n), ...op.i32(1), ...op.i32Add, ...op.localSet(n),
        ]),
        ...op.localGet(p),
      ];
    });
  }

  // join(parts, by)。新しい文字を作る（parts が空でも新しい空の文字）
  joinFn() {
    return this.gen('join', [I32, I32], [I32], (local) => {
      const [n, i, acc] = [local(I32), local(I32), local(I32)];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localSet(n),
        ...op.i32(this.str('')), ...op.i32(this.str('')), ...op.call(this.h.concat), ...op.localSet(acc),
        ...forEach(i, n, [
          ...op.localGet(i), ...op.if(EMPTY), ...op.localGet(acc), ...op.localGet(1), ...op.call(this.h.concat), ...op.localSet(acc), ...op.end,
          ...op.localGet(acc), ...elemAddr(0, i), ...op.i32Load(8), ...op.call(this.h.concat), ...op.localSet(acc),
        ]),
        ...op.localGet(acc),
      ];
    });
  }

  // lines：空なら []。\r\n を \n にそろえ、最後の \n を1つ落としてから \n で切る
  linesFn() {
    const split = this.splitFn();
    return this.gen('lines', [I32], [I32], (local) => {
      const [n, i, w, p, b] = [local(I32), local(I32), local(I32), local(I32), local(I32)];
      const byte = (k) => [...op.localGet(0), ...op.localGet(i), ...op.i32Add, ...op.i32Load8u(4 + k)];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localTee(n), ...op.i32Eqz, ...op.if(EMPTY), ...op.i32(0), ...op.localSet(n), ...this.newList(n, p), ...op.localGet(p), ...op.return, ...op.end,
        ...this.newStr(op.localGet(n), p), ...op.localGet(p), ...op.i32(4), ...op.i32Add, ...op.localSet(w),
        ...forEach(i, n, [
          ...op.block(EMPTY),
          // \r のすぐ後ろが \n なら、\r は写さない
          ...byte(0), ...op.localTee(b), ...op.i32(13), ...op.i32Eq,
          ...op.localGet(i), ...op.i32(1), ...op.i32Add, ...op.localGet(n), ...op.i32LtU, ...op.i32And,
          ...op.if(EMPTY), ...byte(1), ...op.i32(10), ...op.i32Eq, ...op.brIf(1), ...op.end,
          ...op.localGet(w), ...op.localGet(b), ...op.i32Store8(0), ...op.localGet(w), ...op.i32(1), ...op.i32Add, ...op.localSet(w),
          ...op.end,
        ]),
        // 最後の \n を1つ落とす
        ...op.localGet(w), ...op.localGet(p), ...op.i32(4), ...op.i32Add, ...op.i32Sub, ...op.localSet(n),
        ...op.localGet(n), ...op.if(EMPTY),
        ...op.localGet(w), ...op.i32(1), ...op.i32Sub, ...op.i32Load8u(0), ...op.i32(10), ...op.i32Eq, ...op.if(EMPTY), ...op.localGet(n), ...op.i32(1), ...op.i32Sub, ...op.localSet(n), ...op.end,
        ...op.end,
        ...op.localGet(p), ...op.localGet(n), ...op.i32Store(0),
        ...op.localGet(p), ...op.i32(this.str('\n')), ...op.call(split),
      ];
    });
  }

  // html_text：& < > " ' を置きかえた新しい文字（インタプリタの escapeHtml と同じ）
  escapeFn() {
    return this.gen('escape html', [I32], [I32], (local) => {
      const [n, i, out, w, b] = [local(I32), local(I32), local(I32), local(I32), local(I32)];
      const put = (text) => utf8(text).flatMap((c) => [...op.localGet(w), ...op.i32(c), ...op.i32Store8(0), ...op.localGet(w), ...op.i32(1), ...op.i32Add, ...op.localSet(w)]);
      const esc = (c, text) => [...op.localGet(b), ...op.i32(c.charCodeAt(0)), ...op.i32Eq, ...op.if(EMPTY), ...put(text), ...op.br(1), ...op.end];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localSet(n),
        ...op.localGet(n), ...op.i32(6), ...op.i32Mul, ...op.i32(4), ...op.i32Add, ...op.call(this.h.alloc), ...op.localSet(out),
        ...op.localGet(out), ...op.i32(4), ...op.i32Add, ...op.localSet(w),
        ...forEach(i, n, [
          ...op.block(EMPTY),
          ...op.localGet(0), ...op.localGet(i), ...op.i32Add, ...op.i32Load8u(4), ...op.localSet(b),
          ...esc('&', '&amp;'), ...esc('<', '&lt;'), ...esc('>', '&gt;'), ...esc('"', '&quot;'), ...esc("'", '&#39;'),
          ...op.localGet(w), ...op.localGet(b), ...op.i32Store8(0), ...op.localGet(w), ...op.i32(1), ...op.i32Add, ...op.localSet(w),
          ...op.end,
        ]),
        ...op.localGet(out), ...op.localGet(w), ...op.localGet(out), ...op.i32Sub, ...op.i32(4), ...op.i32Sub, ...op.i32Store(0),
        ...op.localGet(out),
      ];
    });
  }

  // Sql の表示：型紙 -- params: ["a","b"]（JSON.stringify と同じ形）
  showSqlFn() {
    return this.gen('show Sql', [I32], [I32], (local) => {
      const [n, i, acc, v] = [local(I32), local(I32), local(I32), local(I32)];
      const cat = (code) => [...op.localGet(acc), ...code, ...op.call(this.h.concat), ...op.localSet(acc)];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localSet(acc), ...cat(op.i32(this.str(' -- params: ['))),
        ...op.localGet(0), ...op.i32Load(4), ...op.localTee(v), ...op.i32Load(0), ...op.localSet(n),
        ...forEach(i, n, [
          ...op.localGet(i), ...op.if(EMPTY), ...cat(op.i32(this.str(','))), ...op.end,
          ...cat([...elemAddr(v, i), ...op.i32Load(8), ...op.call(this.quoteFn())]),
        ]),
        ...cat(op.i32(this.str(']'))), ...op.localGet(acc),
      ];
    });
  }

  textBuiltin(e, A, arg, ctx) {
    const pos = e.pos;
    switch (e.name) {
      case 'chars': return [...A('text'), ...op.call(this.charsFn())];
      case 'split': {
        const by = ctx.local(I32);
        return [...A('text'), ...A('by'), ...op.localTee(by), ...op.i32Load(0), ...op.i32Eqz,
          ...op.if(EMPTY), ...this.failAt('R506', 'split needs a non-empty separator', pos), ...op.end,
          ...op.localGet(by), ...op.call(this.splitFn())];
      }
      case 'join': return [...A('parts'), ...A('by'), ...op.call(this.joinFn())];
      case 'contains': return [...A('text'), ...A('part'), ...op.i32(0), ...op.call(this.indexOfFn()), ...op.i32(0), ...op.i32GeS];
      case 'starts_with': {
        const [t, x] = [ctx.local(I32), ctx.local(I32)];
        return [...A('text'), ...op.localSet(t), ...A('prefix'), ...op.localSet(x), ...op.localGet(t), ...op.i32(0), ...op.localGet(x), ...op.call(this.matchAtFn())];
      }
      case 'ends_with': {
        const [t, x] = [ctx.local(I32), ctx.local(I32)];
        return [...A('text'), ...op.localSet(t), ...A('suffix'), ...op.localSet(x),
          ...op.localGet(t), ...op.localGet(t), ...op.i32Load(0), ...op.localGet(x), ...op.i32Load(0), ...op.i32Sub, ...op.localGet(x), ...op.call(this.matchAtFn())];
      }
      case 'lines': return [...A('text'), ...op.call(this.linesFn())];
      case 'html_text': return [...A('value'), ...op.call(this.escapeFn())];
      case 'html_join': return [...A('parts'), ...op.i32(this.str('')), ...op.call(this.joinFn())];
      case 'html': case 'sql': {
        // 型紙は書いたままの文字（E310 で確かめ済み）なので、穴の数はコンパイルのときにわかる
        const mark = e.name === 'html' ? '{}' : '?';
        const parts = arg('template').value.v.split(mark);
        const vs = ctx.local(I32);
        const check = [
          ...A('values'), ...op.localTee(vs), ...op.i32Load(0), ...op.i32(parts.length - 1), ...op.i32Ne,
          ...op.if(EMPTY), ...this.failAt('R510', `the template has ${parts.length - 1} hole(s) '${mark}' but a different number of values were given`, pos), ...op.end,
        ];
        if (e.name === 'sql') {
          const p = ctx.local(I32);
          return [...check, ...op.i32(8), ...op.call(this.h.alloc), ...op.localTee(p), ...op.i32(this.str(arg('template').value.v)), ...op.i32Store(0),
            ...op.localGet(p), ...op.localGet(vs), ...op.i32Store(4), ...op.localGet(p)];
        }
        const out = [...check, ...op.i32(this.str('')), ...op.i32(this.str(parts[0])), ...op.call(this.h.concat)];
        parts.slice(1).forEach((part, i) => out.push(
          ...op.localGet(vs), ...op.i32Load(8 + 8 * i), ...op.call(this.h.concat), ...op.i32(this.str(part)), ...op.call(this.h.concat),
        ));
        return out;
      }
      default: throw new Unsupported(`the built-in function ${e.name}`, pos);
    }
  }
  // ---- ファイルを読む（Folder。WASI の fd 3 が、渡されたフォルダ） ----
  // read_text の本体。返すのは Result[Str] の場所。ただし 0 は「パスがフォルダの中を指していない」、1 は「リンクで外を指す」（呼ぶ側が R507 で止める）
  readTextFn() {
    const utf8ok = this.utf8OkFn();
    const slice = this.sliceFn();
    const rt = { k: 'Data', name: 'Result', args: [{ k: 'Str' }] };
    return this.gen('read_text', [I32], [I32], (local) => {
      const [n, i, seg, b, e, fd, buf, cap, total, nr, tmp] = [local(I32), local(I32), local(I32), local(I32), local(I32), local(I32), local(I32), local(I32), local(I32), local(I32), local(I32)];
      const ctx = { local: () => tmp };
      const byte = (at) => [...op.localGet(0), ...at, ...op.i32Add, ...op.i32Load8u(4)];
      const err = (suffix) => [
        ...this.mkData(rt, 'Err', [[...op.i32(this.str("'")), ...op.localGet(0), ...op.call(this.h.concat), ...op.i32(this.str(`' ${suffix}`)), ...op.call(this.h.concat)]], ctx, null),
        ...op.return,
      ];
      const ret0 = [...op.i32(0), ...op.return];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localSet(n),
        // インタプリタと同じ確かめ：空・/ で始まる・C: で始まる・\ か \0 を含む・.. の段がある
        ...op.localGet(n), ...op.i32Eqz, ...op.if(EMPTY), ...ret0, ...op.end,
        ...byte(op.i32(0)), ...op.i32(47), ...op.i32Eq, ...op.if(EMPTY), ...ret0, ...op.end,
        ...op.localGet(n), ...op.i32(2), ...op.i32GeU, ...op.if(EMPTY),
        ...byte(op.i32(1)), ...op.i32(58), ...op.i32Eq, ...byte(op.i32(0)), ...op.i32(32), ...op.i32Or, ...op.i32(97), ...op.i32Sub, ...op.i32(26), ...op.i32LtU, ...op.i32And,
        ...op.if(EMPTY), ...ret0, ...op.end, ...op.end,
        ...op.i32(0), ...op.localSet(seg),
        ...op.i32(0), ...op.localSet(i),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        // i == n か、i の文字が / なら、段 [seg, i) を見る
        ...op.localGet(i), ...op.localGet(n), ...op.i32Eq,
        ...op.if(I32), ...op.i32(1), ...op.else,
        ...byte(op.localGet(i)), ...op.localTee(b), ...op.i32(92), ...op.i32Eq, ...op.localGet(b), ...op.i32Eqz, ...op.i32Or, ...op.if(EMPTY), ...ret0, ...op.end,
        ...op.localGet(b), ...op.i32(47), ...op.i32Eq,
        ...op.end,
        ...op.if(EMPTY),
        ...op.localGet(i), ...op.localGet(seg), ...op.i32Sub, ...op.i32(2), ...op.i32Eq,
        ...op.if(EMPTY),
        ...byte(op.localGet(seg)), ...op.i32(46), ...op.i32Eq, ...byte([...op.localGet(seg), ...op.i32(1), ...op.i32Add]), ...op.i32(46), ...op.i32Eq, ...op.i32And,
        ...op.if(EMPTY), ...ret0, ...op.end,
        ...op.end,
        ...op.localGet(i), ...op.i32(1), ...op.i32Add, ...op.localSet(seg),
        ...op.end,
        ...op.localGet(i), ...op.localGet(n), ...op.i32GeU, ...op.brIf(1),
        ...op.localGet(i), ...op.i32(1), ...op.i32Add, ...op.localSet(i), ...op.br(0),
        ...op.end, ...op.end,
        // 開ける：読む権利（fd_read と fd_filestat_get）だけを頼む（書く・作る権利は頼まない）。リンクはたどり、外を指していれば受け皿が断る
        ...op.i32(3), ...op.i32(1), ...op.localGet(0), ...op.i32(4), ...op.i32Add, ...op.localGet(n), ...op.i32(0), ...op.i64(2 + 2097152), ...op.i64(0), ...op.i32(0), ...op.i32(SCRATCH),
        ...op.call(this.imp.pathOpen), ...op.localTee(e),
        ...op.if(EMPTY),
        ...op.localGet(e), ...op.i32(76), ...op.i32Eq, ...op.localGet(e), ...op.i32(63), ...op.i32Eq, ...op.i32Or, ...op.if(EMPTY), ...op.i32(1), ...op.return, ...op.end,
        ...op.localGet(e), ...op.i32(44), ...op.i32Eq, ...op.if(EMPTY), ...err('does not exist'), ...op.end,
        ...op.localGet(e), ...op.i32(31), ...op.i32Eq, ...op.localGet(e), ...op.i32(54), ...op.i32Eq, ...op.i32Or, ...op.if(EMPTY), ...err('is not a file'), ...op.end,
        ...err('could not be read as UTF-8 text'),
        ...op.end,
        ...op.i32(SCRATCH), ...op.i32Load(0), ...op.localSet(fd),
        // ふつうのファイル（filetype 4）でなければ「ファイルでない」（フォルダを開けても、読む前に止める）
        ...op.i32(64), ...op.call(this.h.alloc), ...op.localSet(nr),
        ...op.localGet(fd), ...op.localGet(nr), ...op.call(this.imp.fdFilestat), ...op.localGet(nr), ...op.i32Load8u(16), ...op.i32(4), ...op.i32Ne, ...op.i32Or,
        ...op.if(EMPTY), ...op.localGet(fd), ...op.call(this.imp.fdClose), ...op.drop, ...err('is not a file'), ...op.end,
        // 読む：64KiB ずつ。alloc は続けて呼ぶと続きの場所を返すので、1つの文字としてつながる
        ...op.i32(4 + 65536), ...op.call(this.h.alloc), ...op.localSet(buf), ...op.i32(65536), ...op.localSet(cap),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(total), ...op.localGet(cap), ...op.i32Eq, ...op.if(EMPTY), ...op.i32(65536), ...op.call(this.h.alloc), ...op.drop, ...op.localGet(cap), ...op.i32(65536), ...op.i32Add, ...op.localSet(cap), ...op.end,
        ...op.i32(IOV), ...op.localGet(buf), ...op.i32(4), ...op.i32Add, ...op.localGet(total), ...op.i32Add, ...op.i32Store(0),
        ...op.i32(IOV), ...op.localGet(cap), ...op.localGet(total), ...op.i32Sub, ...op.i32Store(4),
        ...op.localGet(fd), ...op.i32(IOV), ...op.i32(1), ...op.i32(SCRATCH + 8), ...op.call(this.imp.fdRead), ...op.localTee(e),
        ...op.if(EMPTY),
        ...op.localGet(fd), ...op.call(this.imp.fdClose), ...op.drop,
        ...op.localGet(e), ...op.i32(31), ...op.i32Eq, ...op.if(EMPTY), ...err('is not a file'), ...op.end,
        ...err('could not be read as UTF-8 text'),
        ...op.end,
        ...op.i32(SCRATCH + 8), ...op.i32Load(0), ...op.localTee(nr), ...op.i32Eqz, ...op.brIf(1),
        ...op.localGet(total), ...op.localGet(nr), ...op.i32Add, ...op.localSet(total), ...op.br(0),
        ...op.end, ...op.end,
        ...op.localGet(fd), ...op.call(this.imp.fdClose), ...op.drop,
        ...op.localGet(buf), ...op.localGet(total), ...op.i32Store(0),
        ...op.localGet(buf), ...op.call(utf8ok), ...op.i32Eqz, ...op.if(EMPTY), ...err('could not be read as UTF-8 text'), ...op.end,
        // 先頭の BOM（EF BB BF）は落とす（インタプリタの TextDecoder と同じ）
        ...op.localGet(total), ...op.i32(3), ...op.i32GeU, ...op.if(EMPTY),
        ...op.localGet(buf), ...op.i32Load8u(4), ...op.i32(0xef), ...op.i32Eq,
        ...op.localGet(buf), ...op.i32Load8u(5), ...op.i32(0xbb), ...op.i32Eq, ...op.i32And,
        ...op.localGet(buf), ...op.i32Load8u(6), ...op.i32(0xbf), ...op.i32Eq, ...op.i32And,
        ...op.if(EMPTY), ...op.localGet(buf), ...op.i32(3), ...op.localGet(total), ...op.call(slice), ...op.localSet(buf), ...op.end,
        ...op.end,
        ...this.mkData(rt, 'Ok', [op.localGet(buf)], ctx, null),
      ];
    });
  }

  // 正しい UTF-8 なら 1（長すぎる形・サロゲート・U+10FFFF を超えるものは 0。WHATWG の UTF-8 の読み方と同じ）
  utf8OkFn() {
    return this.gen('utf8 ok', [I32], [I32], (local) => {
      const [n, i, b, need, lo, hi, k] = [local(I32), local(I32), local(I32), local(I32), local(I32), local(I32), local(I32)];
      const byte = (at) => [...op.localGet(0), ...at, ...op.i32Add, ...op.i32Load8u(4)];
      const set = (nd, l, h) => [...op.i32(nd), ...op.localSet(need), ...op.i32(l), ...op.localSet(lo), ...op.i32(h), ...op.localSet(hi)];
      const inRange = (a, z) => [...op.localGet(b), ...op.i32(a), ...op.i32Sub, ...op.i32(z - a + 1), ...op.i32LtU];
      const rules = [
        [inRange(0xc2, 0xdf), set(1, 0x80, 0xbf)],
        [inRange(0xe0, 0xe0), set(2, 0xa0, 0xbf)],
        [inRange(0xe1, 0xec), set(2, 0x80, 0xbf)],
        [inRange(0xed, 0xed), set(2, 0x80, 0x9f)],
        [inRange(0xee, 0xef), set(2, 0x80, 0xbf)],
        [inRange(0xf0, 0xf0), set(3, 0x90, 0xbf)],
        [inRange(0xf1, 0xf3), set(3, 0x80, 0xbf)],
        [inRange(0xf4, 0xf4), set(3, 0x80, 0x8f)],
      ];
      const chain = (j) => (j === rules.length
        ? [...op.i32(0), ...op.return]
        : [...rules[j][0], ...op.if(EMPTY), ...rules[j][1], ...op.else, ...chain(j + 1), ...op.end]);
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localSet(n),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(i), ...op.localGet(n), ...op.i32GeU, ...op.brIf(1),
        ...byte(op.localGet(i)), ...op.localTee(b), ...op.i32(0x80), ...op.i32LtU,
        ...op.if(EMPTY), ...op.localGet(i), ...op.i32(1), ...op.i32Add, ...op.localSet(i), ...op.br(1), ...op.end,
        ...chain(0),
        ...op.localGet(i), ...op.localGet(need), ...op.i32Add, ...op.localGet(n), ...op.i32GeU, ...op.if(EMPTY), ...op.i32(0), ...op.return, ...op.end,
        ...byte([...op.localGet(i), ...op.i32(1), ...op.i32Add]), ...op.localTee(b), ...op.localGet(lo), ...op.i32LtU,
        ...op.localGet(b), ...op.localGet(hi), ...op.i32GtU, ...op.i32Or, ...op.if(EMPTY), ...op.i32(0), ...op.return, ...op.end,
        ...op.i32(2), ...op.localSet(k),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(k), ...op.localGet(need), ...op.i32GtU, ...op.brIf(1),
        ...byte([...op.localGet(i), ...op.localGet(k), ...op.i32Add]), ...op.i32(0xc0), ...op.i32And, ...op.i32(0x80), ...op.i32Ne, ...op.if(EMPTY), ...op.i32(0), ...op.return, ...op.end,
        ...op.localGet(k), ...op.i32(1), ...op.i32Add, ...op.localSet(k), ...op.br(0),
        ...op.end, ...op.end,
        ...op.localGet(i), ...op.localGet(need), ...op.i32Add, ...op.i32(1), ...op.i32Add, ...op.localSet(i), ...op.br(0),
        ...op.end, ...op.end,
        ...op.i32(1),
      ];
    });
  }
  // s の k 文字目（コードポイント）が始まるバイトの場所。k が文字の数と同じなら長さ。超えるか負なら -1
  cpOffsetFn() {
    return this.gen('cp offset', [I32, I64], [I32], (local) => {
      const [n, i, c, b] = [local(I32), local(I32), local(I64), local(I32)];
      return [
        ...op.localGet(1), ...op.i64(0), ...op.i64LtS, ...op.if(EMPTY), ...op.i32(-1), ...op.return, ...op.end,
        ...op.localGet(0), ...op.i32Load(0), ...op.localSet(n),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(c), ...op.localGet(1), ...op.i64Eq, ...op.if(EMPTY), ...op.localGet(i), ...op.return, ...op.end,
        ...op.localGet(i), ...op.localGet(n), ...op.i32GeU, ...op.brIf(1),
        // 次の文字の始まりへ（続きのバイト 10xxxxxx を飛ばす）
        ...op.localGet(i), ...op.i32(1), ...op.i32Add, ...op.localSet(i),
        ...op.block(EMPTY), ...op.loop(EMPTY),
        ...op.localGet(i), ...op.localGet(n), ...op.i32GeU, ...op.brIf(1),
        ...op.localGet(0), ...op.localGet(i), ...op.i32Add, ...op.i32Load8u(4), ...op.localTee(b), ...op.i32(0xc0), ...op.i32And, ...op.i32(0x80), ...op.i32Ne, ...op.brIf(1),
        ...op.localGet(i), ...op.i32(1), ...op.i32Add, ...op.localSet(i), ...op.br(0),
        ...op.end, ...op.end,
        ...op.localGet(c), ...op.i64(1), ...op.i64Add, ...op.localSet(c), ...op.br(0),
        ...op.end, ...op.end,
        ...op.i32(-1),
      ];
    });
  }

  // 1文字の文字から、その文字のコード。1文字でなければ -1
  codeOfFn() {
    return this.gen('code of', [I32], [I64], (local) => {
      const [n, b0, w] = [local(I32), local(I32), local(I32)];
      const cont = (k) => [...op.localGet(0), ...op.i32Load8u(4 + k), ...op.i32(63), ...op.i32And];
      const shl = (code, sh) => [...code, ...op.i32(sh), ...op.i32Shl];
      return [
        ...op.localGet(0), ...op.i32Load(0), ...op.localTee(n), ...op.i32Eqz, ...op.if(EMPTY), ...op.i64(-1), ...op.return, ...op.end,
        ...op.localGet(0), ...op.i32Load8u(4), ...op.localTee(b0), ...op.i32(0x80), ...op.i32LtU,
        ...op.if(I32), ...op.i32(1), ...op.else, ...op.localGet(b0), ...op.i32(0xe0), ...op.i32LtU,
        ...op.if(I32), ...op.i32(2), ...op.else, ...op.localGet(b0), ...op.i32(0xf0), ...op.i32LtU, ...op.if(I32), ...op.i32(3), ...op.else, ...op.i32(4), ...op.end, ...op.end, ...op.end,
        ...op.localTee(w), ...op.localGet(n), ...op.i32Ne, ...op.if(EMPTY), ...op.i64(-1), ...op.return, ...op.end,
        ...op.localGet(w), ...op.i32(1), ...op.i32Eq, ...op.if(EMPTY), ...op.localGet(b0), ...op.i64ExtendI32U, ...op.return, ...op.end,
        ...op.localGet(w), ...op.i32(2), ...op.i32Eq, ...op.if(EMPTY), ...shl([...op.localGet(b0), ...op.i32(31), ...op.i32And], 6), ...cont(1), ...op.i32Or, ...op.i64ExtendI32U, ...op.return, ...op.end,
        ...op.localGet(w), ...op.i32(3), ...op.i32Eq, ...op.if(EMPTY), ...shl([...op.localGet(b0), ...op.i32(15), ...op.i32And], 12), ...shl(cont(1), 6), ...op.i32Or, ...cont(2), ...op.i32Or, ...op.i64ExtendI32U, ...op.return, ...op.end,
        ...shl([...op.localGet(b0), ...op.i32(7), ...op.i32And], 18), ...shl(cont(1), 12), ...op.i32Or, ...shl(cont(2), 6), ...op.i32Or, ...cont(3), ...op.i32Or, ...op.i64ExtendI32U,
      ];
    });
  }

  // コードから1文字の文字（UTF-8 で 1〜4 バイト）。範囲は呼ぶ側で確かめる
  charOfFn() {
    return this.gen('char of', [I64], [I32], (local) => {
      const [c, p] = [local(I32), local(I32)];
      const mk = (len) => [...op.i32(4 + len), ...op.call(this.h.alloc), ...op.localTee(p), ...op.i32(len), ...op.i32Store(0)];
      const put = (k, code) => [...op.localGet(p), ...code, ...op.i32Store8(4 + k)];
      const bits = (sh, mask, lead) => [...op.localGet(c), ...(sh ? [...op.i32(sh), ...op.i32ShrU] : []), ...op.i32(mask), ...op.i32And, ...op.i32(lead), ...op.i32Or];
      return [
        ...op.localGet(0), ...op.i32WrapI64, ...op.localSet(c),
        ...op.localGet(c), ...op.i32(0x80), ...op.i32LtU, ...op.if(EMPTY), ...mk(1), ...put(0, op.localGet(c)), ...op.localGet(p), ...op.return, ...op.end,
        ...op.localGet(c), ...op.i32(0x800), ...op.i32LtU, ...op.if(EMPTY), ...mk(2), ...put(0, bits(6, 31, 0xc0)), ...put(1, bits(0, 63, 0x80)), ...op.localGet(p), ...op.return, ...op.end,
        ...op.localGet(c), ...op.i32(0x10000), ...op.i32LtU, ...op.if(EMPTY), ...mk(3), ...put(0, bits(12, 15, 0xe0)), ...put(1, bits(6, 63, 0x80)), ...put(2, bits(0, 63, 0x80)), ...op.localGet(p), ...op.return, ...op.end,
        ...mk(4), ...put(0, bits(18, 7, 0xf0)), ...put(1, bits(12, 63, 0x80)), ...put(2, bits(6, 63, 0x80)), ...put(3, bits(0, 63, 0x80)), ...op.localGet(p),
      ];
    });
  }
}

// リスト（局所変数 list）の i 番目の要素の場所から 8 を引いたもの（load・store の off に 8 を足して使う）
// 辞書の i 番めの組の場所から 8 を引いたところ（鍵は +8、値は +16 で読む）
function entryAddr(d, i) {
  return [...op.localGet(d), ...op.localGet(i), ...op.i32(16), ...op.i32Mul, ...op.i32Add];
}

function elemAddr(list, i) {
  return [...op.localGet(list), ...op.localGet(i), ...op.i32(8), ...op.i32Mul, ...op.i32Add];
}

// i を 0 から n-1 まで回す。body の中から、このループの外へ出るのは br(1)（if の中なら br(2)）
function forEach(i, n, body) {
  return [
    ...op.i32(0), ...op.localSet(i), ...op.block(EMPTY), ...op.loop(EMPTY),
    ...op.localGet(i), ...op.localGet(n), ...op.i32GeU, ...op.brIf(1),
    ...body,
    ...op.localGet(i), ...op.i32(1), ...op.i32Add, ...op.localSet(i), ...op.br(0),
    ...op.end, ...op.end,
  ];
}

// |x| を局所変数 to に入れる（x は ±MAX の中なので、符号を反転してもあふれない）
function abs(from, to) {
  return [
    ...op.localGet(from), ...op.i64(0), ...op.i64LtS,
    ...op.if(I64), ...op.i64(0), ...op.localGet(from), ...op.i64Sub, ...op.else, ...op.localGet(from), ...op.end,
    ...op.localSet(to),
  ];
}
