#pragma once
#include <wpe/webkit.h>
#include <QObject>
#include <QUrl>
#include <QVariantList>
#include <QStringList>

class WpePermission : public QObject {
    Q_OBJECT
public:
    WpePermission(WebKitPermissionRequest *value,QObject *parent):QObject(parent),request(WEBKIT_PERMISSION_REQUEST(g_object_ref(value))){}
    ~WpePermission() override {if(request){webkit_permission_request_deny(request);g_object_unref(request);}}
    Q_INVOKABLE void resolve(bool allow){if(request){if(allow)webkit_permission_request_allow(request);else webkit_permission_request_deny(request);g_object_unref(request);request=nullptr;}deleteLater();}
private:WebKitPermissionRequest *request;
};
class WpeOpenRequest : public QObject {
    Q_OBJECT
    Q_PROPERTY(QUrl requestedUrl MEMBER requestedUrl CONSTANT)
public:
    explicit WpeOpenRequest(const QUrl &url):requestedUrl(url){}
    Q_INVOKABLE void openIn(QObject *value){target=value;}
    QUrl requestedUrl;QObject *target=nullptr;
};
class WpeFiles : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool multiple READ multiple CONSTANT)
public:
    WpeFiles(WebKitFileChooserRequest *value,QObject *parent):QObject(parent),request(WEBKIT_FILE_CHOOSER_REQUEST(g_object_ref(value))){}
    ~WpeFiles() override {cancel();}
    Q_INVOKABLE void dispose(){cancel();deleteLater();}
    bool multiple() const{return request&&webkit_file_chooser_request_get_select_multiple(request);}
    Q_INVOKABLE void cancel(){if(request){webkit_file_chooser_request_cancel(request);g_object_unref(request);request=nullptr;}}
    Q_INVOKABLE void selectFiles(const QVariantList &files){
        if(!request)return;
        if(files.isEmpty()||files.size()>16||(!multiple()&&files.size()!=1)){cancel();return;}
        QList<QByteArray> names;for(const auto &file:files){const QUrl url(file.toString());
            if(!url.isLocalFile()||!url.host().isEmpty()||!url.toLocalFile().startsWith('/')||url.toLocalFile().size()>4096){cancel();return;}
            names.append(url.toLocalFile().toUtf8());
        }
        QList<const char*> paths;for(const auto &name:names)paths.append(name.constData());paths.append(nullptr);
        webkit_file_chooser_request_select_files(request,paths.constData());g_object_unref(request);request=nullptr;
    }
private:WebKitFileChooserRequest *request;
};
class WpeDownload : public QObject {
    Q_OBJECT
public:
    WpeDownload(WebKitDownload *value,QObject *parent):QObject(parent),download(WEBKIT_DOWNLOAD(g_object_ref(value))){
        // Hold engine destination selection until the explicit native dialog resolves.
        g_signal_connect(download,"decide-destination",G_CALLBACK(+[](WebKitDownload*,const char*,gpointer)->gboolean{return TRUE;}),this);
        g_signal_connect(download,"finished",G_CALLBACK(+[](WebKitDownload*,gpointer data){auto *self=static_cast<WpeDownload*>(data);self->complete=true;self->deleteLater();}),this);
    }
    ~WpeDownload() override {g_signal_handlers_disconnect_by_data(download,this);if(!complete)webkit_download_cancel(download);g_object_unref(download);}
    Q_INVOKABLE void cancel(){if(!complete)webkit_download_cancel(download);}
    Q_INVOKABLE void acceptPath(const QUrl &url){
        if(complete||chosen)return;
        if(!url.isLocalFile()||!url.host().isEmpty()||!url.toLocalFile().startsWith('/')||url.toLocalFile().size()>4096){cancel();return;}
        chosen=true;webkit_download_set_allow_overwrite(download,FALSE);
        const auto path=url.toLocalFile().toUtf8();webkit_download_set_destination(download,path.constData());
    }
private:WebKitDownload *download;bool complete=false,chosen=false;
};
