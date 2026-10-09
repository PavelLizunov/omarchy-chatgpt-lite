#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <cstdio>
#include "quickshell-adapter.hpp"
#include "core/common.hpp"

// Actual candidate consumer, offscreen only. Never grabs/saves/exports page pixels.
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    const QString fixture=QString::fromLocal8Bit(argv[1]), socket=QString::fromLocal8Bit(argv[2]);
    qputenv("QT_QPA_PLATFORM","offscreen");
    qputenv("QT_QUICK_BACKEND","software");
    QGuiApplication app(argc,argv);
    qs::Common::INITIAL_ENVIRONMENT = QProcessEnvironment::systemEnvironment();
    initializeQuickshellPreview();
    QJsonArray imports{QStringLiteral("/usr/share/omarchy/shell")};
    auto *generation=createQuickshellPreview(fixture,imports);
    generation->engine->addImportPath("/usr/share/omarchy/shell");
    QQmlComponent component(generation->engine,QUrl::fromLocalFile(fixture));
    if(component.isError()) { std::fprintf(stderr,"Consumer QML failed to load\n"); return 3; }
    auto *root=qobject_cast<QQuickItem*>(component.createWithInitialProperties({{"socketPath",socket}}));
    if(!root) return 4;
    generation->root = root;
    generation->onReload(nullptr);
    QQuickWindow window;
    window.resize(620,640); root->setParentItem(window.contentItem()); window.show();
    bool passed=false;
    QTimer deadline;
    deadline.setSingleShot(true);
    QObject::connect(&deadline,&QTimer::timeout,&app,[&]{
        std::fprintf(stderr,"CONSUMER_TIMEOUT %s\n",qPrintable(root->property("diagnostic").toString()));
        app.exit(5);
    });
    deadline.start(12000);
    QTimer poll;
    QObject::connect(&poll,&QTimer::timeout,&app,[&]{
        if(!root->property("checkPassed").toBool())return;
        passed=true;
        std::puts("ACTUAL_SERVO_SERVICE_FRAME_PASS; no page capture or account action");
        app.quit();
    });
    poll.start(100);
    const int status=app.exec();
    delete root;
    return passed?0:status?status:6;
}
