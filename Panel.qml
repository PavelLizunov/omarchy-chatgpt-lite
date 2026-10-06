import QtQuick
import Quickshell.Io

// Headless host entry. The original site is displayed by the owned GTK process.
Item {
    id: root
    visible: false
    property var shell: null
    property var manifest: null
    property var pluginRegistry: null
    property bool opened: false
    property bool starting: false
    property string pending: ""
    property string scriptPath: decodeURIComponent(String(Qt.resolvedUrl("app.py")).replace(/^file:\/\//, ""))
    readonly property bool processRunning: application.running

    function open(payload) {
        if (application.running) {
            if (starting) pending = "show"
            else application.write("show\n")
            return
        }
        starting = true
        pending = "show"
        application.running = true
    }

    function close() {
        pending = "hide"
        if (application.running && !starting) application.write("hide\n")
    }

    function consume(line) {
        if (String(line).length > 1024) return
        var frame
        try { frame = JSON.parse(line) } catch (e) { return }
        if (!frame || frame.schema !== 1) return
        if (["STOPPED", "HIDDEN", "VISIBLE"].indexOf(frame.state) === -1) return
        opened = frame.state === "VISIBLE"
        if (starting) {
            starting = false
            if (pending === "hide") application.write("hide\n")
            pending = ""
        }
    }

    Connections {
        target: root.pluginRegistry
        function onEnabledChanged() {
            if (root.pluginRegistry && root.pluginRegistry.enabled === false && application.running)
                application.write("quit\n")
        }
    }

    Process {
        id: application
        command: ["/usr/bin/env", "LD_PRELOAD=/usr/lib/libgtk4-layer-shell.so", "GDK_BACKEND=wayland",
                  "PYTHONDONTWRITEBYTECODE=1", "/usr/bin/python", root.scriptPath, "show", "--host-pipe"]
        stdinEnabled: true
        stdout: SplitParser { onRead: function(line) { root.consume(line) } }
        onRunningChanged: if (!running) {
            root.opened = false
            root.starting = false
            root.pending = ""
        }
    }
    // Process destruction closes the owning stdin channel. EOF terminates the
    // application. This must be tested in the actual host before deployment.
    Component.onDestruction: if (application.running) application.write("quit\n")
}
