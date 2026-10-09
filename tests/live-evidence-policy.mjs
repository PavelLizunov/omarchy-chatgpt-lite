import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
export function accepts(metadata, surface) {
  return metadata.captureKind === 'current-browser-item'
    && metadata.pageKind === 'account-capable-live-page'
    && metadata.imageInspected === true
    && surface === 'primary-pixels' && metadata.target === 'primary-browser';
}
const live = { captureKind: 'current-browser-item', pageKind: 'account-capable-live-page',
  imageInspected: true, target: 'primary-browser' };
assert(accepts(live, 'primary-pixels'));
assert(!accepts({ ...live, captureKind: 'reviewed-qml-fixture' }, 'primary-pixels'));
assert(!accepts({ ...live, imageInspected: false }, 'primary-pixels'));
for (const surface of ['auxiliary-pixels', 'native-chrome', 'menu-interaction']) assert(!accepts(live, surface));
if (process.argv.length === 4) {
  const ok = accepts(JSON.parse(readFileSync(process.argv[2])), process.argv[3]);
  console.log(ok ? 'PASS scoped live evidence' : 'NOT VERIFIED for requested live surface');
  process.exitCode = ok ? 0 : 1;
} else console.log('PASS live/fixture and surface-scope regressions; not model obedience');
