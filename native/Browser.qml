import QtQuick
import QtWebEngine
import QtQuick.Dialogs

// Original-site view. No injected scripts or website appearance overrides.
WebEngineView {
    id: root
    property bool fixtureMode: false
    property string loadState: "IDLE"
    property int loadErrorCode: 0
    signal auxiliaryRequested(var request)
    signal dismissRequested()
    signal loadFailed()

    objectName: "chatgptBrowser"
    lifecycleState: WebEngineView.LifecycleState.Active
    settings.localContentCanAccessRemoteUrls: false
    settings.localContentCanAccessFileUrls: false
    settings.allowRunningInsecureContent: false
    settings.javascriptCanOpenWindows: true
    settings.javascriptCanAccessClipboard: true
    settings.javascriptCanPaste: true
    settings.fullScreenSupportEnabled: false
    settings.unknownUrlSchemePolicy: WebEngineSettings.DisallowUnknownUrlSchemes
    settings.playbackRequiresUserGesture: true
    // The shell uses its own fixed icon; site favicons/touch icons are unused.
    settings.autoLoadIconsForPage: false
    settings.touchIconsEnabled: false
    // No speculative DNS or hyperlink-auditing traffic is needed by this view.
    settings.dnsPrefetchEnabled: false
    settings.hyperlinkAuditingEnabled: false

    function safeUrl(value) {
        var uri = String(value)
        if (uri === "about:blank") return true
        if (fixtureMode) return false
        // Reject embedded credentials, insecure schemes and ambiguous authorities.
        return /^https:\/\/[^\s\/@\\?#]+(?::[0-9]+)?(?:[\/?#]|$)/i.test(uri)
            && uri.slice(8).split(/[\/?#]/)[0].indexOf("@") === -1
    }

    onNavigationRequested: function(request) {
        // loadHtml's internal data: load is admitted only in inert fixtures.
        if (fixtureMode && (String(request.url).indexOf("data:text/html") === 0
                || String(request.url) === "")) return
        if (!safeUrl(request.url)) request.reject()
    }
    onNewWindowRequested: function(request) { root.auxiliaryRequested(request) }
    onWindowCloseRequested: root.dismissRequested()
    // Suppress Chromium browser chrome (Back/Forward/Reload). Site-owned menus
    // and the original composer/copy controls are not intercepted.
    onContextMenuRequested: function(request) { request.accepted = true }
    function requestPermission(request) {
        // Never grant background clipboard reads silently. Only the original
        // site may ask through an explicit native confirmation; all else denied.
        if (request.permissionType === WebEngineView.ClipboardReadWrite
                && /^https:\/\/chatgpt\.com\/?$/.test(String(request.origin))
                && !fixtureMode && !clipboardPrompt.pending) {
            clipboardPrompt.pending = request
            clipboardPrompt.open()
        } else request.deny()
    }
    onPermissionRequested: function(request) { requestPermission(request) }
    MessageDialog {
        id: clipboardPrompt
        property var pending: null
        title: qsTr("Clipboard access")
        text: qsTr("Allow ChatGPT to read your clipboard? Only allow this when you are pasting content you intend to share.")
        buttons: MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function(button, role) {
            if (pending) {
                if (button === MessageDialog.Yes) pending.grant()
                else pending.deny()
            }
            pending = null
        }
        onRejected: { if (pending) pending.deny(); pending = null }
    }
    Component.onDestruction: {
        if (clipboardPrompt.pending) clipboardPrompt.pending.deny()
    }
    onCertificateError: function(error) { error.rejectCertificate() }
    onFullScreenRequested: function(request) { request.reject() }
    onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceID) {
        // Deliberately discard site console messages and sensitive source URLs.
    }
    onLoadingChanged: function(info) {
        if (info.status === WebEngineView.LoadStartedStatus) {
            root.loadState = "LOADING"
            root.loadErrorCode = 0
        }
        else if (info.status === WebEngineView.LoadSucceededStatus) root.loadState = "SUCCEEDED"
        else if (info.status === WebEngineView.LoadStoppedStatus) root.loadState = "STOPPED"
        else if (info.status === WebEngineView.LoadFailedStatus) {
            root.loadState = "FAILED"
            root.loadErrorCode = info.errorCode
            root.loadFailed()
        }
    }
    Keys.priority: Keys.AfterItem
    Keys.onEscapePressed: function(event) {
        // Original-site Escape handling must be verified before adding auto-hide.
        // Explicit native toggle/hide remains available regardless of site overlays.
        event.accepted = false
    }
}
