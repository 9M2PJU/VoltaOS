import QtQuick

// Vertical speed bar (next to the number in the CarPanel).
Item {
    id: bar
    property real fillPct: 0    // 0..100
    width: 4
    Rectangle {
        anchors.fill: parent; radius: 2
        color: "#3A3A3A"
    }
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * Math.max(0, Math.min(100, bar.fillPct)) / 100
        radius: 2
        color: "#3D6FE7"
        Behavior on height { NumberAnimation { duration: 200 } }
    }
}
