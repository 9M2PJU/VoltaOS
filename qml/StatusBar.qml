import QtQuick
import QtQuick.Effects
import QtCore as Core
import VoltaApp 1.0

// STATUS BAR — EV style, FIXED part on the right of the UI (above map/apps):
//   left   : lock (closed/open according to the car's lock)
//   center : time · weather icon + temperature (Open-Meteo, no key)
//   destra   : badge "Passenger airbag"
// The part in the car panel will be added later.
Item {
    id: statusBar
    height: 32

    property bool lightTheme: false
    readonly property color fg: lightTheme ? "#1D1D1F" : "#F2F2F2"

    // ── Data ──
    property bool   locked: true               // car lock state (to be connected to the sensor)
    property bool   showAirbag: true
    property bool   gpsOk: false               // receiver detected and with a position: white, otherwise red
    property real   latitude: 45.4642          // position for the weather (Main.qml updates it with the GPS)
    property real   longitude: 9.1900
    signal lockToggled()
    signal weatherTapped(real gx)

    // Meteo (Open-Meteo)
    property string temperature: ""            // es. "17°"
    property int    weatherCode: -1
    property bool   isDay: true
    property real   _wLat: 999
    property real   _wLon: 999

    function weatherIcon(code, day) {
        if (code < 0) return ""
        if (code === 0) return day ? "sunny" : "clear_night"
        if (code === 1 || code === 2) return day ? "partly_day" : "partly_night"
        if (code === 3) return "cloud"
        if (code === 45 || code === 48) return "foggy"
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "snow"
        if (code >= 95) return "thunder"
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return "rainy"
        return "cloud"
    }

    function refreshWeather() {
        var lat = statusBar.latitude, lon = statusBar.longitude
        var xhr = new XMLHttpRequest()
        xhr.timeout = 15000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    var c = JSON.parse(xhr.responseText).current
                    statusBar.temperature = Math.round(c.temperature_2m) + "°"
                    statusBar.weatherCode = c.weather_code
                    statusBar.isDay = c.is_day === 1
                    statusBar._wLat = lat; statusBar._wLon = lon
                    retryTimer.stop()
                    return
                } catch (e) {}
            }
            retryTimer.restart()          // offline / error: retry shortly
        }
        xhr.open("GET", "https://api.open-meteo.com/v1/forecast?latitude=" + lat.toFixed(3)
                        + "&longitude=" + lon.toFixed(3)
                        + "&current=temperature_2m,weather_code,is_day&timezone=auto")
        xhr.send()
    }
    Timer { interval: 600000; running: true; repeat: true; triggeredOnStart: true; onTriggered: statusBar.refreshWeather() }
    Timer { id: retryTimer; interval: 45000; repeat: false; onTriggered: statusBar.refreshWeather() }
    // Large movements (> ~0.2°) → weather of the new place
    onLatitudeChanged:  if (Math.abs(latitude - _wLat) > 0.2) refreshWeather()
    onLongitudeChanged: if (Math.abs(longitude - _wLon) > 0.2) refreshWeather()

    // Orologio
    property string timeText: ""
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            var d = new Date()
            statusBar.timeText = ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
        }
    }

    // Gradient veil at the top: keeps text and icons readable over the map
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: statusBar.lightTheme ? "#99FFFFFF" : "#99000000" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // ══ POSITION / SIZE OF THE INDIVIDUAL ICONS ══
    // Pressing and holding on the time opens the adjustment panel. dx/dy in px
    // (dx > 0 = right, dy > 0 = down), s = size (px; for time/degrees
    // it is the text size, for the airbag the width).
    readonly property var defaults: ({
        lock:  { dx: 0, dy: 0, s: 20 },
        time:  { dx: 0, dy: 0, s: 17 },
        wicon: { dx: 0, dy: 0, s: 24 },
        temp:  { dx: 0, dy: 0, s: 17 },
        air:   { dx: 0, dy: 0, s: 100 }
    })
    property var cfg: JSON.parse(JSON.stringify(defaults))
    Core.Settings { id: sbPrefs; category: "statusbarGeom"; property string layout: "" }
    Component.onCompleted: {
        try {
            var saved = JSON.parse(sbPrefs.layout || "{}")
            var c = JSON.parse(JSON.stringify(defaults))
            for (var k in c) if (saved[k]) for (var f in c[k]) if (saved[k][f] !== undefined) c[k][f] = saved[k][f]
            cfg = c
        } catch (e) {}
    }
    function setVal(key, field, v) {
        var c = JSON.parse(JSON.stringify(cfg))
        c[key][field] = Math.round(v)
        cfg = c
        sbPrefs.layout = JSON.stringify(c)
    }
    function resetGeom() { cfg = JSON.parse(JSON.stringify(defaults)); sbPrefs.layout = "" }
    property bool calOpen: false

    // ── Elements (absolute positions: each one moves on its own) ──
    // Lucchetto
    Item {
        id: lockBox
        x: 22 + cfg.lock.dx
        width: cfg.lock.s; height: cfg.lock.s
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: cfg.lock.dy
        Image {
            id: lockImg
            anchors.fill: parent
            source: "qrc:/VoltaApp/icons/sb_" + (statusBar.locked ? "lock" : "lock_open") + ".svg"
            sourceSize: Qt.size(cfg.lock.s * 3, cfg.lock.s * 3)
            fillMode: Image.PreserveAspectFit
            visible: false
        }
        MultiEffect { anchors.fill: lockImg; source: lockImg; colorization: 1.0; colorizationColor: statusBar.fg }
        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: statusBar.lockToggled() }
    }

    // Time (press and hold = adjustment panel)
    Text {
        id: timeLbl
        x: 70 + cfg.time.dx
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: cfg.time.dy
        text: statusBar.timeText
        color: statusBar.fg
        font.pixelSize: cfg.time.s; font.weight: Font.DemiBold
        MouseArea { anchors.fill: parent; anchors.margins: -8; onPressAndHold: statusBar.calOpen = !statusBar.calOpen }
    }

    // Weather icon (colored) + degrees
    Image {
        id: wxImg
        visible: statusBar.temperature !== "" && statusBar.weatherIcon(statusBar.weatherCode, statusBar.isDay) !== ""
        x: 140 + cfg.wicon.dx
        width: cfg.wicon.s; height: cfg.wicon.s
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: cfg.wicon.dy
        source: statusBar.weatherIcon(statusBar.weatherCode, statusBar.isDay) !== ""
                ? "qrc:/VoltaApp/icons/wx_" + statusBar.weatherIcon(statusBar.weatherCode, statusBar.isDay) + ".svg" : ""
        sourceSize: Qt.size(cfg.wicon.s * 3, cfg.wicon.s * 3)
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
    Text {
        id: tempLbl
        visible: statusBar.temperature !== ""
        x: 176 + cfg.temp.dx
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: cfg.temp.dy
        text: statusBar.temperature
        color: statusBar.fg
        font.pixelSize: cfg.temp.s; font.weight: Font.DemiBold
    }

    // Tap on weather icon + degrees: opens the weather popup (Main.qml)
    MouseArea {
        id: wxTap
        x: wxImg.x - 10
        width: (tempLbl.x + tempLbl.width) - wxImg.x + 20
        height: parent.height + 8
        anchors.verticalCenter: parent.verticalCenter
        enabled: statusBar.temperature !== ""
        onClicked: statusBar.weatherTapped(wxTap.mapToItem(null, 0, 0).x)
    }

    // Passenger airbag (a destra)
    Image {
        id: airImg
        visible: statusBar.showAirbag
        anchors.right: parent.right; anchors.rightMargin: 12 - cfg.air.dx
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: cfg.air.dy
        source: "qrc:/VoltaApp/icons/airbag.svg"
        sourceSize: Qt.size(cfg.air.s * 3, cfg.air.s * 3 * 36 / 124)
        width: cfg.air.s; height: cfg.air.s * 36 / 124
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    // GPS: after the weather degrees, always present like the weather (scrolls away with the map). White = working, red = no receiver / no position.
    Item {
        id: gpsIcon
        width: 22; height: 22
        x: (statusBar.temperature !== "" ? tempLbl.x + tempLbl.width : 140 + cfg.wicon.dx) + 18   // anchored on the left like time and weather: scrolls away with the map
        anchors.verticalCenter: parent.verticalCenter
        Image {
            id: gpsImg
            anchors.fill: parent
            source: "qrc:/VoltaApp/icons/gps.svg"
            sourceSize: Qt.size(66, 66)
            fillMode: Image.PreserveAspectFit
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: statusBar.gpsOk ? (statusBar.lightTheme ? "#1D1D1F" : "#FFFFFF") : "#FF3B30"
            }
        }
    }

    // ══ ADJUSTMENT PANEL ══
    Rectangle {
        id: calPanel
        visible: statusBar.calOpen
        z: 50
        x: Math.max(8, Math.min(parent.width - width - 8, 20)); y: statusBar.height + 6
        width: 520; height: calCol.height + 24
        radius: 8
        color: "#F2181818"; border.color: "#3A3A3A"; border.width: 1
        MouseArea { anchors.fill: parent; preventStealing: true }     // does not let touches through

        component Step: Rectangle {
            id: stp
            property string key: ""
            property string field: ""
            property int step: 1
            property int lo: -999
            property int hi: 999
            width: 126; height: 34; radius: 8
            color: "#2A2A2A"
            readonly property int val: statusBar.cfg[key][field]
            function bump(d) { statusBar.setVal(key, field, Math.max(lo, Math.min(hi, val + d))) }
            Timer { id: rep; interval: 70; repeat: true; onTriggered: stp.bump(rep.dir * stp.step); property int dir: 1 }
            Timer { id: rep0; interval: 350; onTriggered: rep.start() }
            Rectangle {
                x: 0; width: 38; height: parent.height; radius: 8; color: mL.pressed ? "#4A4A4A" : "transparent"
                Text { anchors.centerIn: parent; text: "−"; color: "#FFFFFF"; font.pixelSize: 20 }
                MouseArea { id: mL; anchors.fill: parent
                    onPressed: { stp.bump(-stp.step); rep.dir = -1; rep0.restart() }
                    onReleased: { rep0.stop(); rep.stop() } onCanceled: { rep0.stop(); rep.stop() } }
            }
            Text { anchors.centerIn: parent; text: stp.val; color: "#FFFFFF"; font.pixelSize: 15; font.weight: Font.Medium }
            Rectangle {
                x: parent.width - 38; width: 38; height: parent.height; radius: 8; color: mR.pressed ? "#4A4A4A" : "transparent"
                Text { anchors.centerIn: parent; text: "+"; color: "#FFFFFF"; font.pixelSize: 20 }
                MouseArea { id: mR; anchors.fill: parent
                    onPressed: { stp.bump(stp.step); rep.dir = 1; rep0.restart() }
                    onReleased: { rep0.stop(); rep.stop() } onCanceled: { rep0.stop(); rep.stop() } }
            }
        }

        Column {
            id: calCol
            x: 12; y: 12; width: parent.width - 24
            spacing: 8

            Row {
                spacing: 8
                Text { width: 100; text: qsTr("Icon"); color: "#8A8B8D"; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter; height: 16 }
                Text { width: 126; text: "X (←  →)"; color: "#8A8B8D"; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter }
                Text { width: 126; text: "Y (↑  ↓)"; color: "#8A8B8D"; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter }
                Text { width: 126; text: qsTr("Size"); color: "#8A8B8D"; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter }
            }
            Repeater {
                model: [ { k: "lock", n: qsTr("Lock"), lo: 8, hi: 60 },
                         { k: "time", n: qsTr("Time"), lo: 8, hi: 60 },
                         { k: "wicon", n: qsTr("Weather icon"), lo: 8, hi: 80 },
                         { k: "temp", n: qsTr("Degrees"), lo: 8, hi: 60 },
                         { k: "air", n: qsTr("Airbag"), lo: 30, hi: 260 } ]
                Row {
                    spacing: 8
                    Text { width: 100; height: 34; text: modelData.n; color: "#FFFFFF"; font.pixelSize: 14; verticalAlignment: Text.AlignVCenter }
                    Step { key: modelData.k; field: "dx" }
                    Step { key: modelData.k; field: "dy" }
                    Step { key: modelData.k; field: "s"; lo: modelData.lo; hi: modelData.hi }
                }
            }
            Row {
                spacing: 10
                Rectangle {
                    width: 90; height: 34; radius: 8; color: rst.pressed ? "#4A4A4A" : "#2A2A2A"
                    Text { anchors.centerIn: parent; text: qsTr("Reset"); color: "#FFFFFF"; font.pixelSize: 14 }
                    MouseArea { id: rst; anchors.fill: parent; onClicked: statusBar.resetGeom() }
                }
                Rectangle {
                    width: 90; height: 34; radius: 8; color: cls.pressed ? "#2563EB" : "#1667F2"
                    Text { anchors.centerIn: parent; text: qsTr("Close"); color: "#FFFFFF"; font.pixelSize: 14 }
                    MouseArea { id: cls; anchors.fill: parent; onClicked: statusBar.calOpen = false }
                }
                Text {
                    height: 34; verticalAlignment: Text.AlignVCenter
                    color: "#8A8B8D"; font.pixelSize: 11
                    text: "L " + cfg.lock.dx + "," + cfg.lock.dy + "," + cfg.lock.s
                        + " · O " + cfg.time.dx + "," + cfg.time.dy + "," + cfg.time.s
                        + " · M " + cfg.wicon.dx + "," + cfg.wicon.dy + "," + cfg.wicon.s
                        + " · G " + cfg.temp.dx + "," + cfg.temp.dy + "," + cfg.temp.s
                        + " · A " + cfg.air.dx + "," + cfg.air.dy + "," + cfg.air.s
                }
            }
        }
    }
}
