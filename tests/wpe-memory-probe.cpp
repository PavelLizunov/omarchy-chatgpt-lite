// Isolated WPE feasibility and process-group charge, not production acceptance.
// No account profile, JavaScript injection, resource filtering or desktop window.
#include <wpe/webkit.h>
#include <wpe/headless/wpe-headless.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <fstream>
#include <sstream>
#include <unistd.h>
static GMainLoop *loop;
static int result=5;
static unsigned httpStatus=0;
static std::string read(const std::string &path) {
    std::ifstream f(path); std::string text; char buffer[4096];
    if(!f) return "unavailable";
    f.read(buffer,sizeof(buffer)); text.assign(buffer,f.gcount());
    while(!text.empty() && (text.back()=='\n'||text.back()==' ')) text.pop_back();
    return text;
}
static gboolean finish(gpointer){g_main_loop_quit(loop);return G_SOURCE_REMOVE;}
static void loaded(WebKitWebView *view,WebKitLoadEvent event,gpointer){
    if(event==WEBKIT_LOAD_FINISHED){
        auto *resource=webkit_web_view_get_main_resource(view);
        auto *response=resource?webkit_web_resource_get_response(resource):nullptr;
        httpStatus=response?webkit_uri_response_get_status_code(response):0;
        result=0;g_timeout_add(5000,finish,nullptr);
    }
}
static gboolean failed(WebKitWebView*,WebKitLoadEvent,const char*,GError *error,gpointer){
    fprintf(stderr,"WPE load failed domain=%u code=%d\n",error->domain,error->code);
    result=4;g_main_loop_quit(loop);return TRUE;
}
static gboolean permission(WebKitWebView*,WebKitPermissionRequest *request,gpointer){
    webkit_permission_request_deny(request);return TRUE;
}
static void terminated(WebKitWebView*,WebKitWebProcessTerminationReason reason,gpointer){
    fprintf(stderr,"WPE web process terminated reason=%d\n",reason);result=6;g_main_loop_quit(loop);
}
int main(int argc,char **argv){
    if(argc!=2 || (strcmp(argv[1],"inert") && strcmp(argv[1],"live"))) return 2;
    const bool live=!strcmp(argv[1],"live");
    auto *display=wpe_display_headless_new(); GError *error=nullptr;
    if(!wpe_display_connect(display,&error)) return 3;
    auto *session=webkit_network_session_new_ephemeral();
    auto *view=WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW,"display",display,"network-session",session,nullptr));
    auto *platform=webkit_web_view_get_wpe_view(view);if(!platform)return 3;
    wpe_view_resized(platform,460,560);wpe_view_set_visible(platform,TRUE);wpe_view_map(platform);
    loop=g_main_loop_new(nullptr,FALSE);
    g_signal_connect(view,"load-changed",G_CALLBACK(loaded),nullptr);
    g_signal_connect(view,"load-failed",G_CALLBACK(failed),nullptr);
    g_signal_connect(view,"permission-request",G_CALLBACK(permission),nullptr);
    g_signal_connect(view,"web-process-terminated",G_CALLBACK(terminated),nullptr);
    const auto timeout=g_timeout_add(15000,finish,nullptr);
    if(live) webkit_web_view_load_uri(view,"https://chatgpt.com/");
    else webkit_web_view_load_html(view,"<!doctype html><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'\"><input value='Inert draft'><p>Headless WPE capability</p>",nullptr);
    g_main_loop_run(loop);if(result!=5)g_source_remove(timeout);
    std::string relative;std::istringstream groups(read("/proc/self/cgroup"));std::string line;
    while(std::getline(groups,line))if(line.rfind("0::/",0)==0)relative=line.substr(3);
    const auto base=relative.empty()?"/nonexistent":std::string("/sys/fs/cgroup")+relative;
    printf("{\"engine\":\"WPE\",\"version\":\"%u.%u.%u\",\"mode\":\"%s\",\"loadFinished\":%s,\"httpStatus\":%u,\"pid\":%d,\"cgroupCurrent\":\"%s\",\"cgroupPeak\":\"%s\",\"cgroupMax\":\"%s\",\"swap\":\"%s\",\"qmlVerified\":false,\"authenticatedFunctionsVerified\":false,\"memoryTargetVerified\":false}\n",
        webkit_get_major_version(),webkit_get_minor_version(),webkit_get_micro_version(),argv[1],result==0?"true":"false",httpStatus,getpid(),read(base+"/memory.current").c_str(),read(base+"/memory.peak").c_str(),read(base+"/memory.max").c_str(),read(base+"/memory.swap.current").c_str());
    g_signal_handlers_disconnect_by_data(view,nullptr);g_object_unref(view);g_object_unref(session);g_object_unref(display);g_main_loop_unref(loop);return result;
}
