#pragma once
#include <QFile>
#include <sys/stat.h>
#include <unistd.h>

struct Sample { qint64 pid=0, parent=0, start=0, ticks=0, rss=0; };
static bool readSample(qint64 pid, Sample &s) {
    if (pid <= 0 || pid > 4194304) return false;
    const auto path = QString("/proc/%1").arg(pid);
    struct stat st{};
    if (::stat(path.toLocal8Bit().constData(), &st) || st.st_uid != getuid()) return false;
    QFile file(path + "/stat");
    if (!file.open(QIODevice::ReadOnly)) return false;
    auto data = file.read(4097);
    if (data.isEmpty() || data.size() > 4096) return false;
    const auto end = data.lastIndexOf(')');
    if (end < 0) return false;
    const auto fields = data.mid(end+2).simplified().split(' ');
    if (fields.size() < 22 || fields[0] == "Z" || fields[0] == "X") return false;
    bool ok=true, valid=false;
    auto number = [&](int i) { auto n=fields[i].toLongLong(&valid); ok &= valid; return n; };
    s.pid=pid; s.parent=number(1); s.ticks=number(11)+number(12);
    s.start=number(19); s.rss=number(21);
    return ok && s.ticks>=0 && s.start>0 && s.rss>=0;
}
