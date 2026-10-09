import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

// Evidence gate, not a browser launcher or permission grant. No fixture-only completion.
export function validate(evidence, {settlement = false} = {}) {
  assert.equal(evidence.schema, 1);
  for (const name of ['nativeDraft', 'nativeAction', 'viewport', 'warmRetention', 'installed', 'loaded'])
    assert.equal(evidence[name], true, `Missing actual consumer evidence: ${name}`);
  assert.match(evidence.binarySha256, /^[a-f0-9]{64}$/);
  assert.equal(evidence.loadedEngine, 'SERVO_EXPERIMENTAL');
  if (settlement) {
    for (const name of ['workingChat', 'authentication', 'streamCancel', 'filesDownloads',
      'clipboard', 'relatedOAuth', 'composition', 'accessibility', 'persistentSession', 'workingChatResponsive'])
      assert.equal(evidence[name], true, `Unfinished task contract: ${name}`);
    assert.equal(evidence.matchedWorkload, true, 'No matched working-chat measurement');
    assert.equal(evidence.responseMeasurementScope, 'working-chat',
      'Fixture input does not establish real chat responsiveness');
    assert(Number.isFinite(evidence.wholeEngineSwapPssMiB) && evidence.wholeEngineSwapPssMiB >= 0,
      'Engine swap accounting missing');
    assert(Number.isFinite(evidence.wholeEngineMiB) && evidence.wholeEngineMiB >= 0
      && evidence.wholeEngineMiB + evidence.wholeEngineSwapPssMiB <= 200,
      'Whole-engine resident plus swapped target not reached');
    assert(Number.isFinite(evidence.baselineMiB) && evidence.baselineMiB >= 3 * (evidence.wholeEngineMiB + evidence.wholeEngineSwapPssMiB),
      'Threefold target not reached');
  }
}
if (process.argv[2] === '--self-test') {
  const fixture={schema:1,binarySha256:'a'.repeat(64),loadedEngine:'SERVO_EXPERIMENTAL',
    nativeDraft:true,nativeAction:true,viewport:true,warmRetention:true,installed:true,loaded:true};
  validate(fixture);
  for (const key of ['nativeDraft','nativeAction','viewport','warmRetention','installed','loaded'])
    assert.throws(()=>validate({...fixture,[key]:false}));
  assert.throws(()=>validate(fixture,{settlement:true}));
  assert.throws(()=>validate({...fixture,loadedEngine:'WPEWEBKIT'}));
  const full={...fixture,workingChat:true,authentication:true,streamCancel:true,filesDownloads:true,
    clipboard:true,relatedOAuth:true,composition:true,accessibility:true,persistentSession:true,
    workingChatResponsive:true,responseMeasurementScope:'working-chat',matchedWorkload:true,
    wholeEngineMiB:150,wholeEngineSwapPssMiB:0,baselineMiB:600};
  validate(full,{settlement:true});
  assert.throws(()=>validate({...full,workingChatResponsive:false},{settlement:true}));
  assert.throws(()=>validate({...full,responseMeasurementScope:'fixture'},{settlement:true}));
  assert.throws(()=>validate({...full,wholeEngineSwapPssMiB:100},{settlement:true}));
  assert.throws(()=>validate({...full,wholeEngineSwapPssMiB:undefined},{settlement:true}));
  assert.throws(()=>validate({...full,wholeEngineSwapPssMiB:-1},{settlement:true}));
  console.log('PASS consumer gate and rejection of incomplete/fixture-only settlement');
} else if (process.argv[2]) {
  validate(JSON.parse(readFileSync(process.argv[2])), {settlement:process.argv.includes('--settlement')});
  console.log(process.argv.includes('--settlement')?'Full requested acceptance PASS':'Intermediate consumer evidence PASS; full task remains open');
}
