#include <QQuickPaintedItem>
#include <QLocalSocket>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QPainter>
#include <QMouseEvent>
#include <QKeyEvent>
#include <QInputMethodEvent>
#include <QQmlExtensionPlugin>
#include <qqml.h>
#include <QtEndian>
#include <sys/stat.h>
#include <unistd.h>

// Experimental native Servo frame consumer. No browser launch or page reconstruction.
class ServoView : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QString socketPath READ socketPath WRITE setSocketPath NOTIFY socketPathChanged)
    Q_PROPERTY(bool frameReady READ frameReady NOTIFY frameReadyChanged)
    Q_PROPERTY(quint64 frameSerial READ frameSerial NOTIFY frameSerialChanged)
    Q_PROPERTY(QString transportError READ transportError NOTIFY transportErrorChanged)
public:
    explicit ServoView(QQuickItem *parent=nullptr): QQuickPaintedItem(parent) {
        setAcceptedMouseButtons(Qt::AllButtons);
        setAcceptHoverEvents(true);
        setFlag(ItemIsFocusScope);
        setFlag(ItemAcceptsInputMethod);
        socket.setReadBufferSize(2048*2048*4+16);
        connect(&socket,&QLocalSocket::readyRead,this,&ServoView::receive);
        connect(&socket,&QLocalSocket::connected,this,[this]{
            send({{"type","Resize"},{"width",qRound(width())},{"height",qRound(height())}});
        });
        connect(&socket,&QLocalSocket::errorOccurred,this,[this]{if(!failing)fail(socket.errorString());});
        connect(&socket,&QLocalSocket::disconnected,this,[this]{if(!failing && error.isEmpty())fail(QStringLiteral("Native transport disconnected"));});
        connect(this,&QQuickItem::activeFocusChanged,this,[this]{send({{"type","Focus"},{"focused",hasActiveFocus()}});});
    }
    ~ServoView() override {
        // Socket teardown can emit signals; disconnect while frame/error members live.
        QObject::disconnect(&socket,nullptr,this,nullptr);
        socket.abort();
    }
    QString socketPath() const { return path; }
    bool frameReady() const { return !image.isNull(); }
    quint64 frameSerial() const { return serial; }
    QString transportError() const { return error; }
    void setSocketPath(const QString &value) {
        if (path==value) return;
        failing=true; socket.abort(); failing=false;
        error.clear(); bytes.clear(); image=QImage(); serial=0; path=value; update();
        emit transportErrorChanged(); emit socketPathChanged(); emit frameReadyChanged(); emit frameSerialChanged();
        if(path.isEmpty()) return;
        struct stat st{}; const auto name=path.toLocal8Bit();
        if(!path.startsWith('/') || ::lstat(name.constData(),&st) || !S_ISSOCK(st.st_mode) || st.st_uid!=getuid() || (st.st_mode&0777)!=0600) {
            fail(QStringLiteral("Native socket admission failed")); return;
        }
        error.clear(); emit transportErrorChanged(); socket.connectToServer(path);
    }
    void paint(QPainter *painter) override { if(!image.isNull()) painter->drawImage(boundingRect(),image); }
    Q_INVOKABLE void pointer(qreal x,qreal y,bool down) {
        forceActiveFocus(); const QJsonObject point{{"Device",QJsonArray{x,y}}};
        input({{"MouseMove",QJsonObject{{"point",point},{"is_compatibility_event_for_touch",false}}}});
        input({{"MouseButton",QJsonObject{{"action",down?"Down":"Up"},{"button","Primary"},{"point",point}}}});
    }
    Q_INVOKABLE void reload() { send({{"type","Reload"}}); }
    Q_INVOKABLE void shutdownTransport() {
        send({{"type","Shutdown"}});
        socket.flush();
    }
    Q_INVOKABLE void commit(const QString &text) {
        if(text.size()>4096) return;
        for(const char *state:{"Start","End"}) input({{"Ime",QJsonObject{{"Composition",QJsonObject{{"state",state},{"data",QString(state)=="End"?text:QString()}}}}}});
    }
signals:
    void socketPathChanged(); void frameReadyChanged(); void frameSerialChanged(); void transportErrorChanged();
protected:
    void mousePressEvent(QMouseEvent *e) override { mouse(e,true); }
    void mouseReleaseEvent(QMouseEvent *e) override { mouse(e,false); }
    void mouseMoveEvent(QMouseEvent *e) override {
        input({{"MouseMove",QJsonObject{{"point",QJsonObject{{"Device",QJsonArray{e->position().x(),e->position().y()}}}},{"is_compatibility_event_for_touch",false}}}});
        e->accept();
    }
    void hoverMoveEvent(QHoverEvent *e) override {
        const QJsonObject point{{"Device",QJsonArray{e->position().x(),e->position().y()}}};
        input({{"MouseMove",QJsonObject{{"point",point},{"is_compatibility_event_for_touch",false}}}}); e->accept();
    }
    void keyPressEvent(QKeyEvent *e) override { key(e,true); }
    void keyReleaseEvent(QKeyEvent *e) override { key(e,false); }
    void inputMethodEvent(QInputMethodEvent *e) override { commit(e->commitString()); e->accept(); }
    void wheelEvent(QWheelEvent *e) override {
        const QPointF delta=e->pixelDelta().isNull()?e->angleDelta()/8.0:e->pixelDelta();
        const QJsonObject point{{"Device",QJsonArray{e->position().x(),e->position().y()}}};
        input({{"Wheel",QJsonObject{{"point",point},{"delta",QJsonObject{{"x",delta.x()},{"y",delta.y()},{"z",0},{"mode","DeltaPixel"}}}}}}); e->accept();
    }
    void geometryChange(const QRectF &next,const QRectF &old) override {
        QQuickPaintedItem::geometryChange(next,old);
        if(next.size()!=old.size() && next.width()>=100 && next.height()>=100)
            send({{"type","Resize"},{"width",qRound(next.width())},{"height",qRound(next.height())}});
    }
    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override {
        if(query==Qt::ImEnabled) return true;
        if(query==Qt::ImCursorRectangle) return QRectF(0,0,width(),height());
        return QQuickPaintedItem::inputMethodQuery(query);
    }
