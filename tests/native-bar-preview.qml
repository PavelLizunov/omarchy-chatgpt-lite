pragma ComponentBehavior: Bound
import QtQuick
import QtWebEngine
import QtTest
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
        suppliedProfile: prototype.instance()
        profileReady: true
        fixtureMode: true
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
                var compactWidth = service.popupWidth
                var compactHeight = service.popupHeight
                var button = root.visualObject(service.visualContent, "chatgptExpandButton")
                if (!button || button.text !== "Expand") return
                pointer.mouseClick(button)
                if (!service.expanded || button.text !== "Compact"
                        || service.popupWidth !== service.availableWidth
                        || service.popupHeight !== service.availableHeight) return
                pointer.mouseClick(button)
                if (service.expanded || button.text !== "Expand"
                        || service.popupWidth !== compactWidth || service.popupHeight !== compactHeight) return
                button.forceActiveFocus()
                pointer.keyClick(Qt.Key_Space)
                if (!service.expanded || button.text !== "Compact") return
                button.forceActiveFocus()
                pointer.keyClick(Qt.Key_Return)
                if (service.expanded || button.text !== "Expand") return
                root.buttonClickPassed = true
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
                        root.palettePassed = color === (root.previewPalette === "light"
                            ? "rgb(255, 251, 234)" : "rgb(16, 19, 21)")
                    })
                })
            }
            if (settled > 30 && root.checkPassed && root.palettePassed && root.buttonClickPassed && root.auxiliaryCheckPassed) {
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
        widget.trigger.triggerPress(Qt.LeftButton)
    }
}
