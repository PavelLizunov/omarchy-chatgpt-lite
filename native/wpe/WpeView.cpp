// Experimental native WPE QML surface. Production adoption requires full
// permissions, persistent-session, dialogs, accessibility and lifecycle checks.
#include <wpe/webkit.h>
#include <wpe/wpe-platform.h>
#include <wpe/headless/wpe-headless.h>
#include <QQuickPaintedItem>
#include <QPainter>
#include <QTimer>
#include <QQmlExtensionPlugin>
#include <QMouseEvent>
#include <QHoverEvent>
#include <QKeyEvent>
#include <QWheelEvent>
#include <QInputMethodEvent>
#include <QPointer>
#include <QUrl>
#include <QJSValue>
#include <QGuiApplication>
#include <QClipboard>
#include <QQmlEngine>
#include <xkbcommon/xkbcommon.h>
#include <memory>
#include <dlfcn.h>
#include "WpeSession.h"
#include "WpeRequests.h"

class WpeView;
typedef struct { WPEView parent; WpeView *owner; WPEInputMethodContext *input; } ChatView;
typedef struct { WPEViewClass parent; } ChatViewClass;
G_DEFINE_TYPE(ChatView, chat_view, WPE_TYPE_VIEW)
typedef struct { WPEClipboard parent; } ChatClipboard;
typedef struct { WPEClipboardClass parent; } ChatClipboardClass;
G_DEFINE_TYPE(ChatClipboard, chat_clipboard, WPE_TYPE_CLIPBOARD)
static void chat_clipboard_class_init(ChatClipboardClass *klass){
    WPE_CLIPBOARD_CLASS(klass)->changed=[](WPEClipboard *clipboard,GPtrArray *formats,gboolean local,WPEClipboardContent *content){
        WPE_CLIPBOARD_CLASS(chat_clipboard_parent_class)->changed(clipboard,formats,local,content);
        if(local&&content){const auto *text=wpe_clipboard_content_get_text(content);if(text&&strnlen(text,1048577)<=1048576)QGuiApplication::clipboard()->setText(QString::fromUtf8(text));}
    };
}
static void chat_clipboard_init(ChatClipboard*) {}
typedef struct { WPEDisplay parent; WPEClipboard *clipboard; } ChatDisplay;
typedef struct { WPEDisplayClass parent; } ChatDisplayClass;
G_DEFINE_TYPE(ChatDisplay, chat_display, WPE_TYPE_DISPLAY)
static gboolean renderBuffer(WPEView*,WPEBuffer*,const WPERectangle*,guint,GError**);
static void chat_view_class_init(ChatViewClass *klass) { WPE_VIEW_CLASS(klass)->render_buffer=renderBuffer; }
static void chat_view_init(ChatView *view) { view->owner=nullptr;view->input=nullptr; }
typedef struct { WPEInputMethodContext parent; } ChatInput;
typedef struct { WPEInputMethodContextClass parent; } ChatInputClass;
G_DEFINE_TYPE(ChatInput, chat_input, WPE_TYPE_INPUT_METHOD_CONTEXT)
static void chat_input_class_init(ChatInputClass *klass) {
    WPE_INPUT_METHOD_CONTEXT_CLASS(klass)->get_preedit_string=[](WPEInputMethodContext*,gchar **text,GList **lines,guint *cursor){*text=g_strdup("");*lines=nullptr;*cursor=0;};
}
static void chat_input_init(ChatInput*) {}
static void chat_display_class_init(ChatDisplayClass *klass) {
    G_OBJECT_CLASS(klass)->dispose=[](GObject *object){auto *self=reinterpret_cast<ChatDisplay*>(object);g_clear_object(&self->clipboard);G_OBJECT_CLASS(chat_display_parent_class)->dispose(object);};
    auto *display=WPE_DISPLAY_CLASS(klass);
    display->connect=[](WPEDisplay*,GError**)->gboolean{return TRUE;};
    display->get_clipboard=[](WPEDisplay *display)->WPEClipboard*{auto *self=reinterpret_cast<ChatDisplay*>(display);if(!self->clipboard)self->clipboard=WPE_CLIPBOARD(g_object_new(chat_clipboard_get_type(),"display",display,nullptr));return self->clipboard;};
    display->create_view=[](WPEDisplay *d)->WPEView*{return WPE_VIEW(g_object_new(chat_view_get_type(),"display",d,nullptr));};
    display->create_toplevel=[](WPEDisplay *d,guint)->WPEToplevel*{return WPE_TOPLEVEL(g_object_new(WPE_TYPE_TOPLEVEL_HEADLESS,"display",d,nullptr));};
    display->create_input_method_context=[](WPEDisplay*,WPEView *view)->WPEInputMethodContext*{auto *input=WPE_INPUT_METHOD_CONTEXT(g_object_new(chat_input_get_type(),"view",view,nullptr));reinterpret_cast<ChatView*>(view)->input=input;return input;};
}
static void chat_display_init(ChatDisplay *display) {display->clipboard=nullptr;}

