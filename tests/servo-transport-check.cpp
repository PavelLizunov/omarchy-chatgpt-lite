#include <QGuiApplication>
#include <QLocalServer>
#include <QTemporaryDir>
#include <QElapsedTimer>
#include <QThread>
#include <QFile>
#include <cassert>
#include <cstdio>
#include "../native/servo/ServoView.cpp"

static bool waitFor(const std::function<bool()> &test) {
    QElapsedTimer clock; clock.start();
    while (!test() && clock.elapsed()<1500) { QCoreApplication::processEvents(); QThread::msleep(1); }
    return test();
}
static QByteArray frame(quint32 width,quint32 height,quint32 length) {
    QByteArray packet("SV01");
    for(auto n:{width,height,length}) { char bytes[4];qToBigEndian(n,bytes);packet.append(bytes,4); }
    packet.append(length,'\0'); return packet;
}
int main(int argc,char **argv) {
    qputenv("QT_QPA_PLATFORM","offscreen");
    QGuiApplication app(argc,argv);
    QTemporaryDir directory;
    assert(directory.isValid());
    const QString path=directory.path()+"/transport.sock";
    QLocalServer server; server.setSocketOptions(QLocalServer::UserAccessOption);
    assert(server.listen(path));
    assert(QFile::setPermissions(path,QFile::ReadOwner|QFile::WriteOwner));
    ServoView view; view.setWidth(456);view.setHeight(484);view.setSocketPath(path);
    assert(waitFor([&]{return server.hasPendingConnections();}));
    auto *peer=server.nextPendingConnection();
    assert(waitFor([&]{return peer->bytesAvailable()>4;}));
    auto command=peer->readAll();
    assert(command.mid(4).contains("Resize"));
    view.reload();
    assert(waitFor([&]{return peer->bytesAvailable()>4;}));
    assert(peer->readAll().contains("Reload"));
    QMouseEvent rightDown(QEvent::MouseButtonPress,QPointF(10,10),QPointF(10,10),Qt::RightButton,Qt::RightButton,Qt::NoModifier);
    QCoreApplication::sendEvent(&view,&rightDown);
    assert(waitFor([&]{return peer->bytesAvailable()>4;}));
    assert(peer->readAll().contains("Secondary"));
    auto valid=frame(2,2,16);peer->write(valid.left(7));peer->flush();
    QCoreApplication::processEvents();assert(!view.frameReady());
    peer->write(valid.mid(7));peer->flush();
    assert(waitFor([&]{return view.frameReady();}));assert(view.frameSerial()==1);
    peer->write(valid+valid);peer->flush();assert(waitFor([&]{return view.frameSerial()==3;}));
    // A post-reload frame must replace the full image, not retain an old side strip.
    const auto solid = [](char red,char green,char blue) {
        auto packet=frame(2,2,16);
        for(int i=16;i<packet.size();i+=4) {
            packet[i]=red;packet[i+1]=green;packet[i+2]=blue;packet[i+3]=char(255);
        }
        return packet;
    };
    peer->write(solid(char(240),char(32),char(32)));peer->flush();
    assert(waitFor([&]{return view.frameSerial()==4;}));
    view.reload();
    assert(waitFor([&]{return peer->bytesAvailable()>4;}));
    assert(peer->readAll().contains("Reload"));
    peer->write(solid(char(32),char(240),char(64)));peer->flush();
    assert(waitFor([&]{return view.frameSerial()==5;}));
    QImage painted(456,484,QImage::Format_RGBA8888);painted.fill(Qt::red);
    { QPainter painter(&painted);view.paint(&painter); }
    for(const auto point:{QPoint(0,0),QPoint(15,100),QPoint(455,483)})
        assert(painted.pixelColor(point)==QColor(32,240,64,255));
    peer->write(frame(2049,1,4));peer->flush();
    assert(waitFor([&]{return !view.transportError().isEmpty();}));assert(!view.frameReady());
    view.setSocketPath("");assert(view.transportError().isEmpty());assert(!view.frameReady());
    view.setSocketPath(path);
    assert(waitFor([&]{return server.hasPendingConnections();}));
    auto *reconnected=server.nextPendingConnection();
    reconnected->write(valid);reconnected->flush();
    assert(waitFor([&]{return view.frameReady();}));
    ServoView refused;refused.setSocketPath(directory.path()+"/missing");assert(!refused.transportError().isEmpty());
    const QString ordinary=directory.path()+"/regular";QFile file(ordinary);assert(file.open(QIODevice::WriteOnly));file.close();
    refused.setSocketPath(ordinary);assert(!refused.transportError().isEmpty());
    assert(QFile::setPermissions(path,QFile::ReadOwner|QFile::WriteOwner|QFile::ReadGroup));
    refused.setSocketPath(path);assert(!refused.transportError().isEmpty());
    // Destruction of a connected member socket must not signal freed frame members.
    assert(QFile::setPermissions(path,QFile::ReadOwner|QFile::WriteOwner));
    auto *temporary=new ServoView();temporary->setSocketPath(path);
    assert(waitFor([&]{return server.hasPendingConnections();}));
    auto *lastPeer=server.nextPendingConnection();delete temporary;
    assert(waitFor([&]{return lastPeer->state()==QLocalSocket::UnconnectedState;}));
    puts("PASS fragmented/coalesced frames, malformed geometry, stale-image invalidation, missing/file/mode admission, resize, Reload full-image replacement, right-button routing and connected destruction");
}
