import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, statSync, symlinkSync, chmodSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const executable = process.argv[2];
assert(executable, 'Pass the built prepare-profile helper');
const work = mkdtempSync(join(tmpdir(), 'chatgpt-profile-check-'));
const run = (base, child = 'profile', ok = true) => {
  const result = spawnSync(executable, ['--prepare', base, child], { timeout: 5000 });
  assert.equal(result.status === 0, ok, `Profile admission: ${base}`);
};
try {
  const data = join(work, 'data');
  mkdirSync(data);
  const legacy = join(data, 'omarchy-chatgpt-lite');
  mkdirSync(legacy); writeFileSync(join(legacy, 'keep'), 'legacy data stays');
  run(data); run(data);
  const profileRoot = join(data, 'omarchy-chatgpt-lite-qt');
  for (const path of [profileRoot, join(profileRoot, 'profile')]) {
    assert.equal(statSync(path).mode & 0o777, 0o700);
    chmodSync(path, 0o755);
  }
  run(data);
  for (const path of [profileRoot, join(profileRoot, 'profile')]) assert.equal(statSync(path).mode & 0o777, 0o700);
  assert.equal(readFileSync(join(legacy, 'keep'), 'utf8'), 'legacy data stays');
  run('relative', 'profile', false); run(data, 'unknown', false);
  run(`${data}/../escape`, 'profile', false);
  const linked = join(work, 'linked'); symlinkSync(data, linked, 'dir');
  run(join(linked, 'missing'), 'profile', false);
  for (const child of ['omarchy-chatgpt-lite-qt', 'profile']) {
    const base = join(work, child); mkdirSync(base);
    const prefix = child === 'profile' ? join(base, 'omarchy-chatgpt-lite-qt') : base;
    if (child === 'profile') mkdirSync(prefix);
    symlinkSync(data, join(prefix, child), 'dir'); run(base, 'profile', false);
  }
  const fileRoot = join(work, 'file'); mkdirSync(fileRoot);
  writeFileSync(join(fileRoot, 'omarchy-chatgpt-lite-qt'), 'not directory'); run(fileRoot, 'profile', false);
  const env = { ...process.env, XDG_DATA_HOME: join(work, 'xdg-data'), XDG_CACHE_HOME: join(work, 'xdg-cache') };
  assert.equal(spawnSync(executable, [], { env, timeout: 5000 }).status, 0);
  for (const [base, child] of [[env.XDG_DATA_HOME, 'profile'], [env.XDG_CACHE_HOME, 'cache']]) {
    assert.equal(statSync(join(base, 'omarchy-chatgpt-lite-qt', child)).mode & 0o777, 0o700);
  }
  const manifest = JSON.parse(readFileSync(join(root, 'manifest.json')));
  assert.deepEqual(manifest.kinds, ['service', 'bar-widget']);
  for (const path of Object.values(manifest.entryPoints)) assert(statSync(join(root, path)).isFile());
  const service = readFileSync(join(root, 'native/Service.qml'), 'utf8');
  assert(!service.includes('python'));
  const browser = readFileSync(join(root, 'native/Browser.qml'), 'utf8');
  const content = readFileSync(join(root, 'native/Content.qml'), 'utf8');
  const header = readFileSync(join(root, 'native/Header.qml'), 'utf8');
  assert(!browser.includes('Theme.js') && !browser.includes('runJavaScript') && !browser.includes('userScripts.collection'));
  assert(!content.includes('themeEnabled') && !header.includes('Shared shell:'));
  assert(service.includes('appearance: "ORIGINAL_SITE"'));
  assert(service.includes('prepareDeadline') && service.includes('PROFILE_PATH_TIMEOUT'));
  const files = path => readdirSync(path, { withFileTypes: true }).flatMap(entry =>
    entry.name === '.git' ? [] : entry.isDirectory() ? files(join(path, entry.name)) : [join(path, entry.name)]);
  assert.equal(files(root).filter(path => path.endsWith('.py')).length, 0);
  console.log('PASS native private-profile/idempotence/link/file/relative/enum/XDG preservation and Python-free tree');
} finally {
  rmSync(work, { recursive: true, force: true }); // Exact disposable mkdtemp fixture only.
}
