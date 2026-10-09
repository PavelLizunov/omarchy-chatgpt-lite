import QtQuick
import qs.Ui as Ui
import "Icons.js" as Icons

Ui.Button {
    id: root
    property string symbol: "chat"
    focusable: true
    horizontalPadding: 8
    verticalPadding: 7
    implicitWidth: 34
    implicitHeight: 34
    Accessible.role: Accessible.Button
    Accessible.name: tooltipText
    Image {
        anchors.centerIn: parent
        width: 19
        height: 19
        sourceSize: Qt.size(38, 38)
        source: Icons.source(root.symbol, String(root.foreground))
    }
}
