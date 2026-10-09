#include <QCoreApplication>
#include <QFile>
#include <QElapsedTimer>
#include <QTimer>
#include <QQmlExtensionPlugin>
#include <qqml.h>
#include <QVariantMap>
#include <QSet>
#include <sys/stat.h>
#include <unistd.h>
#include <cmath>

#include "resource-sample.h"
class ResourceMonitor : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(QVariantList rendererPids READ rendererPids WRITE setRendererPids NOTIFY rendererPidsChanged)
    Q_PROPERTY(QVariantMap pages READ pages NOTIFY updated)
    Q_PROPERTY(QVariantMap shell READ shell NOTIFY updated)
public:
    explicit ResourceMonitor(QObject *parent=nullptr):QObject(parent) {
        clock.start(); timer.setInterval(2000);
        connect(&timer,&QTimer::timeout,this,&ResourceMonitor::sample);
    }
    bool active() const { return enabled; }
    QVariantList rendererPids() const { return pids; }
    QVariantMap pages() const { return pageData; }
    QVariantMap shell() const { return shellData; }
    void setActive(bool value) {
        if (enabled==value) return;
        enabled=value; timer.stop(); previous.clear(); lastTime=0;
        pageData={{"state","inactive"}}; shellData=pageData;
        emit activeChanged(); emit updated();
        if (enabled) { sample(); timer.start(); }
    }
    void setRendererPids(const QVariantList &value) {
        if (pids==value) return;
        // At most primary+3 linked renderers. Never enumerate unrelated processes.
        pids=value.mid(0,4); previous.clear(); lastTime=0;
        emit rendererPidsChanged();
        if (enabled) sample();
    }
    Q_INVOKABLE void sample() {
        if (!enabled) return;
        const auto now=clock.elapsed(); const auto dt=now-lastTime;
        QHash<qint64,Sample> current;
        QSet<qint64> requested;
        bool missing=false;
        for (const auto &v:pids) {
            bool ok=false; auto pid=v.toLongLong(&ok);
            if (!ok || pid<=0) { missing=true; continue; }
            requested.insert(pid);
        }
        if (requested.isEmpty()) missing=true;
        for (auto pid:requested) {
            Sample s;
            if (!readSample(pid,s) || !ownedDescendant(s)) { missing=true; continue; }
            current.insert(pid,s);
        }
        pageData=aggregate(current,dt,missing);
        Sample host; QHash<qint64,Sample> shellSample;
        if (readSample(getpid(),host)) shellSample.insert(host.pid,host);
        shellData=aggregate(shellSample,dt,shellSample.isEmpty());
        current.insert(shellSample); previous=current; lastTime=now;
        emit updated();
    }
signals:
    void activeChanged(); void rendererPidsChanged(); void updated();
private:
    bool ownedDescendant(const Sample &first) const {
        auto parent=first.parent;
        for (int i=0;i<16 && parent>1;i++) {
            if (parent==getpid()) return first.pid!=getpid();
            Sample s; if (!readSample(parent,s) || s.parent==parent) return false;
            parent=s.parent;
        }
        return false;
    }
    QVariantMap aggregate(const QHash<qint64,Sample> &samples,qint64 dt,bool missing) const {
        if (missing || samples.isEmpty()) return {{"state","unavailable"},{"processes",samples.size()}};
        qint64 rss=0,ticks=0; bool cpuReady=lastTime>0 && dt>0 && dt<=10000;
        for (auto it=samples.cbegin();it!=samples.cend();++it) {
            rss+=it->rss;
            auto old=previous.constFind(it.key());
            if (old==previous.cend() || old->start!=it->start || old->ticks>it->ticks) cpuReady=false;
            else ticks+=it->ticks-old->ticks;
        }
        const auto hz=sysconf(_SC_CLK_TCK),size=sysconf(_SC_PAGESIZE);
        if(hz<=0||size<=0) return {{"state","unavailable"}};
        QVariant cpu;
        if(cpuReady) cpu=100.0*static_cast<double>(ticks)/hz/(static_cast<double>(dt)/1000.0);
        return {{"state","ready"},{"rssMiB",static_cast<double>(rss)*size/1048576.0},
            {"cpuPercent",cpu},{"processes",samples.size()}};
    }
    bool enabled=false; QVariantList pids; QTimer timer; QElapsedTimer clock;
    qint64 lastTime=0; QHash<qint64,Sample> previous;
    QVariantMap pageData{{"state","inactive"}},shellData{{"state","inactive"}};
};
class ResourcesPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<ResourceMonitor>(uri,1,0,"ResourceMonitor"); }
};
#include "resources.moc"
