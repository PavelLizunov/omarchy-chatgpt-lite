// Explicit finite experiments, no production service/config/profile access.
import {execFileSync,spawnSync} from 'node:child_process';
import {mkdirSync,writeFileSync,readFileSync,realpathSync,statSync,existsSync} from 'node:fs';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash,randomBytes} from 'node:crypto';
import assert from 'node:assert/strict';
const root=dirname(dirname(fileURLToPath(import.meta.url)));
const [destination,kind='synthetic']=process.argv.slice(2);
assert(destination?.startsWith('/') && ['synthetic','live'].includes(kind),'Absolute new evidence directory and synthetic/live mode required');
const parent=realpathSync(dirname(destination));
const output=join(parent,resolve(destination).split('/').at(-1));
assert(!existsSync(output),'Evidence path already exists; no silent overwrite/retry');
assert(!output.startsWith(root+'/'),'Evidence must remain outside source repository');
mkdirSync(output,{mode:0o700});
const binary=join(root,'build/memory-probe');assert(statSync(binary).isFile(),'Run make memory-probe first');
const qml=join(root,'tests',kind==='live'?'memory-live-probe.qml':'memory-probe.qml');
const matrix=kind==='live'?[['live',1024],['live',200]]:
    [['none',1024],['optional',1024],['core',1024],['all',1024],['none',200],['optional',200],['all',200]];
const rows=[];
const hash=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const identity=Object.fromEntries([binary,qml,join(root,'tests/memory-probe.cpp'),join(root,'native/Browser.qml')].map(p=>[p,hash(p)]));
writeFileSync(join(output,'budget.json'),JSON.stringify({kind,cases:matrix,maximumRuntimeSeconds:18,swapBytes:0,retries:0,productionConfigChanges:false,identity},null,2));
for(const [mode,limit]of matrix){
    const unit=`chatgpt-memory-probe-${randomBytes(6).toString('hex')}`;
    const data=join(output,unit);mkdirSync(data,{mode:0o700});
    const args=['--user','--unit='+unit,'--wait','--pipe','-p','RuntimeMaxSec=18','-p','TimeoutStopSec=3',
        '-p','MemoryMax='+limit+'M','-p','MemorySwapMax=0','-p','LimitCORE=0','-p','OOMPolicy=stop',
        '--setenv=QTWEBENGINE_CHROMIUM_FLAGS=','--setenv=XDG_DATA_HOME='+data+'/data','--setenv=XDG_CACHE_HOME='+data+'/cache',binary,qml,mode];
    const result=spawnSync('systemd-run',args,{encoding:'utf8',timeout:25000,maxBuffer:65536});
    writeFileSync(join(data,'stdout.log'),result.stdout||'');writeFileSync(join(data,'stderr.log'),result.stderr||'');
    let metadata={};
    try{
        metadata=Object.fromEntries(execFileSync('systemctl',['--user','show',unit+'.service','-p','Result','-p','MemoryPeak','-p','MemorySwapPeak','-p','ExecMainStatus','-p','ActiveState'],{encoding:'utf8',timeout:3000}).trim().split('\n').map(l=>l.split('=')));
    }catch{metadata={error:'unit metadata unavailable'};}
    let probe=null;
    for(const line of (result.stdout||'').split('\n'))if(line.startsWith('{')){try{probe=JSON.parse(line);}catch{}}
    const row={unit,mode,limitMiB:limit,exit:result.status,signal:result.signal,metadata,probe,
        acceptedFunctionalOptimization:kind==='synthetic'&&mode==='optional'&&probe?.coreWorks===true,
        originalSiteTargetVerified:false};
    rows.push(row);writeFileSync(join(data,'result.json'),JSON.stringify(row,null,2));console.log(JSON.stringify(row));
    if(metadata.ActiveState==='active'||result.error){
        // Stop only the recorded task-owned unit on harness timeout/failure.
        spawnSync('systemctl',['--user','stop',unit+'.service'],{timeout:5000});
        throw Error('Unfinished trial; no automatic retry');
    }
    if(probe){
        assert(probe.cgroup?.state==='ready','In-process cgroup evidence required');
        assert.equal(Number(probe.cgroup['memory.max']),limit*1048576,'Actual configured cap');
        assert.equal(Number(probe.cgroup['memory.swap.max']),0,'No hidden swap workaround');
        assert(probe.rendererPid>0&&probe.rendererRssMiB>0,'Renderer identity/RSS unavailable');
    }
}
writeFileSync(join(output,'results.json'),JSON.stringify({rows,identity,limits:'Synthetic ablation is not original-site memory reduction. Anonymous live load success is not authenticated function/design/streaming acceptance. RSS shared mappings differ from cgroup charge.'},null,2));
if(kind==='synthetic'){
    const get=mode=>rows.find(r=>r.mode===mode&&r.limitMiB===1024)?.probe;
    assert(get('none')?.coreWorks&&get('optional')?.coreWorks&&!get('optional')?.optionalWorks);
    assert(get('core')&&!get('core').coreWorks&&get('all')&&!get('all').coreWorks,'Broken action must fail despite SUCCEEDED');
}
console.log('Recorded bounded trials. Original-site200MiB target not established.');
