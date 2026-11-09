import QtQuick
import QtCore as Core
import VoltaApp 1.0

// ─────────────────────────────────────────────────────────────────────────────
//  COLORIZER — window for the body color (it used to be in
//  Settings › Display › Car color).
//   • left: donut hue wheel
//   • right:   saturation (→) / brightness (↑) square
//   • below:    paint type (Pastel / Glossy / Matte)
//   • divider, then "+" (saves the current color), custom colors and
//     colori predefiniti.
//  Every change applies immediately to the 3D car.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: cz
    anchors.fill: parent
    visible: false
    z: 500

    property bool lightTheme: false

    signal colorPicked(string hex)
    signal finishPicked(string finish)

    // Same keys as before (category "ui"): saved colors
    Core.Settings {
        id: prefs
        category: "ui"
        property string carColor:   "#C8C9CA"
        property string carPalette: ""
        property string carFinish:  "lucida"
    }

    readonly property var defaultPalette: ["#FFFFFF", "#E7E7E5", "#8E8E93", "#111112", "#9E1B1B", "#13315C", "#0A84FF", "#5C5E62"]
    readonly property var customPalette: {
        var arr = prefs.carPalette.length ? prefs.carPalette.split(",") : []
        return arr.slice(Math.max(0, arr.length - 6))
    }
    readonly property var finishes: [
        { id: "pastello", name: qsTr("Pastel") },
        { id: "lucida",   name: qsTr("Glossy") },
        { id: "opaca",    name: qsTr("Matte") }
    ]

    // Stato HSV corrente
    property real hue: 0.0
    property real sat: 1.0
    property real val: 1.0
    readonly property color current: Qt.hsva(hue, sat, val, 1.0)

    readonly property color txt:     lightTheme ? "#171717" : "#FFFFFF"
    readonly property color txtSub:  lightTheme ? "#5A5A5A" : "#A2A3A5"
    readonly property color panelBg: lightTheme ? "#FFFFFF" : "#262626"
    readonly property color divider: lightTheme ? "#E0E0E0" : "#3A3A3A"
    readonly property color ctrlBg:  lightTheme ? "#F0F0F0" : "#1E1E1E"
    readonly property color ctrlSel: lightTheme ? "#FFFFFF" : "#4A4A4A"
    readonly property color blue:    "#2C7BF2"

    function toHex(c) { return Qt.rgba(c.r, c.g, c.b, 1).toString().substring(0, 7).toUpperCase() }

    function open() {
        var c = Qt.color(prefs.carColor)
        cz.hue = c.hsvHue >= 0 ? c.hsvHue : cz.hue
        cz.sat = c.hsvSaturation
        cz.val = c.hsvValue
        cz.visible = true
        ring.requestPaint()
    }
    function close() { cz.visible = false }

    function apply() {
        var hex = cz.toHex(cz.current)
        prefs.carColor = hex
        cz.colorPicked(hex)
    }
    function pickHex(hex) {
        var c = Qt.color(hex)
        if (c.hsvHue >= 0) cz.hue = c.hsvHue
        cz.sat = c.hsvSaturation
        cz.val = c.hsvValue
        prefs.carColor = hex
        cz.colorPicked(hex)
    }
    function setFinish(f) {
        prefs.carFinish = f
        cz.finishPicked(f)
    }
    function addCurrentToPalette() {
        var hex = cz.toHex(cz.current)
        if (cz.defaultPalette.indexOf(hex) >= 0) return
        var list = prefs.carPalette.length ? prefs.carPalette.split(",") : []
        var idx = list.indexOf(hex)
        if (idx >= 0) list.splice(idx, 1)
        list.push(hex)
        if (list.length > 6) list.shift()
        prefs.carPalette = list.join(",")
        cz.pickHex(hex)
    }

    // ── Color swatch with "paint" reflection ──
    component Swatch: Rectangle {
        id: sw
        property string hex
        width: 40; height: 40; radius: 8
        color: hex
        border.width: 1
        border.color: cz.lightTheme ? "#D0D0D0" : "#454545"
        Rectangle {           // horizontal reflection as in the EV swatches
            x: 3; width: parent.width - 6; y: parent.height * 0.36; height: 4; radius: 2
            color: "#66FFFFFF"
        }
        Rectangle {           // selezionato
            anchors.fill: parent; anchors.margins: -4
            radius: sw.radius + 3
            color: "transparent"
            border.width: 2; border.color: cz.blue
            visible: Qt.colorEqual(prefs.carColor, sw.hex)
        }
        MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: cz.pickHex(sw.hex) }
    }

    // Dark background, tap outside = close
    Rectangle {
        anchors.fill: parent; color: "#99000000"
        MouseArea { anchors.fill: parent; onClicked: cz.close() }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 660)
        height: 486
        radius: 8
        color: cz.panelBg
        MouseArea { anchors.fill: parent }

        // ── Intestazione ──
        Item {
            id: hdr
            width: parent.width; height: 56
            Text {
                x: 22; anchors.verticalCenter: parent.verticalCenter
                text: "✕"; color: cz.txtSub; font.pixelSize: 20
                MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: cz.close() }
            }
            Text {
                anchors.centerIn: parent
                text: qsTr("Colorizer"); color: cz.txt; font.pixelSize: 18; font.weight: Font.DemiBold
            }
        }
        Rectangle { anchors.top: hdr.bottom; width: parent.width; height: 1; color: cz.divider }

        // ── Ruota tinte (ciambella) ──
        Item {
            id: ringBox
            x: 32; y: hdr.height + 24
            width: 200; height: 200
            readonly property real outerR: width / 2
            readonly property real thick: 26
            readonly property real midR: outerR - thick / 2

            Canvas {
                id: ring
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                    var cx = width / 2, cy = height / 2
                    ctx.lineWidth = ringBox.thick
                    for (var a = 0; a < 360; a += 1) {
                        ctx.beginPath()
                        ctx.strokeStyle = Qt.hsva(a / 360.0, 1.0, 1.0, 1.0)
                        ctx.arc(cx, cy, ringBox.midR, (a - 0.6) * Math.PI / 180, (a + 0.6) * Math.PI / 180)
                        ctx.stroke()
                    }
                }
                Component.onCompleted: requestPaint()
            }
            // Handle on the donut
            Rectangle {
                width: 28; height: 28; radius: 14
                color: Qt.hsva(cz.hue, 1, 1, 1)
                border.width: 3; border.color: "#FFFFFF"
                x: ringBox.width / 2 + Math.cos(cz.hue * 2 * Math.PI) * ringBox.midR - width / 2
                y: ringBox.height / 2 + Math.sin(cz.hue * 2 * Math.PI) * ringBox.midR - height / 2
            }
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                function upd(mx, my) {
                    var a = Math.atan2(my - height / 2, mx - width / 2)
                    if (a < 0) a += 2 * Math.PI
                    cz.hue = a / (2 * Math.PI)
                    cz.apply()
                }
                onPressed: (m) => upd(m.x, m.y)
                onPositionChanged: (m) => { if (pressed) upd(m.x, m.y) }
            }
        }

        // ── Saturation / brightness square ──
        Item {
            id: svBox
            anchors.right: parent.right; anchors.rightMargin: 32
            y: hdr.height + 24
            width: Math.min(230, panel.width - ringBox.width - 110); height: 200

            Rectangle {
                id: svBase
                anchors.fill: parent
                radius: 8
                color: Qt.hsva(cz.hue, 1, 1, 1)
            }
            // white → hue (saturation, left to right)
            Rectangle {
                anchors.fill: parent; radius: 8
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#FFFFFFFF" }
                    GradientStop { position: 1.0; color: "#00FFFFFF" }
                }
            }
            // transparent → black (brightness, top to bottom)
            Rectangle {
                anchors.fill: parent; radius: 8
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00000000" }
                    GradientStop { position: 1.0; color: "#FF000000" }
                }
            }
            // Rounded square handle, as in the photo
            Rectangle {
                width: 26; height: 26; radius: 8
                color: cz.current
                border.width: 3; border.color: "#FFFFFF"
                x: cz.sat * svBox.width - width / 2
                y: (1 - cz.val) * svBox.height - height / 2
            }
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                function upd(mx, my) {
                    cz.sat = Math.max(0, Math.min(1, mx / width))
                    cz.val = Math.max(0, Math.min(1, 1 - my / height))
                    cz.apply()
                }
                onPressed: (m) => upd(m.x, m.y)
                onPositionChanged: (m) => { if (pressed) upd(m.x, m.y) }
            }
        }

        // ── Paint type ──
        Column {
            id: finishCol
            x: 32; y: ringBox.y + ringBox.height + 22
            spacing: 10
            Text { text: qsTr("Paint type"); color: cz.txt; font.pixelSize: 14; font.weight: Font.DemiBold }
            Rectangle {
                width: 330; height: 44; radius: 8
                color: cz.ctrlBg
                border.width: 1; border.color: cz.divider
                readonly property real cellW: width / cz.finishes.length
                Rectangle {           // sliding indicator (like the Settings selectors)
                    width: parent.cellW - 6; height: parent.height - 6; radius: 8
                    y: 3
                    x: 3 + Math.max(0, cz.finishes.map(function(f) { return f.id }).indexOf(prefs.carFinish)) * parent.cellW
                    color: cz.ctrlSel
                    Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
                }
                Row {
                    anchors.fill: parent
                    Repeater {
                        model: cz.finishes
                        Item {
                            width: parent.width / cz.finishes.length; height: parent.height
                            Text {
                                anchors.centerIn: parent
                                text: modelData.name
                                color: prefs.carFinish === modelData.id ? cz.txt : cz.txtSub
                                font.pixelSize: 14
                                font.weight: prefs.carFinish === modelData.id ? Font.DemiBold : Font.Normal
                            }
                            MouseArea { anchors.fill: parent; onClicked: cz.setFinish(modelData.id) }
                        }
                    }
                }
            }
        }

        // ── Divisore orizzontale ──
        Rectangle {
            id: bottomDiv
            anchors.bottom: presetRow.top; anchors.bottomMargin: 18
            width: parent.width; height: 1; color: cz.divider
        }

        // ── "+" · personalizzati · predefiniti ──
        Flickable {
            id: presetRow
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16
            x: 20; width: parent.width - 40; height: 52
            contentWidth: _presets.width; contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

        Row {
            id: _presets
            y: 6; x: 4
            spacing: 14

            Rectangle {
                width: 40; height: 40; radius: 8
                color: "transparent"
                border.width: 1.5; border.color: cz.txtSub
                Text { anchors.centerIn: parent; text: "+"; color: cz.txtSub; font.pixelSize: 24 }
                MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: cz.addCurrentToPalette() }
            }
            Repeater {
                model: cz.customPalette
                Swatch { hex: modelData }
            }
            Rectangle {
                width: 1; height: 32; color: cz.divider
                anchors.verticalCenter: parent.verticalCenter
                visible: cz.customPalette.length > 0
            }
            Repeater {
                model: cz.defaultPalette
                Swatch { hex: modelData }
            }
        }
        }
    }
}
