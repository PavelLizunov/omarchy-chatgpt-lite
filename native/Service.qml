pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtWebEngine
import QtQuick.Dialogs
import qs.Commons
import qs.Ui as Ui
import "resource-module" as Resources
import "wpe-module" as WpeModule
import "wpe" as Wpe

// One service-owned warm browser, presented only through an attached bar widget.
Item {
    id: root
    property var shell: null
    property var manifest: null
    property var pluginRegistry: null
    property bool opened: false
    property Item anchorItem: null
    property QtObject bar: null
    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    readonly property var targetScreen: anchorWindow ? anchorWindow.screen : (fixtureMode ? Quickshell.screens[0] : null)
    property bool expanded: false
    property int designVariant: 0
    property int paletteChoice: 0
    readonly property string paletteName: [qsTr("Desktop"), qsTr("Light"), qsTr("Dark"), qsTr("Forest")][paletteChoice] || qsTr("Desktop")
    readonly property color panelBackground: paletteChoice === 1 ? "#faf8f2" : paletteChoice === 2 ? "#1e1f2b" : paletteChoice === 3 ? "#10231b" : Color.popups.background
    readonly property color panelForeground: paletteChoice === 1 ? "#24252a" : paletteChoice === 2 ? "#e1e4f0" : paletteChoice === 3 ? "#d8e5c4" : Color.popups.text
    readonly property color panelBorder: paletteChoice === 1 ? "#c3c1b7" : paletteChoice === 2 ? "#5f6684" : paletteChoice === 3 ? "#64846d" : Color.popups.border
    readonly property var rendererPids: {
        var pids = primaryBrowser ? [primaryBrowser.renderProcessPid] : []
        for (var i = 0; i < auxiliaries.length; i++) pids.push(auxiliaries[i].browser.renderProcessPid)
        return pids
    }
    property var engineController: null
    property bool recoveryBusy: false
    function reloadPage() {
        if (!recoveryBusy && primaryBrowser) primaryBrowser.reload()
    }
    function restartEngine() {
        if (engineController && !recoveryBusy && !shuttingDown) engineController.restart()
    }
    property var servoResources: ({state: "unavailable", scope: "servo-engine"})
    readonly property var resourcePages: useServo ? servoResources : resourceMonitor.pages
    readonly property var resourceShell: resourceMonitor.shell
    Resources.ResourceMonitor {
        id: resourceMonitor
        active: root.opened && !root.shuttingDown && !root.useServo
        rendererPids: root.rendererPids
    }
    readonly property int availableWidth: targetScreen ? Math.max(1, targetScreen.width - Style.gapsOut * 2) : Style.space(460)
    readonly property int availableHeight: targetScreen ? Math.max(1, targetScreen.height - (anchorWindow ? anchorWindow.height : 32) - Style.gapsOut * 2) : Style.space(560)
    readonly property int popupWidth: expanded ? availableWidth : Math.min(Style.space(460), availableWidth)
    readonly property int popupHeight: expanded ? availableHeight : Math.min(Style.space(560), availableHeight)
    readonly property alias popup: surface
    property bool initialized: false
    // Inert consumers may supply an off-record profile; production owns its disk profile.
    property var suppliedProfile: null
    property bool fixtureMode: false
    property bool useWpe: !fixtureMode && !useServo
    // Explicit environment opt-in; no implicit replacement or profile migration.
    property bool useServo: !fixtureMode && Quickshell.env("CHATGPT_SERVO_NATIVE_SOCKET") !== ""
    property string servoSocketPath: Quickshell.env("CHATGPT_SERVO_NATIVE_SOCKET") || ""
    property string fixtureHtml: ""
    // Off by default. Enable only for an explicitly consented local capture.
    property bool captureEnabled: false
    Loader {
        active: root.captureEnabled && !root.useWpe && !root.useServo
        source: "Capture.qml"
        onLoaded: {
            item.browser = Qt.binding(function() { return root.primaryBrowser })
            item.presented = Qt.binding(function() { return surface.visible })
        }
    }
    QtObject { id: servoTransportProfile }
    readonly property var ownedProfile: suppliedProfile || (useServo ? servoTransportProfile : (profileLoader.item ? profileLoader.item.profile : null))
    readonly property alias visualContent: surface.contentItem
    readonly property var primaryBrowser: content.item ? content.item.browser : null
    property var auxiliaries: []
    property bool preparing: false
    property bool profileReady: false
    property bool pendingOpen: false
    property bool shuttingDown: false
    property int liveViews: 0
    readonly property bool hostCompatible: Qt.application.arguments.length > 0
    property string startupError: "NONE"
    readonly property string dataRoot: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/omarchy-chatgpt-lite-qt"
    readonly property string cacheRoot: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/omarchy-chatgpt-lite-qt"
    readonly property bool browserRunning: content.item !== null

    function attach(widgetBar, widgetAnchor) {
        if (opened && anchorItem !== widgetAnchor) close()
        bar = widgetBar
        anchorItem = widgetAnchor
    }
    function open(payload) {
        if (shuttingDown) return
        // Qt WebEngine fatally aborts if the host discarded argv[0] at startup.
        // Refuse before creating any Chromium profile in affected stock hosts.
        if (!useWpe && !useServo && !hostCompatible) {
            startupError = "HOST_ARGUMENTS_EMPTY"
            return
        }
        if (!targetScreen || (!fixtureMode && !anchorWindow)) return
        if (useServo && engineController && (!servoSocketPath || (primaryBrowser && primaryBrowser.transportError.length > 0))) {
            if (primaryBrowser && primaryBrowser.transportError.length > 0) engineController.restart()
            else engineController.start()
            return
        }
        if (useServo && !servoSocketPath) {
            startupError = "SERVO_TRANSPORT_UNAVAILABLE"
            return
        }
        if ((useWpe || useServo) && !profileReady) profileReady = true
        if (!profileReady) {
            pendingOpen = true
            if (!preparing) {
                preparing = true
                startupError = "NONE"
                prepareDeadline.start()
                prepare.running = true
            }
            return
        }
        if (!ownedProfile) {
            pendingOpen = true
            profileLoader.active = true
            return
        }
        initialized = true
        content.active = true
        pendingOpen = false
        opened = true
        Qt.callLater(function() {
            if (opened && content.item) content.item.browser.forceActiveFocus()
        })
    }
    function close() {
        pendingOpen = false
        opened = false
        // Linked windows have independent presentation; only shutdown destroys them.
    }
    function toggle() { opened ? close() : open({}) }
    function toggleExpanded() {
        if (shuttingDown) return
        expanded = !expanded
        Qt.callLater(function() {
            if (root.opened && root.primaryBrowser) root.primaryBrowser.forceActiveFocus()
        })
    }
    onOpenedChanged: {
        if (!bar) return
        if (opened) bar.requestPopout(root)
        else bar.releasePopout(root)
    }
    function viewReleased() {
        liveViews = Math.max(0, liveViews - 1)
        if (shuttingDown && liveViews === 0) Qt.callLater(function() {
            if (root.shuttingDown && root.liveViews === 0) profileLoader.active = false
        })
    }
    function shutdown() {
        if (shuttingDown) return
        shuttingDown = true
        if (useServo && primaryBrowser) primaryBrowser.shutdownTransport()
        if (engineController) engineController.stop()
        prepare.running = false
        if (saveDownload.pending) saveDownload.pending.cancel()
        saveDownload.pending = null
        saveDownload.close()
        close()
        for (var i = 0; i < auxiliaries.length; i++) auxiliaries[i].destroy()
        auxiliaries = []
        // Loader and destroy() defer deletion. Release the profile only after
        // the final view confirms destruction, never in the same scheduling tick.
        content.active = false
        initialized = false
        if (liveViews === 0) profileLoader.active = false
    }
    function releaseAuxiliary(window) {
        if (auxiliaries.indexOf(window) === -1) return
        auxiliaries = auxiliaries.filter(function(item) { return item !== window })
        window.destroy()
    }
    function createAuxiliary(request, sourceBrowser) {
        if (useServo) return // No fabricated OAuth/related-window support.
        var source = sourceBrowser || primaryBrowser
        var foregroundSource = source === primaryBrowser ? opened : auxiliaries.some(function(window) {
            return window.visible && window.browser === source
        })
        if (shuttingDown || !foregroundSource || !content.item || auxiliaries.length >= 3
                || (String(request.requestedUrl) !== "" && !content.item.browser.safeUrl(request.requestedUrl))) return
        // Surface ownership also orders whole-root destruction: all views die
        // before the profile holder, including direct host Loader removal.
        var child = (useWpe ? wpeAuxiliary : auxiliary).createObject(surface, useWpe ? {sourceBrowser: source} : {})
        if (!child) return
        auxiliaries = auxiliaries.concat([child])
        request.openIn(child.browser)
        if (!useWpe || fixtureMode) child.visible = true
    }

    Process {
        id: prepare
        command: [decodeURIComponent(String(Qt.resolvedUrl("prepare-profile")).replace(/^file:\/\//, ""))]
        onRunningChanged: {
            if (running) prepareDeadline.start()
            else {
                prepareDeadline.stop()
                // FailedToStart has no exited signal in the installed host.
                if (root.preparing) {
                    root.preparing = false
                    root.pendingOpen = false
                    root.profileReady = false
                    root.startupError = "PROFILE_PATH_FAILED"
                }
            }
        }
        onExited: function(exitCode, exitStatus) {
            if (root.shuttingDown) return
            root.preparing = false
            if (root.startupError === "PROFILE_PATH_TIMEOUT") {
                root.profileReady = false
                root.pendingOpen = false
                return
            }
            root.profileReady = exitCode === 0 && exitStatus === 0
            if (!root.profileReady) root.startupError = "PROFILE_PATH_FAILED"
            if (root.profileReady && root.pendingOpen) root.open({})
            else root.pendingOpen = false
        }
    }
    Timer {
        id: prepareDeadline
        interval: 5000
        onTriggered: {
            root.startupError = "PROFILE_PATH_TIMEOUT"
            root.preparing = false
            root.pendingOpen = false
            // Signal only the Process-owned child; late exit cannot revive startup.
            prepare.signal(9)
        }
    }
    IpcHandler {
        target: "slovn.chatgpt-lite"
        function status(): string {
            return JSON.stringify({schema: 1, state: root.opened ? "VISIBLE" : root.browserRunning ? "HIDDEN" : "STOPPED",
                engine: root.useServo ? "SERVO_EXPERIMENTAL" : root.useWpe ? "WPEWEBKIT" : "QTWEBENGINE", primary_views: root.browserRunning ? 1 : 0,
                auxiliary_views: root.auxiliaries.length,
                load_state: content.item ? content.item.browser.loadState : "IDLE", reduction: "DISABLED",
                host_compatible: root.hostCompatible, startup_error: root.startupError, recovery_busy: root.recoveryBusy,
                renderer_pids: root.rendererPids,
                presentation: "BAR_POPOVER", popup_width: root.popupWidth, popup_height: root.popupHeight,
                load_error_code: content.item ? content.item.browser.loadErrorCode : 0,
                popup_visible: surface.visible, anchor_x: surface.margins.left, anchor_y: surface.margins.top,
                appearance: "ORIGINAL_SITE", error_banner: content.item ? content.item.loadError : false,
                expanded: root.expanded, controls_visible: controls.visible,
                design_variant: root.designVariant + 1, palette: root.paletteName,
                resources: {pages: root.resourcePages, shared_shell: root.resourceShell}})
        }
        function reload(): void { root.reloadPage() }
        function restart(): void { root.restartEngine() }
        function toggleExpanded(): void {
            // Only resize an already open task-owned view; never launch a page.
            if (root.opened) root.toggleExpanded()
        }
    }
    FileDialog {
        id: saveDownload
        property var pending: null
        title: qsTr("Save ChatGPT download")
        fileMode: FileDialog.SaveFile
        onAccepted: {
            var file = String(selectedFile)
            var item = pending
            pending = null
            if (!item) return
            if (!file.startsWith("file:///")) { item.cancel(); return }
            var path = decodeURIComponent(file.slice(7))
            var split = path.lastIndexOf("/")
            if (split < 0 || split === path.length - 1) { item.cancel(); return }
            item.downloadDirectory = path.slice(0, split)
            item.downloadFileName = path.slice(split + 1)
            item.accept()
        }
        onRejected: { if (pending) pending.cancel(); pending = null }
    }
    Connections {
        target: (root.useWpe || root.useServo) ? null : root.ownedProfile
        function onDownloadRequested(download) {
            if (root.fixtureMode || root.shuttingDown || !root.opened || saveDownload.pending) {
                download.cancel()
                return
            }
            // Admission is one explicit user-chosen path, never a site-provided
            // arbitrary filesystem destination or automatic background download.
            saveDownload.pending = download
            saveDownload.open()
        }
    }
    Connections {
        target: root.pluginRegistry
        function onEnabledChanged() {
            if (root.pluginRegistry && root.pluginRegistry.enabled === false) root.shutdown()
        }
    }
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (root.targetScreen && Quickshell.screens.indexOf(root.targetScreen) === -1) root.close()
        }
    }
    PanelWindow {
        id: surface
        // Bounded OnDemand surface: no xdg-popup grab, no exclusive focus.
        // Dictation/virtual-keyboard handoffs must not dismiss the warm browser.
        visible: !root.fixtureMode && root.opened && !!root.anchorWindow
        screen: root.targetScreen
        color: root.panelBackground
        implicitWidth: root.popupWidth
        implicitHeight: root.popupHeight
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; left: true }
        WlrLayershell.namespace: "slovn-chatgpt-lite"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        onClosed: root.close()
        TransformWatcher {
            id: anchorWatcher
            a: root.anchorWindow ? root.anchorWindow.contentItem : null
            b: root.anchorItem
        }
        readonly property point cardOrigin: {
            anchorWatcher.transform
            var window = root.anchorWindow
            var screen = root.targetScreen
            if (!window || !screen || !root.anchorItem) return Qt.point(0, 0)
            var point = window.contentItem.mapFromItem(root.anchorItem, root.anchorItem.width / 2, 0)
            var position = root.bar ? root.bar.position : "top"
            var x = point.x - root.popupWidth / 2
            var y = window.height + Style.gapsOut
            if (position === "bottom") y = screen.height - window.height - root.popupHeight - Style.gapsOut
            else if (position === "left" || position === "right") {
                x = position === "left" ? window.width + Style.gapsOut : screen.width - window.width - root.popupWidth - Style.gapsOut
                y = point.y + root.anchorItem.height / 2 - root.popupHeight / 2
            }
            return Qt.point(Math.round(Math.max(Style.gapsOut, Math.min(x, screen.width - root.popupWidth - Style.gapsOut))),
                            Math.round(Math.max(Style.gapsOut, Math.min(y, screen.height - root.popupHeight - Style.gapsOut))))
        }
        margins { left: surface.cardOrigin.x; top: surface.cardOrigin.y }
        Ui.BorderSurface {
            id: popupFrame
            objectName: "chatgptNativeFrame"
            anchors.fill: parent
            color: root.panelBackground
            borderSpec: Border.localOrSurfaceSpec("popups", "border", root.panelBorder, root.panelBorder, Math.max(1, Style.space(2)))
            clip: true
        Header {
            id: controls
            service: root
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: popupFrame.contentLeftInset
            anchors.rightMargin: popupFrame.contentRightInset
            anchors.topMargin: popupFrame.contentTopInset
            height: implicitHeight
        }
        Loader {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: controls.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: popupFrame.contentLeftInset
            anchors.rightMargin: popupFrame.contentRightInset
            anchors.bottomMargin: popupFrame.contentBottomInset
            active: false
            sourceComponent: root.useServo ? servoContent : root.useWpe ? wpeContent : chromiumContent
            Component {
                id: chromiumContent
                Content {
                    browserProfile: root.ownedProfile
                    fixtureMode: root.fixtureMode
                    fixtureHtml: root.fixtureHtml
                    panelBackground: root.panelBackground
                    panelForeground: root.panelForeground
                    panelBorder: root.panelBorder
                    frameBorderWidth: 0
                    panelFontSize: Style.font.body
                    onAuxiliaryRequested: function(request) { root.createAuxiliary(request, browser) }
                    onDismissRequested: root.close()
                    Component.onCompleted: root.liveViews++
                    Component.onDestruction: root.viewReleased()
                }
            }
            Component {
                id: servoContent
                ServoContent {
                    socketPath: root.servoSocketPath
                    presented: root.opened
                    panelBackground: root.panelBackground
                    panelForeground: root.panelForeground
                    panelBorder: root.panelBorder
                    Component.onCompleted: root.liveViews++
                    Component.onDestruction: root.viewReleased()
                }
            }
            Component {
                id: wpeContent
                WpeContent {
                    browserProfile: root.ownedProfile
                    fixtureMode: root.fixtureMode
                    fixtureHtml: root.fixtureHtml
                    presented: root.opened
                    panelBackground: root.panelBackground
                    panelForeground: root.panelForeground
                    panelBorder: root.panelBorder
                    frameBorderWidth: 0
                    panelFontSize: Style.font.body
                    onAuxiliaryRequested: function(request) { root.createAuxiliary(request, browser) }
                    onDismissRequested: root.close()
                    Component.onCompleted: root.liveViews++
                    Component.onDestruction: root.viewReleased()
                }
            }
        }
    }
    }
    Component {
        id: auxiliary
        FloatingWindow {
            id: window
            visible: false
            implicitWidth: 620
            implicitHeight: 700
            title: qsTr("ChatGPT")
            // A layer-shell surface is not an xdg_toplevel parent.
            onClosed: root.releaseAuxiliary(window)
            readonly property alias browser: linked
            Browser {
                id: linked
                anchors.fill: parent
                profile: root.ownedProfile
                fixtureMode: root.fixtureMode
                backgroundColor: root.panelBackground
                onDismissRequested: root.releaseAuxiliary(window)
                onAuxiliaryRequested: function(request) { root.createAuxiliary(request, linked) }
                Component.onCompleted: root.liveViews++
                Component.onDestruction: root.viewReleased()
            }
        }
    }
    Component {
        id: wpeAuxiliary
        FloatingWindow {
            id: window
            required property var sourceBrowser
            visible: false
            implicitWidth: 620
            implicitHeight: 700
            title: qsTr("ChatGPT")
            readonly property alias browser: linked
            onClosed: root.releaseAuxiliary(window)
            Wpe.Browser {
                id: linked
                anchors.fill: parent
                profile: root.ownedProfile
                relatedView: window.sourceBrowser
                onReadyToShow: window.visible = true
                fixtureMode: root.fixtureMode
                fixtureHtml: root.fixtureHtml
                presented: window.visible
                onDismissRequested: root.releaseAuxiliary(window)
                onAuxiliaryRequested: function(request) { root.createAuxiliary(request, linked) }
                Component.onCompleted: root.liveViews++
                Component.onDestruction: root.viewReleased()
            }
        }
    }
    // Declared last so QObject whole-root cleanup releases surface-owned views
    // before the prototype's unique-owned profile, even without queued callbacks.
    Loader {
        id: profileLoader
        active: false
        sourceComponent: root.useWpe ? wpeProfile : chromiumProfile
        Component {
            id: wpeProfile
            WpeModule.WpeSession {
                id: wpeSession
                readonly property var profile: wpeSession
                ephemeral: root.fixtureMode
                dataPath: root.dataRoot.replace(/-qt$/, "-wpe") + "/profile"
                cachePath: root.cacheRoot.replace(/-qt$/, "-wpe") + "/cache"
                Component.onCompleted: {
                    if (!initialize()) { root.startupError = error; root.pendingOpen = false; return }
                    Qt.callLater(function() { if (root.pendingOpen) root.open({}) })
                }
            }
        }
        Component {
            id: chromiumProfile
            Item {
                id: holder
                property var profile: null
                WebEngineProfilePrototype {
                    id: prototype
                    storageName: root.fixtureMode ? "" : "slovn-chatgpt-lite-qt"
                    persistentStoragePath: root.fixtureMode ? "" : root.dataRoot + "/profile"
                    cachePath: root.fixtureMode ? "" : root.cacheRoot + "/cache"
                    persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
                }
                Component.onCompleted: {
                    profile = prototype.instance()
                    if (!profile) {
                        root.startupError = "PROFILE_IN_USE"
                        root.pendingOpen = false
                        profileLoader.active = false
                        return
                    }
                    Qt.callLater(function() {
                        if (root.pendingOpen && holder.profile) root.open({})
                    })
                }
            }
        }
    }
    Component.onDestruction: shutdown()
}
