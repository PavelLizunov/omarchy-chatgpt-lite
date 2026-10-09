#include "../native/wpe/WpeSession.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QDebug>
#include <libsoup/soup.h>
#include <cassert>

static bool done=false,good=false;
static void waitForAsync(){
    auto *loop=g_main_loop_new(nullptr,FALSE);
    guint timer=g_timeout_add(10,+[](gpointer value)->gboolean{if(!done)return G_SOURCE_CONTINUE;g_main_loop_quit(static_cast<GMainLoop*>(value));return G_SOURCE_REMOVE;},loop);
    guint deadline=g_timeout_add_seconds(4,+[](gpointer value)->gboolean{g_main_loop_quit(static_cast<GMainLoop*>(value));return G_SOURCE_REMOVE;},loop);
    g_main_loop_run(loop);if(!done)g_source_remove(timer);g_source_remove(deadline);g_main_loop_unref(loop);assert(done&&good);
}
int main(int argc,char **argv){
    QCoreApplication app(argc,argv);QTemporaryDir root;assert(root.isValid());
    const auto data=root.path()+"/engine/profile",cache=root.path()+"/engine/cache";
    {
        WpeSession session;session.setProperty("ephemeral",false);session.setProperty("dataPath",data);session.setProperty("cachePath",cache);assert(session.initialize());
        struct stat st{};assert(!stat(data.toUtf8().constData(),&st)&&(st.st_mode&0777)==0700);
        auto *cookie=soup_cookie_new("inert-check","retained","fixture.invalid","/",3600);
        done=false;good=false;
        webkit_cookie_manager_add_cookie(webkit_network_session_get_cookie_manager(session.nativeSession()),cookie,nullptr,+[](GObject *source,GAsyncResult *result,gpointer){GError *error=nullptr;good=webkit_cookie_manager_add_cookie_finish(WEBKIT_COOKIE_MANAGER(source),result,&error);if(error)g_error_free(error);done=true;},nullptr);
        soup_cookie_free(cookie);waitForAsync();
    }
    {
        WpeSession session;session.setProperty("ephemeral",false);session.setProperty("dataPath",data);session.setProperty("cachePath",cache);assert(session.initialize());done=false;good=false;
        webkit_cookie_manager_get_all_cookies(webkit_network_session_get_cookie_manager(session.nativeSession()),nullptr,+[](GObject *source,GAsyncResult *result,gpointer){GError *error=nullptr;auto *cookies=webkit_cookie_manager_get_all_cookies_finish(WEBKIT_COOKIE_MANAGER(source),result,&error);for(auto *it=cookies;it;it=it->next){auto *cookie=static_cast<SoupCookie*>(it->data);if(!strcmp(soup_cookie_get_name(cookie),"inert-check")&&!strcmp(soup_cookie_get_value(cookie),"retained"))good=true;}g_list_free_full(cookies,reinterpret_cast<GDestroyNotify>(soup_cookie_free));if(error)g_error_free(error);done=true;},nullptr);waitForAsync();
    }
    for(const auto &bad:QStringList{"relative",root.path()+"/../escape",root.path()+"/link/profile",root.path()+"/public/profile"}){
        if(bad.contains("/link/"))assert(!symlink(root.path().toUtf8().constData(),(root.path()+"/link").toUtf8().constData()));
        if(bad.contains("/public/")){QDir().mkpath(root.path()+"/public");assert(!chmod((root.path()+"/public").toUtf8().constData(),0755));}
        WpeSession session;session.setProperty("ephemeral",false);session.setProperty("dataPath",bad);session.setProperty("cachePath",cache);assert(!session.initialize());
    }
    qInfo()<<"PASS WPE private path admission, persistent inert cookie across native sessions, relative/dotdot/symlink/public-mode rejection; no production account/storage access";
}
