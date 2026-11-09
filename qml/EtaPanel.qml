import QtQuick
import QtQuick.Shapes

// Trip panel (SVG drawing): arrival time | duration and distance, destination,
// progress line with arrow, "End trip" | divider | •••.
// Used by the map's bottom box (MapLibreView) and by the map widget (MapWidget).
// All measures are those of the drawing: panel 226.4 px wide => k = width / 300.
Item {
    id: eta
    property real k: 1
    property string arrival: "--:--"
    property string duration: qsTr("-- min")
    property string distance: qsTr("-- km")
    property string destination: ""
    property real progress: 0
    property var traffic: []            // [{from, to, color}] as a 0..1 fraction of the route
    property color cText: "#F5F5F5"
    property color cSubtle: "#A3A3A3"
    property color lineColor: "#0A84FF"       // same blue as the navigation line
    property bool interactive: true
    // how far the progress line protrudes left/right to touch the widget's edges
    property real bleedL: 0
    property real bleedR: 0
    // side margin of the texts
    property real padX: 0
    // empty space at the top to remove (only needed when the block sits inside another box)
    property real yOff: 0
    // Vertical distribution (used by the map widget, which is taller than the drawing):
    // vStretch widens the gaps between rows (1 = as in the drawing), vShift moves everything.
    // The sizes of texts, line and divider do NOT change.
    property real vStretch: 1
    property real vShift: 0
    signal stopRequested()
    signal recenterRequested()
    signal addStopRequested()
    signal editTripRequested()   // dl92
    property bool menuOpen: false
    property bool menuExternal: false   // map widget: the ••• open the big map with the menu open
    signal menuRequested()
    // dl92: with growMenu the ••• menu sits INSIDE the widget, which grows upward
    property bool growMenu: false
    property bool canAddStop: true
    readonly property real menuRowH: Math.round(48 * k)
    readonly property real menuTargetH: growMenu ? 2 * menuRowH : 0   // dl94: 2 voci
    property real menuH: (growMenu && menuOpen) ? menuTargetH : 0
    Behavior on menuH { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    onInteractiveChanged: if (!interactive) menuOpen = false

    function vy(v) { return Math.round((10.9 + (v - 10.9) * vStretch) * k + vShift) - yOff }   // dl93: the menu sits BELOW, the rest does not move
    // line and arrow have EQUAL sizes: so the arrow tip falls exactly
    // on the line's midline, at any scale
    readonly property int lineBox: 2 * Math.max(1, Math.round(6 * k))
    readonly property real dividerH: Math.round(35.8 * k)
    readonly property int lineT: Math.max(2, 2 * Math.round(1.6 * k))

    implicitHeight: Math.round(127.3 * k + menuH) - yOff
    height: implicitHeight

    // row 1: arrival time | duration and distance (same weight and same color)
    Text {
        x: eta.padX
        y: eta.vy(19.7) - height / 2
        text: eta.arrival
        color: eta.cText; opacity: 0.8
        font.pixelSize: Math.round(17.6 * eta.k)
    }
    Row {
        anchors.right: parent.right; anchors.rightMargin: eta.padX
        y: eta.vy(19.7) - height / 2
        spacing: Math.round(30.5 * eta.k)
        Text {
            text: eta.duration
            color: eta.cText; opacity: 0.8
            font.pixelSize: Math.round(17.6 * eta.k)
        }
        Text {
            text: eta.distance
            color: eta.cText; opacity: 0.8
            font.pixelSize: Math.round(17.6 * eta.k)
        }
    }
    // row 2: destination
    Text {
        x: eta.padX
        y: eta.vy(43.6) - height / 2
        width: parent.width - 2 * eta.padX
        text: eta.destination
        color: eta.cText; opacity: 0.8
        font.pixelSize: Math.round(16 * eta.k)
        maximumLineCount: 1
        elide: Text.ElideRight
    }
    // progress line: remaining stretch in blue, arrow at the current position
    Item {
        x: -eta.bleedL
        y: eta.vy(63.6) - eta.lineBox / 2
        width: parent.width + eta.bleedL + eta.bleedR
        height: eta.lineBox
        Rectangle {
            y: (eta.lineBox - eta.lineT) / 2
            x: parent.width * Math.max(0, Math.min(1, eta.progress))
            width: parent.width - x
            height: eta.lineT
            radius: height / 2
            color: eta.lineColor
            Behavior on x { NumberAnimation { duration: 400 } }
            Behavior on width { NumberAnimation { duration: 400 } }
        }
        // traffic: the colored stretches above the blue line, only from where you are onward
        Item {
            y: (eta.lineBox - eta.lineT) / 2
            width: parent.width; height: eta.lineT
            Repeater {
                model: eta.traffic
                Rectangle {
                    readonly property real p: Math.max(0, Math.min(1, eta.progress))
                    readonly property real a: Math.max(modelData.from, p)
                    visible: modelData.to > p
                    x: parent.width * a
                    width: Math.max(1, parent.width * (modelData.to - a))
                    height: parent.height
                    radius: height / 2
                    color: modelData.color
                }
            }
        }
        // arrow: drawn as a vector (same graphics as icons/map-arrow.svg) so the tip
        // always falls exactly on the line's midline
        Item {
            id: arrow
            width: eta.lineBox; height: eta.lineBox
            y: 0
            x: Math.max(0, parent.width * Math.max(0, Math.min(1, eta.progress)) - width / 2)
            Behavior on x { NumberAnimation { duration: 400 } }
            layer.enabled: true
            layer.smooth: true
            layer.samples: 4
            Item {
                anchors.centerIn: parent
                width: arrow.width; height: arrow.height
                rotation: 90
                Shape {
                    width: 136; height: 157
                    x: (arrow.width - 136 * arrow.height / 157) / 2
                    transform: Scale { xScale: arrow.height / 157; yScale: arrow.height / 157 }
                    ShapePath { fillRule: ShapePath.WindingFill; fillColor: "#FFFFFF"; strokeColor: "transparent"; PathSvg { path: qsTr("M67.2527 133.236C48.0527 142.429 35.7661 148.385 30.3927 151.105C24.0261 154.332 19.4794 155.969 16.7527 156.016C7.57275 156.176 -0.167252 149.065 0.00274828 139.505C0.049415 136.972 0.929414 133.932 2.64275 130.385C2.74275 130.179 19.7728 89.8788 53.7327 9.48549C55.9727 4.18549 62.0127 0.255494 68.0127 0.015494C72.7061 -0.171173 76.7961 1.32883 80.2827 4.5155C82.2294 6.28883 84.3127 10.1555 86.5327 16.1155C86.7327 16.6622 101.709 53.0122 131.463 125.165C134.573 132.695 136.853 136.385 135.643 142.335C133.973 150.545 126.603 155.686 118.433 155.406C116.119 155.326 113.013 154.309 109.113 152.355C107.379 151.495 94.0027 145.119 68.9827 133.225C68.7107 133.098 68.4141 133.032 68.1146 133.034C67.8152 133.036 67.5207 133.104 67.2527 133.236ZM68.1628 123.925L88.3528 133.546C97.2594 137.846 106.299 142.145 115.473 146.445C120.783 148.935 127.443 146.005 127.953 139.965C128.059 138.719 127.489 136.579 126.243 133.546C117.516 112.299 108.786 91.1022 100.053 69.9555L80.5428 22.6755C79.5894 20.2888 78.6094 17.8855 77.6028 15.4655C76.4028 12.5855 75.3894 10.7855 74.5627 10.0655C71.2227 7.19549 66.1327 7.3655 62.8627 10.2155C61.9361 11.0155 60.9027 12.8388 59.7627 15.6855C59.1627 17.1988 42.4261 56.8355 9.55275 134.596C8.42608 137.256 7.89608 139.182 7.96275 140.376C8.19275 144.786 12.2027 148.045 16.4627 147.995C17.7227 147.982 19.7528 147.299 22.5528 145.945C37.7994 138.552 53.0028 131.212 68.1628 123.925Z") } }
                    ShapePath { fillRule: ShapePath.WindingFill; fillColor: "#FF3A3A"; strokeColor: "transparent"; PathSvg { path: "M80.5426 22.6756L68.5026 48.1156C68.3776 48.3788 68.3127 48.6691 68.3126 48.9656L68.1626 123.926C53.0026 131.212 37.7993 138.552 22.5526 145.946C19.7526 147.299 17.7226 147.982 16.4626 147.996C12.2026 148.046 8.19262 144.786 7.96262 140.376C7.89595 139.182 8.42596 137.256 9.55262 134.596C42.426 56.8356 59.1626 17.1989 59.7626 15.6856C60.9026 12.8389 61.936 11.0156 62.8626 10.2156C66.1326 7.36557 71.2226 7.19557 74.5626 10.0656C75.3893 10.7856 76.4026 12.5856 77.6026 15.4656C78.6093 17.8856 79.5893 20.2889 80.5426 22.6756Z" } }
                    ShapePath { fillRule: ShapePath.WindingFill; fillColor: "#FF3A3A"; strokeColor: "transparent"; PathSvg { path: "M100.053 69.9558C108.786 91.1024 117.516 112.299 126.242 133.546C127.489 136.579 128.059 138.719 127.952 139.966C127.442 146.005 120.783 148.936 115.473 146.446C106.299 142.146 97.2592 137.846 88.3525 133.546L68.1621 123.926L68.3125 48.9656C68.3126 48.6692 68.378 48.3791 68.5029 48.116L80.543 22.6755L100.053 69.9558Z" } }
                }
            }
        }
    }
    // bottom row: End trip | divider | •••
    Text {
        x: eta.width * 0.369 - width / 2
        y: eta.vy(93.0) - height / 2
        text: qsTr("End trip")
        color: eta.cSubtle
        font.pixelSize: Math.round(17.4 * eta.k)
    }
    MouseArea {
        enabled: eta.interactive
        x: 0; y: Math.round(eta.vy(96) - dividerH / 2); width: eta.width * 0.694; height: Math.round(127.3 * eta.k) - eta.yOff - y   // dl93
        onClicked: eta.stopRequested()
    }
    Rectangle {
        x: eta.width * 0.694
        y: Math.round(eta.vy(96) - height / 2)
        width: Math.max(1, Math.round(0.8 * eta.k)); height: eta.dividerH
        color: eta.cSubtle
    }
    Row {
        x: eta.width * 0.848 - width / 2
        y: eta.vy(95.9) - height / 2
        spacing: Math.round(3.2 * eta.k)
        Repeater {
            model: 3
            Rectangle { width: Math.round(3.43 * eta.k); height: width; radius: width / 2; color: eta.cSubtle }
        }
    }
    MouseArea {
        enabled: eta.interactive
        x: eta.width * 0.694; y: Math.round(eta.vy(96) - dividerH / 2); width: eta.width - x; height: Math.round(127.3 * eta.k) - eta.yOff - y   // dl93
        onClicked: { if (eta.menuExternal) eta.menuRequested(); else eta.menuOpen = !eta.menuOpen }
    }

    // dl92: menu inside the widget (rises from the bottom: the panel grows upward)
    Item {
        id: inlineMenu
        visible: eta.growMenu && eta.menuH > 0.5
        x: 0
        y: Math.round(127.3 * eta.k) - eta.yOff   // dl93: right below the End trip row
        width: parent.width
        height: eta.menuH
        clip: true
        z: 100
        opacity: eta.menuTargetH > 0 ? Math.min(1, eta.menuH / eta.menuTargetH) : 0
        Timer { running: eta.growMenu && eta.menuOpen; interval: 9000; onTriggered: eta.menuOpen = false }
        Column {
            width: parent.width
            Repeater {
                model: [ { t: qsTr("Add stop"), a: "stop" }, { t: qsTr("Edit route"), a: "edit" } ]   // dl94: via Ricentra
                Item {
                    id: imRow
                    readonly property bool off: modelData.a === "stop" && !eta.canAddStop
                    width: inlineMenu.width
                    height: eta.menuRowH
                    Rectangle { anchors.fill: parent; color: eta.cText; opacity: 0.12; visible: _im.pressed && !imRow.off }
                    Text {
                        x: eta.padX + Math.round(6 * eta.k)
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.t + (imRow.off ? qsTr("  (max 2)") : "")
                        color: imRow.off ? eta.cSubtle : eta.cText
                        opacity: imRow.off ? 0.6 : 0.9
                        font.pixelSize: Math.round(17 * eta.k)
                    }
                    Rectangle {
                        anchors.top: parent.top
                        x: eta.padX; width: parent.width - 2 * eta.padX
                        height: 1; color: eta.cSubtle; opacity: 0.35
                    }
                    MouseArea {
                        id: _im
                        anchors.fill: parent
                        onClicked: {
                            if (imRow.off) return   // dl93: disabled but absorbs the touch
                            eta.menuOpen = false
                            if (modelData.a === "stop") eta.addStopRequested()
                            else if (modelData.a === "edit") eta.editTripRequested()
                            else eta.recenterRequested()
                        }
                    }
                }
            }
        }
    }

    // Three-dots menu (old one, above the bar): only where the widget does not grow (map widget)
    Rectangle {
        id: moreMenu
        visible: eta.menuOpen && !eta.growMenu
        z: 100
        readonly property real itemH: 52
        width: 210; height: itemH * 2 + 2
        x: eta.width - width - Math.round(6 * eta.k)
        y: -height - 8
        radius: 12
        color: "#F2262626"
        border.width: 1; border.color: "#3A3A3A"
        Timer { running: moreMenu.visible; interval: 7000; onTriggered: eta.menuOpen = false }
        Column {
            anchors.fill: parent
            Repeater {
                model: [ { t: qsTr("Add stop"), a: "stop" }, { t: qsTr("Recenter"), a: "center" } ]
                Item {
                    width: moreMenu.width; height: moreMenu.itemH
                    Rectangle { anchors.fill: parent; radius: 12; color: "#33FFFFFF"; visible: _mm.pressed }
                    Text { x: 18; anchors.verticalCenter: parent.verticalCenter; text: modelData.t; color: "#F5F5F5"; font.pixelSize: 17 }
                    Rectangle { visible: index === 0; anchors.bottom: parent.bottom; x: 14; width: parent.width - 28; height: 1; color: "#3A3A3A" }
                    MouseArea {
                        id: _mm; anchors.fill: parent
                        onClicked: {
                            eta.menuOpen = false
                            if (modelData.a === "stop") eta.addStopRequested(); else eta.recenterRequested()
                        }
                    }
                }
            }
        }
    }
}
