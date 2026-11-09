import QtQuick
import Qt5Compat.GraphicalEffects
import VoltaApp 1.0

// Arcade-style banner for the Toybox features: big image,
// title, description and, as chosen, a blue button or a switch.
// Immagine: <coverBase>/<key>_hero.png, altrimenti <key>.png, altrimenti
// a gradient background with the "accent" color.
Item {
    id: bn

    property bool lightTheme: false
    property string coverBase: appUrl + "/assets/toybox/"
    property string key: ""
    property string coverFile: ""      // explicit image file (e.g. "cover.jpeg") inside coverBase
    property string title: ""
    property string description: ""
    property color accent: "#333333"

    // Blue button (if buttonText is not empty)
    property string buttonText: ""
    signal buttonClicked()

    // Switch (if toggleText is not empty)
    property string toggleText: ""
    property bool toggleChecked: false
    signal toggled(bool on)

    // Checkboxes under the switch: [{ text: "...", checked: true/false }]
    property var checkOptions: []
    signal optionToggled(int index, bool on)

    Rectangle {
        id: bgRect
        anchors.fill: parent
        radius: 8
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.darker(bn.accent, 1.6) }
            GradientStop { position: 1.0; color: bn.lightTheme ? "#DADADA" : "#101010" }
        }
    }

    Image {
        id: heroImg
        anchors.fill: parent
        // the big photo <key>_hero.png is optional: if missing <key>.png is used
        readonly property string heroUrl: bn.key !== "" ? bn.coverBase + bn.key + "_hero.png" : ""
        source: bn.coverFile !== "" ? bn.coverBase + bn.coverFile
              : (heroUrl !== "" && Files.exists(heroUrl) ? heroUrl : "")
        fillMode: Image.PreserveAspectCrop
        visible: false; smooth: true
    }
    Image {
        id: heroFallback
        anchors.fill: parent
        source: (heroImg.source.toString() === "" || heroImg.status === Image.Error) && bn.key !== "" ? bn.coverBase + bn.key + ".png" : ""
        fillMode: Image.PreserveAspectCrop
        visible: false; smooth: true
    }
    Rectangle { id: maskRect; anchors.fill: parent; radius: 8; visible: false; layer.enabled: true }
    OpacityMask {
        anchors.fill: parent
        source: heroImg.status === Image.Ready ? heroImg : heroFallback
        maskSource: maskRect
        visible: heroImg.status === Image.Ready || heroFallback.status === Image.Ready
    }

    // Dark veil on the left to read the text
    Rectangle {
        anchors.fill: parent; radius: 8
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;  color: "#E6000000" }
            GradientStop { position: 0.45; color: "#80000000" }
            GradientStop { position: 0.75; color: "#00000000" }
        }
    }

    Column {
        anchors.left: parent.left; anchors.leftMargin: 28
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -24
        width: Math.min(400, parent.width * 0.45)
        spacing: 12

        Text { text: bn.title; color: "#FFFFFF"; font.pixelSize: 30; font.weight: Font.DemiBold }
        Text {
            width: parent.width
            text: bn.description
            color: "#E0E0E0"; font.pixelSize: 15
            wrapMode: Text.WordWrap
        }
        Item { width: 1; height: 6 }

        Rectangle {
            visible: bn.buttonText !== ""
            width: 210; height: 52; radius: 8
            color: _btnMA.pressed ? "#1E63D0" : "#2C7BF2"
            Behavior on color { ColorAnimation { duration: 100 } }
            Text { anchors.centerIn: parent; text: bn.buttonText; color: "#FFFFFF"; font.pixelSize: 17; font.weight: Font.DemiBold }
            MouseArea { id: _btnMA; anchors.fill: parent; onClicked: bn.buttonClicked() }
        }

        // Switch (like "Multi-planetary species")
        Item {
            visible: bn.toggleText !== ""
            width: _tgRow.width; height: 40
            Row {
                id: _tgRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14
                Rectangle {
                    width: 52; height: 30; radius: 15
                    anchors.verticalCenter: parent.verticalCenter
                    color: bn.toggleChecked ? "#2C7BF2" : "#4A4A4A"
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Rectangle {
                        width: 24; height: 24; radius: 12
                        y: 3; x: bn.toggleChecked ? parent.width - width - 3 : 3
                        color: "#FFFFFF"
                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: bn.toggleText
                    color: "#FFFFFF"; font.pixelSize: 16; font.weight: Font.DemiBold
                }
            }
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: bn.toggled(!bn.toggleChecked) }
        }

        // Checkboxes
        Repeater {
            model: bn.checkOptions
            Item {
                width: _ckRow.width; height: 34
                Row {
                    id: _ckRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    Rectangle {
                        width: 24; height: 24; radius: 6
                        anchors.verticalCenter: parent.verticalCenter
                        color: modelData.checked ? "#2C7BF2" : "transparent"
                        border.width: modelData.checked ? 0 : 2; border.color: "#9A9A9A"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text { anchors.centerIn: parent; text: "\u2713"; color: "#FFFFFF"; font.pixelSize: 16; font.weight: Font.Bold; visible: modelData.checked }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.text
                        color: "#F0F0F0"; font.pixelSize: 15
                    }
                }
                MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: bn.optionToggled(index, !modelData.checked) }
            }
        }
    }
}
