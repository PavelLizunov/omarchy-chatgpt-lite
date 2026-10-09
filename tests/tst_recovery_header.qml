import QtQuick
import QtTest
import "../native" as Native
Item {
    width: 620
    height: 200
    QtObject {
        id: service
        property color panelBackground: "#101315"
        property color panelForeground: "#cacccc"
        property color panelBorder: "#cacccc"
        property int designVariant: 0
        property int paletteChoice: 0
        property string paletteName: "Desktop"
        property bool expanded: false
        property bool useServo: true
        property bool recoveryBusy: false
        property string startupError: "NONE"
        property var primaryBrowser: ({})
        property var resourcePages: ({state: "unavailable"})
        property int reloads: 0
        property int restarts: 0
        function reloadPage() { reloads++ }
        function restartEngine() { restarts++ }
        function toggleExpanded() { expanded = !expanded }
        function close() {}
    }
    Native.Header { id: header; width: 456; height: implicitHeight; service: service }
    TestCase {
        name: "RecoveryHeader"
        when: windowShown
        function test_mouse_and_keyboard() {
            var reload = findChild(header, "chatgptReloadButton")
            var restart = findChild(header, "chatgptRestartButton")
            verify(reload && restart)
            mouseClick(reload);compare(service.reloads, 1)
            mouseClick(restart);compare(service.restarts, 1)
            reload.forceActiveFocus();keyClick(Qt.Key_Return);compare(service.reloads, 2)
            restart.forceActiveFocus();keyClick(Qt.Key_Space);compare(service.restarts, 2)
            service.recoveryBusy = true
            verify(!reload.enabled && !restart.enabled)
            mouseClick(reload);mouseClick(restart)
            compare(service.reloads, 2);compare(service.restarts, 2)
            service.recoveryBusy = false
            verify(reload.tooltipText.indexOf("unsent text") !== -1)
            verify(restart.tooltipText.indexOf("unsent text") !== -1)
        }
    }
}
