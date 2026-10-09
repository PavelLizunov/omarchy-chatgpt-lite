pragma ComponentBehavior: Bound
import QtQuick
import QtWebEngine
import "../native" as Candidate

// Service/helper startup only. Off-record browser; explicit isolated helper paths.
Item {
    id: root
    property string testMode: "success"
    property string isolatedRoot: ""
    property bool previewReady: false
    property bool checkPassed: false
    property var preparation: null
    property bool timedOut: false
    property int helperPid: 0
    property var inertProfile: null
    onPreviewReadyChanged: if (previewReady) console.log("STARTUP_CHECK " + testMode + " passed=" + checkPassed + " error=" + service.startupError)
    WebEngineProfilePrototype { id: prototype; httpCacheType: WebEngineProfile.MemoryHttpCache }
    Candidate.Service {
        id: service
        fixtureMode: true
        captureEnabled: false
        suppliedProfile: root.inertProfile
        fixtureHtml: "<!doctype html><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'\"><p>Inert startup only</p>"
    }
    Timer {
        interval: 20
        repeat: true
        running: !root.previewReady
        onTriggered: {
            if (!root.preparation) return
            if (root.preparation.running) root.helperPid = Number(root.preparation.processId)
            if (root.testMode === "success") {
                if (!service.primaryBrowser || service.primaryBrowser.loadState !== "SUCCEEDED") return
                root.checkPassed = service.profileReady && !service.preparing && !service.pendingOpen
                    && service.opened && service.liveViews === 1 && service.startupError === "NONE"
                    && service.primaryBrowser.profile === service.suppliedProfile
                    && !service.popup.visible && !root.preparation.running
                console.log("STARTUP_STATE " + JSON.stringify({ready:service.profileReady, preparing:service.preparing,
                    pending:service.pendingOpen, opened:service.opened, views:service.liveViews,
                    sameProfile:service.primaryBrowser.profile === service.suppliedProfile,
                    popup:service.popup.visible, running:root.preparation.running}))
                root.previewReady = true
            } else if (["failure", "missing"].includes(root.testMode) && !service.preparing && !service.pendingOpen) {
                root.checkPassed = !service.profileReady && !service.primaryBrowser
                    && !service.opened && service.startupError === "PROFILE_PATH_FAILED"
                    && !root.preparation.running
                root.previewReady = true
            } else if (root.testMode === "timeout") {
                if (service.startupError === "PROFILE_PATH_TIMEOUT") root.timedOut = true
                // Observe the result after process cancellation, not only timer firing.
                if (root.timedOut && !root.preparation.running) {
                    timeoutSettled.start()
                    stop()
                }
            }
        }
    }
    Timer {
        id: timeoutSettled
        interval: 300
        onTriggered: {
            root.checkPassed = root.helperPid > 0 && !service.profileReady && !service.primaryBrowser
                && !service.preparing && !service.pendingOpen && !service.opened
                && service.startupError === "PROFILE_PATH_TIMEOUT" && !root.preparation.running
            root.previewReady = true
        }
    }
    Component.onCompleted: {
        if (!isolatedRoot.startsWith("/") || !["success", "failure", "timeout", "missing"].includes(testMode)) return
        for (var i = 0; i < service.resources.length; i++) {
            var object = service.resources[i]
            if (object.command !== undefined && object.command.length === 1
                    && String(object.command[0]).endsWith("/prepare-profile")) root.preparation = object
        }
        if (!root.preparation) return
        root.inertProfile = prototype.instance()
        if (!root.inertProfile || !root.inertProfile.offTheRecord) return
        root.preparation.environment = {
            XDG_DATA_HOME: testMode === "failure" ? "relative-refused" : isolatedRoot + "/data",
            XDG_CACHE_HOME: isolatedRoot + "/cache"
        }
        // Controlled failure injection only in the reviewed inert fixture.
        // Success/failure invoke the unchanged installed C++ helper path.
        if (testMode === "timeout") root.preparation.command = ["/usr/bin/sleep", "8"]
        if (testMode === "missing") root.preparation.command = [isolatedRoot + "/absent-helper"]
        service.open({})
    }
    Component.onDestruction: service.shutdown()
}
