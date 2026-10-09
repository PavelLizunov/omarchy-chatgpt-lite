pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../native" as Candidate
Item {
    id: root
    width: 620
    height: 640
    property string socketPath: ""
    property string helperPath: Quickshell.env("CHATGPT_TEST_HELPER") || ""
    property bool checkPassed: false
    property int phase: 0
    Candidate.ServoService {
        id: service
        objectName: "recoveryController"
        fixtureMode: true
        managedEngine: true
        profileReady: true
        nativeSocketPath: root.socketPath
        controlProgram: root.helperPath
    }
    Timer {
        interval: 100
        running: !root.checkPassed
        repeat: true
        onTriggered: {
            if (service.recoveryBusy) return
            if (root.phase === 0) {
                root.phase = 1
                service.restartEngine()
                service.restartEngine() // Single-flight: second call must be ignored.
            } else if (root.phase === 1) {
                if (service.startupError !== "NONE" || service.servoSocketPath !== root.socketPath) return
                root.phase = 2
                service.controlProgram = "/missing/servo-helper"
                service.restartEngine()
            } else if (root.phase === 2) {
                if (service.startupError !== "SERVO_RECOVERY_FAILED") return
                root.phase = 3
                root.checkPassed = true
            }
        }
    }
}
