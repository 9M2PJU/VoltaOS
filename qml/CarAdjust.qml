import QtQuick
import VoltaApp 1.0

// "Car adjust": car position and size, shadow, button positions. Visible right away on the car.
// Each value has a slider and − / + buttons for precise tweaks. Everything saves by itself.
Item {
    id: adj
    property var scene: null                // CarScene
    property var blurSources: []          // what to blur behind the panel
    property bool lightTheme: false
    signal closed()

    readonly property color fg: lightTheme ? "#1D1D1F" : "#FFFFFF"
    readonly property color sub: lightTheme ? "#555555" : "#BBBBBB"
    readonly property color btnBg: lightTheme ? "#D5D5D5" : "#3A3A3A"
    // control colors: the same as the Settings
    readonly property color ctrlBg: lightTheme ? "#E3E3E3" : "#2E2E2E"
    readonly property color ctrlBrd: lightTheme ? "#D8D8D8" : "#454545"
    readonly property color trackCol: lightTheme ? "#DDDDDD" : "#333333"
    readonly property color thumbCol: lightTheme ? "#FFFFFF" : "#A2A3A5"
    readonly property color thumbTxt: lightTheme ? "#171717" : "#FFFFFF"
    readonly property color btnBgDown: lightTheme ? "#C0C0C0" : "#505050"

    // an adjustable value: label, slider, − and +
    component AdjRow: Item {
        id: row
        property string label
        property string key
        property real lo: 0
        property real hi: 1
        property real step: 0.01
        property real mult: 1                 // for the text (e.g. 100 = percentage)
        property string unit: ""
        property int decimals: 0
        readonly property real value: adj.scene ? adj.scene.layout[key] : 0
        function setValue(v) { v = Math.max(lo, Math.min(hi, v)); adj.setValue(key, Math.round(v * 1000) / 1000) }
        width: parent.width; height: 60

        Text { x: 2; y: 0; text: row.label; color: adj.sub; font.pixelSize: 13 }
        // same look as the brightness slider: round container, thin line and wide knob with the value inside
        Rectangle {
            id: bar
            y: 18; width: parent.width; height: 40; radius: 10
            color: adj.ctrlBg; border.width: 1; border.color: adj.ctrlBrd
            clip: true
            Item {
                id: minusBox; x: 0; width: 44; height: parent.height
                Text { anchors.centerIn: parent; text: "−"; color: _mm.pressed ? adj.fg : adj.sub; font.pixelSize: 24 }
                MouseArea { id: _mm; anchors.fill: parent; onClicked: row.setValue(row.value - row.step)
                            onPressAndHold: rep.start(-row.step); onReleased: rep.stop() }
            }
            Item {
                id: track
                x: 44; width: parent.width - 88; height: parent.height
                readonly property real frac: Math.max(0, Math.min(1, (row.value - row.lo) / (row.hi - row.lo)))
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: adj.trackCol }
                Rectangle {
                    id: thumb
                    width: 74; height: parent.height; radius: 10
                    color: adj.thumbCol; border.width: 1; border.color: adj.ctrlBrd
                    anchors.verticalCenter: parent.verticalCenter
                    x: track.frac * (track.width - width)
                    Text { anchors.centerIn: parent; text: (row.value * row.mult).toFixed(row.decimals) + row.unit
                           color: adj.thumbTxt; font.pixelSize: 15; font.weight: Font.DemiBold }
                }
                MouseArea {
                    anchors.fill: parent; preventStealing: true
                    function upd(mx) {
                        var safeX = Math.max(0, Math.min(mx - thumb.width / 2, track.width - thumb.width))
                        var f = safeX / (track.width - thumb.width)
                        if (isNaN(f)) f = 0
                        row.setValue(row.lo + f * (row.hi - row.lo))
                    }
                    onPressed: m => upd(m.x)
                    onPositionChanged: m => { if (pressed) upd(m.x) }
                }
            }
            Item {
                id: plusBox; x: parent.width - 44; width: 44; height: parent.height
                Text { anchors.centerIn: parent; text: "+"; color: _pp.pressed ? adj.fg : adj.sub; font.pixelSize: 24 }
                MouseArea { id: _pp; anchors.fill: parent; onClicked: row.setValue(row.value + row.step)
                            onPressAndHold: rep.start(row.step); onReleased: rep.stop() }
            }
        }
        // holding − or + the value keeps changing
        Timer {
            id: rep; interval: 70; repeat: true
            property real d: 0
            function start(delta) { d = delta; running = true }
            function stop() { running = false }
            onTriggered: row.setValue(row.value + d)
        }
    }

    // writes a value; with locked proportions the shadow's length and width grow together
    function setValue(key, v) {
        if (!scene) return
        var L = scene.layout
        if (L.shLock && key === "shLen" && L.shLen > 0.0001) {
            var k = v / L.shLen
            scene.setLayout("shWid", Math.max(0.2, Math.min(5, Math.round(L.shWid * k * 1000) / 1000)))
        } else if (L.shLock && key === "shWid" && L.shWid > 0.0001) {
            var k2 = v / L.shWid
            scene.setLayout("shLen", Math.max(0.2, Math.min(5, Math.round(L.shLen * k2 * 1000) / 1000)))
        }
        scene.setLayout(key, v)
    }

    Rectangle {
        id: card
        readonly property bool wide: adj.width > 1100
        x: wide ? 120 : (parent.width - width) / 2
        y: wide ? 24 : 20
        width: wide ? 420 : Math.min(parent.width - 32, 460)
        height: Math.min(adj.height * 0.76 - y, content.height + footer.height + 70)
        radius: 18
        color: "transparent"
        MouseArea { anchors.fill: parent }
        GlassPanel { anchors.fill: parent; z: -1; sources: adj.blurSources; lightTheme: adj.lightTheme; radius: 18 }

        Flickable {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: footer.top
            anchors.margins: 20; anchors.bottomMargin: 10
            contentHeight: content.height; clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: content
                width: parent.width; spacing: 4

                Text { text: qsTr("Car adjust"); color: adj.fg; font.pixelSize: 24; font.weight: Font.DemiBold }
                Item { width: 1; height: 8 }

                Item {
                    width: parent.width; height: 34
                    Text { text: qsTr("Auto"); color: "#2C7BF2"; font.pixelSize: 15; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                    // the front of the car is on the wrong side: rotate 180 degrees
                    Rectangle {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: yawRow.width + 24; height: 32; radius: 16
                        color: adj.scene && adj.scene.layout.yawExtra === 180 ? "#2C7BF2" : adj.btnBg
                        Row {
                            id: yawRow; anchors.centerIn: parent; spacing: 6
                            Text { text: "↻"; font.pixelSize: 15; color: adj.scene && adj.scene.layout.yawExtra === 180 ? "#FFFFFF" : adj.fg; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: qsTr("Rotate 180°"); color: adj.scene && adj.scene.layout.yawExtra === 180 ? "#FFFFFF" : adj.fg; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: if (adj.scene) adj.scene.setLayout("yawExtra", adj.scene.layout.yawExtra === 180 ? 0 : 180) }
                    }
                }
                AdjRow { label: qsTr("Position X (left / right)"); key: "carX"; lo: -1.5; hi: 1.5; step: 0.01; mult: 100; decimals: 0 }
                AdjRow { label: qsTr("Position Y (up / down)"); key: "carY"; lo: -0.8; hi: 0.8; step: 0.01; mult: 100; decimals: 0 }
                AdjRow { label: qsTr("Size"); key: "carScale"; lo: 0.4; hi: 2.0; step: 0.01; mult: 100; unit: "%"; decimals: 0 }

                Item { width: 1; height: 6 }
                Item {
                    width: parent.width; height: 34
                    Text { text: qsTr("Shadow"); color: "#2C7BF2"; font.pixelSize: 15; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                    // blocco proporzioni: acceso = lunghezza e larghezza crescono insieme
                    Rectangle {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: lockRow.width + 24; height: 32; radius: 16
                        color: adj.scene && adj.scene.layout.shLock ? "#2C7BF2" : adj.btnBg
                        Row {
                            id: lockRow; anchors.centerIn: parent; spacing: 6
                            Text { text: adj.scene && adj.scene.layout.shLock ? "🔒" : "🔓"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: qsTr("Proportions"); color: adj.scene && adj.scene.layout.shLock ? "#FFFFFF" : adj.fg; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: if (adj.scene) adj.scene.setLayout("shLock", !adj.scene.layout.shLock) }
                    }
                }
                AdjRow { label: qsTr("Position X (left / right)"); key: "shX"; lo: -1.5; hi: 1.5; step: 0.01; mult: 100; decimals: 0 }
                AdjRow { label: qsTr("Position Y (forward / back)"); key: "shZ"; lo: -1.5; hi: 1.5; step: 0.01; mult: 100; decimals: 0 }
                AdjRow { label: qsTr("Length"); key: "shLen"; lo: 0.2; hi: 5.0; step: 0.01; mult: 100; unit: "%"; decimals: 0 }
                AdjRow { label: qsTr("Width"); key: "shWid"; lo: 0.2; hi: 5.0; step: 0.01; mult: 100; unit: "%"; decimals: 0 }

            }
        }
        // fixed part at the bottom: buttons to move, Reset, Done
        Column {
            id: footer
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: 20; spacing: 8
        Rectangle {
            width: parent.width; height: 44; radius: 10
            color: adj.scene && adj.scene.moveButtons ? "#2C7BF2" : adj.btnBg
            Text { anchors.centerIn: parent; width: parent.width - 24; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                   text: adj.scene && adj.scene.moveButtons ? qsTr("Drag the buttons on the car (tap to finish)") : qsTr("Move the buttons (lock, hood, trunk)")
                   color: adj.scene && adj.scene.moveButtons ? "#FFFFFF" : adj.fg; font.pixelSize: 14 }
            MouseArea { anchors.fill: parent; onClicked: if (adj.scene) adj.scene.moveButtons = !adj.scene.moveButtons }
        }

        Row {
            spacing: 10
            Rectangle {
                width: (footer.width - 10) / 2; height: 44; radius: 10
                color: _rs.pressed ? adj.btnBgDown : adj.btnBg
                Text { anchors.centerIn: parent; text: qsTr("Reset"); color: adj.fg; font.pixelSize: 16 }
                MouseArea { id: _rs; anchors.fill: parent; onClicked: if (adj.scene) adj.scene.resetLayout() }
            }
            Rectangle {
                width: (footer.width - 10) / 2; height: 44; radius: 10
                color: _fi.pressed ? "#1E63D0" : "#2C7BF2"
                Text { anchors.centerIn: parent; text: qsTr("Done"); color: "#FFFFFF"; font.pixelSize: 16; font.weight: Font.DemiBold }
                MouseArea { id: _fi; anchors.fill: parent; onClicked: { if (adj.scene) adj.scene.moveButtons = false; adj.closed() } }
            }
        }

        }
    }
}
