import QtQuick
import QtTest
import QtWebEngine
import "../native" as Candidate

// One anonymous off-record navigation, bounded to 10 seconds, no reload/retry.
// Collect only public static script basenames, never queries, page text or storage.
Item {
    width: 800
    height: 600
    property var anonymousProfile: null
    WebEngineProfilePrototype { id: prototype; httpCacheType: WebEngineProfile.MemoryHttpCache }
    Loader { id: consumer; anchors.fill: parent }
    Component {
        id: browserComponent
        Candidate.Browser { profile: anonymousProfile; themeEnabled: false }
    }
    TestCase {
        name: "AnonymousPublicResources"
        when: windowShown
        function test_one_public_navigation() {
            anonymousProfile = prototype.instance()
            verify(anonymousProfile.offTheRecord)
            consumer.sourceComponent = browserComponent
            tryCompare(consumer, "status", Loader.Ready)
            var browser = consumer.item
            browser.url = "https://chatgpt.com/"
            tryVerify(function() { return browser.loadState === "SUCCEEDED" || browser.loadState === "FAILED" }, 10000)
            var result = null
            browser.runJavaScript("(() => { const u=new URL(location.href); if(u.origin!=='https://chatgpt.com')return {admitted:false}; const paths=[...document.scripts].map(s=>s.src).filter(Boolean).slice(0,64).map(s=>{const x=new URL(s);return {host:x.hostname,file:x.pathname.split('/').pop().slice(0,128),challenge:x.pathname.startsWith('/cdn-cgi/')}});return {admitted:true,challenge:u.pathname.startsWith('/cdn-cgi/'),scripts:paths};})()", function(value) { result = value })
            tryVerify(function() { return result !== null }, 2000)
            console.log("PUBLIC_RESOURCE_INVENTORY " + JSON.stringify(result))
            consumer.sourceComponent = null
        }
    }
}
