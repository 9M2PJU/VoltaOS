import QtQuick
import QtLocation
import QtPositioning
import QtWebSockets
import Qt5Compat.GraphicalEffects

// MapLibre mini-map — reduced version of MapLibreView, without controls,
// without navigation banner, without search. Only map + car + any
// route. It serves as a "sneak peek" when the car panel is full screen.
// Reuses the same service on port 9098 as the main map (map_proxy.py), so
// the tile cache is shared: no extra network cost.
Item {
    id: root

    property bool lightTheme: false
    property bool active: true
    property bool marsMode: false        // Toybox › Marte
    // The big map (MapLibreView): it takes the arrow and the fake test GPS from it
    property var source: null

    // ── Starting directly in the right theme ──
    // MapLibre, as soon as it is created, ALWAYS loads the first style in the list; changing it
    // afterwards means reloading the whole map (it started dark and then turned
    // white). That is why the map is not created right away: we wait for the UI theme
    // to settle (the settings are read after startup), then we
    // create it with the current theme's style as FIRST in the list.
    property bool _initialLight: false
    Timer {
        id: createDelay
        interval: 250
        running: true
        onTriggered: {
            root._initialLight = root.lightTheme
            mapLoader.active = true
        }
    }
    // If the theme changes before creation, start waiting again
    onLightThemeChanged: if (!mapLoader.active) createDelay.restart()

    // Index of the style matching the theme: 0 = the one loaded at startup
    readonly property int styleIndex: (lightTheme === _initialLight) ? 0 : 1

    readonly property var map: mapLoader.item

    // Reapplying the SAME style reloads the whole map: we avoid it
    property int _appliedIndex: 0
    // after the guided setup (new map keys): reload the style
    function reloadStyle() {
        if (!root.map || root.map.supportedMapTypes.length <= styleIndex) return
        root._appliedIndex = styleIndex
        root.map.activeMapType = root.map.supportedMapTypes[styleIndex]
    }
    function applyStyle() {
        if (!root.map) return
        if (root.map.supportedMapTypes.length <= styleIndex) return
        if (root._appliedIndex === styleIndex) return
        root._appliedIndex = styleIndex
        root.map.activeMapType = root.map.supportedMapTypes[styleIndex]
    }
    // Theme change with the UI already running: debounce so as not to reload several times in a row
    Timer {
        id: styleDebounce
        interval: 250
        onTriggered: root.applyStyle()
    }
    onStyleIndexChanged: if (mapLoader.active) styleDebounce.restart()

    // ── Appearance without flicker ──
    // It is shown only when the map exists AND the position is the real one,
    // plus a margin for the tiles to draw: the settling happens while
    // the map is still invisible.
    property bool _ready: false
    function _maybeReveal() {
        if (root._ready) return
        if (root.map && root.gpsReceived) revealTimer.restart()
    }
    Timer {
        id: revealTimer
        interval: 1500
        onTriggered: root._ready = true
    }
    Timer {
        // Without GPS we do not stay invisible forever
        interval: 5000; running: true
        onTriggered: root._ready = true
    }
    onGpsReceivedChanged: root._maybeReveal()

    // Position shown: interpolated (the Behaviors smooth between one fix and the next)
    property real carLat: 45.4642
    property real carLon: 9.1900
    // Disabled until the first fix: the first jump (default → GPS) is instant,
    // not a long pan across the map.
    readonly property bool _mirror: !!root.source && root.source.gpsReceived
    Behavior on carLat { enabled: root.gpsReceived && !root._mirror; NumberAnimation { duration: 450; easing.type: Easing.Linear } }
    Behavior on carLon { enabled: root.gpsReceived && !root._mirror; NumberAnimation { duration: 450; easing.type: Easing.Linear } }

    property real bearingRot: 0
    property bool gpsReceived: false

    // Last "useful" fix — dead band to avoid jitter when stopped
    property real _lastFixLat: 0
    property real _lastFixLon: 0
    readonly property real bearingMinSpeed: 4.0

    readonly property string _darkUrl:  "http://127.0.0.1:9098/style.json?s=dark"
    readonly property string _lightUrl: "http://127.0.0.1:9098/style.json?s=light"

    Loader {
        id: mapLoader
        anchors.fill: parent
        active: false
        opacity: root._ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        onLoaded: {
            item.center = QtPositioning.coordinate(root.carLat, root.carLon)
            root._maybeReveal()
        }

        sourceComponent: Component {
            Map {
                id: map
                plugin: Plugin {
                    name: "maplibre"
                    PluginParameter {
                        name: "maplibre.map.styles"
                        // First in the list = current theme at startup → no style change
                        value: root._initialLight
                               ? (root._lightUrl + "," + root._darkUrl)
                               : (root._darkUrl + "," + root._lightUrl)
                    }
                }
                zoomLevel: 17.0             // same zoom as the navigation view
                tilt: 0
                maximumTilt: 0
                copyrightsVisible: false

                // Background consistent with the theme while the tiles load
                color: root.lightTheme ? "#F2F2F2" : "#141414"

                // If the big map is navigating, the mini one rotates too to align
                // the "front" to the top
                // (with the big map available: same angle, already smoothed, as the big one)
                bearing: root._mirror ? root.source._mapBearing : (Nav.navigating ? root.bearingRot : 0)
                Behavior on bearing { enabled: !root._mirror; RotationAnimation { duration: 600; direction: RotationAnimation.Shortest } }

                // Route: thin line because the mini map is small
                MapPolyline {
                    visible: Nav.hasRoute
                    line.width: 5; line.color: "#1B3A6B"
                    path: Nav.routeCoordinates
                }
                MapPolyline {
                    visible: Nav.hasRoute
                    line.width: 3; line.color: "#4A9EFF"
                    path: Nav.routeCoordinates
                }
                // Part already traveled: dark blue as in the big map
                MapPolyline {
                    visible: !!root.source && root.source._riding && Nav.navigating
                    line.width: 5; line.color: "#3A4A62"
                    path: root.source ? root.source.trvStaticPath : []
                }
                MapPolyline {
                    visible: !!root.source && root.source._riding && Nav.navigating
                    line.width: 3; line.color: "#5F7290"
                    path: root.source ? root.source.trvStaticPath : []
                }
                MapPolyline {
                    visible: !!root.source && root.source._riding && Nav.navigating && root.source._trvLive.length > 1
                    line.width: 5; line.color: "#3A4A62"
                    path: root.source ? root.source._trvLive : []
                }
                MapPolyline {
                    visible: !!root.source && root.source._riding && Nav.navigating && root.source._trvLive.length > 1
                    line.width: 3; line.color: "#5F7290"
                    path: root.source ? root.source._trvLive : []
                }
                // Traffic on the route (orange / red), as in the big map
                MapItemView {
                    model: Nav.trafficSegments
                    delegate: MapPolyline {
                        visible: modelData.color !== "#0A84FF"
                        line.width: 3; line.color: modelData.color
                        path: (modelData && modelData.coordinates) ? modelData.coordinates : []
                    }
                }

                // Car: the same arrow as the big map (a single element: layers always together)
                MapQuickItem {
                    coordinate: QtPositioning.coordinate(root.carLat, root.carLon)
                    anchorPoint.x: 16; anchorPoint.y: 16
                    sourceItem: Item {
                        width: 32; height: 32
                        rotation: root.bearingRot - map.bearing
                        Image {
                            id: arrowImg
                            anchors.centerIn: parent
                            source: "qrc:/VoltaApp/icons/map-arrow.svg"
                            sourceSize.width: 20; sourceSize.height: 23
                            width: 20; height: 23
                            visible: Theme.lowPower
                        }
                        DropShadow {
            visible: !Theme.lowPower
                            anchors.fill: arrowImg
                            source: arrowImg
                            horizontalOffset: 0
                            verticalOffset: 2
                            radius: 6
                            samples: 13
                            color: "#4A000000"
                            transparentBorder: true
                        }
                    }
                }

                // Destination (if any)
                MapQuickItem {
                    visible: Nav.hasRoute
                    coordinate: Nav.destination
                    anchorPoint.x: 10; anchorPoint.y: 22
                    sourceItem: Image {
                        source: "qrc:/VoltaApp/icons/map-pin.svg"
                        sourceSize.width: 20; sourceSize.height: 22
                        width: 20; height: 22
                    }
                }
            }
        }
    }

    // Always-on tracking: the mini map has no user pan/zoom, it must
    // only show "where you are now"
    // Lat and lon change together: the map is moved only once (Qt.callLater
    // merges the two calls), before it was moved twice at every position.
    function _follow() { if (root.map) root.map.center = QtPositioning.coordinate(carLat, carLon) }
    onCarLatChanged: Qt.callLater(root._follow)
    onCarLonChanged: Qt.callLater(root._follow)

    // GPS: from the same receiver read in C++ (GpsService, "Gps") as the big map;
    // off when the mini map is hidden.
    // Same logic as the big map: position and arrow direction (including
    // sliding along the route) come from it, the mini map copies them without recomputing.
    Connections {
        target: root.source
        enabled: root._mirror
        ignoreUnknownSignals: true
        function onCarLatChanged() { root.carLat = root.source.carLat; root.gpsReceived = true }
        function onCarLonChanged() { root.carLon = root.source.carLon }
        function onBearingRotChanged() { root.bearingRot = root.source.bearingRot }
    }
    on_MirrorChanged: if (_mirror) {
        root.carLat = root.source.carLat; root.carLon = root.source.carLon
        root.bearingRot = root.source.bearingRot; root.gpsReceived = true
    }
    // Fake GPS (tests, file ~/.config/volta_fake_gps): the position comes from the big map
    Connections {
        target: root.source
        enabled: !!root.source && root.source.fakeGps && !root._mirror
        ignoreUnknownSignals: true
        function onFakeFix(lat, lon, bearing) {
            root.bearingRot = bearing
            root.carLat = lat
            root.carLon = lon
            root.gpsReceived = true
        }
    }
    Connections {
        target: Gps
        enabled: root.active && !root._mirror && !(root.source && root.source.fakeGps)
        function onUpdated(d) {
            try {
                if (!d.fix) return
                var speedKmh = (d.speed || 0) * 3.6

                if (root.gpsReceived) {
                    var dLat = (d.lat - root._lastFixLat) * 111320
                    var dLon = (d.lon - root._lastFixLon) * 111320
                              * Math.cos(d.lat * Math.PI / 180)
                    var moved = Math.sqrt(dLat * dLat + dLon * dLon)
                    var deadband = speedKmh < 2 ? 6.0 : 1.5
                    if (moved < deadband) return
                }
                root._lastFixLat = d.lat
                root._lastFixLon = d.lon

                if (speedKmh >= root.bearingMinSpeed && d.bearing !== undefined)
                    root.bearingRot = d.bearing

                // If Nav has road snapping, we trust that
                if (Nav.snapped) {
                    root.carLat = Nav.snappedPosition.latitude
                    root.carLon = Nav.snappedPosition.longitude
                    root.bearingRot = Nav.routeBearing
                } else {
                    root.carLat = d.lat
                    root.carLon = d.lon
                }
                root.gpsReceived = true
            } catch (e) { /* silenzio: la mini è secondaria */ }
        }
    }
    Behavior on bearingRot { enabled: !root._mirror; RotationAnimation { duration: 500; direction: RotationAnimation.Shortest } }

    // Mars (Toybox): covers the Earth mini-map
    Loader {
        anchors.fill: parent
        z: 1000
        active: root.marsMode
        visible: active
        sourceComponent: MarsMap {
            carLat: root.carLat
            carLon: root.carLon
            carBearing: root.bearingRot
            lightTheme: root.lightTheme
            interactive: false
            startZoom: 6
            roverSize: 34
            showLabel: false
        }
    }
}
