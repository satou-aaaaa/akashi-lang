// Node から使う入口。src/core.js と同じものを出す。違いは2つ：
// run はフォルダの名前を鍵にして渡す（CLI の --allow-read・--allow-write）。file（main のファイルの場所）を渡すと、use で読むファイルをそのフォルダから読む。
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import * as core from './core.js';
import { openFolder, openOutFolder } from './folder.js';

export * from './core.js';

// use のファイルを、main のファイルのフォルダから読む（パスの確かめは src/modules.js が先にする）
function loaderFor(file) {
  if (!file) return undefined;
  const root = dirname(resolve(file));
  return (rel) => {
    try { return readFileSync(join(root, rel), 'utf8'); } catch { return null; }
  };
}

export const analyze = (src, { file } = {}) => core.analyze(src, { load: loaderFor(file) });
export const checkSource = (src, { file } = {}) => core.checkSource(src, { load: loaderFor(file) });
export const buildSource = (src, { file } = {}) => core.buildSource(src, { load: loaderFor(file) });

export function runSource(src, { out, grants = {}, file } = {}) {
  return core.runSource(src, { out, load: loaderFor(file), grants: { ...grants, folder: grants.folder ? openFolder(grants.folder) : undefined, outFolder: grants.outFolder ? openOutFolder(grants.outFolder) : undefined } });
}
