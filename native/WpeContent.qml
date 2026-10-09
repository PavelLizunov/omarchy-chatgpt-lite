import QtQuick
import "wpe" as Wpe

// Actual panel content, also loaded by the offscreen actual-consumer fixture.
Rectangle {
    id: root
    required property var browserProfile
    required property color panelBackground
    required property color panelForeground
    required property color panelBorder
    property bool fixtureMode: false
    property bool presented: false
    property string fixtureHtml: ""
    readonly property bool loadError: view.loadState === "FAILED"
    property int panelFontSize: 14
    property int frameBorderWidth: 1
    readonly property alias browser: view
    readonly property alias statusStrip: statusBar
    readonly property bool ready: view.loadState === "SUCCEEDED"
    signal auxiliaryRequested(var request)
    signal dismissRequested()

    objectName: "chatgptPanelContent"
    color: panelBackground
    // Bound the embedded engine's scene-graph child during popup map and resize.
    clip: true
    border.color: panelBorder
    border.width: frameBorderWidth
    Wpe.Browser {
        id: view
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: statusBar.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.frameBorderWidth
        anchors.rightMargin: root.frameBorderWidth
        anchors.bottomMargin: root.frameBorderWidth
        profile: root.browserProfile
        backgroundColor: root.panelBackground
        fixtureMode: root.fixtureMode
        fixtureHtml: root.fixtureHtml
        presented: root.presented
        onAuxiliaryRequested: function(request) { root.auxiliaryRequested(request) }
        onDismissRequested: root.dismissRequested()
    }
    Component.onCompleted: {
        if (fixtureMode) view.loadHtml(fixtureHtml)
        else view.url = "https://chatgpt.com/"
    }
    Rectangle {
        id: statusBar
        objectName: "chatgptStatusStrip"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.frameBorderWidth
        visible: view.loadState === "LOADING" || root.loadError
        height: visible ? loadLabel.implicitHeight + root.panelFontSize : 0
        color: root.panelBackground
        clip: true
        // Reserve space outside the browser; never cover site error/security controls.
        Text {
            id: loadLabel
            objectName: "chatgptLoadStatus"
            anchors.centerIn: parent
            width: Math.max(1, parent.width - root.panelFontSize * 2)
            text: root.loadError ? (view.loadErrorCode > 0
                ? qsTr("ChatGPT could not load (%1).").arg(view.loadErrorCode)
                : qsTr("ChatGPT could not load.")) : qsTr("Loading ChatGPT…")
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: root.panelForeground
            font.pixelSize: root.panelFontSize
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: root.panelBorder
        }
    }
}
