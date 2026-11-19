// Akashi の診断（エラー）。コードは変えない（AI が覚えて直せるように、意味を固定する）。
// 1つの診断 = { code, kind, message, line, col, fix }。fix は「次にどう書けば通るか」を具体的に書く。

export const CODES = {
  E100: 'syntax error',
  E101: 'unsupported literal',
  E102: 'missing return type',
  E103: 'let needs a type',
  E104: 'unknown type',
  E105: 'and/or mixed without parentheses',
  E106: 'chained comparison',
  E107: 'if without else',
  E108: 'extra end',
  E112: 'when without else',
  E113: 'use path not allowed',
  E114: 'used file not found',
  E115: 'main in a used file',
  E200: 'unknown name',
  E201: 'type mismatch',
  E202: 'wrong arguments',
  E203: 'name reused',
  E206: 'positional argument',
  E207: 'arguments out of order',
  E210: 'match misses a case',
  E211: 'match case that does not belong (else, _, unknown or repeated case)',
  E212: 'pattern fields do not match the case',
  E300: 'capability not given',
  E301: 'no main',
  E302: 'unknown effect (retired in v0.2: effects were replaced by capabilities)',
  E303: 'bad main signature',
  E304: 'function with capabilities passed as value',
  E305: 'effects clause (replaced by capabilities)',
  E309: 'capability stored, returned or compared',
  E310: 'template is not a literal',
  E311: 'template holes and values do not match',
  E401: 'missing ensures',
  E402: 'missing example',
  E600: 'not supported by the compiler yet (akashi build)',
  R500: 'requires failed',
  R501: 'ensures failed',
  R502: 'example failed',
  R503: 'division by zero',
  R504: 'integer overflow',
  R505: 'recursion too deep',
  R506: 'index out of range',
  R507: 'path escapes the folder',
  R508: 'file not readable (retired in v0.5: read_text returns Result[Str] and a missing file is Err)',
  R509: 'capability not granted',
  R510: 'template holes and values do not match',
  R511: 'ensures fails for a generated input',
  R512: 'crash on a generated input that satisfies requires',
};

// もう出さないコード（意味は変えず、番号を使い回さない）
export const RETIRED = ['E302', 'R508'];

export function diag(code, message, pos, fix, extra = {}) {
  return {
    code,
    kind: code.startsWith('R') ? 'runtime' : 'compile',
    message,
    line: pos?.line ?? 0,
    col: pos?.col ?? 0,
    ...(pos?.file ? { file: pos.file } : {}),
    fix,
    ...extra,
  };
}

export class AkashiError extends Error {
  constructor(d) {
    super(`${d.code} ${d.message}`);
    this.diag = d;
  }
}

export function formatDiag(d, file = '<input>') {
  // use で読んだファイルのエラーは、そのファイルの名前を出す（main のファイルから見た場所）
  if (d.file) file = file.includes('/') ? `${file.slice(0, file.lastIndexOf('/') + 1)}${d.file}` : d.file;
  return `${file}:${d.line}:${d.col}: ${d.code} ${d.message}\n  fix: ${d.fix}`;
}

// 似た名前を探す（打ち間違いの直し方を出すため）
export function suggest(name, candidates) {
  let best = null;
  let bestDist = Infinity;
  for (const c of candidates) {
    const d = distance(name, c);
    if (d < bestDist) { best = c; bestDist = d; }
  }
  return best !== null && bestDist <= Math.max(2, Math.floor(name.length / 3)) ? best : null;
}

function distance(a, b) {
  const dp = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
  for (let j = 1; j <= b.length; j++) dp[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      dp[i][j] = Math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
  }
  return dp[a.length][b.length];
}
