import QtQuick
import Slovn.ChatGPTCapture 1.0

// Opt-in, fixed primary browser only. No navigation, visibility or page scripts.
BrowserCapture {
    ownerSource: Qt.resolvedUrl("Capture.qml")
    enabled: true
}
