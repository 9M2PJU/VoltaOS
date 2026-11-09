import QtQuick
import QtQuick.Window
import QtQuick.VirtualKeyboard
import VoltaApp 1.0

// ─────────────────────────────────────────────────────────────────────────────
//  UNIFIED SEARCH — shared by YT Music, Spotify and Bluetooth. Searches
//  all providers in parallel (MediaHub.search) and shows the results
//  mixed together, filterable by provider. Tap on a track = play,
//  "+" = add to the unified queue, albums/artists/playlists open in the app
//  of their provider.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: sp
    color: Theme.bg

    property var hub: null
    property bool lightTheme: false
    property real headerH: 32 * ((Window.window && Window.window.uPx) ? Window.window.uPx : 1.12)

    signal closed()

    // dl58: starting selected tag = that of the app that opens the search ("ytmusic" / "spotify")
    property string defaultFilter: ""
    function _applyDefault() { if (hub && defaultFilter !== "") hub.searchFilter = defaultFilter }
    onVisibleChanged: if (visible) _applyDefault()
    onHubChanged: _applyDefault()
    Component.onCompleted: _applyDefault()

    readonly property color iconCol: lightTheme ? "#555555" : "#A2A3A5"

    function focusInput() { _in.forceActiveFocus() }
    function reset() { _in.text = ""; if (hub) hub.search("") }

    function commit() { if (hub) hub.pushRecent(_in.text) }

    function playTrack(item) {
        sp.commit()
        hub.play(item.provider, item.data)
    }
    function openItem(item) {
        sp.commit()
        sp.closed()
        hub.openInProvider(item.provider, item.data)
    }

    Timer { id: _deb; interval: 350; onTriggered: sp.hub.search(_in.text) }

    // ── Top bar: close + search field + provider filters ──
    Item {
        id: _top
        width: parent.width; height: sp.headerH + 64

        Row {
            id: _topRow
            x: 20; width: parent.width - 60; height: sp.headerH + 20
            spacing: 20
            Text {
                text: "✕"; color: sp.iconCol; font.pixelSize: 24; font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { sp.commit(); sp.closed() } }
            }
            Rectangle {
                width: parent.width - 60; height: 44
                anchors.verticalCenter: parent.verticalCenter
                radius: 8; color: "transparent"
                border.color: Theme.surfaceElevated; border.width: 1

                TextInput {
                    id: _in
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 40
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.textPrimary; font.pixelSize: 16; font.weight: Font.Medium
                    clip: true
                    EnterKeyAction.actionId: EnterKeyAction.Search
                    EnterKeyAction.label: qsTr("Search")
                    onTextChanged: _deb.restart()
                    Keys.onReturnPressed: { _deb.stop(); sp.hub.search(text); sp.commit() }
                    Keys.onEnterPressed:  { _deb.stop(); sp.hub.search(text); sp.commit() }
                    Text {
                        visible: parent.text === ""
                        text: qsTr("Search YT Music, Spotify and Music...")
                        color: Theme.textHint; font.pixelSize: 16; font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Rectangle {
                    visible: _in.text !== ""
                    width: 24; height: 24; radius: 12
                    color: sp.lightTheme ? "#E0E0E0" : "#262626"
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    Text { anchors.centerIn: parent; text: "✕"; color: sp.lightTheme ? "#333" : "#CCC"; font.pixelSize: 12 }
                    MouseArea { anchors.fill: parent; onClicked: sp.reset() }
                }
            }
        }

        // Filtri provider
        Row {
            anchors.top: _topRow.bottom; anchors.topMargin: -6
            x: 64; spacing: 10
            Repeater {
                model: [ { id: "ytmusic", name: "YT Music", icon: "qrc:/VoltaApp/icons/ytmusic.svg" },
                         { id: "spotify", name: "Spotify", icon: "qrc:/VoltaApp/icons/spotify.svg" },
                         { id: "localmusic", name: qsTr("Music"), icon: "qrc:/VoltaApp/icons/localmusic.svg" } ]
                Rectangle {
                    id: _chip
                    readonly property bool sel: sp.hub && sp.hub.searchFilter === modelData.id
                    // Rectangles with slightly rounded corners: dark gray (dark
                    // theme) / light gray (light theme), the selected one in contrast
                    height: 36; radius: 8
                    width: _chipRow.implicitWidth + 28
                    color: sel ? (sp.lightTheme ? "#444444" : "#FFFFFF") : (sp.lightTheme ? "#E4E4E4" : "#333333")
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Row {
                        id: _chipRow
                        anchors.centerIn: parent; spacing: 8
                        Image { sourceSize: Qt.size(width * 2, height * 2);
                            visible: modelData.icon !== ""
                            source: modelData.icon; width: 16; height: 16
                            fillMode: Image.PreserveAspectFit
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: modelData.name
                            color: _chip.sel ? (sp.lightTheme ? "#FFFFFF" : "#000000") : (sp.lightTheme ? "#555555" : Theme.textPrimary)
                            font.pixelSize: 14; font.weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: sp.hub.searchFilter = modelData.id }
                }
            }
            Text {
                visible: sp.hub && sp.hub.searching
                text: qsTr("Searching…"); color: Theme.textSecondary; font.pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ── Track row (play / add to queue) ──
    component ResultRow: Item {
        id: _rr
        property var item
        readonly property var d: item ? item.data : ({})
        width: parent ? parent.width : 600; height: 64
        Rectangle { anchors.fill: parent; color: _rrMA.pressed ? Theme.surface : "transparent" }
        MediaCover {
            id: _rrc; x: 40; width: 48; height: 48; radius: 3
            anchors.verticalCenter: parent.verticalCenter
            source: _rr.d.cover || ""
            placeholderIcon: sp.hub.providerIcon(_rr.item.provider)
        }
        Column {
            anchors.left: _rrc.right; anchors.leftMargin: 16
            anchors.right: _rrActions.left; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter; spacing: 3
            Text { text: _rr.d.title || ""; color: Theme.textPrimary; font.pixelSize: 16; font.weight: Font.Medium; width: parent.width; elide: Text.ElideRight }
            Text {
                text: (_rr.d.subtitle || "") + (_rr.d.duration ? " · " + _rr.d.duration : "")
                color: Theme.textSecondary; font.pixelSize: 13; width: parent.width; elide: Text.ElideRight
            }
        }
        MouseArea { id: _rrMA; anchors.fill: parent; onClicked: sp.playTrack(_rr.item) }
        Row {
            id: _rrActions
            anchors.right: parent.right; anchors.rightMargin: 40
            anchors.verticalCenter: parent.verticalCenter
            spacing: 22
            Image { sourceSize: Qt.size(width * 2, height * 2);
                source: sp.hub.providerIcon(_rr.item.provider)
                width: 20; height: 20; fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ── Horizontal row of albums / artists / playlists ──
    component CardRow: Column {
        id: _cr
        property string title
        property var items: []
        property bool circle: false
        width: parent ? parent.width : 600
        spacing: 14
        visible: items.length > 0
        Text { text: _cr.title; color: Theme.textPrimary; font.pixelSize: 20; font.weight: Font.Medium; leftPadding: 40 }
        ListView {
            width: parent.width; height: _cr.circle ? 190 : 225
            orientation: ListView.Horizontal; spacing: 14; leftMargin: 40; rightMargin: 40; clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: _cr.items
            delegate: Item {
                width: _cr.circle ? 140 : 160; height: ListView.view.height
                Column {
                    width: parent.width; spacing: 8
                    Item {
                        width: parent.width; height: parent.width
                        MediaCover {
                            anchors.fill: parent; circle: _cr.circle
                            source: modelData.data.cover || ""
                            placeholderIcon: sp.hub.providerIcon(modelData.provider)
                        }
                        // Badge provider
                        Image { sourceSize: Qt.size(width * 2, height * 2);
                            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 6
                            source: sp.hub.providerIcon(modelData.provider)
                            width: 20; height: 20; fillMode: Image.PreserveAspectFit
                        }
                    }
                    Text { text: modelData.data.title || ""; color: Theme.textPrimary; font.pixelSize: 14; font.weight: Font.Medium; width: parent.width; elide: Text.ElideRight; horizontalAlignment: _cr.circle ? Text.AlignHCenter : Text.AlignLeft }
                    Text { text: modelData.data.subtitle || ""; color: Theme.textSecondary; font.pixelSize: 12; width: parent.width; elide: Text.ElideRight; horizontalAlignment: _cr.circle ? Text.AlignHCenter : Text.AlignLeft }
                }
                MouseArea { anchors.fill: parent; onClicked: sp.openItem(modelData) }
            }
        }
    }

    Flickable {
        anchors.top: _top.bottom; anchors.bottom: parent.bottom; width: parent.width
        contentHeight: _col.height + 80; clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: _col
            width: parent.width; topPadding: 10; spacing: 26

            // Recent searches (shared between apps)
            Column {
                visible: _in.text.length === 0
                width: parent.width; spacing: 18; leftPadding: 40
                Row {
                    spacing: 18
                    visible: sp.hub && sp.hub.recentSearches.length > 0
                    Text { text: qsTr("Recent searches"); color: Theme.textPrimary; font.pixelSize: 18; font.weight: Font.Medium }
                    Text {
                        text: qsTr("Delete"); color: Theme.accent; font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: sp.hub.clearRecent() }
                    }
                }
                Repeater {
                    model: sp.hub ? sp.hub.recentSearches : []
                    Item {      // dl58: drawn clock (as in the app's recent searches), not the emoji
                        width: _rsRow.implicitWidth; height: _rsRow.implicitHeight
                        Row {
                            id: _rsRow
                            spacing: 16
                            Canvas {
                                width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter
                                onPaint: {
                                    var c = getContext("2d"); c.clearRect(0, 0, width, height)
                                    c.strokeStyle = Theme.textHint; c.lineWidth = 1.5; c.lineCap = "round"
                                    c.beginPath(); c.arc(9, 9, 7.5, 0, 2 * Math.PI); c.stroke()
                                    c.beginPath(); c.moveTo(9, 4); c.lineTo(9, 9); c.lineTo(12, 12); c.stroke()
                                }
                            }
                            Text { text: modelData; color: Theme.textPrimary; font.pixelSize: 16; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: { _in.text = modelData; _deb.stop(); sp.hub.search(modelData) } }
                    }
                }
            }

            // No results
            Text {
                visible: sp.hub && _in.text.length >= 2 && !sp.hub.searching
                         && sp.hub.resultTracks.length === 0 && sp.hub.resultAlbums.length === 0
                         && sp.hub.resultArtists.length === 0 && sp.hub.resultPlaylists.length === 0
                text: qsTr("No results for “") + _in.text + "”"
                color: Theme.textSecondary; font.pixelSize: 15; leftPadding: 40
            }

            // Tracks
            Column {
                width: parent.width; spacing: 4
                visible: sp.hub && sp.hub.resultTracks.length > 0 && _in.text.length > 0
                Text { text: qsTr("Tracks"); color: Theme.textPrimary; font.pixelSize: 20; font.weight: Font.Medium; leftPadding: 40; bottomPadding: 6 }
                Repeater {
                    model: sp.hub ? sp.hub.resultTracks.slice(0, 12) : []
                    ResultRow { item: modelData }
                }
            }

            // Video (YT Music only)
            Column {
                width: parent.width; spacing: 4
                visible: sp.hub && sp.hub.resultVideos.length > 0 && _in.text.length > 0
                Text { text: qsTr("Video"); color: Theme.textPrimary; font.pixelSize: 20; font.weight: Font.Medium; leftPadding: 40; bottomPadding: 6 }
                Repeater {
                    model: sp.hub ? sp.hub.resultVideos.slice(0, 6) : []
                    ResultRow { item: modelData }
                }
            }

            CardRow { title: qsTr("Artists");  circle: true; items: sp.hub && _in.text.length > 0 ? sp.hub.resultArtists : [] }
            CardRow { title: qsTr("Albums");    items: sp.hub && _in.text.length > 0 ? sp.hub.resultAlbums : [] }
            CardRow { title: qsTr("Playlist"); items: sp.hub && _in.text.length > 0 ? sp.hub.resultPlaylists : [] }
        }
    }

    // Short message (e.g. "Added to queue")
    Rectangle {
        z: 10
        anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.margins: 16
        radius: 8; color: "#CC000000"
        width: _toastT.implicitWidth + 24; height: 34
        visible: sp.hub && sp.hub.toastText !== ""
        Text { id: _toastT; anchors.centerIn: parent; text: sp.hub ? sp.hub.toastText : ""; color: "#FFF"; font.pixelSize: 13 }
    }
}
