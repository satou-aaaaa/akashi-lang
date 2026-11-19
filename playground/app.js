// 遊べるページの画面。検査と実行は Worker（worker.js）に任せ、時間がかかりすぎたら止める。
// 見本は examples/ から同じサイトの中だけで読む。コードは URL の # の後ろに入れて共有する（サーバーには送られない）。
const EXAMPLES = ['hello', 'gcd', 'fizzbuzz', 'types', 'stats', 'web'];
const TIMEOUT_MS = 10000;
const $ = (id) => document.getElementById(id);
const code = $('code');
const output = $('output');
const diags = $('diags');
const status = $('status');
const buttons = ['check', 'run', 'wasm', 'fmt'].map($);

let worker = null;
let seq = 0;
function newWorker() {
  worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
}
newWorker();

function ask(action) {
  const id = ++seq;
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      worker.terminate();
      newWorker();
      resolve({ ok: false, diagnostics: [], output: '', crash: `${TIMEOUT_MS / 1000} 秒たっても終わらないので止めました` });
    }, TIMEOUT_MS);
    worker.onmessage = (e) => {
      if (e.data.id !== id) return;
      clearTimeout(timer);
      resolve(e.data);
    };
    worker.postMessage({ id, action, src: code.value });
  });
}

function setStatus(text, kind = '') {
  status.textContent = text;
  status.className = kind;
}

function jumpTo(line, col) {
  const lines = code.value.split('\n');
  let pos = 0;
  for (let i = 0; i < line - 1 && i < lines.length; i++) pos += lines[i].length + 1;
  pos += Math.max(0, col - 1);
  code.focus();
  code.setSelectionRange(pos, pos);
}

function showDiags(list) {
  diags.replaceChildren();
  for (const d of list) {
    const li = document.createElement('li');
    const at = document.createElement('button');
    at.type = 'button';
    at.textContent = `${d.line}:${d.col}`;
    at.title = 'その場所へ';
    at.addEventListener('click', () => jumpTo(d.line, d.col));
    const msg = document.createElement('strong');
    msg.textContent = `${d.code} `;
    const text = document.createTextNode(d.message);
    const fix = document.createElement('span');
    fix.className = 'fix';
    fix.textContent = `fix: ${d.fix}`;
    li.append(at, msg, text, fix);
    diags.append(li);
  }
}

async function act(action) {
  buttons.forEach((b) => { b.disabled = true; });
  setStatus('動かしています…');
  const t0 = performance.now();
  const r = await ask(action);
  const ms = Math.round(performance.now() - t0);
  buttons.forEach((b) => { b.disabled = false; });
  showDiags(r.diagnostics ?? []);
  if (action === 'fmt') {
    if (r.ok) { code.value = r.text; saveHash(); }
    setStatus(r.ok ? '整えました' : '構文の誤りがあるので整えられません', r.ok ? 'ok' : 'bad');
    return;
  }
  let text = r.output ?? r.summary ?? '';
  if (r.errors) text += r.errors;
  if (r.crash) text += `\n${r.crash}`;
  output.textContent = text;
  const extra = r.bytes ? `（${r.bytes} バイトの WebAssembly）` : '';
  setStatus(r.ok ? `通りました ${ms}ms${extra}` : `エラーがあります（${(r.diagnostics ?? []).length || 1} 件）`, r.ok ? 'ok' : 'bad');
}

// URL の # にコードを入れる（UTF-8 → base64url）
function encode(s) {
  const bytes = new TextEncoder().encode(s);
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function decode(s) {
  const bin = atob(s.replace(/-/g, '+').replace(/_/g, '/'));
  return new TextDecoder().decode(Uint8Array.from(bin, (c) => c.charCodeAt(0)));
}
function saveHash() {
  history.replaceState(null, '', `#code=${encode(code.value)}`);
}

async function loadExample(name) {
  const res = await fetch(`examples/${name}.ak`);
  code.value = res.ok ? await res.text() : `# ${name}.ak を読めませんでした\n`;
  output.textContent = '';
  diags.replaceChildren();
  setStatus('');
}

const select = $('example');
for (const name of EXAMPLES) {
  const o = document.createElement('option');
  o.value = name;
  o.textContent = `${name}.ak`;
  select.append(o);
}
select.addEventListener('change', () => loadExample(select.value));
$('check').addEventListener('click', () => act('check'));
$('run').addEventListener('click', () => act('run'));
$('wasm').addEventListener('click', () => act('wasm'));
$('fmt').addEventListener('click', () => act('fmt'));
$('share').addEventListener('click', async () => {
  saveHash();
  try {
    await navigator.clipboard.writeText(location.href);
    setStatus('リンクを写しました', 'ok');
  } catch {
    setStatus('アドレス欄の URL を写してください');
  }
});
code.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); act('run'); }
});

const m = location.hash.match(/^#code=([A-Za-z0-9_-]+)$/);
if (m) {
  try { code.value = decode(m[1]); } catch { loadExample('hello'); }
} else {
  loadExample('hello');
}
