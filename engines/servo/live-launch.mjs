import {spawn,execFileSync} from 'node:child_process';
import {writeFileSync,readFileSync,existsSync,mkdirSync,lstatSync,unlinkSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('.',import.meta.url)).replace(/\/$/,'');
const tools='/home/slovn/.local/share/chatgpt-servo-probe-omhhV0yd/network-tools';
const runtime=process.argv[2]==='inner'?process.argv[3]:'/run/user/'+process.getuid()+'/chatgpt-servo-native';
const profile=root+'/live-isolated-profile';
process.umask(0o077);
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
if(process.argv[2]==='inner') {
 execFileSync('/usr/bin/ip',['link','set','lo','up']);
 writeFileSync(runtime+'/net-pid',String(process.pid),{mode:0o600});
 for(let i=0;i<40&&!existsSync(runtime+'/net-ready');i++)await sleep(100);
 if(!existsSync(runtime+'/net-ready'))throw Error('Private network readiness timeout');
 const args=['--die-with-parent','--new-session','--unshare-all','--share-net','--ro-bind','/usr','/usr','--symlink','usr/lib','/lib','--symlink','usr/lib','/lib64','--symlink','usr/bin','/bin','--dir','/etc','--ro-bind','/etc/ssl','/etc/ssl','--ro-bind','/etc/ca-certificates','/etc/ca-certificates','--ro-bind','/etc/fonts','/etc/fonts','--ro-bind','/etc/hosts','/etc/hosts','--ro-bind','/etc/nsswitch.conf','/etc/nsswitch.conf','--ro-bind','/etc/localtime','/etc/localtime','--dir','/run/systemd/resolve','--ro-bind',runtime+'/resolv.conf','/run/systemd/resolve/stub-resolv.conf','--ro-bind',runtime+'/resolv.conf','/etc/resolv.conf','--dir','/var/cache','--ro-bind','/var/cache/fontconfig','/var/cache/fontconfig','--proc','/proc','--dev','/dev','--tmpfs','/tmp','--dir','/opt','--ro-bind',root+'/engine','/opt/servo','--bind',profile,'/work','--bind',runtime,'/transport','--clearenv','--setenv','HOME','/work','--setenv','XDG_CONFIG_HOME','/work/config','--setenv','XDG_DATA_HOME','/work/data','--setenv','XDG_CACHE_HOME','/work/cache','--setenv','CHATGPT_SERVO_NATIVE_SOCKET','/transport/native.sock','--setenv','RUST_LOG','warn','--chdir','/opt/servo','/usr/bin/sh','-c','umask 077; exec "$@"','servo-engine','/opt/servo/servoshell','--headless','--multiprocess','--sandbox','--window-size','456x484','https://chatgpt.com/'];
 const engine=spawn('/usr/bin/bwrap',args,{stdio:['ignore','pipe','pipe']});
 // Discard page console output. Only lifecycle/boolean readiness is reported.
 engine.stdout.resume();engine.stderr.resume();
 process.on('SIGTERM',()=>engine.kill('SIGTERM'));
 const end=await new Promise(r=>engine.once('exit',(code,signal)=>r({code,signal})));
 console.log('SERVO_ENGINE_EXIT '+JSON.stringify(end));process.exitCode=end.code??(end.signal==='SIGTERM'?0:1);
} else {
 for(const dir of [runtime,profile]) {
  if(!existsSync(dir))mkdirSync(dir,{mode:0o700});
  const st=lstatSync(dir);if(!st.isDirectory()||st.isSymbolicLink()||st.uid!==process.getuid()||(st.mode&0o777)!==0o700)throw Error('Unsafe owned directory');
 }
 // Under the exclusive persistent systemd unit, a leftover socket is stale only
 // after the old cgroup has stopped. Never unlink a reachable listener.
 if(existsSync(runtime+'/native.sock')) {
  const st=lstatSync(runtime+'/native.sock');
  if(!st.isSocket()||st.isSymbolicLink()||st.uid!==process.getuid()||(st.mode&0o777)!==0o600)throw Error('Unsafe stale socket');
  // A connection probe would consume Servo's sole listener and terminate it.
  // Inspect the kernel socket registry instead; no connection or private pixels.
  const sockets=readFileSync('/proc/net/unix','utf8');
  if(sockets.length>1048576)throw Error('Socket registry bound exceeded');
  if(sockets.split('\n').some(line=>line.trim().split(/\s+/).at(-1)===runtime+'/native.sock'))throw Error('Existing native listener refuses replacement');
  unlinkSync(runtime+'/native.sock');
 }
 const hash=execFileSync('/usr/bin/sha256sum',[root+'/engine/servoshell'],{encoding:'utf8',timeout:10000}).split(' ')[0];
 const identity=JSON.parse(readFileSync(root+'/live-identity.json'));if(hash!==identity.binarySha256)throw Error('Servo candidate hash changed');
 for(const name of ['net-ready','net-pid'])if(existsSync(runtime+'/'+name))unlinkSync(runtime+'/'+name);
 writeFileSync(runtime+'/resolv.conf','nameserver 10.0.2.3\n',{mode:0o600});
 const child=spawn('/usr/bin/unshare',['--user','--map-root-user','--net','/usr/bin/node',root+'/live-launch.mjs','inner',runtime],{stdio:['ignore','pipe','pipe']});
 child.stdout.pipe(process.stdout);child.stderr.pipe(process.stderr);
 const done=new Promise(r=>child.once('exit',(code,signal)=>r({code,signal})));
 let network;
 process.on('SIGTERM',()=>{child.kill('SIGTERM');network?.kill('SIGTERM');});
 try {
  for(let i=0;i<40&&!existsSync(runtime+'/net-pid');i++)await sleep(100);
  if(!existsSync(runtime+'/net-pid'))throw Error('Network namespace unavailable');
  const pid=readFileSync(runtime+'/net-pid','utf8').trim();
  network=spawn(tools+'/usr/bin/slirp4netns',['--configure','--disable-host-loopback',pid,'tap0'],{env:{PATH:'/usr/bin',LD_LIBRARY_PATH:tools+'/usr/lib'},stdio:'ignore'});
  await sleep(300);if(network.exitCode!==null)throw Error('Private network failed');
  writeFileSync(runtime+'/net-ready','ready',{mode:0o600});
  const end=await done;process.exitCode=end.code??(end.signal==='SIGTERM'?0:1);
 } finally {child.kill('SIGTERM');network?.kill('SIGTERM');}
}
