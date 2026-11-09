import QtQuick
import QtQuick.Effects
import VoltaApp 1.0

// Screen shown by Phone and Messages when no smartphone is
// connected over Bluetooth: an invitation to connect one, with a button that leads
// direttamente a Impostazioni › Bluetooth.
Rectangle {
    id: ov
    anchors.fill: parent
    z: 500
    color: lightTheme ? "#FFFFFF" : "#171717"

    property bool lightTheme: false
    property string appIcon: ""
    property string appName: ""
    signal openBluetoothSettings()

    // Blocks touches to the app underneath
    MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: (w) => w.accepted = true }

    Column {
        anchors.centerIn: parent
        spacing: 18
        width: Math.min(460, parent.width - 80)

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "qrc:/VoltaApp/icons/bluetooth.svg"
            width: 72; height: 72
            sourceSize: Qt.size(144, 144)
            fillMode: Image.PreserveAspectFit
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: qsTr("Connect your smartphone via Bluetooth")
            color: ov.lightTheme ? "#171717" : "#FFFFFF"
            font.pixelSize: 24; font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: ov.appName !== ""
                  ? qsTr("To use ") + ov.appName + qsTr(" connect your phone to the car via Bluetooth.")
                  : qsTr("Connect your phone to the car via Bluetooth.")
            color: ov.lightTheme ? "#757575" : "#A2A3A5"
            font.pixelSize: 15
        }
        Item { width: 1; height: 6 }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 260; height: 52; radius: 8
            color: _btnMA.pressed ? "#1E63D0" : "#2C7BF2"
            Behavior on color { ColorAnimation { duration: 100 } }
            Text {
                anchors.centerIn: parent
                text: qsTr("Bluetooth settings")
                color: "#FFFFFF"; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            MouseArea { id: _btnMA; anchors.fill: parent; onClicked: ov.openBluetoothSettings() }
        }
    }
}
