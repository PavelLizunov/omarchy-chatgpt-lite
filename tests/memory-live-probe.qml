import QtQuick
import QtWebEngine
import "../native" as Candidate

// Anonymous original-site load only. No production profile, DOM reads or input.
Item {
    readonly property string loadState: browser.loadState
    readonly property int loadErrorCode: browser.loadErrorCode
    property bool coreWorks: false // Full site interaction deliberately not claimed.
    property bool optionalWorks: false
    function verifyFixture() {}
    Candidate.Browser {
        id: browser
        anchors.fill: parent
        profile: probeProfile
        Component.onCompleted: url = "https://chatgpt.com/"
    }
}