class WpeView : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QString fixtureHtml READ fixtureHtml WRITE setFixtureHtml NOTIFY fixtureHtmlChanged)
    Q_PROPERTY(WpeSession* profile MEMBER profile)
    Q_PROPERTY(WpeView* relatedView MEMBER relatedView)
    Q_PROPERTY(int renderProcessPid READ renderProcessPid NOTIFY changed)
    Q_PROPERTY(QUrl url READ url WRITE setUrl NOTIFY changed)
    Q_PROPERTY(int loadErrorCode READ loadErrorCode NOTIFY changed)
    Q_PROPERTY(bool fixtureMode MEMBER fixtureMode)
    Q_PROPERTY(bool presented MEMBER presented)
    Q_PROPERTY(QString loadState READ loadState NOTIFY changed)
    Q_PROPERTY(bool frameReady READ frameReady NOTIFY changed)
    Q_PROPERTY(bool fixtureVerified READ fixtureVerified NOTIFY changed)
public:
    explicit WpeView(QQuickItem *parent=nullptr):QQuickPaintedItem(parent) {
        setAcceptedMouseButtons(Qt::AllButtons);
        setAcceptHoverEvents(true);
    }
    ~WpeView() override {
        if(platform) reinterpret_cast<ChatView*>(platform)->owner=nullptr;
        if(web) {g_signal_handlers_disconnect_by_data(web,this);webkit_web_view_stop_loading(web);g_object_unref(web);}
        if(input)g_object_unref(input);
        if(session){g_signal_handlers_disconnect_by_data(session,this);g_object_unref(session);}
        if(display)g_object_unref(display);
    }
    QString fixtureHtml() const {return html;}
    void setFixtureHtml(const QString &value){html=value;emit fixtureHtmlChanged();}
    QString loadState() const{return state;}
    int loadErrorCode() const{return errorCode;}
    int renderProcessPid() const{return rendererPid;}
    QUrl url() const{return pageUrl;}
    void setUrl(const QUrl &value){if(!safeUrl(value)){errorCode=0;state="FAILED";emit changed();return;}pageUrl=value;if(web){const auto uri=value.toEncoded();webkit_web_view_load_uri(web,uri.constData());}}
    Q_INVOKABLE bool safeUrl(const QUrl &value) const {
        return value==QUrl("about:blank")||(!fixtureMode&&value.scheme()=="https"&&!value.host().isEmpty()&&value.userInfo().isEmpty());
    }
    Q_INVOKABLE void loadHtml(const QString &value){if(!fixtureMode||value.toUtf8().size()>65536)return;html=value;if(web){const auto bytes=value.toUtf8();webkit_web_view_load_html(web,bytes.constData(),nullptr);}}
    Q_INVOKABLE void pasteText(const QString &text){if(!input||!hasActiveFocus()||!presented||text.toUtf8().size()>1048576)return;const auto bytes=text.toUtf8();g_signal_emit_by_name(input,"committed",bytes.constData());}
    Q_INVOKABLE void pasteConfirmed(){if(presented&&!fixtureMode){forceActiveFocus();pasteText(QGuiApplication::clipboard()->text());}}
    Q_INVOKABLE void fixturePaste(){if(fixtureMode)pasteText(QStringLiteral("abc"));}
    Q_INVOKABLE bool fixtureCopyVerified() const{return fixtureMode&&QGuiApplication::clipboard()->text()==QStringLiteral("Inert draftabc");}
    bool frameReady() const{return contentFrame;}
    bool fixtureVerified() const{return verified;}
    Q_INVOKABLE void verifyFixture() {
        if(!web || !fixtureMode || html.isEmpty())return;
        // Fixed inert acceptance only. Never evaluate on an account page.
        constexpr auto script="JSON.stringify({draft:document.querySelector('input').value,actions:window.actions||0})";
        auto *guard=new QPointer<WpeView>(this);
        webkit_web_view_evaluate_javascript(web,script,-1,nullptr,nullptr,nullptr,+[](GObject *source,GAsyncResult *result,gpointer data){
            std::unique_ptr<QPointer<WpeView>> guard(static_cast<QPointer<WpeView>*>(data));GError *error=nullptr;
            auto *value=webkit_web_view_evaluate_javascript_finish(WEBKIT_WEB_VIEW(source),result,&error);
            if(error)g_error_free(error);
            if(value){char *text=jsc_value_to_string(value);
                if(*guard){auto *self=guard->data();self->verified=QString::fromUtf8(text)==QStringLiteral("{\"draft\":\"Inert draftabc\",\"actions\":1}");emit self->changed();}
                g_free(text);g_object_unref(value);
            }
        },guard);
    }
    void paint(QPainter *p) override {if(!image.isNull())p->drawImage(boundingRect(),image);}
    bool frame(WPEBuffer *buffer,GError **error) {
        const int w=wpe_buffer_get_width(buffer),h=wpe_buffer_get_height(buffer);
        if(w<=0||h<=0||w>4096||h>4096){g_set_error_literal(error,WPE_VIEW_ERROR,WPE_VIEW_ERROR_RENDER_FAILED,"Buffer geometry exceeds native surface bounds");return false;}
        GBytes *pixels=WPE_IS_BUFFER_SHM(buffer)?g_bytes_ref(wpe_buffer_shm_get_data(WPE_BUFFER_SHM(buffer))):wpe_buffer_import_to_pixels(buffer,error);
        if(!pixels){if(error&&!*error)g_set_error_literal(error,WPE_VIEW_ERROR,WPE_VIEW_ERROR_RENDER_FAILED,"Cannot import engine buffer to native surface");return false;}
        gsize length=0;const auto *data=static_cast<const uchar*>(g_bytes_get_data(pixels,&length));
        const guint stride=WPE_IS_BUFFER_SHM(buffer)?wpe_buffer_shm_get_stride(WPE_BUFFER_SHM(buffer)):guint(w)*4;
        if(stride<guint(w)*4||length<static_cast<gsize>(stride)*h){g_bytes_unref(pixels);g_set_error_literal(error,WPE_VIEW_ERROR,WPE_VIEW_ERROR_RENDER_FAILED,"Buffer storage is shorter than geometry");return false;}
        image=QImage(data,w,h,stride,QImage::Format_ARGB32_Premultiplied).copy();g_bytes_unref(pixels);
        // Reject startup blank frames as visual readiness; inert fixture has text.
        const auto first=image.pixel(0,0);contentFrame=false;
        for(int y=0;y<h && !contentFrame;y+=4)for(int x=0;x<w;x+=4)if(image.pixel(x,y)!=first){contentFrame=true;break;}
        update();emit changed();return true;
    }
