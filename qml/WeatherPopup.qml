import QtQuick

// WEATHER POPUP — opens by tapping the degrees in the top bar (EV style).
// Layout derived from the reference photo (panel 400 x 602 "units", then
// scaled as a block: k = width / 400). Data: Open-Meteo (no key) +
// Open-Meteo air quality + place name (BigDataCloud, no key).
// Offline: shows the last data received (or dashes) without errors.
Item {
    id: pop

    // ── Da collegare in Main.qml ──
    property bool open: false
    property bool lightTheme: false
    property real latitude: 45.4642
    property real longitude: 9.1900
    property real uPx: 1.5            // 1 px of the wireframe (Main.qml: root.uPx)
    property real anchorX: 0          // x (scene) from which the panel starts: the degrees area
    property real topY: 40            // y (scene) of the panel's top edge

    // ── Data ──
    property bool   hasData: false
    property string place: ""
    property int    temp: 0
    property int    hi: 0
    property int    lo: 0
    property int    code: -1
    property bool   isDay: true
    property var    hours: []         // [{h:"17:00", t:21, code:0, day:true}, ...]
    property string rain: "—"
    property string humidity: "—"
    property string wind: "—"
    property string uv: "—"
    property string aqi: "—"
    property string updatedText: ""
    property real   _fetchedAt: 0
    property real   _lat0: 999
    property real   _lon0: 999
    property real   _geoLat: 999
    property real   _geoLon: 999

    anchors.fill: parent
    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // ── Colori ──
    // UI colors: like the mini player (dark gray #262626 / light gray #F2F2F2)
    readonly property color cardBg:  lightTheme ? "#F2F2F2" : "#262626"
    readonly property color fg:      lightTheme ? "#171717" : "#FFFFFF"
    readonly property color fgDim:   lightTheme ? "#757575" : "#A2A3A5"
    readonly property color fgFaint: lightTheme ? "#757575" : "#A2A3A5"
    readonly property color line:    lightTheme ? "#D0D1D2" : "#26FFFFFF"

    function weatherIcon(c, day) {
        if (c < 0) return ""
        if (c === 0) return day ? "sunny" : "clear_night"
        if (c === 1 || c === 2) return day ? "partly_day" : "partly_night"
        if (c === 3) return "cloud"
        if (c === 45 || c === 48) return "foggy"
        if ((c >= 71 && c <= 77) || c === 85 || c === 86) return "snow"
        if (c >= 95) return "thunder"
        if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) return "rainy"
        return "cloud"
    }
    function weatherText(c) {
        if (c < 0) return ""
        if (c === 0) return qsTr("Clear sky")
        if (c === 1) return qsTr("Mostly clear")
        if (c === 2) return qsTr("Partly cloudy")
        if (c === 3) return qsTr("Overcast")
        if (c === 45 || c === 48) return qsTr("Fog")
        if (c >= 51 && c <= 57) return qsTr("Drizzle")
        if (c >= 61 && c <= 67) return qsTr("Rain")
        if (c >= 71 && c <= 77) return qsTr("Snow")
        if (c >= 80 && c <= 82) return qsTr("Showers")
        if (c === 85 || c === 86) return qsTr("Snow")
        if (c >= 95) return qsTr("Thunderstorm")
        return qsTr("Cloudy")
    }
    function aqiText(v) {
        if (v <= 50)  return qsTr("Good")
        if (v <= 100) return qsTr("Moderate")
        if (v <= 200) return qsTr("Unhealthy")
        if (v <= 300) return qsTr("Very unhealthy")
        return qsTr("Hazardous")
    }
    function windDirText(deg) {
        var d = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        return d[Math.round(((deg % 360) + 360) % 360 / 45) % 8]
    }
    function two(n) { return ("0" + n).slice(-2) }
    function stamp() {
        var m = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]
        var d = new Date()
        return d.getDate() + " " + m[d.getMonth()] + ", " + two(d.getHours()) + ":" + two(d.getMinutes())
    }

    // ── Rete ──
    function getJson(url, ok) {
        var xhr = new XMLHttpRequest()
        xhr.timeout = 15000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return
            try { ok(JSON.parse(xhr.responseText)) } catch (e) { console.log("[Weather] invalid response:", e) }
        }
        xhr.open("GET", url)
        xhr.send()
    }
    function refresh() {
        var lat = pop.latitude, lon = pop.longitude
        var q = "latitude=" + lat.toFixed(3) + "&longitude=" + lon.toFixed(3)
        getJson("https://api.open-meteo.com/v1/forecast?" + q
            + "&current=temperature_2m,relative_humidity_2m,weather_code,is_day,wind_speed_10m,wind_direction_10m"
            + "&hourly=temperature_2m,weather_code,is_day,precipitation_probability,uv_index"
            + "&daily=temperature_2m_max,temperature_2m_min&forecast_days=2&timezone=auto",
            function(j) {
                var c = j.current
                pop.temp = Math.round(c.temperature_2m)
                pop.code = c.weather_code
                pop.isDay = c.is_day === 1
                pop.humidity = Math.round(c.relative_humidity_2m) + "%"
                pop.wind = pop.windDirText(c.wind_direction_10m) + " " + Math.round(c.wind_speed_10m) + " km/h"
                if (j.daily && j.daily.temperature_2m_max) {
                    pop.hi = Math.round(j.daily.temperature_2m_max[0])
                    pop.lo = Math.round(j.daily.temperature_2m_min[0])
                }
                var H = j.hourly, now = String(c.time).slice(0, 13), idx = -1
                for (var i = 0; i < H.time.length; i++) if (String(H.time[i]).slice(0, 13) === now) { idx = i; break }
                if (idx < 0) idx = 0
                var pp = H.precipitation_probability ? H.precipitation_probability[idx] : null
                pop.rain = (pp === null || pp === undefined) ? "—" : Math.round(pp) + "%"
                var uvv = H.uv_index ? H.uv_index[idx] : null
                pop.uv = (uvv === null || uvv === undefined) ? "—" : String(Math.round(uvv))
                var list = []
                for (var k = idx + 1; k < H.time.length && list.length < 24; k++)
                    list.push({ h: String(H.time[k]).slice(11, 16), t: Math.round(H.temperature_2m[k]),
                                code: H.weather_code[k], day: H.is_day[k] === 1 })
                pop.hours = list
                pop.hasData = true
                pop.updatedText = pop.stamp()
                pop._fetchedAt = Date.now()
                pop._lat0 = lat; pop._lon0 = lon
            })
        getJson("https://air-quality-api.open-meteo.com/v1/air-quality?" + q + "&current=us_aqi&timezone=auto",
            function(j) {
                var v = j.current ? j.current.us_aqi : null
                pop.aqi = (v === null || v === undefined) ? "—" : pop.aqiText(v) + " • " + Math.round(v)
            })
        if (Math.abs(lat - pop._geoLat) > 0.05 || Math.abs(lon - pop._geoLon) > 0.05 || pop.place === "") {
            getJson("https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=" + lat.toFixed(4)
                    + "&longitude=" + lon.toFixed(4) + "&localityLanguage=it",
                function(j) {
                    var city = j.city || j.locality || ""
                    var sub = j.principalSubdivision || ""
                    var cd = j.principalSubdivisionCode || ""
                    if (cd.indexOf("US-") === 0) sub = cd.slice(3)
                    pop.place = city ? (sub && sub !== city ? city + ", " + sub : city) : (sub || "")
                    pop._geoLat = lat; pop._geoLon = lon
                })
        }
    }
    onOpenChanged: {
        if (open && (Date.now() - _fetchedAt > 120000 || Math.abs(latitude - _lat0) > 0.05 || Math.abs(longitude - _lon0) > 0.05))
            refresh()
        if (open) hourFlick.contentX = 0
    }
    Timer { interval: 600000; running: pop.open; repeat: true; onTriggered: pop.refresh() }

    // ── Darkened background: the whole UI behind the panel dims.
    //    Absorbs touches (does not close): the popup closes ONLY with the X. ──
    Rectangle {
        anchors.fill: parent
        color: "#A6000000"
        MouseArea {
            anchors.fill: parent
            enabled: pop.open
            hoverEnabled: true
            preventStealing: true              // the map underneath cannot "steal" the drag
            acceptedButtons: Qt.AllButtons
            onWheel: function(w) { w.accepted = true }
        }
    }

    // ══════════ Panel ══════════
    Rectangle {
        id: card
        readonly property real k: width / 400
        width: Math.round(300 * pop.uPx)
        height: Math.round(602 * k)
        x: Math.max(8, Math.min(pop.width - width - 8, pop.anchorX - 24 * k))
        y: Math.round((pop.height - height) / 2)          // centrato in verticale
        radius: 6 * pop.uPx                               // same radius as the mini player
        clip: true
        color: pop.cardBg
        scale: pop.open ? 1.0 : 0.96
        transformOrigin: Item.Center
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        // prevents touches on the panel from reaching the "outside" area
        MouseArea { anchors.fill: parent; preventStealing: true; hoverEnabled: true; acceptedButtons: Qt.AllButtons }

        // ── Intestazione: X · luogo ──
        Item {
            id: closeBtn
            x: 6 * card.k; y: 8 * card.k
            width: 44 * card.k; height: 44 * card.k
            Rectangle { anchors.centerIn: parent; width: 19 * card.k; height: 2.4 * card.k; radius: height / 2; rotation: 45;  color: pop.fg }
            Rectangle { anchors.centerIn: parent; width: 19 * card.k; height: 2.4 * card.k; radius: height / 2; rotation: -45; color: pop.fg }
            MouseArea { anchors.fill: parent; onClicked: pop.open = false }
        }
        Text {
            x: 56 * card.k; width: card.width - 112 * card.k
            y: 33 * card.k - height / 2
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: pop.place !== "" ? pop.place : qsTr("Current location")
            color: pop.fg
            font.pixelSize: Math.round(21 * card.k); font.weight: Font.Medium
        }
        Rectangle { y: 67 * card.k; width: parent.width; height: 1; color: pop.line }

        // ── Temperatura grande ──
        Text {
            x: 26 * card.k; y: 108 * card.k
            text: pop.hasData ? pop.temp + "°" : "—"
            color: pop.fg
            font.pixelSize: Math.round(54 * card.k); font.weight: Font.Medium
        }
        Text {
            x: 28 * card.k; y: 163 * card.k
            text: qsTr("Outside temp.")
            color: pop.fg
            font.pixelSize: Math.round(11.5 * card.k); font.weight: Font.Medium
        }

        // ── Condition + max/min + icon ──
        Column {
            id: condCol
            spacing: 3 * card.k
            x: 290 * card.k - width
            y: 104 * card.k
            Text {
                anchors.right: parent.right
                text: pop.hasData ? pop.weatherText(pop.code) : ""
                color: pop.fg
                font.pixelSize: Math.round(21 * card.k); font.weight: Font.Medium
            }
            Text {
                anchors.right: parent.right
                visible: pop.hasData
                text: "↑" + pop.hi + "° ↓" + pop.lo + "°"
                color: pop.fg
                font.pixelSize: Math.round(19 * card.k); font.weight: Font.Medium
            }
        }
        Image {
            x: 308 * card.k; y: 100 * card.k
            width: 57 * card.k; height: 57 * card.k
            visible: pop.hasData && pop.weatherIcon(pop.code, pop.isDay) !== ""
            source: pop.weatherIcon(pop.code, pop.isDay) !== "" ? "qrc:/VoltaApp/icons/wx_" + pop.weatherIcon(pop.code, pop.isDay) + ".svg" : ""
            sourceSize: Qt.size(width * 2, height * 2)
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        // ── Previsione oraria (scorre in orizzontale) ──
        Rectangle {
            id: hourBox
            x: 28 * card.k; y: 188 * card.k
            width: card.width - 58 * card.k; height: 142 * card.k
            color: pop.lightTheme ? "#E0E0E0" : "#14FFFFFF"
            radius: 4 * card.k
            clip: true
            Flickable {
                id: hourFlick
                objectName: "hourFlick"
                anchors.fill: parent
                contentWidth: hourRow.width; contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                // mouse wheel: scrolls the hours
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: function(ev) {
                        var d = ev.angleDelta.x !== 0 ? ev.angleDelta.x : ev.angleDelta.y
                        hourFlick.contentX = Math.max(0, Math.min(hourFlick.contentWidth - hourFlick.width, hourFlick.contentX - d))
                    }
                }
                Row {
                    id: hourRow
                    Repeater {
                        model: pop.hours
                        delegate: Item {
                            required property var modelData
                            width: 79 * card.k; height: hourBox.height
                            Image {
                                x: (parent.width - width) / 2; y: 21 * card.k
                                width: 32 * card.k; height: 32 * card.k
                                source: pop.weatherIcon(modelData.code, modelData.day) !== "" ? "qrc:/VoltaApp/icons/wx_" + pop.weatherIcon(modelData.code, modelData.day) + ".svg" : ""
                                sourceSize: Qt.size(width * 2, height * 2)
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                            Text {
                                width: parent.width; y: 70 * card.k
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.t + "°"
                                color: pop.fg
                                font.pixelSize: Math.round(19 * card.k); font.weight: Font.Medium
                            }
                            Text {
                                width: parent.width; y: 99 * card.k
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.h
                                color: pop.fg
                                font.pixelSize: Math.round(19 * card.k); font.weight: Font.Medium
                            }
                        }
                    }
                }
            }
        }

        // ── Detail rows ──
        Repeater {
            model: [
                { l: qsTr("Chance of rain"), v: pop.rain },
                { l: qsTr("Humidity"),                v: pop.humidity },
                { l: qsTr("Wind"),                  v: pop.wind },
                { l: qsTr("UV index"),              v: pop.uv },
                { l: "AQI",                    v: pop.aqi }
            ]
            delegate: Item {
                required property var modelData
                required property int index
                x: 28 * card.k; width: card.width - 58 * card.k
                y: (356 + index * 39.7) * card.k - height / 2
                height: 30 * card.k
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.l
                    color: pop.fg
                    font.pixelSize: Math.round(19 * card.k); font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: modelData.v
                    color: pop.fg
                    font.pixelSize: Math.round(19 * card.k); font.weight: Font.Medium
                }
            }
        }

        // ── Ultimo aggiornamento ──
        Text {
            width: parent.width; y: 568 * card.k - height / 2
            horizontalAlignment: Text.AlignHCenter
            text: pop.updatedText !== "" ? qsTr("Last updated ") + pop.updatedText : qsTr("No data (offline?)")
            color: pop.fgFaint
            font.pixelSize: Math.round(10.5 * card.k)
        }
    }
}
