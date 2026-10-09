import QtQuick
import QtWebEngine
import "../native/resource-module" as Resources
import "../native" as Candidate

Item {
    id: root
    property bool checkPassed: false
    property var storedProfile: null
    property var oldData: null
    property int stage: 0
    property int ticks: 0
    onStageChanged: console.log("RESOURCE_STAGE " + stage)
    WebEngineProfilePrototype { id: prototype }
    readonly property var browser: browserLoader.item
    Loader {
        id: browserLoader
        active: !!root.storedProfile
        sourceComponent: Component {
            Candidate.Browser {
                fixtureMode: true
                profile: root.storedProfile
                Component.onCompleted: loadHtml("<!doctype html><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'\"><p>Resource test</p>")
            }
        }
    }
    Connections {
        target: monitor
        function onUpdated() { console.log("RESOURCE_SAMPLE " + JSON.stringify(monitor.pages)) }
    }
    Resources.ResourceMonitor {
        id: monitor
        rendererPids: browser ? [browser.renderProcessPid, browser.renderProcessPid] : []
    }
    Timer {
        interval: 100
        repeat: true
        running: !root.checkPassed
        onTriggered: {
            if (!browser || browser.loadState !== "SUCCEEDED" || browser.renderProcessPid <= 0) return
            if (root.stage === 0) {
                monitor.rendererPids = [browser.renderProcessPid, browser.renderProcessPid]
                console.log("RESOURCE_PIDS " + JSON.stringify(monitor.rendererPids))
                monitor.active = true
                root.stage = 1
            } else if (root.stage === 1 && typeof monitor.pages.cpuPercent === "number") {
                console.log("RESOURCE_READY " + JSON.stringify(monitor.pages))
                if (monitor.pages.state !== "ready" || monitor.pages.processes !== 1 || monitor.pages.rssMiB <= 0
                        || monitor.shell.state !== "ready") return
                monitor.rendererPids = [1] // unrelated kernel init must never count as chat
                if (monitor.pages.state !== "unavailable" || monitor.pages.rssMiB !== undefined) return
                monitor.active = false
                if (monitor.pages.state !== "inactive") return
                root.oldData = JSON.stringify(monitor.pages)
                root.stage = 2
            } else if (root.stage === 2 && ++root.ticks > 22) {
                if (JSON.stringify(monitor.pages) !== root.oldData) return
                monitor.rendererPids = [browser.renderProcessPid]
                monitor.active = true
                if (monitor.pages.cpuPercent !== null && monitor.pages.cpuPercent !== undefined) {
                    console.log("RESOURCE_RESET " + JSON.stringify(monitor.pages)); return
                }
                root.stage = 3
            } else if (root.stage === 3 && typeof monitor.pages.cpuPercent === "number") {
                root.checkPassed = monitor.pages.state === "ready"
                monitor.active = false
                console.log("RESOURCE_CHECK passed=" + root.checkPassed)
            }
        }
    }
    Component.onCompleted: root.storedProfile = prototype.instance()
}
