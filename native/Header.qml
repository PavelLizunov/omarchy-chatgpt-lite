import QtQuick
import qs.Commons
import "Icons.js" as Icons

Rectangle {
    id: root
    required property var service
    objectName: "chatgptPopoverControls"
    color: service.panelBackground
    implicitHeight: service.designVariant === 1 ? 92 : 72
    Rectangle {
        visible: service.designVariant === 2
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 3
        color: service.panelForeground
    }
    readonly property bool variantReady: true
    function metric(value) {
        if (!value || value.state !== "ready") return qsTr("unavailable")
        return Math.round(value.rssMiB) + " MiB · "
            + (typeof value.cpuPercent === "number" ? value.cpuPercent.toFixed(1) + "%" : "…")
    }
    Image {
        id: logo
        x: 12; y: 11
        width: 24; height: 24
        sourceSize: Qt.size(48,48)
        source: Icons.source("chat", String(service.panelForeground))
    }
    Text {
        id: title
        x: logo.x + logo.width + 9
        y: 13
        text: "ChatGPT"
        color: service.panelForeground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: service.designVariant !== 0
        textFormat: Text.PlainText
    }
    Row {
        id: actions
        anchors.right: parent.right
        anchors.rightMargin: 8
        y: 5
        spacing: service.designVariant === 2 ? 8 : 2
        IconButton {
            objectName: "chatgptReloadButton"
            symbol: "reload"
            foreground: service.panelForeground
            tooltipText: qsTr("Reload page; unsent text may be lost")
            enabled: !service.recoveryBusy && !!service.primaryBrowser
            onClicked: service.reloadPage()
        }
        IconButton {
            objectName: "chatgptRestartButton"
            visible: service.useServo
            symbol: "restart"
            foreground: service.panelForeground
            tooltipText: qsTr("Restart ChatGPT engine; unsent text may be lost")
            enabled: !service.recoveryBusy
            onClicked: service.restartEngine()
        }
        IconButton {
            objectName: "chatgptVariantButton"
            symbol: "layout"
            foreground: service.panelForeground
            tooltipText: qsTr("Layout %1 of 3; switch").arg(service.designVariant + 1)
            onClicked: service.designVariant = (service.designVariant + 1) % 3
        }
        IconButton {
            objectName: "chatgptPaletteButton"
            symbol: "palette"
            foreground: service.panelForeground
            tooltipText: qsTr("Palette: %1; switch").arg(service.paletteName)
            onClicked: service.paletteChoice = (service.paletteChoice + 1) % 4
        }
        IconButton {
            objectName: "chatgptExpandButton"
            symbol: service.expanded ? "compact" : "expand"
            // Text retained as semantic state for existing consumer tests, not painted.
            text: ""
            property string actionName: service.expanded ? "Compact" : "Expand"
            foreground: service.panelForeground
            tooltipText: service.expanded ? qsTr("Compact") : qsTr("Expand")
            bordered: service.designVariant === 0
            onClicked: service.toggleExpanded()
        }
        IconButton {
            objectName: "chatgptCloseButton"
            symbol: "close"
            foreground: service.panelForeground
            tooltipText: qsTr("Hide ChatGPT")
            onClicked: service.close()
        }
    }
    Text {
        id: label
        objectName: "chatgptPageResourceLabel"
        x: service.designVariant === 2 ? 20 : 12; y: 47
        width: parent.width - 24
        text: service.recoveryBusy ? qsTr("Restarting ChatGPT engine…")
            : service.useServo && service.startupError !== "NONE" ? qsTr("Engine unavailable; try Restart")
            : service.useServo
            ? (service.designVariant === 1 ? qsTr("SERVO ENGINE") : qsTr("Servo engine: %1").arg(root.metric(service.resourcePages)))
            : (service.designVariant === 1 ? qsTr("PAGE RENDERERS") : qsTr("Page renderers: %1").arg(root.metric(service.resourcePages)))
        color: service.panelForeground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }
    Text {
        id: largeMetric
        objectName: "chatgptPageResourceValue"
        visible: service.designVariant === 1
        x: 12; y: 65
        text: root.metric(service.resourcePages)
        color: service.panelForeground
        font.family: Style.font.family
        font.pixelSize: Style.font.body + 3
        textFormat: Text.PlainText
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: service.designVariant === 2 ? 2 : 1
        color: service.panelBorder
    }
}
