// Node から使う入口。src/core.js と同じものを出し、run だけフォルダの名前を Folder の鍵にして渡す（CLI の --allow-read）。
import { runSource as runCore } from './core.js';
import { openFolder } from './folder.js';

export * from './core.js';

export function runSource(src, { out, grants = {} } = {}) {
  return runCore(src, { out, grants: { ...grants, folder: grants.folder ? openFolder(grants.folder) : undefined } });
}
