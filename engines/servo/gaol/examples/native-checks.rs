extern crate gaol;
extern crate libc;
use gaol::profile::{Operation,PathPattern,Profile};
use gaol::sandbox::{ChildSandbox,ChildSandboxMethods,Command,Sandbox,SandboxMethods};
use std::ffi::CString;
use std::path::PathBuf;
use std::env;
fn profile()->Profile { Profile::new(vec![Operation::FileReadAll(PathPattern::Subpath(PathBuf::from("/data")))]).unwrap() }
fn child(mode:&str) {
    let file=CString::new("/data/readme").unwrap();
    if mode=="inherited-write" { let fd=unsafe{libc::open(file.as_ptr(),libc::O_RDWR)};assert!(fd>=0); }
    if mode=="inherited-write" { assert!(ChildSandbox::new(profile()).activate().is_err());return; }
    ChildSandbox::new(profile()).activate().unwrap();
    unsafe {
        match mode {
            "ipc-memory"=>{let n=CString::new("native-ipc").unwrap();let fd=libc::memfd_create(n.as_ptr(),libc::MFD_CLOEXEC);assert!(fd>=0);assert_eq!(libc::ftruncate(fd,9216),0);libc::close(fd);},
            "read"=>{let fd=libc::open(file.as_ptr(),libc::O_RDONLY);assert!(fd>=0);let mut b=[0u8;4];assert_eq!(libc::read(fd,b.as_mut_ptr() as *mut _,4),4);assert_eq!(&b,b"safe");libc::close(fd);},
            "cwd"=>{let mut b=[0i8;64];assert!(!libc::getcwd(b.as_mut_ptr(),64).is_null());assert_eq!(std::ffi::CStr::from_ptr(b.as_ptr()).to_bytes(),b"/");},
            "clone3-fallback"=>{assert_eq!(libc::syscall(libc::SYS_clone3,0usize,0usize),-1);assert_eq!(*libc::__errno_location(),libc::ENOSYS);},
            "network-denied"=>{libc::socket(libc::AF_INET,libc::SOCK_STREAM,0);},
            "write-open-denied"=>{libc::open(file.as_ptr(),libc::O_WRONLY);},
            "limit-change-denied"=>{let limit=libc::rlimit{rlim_cur:1,rlim_max:1};libc::prlimit(0,libc::RLIMIT_NOFILE,&limit,std::ptr::null_mut());},
            "readonly-truncate"=>{let fd=libc::open(file.as_ptr(),libc::O_RDONLY);assert!(fd>=0);assert_eq!(libc::ftruncate(fd,0),-1);libc::close(fd);},
            "ipc-size-ceiling"=>{let n=CString::new("native-ipc").unwrap();let fd=libc::memfd_create(n.as_ptr(),libc::MFD_CLOEXEC);assert!(fd>=0);assert_eq!(libc::ftruncate(fd,65*1024*1024),-1);assert_eq!(*libc::__errno_location(),libc::EFBIG);},
            "prctl-danger-denied"=>{libc::prctl(libc::PR_SET_DUMPABLE,1,0,0,0);},
            _=>panic!("Unknown mode")
        }
    }
}
fn main(){
 let args:Vec<_>=env::args().collect();if args.len()==2 {child(&args[1]);return;}
 for (mode,expected) in [("ipc-memory",true),("read",true),("cwd",true),("clone3-fallback",true),("inherited-write",true),("readonly-truncate",true),("network-denied",false),("write-open-denied",false),("limit-change-denied",false),("ipc-size-ceiling",true),("prctl-danger-denied",false)] {
  let status=Sandbox::new(profile()).start(Command::me().unwrap().arg(mode)).unwrap().wait().unwrap();
  assert_eq!(status.success(),expected,"{}",mode);println!("CHECK {} PASS success={}",mode,status.success());
 }
}
