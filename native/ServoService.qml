import QtQuick
import Quickshell
import Quickshell.Io
import "servo-metrics-module" as Metrics

// Explicit experimental entry point; uses a separate engine/profile, never migrates cookies.
Service {
    id: root
    useServo: true
    property string servoUnitName: Quickshell.env("CHATGPT_SERVO_UNIT") || ""
    property string servoEnginePath: Quickshell.env("CHATGPT_SERVO_ENGINE") || ""
    property bool managedEngine: !fixtureMode
    property string controlProgram: decodeURIComponent(String(Qt.resolvedUrl("servo-control.sh")).replace(/^file:\/\//, ""))
    engineController: managedEngine ? controller : null
    QtObject {
        id: controller
        property bool stopping: false
        property bool restoreOpen: false
        property bool timedOut: false
        function run(action) {
            if (control.running || root.recoveryBusy) return
            timedOut = false
            restoreOpen = root.opened || action === "start"
            root.recoveryBusy = true
            root.startupError = "SERVO_RECOVERING"
            if (root.primaryBrowser) root.primaryBrowser.shutdownTransport()
            root.servoSocketPath = ""
            control.command = [root.controlProgram, action]
            deadline.start()
            control.running = true
        }
        function start() { run("start") }
        function restart() { run("restart") }
        function stop() {
            if (stopping) return
            stopping = true
            stopControl.running = true
        }
    }
    Process {
        id: control
        onRunningChanged: {
            if (!running && root.recoveryBusy && !controller.timedOut) {
                deadline.stop()
                root.recoveryBusy = false
                root.startupError = "SERVO_RECOVERY_FAILED"
            }
        }
        onExited: function(code, status) {
            deadline.stop()
            root.recoveryBusy = false
            if (root.shuttingDown || controller.timedOut) return
            if (code !== 0) { root.startupError = "SERVO_RECOVERY_FAILED"; return }
            root.servoSocketPath = root.nativeSocketPath
            root.startupError = "NONE"
            if (controller.restoreOpen) root.open({})
        }
    }
    Timer {
        id: deadline
        interval: 30000
        onTriggered: {
            controller.timedOut = true
            control.signal(9)
            root.recoveryBusy = false
            root.startupError = "SERVO_RECOVERY_TIMEOUT"
        }
    }
    Process {
        id: stopControl
        command: [root.controlProgram, "stop"]
    }
    servoResources: metrics.resources
    Metrics.ServoMetrics {
        id: metrics
        active: root.opened && !root.shuttingDown
        unitName: root.servoUnitName
        enginePath: root.servoEnginePath
    }
    useWpe: false
    property string nativeSocketPath: Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/chatgpt-servo-native/native.sock" : ""
    servoSocketPath: managedEngine ? "" : nativeSocketPath
}
