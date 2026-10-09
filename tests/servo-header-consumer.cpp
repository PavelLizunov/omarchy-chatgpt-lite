#include <QGuiApplication>
#include <QJsonArray>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTest>
#include <cassert>
#include <cstdio>
#include "quickshell-adapter.hpp"
int main(int argc,char **argv) {
    assert(argc==2);
    qputenv("QT_QPA_PLATFORM","offscreen");qputenv("QT_QUICK_BACKEND","software");
    QGuiApplication app(argc,argv);initializeQuickshellPreview();
    QString fixture=QString::fromLocal8Bit(argv[1]);
    auto *generation=createQuickshellPreview(fixture,QJsonArray{"/usr/share/omarchy/shell"});
    QQmlComponent component(generation->engine,QUrl::fromLocalFile(fixture));
    auto *root=qobject_cast<QQuickItem*>(component.create());assert(root);
    QQuickWindow window;window.resize(620,200);root->setParentItem(window.contentItem());window.show();
    QTest::qWait(100);
    auto *reload=root->findChild<QQuickItem*>("chatgptReloadButton");
    auto *restart=root->findChild<QQuickItem*>("chatgptRestartButton");assert(reload&&restart);
    for(auto *item:{reload,restart})QTest::mouseClick(&window,Qt::LeftButton,Qt::NoModifier,item->mapToScene(item->boundingRect().center()).toPoint());
    assert(root->property("reloads").toInt()==1&&root->property("restarts").toInt()==1);
    reload->forceActiveFocus();QTest::keyClick(&window,Qt::Key_Return);
    restart->forceActiveFocus();QTest::keyClick(&window,Qt::Key_Space);
    assert(root->property("reloads").toInt()==2&&root->property("restarts").toInt()==2);
    root->setProperty("busy",true);QTest::qWait(20);assert(!reload->isEnabled()&&!restart->isEnabled());
    for(auto *item:{reload,restart})QTest::mouseClick(&window,Qt::LeftButton,Qt::NoModifier,item->mapToScene(item->boundingRect().center()).toPoint());
    assert(root->property("reloads").toInt()==2&&root->property("restarts").toInt()==2);
    delete root;puts("PASS actual Header mouse, Return, Space, busy-state admission");
}
