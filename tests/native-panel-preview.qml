pragma ComponentBehavior: Bound
import QtQuick
import QtWebEngine
import Quickshell
import "../native" as Candidate

// Actual native wrapper with inert off-record I/O and a real offscreen host interface.
Item {
    id: root
    property bool previewReady: false
    property bool teardownCheck: false
    property bool lifetimeCheck: false
    property bool interactionCheck: false
    property bool checkPassed: false
    property var retained: null
    WebEngineProfilePrototype { id: prototype; httpCacheType: WebEngineProfile.MemoryHttpCache }
    Loader { id: candidate; active: false; sourceComponent: wrapper }
    Component {
        id: wrapper
        Candidate.Service {
            suppliedProfile: root.lifetimeCheck ? null : prototype.instance()
            profileReady: true
            fixtureMode: true
            fixtureHtml: "<!doctype html><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; style-src 'unsafe-inline'\"><style>body{font:16px sans-serif;margin:24px;background:#101315;color:#cacccc}input{width:90%;padding:10px}pre{white-space:pre-wrap}</style><h1>Native host fixture</h1><p>Actual Panel, Content and Browser. No network or account.</p><pre>const answer = 42;</pre><label>Draft<input value='Retained inert draft'></label>"
            Component.onCompleted: {
                contentForPreview()
            }
            function contentForPreview() {
                // The real surface stays unshown. Reparent its actual visual
                // content to the capture canvas; do not create an alternate panel.
                visualContent.parent = root
                visualContent.width = Qt.binding(function() { return candidate.item.popupWidth })
                visualContent.height = Qt.binding(function() { return candidate.item.popupHeight })
                open({})
                opened = false
            }
        }
    }
    Timer {
        interval: 20
        running: candidate.item !== null && !root.previewReady
        repeat: true
        property int settled: 0
        onTriggered: {
            var panel = candidate.item
            if (root.teardownCheck && settled === -1) {
                if (panel.liveViews === 0 && panel.ownedProfile === null) {
                    root.checkPassed = true
                    root.previewReady = true
                }
                return
            }
            if (!panel.primaryBrowser || panel.primaryBrowser.loadState !== "SUCCEEDED") return
            if (++settled < 15) return
            if (root.interactionCheck && root.retained === null) {
                root.retained = "PENDING"
                panel.primaryBrowser.runJavaScript("document.querySelector('input').value='Warm fixture draft'; true", function(ok) {
                    panel.close()
                    panel.open({})
                    panel.opened = false
                    panel.visualContent.parent = root
                    panel.visualContent.width = Qt.binding(function() { return panel.popupWidth })
                    panel.visualContent.height = Qt.binding(function() { return panel.popupHeight })
                    panel.primaryBrowser.runJavaScript("document.querySelector('input').value", function(value) {
                        root.retained = value
                        root.checkPassed = ok && value === "Warm fixture draft" && panel.liveViews === 1
                    })
                })
                return
            }
            if (root.interactionCheck && (!root.checkPassed || settled < 45)) return
            if (root.teardownCheck) {
                // Exercise true host Loader removal, not only close().
                candidate.active = false
                Qt.callLater(function() { root.checkPassed = candidate.item === null; root.previewReady = root.checkPassed })
                return
            }
            root.previewReady = true
        }
    }
    Component.onCompleted: candidate.active = true
}
