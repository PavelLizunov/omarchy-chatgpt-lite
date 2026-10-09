// Isolated offscreen performance experiment, never the shared production shell.
// Synthetic resources only; no production profile, account data or captures.
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#include <QtWebEngineQuick/qquickwebengineprofile.h>
#include <QtWebEngineCore/qwebengineurlrequestinterceptor.h>
#include <QtWebEngineCore/qwebengineurlrequestinfo.h>
#include <QGuiApplication>
#include <QQuickView>
#include <QQuickItem>
#include <QQmlContext>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QElapsedTimer>
#include <QFile>
#include <QDir>
#include <atomic>
#include <unistd.h>

class Gate final : public QWebEngineUrlRequestInterceptor {
public:
    QString mode;
    quint16 port=0;
    std::atomic<int> blocked{0};
    void interceptRequest(QWebEngineUrlRequestInfo &info) override {
        const auto url=info.requestUrl();
        if(mode=="live") {
            // Original site/providers, no filters or security overrides in live mode.
            if(url.scheme()!="https" && url.scheme()!="data" && url.scheme()!="blob") info.block(true);
            return;
        }
        // Exact inert origin only. Fail closed for unexpected external traffic.
        if(url.scheme()!="http" || url.host()!="127.0.0.1" || url.port()!=port) { info.block(true); return; }
        const bool script=info.resourceType()==QWebEngineUrlRequestInfo::ResourceTypeScript;
        const bool deny=script && (mode=="all" || (mode=="optional" && url.path()=="/optional.js")
            || (mode=="core" && url.path()=="/core.js"));
        if(deny) { blocked++; info.block(true); }
    }
};

static QJsonObject cgroupMemory() {
    QFile membership("/proc/self/cgroup");
    if(!membership.open(QIODevice::ReadOnly)) return {{"state","unavailable"}};
    const auto data=membership.read(4096);
    QString relative;
    for(const auto &line:data.split('\n')) if(line.startsWith("0::")) relative=QString::fromUtf8(line.mid(3));
    if(relative.isEmpty() || relative.contains("..")) return {{"state","unavailable"}};
    const auto base=QString("/sys/fs/cgroup")+relative;
    QJsonObject result{{"state","ready"}};
    for(const auto &name:QStringList{"memory.current","memory.peak","memory.max","memory.swap.current","memory.swap.max","memory.events"}) {
        QFile file(base+"/"+name);
        if(!file.open(QIODevice::ReadOnly)) return {{"state","unavailable"}};
        result.insert(name,QString::fromUtf8(file.read(4096)).trimmed());
    }
    return result;
}

