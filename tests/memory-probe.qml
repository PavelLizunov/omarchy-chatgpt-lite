import QtQuick
import QtWebEngine
import "../native" as Candidate

Item {
    id: root
    property bool coreWorks: false
    property bool optionalWorks: false
    readonly property string loadState: browser.loadState
    readonly property int loadErrorCode: browser.loadErrorCode
    function verifyFixture() {
        browser.runJavaScript("document.getElementById('action').click(); ({core:window.coreReady===true && window.actions===1 && document.getElementById('draft').value==='Inert draft',optional:window.optionalReady===true})", function(value) {
            if (!value) return
            coreWorks = value.core
            optionalWorks = value.optional
        })
    }
    Candidate.Browser {
        id: browser
        anchors.fill: parent
        profile: probeProfile
        // Local fixture, supplied by the reviewed loopback-only probe server.
        fixtureMode: true
        onNavigationRequested: function(request) {
            if (String(request.url) === String(probeUrl)) request.action = WebEngineNavigationRequest.AcceptRequest
            else request.reject()
        }
        Component.onCompleted: url = probeUrl
    }
}
