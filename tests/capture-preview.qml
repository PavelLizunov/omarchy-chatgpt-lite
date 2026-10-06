pragma ComponentBehavior: Bound
import QtQuick
import QtWebEngine
import "../native" as Candidate

// Real candidate Browser, one off-record profile. Never production storage.
// Capture reads this existing Chromium composition; it does not load replacement
// HTML, change URL, visibility, geometry or focus as part of the capture request.
Item {
    id: root
    property bool previewReady: false
    property bool hideForCapture: false
    property bool enableCapture: true
    property var ephemeralProfile: null
    WebEngineProfilePrototype { id: prototype; httpCacheType: WebEngineProfile.MemoryHttpCache }
    Loader {
        id: browserLoader
        anchors.fill: parent
        active: root.ephemeralProfile !== null
        sourceComponent: Component {
            Candidate.Browser {
                id: browser
                profile: root.ephemeralProfile
                fixtureMode: true
                backgroundColor: "#ffffff"
                visible: !root.hideForCapture
                Component.onCompleted: loadHtml("<!doctype html><meta charset='utf-8'><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; style-src 'unsafe-inline'\"><style>body{margin:0;background:#ffffff;font:22px sans-serif}.red{background:#e91e63;height:100px}.blue{background:#1565c0;height:100px;color:white}</style><div class='red'>CHROMIUM PRIMARY PIXELS</div><div class='blue'>Local off-record page, not ChatGPT</div><p>No account, navigation or interaction coverage.</p>")
            }
        }
    }
    Loader {
        id: bridge
        active: root.enableCapture && browserLoader.item !== null
        sourceComponent: Component {
            Candidate.Capture {
                browser: browserLoader.item
                presented: !root.hideForCapture
                onCaptured: root.previewReady = true
            }
        }
    }
    Timer {
        interval: 6000
        running: true
        onTriggered: root.previewReady = true
    }
    Component.onCompleted: root.ephemeralProfile = prototype.instance()
}
