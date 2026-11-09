import QtQuick

// Speed cluster in EV style: PRND, number, unit, and light indicators
// (green headlight + red seat belt, icons taken from the repo). Compact proportions.
Item {
    id: cluster

    property string gear:        "P"        // P R N D
    property string speedValue:  "0"
    property string speedUnit:   "km/h"
    property bool   lightTheme:  false
    property bool   rhd:         false     // right-hand drive: content aligned to the right (the block sits on the right edge)

    // Indicators (on by default as in the photo). Connect them to the real data.
    property bool headlightOn: true
    property bool highBeamOn:  false
    property bool seatbeltOn:  true

    implicitWidth:  col.width      // as wide as the content: so the margin from the edge is the real one
    implicitHeight: col.height

    Column {
        id: col
        spacing: 2

        // ── PRND ────────────────────────────────────────────────────────────
        Row {
            x: cluster.rhd ? col.width - width : 0
            spacing: 7
            Repeater {
                model: ["P", "R", "N", "D"]
                Text {
                    text: modelData
                    font.pixelSize: 15; font.weight: Font.DemiBold; font.letterSpacing: 1
                    color: cluster.gear === modelData ? "#F0F0F0" : "#414141"
                }
            }
        }

        // ── Number + unit ───────────────────────────────────────────────────
        Column {
            x: cluster.rhd ? col.width - width : 0
            spacing: -2
            Text {
                x: cluster.rhd ? parent.width - width : 0
                text: cluster.speedValue
                color: cluster.lightTheme ? "#171717" : "#F0F0F0"
                font.pixelSize: 80; font.weight: Font.Thin; font.letterSpacing: -1
                lineHeight: 0.9
            }
            Text {
                x: cluster.rhd ? parent.width - width : 0
                text: cluster.speedUnit
                color: "#757575"
                font.pixelSize: 18; font.weight: Font.DemiBold; font.letterSpacing: 1
                topPadding: 2
            }
        }

        // ── Light indicators (icons from the repo) ──────────────────────────
        Column {
            x: cluster.rhd ? col.width - width : 0
            // Increased from 8 to 65 to make exact room for the speed-limit sign
            topPadding: 65
            spacing: 6

            // faro anabbagliante (verde)
            Image {
                source: "qrc:/VoltaApp/icons/light-headlight.svg"
                sourceSize.width: 28; sourceSize.height: 28
                width: 28; height: 28
                visible: cluster.headlightOn
                smooth: true
            }
            // abbaglianti (verde, variante)
            Image {
                source: "qrc:/VoltaApp/icons/light-highbeam.svg"
                sourceSize.width: 28; sourceSize.height: 28
                width: 28; height: 28
                visible: cluster.highBeamOn
                smooth: true
            }
            // seat belt (red)
            Image {
                source: "qrc:/VoltaApp/icons/light-seatbelt.svg"
                sourceSize.width: 26; sourceSize.height: 26
                width: 26; height: 26
                visible: cluster.seatbeltOn
                smooth: true
            }
        }
    }
}