signals:
    void changed();void fixtureHtmlChanged();
    void filesRequested(WpeFiles *request);
    void downloadRequested(WpeDownload *request);
    void auxiliaryRequested(WpeOpenRequest *request);
    void dismissRequested();
    void readyToShow();
    void pasteRequested();
    void clipboardPermissionRequested(WpePermission *request);
protected:
    void componentComplete() override {
        QQuickPaintedItem::componentComplete();
        // WebKit runs on the GUI/GLib event loop, never Qt's scenegraph thread.
        create();
    }
    void geometryChange(const QRectF &next,const QRectF &old) override {
        QQuickPaintedItem::geometryChange(next,old);
        if(platform && next.width()>0 && next.height()>0 && next.width()<=4096 && next.height()<=4096)
            wpe_view_resized(platform,next.width(),next.height());
    }
    void mousePressEvent(QMouseEvent *event) override {forceActiveFocus();pointer(event,WPE_EVENT_POINTER_DOWN);}
    void mouseReleaseEvent(QMouseEvent *event) override {pointer(event,WPE_EVENT_POINTER_UP);}
    void mouseDoubleClickEvent(QMouseEvent *event) override {pointer(event,WPE_EVENT_POINTER_DOWN,2);}
    void hoverMoveEvent(QHoverEvent *event) override {
        if(!platform)return;
        auto *e=wpe_event_pointer_move_new(WPE_EVENT_POINTER_MOVE,platform,WPE_INPUT_SOURCE_MOUSE,event->timestamp(),modifiers(event->modifiers()),event->position().x(),event->position().y(),0,0);
        if(e){wpe_view_event(platform,e);wpe_event_unref(e);}
    }
    void mouseMoveEvent(QMouseEvent *event) override {
        if(!platform)return;
        auto *e=wpe_event_pointer_move_new(WPE_EVENT_POINTER_MOVE,platform,WPE_INPUT_SOURCE_MOUSE,event->timestamp(),WPEModifiers(0),event->position().x(),event->position().y(),0,0);
        if(e){wpe_view_event(platform,e);wpe_event_unref(e);}
    }
    void wheelEvent(QWheelEvent *event) override {
        if(!platform)return;
        const bool precise=!event->pixelDelta().isNull();
        const auto delta=precise?event->pixelDelta():event->angleDelta()/8;
        auto *e=wpe_event_scroll_new(platform,WPE_INPUT_SOURCE_MOUSE,event->timestamp(),modifiers(event->modifiers()),delta.x(),delta.y(),precise,FALSE,event->position().x(),event->position().y());
        if(e){wpe_view_event(platform,e);wpe_event_unref(e);}
    }
    void focusInEvent(QFocusEvent*) override {if(platform)wpe_view_focus_in(platform);}
    void focusOutEvent(QFocusEvent*) override {if(platform)wpe_view_focus_out(platform);}
    void keyPressEvent(QKeyEvent *event) override {
        if((event->key()==Qt::Key_V&&event->modifiers().testFlag(Qt::ControlModifier))||(event->key()==Qt::Key_Insert&&event->modifiers().testFlag(Qt::ShiftModifier))){if(presented)emit pasteRequested();event->accept();return;}
        key(event,WPE_EVENT_KEYBOARD_KEY_DOWN);
    }
    void keyReleaseEvent(QKeyEvent *event) override {key(event,WPE_EVENT_KEYBOARD_KEY_UP);}
    void inputMethodEvent(QInputMethodEvent *event) override {
        if(input && !event->commitString().isEmpty()){auto text=event->commitString().toUtf8();g_signal_emit_by_name(input,"committed",text.constData());event->accept();}
    }
    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override {
        if(query==Qt::ImEnabled)return hasActiveFocus();
        if(query==Qt::ImCursorRectangle)return boundingRect();
        return QQuickPaintedItem::inputMethodQuery(query);
    }
