#pragma once
#include <wpe/webkit.h>
#include <QObject>
#include <QUrl>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

// Engine-specific storage; never import/alter Chromium's persistent profile.
class WpeSession : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString dataPath MEMBER dataPath)
    Q_PROPERTY(QString cachePath MEMBER cachePath)
    Q_PROPERTY(bool ephemeral MEMBER ephemeral)
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
public:
    using QObject::QObject;
    ~WpeSession() override {if(session)g_object_unref(session);}
    bool ready() const{return session;}
    QString error() const{return failure;}
    WebKitNetworkSession *nativeSession(){if(!session)initialize();return session;}
    Q_INVOKABLE bool initialize() {
        if(session)return true;
        if(ephemeral)session=webkit_network_session_new_ephemeral();
        else {
            if(!privateDirectory(dataPath)||!privateDirectory(cachePath)){failure="PROFILE_PATH_FAILED";emit changed();return false;}
            const auto data=dataPath.toUtf8(),cache=cachePath.toUtf8();
            session=webkit_network_session_new(data.constData(),cache.constData());
            const auto cookies=(dataPath+"/cookies.sqlite").toUtf8();
            webkit_cookie_manager_set_persistent_storage(webkit_network_session_get_cookie_manager(session),cookies.constData(),WEBKIT_COOKIE_PERSISTENT_STORAGE_SQLITE);
        }
        webkit_network_session_set_tls_errors_policy(session,WEBKIT_TLS_ERRORS_POLICY_FAIL);
        emit changed();return true;
    }
signals:void changed();
private:
    static bool privateDirectory(const QString &path) {
        if(!path.startsWith('/')||path.size()>4096||path.contains(QChar(0)))return false;
        int fd=open("/",O_RDONLY|O_DIRECTORY|O_CLOEXEC);if(fd<0)return false;
        const auto parts=path.split('/',Qt::SkipEmptyParts);if(parts.size()<2){close(fd);return false;}bool ok=true;
        for(int i=0;i<parts.size();++i){
            const auto name=parts[i].toUtf8();if(name=="."||name==".."){ok=false;break;}
            // Last two components belong to this engine. Existing ancestors unchanged.
            if(i>=parts.size()-2 && mkdirat(fd,name.constData(),0700) && errno!=EEXIST){ok=false;break;}
            const int next=openat(fd,name.constData(),O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
            if(next<0){ok=false;break;}
            close(fd);fd=next;struct stat st{};
            if(fstat(fd,&st)||(i>=parts.size()-2 && (st.st_uid!=getuid()||(st.st_mode&0777)!=0700))){ok=false;break;}
        }
        close(fd);return ok;
    }
    QString dataPath,cachePath,failure="NONE";bool ephemeral=true;WebKitNetworkSession *session=nullptr;
};
