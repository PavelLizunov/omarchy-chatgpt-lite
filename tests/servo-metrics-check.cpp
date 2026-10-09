#include "../native/servo/ServoMetrics.cpp"
#include <QCoreApplication>
#include <QThread>
#include <QTemporaryDir>
#include <sys/wait.h>
#include <sys/prctl.h>
#include <cassert>
#include <cstdio>

int main(int argc,char **argv) {
    QCoreApplication app(argc,argv);
    ServoMetrics monitor;
    assert(monitor.resources().value("state")=="inactive");
    monitor.setActive(true);
    assert(monitor.resources().value("state")=="unavailable");
    monitor.setEnginePath(QCoreApplication::applicationFilePath());
    monitor.setUnitName("../arbitrary.service");
    assert(monitor.resources().value("state")=="unavailable");
    if(argc!=2)return 2;
    monitor.setUnitName(QString::fromLocal8Bit(argv[1]));
    assert(monitor.resources().value("state")=="ready");
    assert(monitor.resources().value("processes").toInt()==1);
    assert(monitor.resources().value("pids").toList()==QVariantList{getpid()});
    assert(monitor.resources().value("rssMiB").toDouble()>0);
    assert(!monitor.resources().value("cpuPercent").isValid());
    QThread::msleep(100);monitor.sample();
    assert(monitor.resources().value("cpuPercent").isValid());
    const auto child = fork();
    assert(child >= 0);
    if (child == 0) {
        prctl(PR_SET_NAME, "Constellation", 0, 0, 0);
        sleep(1);
        _exit(0);
    }
    monitor.sample();
    assert(monitor.resources().value("processes").toInt() == 2);
    assert(!monitor.resources().value("cpuPercent").isValid());
    assert(monitor.resources().value("pids").toList().contains(child));
    int childStatus = 0;
    assert(waitpid(child, &childStatus, 0) == child);
    assert(WIFEXITED(childStatus) && WEXITSTATUS(childStatus) == 0);
    monitor.sample();
    assert(monitor.resources().value("processes").toInt() == 1);
    assert(!monitor.resources().value("cpuPercent").isValid());
    QThread::msleep(50);
    monitor.sample();
    assert(monitor.resources().value("cpuPercent").isValid());
    QTemporaryDir fixture;
    const auto link = fixture.path() + "/engine";
    assert(QFile::link(QCoreApplication::applicationFilePath(), link));
    monitor.setEnginePath(link);
    assert(monitor.resources().value("state") == "unavailable");
    monitor.setEnginePath(QCoreApplication::applicationFilePath());
    monitor.setUnitName("chatgpt-servo-missing-fixture.service");
    assert(monitor.resources().value("state")=="unavailable");
    assert(!monitor.resources().contains("rssMiB"));
    monitor.setUnitName(QString::fromLocal8Bit(argv[1]));
    monitor.setEnginePath("/usr/bin/true");
    assert(monitor.resources().value("state")=="unavailable");
    monitor.setActive(false);
    monitor.sample();
    assert(monitor.resources().value("state")=="inactive");
    puts("PASS exact-cgroup/executable/UID admission, renamed child/start baseline, symlink/missing unit/wrong binary, inactive and stale-value rejection");
}
