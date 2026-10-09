import QtQuick
import QtQuick.Dialogs
import "../wpe-module"

WpeView {
    id: root
    objectName: "chatgptBrowser"
    property color backgroundColor: "transparent"
    signal loadFailed()
    onChanged: { if (loadState === "FAILED") root.loadFailed() }
    onFilesRequested: function(request) { chooser.pending = request; chooser.fileMode = request.multiple ? FileDialog.OpenFiles : FileDialog.OpenFile; chooser.open() }
    onDownloadRequested: function(request) { save.pending = request; save.open() }
    onPasteRequested: { if (!paste.visible) paste.open() }
    onClipboardPermissionRequested: function(request) { if (paste.visible) {request.resolve(false);return}; paste.pending = request; paste.open() }
    FileDialog {
        id: chooser
        property var pending: null
        title: qsTr("Choose ChatGPT attachments")
        onAccepted: { if (pending) { pending.selectFiles(selectedFiles); pending.dispose() }; pending = null }
        onRejected: { if (pending) pending.dispose(); pending = null }
    }
    FileDialog {
        id: save
        property var pending: null
        title: qsTr("Save ChatGPT download")
        fileMode: FileDialog.SaveFile
        onAccepted: { if (pending) pending.acceptPath(selectedFile); pending = null }
        onRejected: { if (pending) pending.cancel(); pending = null }
    }
    MessageDialog {
        id: paste
        property var pending: null
        title: qsTr("Clipboard access")
        text: qsTr("Allow ChatGPT to read your clipboard? Only allow this when you are pasting content you intend to share.")
        buttons: MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function(button) { if (pending) {pending.resolve(button === MessageDialog.Yes);pending = null} else if (button === MessageDialog.Yes) root.pasteConfirmed() }
        onRejected: { if (pending) pending.resolve(false); pending = null }
    }
    Component.onDestruction: {
        if (paste.pending) paste.pending.resolve(false)
        if (chooser.pending) chooser.pending.cancel()
        if (save.pending) save.pending.cancel()
    }
}