static qint64 rssKiB(qint64 pid) {
    QFile file(QString("/proc/%1/status").arg(pid));
    if(!file.open(QIODevice::ReadOnly)) return -1;
    const auto data=file.read(65536);
    for(const auto &line:data.split('\n')) if(line.startsWith("VmRSS:")) return line.simplified().split(' ').value(1).toLongLong();
    return -1;
}
int main(int argc,char **argv) {
    qputenv("QT_QPA_PLATFORM","offscreen");
    qputenv("QT_QUICK_BACKEND","software");
    QtWebEngineQuick::initialize();
    QGuiApplication app(argc,argv);
    if(argc!=3) return 2;
    const QString mode=QString::fromLocal8Bit(argv[2]);
    if(!QStringList{"none","optional","core","all","live"}.contains(mode)) return 2;
    QElapsedTimer elapsed; elapsed.start();
    QTcpServer server;
    if(!server.listen(QHostAddress::LocalHost,0)) return 3;
    Gate gate; gate.mode=mode; gate.port=server.serverPort();
    const QByteArray html="<!doctype html><meta http-equiv='Content-Security-Policy' content=\"default-src 'self'; script-src 'self'; style-src 'none'\"><input id='draft' value='Inert draft'><button id='action'>Inert action</button><script src='/core.js'></script><script src='/optional.js'></script>";
    const QByteArray core="window.coreBuffers=Array.from({length:32},()=>{let x=new Uint8Array(1024*1024);x.fill(7);return x});window.actions=0;document.getElementById('action').onclick=()=>window.actions++;window.coreReady=true;";
    const QByteArray optional="window.optionalBuffers=Array.from({length:128},()=>{let x=new Uint8Array(1024*1024);x.fill(3);return x});window.optionalReady=true;";
    QObject::connect(&server,&QTcpServer::newConnection,&app,[&] {
        while(server.hasPendingConnections()) {
            auto *socket=server.nextPendingConnection(); socket->setParent(&server);
            auto *deadline=new QTimer(socket); deadline->setSingleShot(true); deadline->start(2000);
            QObject::connect(deadline,&QTimer::timeout,socket,&QTcpSocket::abort);
            QObject::connect(socket,&QTcpSocket::disconnected,socket,&QObject::deleteLater);
            QObject::connect(socket,&QTcpSocket::readyRead,socket,[&,socket] {
                auto data=socket->property("request").toByteArray()+socket->readAll();
                if(data.size()>8192) {socket->abort(); return;}
                socket->setProperty("request",data);
                if(!data.contains("\r\n\r\n")) return;
                const auto path=data.split(' ').value(1);
                const auto body=path=="/"?html:path=="/core.js"?core:path=="/optional.js"?optional:QByteArray();
                const auto mime=path=="/"?"text/html":"application/javascript";
                socket->write("HTTP/1.1 200 OK\r\nContent-Type: "+QByteArray(mime)+"\r\nContent-Length: "+QByteArray::number(body.size())+"\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"+body);
                socket->disconnectFromHost();
            });
        }
    });
    QQuickWebEngineProfile profile; // Always off-record; never read the production profile.
    profile.setUrlRequestInterceptor(&gate);
    QQuickView view;
    view.rootContext()->setContextProperty("probeProfile",&profile);
    view.rootContext()->setContextProperty("probeUrl",QUrl(QString("http://127.0.0.1:%1/").arg(gate.port)));
    view.setResizeMode(QQuickView::SizeRootObjectToView); view.resize(460,560);
    view.setSource(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if(view.status()==QQuickView::Error || !view.rootObject()) return 4;
    view.show(); // offscreen QPA; no compositor connection or visible desktop window.
    QTimer deadline; deadline.setSingleShot(true); deadline.start(12000);
    QObject::connect(&deadline,&QTimer::timeout,&app,[&]{app.exit(5);});
    QTimer poll; poll.setInterval(50);
    bool completing=false;
    QObject::connect(&poll,&QTimer::timeout,&app,[&] {
        auto *root=view.rootObject();
        if(completing || root->property("loadState").toString()!="SUCCEEDED" || elapsed.elapsed()<2000) return;
        completing=true;
        QMetaObject::invokeMethod(root,"verifyFixture");
        QTimer::singleShot(1500,&app,[&,root] {
            auto *browser=root->findChild<QQuickItem*>("chatgptBrowser");
            const auto pid=browser ? browser->property("renderProcessPid").toLongLong() : 0;
            if(pid<=0 || rssKiB(pid)<0) { app.exit(6); return; } // Missing identity is not zero memory.
            QJsonObject result{{"surface",mode=="live"?"anonymous-original-site-load-only":"synthetic-local-resource-experiment"},{"mode",mode},
                {"loadState",root->property("loadState").toString()},
                {"loadErrorCode",root->property("loadErrorCode").toInt()},{"coreWorks",root->property("coreWorks").toBool()},
                {"optionalWorks",root->property("optionalWorks").toBool()},
                {"rendererPid",pid},{"rendererRssMiB",rssKiB(pid)/1024.0},
                {"probeRssMiB",rssKiB(getpid())/1024.0},{"blockedScripts",gate.blocked.load()},
                {"elapsedMs",elapsed.elapsed()},{"productionMemoryAcceptance",false},{"cgroup",cgroupMemory()}};
            const auto json=QJsonDocument(result).toJson(QJsonDocument::Compact);
            fwrite(json.constData(),1,json.size(),stdout);fputc('\n',stdout);fflush(stdout);
            app.quit();
        });
    });
    poll.start();
    return app.exec();
}
