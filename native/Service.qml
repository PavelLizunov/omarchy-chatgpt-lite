pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import QtWebEngine
import QtQuick.Dialogs
import qs.Commons
import qs.Ui as Ui

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
    readonly property int availableWidth: targetScreen ? Math.max(1, targetScreen.width - Style.gapsOut * 2) : Style.space(460)
    readonly property int availableHeight: targetScreen ? Math.max(1, targetScreen.height - (anchorWindow ? anchorWindow.height : 32) - Style.gapsOut * 2) : Style.space(560)
    readonly property int popupWidth: expanded ? availableWidth : Math.min(Style.space(460), availableWidth)
    readonly property int popupHeight: expanded ? availableHeight : Math.min(Style.space(560), availableHeight)
    readonly property alias popup: surface
    property bool initialized: false
    // Inert consumers may supply an off-record profile; production owns its disk profile.
    property var suppliedProfile: null
    property bool fixtureMode: false
    property string fixtureHtml: ""
    // Off by default. Enable only for an explicitly consented local capture.
    property bool captureEnabled: false
    Loader {
        active: root.captureEnabled
        source: "Capture.qml"
        onLoaded: {
            item.browser = Qt.binding(function() { return root.primaryBrowser })
            item.presented = Qt.binding(function() { return surface.visible })
        }
    }
    readonly property var ownedProfile: suppliedProfile || (profileLoader.item ? profileLoader.item.profile : null)
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
        if (!hostCompatible) {
            startupError = "HOST_ARGUMENTS_EMPTY"
            return
        }
        if (!targetScreen || (!fixtureMode && !anchorWindow)) return
        if (!profileReady) {
            pendingOpen = true
            if (!preparing) {
                preparing = true
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
        var source = sourceBrowser || primaryBrowser
        var foregroundSource = source === primaryBrowser ? opened : auxiliaries.some(function(window) {
            return window.visible && window.browser === source
        })
        if (shuttingDown || !foregroundSource || !content.item || auxiliaries.length >= 3
                || (String(request.requestedUrl) !== "" && !content.item.browser.safeUrl(request.requestedUrl))) return
        // Surface ownership also orders whole-root destruction: all views die
        // before the profile holder, including direct host Loader removal.
        var child = auxiliary.createObject(surface)
        if (!child) return
        auxiliaries = auxiliaries.concat([child])
        request.openIn(child.browser)
        child.visible = true
    }

    Process {
        id: prepare
        command: ["/usr/bin/python", "-B", decodeURIComponent(String(Qt.resolvedUrl("prepare-profile.py")).replace(/^file:\/\//, ""))]
        onExited: function(exitCode, exitStatus) {
            if (root.shuttingDown) return
            root.preparing = false
            root.profileReady = exitCode === 0 && exitStatus === 0
            if (!root.profileReady) root.startupError = "PROFILE_PATH_FAILED"
            if (root.profileReady && root.pendingOpen) root.open({})
            else root.pendingOpen = false
        }
    }
    IpcHandler {
        target: "slovn.chatgpt-lite"
        function status(): string {
            return JSON.stringify({schema: 1, state: root.opened ? "VISIBLE" : root.browserRunning ? "HIDDEN" : "STOPPED",
                engine: "QTWEBENGINE", primary_views: root.browserRunning ? 1 : 0,
                auxiliary_views: root.auxiliaries.length,
                load_state: content.item ? content.item.browser.loadState : "IDLE", reduction: "DISABLED",
                host_compatible: root.hostCompatible, startup_error: root.startupError,
                presentation: "BAR_POPOVER", popup_width: root.popupWidth, popup_height: root.popupHeight,
                load_error_code: content.item ? content.item.browser.loadErrorCode : 0,
                popup_visible: surface.visible, anchor_x: surface.anchor.rect.x, anchor_y: surface.anchor.rect.y,
                appearance: "OMARCHY_CSS", error_banner: content.item ? content.item.loadError : false,
                expanded: root.expanded, controls_visible: controls.visible})
        }
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
        target: root.ownedProfile
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
    PopupWindow {
        id: surface
        // A native xdg popup, not a full-screen layer or an Exclusive focus grab.
        // Inert preview keeps it unmapped and captures the actual content subtree.
        visible: !root.fixtureMode && root.opened && !!root.anchorWindow
        color: Color.popups.background
        implicitWidth: root.popupWidth
        implicitHeight: root.popupHeight
        grabFocus: true
        onClosed: root.close()
        anchor {
            id: popupAnchor
            window: root.anchorWindow
            adjustment: PopupAdjustment.Slide
            edges: Edges.Top | Edges.Left
            gravity: Edges.Bottom | Edges.Right
            rect.width: 1
            rect.height: 1
            onAnchoring: {
                if (!root.anchorItem || !root.anchorWindow) return
                var window = root.anchorWindow
                var point = window.contentItem.mapFromItem(root.anchorItem, root.anchorItem.width / 2, 0)
                var position = root.bar ? root.bar.position : "top"
                var x = point.x - root.popupWidth / 2
                var y = window.height + Style.gapsOut
                if (position === "bottom") y = -root.popupHeight - Style.gapsOut
                else if (position === "left" || position === "right") {
                    x = position === "left" ? window.width + Style.gapsOut : -root.popupWidth - Style.gapsOut
                    y = point.y + root.anchorItem.height / 2 - root.popupHeight / 2
                    y = Math.max(Style.gapsOut, Math.min(y, window.height - root.popupHeight - Style.gapsOut))
                } else x = Math.max(Style.gapsOut, Math.min(x, window.width - root.popupWidth - Style.gapsOut))
                popupAnchor.rect.x = Math.round(x)
                popupAnchor.rect.y = Math.round(y)
            }
        }
        Ui.BorderSurface {
            id: popupFrame
            objectName: "chatgptNativeFrame"
            anchors.fill: parent
            color: Color.popups.background
            borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(2)))
            clip: true
        Rectangle {
            id: controls
            objectName: "chatgptPopoverControls"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: popupFrame.contentLeftInset
            anchors.rightMargin: popupFrame.contentRightInset
            anchors.topMargin: popupFrame.contentTopInset
            height: expandButton.implicitHeight + Style.spacing.sm * 2
            color: Color.popups.background
            clip: true
            Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                text: "ChatGPT"
                textFormat: Text.PlainText
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Color.popups.border
            }
            Ui.Button {
                id: expandButton
                objectName: "chatgptExpandButton"
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                text: root.expanded ? qsTr("Compact") : qsTr("Expand")
                tooltipText: root.expanded ? qsTr("Return to compact view") : qsTr("Expand to available screen")
                foreground: Color.popups.text
                focusable: true
                bordered: true
                // Explicit idle outline: the action must not look like loose text.
                borderSpec: _showFocusRing ? _focusBorderSpec : Border.flat(Color.popups.text, 1)
                Accessible.name: tooltipText
                Accessible.role: Accessible.Button
                onClicked: root.toggleExpanded()
            }
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
            sourceComponent: Component {
                Content {
                    browserProfile: root.ownedProfile
                    fixtureMode: root.fixtureMode
                    fixtureHtml: root.fixtureHtml
                    panelBackground: Color.popups.background
                    panelForeground: Color.popups.text
                    panelBorder: Color.popups.border
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
            title: qsTr("ChatGPT sign-in")
            // A layer-shell surface is not an xdg_toplevel parent.
            onClosed: root.releaseAuxiliary(window)
            readonly property alias browser: linked
            Browser {
                id: linked
                anchors.fill: parent
                profile: root.ownedProfile
                fixtureMode: root.fixtureMode
                backgroundColor: Color.popups.background
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
        sourceComponent: Component {
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
