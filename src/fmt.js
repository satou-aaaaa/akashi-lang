// 書式を整える（akashi fmt）。書き方の揺れを無くし、AI と人が同じ形で読めるようにする。
// やること：字下げを2つずつにそろえる・語のあいだの空白をそろえる・行末の空白と続く空行を消す・コメントは残す。
// 行の分け方は変えない（どこで改行するかは書いた人に任せる）。意味は変えない（test/fmt.test.js が、整える前と後で構文の木が同じかを確かめる）。
import { lex, parse } from './parse.js';

const OPENERS = new Set(['do', 'if', 'when', 'match', 'type']);

// 1行の語を、決まった空白でつなぐ
function joinLine(toks, src) {
  let out = '';
  let prev = null;
  for (const t of toks) {
    const text = src.slice(t.pos.offset, t.end);
    const v = t.t === 'op' || t.t === 'kw' ? t.v : null;
    let space = prev !== null;
    if (prev) {
      const pv = prev.t === 'op' ? prev.v : null;
      if (v === ',' || v === ')' || v === ']' || v === ':') space = false;
      else if (pv === '(' || pv === '[') space = false;
      else if (v === '(' && (prev.t === 'id')) space = false; // 呼び出し f(x: 1)
      else if (v === '[' && prev.t === 'id') space = false; // 型 List[Int]
      else if (pv === '-' && prev.unary) space = false; // -x
    }
    // 前置きの - かどうか（行のはじめ・演算子・( [ , : のあと・キーワードのあと）
    if (v === '-') {
      t.unary = prev === null || (prev.t === 'op' && prev.v !== ')' && prev.v !== ']') || (prev.t === 'kw' && !['true', 'false', 'end'].includes(prev.v));
    }
    out += (space ? ' ' : '') + text;
    prev = t;
  }
  return out;
}

// 整えた文を返す。構文が通らないものは整えない（{ ok: false, error }）
export function format(src) {
  try {
    parse(src);
  } catch (e) {
    if (e.diag) return { ok: false, error: e.diag };
    throw e;
  }
  const lines = src.replace(/\r\n/g, '\n').split('\n');
  const stack = []; // 開いているもの：'sig'（fn の頭から do まで）・'do'・'if'・'when'・'match'・'type'
  const out = [];
  let blank = 0;
  for (const raw of lines) {
    const line = raw.trim();
    if (line === '') { blank++; continue; }
    const toks = lex(line).filter((t) => t.t !== 'eof');
    const lastEnd = toks.length ? toks[toks.length - 1].end : 0;
    const comment = line.slice(lastEnd).trim(); // 語のあとに残るのはコメントだけ
    const first = toks[0];
    const fv = first && (first.t === 'kw' || first.t === 'op') ? first.v : null;

    // この行の字下げ
    let depth = stack.length;
    if (fv === 'end') depth--;
    else if (fv === 'do' && stack[stack.length - 1] === 'sig') depth--;
    else if (fv === 'else' && stack[stack.length - 1] === 'if') depth--;
    if (fv === 'fn' || fv === 'type') depth = stack.filter((s) => s !== 'sig').length;

    // 空行は1つまで。ブロックのはじめと終わりの空行は消す。いちばん外の fn・type のあいだには空行を1つ置く
    const prevLine = out[out.length - 1];
    const topItem = (fv === 'fn' || fv === 'type') && prevLine !== undefined && /^end\b/.test(prevLine);
    if ((blank || topItem) && out.length && fv !== 'end' && !/(\bdo|\bthen|\belse)$/.test(prevLine)) out.push('');
    blank = 0;

    const body = toks.length ? joinLine(toks, line) : '';
    out.push(`${'  '.repeat(Math.max(0, depth))}${body}${body && comment ? ' ' : ''}${comment}`.trimEnd());

    // 開け閉めを数える
    for (const t of toks) {
      if (t.t !== 'kw') continue;
      if (t.v === 'fn') stack.push('sig');
      else if (t.v === 'do' && stack[stack.length - 1] === 'sig') stack[stack.length - 1] = 'do';
      else if (OPENERS.has(t.v)) stack.push(t.v);
      else if (t.v === 'end') stack.pop();
    }
  }
  return { ok: true, text: `${out.join('\n')}\n` };
}
