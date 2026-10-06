pragma ComponentBehavior: Bound
import QtQuick
import QtWebEngine
import "../native" as Candidate

Item {
    id: root
    property bool lightTheme: false
    property bool previewReady: false
    Timer {
        interval: 300
        running: consumer.item !== null && consumer.item.browser.loadState === "SUCCEEDED" && !root.previewReady
        onTriggered: root.previewReady = true
    }
    readonly property var ephemeralProfile: WebEngineProfilePrototype {
        httpCacheType: WebEngineProfile.MemoryHttpCache
    }
    Loader {
        id: consumer
        anchors.fill: parent
        sourceComponent: root.profileReady ? candidate : null
    }
    property var readyProfile: null
    property bool profileReady: false
    Component.onCompleted: {
        readyProfile = ephemeralProfile.instance()
        profileReady = readyProfile !== null
    }
    Component {
      id: candidate
      Candidate.Content {
        id: panel
        anchors.fill: parent
        browserProfile: root.readyProfile
        panelBackground: root.lightTheme ? "#ffffff" : "#101315"
        panelForeground: root.lightTheme ? "#181818" : "#cacccc"
        panelBorder: root.lightTheme ? "#707880" : "#cacccc"
        fixtureMode: true
        fixtureHtml: "<!doctype html><meta charset='utf-8'><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; style-src 'unsafe-inline'\"><style>body{font:16px sans-serif;background:" + panel.panelBackground + ";color:" + panel.panelForeground + ";padding:20px}input{box-sizing:border-box;width:100%;padding:10px}button{padding:8px}pre{white-space:pre-wrap}h1{font-size:22px}</style><nav><button>New chat</button> <button>Model</button></nav><main><h1>Original-site browser fixture</h1><p>Inert local content. No account or network.</p><pre>const answer = 42;</pre><label>Draft<input id='draft' value='Retained fixture draft'></label><button>Send</button></main>"

    }
    }
}
