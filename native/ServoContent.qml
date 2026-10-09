import QtQuick
import "servo-module" as Servo

// Experimental native frame transport; the engine lifecycle is owned separately.
Rectangle {
    id: root
    required property color panelBackground
    required property color panelForeground
    required property color panelBorder
    property string socketPath: ""
    property bool presented: false
    property int frameBorderWidth: 0
    readonly property alias browser: view
    readonly property bool ready: view.frameReady && view.transportError.length === 0
    readonly property bool loadError: view.transportError.length > 0
    objectName: "chatgptPanelContent"
    color: panelBackground
    clip: true
    border.color: panelBorder
    border.width: frameBorderWidth
    Servo.ServoView {
        id: view
        objectName: "chatgptServoBrowser"
        anchors.fill: parent
        socketPath: root.socketPath
        readonly property string loadState: transportError.length ? "FAILED" : frameReady ? "FRAME_READY" : "LOADING"
        readonly property int loadErrorCode: 0
        readonly property int renderProcessPid: 0 // Namespace identity not yet attested.
        function safeUrl(value) { return false } // Related windows are not implemented by this prototype.
    }
}
