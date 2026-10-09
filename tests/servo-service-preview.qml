pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import qs.Commons
import "../native" as Candidate
Rectangle {
    id: root
    width: 620
    height: 640
    color: "#101315"
    property string socketPath: ""
    property string acceptancePath: ""
    readonly property bool previewReady: checkPassed && pageAccepted
    property bool pageAccepted: false
    property var metricsSample: ({state: "unavailable", scope: "servo-engine"})
    property bool checkPassed: false
    property bool inputSent: false
    property var retained: null
    QtObject { id: inertProfile }
    Candidate.Service {
        id: service
        useServo: true
        useWpe: false
        servoResources: root.metricsSample
        fixtureMode: true
        suppliedProfile: inertProfile
        profileReady: true
        servoSocketPath: root.socketPath
        captureEnabled: false
    }
    Item {
        id: card
        objectName: "servoServiceCard"
        x: 80
        y: 20
        width: service.popupWidth
        height: service.popupHeight
    }
    Timer {
        interval: 100
        repeat: true
        running: !root.inputSent
        onTriggered: {
            var view = service.primaryBrowser
            if (!view || !view.frameReady) return
            service.visualContent.parent = card
            service.visualContent.width = Qt.binding(function() { return card.width })
            service.visualContent.height = Qt.binding(function() { return card.height })
            root.retained = view
            root.inputSent = true
            inputTimer.start()
        }
    }
    Timer {
        id: inputTimer
        interval: 1800
        onTriggered: {
            service.primaryBrowser.pointer(60, 30, true)
            service.primaryBrowser.pointer(60, 30, false)
            service.primaryBrowser.commit("native-probe")
            actionTimer.start()
        }
    }
    Timer {
        id: actionTimer
        interval: 700
        onTriggered: {
            service.primaryBrowser.pointer(60, 80, true)
            service.primaryBrowser.pointer(60, 80, false)
            settleTimer.start()
        }
    }
    Timer {
        id: settleTimer
        interval: 1200
        onTriggered: {
            root.checkPassed = service.primaryBrowser === root.retained && service.liveViews === 1 && service.opened && service.primaryBrowser.frameReady && service.primaryBrowser.transportError.length === 0
            service.close()
            service.open({})
            root.checkPassed = root.checkPassed && service.primaryBrowser === root.retained
        }
    }
    FileView {
        id: acceptance
        path: root.acceptancePath
        printErrors: false
        onLoaded: {
            try { var value = JSON.parse(text()); root.pageAccepted = value.draft === true && value.action === true && value.viewport === true }
            catch (error) { root.pageAccepted = false }
        }
    }
    Timer { interval: 100; repeat: true; running: !root.pageAccepted; onTriggered: acceptance.reload() }
    Component.onCompleted: {
        Color.popups.background = "#101315"
        Color.popups.text = "#cacccc"
        Color.popups.border = "#cacccc"
        service.open({})
    }
    Component.onDestruction: service.shutdown()
}
