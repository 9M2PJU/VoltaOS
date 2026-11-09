import QtQuick
import QtLocation
import QtPositioning
import QtQuick.Effects
import VoltaApp 1.0

// Map of Mars (Toybox › Mars): the planet's real surface at the same
// latitude/longitude as the car, served by map_proxy.py (/style.json?s=mars).
// No search, route or navigation.
Item {
    id: mars

    property real carLat: 0
    property real carLon: 0
    property real carBearing: 0
    property bool interactive: true
    property real startZoom: 6.5
    property real roverSize: 52
    property bool showLabel: true

    // White radial glow (Canvas: no extra module required)
    component RadialGlow: Canvas {
        property real size: 60
        width: size; height: size
        onPaint: {
            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
            var r = width / 2
            var g = ctx.createRadialGradient(r, r, 0, r, r, r)
            g.addColorStop(0.0, "rgba(255,255,255,0.75)")
            g.addColorStop(0.45, "rgba(255,255,255,0.35)")
            g.addColorStop(1.0, "rgba(255,255,255,0.0)")
            ctx.fillStyle = g
            ctx.beginPath(); ctx.arc(r, r, r, 0, 2 * Math.PI); ctx.fill()
        }
        onSizeChanged: requestPaint()
        Component.onCompleted: requestPaint()
    }

    Rectangle { anchors.fill: parent; color: "#1A0E08" }

    Map {
        id: map
        anchors.fill: parent
        plugin: Plugin {
            name: "maplibre"
            PluginParameter { name: "maplibre.map.styles"; value: "http://127.0.0.1:9098/style.json?s=mars" }
        }
        zoomLevel: mars.startZoom
        minimumZoomLevel: 3
        maximumZoomLevel: 7.5          // the global NASA mosaics reach ~z6: beyond that it gets grainy
        copyrightsVisible: false
        color: "#1A0E08"
        center: QtPositioning.coordinate(mars.carLat, mars.carLon)

        // Mars rover in place of the car arrow (as in EVs)
        MapQuickItem {
            coordinate: QtPositioning.coordinate(mars.carLat, mars.carLon)
            anchorPoint.x: mars.roverSize / 2; anchorPoint.y: mars.roverSize / 2
            sourceItem: Item {
                width: mars.roverSize; height: mars.roverSize
                rotation: mars.carBearing - map.bearing
                // Soft white glow under the rover
                RadialGlow { anchors.centerIn: parent; size: parent.width * 1.5 }
                Image {
                    anchors.fill: parent
                    source: "qrc:/VoltaApp/images/mars_rover.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true; mipmap: true
                    layer.enabled: true
                    layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.5; shadowColor: "#66000000"; shadowVerticalOffset: 2 }
                }
            }
        }

        PinchHandler {
            enabled: mars.interactive
            target: null
            property real startZ: 0
            onActiveChanged: if (active) startZ = map.zoomLevel
            onActiveScaleChanged: map.zoomLevel = Math.max(map.minimumZoomLevel, Math.min(map.maximumZoomLevel, startZ + Math.log2(activeScale)))
        }
        DragHandler {
            enabled: mars.interactive
            target: null
            onTranslationChanged: (delta) => map.pan(-delta.x, -delta.y)
        }
        WheelHandler {
            enabled: mars.interactive
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (e) => map.zoomLevel = Math.max(map.minimumZoomLevel, Math.min(map.maximumZoomLevel, map.zoomLevel + (e.angleDelta.y > 0 ? 0.4 : -0.4)))
        }
    }

    // Blocks touches to the Earth map underneath
    MouseArea { anchors.fill: parent; z: -1; acceptedButtons: Qt.AllButtons; onWheel: (w) => w.accepted = true }

    property bool lightTheme: false

    // "Mars" label at the bottom right, same box as the street/city
    // current in the normal map (no navigation button here)
    Rectangle {
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.rightMargin: mars.interactive ? 16 : 10
        anchors.bottomMargin: mars.interactive ? 88 : 10
        radius: 8
        color: mars.lightTheme ? "#EBE8E8EA" : "#EB141414"
        width: _lblCol.width + 22; height: _lblCol.height + 14
        visible: mars.showLabel
        Column {
            id: _lblCol
            anchors.centerIn: parent
            Text { text: qsTr("Mars"); color: mars.lightTheme ? "#171717" : "#F0F0F0"; font.pixelSize: 14; font.weight: Font.DemiBold }
        }
    }
}
