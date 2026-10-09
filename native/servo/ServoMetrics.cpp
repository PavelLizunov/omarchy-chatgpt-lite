#include <QObject>
#include <QTimer>
#include <QElapsedTimer>
#include <QVariantMap>
#include <QVariantList>
#include <QSet>
#include <QRegularExpression>
#include <QQmlExtensionPlugin>
#include <qqml.h>
#include "../resource-sample.h"

// Separately supervised Servo is not a shell descendant. Admit only its exact
// user cgroup and executable inode, never enumerate the machine's process table.
class ServoMetrics : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY changed)
    Q_PROPERTY(QString unitName READ unitName WRITE setUnitName NOTIFY changed)
    Q_PROPERTY(QString enginePath READ enginePath WRITE setEnginePath NOTIFY changed)
    Q_PROPERTY(QVariantMap resources READ resources NOTIFY changed)
public:
    explicit ServoMetrics(QObject *parent=nullptr):QObject(parent) {
        clock.start();timer.setInterval(2000);
        connect(&timer,&QTimer::timeout,this,&ServoMetrics::sample);
    }
    bool active() const { return enabled; }
    QString unitName() const { return unit; }
    QString enginePath() const { return engine; }
    QVariantMap resources() const { return data; }
    void setUnitName(const QString &value) { if(unit!=value){unit=value;reset();} }
    void setEnginePath(const QString &value) { if(engine!=value){engine=value;reset();} }
    void setActive(bool value) {
        if(enabled==value)return;
        enabled=value;reset();timer.stop();if(enabled)timer.start();
    }
    Q_INVOKABLE void sample() {
        if(!enabled)return;
        data={{"state","unavailable"},{"scope","servo-engine"}};
        struct stat binary{};
        const auto encoded=engine.toLocal8Bit();
        const auto pattern=QRegularExpression(QStringLiteral("^chatgpt-servo-[a-z0-9-]{1,100}\\.service$"));
        if(!pattern.match(unit).hasMatch() || !engine.startsWith('/') ||
            ::lstat(encoded.constData(),&binary) || !S_ISREG(binary.st_mode) ||
            binary.st_uid!=getuid() || (binary.st_mode&0022)) { unavailable();return; }
        const auto relative=QString("/user.slice/user-%1.slice/user@%1.service/app.slice/%2").arg(getuid()).arg(unit);
        QByteArray membership;
        if(!bounded("/sys/fs/cgroup"+relative+"/cgroup.procs",membership,65536)){unavailable();return;}
        const auto entries=membership.simplified().split(' ');
        if(entries.size()>256){unavailable();return;}
        QSet<qint64> requested;
        for(const auto &entry:entries) {
            bool ok=false;const auto pid=entry.toLongLong(&ok);
            if(!ok || pid<=0 || pid>4194304){unavailable();return;}
            requested.insert(pid);
        }
        QHash<qint64,Sample> current;
        for(const auto pid:requested) {
            const auto proc=QString("/proc/%1").arg(pid);
            struct stat executable{};
            if(::stat((proc+"/exe").toLocal8Bit().constData(),&executable))continue;
            if(executable.st_dev!=binary.st_dev || executable.st_ino!=binary.st_ino)continue;
            Sample before,after;QByteArray group;
            if(!readSample(pid,before) || !bounded(proc+"/cgroup",group,4096) ||
                group.trimmed()!=QByteArray("0::")+relative.toUtf8() || !readSample(pid,after) ||
                before.start!=after.start || ::stat((proc+"/exe").toLocal8Bit().constData(),&executable) ||
                executable.st_dev!=binary.st_dev || executable.st_ino!=binary.st_ino) {unavailable();return;}
            current.insert(pid,after);
            if(current.size()>32){unavailable();return;}
        }
        if(current.isEmpty()){unavailable();return;}
        const auto now=clock.elapsed(),dt=now-lastTime;
        qint64 rss=0,ticks=0;bool cpuReady=lastTime>=0 && dt>0 && dt<=10000 && current.size()==previous.size();
        QVariantList pids;
        for(auto it=current.cbegin();it!=current.cend();++it) {
            rss+=it->rss;pids.append(it.key());
            const auto old=previous.constFind(it.key());
            if(old==previous.cend() || old->start!=it->start || old->ticks>it->ticks)cpuReady=false;
            else ticks+=it->ticks-old->ticks;
        }
        const auto hz=sysconf(_SC_CLK_TCK),page=sysconf(_SC_PAGESIZE);
        if(hz<=0||page<=0){unavailable();return;}
        QVariant cpu;if(cpuReady)cpu=100.0*double(ticks)/hz/(double(dt)/1000.0);
        data={{"state","ready"},{"scope","servo-engine"},{"rssMiB",double(rss)*page/1048576.0},
            {"cpuPercent",cpu},{"processes",current.size()},{"pids",pids}};
        previous=current;lastTime=now;emit changed();
    }
signals:
    void changed();
private:
    static bool bounded(const QString &path,QByteArray &out,qint64 limit) {
        QFile f(path);if(!f.open(QIODevice::ReadOnly))return false;
        out=f.read(limit+1);return !out.isEmpty()&&out.size()<=limit;
    }
    void unavailable(){previous.clear();lastTime=-1;emit changed();}
    void reset(){previous.clear();lastTime=-1;data={{"state",enabled?"unavailable":"inactive"},{"scope","servo-engine"}};if(enabled)sample();else emit changed();}
    QString unit,engine;bool enabled=false;QTimer timer;QElapsedTimer clock;
    qint64 lastTime=-1;QHash<qint64,Sample> previous;
    QVariantMap data{{"state","inactive"},{"scope","servo-engine"}};
};
class ServoMetricsPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override {qmlRegisterType<ServoMetrics>(uri,1,0,"ServoMetrics");}
};
#include "ServoMetrics.moc"
