import QtQuick
import QtTest
import "../build/wpe"
Item {
    width: 460; height: 560
    WpeView {
        id: browser
        fixtureMode: true
        presented: true
        anchors.fill: parent
        fixtureHtml: `<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'"><body style="margin:24px"><input value="Inert draft"><button onclick="window.actions=(window.actions||0)+1">Inert action</button></body>`
    }
    TestCase {
        name: "WpeNativeInput"
        when: browser.frameReady && browser.loadState === "SUCCEEDED"
        function test_mouse_keyboard_action_retention() {
            mouseClick(browser,65,35)
            wait(100)
            keyClick(Qt.Key_End)
            browser.fixturePaste()
            wait(100)
            keyClick(Qt.Key_A, Qt.ControlModifier)
            keyClick(Qt.Key_C, Qt.ControlModifier)
            tryVerify(function(){return browser.fixtureCopyVerified()},3000)
            mouseClick(browser,265,35)
            browser.visible = false
            browser.visible = true
            wait(100)
            browser.verifyFixture()
            tryCompare(browser,"fixtureVerified",true,3000)
        }
    }
}
