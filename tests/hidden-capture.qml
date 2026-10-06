pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import QtWebEngine
import "../native" as Candidate

// Inert real Browser; native extension compiled with a distinct test endpoint.
Item {
    id: root
    width: 480
    height: 320
    property var testProfile: null
    property bool prepared: false
    property bool completed: false
    property bool windowlessCapture: false
    property var detached: null
    Component { id: detachedComponent; Item { width: 480; height: 320 } }
    property string failureMode: ""
    property bool teardownNegative: false
    readonly property bool bridgeEnabled: !(failureMode === "disable" && teardownNegative)
    property int shownAfterPrepared: 0
    property var initialBrowser: null
    WebEngineProfilePrototype { id: prototype; httpCacheType: WebEngineProfile.MemoryHttpCache }
    TextInput { id: sentinel; text: "Unrelated inert input"; focus: true }
    Window {
        id: hiddenWindow
        width: 480
        height: 320
        visible: false
        onVisibleChanged: if (root.prepared && visible) root.shownAfterPrepared++
        Loader {
            id: content
            width: 480
            height: 320
            active: root.testProfile !== null
            sourceComponent: Component {
                Candidate.Browser {
                    anchors.fill: parent
                    profile: root.testProfile
                    fixtureMode: true
                    Component.onCompleted: loadHtml("<!doctype html><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'\"><style>body{margin:0;background:#fff;font:22px sans-serif}.top{height:100px;background:#e91e63}.bottom{height:100px;background:#1565c0;color:#fff}</style><div id='top' class='top'>OLD INERT FRAME</div><div class='bottom'>Off-record Chromium</div><input id='draft' value='Retained inert draft'>")
                }
            }
        }
    }
    Loader {
        active: root.prepared
        sourceComponent: Component {
            Candidate.Capture {
                browser: content.item
                presented: false
                enabled: root.bridgeEnabled
                onCaptured: root.completed = true
            }
        }
    }
    TestCase {
        name: "HiddenPrimaryCapture"
        when: windowShown
        function test_unmapped_fresh_pixels_and_retention() {
            root.testProfile = prototype.instance()
            tryCompare(content, "status", Loader.Ready)
            var browser = content.item
            root.initialBrowser = browser
            tryCompare(browser, "loadState", "SUCCEEDED", 5000)
            verify(!hiddenWindow.visible)
            sentinel.forceActiveFocus()
            var changed = false
            // The only JS executes in a synthetic off-record page, not capture.
            browser.runJavaScript("document.getElementById('top').style.background='#00aa44';document.getElementById('top').textContent='FRESH HIDDEN INERT FRAME';true", function(value) { changed = value })
            tryVerify(function() { return changed }, 2000)
            var renderer = browser.renderProcessPid
            verify(renderer > 0)
            compare(browser.width, 480)
            compare(browser.height, 320)
            console.log("INERT_GEOMETRY " + browser.width + "x" + browser.height)
            if (root.windowlessCapture) {
                root.detached = detachedComponent.createObject(null)
                content.parent = root.detached
            }
            root.prepared = true
            if (root.failureMode !== "") negativeTimer.start()
            if (root.failureMode === "") tryCompare(root, "completed", true, 6500)
            else wait(700)
            compare(root.shownAfterPrepared, 0)
            verify(!hiddenWindow.visible)
            verify(sentinel.activeFocus)
            compare(content.item, root.initialBrowser)
            compare(browser.profile, root.testProfile)
            compare(browser.renderProcessPid, renderer)
            var draft = null
            browser.runJavaScript("document.getElementById('draft').value", function(value) { draft = value })
            tryVerify(function() { return draft !== null }, 2000)
            compare(draft, "Retained inert draft")
            compare(browser.parent, content)
            if (root.windowlessCapture) compare(content.parent, root.detached)
            if (root.failureMode !== "") compare(root.completed, false)
            console.log("HIDDEN_IDENTITY_FOCUS_DRAFT_RETAINED renderer=" + renderer)
            content.active = false
            if (root.detached) { content.parent = hiddenWindow.contentItem; root.detached.destroy() }
        }
    }
    Timer {
        id: negativeTimer
        interval: 140
        onTriggered: {
            if (root.failureMode === "disable") root.teardownNegative = true
            else if (root.failureMode === "resize") content.width = 481
        }
    }
    Component.onDestruction: { content.active = false }
}
