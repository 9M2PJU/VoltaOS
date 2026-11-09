import QtQuick

// Dropdown menu for the interface language (flag + name). Used by the
// guided setup and by the Settings. Changes the language immediately (Lang).
Item {
    id: pick
    property color ctrlBg: "#2E2E2E"
    property color selBg: "#3A3A3A"
    property color txt: "#FFFFFF"
    property color txtSub: "#A2A3A5"
    property color divider: "#333333"
    property int corner: 8
    property bool open: false
    width: 300; height: 60
    z: 50

    readonly property var langs: [ { c: "en", n: "English" }, { c: "es", n: "Español" }, { c: "fr", n: "Français" },
                                   { c: "pt", n: "Português" }, { c: "it", n: "Italiano" } ]
    function nameOf(c) { for (var i = 0; i < langs.length; i++) if (langs[i].c === c) return langs[i].n; return "" }

    Rectangle {
        anchors.fill: parent; radius: pick.corner
        color: pick.ctrlBg
        border.width: pick.open ? 2 : 0; border.color: pick.txtSub
        FlagIcon { code: Lang.code; anchors.verticalCenter: parent.verticalCenter; x: 18 }
        Text {
            x: 68; anchors.verticalCenter: parent.verticalCenter
            text: pick.nameOf(Lang.code)
            color: pick.txt; font.pixelSize: 21; font.weight: Font.Medium
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter
            text: pick.open ? "▴" : "▾"; color: pick.txtSub; font.pixelSize: 20
        }
        MouseArea { anchors.fill: parent; onClicked: pick.open = !pick.open }
    }
    Rectangle {
        visible: pick.open
        y: pick.height + 6; width: pick.width; height: pick.langs.length * 56 + 8
        radius: pick.corner; color: pick.selBg
        border.width: 1; border.color: pick.divider
        Column {
            x: 0; y: 4; width: parent.width
            Repeater {
                model: pick.langs
                Item {
                    width: parent.width; height: 56
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 4; radius: Math.max(2, pick.corner - 3)
                        color: Lang.code === modelData.c ? pick.ctrlBg : "transparent"
                    }
                    FlagIcon { code: modelData.c; anchors.verticalCenter: parent.verticalCenter; x: 18 }
                    Text {
                        x: 68; anchors.verticalCenter: parent.verticalCenter
                        text: modelData.n; color: pick.txt; font.pixelSize: 21
                        font.weight: Lang.code === modelData.c ? Font.DemiBold : Font.Normal
                    }
                    MouseArea { anchors.fill: parent; onClicked: { Lang.setLanguage(modelData.c); pick.open = false } }
                }
            }
        }
    }
}
