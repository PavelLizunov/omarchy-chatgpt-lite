import QtQuick
import "../native" as Native
Item {
    id: root
    width: 620
    height: 140
    property bool busy: false
    property bool failed: false
    property bool light: false
    readonly property int reloads: service.reloads
    readonly property int restarts: service.restarts
    function imagesReady(item) {
        if (item.source !== undefined && item.status !== undefined && String(item.source) !== "" && item.status !== Image.Ready) return false
        for (var i = 0; i < item.children.length; i++) if (!imagesReady(item.children[i])) return false
        return true
    }
    property bool previewReady: false
    Timer {
        interval: 20
        repeat: true
        running: !root.previewReady
        onTriggered: root.previewReady = root.imagesReady(header)
    }
    QtObject {
        id: service
        property color panelBackground: root.light ? "#faf8f2" : "#101315"
        property color panelForeground: root.light ? "#24252a" : "#cacccc"
        property color panelBorder: root.light ? "#c3c1b7" : "#cacccc"
        property int designVariant: 0
        property int paletteChoice: 0
        property string paletteName: "Desktop"
        property bool expanded: false
        property bool useServo: true
        property bool recoveryBusy: root.busy
        property string startupError: root.failed ? "SERVO_RECOVERY_FAILED" : "NONE"
        property var primaryBrowser: ({})
        property var resourcePages: ({state: "unavailable"})
        property int reloads: 0
        property int restarts: 0
        function reloadPage() { reloads++ }
        function restartEngine() { restarts++ }
        function toggleExpanded() { expanded = !expanded }
        function close() {}
    }
    Native.Header { id: header; width: parent.width; height: implicitHeight; service: service }
}
