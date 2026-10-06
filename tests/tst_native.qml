pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import QtWebEngine
import "../native" as Candidate

Item {
    id: root
    width: 620
    height: 768
    WebEngineProfilePrototype { id: prototype; httpCacheType: WebEngineProfile.MemoryHttpCache }
    Loader { id: consumer; anchors.fill: parent }
    Component {
        id: content
        Candidate.Content {
            browserProfile: root.testProfile
            fixtureMode: true
            panelBackground: "#101315"
            panelForeground: "#cacccc"
            panelBorder: "#cacccc"
            fixtureHtml: "<!doctype html><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'\"><style>.bg-token-bg-elevated-secondary{background:#fff}.composer-shell{background:#fff}.bg-surface-primary{background:#fff}button{background:#161616;color:#fff}</style><div id='suggestions' class='bg-token-bg-elevated-secondary'>Inert suggestions</div><div id='composer' class='composer-shell' data-composer-surface='true'><input id='draft' value='Fixture draft'></div><div id='surface' class='bg-surface-primary'>Inert surface</div><button id='send'>Inert action</button>"
        }
    }
    property var testProfile: null
    SignalSpy {
        id: contextSpy
        target: consumer.item ? consumer.item.browser : null
        signalName: "contextMenuRequested"
    }
    TestCase {
        name: "NativeBrowser"
        when: windowShown
        function test_load_and_retention() {
            root.testProfile = prototype.instance()
            verify(root.testProfile !== null)
            consumer.sourceComponent = content
            tryCompare(consumer, "status", Loader.Ready)
            var browser = consumer.item.browser
            tryCompare(browser, "loadState", "SUCCEEDED", 5000)
            compare(browser.settings.autoLoadIconsForPage, false)
            compare(browser.settings.touchIconsEnabled, false)
            compare(browser.settings.dnsPrefetchEnabled, false)
            compare(browser.settings.hyperlinkAuditingEnabled, false)
            compare(browser.settings.javascriptEnabled, true)
            compare(browser.settings.localStorageEnabled, true)
            var strip = consumer.item.statusStrip
            var readyHeight = browser.height
            browser.loadErrorCode = 403
            browser.loadState = "FAILED"
            verify(consumer.item.loadError)
            wait(0)
            verify(strip.visible && strip.height > 0)
            verify(browser.y >= strip.y + strip.height)
            verify(browser.height < readyHeight)
            browser.loadState = "LOADING"
            verify(!consumer.item.loadError)
            wait(0)
            verify(strip.visible && browser.y >= strip.y + strip.height)
            browser.loadState = "SUCCEEDED"
            verify(!consumer.item.loadError)
            wait(0)
            verify(!strip.visible)
            compare(strip.height, 0)
            compare(browser.height, readyHeight)
            var appearance = null
            browser.runJavaScript("getComputedStyle(document.body).backgroundColor", function(value) { appearance = value })
            tryVerify(function() { return appearance === "rgb(16, 19, 21)" }, 3000)
            browser.themeBackground = "#fffbea"
            browser.themeForeground = "#161616"
            appearance = null
            browser.runJavaScript("getComputedStyle(document.body).backgroundColor", function(value) { appearance = value })
            tryVerify(function() { return appearance === "rgb(255, 251, 234)" }, 3000)
            var surfaces = null
            browser.runJavaScript("['suggestions','composer','surface'].map(id => getComputedStyle(document.getElementById(id)).backgroundColor).join('|')", function(value) { surfaces = value })
            tryVerify(function() { return surfaces === "rgb(255, 251, 234)|rgb(255, 251, 234)|rgb(255, 251, 234)" }, 3000)
            var actionColor = null
            browser.runJavaScript("getComputedStyle(document.getElementById('send')).backgroundColor", function(value) { actionColor = value })
            tryVerify(function() { return actionColor === "rgb(22, 22, 22)" }, 3000)
            browser.runJavaScript("document.getElementById('slovn-chatgpt-theme').remove(); true", function() {})
            browser.fixtureMode = false
            browser.applyTheme()
            var admitted = null
            browser.runJavaScript("document.getElementById('slovn-chatgpt-theme') === null", function(value) { admitted = value })
            tryVerify(function() { return admitted === true }, 3000)
            browser.fixtureMode = true
            browser.applyTheme()
            var result = null
            browser.runJavaScript("document.getElementById('draft').value", function(value) { result = value })
            tryVerify(function() { return result !== null }, 3000)
            compare(result, "Fixture draft")
            var focused = false
            browser.runJavaScript("document.getElementById('draft').focus(); true", function(value) { focused = value })
            tryVerify(function() { return focused }, 3000)
            browser.forceActiveFocus()
            keyClick(Qt.Key_End)
            keyClick(Qt.Key_X)
            var typed = null
            tryVerify(function() {
                browser.runJavaScript("document.getElementById('draft').value", function(value) { typed = value })
                return typed === "Fixture draftx"
            }, 3000)
            compare(typed, "Fixture draftx")
            consumer.visible = false
            wait(100)
            consumer.visible = true
            var retained = null
            browser.runJavaScript("document.getElementById('draft').value", function(value) { retained = value })
            tryVerify(function() { return retained !== null }, 3000)
            compare(retained, "Fixture draftx")
            compare(browser.lifecycleState, WebEngineView.LifecycleState.Active)
            browser.fixtureMode = false
            for (var uri of ["https://chatgpt.com/", "https://accounts.google.com/", "about:blank"])
                verify(browser.safeUrl(uri))
            for (var forbidden of ["javascript:alert(1)", "file:///etc/passwd", "http://chatgpt.com/", "https://user:pw@example.com/", "https://example.com\\\\evil/"])
                verify(!browser.safeUrl(forbidden))
            var denied = 0
            for (var origin of ["https://example.com/", "https://chatgpt.com.attacker.invalid/", "http://chatgpt.com/"]) {
                browser.requestPermission({origin: origin, permissionType: WebEngineView.ClipboardReadWrite,
                    deny: function() { denied++ }})
            }
            compare(denied, 3)
            mouseClick(browser, 200, 100, Qt.RightButton)
            tryCompare(contextSpy, "count", 1, 3000)
            verify(contextSpy.signalArguments[0][0].accepted)
            browser.fixtureMode = true
            verify(!browser.safeUrl("https://chatgpt.com/"))
            consumer.sourceComponent = null
        }
        function test_native_freeze_experiment() {
            root.testProfile = prototype.instance()
            consumer.sourceComponent = content
            tryCompare(consumer, "status", Loader.Ready)
            var browser = consumer.item.browser
            tryCompare(browser, "loadState", "SUCCEEDED", 5000)
            var started = false
            browser.runJavaScript("window.inertTicks=0;window.inertTimer=setInterval(()=>window.inertTicks++,100);true", function(value) { started = value })
            tryVerify(function() { return started }, 2000)
            consumer.visible = false
            wait(1200)
            var activeTicks = null
            browser.runJavaScript("window.inertTicks", function(value) { activeTicks = value })
            tryVerify(function() { return activeTicks !== null }, 2000)
            verify(activeTicks > 0)
            browser.lifecycleState = WebEngineView.LifecycleState.Frozen
            tryCompare(browser, "lifecycleState", WebEngineView.LifecycleState.Frozen)
            wait(1200)
            browser.lifecycleState = WebEngineView.LifecycleState.Active
            var resumed = null
            browser.runJavaScript("({ticks:window.inertTicks,draft:document.getElementById('draft').value})", function(value) { resumed = value })
            tryVerify(function() { return resumed !== null }, 2000)
            verify(resumed.ticks - activeTicks <= 2)
            compare(resumed.draft, "Fixture draft")
            var resumedTicks = resumed.ticks
            wait(1200)
            resumed = null
            browser.runJavaScript("window.inertTicks", function(value) { resumed = value })
            tryVerify(function() { return resumed !== null }, 2000)
            verify(resumed > resumedTicks)
            browser.runJavaScript("clearInterval(window.inertTimer)")
            consumer.visible = true
            consumer.sourceComponent = null
        }
    }
}