private:
    void mouse(QMouseEvent *e,bool down) {
        forceActiveFocus();
        QString button;
        switch(e->button()) {
        case Qt::LeftButton: button="Primary"; break;
        case Qt::MiddleButton: button="Auxiliary"; break;
        case Qt::RightButton: button="Secondary"; break;
        case Qt::BackButton: button="Back"; break;
        case Qt::ForwardButton: button="Forward"; break;
        default: e->ignore(); return;
        }
        const QJsonObject point{{"Device",QJsonArray{e->position().x(),e->position().y()}}};
        input({{"MouseMove",QJsonObject{{"point",point},{"is_compatibility_event_for_touch",false}}}});
        input({{"MouseButton",QJsonObject{{"action",down?"Down":"Up"},{"button",button},{"point",point}}}});
        e->accept();
    }
    void key(QKeyEvent *e,bool down) {
        const QHash<int,QString> names{{Qt::Key_Backspace,"Backspace"},{Qt::Key_Delete,"Delete"},{Qt::Key_Return,"Enter"},{Qt::Key_Enter,"Enter"},{Qt::Key_Tab,"Tab"},{Qt::Key_Escape,"Escape"},{Qt::Key_Left,"ArrowLeft"},{Qt::Key_Right,"ArrowRight"},{Qt::Key_Up,"ArrowUp"},{Qt::Key_Down,"ArrowDown"},{Qt::Key_Home,"Home"},{Qt::Key_End,"End"}};
        QJsonObject value;
        if(names.contains(e->key())) value={{"Named",names[e->key()]}};
        else if(!e->text().isEmpty()) value={{"Character",e->text()}};
        else { e->ignore(); return; }
        QStringList mods;
        if(e->modifiers()&Qt::ShiftModifier) mods<<"SHIFT";
        if(e->modifiers()&Qt::ControlModifier) mods<<"CONTROL";
        if(e->modifiers()&Qt::AltModifier) mods<<"ALT";
        if(e->modifiers()&Qt::MetaModifier) mods<<"META";
        QJsonObject event{{"state",down?"Down":"Up"},{"key",value},{"code","Unidentified"},{"location","Standard"},{"modifiers",mods.join(" | ")},{"repeat",e->isAutoRepeat()},{"is_composing",false}};
        input({{"Keyboard",QJsonObject{{"event",event}}}}); e->accept();
    }
    void input(const QJsonObject &event) { send({{"type","Input"},{"event",event}}); }
    void send(const QJsonObject &command) {
        if(socket.state()!=QLocalSocket::ConnectedState) return;
        const auto data=QJsonDocument(command).toJson(QJsonDocument::Compact);
        if(data.size()>16384 || socket.bytesToWrite()>65536) { fail(QStringLiteral("Native input queue exceeded")); return; }
        QByteArray packet(4,Qt::Uninitialized); qToBigEndian<quint32>(data.size(),packet.data()); packet+=data;
        socket.write(packet);
    }
    void fail(const QString &reason) {
        if(failing) return;
        failing=true; error=reason; socket.abort(); bytes.clear(); image=QImage(); update();
        emit frameReadyChanged(); emit transportErrorChanged(); failing=false;
    }
    void receive() {
        while(socket.bytesAvailable()>0) {
            if(bytes.size()<16) bytes+=socket.read(16-bytes.size());
            if(bytes.size()<16) return;
            if(bytes.left(4)!="SV01") { fail(QStringLiteral("Invalid native frame")); return; }
            const auto w=qFromBigEndian<quint32>(bytes.constData()+4),h=qFromBigEndian<quint32>(bytes.constData()+8),n=qFromBigEndian<quint32>(bytes.constData()+12);
            if(!w||!h||w>2048||h>2048||n!=w*h*4) { fail(QStringLiteral("Invalid native geometry")); return; }
            bytes+=socket.read(16+n-bytes.size());
            if(bytes.size()<16+n) return;
            const bool first=image.isNull();
            image=QImage(reinterpret_cast<const uchar*>(bytes.constData()+16),w,h,w*4,QImage::Format_RGBA8888).copy();
            bytes.clear(); ++serial; update(); emit frameSerialChanged(); if(first)emit frameReadyChanged();
        }
    }
    QLocalSocket socket; QByteArray bytes; QImage image; QString path,error; quint64 serial=0; bool failing=false;
};
class ServoPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<ServoView>(uri,1,0,"ServoView"); }
};
#include "ServoView.moc"
