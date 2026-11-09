import QtQuick
import QtQuick.Window
import QtQuick.Effects
import VoltaApp 1.0
import QtQuick.Controls

// MAP WIDGET — connected to the Vite (React) map.
//  • Search  → opens the map and its search
//  • Home / Work → navigates directly (route preview on the map)
//  • Active trip → the widget becomes the trip card (ETA, minutes, km)
Item {
    property bool lightTheme: Window.window.lightTheme
    id: root
    // Scale relative to the original design (250 x 122): Main sets it so that
    // the height always matches the miniplayer's (baseH)
    property real s: 1
    // corner radius = that of the miniplayer (6 wireframe px, k = s * 1.22)
    readonly property real cornerR: 10
    width: 250 * s
    height: 122 * s

    // Background for the "glass" blur (see MusicWidget): set by Main.qml
    property Item blurSource: null
    property rect blurRect: Qt.rect(0, 0, 0, 0)

    // Reference to the MapLibre map (set by Main.qml)
    property var mapLibre: null
    // Request to open the map view (handled by Main.qml)
    signal openMap()

    // The map becomes visible with an animation: we give focus to the search
    // only when it is already on screen, otherwise the keyboard/cursor does not appear.
    Timer {
        id: focusSearchTimer
        interval: 400
        onTriggered: if (root.mapLibre) root.mapLibre.focusSearch()
    }

    Timer {
        id: tripMenuTimer
        interval: 400
        onTriggered: if (root.mapLibre) root.mapLibre.openTripMenu()
    }

    Timer {
        id: stopSearchTimer
        interval: 400
        onTriggered: if (root.mapLibre) root.mapLibre.beginAddStop()
    }

    function openSearch() {
        root.openMap()
        focusSearchTimer.restart()
    }

    // Home/Work use the places saved on the map (place card →
    // "Set as Home/Work"). If not yet set, the
    // search opens to choose them.
    function navigateHome() {
        root.openMap()
        if (root.mapLibre && root.mapLibre.homePlace) root.mapLibre.navigateHome()
        else focusSearchTimer.restart()
    }
    function navigateWork() {
        root.openMap()
        if (root.mapLibre && root.mapLibre.workPlace) root.mapLibre.navigateWork()
        else focusSearchTimer.restart()
    }

    // dl73: recent destinations (the same as the native map's search), max 12
    readonly property var recentDestinations: (root.mapLibre && root.mapLibre.recentSearches) ? root.mapLibre.recentSearches.slice(0, 12) : []
    function openRecent(p) {
        if (!p) return
        root.openMap()
        if (root.mapLibre && root.mapLibre.openPlaceDetails)
            root.mapLibre.openPlaceDetails(p.lat, p.lon, p.name, p.address, { isBusiness: p.isBusiness, category: p.category, phone: p.phone, website: p.website })
    }

    function _fmtKm(m) {
        return m >= 1000 ? (Math.round(m / 100) / 10) + " km" : Math.round(m) + " m"
    }

    // ── Trip state: real-time data from the navigator ──────────────────
    readonly property bool   tripActive: Nav.navigating
    readonly property string tripName: Nav.destinationName
    readonly property string tripEta:  Nav.arrivalTime !== "" ? Nav.arrivalTime : "--:--"
    readonly property real   tripPct: Math.max(0, Math.min(1, Nav.progress))

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: root.cornerR
        border.width: 0
        clip: true

        // Very light shadow, same treatment as the music widget.
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.8
            shadowColor: "#20000000"
            shadowVerticalOffset: 4
            shadowHorizontalOffset: 0
            paddingRect: Qt.rect(0, 0, 0, 12)
        }

        // ── "APPLE-STYLE" BLUR (same scheme as MusicWidget) ──────────
        Item {
            anchors.fill: parent
            visible: root.blurSource !== null && !Theme.lowPower

            ShaderEffectSource {
                id: mwGrab
                anchors.fill: parent
                sourceItem: root.blurSource
                sourceRect: root.blurRect
                live: true
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: mwGrab
                blurEnabled: true
                blur: 1.0
                blurMax: 48
                autoPaddingEnabled: false
                maskEnabled: true
                maskSource: mwRoundMask
            }
            Rectangle {
                id: mwRoundMask
                anchors.fill: parent
                radius: root.cornerR
                visible: false
                layer.enabled: true
                color: "#FFFFFF"
            }
        }
        // Translucent dark veil (solid if the blur is not available)
        Rectangle {
            anchors.fill: parent
            radius: root.cornerR
            color: (root.blurSource !== null && !Theme.lowPower) ? (root.lightTheme ? "#A0F2F2F2" : "#A0262626") : (root.lightTheme ? "#F2F2F2" : "#262626")
        }

        // ══════════ NORMAL MODE: search + home/work ══════════
        Column {
                    anchors.fill: parent
                    visible: !root.tripActive
        
                    // dl73: top row: search on the left, Home and Work on the right
                    Item {
                        width: parent.width
                        height: 62 * root.s
        
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 16 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12 * root.s
        
                            // Search icon (icons/search.svg)
                            Image {
                                source: "qrc:/VoltaApp/icons/search.svg"
                                width: 19 * root.s; height: 19 * root.s
                                sourceSize: Qt.size(width, height)
                                fillMode: Image.PreserveAspectFit
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: lightTheme ? 0.9 : 0.92
                            }
        
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Navigate")
                                color: lightTheme ? "#A2A3A5" : "#FFFFFF"   // dl74
                                font.pixelSize: 15 * root.s
                                font.weight: Font.DemiBold
                            }
                        }
        
                        // Tap on the search area: opens the map's search
                        MouseArea {
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            anchors.right: homeWorkRow.left
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openSearch()
                        }
        
                        // ── Casa e Lavoro (a destra) ──
                        Row {
                            id: homeWorkRow
                            anchors.right: parent.right
                            anchors.rightMargin: 6 * root.s
                            anchors.verticalCenter: parent.verticalCenter
        
                            MouseArea {
                                width: 40 * root.s; height: 62 * root.s
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.navigateHome()
                                Image {
                                    anchors.centerIn: parent
                                    source: "qrc:/VoltaApp/icons/home.svg"
                                    width: 18 * root.s; height: 18 * root.s   // dl74
                                    sourceSize: Qt.size(width, height)
                                    fillMode: Image.PreserveAspectFit
                                    opacity: 0.9
                                }
                            }
                            MouseArea {
                                width: 40 * root.s; height: 62 * root.s
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.navigateWork()
                                Image {
                                    anchors.centerIn: parent
                                    source: "qrc:/VoltaApp/icons/work.svg"
                                    width: 18 * root.s; height: 18 * root.s   // dl74
                                    sourceSize: Qt.size(width, height)
                                    fillMode: Image.PreserveAspectFit
                                    opacity: 0.9
                                }
                            }
                        }
                    }
        
                    // dl73: full-width dividing line of the widget
                    Rectangle {
                        width: parent.width
                        height: Math.max(1, root.s)
                        color: lightTheme ? "#1A171717" : "#1AFFFFFF"
                    }
        
                    // dl73: destinazioni recenti, scorrevoli a destra e sinistra
                    Item {
                        width: parent.width
                        height: parent.height - 62 * root.s - Math.max(1, root.s)
        
                        Text {
                            anchors.centerIn: parent
                            visible: recentList.count === 0
                            text: qsTr("No recent destinations")
                            color: lightTheme ? "#A2A3A5" : "#6A6B6D"
                            font.pixelSize: 12 * root.s
                        }
        
                        ListView {
                            id: recentList
                            anchors.fill: parent
                            orientation: ListView.Horizontal
                            clip: true
                            spacing: 6 * root.s
                            leftMargin: 10 * root.s
                            rightMargin: 10 * root.s
                            boundsBehavior: Flickable.StopAtBounds
                            flickableDirection: Flickable.HorizontalFlick
                            model: root.recentDestinations
                            delegate: Item {
                                width: Math.min(root.width * 0.66, 170 * root.s)
                                height: recentList.height
        
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                            anchors.rightMargin: 10 * root.s   // dl74
                                    spacing: 9 * root.s
        
                                    Item {   // dl74: icon without circle
                                        width: 28 * root.s; height: 28 * root.s
                                        anchors.verticalCenter: parent.verticalCenter
                                        Image {
                                            anchors.centerIn: parent
                                            source: "qrc:/VoltaApp/icons/poi_generic.svg"
                                            width: 20 * root.s; height: 20 * root.s
                                            sourceSize: Qt.size(width * 2, height * 2)
                                            fillMode: Image.PreserveAspectFit
                                            opacity: 0.9
                                        }
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 37 * root.s
                                        spacing: 1 * root.s
                                        Text {
                                            width: parent.width
                                            text: modelData.name || ""
                                            elide: Text.ElideRight
                                            color: lightTheme ? "#171717" : "#E8E8E8"
                                            font.pixelSize: 13 * root.s
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            width: parent.width
                                            text: modelData.address || ""
                                            elide: Text.ElideRight
                                            color: lightTheme ? "#757575" : "#8A8B8D"
                                            font.pixelSize: 10.5 * root.s
                                        }
                                    }
                                }
        
                                // dl74: dividing bar between one destination and the next
                                Rectangle {
                                    visible: index < recentList.count - 1
                                    anchors.right: parent.right; anchors.rightMargin: -3 * root.s
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(1, root.s); height: 34 * root.s
                                    color: lightTheme ? "#26171717" : "#33FFFFFF"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.openRecent(modelData)
                                }
                            }
                        }
                    }
                }

        // ══════════ TRIP MODE: identical to the map's bottom box ══════════
        // (EtaBlock of MapLibreView.qml: same proportions, texts, blue line with arrow,
        // "End" and "•••"; 300 px box width = 1)
        Item {
            id: tripBox
            anchors.fill: parent
            visible: root.tripActive
            readonly property real k: root.width / 300
            readonly property color cText:   root.lightTheme ? "#141414" : "#F5F5F5"
            readonly property color cSubtle: root.lightTheme ? "#737373" : "#A3A3A3"

            function fmtDur(min) {
                if (min <= 0) return qsTr("-- min")
                var h = Math.floor(min / 60), m = min % 60
                return h > 0 ? (h + " h " + m + " min") : (m + " min")
            }
            function fmtDist(m) { return m >= 1000 ? (m / 1000).toFixed(1) + " km" : Math.round(m) + " m" }
            function fmtBig(m) {
                if (m <= 0) return qsTr("-- km")
                return m >= 100000 ? (Math.round(m / 1000) + " km") : fmtDist(m)
            }

            // Tap on the rest of the widget → opens the map (under the controls)
            MouseArea { anchors.fill: parent; onClicked: root.openMap() }

            EtaPanel {
                id: etaBox
                k: tripBox.k
                x: 0
                width: parent.width
                // rows distributed over the widget's full height, same margin above and below
                y: 0
                height: parent.height
                vStretch: (parent.height / k - 2 * 19) / 90.8
                vShift: (19 - 10.9) * k
                padX: Math.round(15 * k)
                cText: tripBox.cText
                cSubtle: tripBox.cSubtle
                arrival: root.tripEta
                duration: tripBox.fmtDur(Nav.remainingDuration)
                distance: tripBox.fmtBig(Nav.remainingDistance)
                destination: root.tripName
                progress: root.tripPct
                traffic: Nav.trafficFractions
                interactive: true
                onStopRequested: root.mapLibre.stopNav()
                onRecenterRequested: root.mapLibre.recenter()
                onAddStopRequested: { root.openMap(); stopSearchTimer.restart() }
                menuExternal: true
                onMenuRequested: { root.openMap(); tripMenuTimer.restart() }
            }
        }
    }
}
