import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(process.argv[2] || dirname(dirname(fileURLToPath(import.meta.url))));
const read = name => readFileSync(resolve(root, name), 'utf8');
const readme = read('README.md');
const status = read('docs/engine-status.md');
assert(readme.includes('speed-first baseline'));
assert(readme.includes('400 MiB ceiling') && readme.includes('are retired'));
assert(!readme.includes('toward 200 MiB'));
assert(status.includes('RAM remains diagnostic information, not a numerical acceptance gate.'));
assert(status.includes('server-side answer-generation speed are different'));
assert(status.replace(/\s+/g, ' ').includes('do not establish installed shared-shell acceptance'));

// Source guards complement, but do not replace, measured consumer behavior.
const service = read('native/Service.qml');
const close = service.match(/function close\(\) \{([\s\S]*?)\n    \}/)?.[1];
assert(close, 'Service close path is required');
assert(close.includes('opened = false'));
assert(!/content\.active\s*=\s*false|profileLoader\.active\s*=\s*false|shutdown\(/.test(close),
  'Ordinary hide must not destroy the retained browser/profile');
assert(read('native/Browser.qml').includes('lifecycleState: WebEngineView.LifecycleState.Active'));
console.log('PASS speed-first documentation and retained-browser source guards; not measured latency or release acceptance');
