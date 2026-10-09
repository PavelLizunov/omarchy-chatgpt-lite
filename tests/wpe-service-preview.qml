pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import qs.Commons
import "../native" as Candidate
import "../native/wpe-module" as Wpe

Rectangle {
    id: root
    width: 620; height: 640
    color: "#101315"
    property bool previewReady: false
    property bool checkPassed: false
    property bool useSuppliedProfile: true
    property var retained: null
    property var retainedProfile: null
    property int steps: 0
    TestCase { id: pointer; when: false; optional: true }
    Wpe.WpeSession { id: session; ephemeral: true }
    Candidate.Service {
        id: service
        useWpe: true
        fixtureMode: true
        suppliedProfile: root.useSuppliedProfile ? session : null
        profileReady: true
        captureEnabled: false
        fixtureHtml: `<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'"><body style="margin:24px;background:#fff;color:#161616"><input value="Inert draft"><button onclick="window.actions=(window.actions||0)+1">Inert action</button><p>Original embedded WPE component. Inert test, no account.</p></body>`
    }
    Item { id: card; objectName: "fixtureCard"; x: 80; y: 20; width: service.popupWidth; height: service.popupHeight }
    function find(item,name) { if(item.objectName===name)return item;for(var i=0;i<item.children.length;i++){var found=find(item.children[i],name);if(found)return found}return null }
    Timer {
        interval: 100; repeat: true; running: !root.previewReady
        onTriggered: {
            var browser=service.primaryBrowser
            if(!browser||!browser.frameReady||browser.loadState!=="SUCCEEDED"||browser.renderProcessPid<=0)return
            if(service.visualContent.parent!==card){service.visualContent.parent=card;service.visualContent.width=Qt.binding(function(){return card.width});service.visualContent.height=Qt.binding(function(){return card.height})}
            if(root.steps++===0){
                root.retained=browser
                root.retainedProfile=service.ownedProfile
                pointer.mouseClick(browser,65,35)
                return
            }
            if(root.steps===2){pointer.keyClick(Qt.Key_End);pointer.keyClick(Qt.Key_A);pointer.keyClick(Qt.Key_B);pointer.keyClick(Qt.Key_C);return}
            if(root.steps===3){pointer.mouseClick(browser,265,35);return}
            if(root.steps===4){
                service.close();service.open({});service.toggleExpanded();service.toggleExpanded()
                if(browser!==root.retained||service.popupWidth!==460||service.popupHeight!==560)return
                var handed=false
                service.createAuxiliary({requestedUrl:"about:blank",openIn:function(view){handed=view.profile===root.retainedProfile&&view.relatedView===browser}})
                if(!handed||service.auxiliaries.length!==1)return
                service.close()
                if(!service.auxiliaries[0].visible)return
                var linked=service.auxiliaries[0]
                service.releaseAuxiliary(linked);service.open({})
                browser.verifyFixture()
                return
            }
            if(root.steps>4&&browser.fixtureVerified&&service.liveViews===1&&service.resourcePages.state==="ready"){
                root.checkPassed=browser===root.retained&&service.ownedProfile===root.retainedProfile&&service.opened&&find(service.visualContent,"chatgptPopoverControls").height===72
                console.log("WPE_SERVICE_CHECK "+JSON.stringify({passed:root.checkPassed,pid:browser.renderProcessPid,rssMiB:service.resourcePages.rssMiB,views:service.liveViews}))
                root.previewReady=root.checkPassed
            }
        }
    }
    Component.onCompleted: {Color.popups.background="#101315";Color.popups.text="#cacccc";Color.popups.border="#cacccc";service.open({})}
    Component.onDestruction: service.shutdown()
}
