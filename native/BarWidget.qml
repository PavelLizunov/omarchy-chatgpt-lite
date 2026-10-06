import QtQuick
import qs.Commons
import qs.Ui as Ui

// All monitor instances share the host-owned service and its one browser.
Ui.BarWidget {
    id: root
    moduleName: "slovn.chatgpt-lite"
    property var suppliedService: null
    readonly property var service: suppliedService || (bar && bar.shell ? bar.shell.serviceFor(moduleName) : null)
    readonly property bool opened: !!service && service.opened && service.anchorItem === button
    readonly property alias trigger: button

    function open() {
        if (!service || !bar) return
        service.attach(bar, button)
        service.open({})
    }
    function close() { if (service && service.anchorItem === button) service.close() }
    function toggle() { opened ? close() : open() }
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    Ui.BarIconButton {
        id: button
        objectName: "chatgptBarTrigger"
        anchors.fill: parent
        bar: root.bar
        text: "󰍩"
        tooltipText: qsTr("ChatGPT Lite")
        active: root.opened
        Accessible.name: qsTr("ChatGPT Lite")
        Accessible.role: Accessible.Button
        onPressed: function(mouseButton) { if (mouseButton === Qt.LeftButton) root.toggle() }
    }
    Component.onDestruction: {
        if (service && service.anchorItem === button) {
            service.close()
            service.attach(null, null)
        }
    }
}
