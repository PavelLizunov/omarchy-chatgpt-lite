pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../native" as Candidate
Item {
    id: root
    width: 620
    height: 640
    property string socketPath: ""
    property bool checkPassed: false
    Candidate.Service {
        id: service
        useServo: true
        useWpe: false
        fixtureMode: true
        profileReady: true
        servoSocketPath: root.socketPath
        captureEnabled: false
    }
    Item { id: card; x: 80; y: 20; width: service.popupWidth; height: service.popupHeight }
    Timer {
        interval: 100
        repeat: true
        running: !root.checkPassed
        onTriggered: {
            if (!service.primaryBrowser || !service.primaryBrowser.frameReady) return
            service.visualContent.parent = card
            service.visualContent.width = Qt.binding(function() { return card.width })
            service.visualContent.height = Qt.binding(function() { return card.height })
            root.checkPassed = service.liveViews === 1 && service.primaryBrowser.transportError.length === 0
        }
    }
    Component.onCompleted: {
        Color.popups.background = "#101315"
        Color.popups.text = "#cacccc"
        Color.popups.border = "#cacccc"
        service.open({})
    }
    Component.onDestruction: service.shutdown()
}
