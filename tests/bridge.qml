import QtQuick
import ".." as Candidate

// Actual candidate with the installed Quickshell.Io Process, inert I/O only.
Item {
    id: fixture
    property bool previewReady: false
    property int stage: 0
    property int ticks: 0
    property string result: "CHECKING"
    QtObject { id: registry; property bool enabled: true }
    Candidate.Panel {
        id: bridge
        scriptPath: Qt.resolvedUrl("inert_host.py").toString().replace(/^file:\/\//, "")
        pluginRegistry: registry
    }
    Text {
        anchors.centerIn: parent
        text: fixture.result
        color: "white"
    }
    Timer {
        interval: 20
        running: !fixture.previewReady
        repeat: true
        onTriggered: {
            fixture.ticks++
            if (fixture.ticks > 200) {
                fixture.result = "FAIL stage=" + fixture.stage
                fixture.previewReady = true
                return
            }
            if (fixture.stage === 0) {
                if (bridge.processRunning || bridge.opened) fixture.result = "FAIL mounted starts process"
                bridge.open({})
                fixture.stage = 1
            } else if (fixture.stage === 1 && bridge.opened) {
                bridge.close()
                fixture.stage = 2
            } else if (fixture.stage === 2 && !bridge.opened) {
                bridge.open({})
                fixture.stage = 3
            } else if (fixture.stage === 3 && bridge.opened) {
                registry.enabled = false
                fixture.stage = 4
            } else if (fixture.stage === 4 && !bridge.processRunning && !bridge.opened) {
                fixture.result = "PASS open / hide / show / disable"
                fixture.previewReady = true
            }
        }
    }
}
