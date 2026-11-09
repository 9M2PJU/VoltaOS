import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Shapes
import VoltaApp 1.0

// ─────────────────────────────────────────────────────────────────────────────
//  BLUETOOTH — music from the phone, part of the single multimedia system
//  (MediaHub) insieme a YT Music e Spotify:
//   • header like YT Music / Spotify: unified search, app selector
//     musicali, coda unica;
//   • card of the connected device (+ the track playing) and
//     riquadro "Connetti telefono" → Impostazioni › Bluetooth;
//   • collegamenti alle altre app musicali.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root
    color: Theme.bg
    clip: true

    property bool lightTheme: false
    property bool active: false
    property var hub: null

    signal switchToApp(string appId)
    signal openBluetoothSettings()

    readonly property real headerH: 32 * ((Window.window && Window.window.uPx) ? Window.window.uPx : 1.12)   // fascia intestazioni: 32 px wireframe
    readonly property string iconColor: lightTheme ? "#555555" : "#A2A3A5"
    readonly property string dividerColor: lightTheme ? "#777777" : "#414141"
    readonly property string selectedTextColor: lightTheme ? "#444444" : Theme.textPrimary
    readonly property color tileColor: lightTheme ? "#EDEDED" : "#222222"
    readonly property color tilePressed: lightTheme ? "#E0E0E0" : "#2C2C2C"

    // View: "devices" | queue (playerVisible) | search (searchExpanded)
    property bool playerVisible: false
    property bool searchExpanded: false
    property bool appMenuOpen: false
    onActiveChanged: if (!active) { appMenuOpen = false }
    onSearchExpandedChanged: if (searchExpanded) Qt.callLater(function() { _uSearch.focusInput() })

    readonly property var musicApps: [
        { appId: "spotify",    name: "YT Music",  icon: "qrc:/VoltaApp/icons/ytmusic.svg" },
        { appId: "spotifyapp", name: "Spotify",   icon: "qrc:/VoltaApp/icons/spotify.svg" },
        { appId: "localmusic", name: qsTr("Music"), icon: "qrc:/VoltaApp/icons/localmusic.svg" },
        { appId: "podcast",    name: "Apple Podcast",   icon: "qrc:/VoltaApp/icons/podcast.svg" },
        { appId: "bluetooth",  name: "Bluetooth", icon: "qrc:/VoltaApp/icons/bluetooth.svg" }
    ]

    // Monochrome icon colored according to the theme
    component TintIcon: Image {
        id: _ti
        property color tint: root.iconColor
        fillMode: Image.PreserveAspectFit
        layer.enabled: true
        layer.effect: MultiEffect { colorization: 1.0; colorizationColor: _ti.tint }
    }

    // ── Device icons ──
    // Smartphone silhouette: the same as the map's phone-related button
    component PhoneGlyph: Item {
        id: _pg
        property color tint: root.iconColor
        width: 26; height: 26
        Rectangle {
            anchors.centerIn: parent
            width: 15; height: 25; radius: 4
            color: "transparent"
            border.width: 2; border.color: _pg.tint
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 3.5
                width: 4; height: 2; radius: 1
                color: _pg.tint
            }
        }
    }
    // Material icon (24x24 SVG path)
    component MdiIcon: Item {
        id: _mi
        property string path: ""
        property color tint: root.iconColor
        property real size: 26
        width: size; height: size
        Shape {
            width: 24; height: 24
            scale: _mi.size / 24
            transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: _mi.tint; strokeColor: "transparent"
                fillRule: ShapePath.WindingFill
                PathSvg { path: _mi.path }
            }
        }
    }
    readonly property var mdiPaths: ({
        "bluetooth": "M14.88 16.29 13 18.17v-3.76m0-8.58 1.88 1.88L13 9.58m4.71-1.87L12 2h-1v7.58L6.41 5 5 6.41 10.59 12 5 17.58 6.41 19 11 14.41V22h1l5.71-5.71-4.3-4.29z",
        "headphones": "M12 1c-5 0-9 4-9 9v7a3 3 0 0 0 3 3h3v-8H5v-2a7 7 0 0 1 7-7 7 7 0 0 1 7 7v2h-4v8h3a3 3 0 0 0 3-3v-7c0-5-4.03-9-9-9",
        "headset": "M12 1c-5 0-9 4-9 9v7a3 3 0 0 0 3 3h3v-8H5v-2a7 7 0 0 1 7-7 7 7 0 0 1 7 7v2h-4v8h4v1h-7v2h6a3 3 0 0 0 3-3V10c0-5-4.03-9-9-9",
        "gamepad": qsTr("M7 6h10a6 6 0 0 1 6 6 6 6 0 0 1-6 6c-1.78 0-3.37-.77-4.47-2h-1.06c-1.1 1.23-2.69 2-4.47 2a6 6 0 0 1-6-6 6 6 0 0 1 6-6M6 9v2H4v2h2v2h2v-2h2v-2H8V9zm9.5 3a1.5 1.5 0 0 0-1.5 1.5 1.5 1.5 0 0 0 1.5 1.5 1.5 1.5 0 0 0 1.5-1.5 1.5 1.5 0 0 0-1.5-1.5m3-3a1.5 1.5 0 0 0-1.5 1.5 1.5 1.5 0 0 0 1.5 1.5 1.5 1.5 0 0 0 1.5-1.5A1.5 1.5 0 0 0 18.5 9"),
        "keyboard": "M19 10h-2V8h2m0 5h-2v-2h2m-3-1h-2V8h2m0 5h-2v-2h2m0 6H8v-2h8m-9-5H5V8h2m0 5H5v-2h2m1 0h2v2H8m0-5h2v2H8m3 1h2v2h-2m0-5h2v2h-2m9-5H4c-1.11 0-2 .89-2 2v10a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2",
        "mouse": "M11 1.07C7.05 1.56 4 4.92 4 9h7m-7 6a8 8 0 0 0 8 8 8 8 0 0 0 8-8v-4H4m9-9.93V9h7c0-4.08-3.06-7.44-7-7.93",
        "speaker": "M12 12a3 3 0 0 0-3 3 3 3 0 0 0 3 3 3 3 0 0 0 3-3 3 3 0 0 0-3-3m0 8a5 5 0 0 1-5-5 5 5 0 0 1 5-5 5 5 0 0 1 5 5 5 5 0 0 1-5 5m0-16a2 2 0 0 1 2 2 2 2 0 0 1-2 2 2 2 0 0 1-2-2c0-1.11.89-2 2-2m5-2H7c-1.11 0-2 .89-2 2v16a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2",
        "laptop": "M4 6h16v10H4m16 2a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2H4c-1.11 0-2 .89-2 2v10a2 2 0 0 0 2 2H0v2h24v-2z",
        "monitor": "M21 16H3V4h18m0-2H3c-1.11 0-2 .89-2 2v12a2 2 0 0 0 2 2h7v2H8v2h8v-2h-2v-2h7a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2",
        "tablet": "M19 18H5V6h14m2-2H3c-1.11 0-2 .89-2 2v12a2 2 0 0 0 2 2h18a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2",
        "watch": "M6 12a6 6 0 0 1 6-6 6 6 0 0 1 6 6 6 6 0 0 1-6 6 6 6 0 0 1-6-6m14 0a7.94 7.94 0 0 0-3.05-6.27L16 0H8l-.95 5.73A7.94 7.94 0 0 0 4 12c0 2.54 1.19 4.81 3.05 6.27L8 24h8l.95-5.73A7.96 7.96 0 0 0 20 12",
        "earbuds": qsTr("M5 3C3 3 2 5 2 6v5c0 1 1 3 3 3 .61 0 1.32-.28 2-.73V20c0 .55.45 1 1 1h1c.55 0 1-.45 1-1V8c0-2-3-5-5-5m3 7.23L5.91 11.6c-.51.33-.83.4-.91.4-.7 0-1-.92-1-1V6.03C4 5.92 4.3 5 5 5c.9 0 3 2.1 3 3zM16.5 15c.7 0 1.37-.11 2-.32V20c0 .55-.45 1-1 1h-2c-.55 0-1-.45-1-1v-5.32c.63.21 1.3.32 2 .32m0-12C13.46 3 11 5.46 11 8.5s2.46 5.5 5.5 5.5S22 11.54 22 8.5 19.54 3 16.5 3m0 9c-1.93 0-3.5-1.57-3.5-3.5S14.57 5 16.5 5 20 6.57 20 8.5 18.43 12 16.5 12"),
        "car": qsTr("M5 14h14l-1.5-4.5h-11zm12.5 5a1.5 1.5 0 0 0 1.5-1.5 1.5 1.5 0 0 0-1.5-1.5 1.5 1.5 0 0 0-1.5 1.5 1.5 1.5 0 0 0 1.5 1.5m-11 0A1.5 1.5 0 0 0 8 17.5 1.5 1.5 0 0 0 6.5 16 1.5 1.5 0 0 0 5 17.5 1.5 1.5 0 0 0 6.5 19M18.92 9 21 15v8a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1v-1H6v1a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-8l2.08-6c.2-.58.77-1 1.42-1h11c.65 0 1.22.42 1.42 1M12 0c2.12 0 4.15.86 5.65 2.35l-1.42 1.42A6.02 6.02 0 0 0 12 2c-1.58 0-3.11.65-4.23 1.77L6.36 2.35A8 8 0 0 1 12 0m0 4c1.06 0 2.07.44 2.82 1.18L13.4 6.6c-.37-.37-.87-.6-1.4-.6-.5 0-1.03.23-1.4.6L9.18 5.18C9.93 4.44 10.94 4 12 4"),
        "printer": "M18 3H6v4h12m1 5a1 1 0 0 1-1-1 1 1 0 0 1 1-1 1 1 0 0 1 1 1 1 1 0 0 1-1 1m-3 7H8v-5h8m3-6H5a3 3 0 0 0-3 3v6h4v4h12v-4h4v-6a3 3 0 0 0-3-3",
        "microphone": "M12 2a3 3 0 0 1 3 3v6a3 3 0 0 1-3 3 3 3 0 0 1-3-3V5a3 3 0 0 1 3-3m7 9c0 3.53-2.61 6.44-6 6.93V21h-2v-3.07c-3.39-.49-6-3.4-6-6.93h2a5 5 0 0 0 5 5 5 5 0 0 0 5-5z"
    })
    function mdiPath(kind) { return mdiPaths[kind] || mdiPaths["bluetooth"] }
    // Device type from the BlueZ icon, and if missing from the name
    function devKind(d) {
        var ic = String((d && d.icon) || "").toLowerCase()
        var nm = String((d && d.name) || "").toLowerCase()
        if (ic === "phone") return "phone"
        if (ic.indexOf("gaming") >= 0 || /controller|gamepad|joypad|xbox|dualsense|dualshock|playstation|joy-con/.test(nm)) return "gamepad"
        if (ic.indexOf("keyboard") >= 0 || /keyboard|tastiera/.test(nm)) return "keyboard"
        if (ic.indexOf("mouse") >= 0 || /mouse/.test(nm)) return "mouse"
        if (/buds|airpods|earbuds|auricolari/.test(nm)) return "earbuds"
        if (ic.indexOf("headphones") >= 0 || /headphone|cuffie/.test(nm)) return "headphones"
        if (ic.indexOf("headset") >= 0) return "headset"
        if (ic.indexOf("speaker") >= 0 || ic === "audio-card" || /speaker|soundbar|boombox|altoparlante/.test(nm)) return "speaker"
        if (/watch|smartband/.test(nm)) return "watch"
        if (ic === "computer" || /laptop|notebook|macbook/.test(nm)) return "laptop"
        if (ic.indexOf("tablet") >= 0 || /ipad|tablet/.test(nm)) return "tablet"
        if (ic === "video-display" || /\btv\b/.test(nm)) return "monitor"
        if (ic === "printer") return "printer"
        if (ic.indexOf("microphone") >= 0 || /\bmic\b/.test(nm)) return "microphone"
        if (/\bcar\b|\bauto\b/.test(nm)) return "car"
        if (ic === "") return "phone"      // BlueZ without an icon: as in the rest of the app, it is the phone
        return "bluetooth"
    }

    // ════════ HEADER (same structure as YT Music / Spotify) ════════
    Rectangle {
        id: _hdr; width: parent.width; height: root.headerH; z: 100
        color: Theme.bg

        Row {
            anchors.left: parent.left; anchors.leftMargin: 20; anchors.verticalCenter: parent.verticalCenter
            spacing: 18

            // 1. Selettore app musicali
            Item {
                width: _swRow.width; height: 34
                anchors.verticalCenter: parent.verticalCenter
                Row {
                    id: _swRow
                    spacing: 7
                    anchors.verticalCenter: parent.verticalCenter
                    Image { sourceSize: Qt.size(width * 2, height * 2);
                        source: "qrc:/VoltaApp/icons/bluetooth.svg"
                        width: 29; height: 29; fillMode: Image.PreserveAspectFit
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.appMenuOpen = !root.appMenuOpen }
            }

            Rectangle { width: 1; height: 21; color: root.dividerColor; anchors.verticalCenter: parent.verticalCenter }

            // 2. Unified search
            Item {
                width: 27; height: 27; anchors.verticalCenter: parent.verticalCenter
                TintIcon { source: "qrc:/VoltaApp/icons/Icons_search_black.svg"; anchors.fill: parent; tint: root.lightTheme ? "#141414" : "#FFFFFF" }
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: { root.searchExpanded = true; root.playerVisible = false } }
            }

            Rectangle { width: 1; height: 21; color: root.dividerColor; anchors.verticalCenter: parent.verticalCenter }

            // 3. Coda unica
            Item {
                width: 27; height: 27; anchors.verticalCenter: parent.verticalCenter
                Canvas {
                    id: _qIcon
                    anchors.centerIn: parent; width: 22; height: 19.5
                    property color col: root.iconColor
                    onColChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d"); c.clearRect(0, 0, width, height)
                        var k = width / 178
                        c.save(); c.scale(k, k); c.translate(-19, -53)
                        c.fillStyle = col; c.strokeStyle = col; c.lineWidth = 10; c.lineJoin = "round"; c.lineCap = "round"
                        c.beginPath(); c.moveTo(29, 58); c.lineTo(63, 78); c.lineTo(29, 98); c.closePath(); c.fill(); c.stroke()
                        c.beginPath(); c.roundedRect(84, 66, 108, 24, 12, 12); c.fill()
                        c.beginPath(); c.roundedRect(24, 122, 168, 24, 12, 12); c.fill()
                        c.beginPath(); c.roundedRect(24, 182, 168, 24, 12, 12); c.fill()
                        c.restore()
                    }
                }
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: { root.playerVisible = true; root.searchExpanded = false } }
            }

            Rectangle { width: 1; height: 21; color: root.dividerColor; anchors.verticalCenter: parent.verticalCenter }

            // Tabs
            Item {
                width: _tDev.implicitWidth; height: 44
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    id: _tDev; anchors.centerIn: parent; text: qsTr("Devices")
                    color: !root.playerVisible && !root.searchExpanded ? root.selectedTextColor : root.iconColor
                    font.pixelSize: 20; font.weight: Font.DemiBold
                }
                MouseArea { anchors.fill: parent; onClicked: { root.playerVisible = false; root.searchExpanded = false } }
            }
        }
    }

    // ── Menu a tendina app musicali ──
    MouseArea {
        anchors.fill: parent; z: 150
        visible: root.appMenuOpen
        onClicked: root.appMenuOpen = false
    }
    Rectangle {
        z: 160
        visible: root.appMenuOpen
        x: 14; y: root.headerH - 10
        width: 220; height: _menuCol.height + 12
        radius: 10
        color: root.lightTheme ? "#FFFFFF" : "#2A2A2A"
        border.width: 1; border.color: Theme.border
        Column {
            id: _menuCol
            y: 6; width: parent.width
            Repeater {
                model: root.musicApps
                Rectangle {
                    width: _menuCol.width; height: 48
                    color: _mMA.pressed ? Theme.surfaceElevated : "transparent"
                    Row {
                        anchors.left: parent.left; anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        Image { sourceSize: Qt.size(width * 2, height * 2); source: modelData.icon; width: 24; height: 24; fillMode: Image.PreserveAspectFit; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: modelData.name; color: root.selectedTextColor; font.pixelSize: 16
                            font.weight: modelData.appId === "bluetooth" ? Font.DemiBold : Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        id: _mMA
                        anchors.fill: parent
                        onClicked: {
                            root.appMenuOpen = false
                            if (modelData.appId !== "bluetooth") root.switchToApp(modelData.appId)
                        }
                    }
                }
            }
        }
    }

    // ════════ VISTA DISPOSITIVI ════════
    Flickable {
        anchors.fill: parent
        anchors.topMargin: root.headerH
        visible: !root.playerVisible && !root.searchExpanded
        contentHeight: _devCol.height + 60
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: _devCol
            x: 40; y: 16
            width: parent.width - 80
            spacing: 34

            // ── Riquadri dispositivi ──
            Flow {
                width: parent.width
                spacing: 20

                // One card for each connected device: informational only (not clickable)
                Repeater {
                    model: root.hub ? root.hub.connectedDevices : []
                    Rectangle {
                        id: _devTile
                        width: 300; height: 160; radius: 8
                        color: root.tileColor

                        PhoneGlyph { x: 22; y: 22; visible: root.devKind(modelData) === "phone" }
                        MdiIcon {
                            x: 22; y: 22; size: 26
                            visible: root.devKind(modelData) !== "phone"
                            path: root.mdiPath(root.devKind(modelData))
                        }
                        // spunta «connesso»
                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 20; y: 20
                            width: 24; height: 24; radius: 12
                            color: root.lightTheme ? "#444444" : "#E6E6E6"
                            Canvas {
                                anchors.fill: parent
                                property color col: root.tileColor
                                onColChanged: requestPaint()
                                onPaint: {
                                    var c = getContext("2d"); c.clearRect(0, 0, width, height)
                                    c.strokeStyle = col; c.lineWidth = 2.2; c.lineCap = "round"; c.lineJoin = "round"
                                    c.beginPath(); c.moveTo(7, 12.5); c.lineTo(10.5, 16); c.lineTo(17, 8.5); c.stroke()
                                }
                            }
                        }
                        Column {
                            x: 22; anchors.bottom: parent.bottom; anchors.bottomMargin: 20
                            width: parent.width - 44; spacing: 4
                            Text {
                                text: modelData.name; color: Theme.textPrimary
                                font.pixelSize: 17; font.weight: Font.Medium
                                width: parent.width; elide: Text.ElideRight
                            }
                            Text {
                                text: qsTr("Connected")
                                color: Theme.textSecondary
                                font.pixelSize: 13; width: parent.width; elide: Text.ElideRight
                            }
                        }
                    }
                }

                // Connetti telefono
                Rectangle {
                    width: 300; height: 160; radius: 8
                    color: _cMA.pressed ? root.tilePressed : root.tileColor
                    MdiIcon { x: 22; y: 22; size: 26; path: root.mdiPath("bluetooth") }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 22; y: 14
                        text: "+"; color: root.iconColor; font.pixelSize: 30; font.weight: Font.Light
                    }
                    Text {
                        x: 22; anchors.bottom: parent.bottom; anchors.bottomMargin: 20
                        text: root.hub && root.hub.connectedDevices.length > 0 ? qsTr("Connect another device") : qsTr("Connect phone")
                        color: Theme.textPrimary; font.pixelSize: 17; font.weight: Font.Medium
                    }
                    MouseArea { id: _cMA; anchors.fill: parent; onClicked: root.openBluetoothSettings() }
                }
            }

            // ── Altre app musicali ──
            Column {
                width: parent.width; spacing: 6
                Text { text: qsTr("Or play directly from these apps"); color: Theme.textPrimary; font.pixelSize: 17; font.weight: Font.Medium }
                Text {
                    text: qsTr("Listen to music from the car's apps instead of streaming from the phone")
                    color: Theme.textSecondary; font.pixelSize: 13
                    width: parent.width; wrapMode: Text.WordWrap
                }
            }

            Flow {
                width: parent.width
                spacing: 20
                Repeater {
                    model: [ { appId: "spotifyapp", name: "Spotify",  icon: "qrc:/VoltaApp/icons/spotify.svg" },
                             { appId: "spotify",    name: "YT Music", icon: "qrc:/VoltaApp/icons/ytmusic.svg" },
                             { appId: "localmusic", name: qsTr("Music"), icon: "qrc:/VoltaApp/icons/localmusic.svg" },
                             { appId: "podcast",    name: "Apple Podcast", icon: "qrc:/VoltaApp/icons/podcast.svg" } ]
                    Rectangle {
                        width: 300; height: 72; radius: 8
                        color: _aMA.pressed ? root.tilePressed : root.tileColor
                        Row {
                            x: 22; anchors.verticalCenter: parent.verticalCenter; spacing: 14
                            Image { sourceSize: Qt.size(width * 2, height * 2); source: modelData.icon; width: 24; height: 24; fillMode: Image.PreserveAspectFit; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.name; color: Theme.textPrimary; font.pixelSize: 16; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { id: _aMA; anchors.fill: parent; onClicked: root.switchToApp(modelData.appId) }
                    }
                }
            }
        }
    }

    // ════════ CODA UNICA ════════
    MediaQueuePanel {
        anchors.fill: parent; z: 80
        hub: root.hub
        lightTheme: root.lightTheme
        topPadding: root.headerH
        visible: root.playerVisible && root.hub !== null
    }

    // ════════ UNIFIED SEARCH ════════
    MediaSearchPanel {
        id: _uSearch
        defaultFilter: "ytmusic"   // dl58
        anchors.fill: parent; z: 110
        hub: root.hub
        lightTheme: root.lightTheme
        headerH: root.headerH
        visible: root.searchExpanded && root.hub !== null
        onClosed: root.searchExpanded = false
    }
}
