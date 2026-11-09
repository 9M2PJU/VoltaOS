import QtQuick
import VoltaApp 1.0

// Base page for apps not yet implemented (Camera, Bluetooth): header with icon + name like the other apps and an
// empty state in the center. Each app has its own file (CameraApp.qml, ...) that
// uses this page: to develop it just replace its content.
Rectangle {
    id: page
    color: lightTheme ? "#FFFFFF" : "#171717"
    clip: true

    property bool lightTheme: false
    property bool active: false
    property string title: ""
    property string iconSource: ""
    property string message: qsTr("Coming up")
    property string hint: ""
    property bool showHeaderIcon: true

    // Custom content (replaces the empty state if present)
    default property alias content: contentArea.data

    // ── Header: same style as Theater/Arcade ──
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 20
        height: 26
        z: 50

        Image {
            id: headerIcon
            visible: page.showHeaderIcon
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            source: page.iconSource
            sourceSize: Qt.size(26, 26)
        }
        Text {
            anchors.left: page.showHeaderIcon ? headerIcon.right : parent.left
            anchors.leftMargin: page.showHeaderIcon ? 12 : 20
            anchors.verticalCenter: parent.verticalCenter
            text: page.title
            color: page.lightTheme ? "#171717" : "#FFFFFF"
            font.pixelSize: 18; font.weight: Font.DemiBold
        }
    }

    Item {
        id: contentArea
        anchors.top: header.bottom
        anchors.topMargin: 20
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }

    // ── Stato vuoto ──
    Column {
        anchors.centerIn: parent
        spacing: 18
        visible: contentArea.children.length === 0

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: page.iconSource
            sourceSize: Qt.size(88, 88)
            opacity: 0.9
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.title
            color: page.lightTheme ? "#171717" : "#FFFFFF"
            font.pixelSize: 24; font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.message
            color: page.lightTheme ? "#757575" : "#A2A3A5"
            font.pixelSize: 15
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: page.hint !== ""
            width: Math.min(420, page.width - 80)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: page.hint
            color: page.lightTheme ? "#9A9A9A" : "#6E6F71"
            font.pixelSize: 13
        }
    }
}
