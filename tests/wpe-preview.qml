import QtQuick
import "../build/wpe"
Item {
    width: 460; height: 560
    property bool previewReady: browser.frameReady && browser.loadState === "SUCCEEDED"
    WpeView {
        id: browser
        fixtureMode: true
        presented: true
        objectName: "wpeCandidate"
        anchors.fill: parent
        fixtureHtml: `<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'"><body style="background:#eef3e9;color:#17251c;margin:24px;font:20px sans-serif"><h2>Native WPE surface</h2><input value="Inert draft"><button>Inert action</button><p>Original browser engine, QML frame.</p></body>`
    }
}
