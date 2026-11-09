import QtQuick
import VoltaApp 1.0

// CAMERA — one main view (rear) and two side views below, as on electric cars.
// Tiles only, edge to edge, no header or margins. For now they are
// placeholders: later each tile gets connected to the camera stream
// (just put the image/video inside the relevant CamTile).
Rectangle {
    id: cam
    color: lightTheme ? "#FFFFFF" : "#171717"
    clip: true

    property bool lightTheme: false
    property bool active: false
    readonly property real gap: 4

    component CamTile: Rectangle {
        id: tile
        property string label: ""
        radius: 0
        color: cam.lightTheme ? "#E2E2E2" : "#0E0E0E"
        clip: true
        default property alias content: tileContent.data

        Item { id: tileContent; anchors.fill: parent }

        Column {
            anchors.centerIn: parent
            spacing: 8
            visible: tileContent.children.length === 0
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "qrc:/VoltaApp/icons/camera.svg"
                sourceSize: Qt.size(40, 40)
                width: 40; height: 40
                opacity: 0.35
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.label
                color: cam.lightTheme ? "#757575" : "#8A8B8D"
                font.pixelSize: 14; font.weight: Font.Medium
            }
        }
    }

    CamTile {
        id: mainCam
        label: qsTr("Rear")
        anchors.top: parent.top
        anchors.left: parent.left; anchors.right: parent.right
        height: Math.round((parent.height - cam.gap) * 0.64)
    }
    Row {
        anchors.top: mainCam.bottom; anchors.topMargin: cam.gap
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: cam.gap
        CamTile { label: qsTr("Left"); width: (parent.width - cam.gap) / 2; height: parent.height }
        CamTile { label: qsTr("Right");   width: (parent.width - cam.gap) / 2; height: parent.height }
    }
}
