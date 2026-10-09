// Exact native monitor checks, no production process or profile involved.
#include "../native/resources.cpp"
#include <cassert>
#include <sys/wait.h>
#include <signal.h>
#include <QThread>

int main(int argc,char **argv) {
    QCoreApplication app(argc,argv);
    ResourceMonitor monitor;
    assert(monitor.pages().value("state")=="inactive");
    monitor.setRendererPids({1, getpid()});
    monitor.setActive(true);
    assert(monitor.pages().value("state")=="unavailable");
    auto child=fork();
    assert(child>=0);
    if(child==0) { sleep(10); _exit(0); }
    monitor.setRendererPids({child,child});
    assert(monitor.pages().value("state")=="ready");
    assert(monitor.pages().value("processes").toInt()==1);
    assert(monitor.pages().value("rssMiB").toDouble()>0);
    assert(!monitor.pages().value("cpuPercent").isValid());
    QThread::msleep(100);
    monitor.sample();
    assert(monitor.pages().value("cpuPercent").isValid());
    assert(monitor.pages().value("cpuPercent").toDouble()>=0);
    kill(child,SIGTERM); waitpid(child,nullptr,0);
    monitor.sample();
    assert(monitor.pages().value("state")=="unavailable");
    assert(!monitor.pages().contains("rssMiB"));
    monitor.setActive(false);
    monitor.sample();
    assert(monitor.pages().value("state")=="inactive");
    assert(monitor.shell().value("state")=="inactive");
    Sample s;
    assert(!readSample(-1,s)); assert(!readSample(0,s)); assert(!readSample(4194305,s));
    assert(readSample(getpid(),s)); assert(s.start>0 && s.ticks>=0);
    puts("PASS exact monitor: ownership/dedupe/RSS/CPU baseline/dead PID/inactive/bounds");
}
