// Trusted native extension reports only process identity; never reads page data.
#include <wpe/webkit-web-process-extension.h>
#include <unistd.h>
#include <sys/stat.h>
static void reportIdentity(WebKitWebPage *page) {
    struct stat identity{};
    if(stat("/proc/self/ns/pid",&identity))return;
    auto *message=webkit_user_message_new("slovn.chatgpt-lite.renderer",g_variant_new("(ut)",guint32(getpid()),guint64(identity.st_ino)));
    webkit_web_page_send_message_to_view(page,message,nullptr,nullptr,nullptr);
}
extern "C" G_MODULE_EXPORT void webkit_web_process_extension_initialize(WebKitWebProcessExtension *extension) {
    g_signal_connect(extension,"page-created",G_CALLBACK(+[](WebKitWebProcessExtension*,WebKitWebPage *page,gpointer){
        reportIdentity(page);
        g_signal_connect(page,"user-message-received",G_CALLBACK(+[](WebKitWebPage*,WebKitUserMessage *message,gpointer)->gboolean{
            if(g_strcmp0(webkit_user_message_get_name(message),"slovn.chatgpt-lite.identity-request"))return FALSE;
            struct stat identity{};if(stat("/proc/self/ns/pid",&identity))return TRUE;
            webkit_user_message_send_reply(message,webkit_user_message_new("slovn.chatgpt-lite.renderer",g_variant_new("(ut)",guint32(getpid()),guint64(identity.st_ino))));return TRUE;
        }),nullptr);
        // Cross-origin navigation can replace the provisional initial renderer.
        g_signal_connect(page,"document-loaded",G_CALLBACK(+[](WebKitWebPage *page,gpointer){reportIdentity(page);}),nullptr);
    }),nullptr);
}
