import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const entry = readFileSync(new URL('../native/ChromiumService.qml', import.meta.url), 'utf8');
assert.match(entry, /Service\s*\{/);
assert.match(entry, /useServo:\s*false/);
assert.match(entry, /useWpe:\s*false/);
assert.doesNotMatch(entry, /fixtureMode:|hostCompatible:|suppliedProfile:|dataRoot:|cacheRoot:/);
const service = readFileSync(new URL('../native/Service.qml', import.meta.url), 'utf8');
assert.match(service, /!useWpe && !useServo && !hostCompatible/);
assert.match(service, /HOST_ARGUMENTS_EMPTY/);
console.log('PASS explicit Chromium entry retains host guard and existing persistent profile; not live-site acceptance');
