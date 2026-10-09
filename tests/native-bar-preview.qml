pragma ComponentBehavior: Bound
import QtQuick
import QtWebEngine
import QtTest
import Quickshell.Wayland
import qs.Commons
import "../native" as Candidate

// Actual bar trigger and service/popup content; no mapped popup, disk or network.
Rectangle {
    id: root
    color: previewPalette === "light" ? "#fffbea" : "#101315"
    property bool previewReady: false
    property bool checkPassed: false
    property string previewState: "ready"
    property string previewPalette: "dark"
    property bool previewExpanded: false
    property int previewVariant: 0
    property int previewPaletteChoice: 0
    property bool telemetryPassed: false
    property bool palettePassed: false
    property bool buttonClickPassed: false
    property bool auxiliaryCheckPassed: false
    // QtTest delivers actual offscreen mouse events to the native button.
    TestCase { id: pointer; when: false; optional: true }
    function visualObject(item, name) {
        if (item.objectName === name) return item
        for (var i = 0; i < item.children.length; i++) {
            var result = visualObject(item.children[i], name)
            if (result) return result
        }
        return null
    }
    property var retainedBrowser: null
    property var retainedProfile: null
    property var inertProfile: null
    property bool dictationCheckPassed: false
    TextInput { id: otherFocus; visible: false }
    QtObject {
        id: inertBar
        property bool vertical: false
        property bool foregroundAnimationEnabled: false
        property int barSize: 32
        property string position: "top"
        property string fontFamily: Style.font.family
        property color barForeground: root.previewPalette === "light" ? "#161616" : "#cacccc"
        property color urgent: Color.urgent
        property var activePopout: null
        function requestPopout(owner) { activePopout = owner }
        function releasePopout(owner) { if (activePopout === owner) activePopout = null }
        function registerClickTarget(target) {}
        function unregisterClickTarget(target) {}
        function showTooltip(target, text) {}
        function hideTooltip(target) {}
    }
    WebEngineProfilePrototype { id: prototype; httpCacheType: WebEngineProfile.MemoryHttpCache }
    Candidate.Service {
        id: service
        suppliedProfile: root.inertProfile
        profileReady: true
        fixtureMode: true
        captureEnabled: false
        designVariant: root.previewVariant
        paletteChoice: root.previewPaletteChoice
        fixtureHtml: "<!doctype html><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; style-src 'unsafe-inline'\"><style>body{font:16px sans-serif;margin:20px;background:#101315;color:#cacccc}input{box-sizing:border-box;width:100%;padding:10px}pre{white-space:pre-wrap}</style><h2>Inert ChatGPT fixture</h2><p>Original browser component. No account or network.</p><pre>const answer = 42;</pre><style>.bg-token-bg-elevated-secondary,.composer-shell{background:#fff;padding:12px}</style><div class='bg-token-bg-elevated-secondary'>Inert elevated surface</div><div class='composer-shell' data-composer-surface='true'><label>Draft<input value='Retained inert draft'></label></div>"
    }
    Candidate.BarWidget {
        id: widget
        suppliedService: service
        bar: inertBar
        x: root.width - width - 24
        width: implicitWidth
        height: implicitHeight
    }
    Item {
        id: card
        objectName: "chatgptPopoverFrame"
        x: Math.max(8, Math.min(widget.x + widget.width / 2 - width / 2, root.width - width - 8))
        y: inertBar.barSize + Style.gapsOut
        width: service.popupWidth
        height: service.popupHeight
    }
    Timer {
        interval: 20
        repeat: true
        running: !root.previewReady
        property int settled: 0
        onTriggered: {
            if (!service.primaryBrowser || service.primaryBrowser.loadState !== "SUCCEEDED") return
            if (service.visualContent.parent !== card) {
                service.visualContent.parent = card
                service.visualContent.width = Qt.binding(function() { return service.popupWidth })
                service.visualContent.height = Qt.binding(function() { return service.popupHeight })
            }
            if (++settled === 15) {
                root.retainedBrowser = service.primaryBrowser
                root.retainedProfile = service.ownedProfile
                var barSvg = root.visualObject(widget.trigger, "chatgptBarSvg")
                if (!widget.trigger.hasVisualContent || !widget.trigger.visible
                        || widget.trigger.opacity < 0.99 || !barSvg || barSvg.status !== Image.Ready
                        || barSvg.width <= 0 || barSvg.height <= 0) return
                var header = root.visualObject(service.visualContent, "chatgptPopoverControls")
                if (header.height !== (service.designVariant === 1 ? 92 : 72)) return
                for (var child = 0; child < header.children.length; child++)
                    if (header.children[child].text !== undefined && String(header.children[child].text).startsWith("Shared shell:")) return
                if (service.primaryBrowser.userScripts.collection.length !== 0) return
                for (var h = 0; h < header.resources.length; h++)
                    if (header.resources[h].text !== undefined && String(header.resources[h].text).startsWith("RAM is resident")) return
                var variantButton = root.visualObject(service.visualContent, "chatgptVariantButton")
                var paletteButton = root.visualObject(service.visualContent, "chatgptPaletteButton")
                if (!variantButton || !paletteButton) return
                for (var cycle = 0; cycle < 3; cycle++) pointer.mouseClick(variantButton)
                if (service.designVariant !== root.previewVariant) return
                for (var tone = 0; tone < 4; tone++) pointer.mouseClick(paletteButton)
                if (service.paletteChoice !== root.previewPaletteChoice) return
                var compactWidth = service.popupWidth
                var compactHeight = service.popupHeight
                var button = root.visualObject(service.visualContent, "chatgptExpandButton")
                if (!button || button.actionName !== "Expand") return
                pointer.mouseClick(button)
                if (!service.expanded || button.actionName !== "Compact"
                        || service.popupWidth !== service.availableWidth
                        || service.popupHeight !== service.availableHeight) return
                pointer.mouseClick(button)
                if (service.expanded || button.actionName !== "Expand"
                        || service.popupWidth !== compactWidth || service.popupHeight !== compactHeight) return
                button.forceActiveFocus()
                pointer.keyClick(Qt.Key_Space)
                if (!service.expanded || button.actionName !== "Compact") return
                button.forceActiveFocus()
                pointer.keyClick(Qt.Key_Return)
                if (service.expanded || button.actionName !== "Expand") return
                root.buttonClickPassed = true
                var closeButton = root.visualObject(service.visualContent, "chatgptCloseButton")
                if (!closeButton || service.popup.WlrLayershell.keyboardFocus !== WlrKeyboardFocus.OnDemand) return
                service.primaryBrowser.forceActiveFocus()
                pointer.keyClick(Qt.Key_Insert)
                otherFocus.forceActiveFocus()
                service.primaryBrowser.forceActiveFocus()
                pointer.keyClick(Qt.Key_Insert, Qt.ShiftModifier)
                if (!service.opened || service.primaryBrowser !== root.retainedBrowser) return
                pointer.mouseClick(closeButton)
                if (service.opened || service.popup.WlrLayershell.keyboardFocus !== WlrKeyboardFocus.None) return
                service.open({})
                closeButton.forceActiveFocus()
                pointer.keyClick(Qt.Key_Return)
                if (service.opened) return
                service.open({})
                closeButton.forceActiveFocus()
                pointer.keyClick(Qt.Key_Space)
                if (service.opened) return
                service.open({})
                root.dictationCheckPassed = service.primaryBrowser === root.retainedBrowser
                if (root.previewExpanded) pointer.mouseClick(button)
                // Actual owned FloatingWindow/Browser, with inert request handoff.
                service.createAuxiliary({requestedUrl: "about:blank", openIn: function(view) {
                    view.loadHtml("<!doctype html><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'\"><p>Inert linked window</p>")
                }})
                if (service.auxiliaries.length !== 1) return
                var linked = service.auxiliaries[0]
                widget.trigger.triggerPress(Qt.LeftButton)
                if (service.opened || !linked.visible) return
                // An independent linked window can hand off another window while
                // the main popover is hidden. Shared profile and admission stay bounded.
                linked.browser.auxiliaryRequested({requestedUrl: "about:blank", openIn: function(view) {
                    view.loadHtml("<!doctype html><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'\"><p>Inert nested window</p>")
                }})
                if (service.auxiliaries.length !== 2
                        || service.auxiliaries[1].browser.profile !== service.ownedProfile) return
                service.auxiliaries[1].browser.dismissRequested()
                if (service.auxiliaries.length !== 1) return
                var unsafeHandoff = false
                service.createAuxiliary({requestedUrl: "file:///etc/passwd", openIn: function() { unsafeHandoff = true }}, linked.browser)
                if (unsafeHandoff || service.auxiliaries.length !== 1) return
                for (var n = 0; n < 3; n++) service.createAuxiliary({requestedUrl: "about:blank", openIn: function(view) {}}, linked.browser)
                if (service.auxiliaries.length !== 3) return
                while (service.auxiliaries.length > 1) service.releaseAuxiliary(service.auxiliaries[service.auxiliaries.length - 1])
                widget.trigger.triggerPress(Qt.LeftButton)
                if (!linked.visible) return
                // Reopening the popover must not revive a separately hidden child.
                linked.visible = false
                service.close()
                service.open({})
                if (linked.visible) return
                service.createAuxiliary({requestedUrl: "about:blank", openIn: function() { unsafeHandoff = true }}, linked.browser)
                if (unsafeHandoff || service.auxiliaries.length !== 1) return
                service.close()
                service.createAuxiliary({requestedUrl: "about:blank", openIn: function() { unsafeHandoff = true }}, service.primaryBrowser)
                if (unsafeHandoff || service.auxiliaries.length !== 1) return
                service.open({})
                root.auxiliaryCheckPassed = true
                service.releaseAuxiliary(linked)
                service.primaryBrowser.runJavaScript("document.querySelector('input').value", function(value) {
                    root.checkPassed = service.opened && widget.opened
                        && service.liveViews === 1 && service.primaryBrowser === root.retainedBrowser
                        && service.ownedProfile === root.retainedProfile && value === "Retained inert draft"
                        && inertBar.activePopout === service
                    service.primaryBrowser.runJavaScript("getComputedStyle(document.body).backgroundColor", function(color) {
                        // Native palette changes must not recolor the website.
                        root.palettePassed = color === "rgb(16, 19, 21)"
                    })
                })
            }
            if (settled > 15 && !root.checkPassed && root.auxiliaryCheckPassed) {
                // Deferred auxiliary destruction must settle before checking exact live views.
                service.primaryBrowser.runJavaScript("document.querySelector('input').value", function(value) {
                    root.checkPassed = service.opened && widget.opened && service.liveViews === 1
                        && service.primaryBrowser === root.retainedBrowser
                        && service.ownedProfile === root.retainedProfile && value === "Retained inert draft"
                        && inertBar.activePopout === service
                })
            }
            if (settled === 80) console.log("FIXTURE_STATE " + JSON.stringify({checks:root.checkPassed, palette:root.palettePassed,
                buttons:root.buttonClickPassed, auxiliary:root.auxiliaryCheckPassed, dictation:root.dictationCheckPassed,
                pages:service.resourcePages, pids:service.rendererPids}))
            root.telemetryPassed = service.resourcePages.state === "ready"
                && typeof service.resourcePages.cpuPercent === "number"
                && service.resourcePages.rssMiB > 0 && service.resourceShell.state === "ready"
            if (settled > 30 && root.telemetryPassed && root.checkPassed && root.palettePassed && root.buttonClickPassed && root.auxiliaryCheckPassed && root.dictationCheckPassed) {
                if (root.previewState === "error") service.primaryBrowser.loadState = "FAILED"
                else if (root.previewState === "loading") service.primaryBrowser.loadState = "LOADING"
                else if (root.previewState === "recovered") {
                    service.primaryBrowser.loadState = "FAILED"
                    service.primaryBrowser.loadState = "LOADING"
                    service.primaryBrowser.loadState = "SUCCEEDED"
                }
                root.previewReady = true
            }
        }
    }
    Component.onCompleted: {
        // Only the isolated render process changes palette; the desktop is untouched.
        Color.background = previewPalette === "light" ? "#fffbea" : "#101315"
        Color.foreground = previewPalette === "light" ? "#161616" : "#cacccc"
        Color.popups.background = Color.background
        Color.popups.text = Color.foreground
        Color.popups.border = Color.foreground
        root.inertProfile = prototype.instance()
        if (!root.inertProfile || !root.inertProfile.offTheRecord) return
        widget.trigger.triggerPress(Qt.LeftButton)
    }
}
