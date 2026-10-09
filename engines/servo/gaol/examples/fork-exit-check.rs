extern crate gaol;
extern crate libc;
use gaol::profile::{Operation, PathPattern, Profile};
use std::path::PathBuf;
fn profile() -> Profile {
    Profile::new(vec![Operation::FileReadAll(PathPattern::Subpath(PathBuf::from("/data")))]).unwrap()
}
use gaol::sandbox::{ChildSandbox, ChildSandboxMethods, Command, Sandbox, SandboxMethods};
use std::sync::atomic::{AtomicI32, Ordering};
use std::time::{Duration, Instant};
static PARENT: AtomicI32 = AtomicI32::new(0);
extern "C" fn inherited_exit_handler() {
    if unsafe { libc::getpid() } != PARENT.load(Ordering::SeqCst) {
        // Stand-in for an inherited allocator/runtime lock held by a vanished
        // sibling thread. An intermediate fork child must not call this.
        unsafe { libc::sleep(30); }
    }
}
fn main() {
    if std::env::args().nth(1).as_deref() == Some("child") {
        ChildSandbox::new(profile()).activate().unwrap();
        return;
    }
    PARENT.store(unsafe { libc::getpid() }, Ordering::SeqCst);
    assert_eq!(unsafe { libc::atexit(inherited_exit_handler) }, 0);
    let sibling = std::thread::spawn(|| std::thread::sleep(Duration::from_secs(2)));
    let process = Sandbox::new(profile())
        .start(Command::me().unwrap().arg("child")).unwrap();
    let deadline = Instant::now() + Duration::from_secs(1);
    let mut reaped = Vec::new();
    while Instant::now() < deadline {
        let mut status = 0;
        let pid = unsafe { libc::waitpid(-1, &mut status, libc::WNOHANG) };
        if pid > 0 {
            assert!(libc::WIFEXITED(status) && libc::WEXITSTATUS(status) == 0);
            reaped.push(pid);
        } else if pid < 0 { break; }
        std::thread::sleep(Duration::from_millis(5));
    }
    let children = std::fs::read_to_string(format!("/proc/self/task/{}/children", unsafe {libc::getpid()})).unwrap();
    assert!(children.trim().is_empty(), "intermediate child still alive: {}", children.trim());
    assert!(reaped.contains(&process.pid), "sandbox content not reaped");
    sibling.join().unwrap();
    println!("PASS multithreaded sandbox launch bypasses inherited exit handlers and reaps intermediate/content children");
}
