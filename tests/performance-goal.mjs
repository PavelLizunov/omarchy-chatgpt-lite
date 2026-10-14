import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

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

const wpeExpression = service.match(/property bool useWpe: ([^\n]+)/)?.[1];
assert(wpeExpression, 'Engine selection binding is required');
const servoExpression = service.match(/property bool useServo: ([^\n]+)/)?.[1];
assert(servoExpression, 'Servo selection binding is required');
const chooseWpe = new Function('fixtureMode', 'useServo', 'Quickshell', `return ${wpeExpression}`);
const chooseServo = new Function('fixtureMode', 'Quickshell', `return ${servoExpression}`);
// Quickshell.env returns null for an unset variable, not an empty string.
for (const [fixture, socket, engine, expected] of [
  [false, null, null, 'wpe'], [false, '', '', 'wpe'],
  [false, null, 'chromium', 'chromium'], [false, '', 'chromium', 'chromium'],
  [false, null, 'unknown', 'wpe'], [false, '/owned/socket', 'chromium', 'servo'],
  [true, '/owned/socket', 'chromium', 'chromium'], [true, null, null, 'chromium']
]) {
  const shell = {env: name => {
    assert(['CHATGPT_LITE_ENGINE', 'CHATGPT_SERVO_NATIVE_SOCKET'].includes(name));
    return name === 'CHATGPT_LITE_ENGINE' ? engine : socket;
  }};
  const servo = chooseServo(fixture, shell);
  assert.equal(servo ? 'servo' : chooseWpe(fixture, servo, shell) ? 'wpe' : 'chromium', expected);
}

const launcher = resolve(root, 'native/chromium-env.sh');
const args = ['two words', '', '$(not-a-command)', '--literal=;'];
for (const previous of ['', '--lang=en-US']) {
  const run = spawnSync(launcher, [process.execPath, '-e',
    'console.log(JSON.stringify({engine:process.env.CHATGPT_LITE_ENGINE,flags:process.env.QTWEBENGINE_CHROMIUM_FLAGS,args:process.argv.slice(1)}))',
    '--', ...args], {encoding: 'utf8', timeout: 5000,
    env: {...process.env, CHATGPT_LITE_ENGINE: 'old', QTWEBENGINE_CHROMIUM_FLAGS: previous}});
  assert.equal(run.status, 0, run.stderr);
  assert.deepEqual(JSON.parse(run.stdout), {engine: 'chromium',
    flags: `${previous ? previous + ' ' : ''}--site-per-process`, args});
}
assert.equal(spawnSync(launcher, [], {timeout: 5000}).status, 64);
console.log('PASS speed-first guards, explicit engine selection and native launcher argv/environment; not measured latency or release acceptance');
