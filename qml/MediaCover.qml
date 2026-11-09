import QtQuick
import Qt5Compat.GraphicalEffects
import VoltaApp 1.0

// Cover with rounded corners (or circle) and placeholder, used by the
// shared queue/search panels (MediaQueuePanel, MediaSearchPanel,
// BluetoothApp). If there is no image it shows a placeholder icon.
Item {
    id: cov
    property string source: ""
    property real radius: 3
    property bool circle: false
    property string placeholderIcon: ""     // e.g. Bluetooth icon

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: cov.circle ? width / 2 : cov.radius
        color: cov.noteHolder ? (Theme.light ? "#F0F0F0" : "#262626") : Theme.surfaceElevated
    }

    // Separate OPAQUE mask: before, the mask was the background itself, which in
    // dark theme is semi-transparent gray (#24FFFFFF) → the image was
    // drawn at 14% opacity and looked washed out/whitish.
    Rectangle {
        id: maskRect
        anchors.fill: parent
        radius: cov.circle ? width / 2 : cov.radius
        color: "white"
        visible: false
        layer.enabled: true
    }

    Image {
        id: img
        anchors.fill: parent
        source: cov.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true; mipmap: true
        visible: false
    }
    OpacityMask {
        anchors.fill: parent
        source: img
        maskSource: maskRect
        visible: img.status === Image.Ready
    }

    // Music (local files): same placeholder as the music widget (gray tile with the note)
    readonly property bool noteHolder: cov.placeholderIcon.indexOf("localmusic") >= 0
    Text {
        anchors.centerIn: parent; text: "🎵"; font.pixelSize: cov.width * 0.34
        visible: img.status !== Image.Ready && cov.noteHolder
    }
    Image {
        anchors.centerIn: parent
        visible: img.status !== Image.Ready && cov.placeholderIcon !== "" && !cov.noteHolder
        source: cov.placeholderIcon
        width: parent.width * 0.42; height: width
        sourceSize: Qt.size(width * 2, height * 2)
        fillMode: Image.PreserveAspectFit
        opacity: 0.85
    }
}