private:
    gboolean receiveIdentity(WebKitUserMessage *message) {
            if(g_strcmp0(webkit_user_message_get_name(message),"slovn.chatgpt-lite.renderer"))return FALSE;
            auto *parameters=webkit_user_message_get_parameters(message);
            if(!parameters||!g_variant_is_of_type(parameters,G_VARIANT_TYPE("(ut)")))return TRUE;
            guint32 localPid=0;guint64 namespaceId=0;g_variant_get(parameters,"(ut)",&localPid,&namespaceId);
            auto *self=this;self->rendererPid=0;
            // Sandboxed WebKit reports a namespace PID. Resolve its namespace,
            // never assume that PID belongs to the host's /proc namespace.
            const auto entries=QDir("/proc").entryList(QDir::Dirs|QDir::NoDotAndDotDot);
            for(const auto &entry:entries){
                bool numeric=false;const int pid=entry.toInt(&numeric);if(!numeric||pid<=1)continue;
                struct stat identity{};struct stat process{};const auto base=("/proc/"+entry).toUtf8();
                if(stat(base.constData(),&process)||process.st_uid!=getuid()||stat((base+"/ns/pid").constData(),&identity)||identity.st_ino!=namespaceId)continue;
                QFile status(QString::fromUtf8(base)+"/status");if(!status.open(QIODevice::ReadOnly))continue;
                const auto lines=status.read(16384).split('\n');
                for(const auto &line:lines)if(line.startsWith("NSpid:")&&line.simplified().split(' ').last().toUInt()==localPid){
                    if(self->rendererPid){self->rendererPid=0;emit self->changed();return TRUE;}
                    self->rendererPid=pid;
                }
            }
            emit self->changed();return TRUE;
    }
    void requestIdentity() {
        auto *guard=new QPointer<WpeView>(this);
        webkit_web_view_send_message_to_page(web,webkit_user_message_new("slovn.chatgpt-lite.identity-request",nullptr),nullptr,+[](GObject *source,GAsyncResult *result,gpointer data){
            std::unique_ptr<QPointer<WpeView>> guard(static_cast<QPointer<WpeView>*>(data));GError *error=nullptr;
            auto *reply=webkit_web_view_send_message_to_page_finish(WEBKIT_WEB_VIEW(source),result,&error);
            if(reply){if(*guard)guard->data()->receiveIdentity(reply);g_object_unref(reply);}if(error)g_error_free(error);
        },guard);
    }
    static WPEModifiers modifiers(Qt::KeyboardModifiers m) {
        return WPEModifiers((m.testFlag(Qt::ShiftModifier)?WPE_MODIFIER_KEYBOARD_SHIFT:0)|(m.testFlag(Qt::ControlModifier)?WPE_MODIFIER_KEYBOARD_CONTROL:0)|(m.testFlag(Qt::AltModifier)?WPE_MODIFIER_KEYBOARD_ALT:0)|(m.testFlag(Qt::MetaModifier)?WPE_MODIFIER_KEYBOARD_META:0));
    }
    void key(QKeyEvent *event,WPEEventType type) {
        if(!platform)return;
        guint value=event->nativeVirtualKey();
        if(!value){
            switch(event->key()){
            case Qt::Key_Backspace:value=XKB_KEY_BackSpace;break;case Qt::Key_Delete:value=XKB_KEY_Delete;break;
            case Qt::Key_Return:case Qt::Key_Enter:value=XKB_KEY_Return;break;case Qt::Key_Tab:value=XKB_KEY_Tab;break;
            case Qt::Key_Escape:value=XKB_KEY_Escape;break;case Qt::Key_Left:value=XKB_KEY_Left;break;case Qt::Key_Right:value=XKB_KEY_Right;break;
            case Qt::Key_Up:value=XKB_KEY_Up;break;case Qt::Key_Down:value=XKB_KEY_Down;break;case Qt::Key_Home:value=XKB_KEY_Home;break;
            case Qt::Key_End:value=XKB_KEY_End;break;case Qt::Key_Insert:value=XKB_KEY_Insert;break;
            default:if(!event->text().isEmpty())value=xkb_utf32_to_keysym(event->text().toUcs4().first());
                else if(event->key()>=Qt::Key_A && event->key()<=Qt::Key_Z)value=XKB_KEY_a+event->key()-Qt::Key_A;
                break;
            }
        }
        if(!value)return;
        auto *e=wpe_event_keyboard_new(type,platform,WPE_INPUT_SOURCE_KEYBOARD,event->timestamp(),modifiers(event->modifiers()),event->nativeScanCode(),value);
        if(e){wpe_view_event(platform,e);wpe_event_unref(e);event->accept();}
    }
    void pointer(QMouseEvent *event,WPEEventType type,guint presses=1) {
        if(!platform)return;
        wpe_view_focus_in(platform);
        const auto button=event->button()==Qt::LeftButton?1u:event->button()==Qt::MiddleButton?2u:3u;
        auto *e=wpe_event_pointer_button_new(type,platform,WPE_INPUT_SOURCE_MOUSE,event->timestamp(),modifiers(event->modifiers()),button,event->position().x(),event->position().y(),type==WPE_EVENT_POINTER_DOWN?presses:0);
        if(e){wpe_view_event(platform,e);wpe_event_unref(e);}
    }
    void create() {
        if(fixtureMode?(html.isEmpty()||html.toUtf8().size()>65536):(!pageUrl.isEmpty()&&!safeUrl(pageUrl))){state="FAILED";emit changed();return;}
        display=WPE_DISPLAY(g_object_new(chat_display_get_type(),nullptr));GError *error=nullptr;
        if(!wpe_display_connect(display,&error)){if(error)g_error_free(error);state="FAILED";emit changed();return;}
        if(profile){auto *value=profile->nativeSession();if(!value){state="FAILED";emit changed();return;}session=WEBKIT_NETWORK_SESSION(g_object_ref(value));}
        else if(fixtureMode)session=webkit_network_session_new_ephemeral();
        else {state="FAILED";emit changed();return;}
        auto *settings=webkit_settings_new();
        webkit_settings_set_enable_developer_extras(settings,FALSE);
        webkit_settings_set_enable_write_console_messages_to_stdout(settings,FALSE);
        webkit_settings_set_allow_file_access_from_file_urls(settings,FALSE);
        webkit_settings_set_allow_universal_access_from_file_urls(settings,FALSE);
        webkit_settings_set_media_playback_requires_user_gesture(settings,TRUE);
        // Preserve default script clipboard restrictions; explicit keyboard paste below.
        webkit_settings_set_javascript_can_access_clipboard(settings,FALSE);
        WebKitWebContext *context=relatedView&&relatedView->web?webkit_web_view_get_context(relatedView->web):webkit_web_context_new();
        if(!relatedView){
            Dl_info location{};
            if(dladdr(reinterpret_cast<void*>(&renderBuffer),&location)&&location.dli_fname){
                const auto extension=(QFileInfo(QString::fromLocal8Bit(location.dli_fname)).absolutePath()+"/extensions").toUtf8();
                webkit_web_context_add_path_to_sandbox(context,extension.constData(),TRUE);
                webkit_web_context_set_web_process_extensions_directory(context,extension.constData());
            }
        }
        if(relatedView&&relatedView->web)
            web=WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW,"related-view",relatedView->web,"settings",settings,nullptr));
        else web=WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW,"display",display,"web-context",context,"network-session",session,"settings",settings,nullptr));
        if(!relatedView)g_object_unref(context);
        g_object_unref(settings);
        g_signal_connect(web,"user-message-received",G_CALLBACK(+[](WebKitWebView*,WebKitUserMessage *message,gpointer data)->gboolean{
            return static_cast<WpeView*>(data)->receiveIdentity(message);
        }),this);
        platform=webkit_web_view_get_wpe_view(web);reinterpret_cast<ChatView*>(platform)->owner=this;
        setFlag(ItemAcceptsInputMethod,true);
        // Commit into the exact input context WebKit created, not an unconnected twin.
        input=reinterpret_cast<ChatView*>(platform)->input;
        if(input)g_object_ref(input);
        if(auto *top=wpe_view_get_toplevel(platform))wpe_toplevel_resize(top,qBound(1,int(width()),4096),qBound(1,int(height()),4096));
        wpe_view_resized(platform,qBound(1,int(width()),4096),qBound(1,int(height()),4096));wpe_view_set_visible(platform,TRUE);wpe_view_map(platform);
        g_signal_connect(web,"permission-request",G_CALLBACK(+[](WebKitWebView *view,WebKitPermissionRequest *request,gpointer data)->gboolean{
            auto *self=static_cast<WpeView*>(data);const QUrl origin(QString::fromUtf8(webkit_web_view_get_uri(view)));
            if(g_strcmp0(G_OBJECT_TYPE_NAME(request),"WebKitClipboardPermissionRequest")==0&&!self->fixtureMode&&self->presented&&origin.scheme()=="https"&&origin.host()=="chatgpt.com"&&!self->pendingPermission){
                auto *value=new WpePermission(request,self);self->pendingPermission=value;emit self->clipboardPermissionRequested(value);
            }else webkit_permission_request_deny(request);
            return TRUE;
        }),this);
        g_signal_connect(web,"load-changed",G_CALLBACK(+[](WebKitWebView*,WebKitLoadEvent event,gpointer data){
            auto *self=static_cast<WpeView*>(data);if(event==WEBKIT_LOAD_STARTED)self->state="LOADING";else if(event==WEBKIT_LOAD_FINISHED && self->state!="FAILED"){self->state="SUCCEEDED";self->requestIdentity();}emit self->changed();}),this);
        g_signal_connect(web,"load-failed",G_CALLBACK(+[](WebKitWebView*,WebKitLoadEvent,const char*,GError *error,gpointer data)->gboolean{auto *self=static_cast<WpeView*>(data);self->errorCode=error?error->code:0;self->state="FAILED";emit self->changed();return TRUE;}),this);
        g_signal_connect(web,"decide-policy",G_CALLBACK(+[](WebKitWebView*,WebKitPolicyDecision *decision,WebKitPolicyDecisionType type,gpointer data)->gboolean{
            if(type==WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION||type==WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION){
                auto *self=static_cast<WpeView*>(data);auto *action=webkit_navigation_policy_decision_get_navigation_action(WEBKIT_NAVIGATION_POLICY_DECISION(decision));
                const QUrl url(QString::fromUtf8(webkit_uri_request_get_uri(webkit_navigation_action_get_request(action))));
                if(self->fixtureMode&&(url.scheme()=="data"||url.isEmpty()))return FALSE;
                if(!self->safeUrl(url)){webkit_policy_decision_ignore(decision);return TRUE;}
            }return FALSE;
        }),this);
        g_signal_connect(web,"create",G_CALLBACK(+[](WebKitWebView*,WebKitNavigationAction *action,gpointer data)->WebKitWebView*{
            auto *self=static_cast<WpeView*>(data);const QUrl url(QString::fromUtf8(webkit_uri_request_get_uri(webkit_navigation_action_get_request(action))));
            if(!self->presented||!self->safeUrl(url))return nullptr;
            WpeOpenRequest request(url);emit self->auxiliaryRequested(&request);
            auto *target=qobject_cast<WpeView*>(request.target);
            return target&&target->web?WEBKIT_WEB_VIEW(g_object_ref(target->web)):nullptr;
        }),this);
        g_signal_connect(web,"ready-to-show",G_CALLBACK(+[](WebKitWebView*,gpointer data){emit static_cast<WpeView*>(data)->readyToShow();}),this);
        g_signal_connect(web,"close",G_CALLBACK(+[](WebKitWebView*,gpointer data){emit static_cast<WpeView*>(data)->dismissRequested();}),this);
        g_signal_connect(web,"run-file-chooser",G_CALLBACK(+[](WebKitWebView*,WebKitFileChooserRequest *request,gpointer data)->gboolean{
            auto *self=static_cast<WpeView*>(data);if(self->fixtureMode||!self->presented||self->pendingFiles){webkit_file_chooser_request_cancel(request);return TRUE;}
            auto *value=new WpeFiles(request,self);self->pendingFiles=value;emit self->filesRequested(value);return TRUE;
        }),this);
        g_signal_connect(session,"download-started",G_CALLBACK(+[](WebKitNetworkSession*,WebKitDownload *download,gpointer data){
            auto *self=static_cast<WpeView*>(data);if(webkit_download_get_web_view(download)!=self->web)return;
            if(self->fixtureMode||!self->presented||self->pendingDownload){webkit_download_cancel(download);return;}
            auto *value=new WpeDownload(download,self);self->pendingDownload=value;emit self->downloadRequested(value);
        }),this);
        g_signal_connect(web,"web-process-terminated",G_CALLBACK(+[](WebKitWebView*,WebKitWebProcessTerminationReason,gpointer data){auto *self=static_cast<WpeView*>(data);self->rendererPid=0;self->state="FAILED";emit self->changed();}),this);
        if(fixtureMode){const auto bytes=html.toUtf8();webkit_web_view_load_html(web,bytes.constData(),nullptr);}
        else if(!pageUrl.isEmpty()){const auto uri=pageUrl.toEncoded();webkit_web_view_load_uri(web,uri.constData());}
    }
    QString html,state="IDLE";QImage image;bool contentFrame=false,verified=false,fixtureMode=false,presented=false;
    QUrl pageUrl;int errorCode=0,rendererPid=0;WpeSession *profile=nullptr;WpeView *relatedView=nullptr;
    QPointer<WpeFiles> pendingFiles;QPointer<WpeDownload> pendingDownload;QPointer<WpePermission> pendingPermission;
    WPEInputMethodContext *input=nullptr;
    WPEDisplay *display=nullptr;WebKitNetworkSession *session=nullptr;WebKitWebView *web=nullptr;WPEView *platform=nullptr;
};
static gboolean renderBuffer(WPEView *view,WPEBuffer *buffer,const WPERectangle*,guint,GError **error) {
    auto *owner=reinterpret_cast<ChatView*>(view)->owner;
    if(!owner){g_set_error_literal(error,WPE_VIEW_ERROR,WPE_VIEW_ERROR_RENDER_FAILED,"Native surface no longer exists");return FALSE;}
    if(!owner->frame(buffer,error))return FALSE;
    // WebKit updates its committed-buffer state after this vfunc returns.
    // Never acknowledge/release reentrantly from inside render_buffer.
    auto heldView=std::shared_ptr<WPEView>(WPE_VIEW(g_object_ref(view)),[](WPEView *value){g_object_unref(value);});
    auto heldBuffer=std::shared_ptr<WPEBuffer>(WPE_BUFFER(g_object_ref(buffer)),[](WPEBuffer *value){g_object_unref(value);});
    QTimer::singleShot(0,owner,[heldView,heldBuffer](){wpe_view_buffer_rendered(heldView.get(),heldBuffer.get());wpe_view_buffer_released(heldView.get(),heldBuffer.get());});
    return TRUE;
}
class WpePlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:void registerTypes(const char *uri) override {qmlRegisterType<WpeView>(uri,1,0,"WpeView");qmlRegisterType<WpeSession>(uri,1,0,"WpeSession");qmlRegisterUncreatableType<WpePermission>(uri,1,0,"WpePermission","Owned request");qmlRegisterUncreatableType<WpeOpenRequest>(uri,1,0,"WpeOpenRequest","Owned request");qmlRegisterUncreatableType<WpeFiles>(uri,1,0,"WpeFiles","Owned request");qmlRegisterUncreatableType<WpeDownload>(uri,1,0,"WpeDownload","Owned request");}
};
#include "WpeView.moc"
