import QtQuick
import QtQuick.Window
import QtQuick.Effects
import VoltaApp 1.0

// MUSIC APP — the audio files of the PC and of USB sticks, played by local_music_service.py (port 8097).
// Tabs: Tracks (list) · Albums · Artists · Playlists (grids like Spotify); album / artist / playlist page.
// Search and queue are the UNIFIED ones (MediaSearchPanel / MediaQueuePanel, shared with YT Music and Spotify).
// Title, cover and controls also reach the mini player from the system player (MPRIS, "Music").
Rectangle {
    id: root
    color: Theme.bg
    clip: true
    property bool lightTheme: false
    onLightThemeChanged: Theme.light = lightTheme

    property var hub: null                       // MediaHub: unified queue and search
    signal switchToApp(string appId)

    property string backendUrl: "http://127.0.0.1:8097"
    readonly property color accent: "#E8548A"
    readonly property color accentSoft: lightTheme ? "#FBE0EA" : "#4A1E31"
    property string iconColor: lightTheme ? "#555555" : "#A2A3A5"
    property string dividerColor: lightTheme ? "#777777" : "#414141"
    property string selectedTextColor: lightTheme ? "#444444" : Theme.textPrimary
    readonly property real u: (Window.window && Window.window.uPx) ? Window.window.uPx : 1.12
    readonly property real headerH: 38 * u
    readonly property real k: (Window.window ? Window.window.width : 1200) / 1070      // same scale as the music widget
    readonly property real btnRadius: 6 * k                                          // corners like the music widget

    readonly property var musicApps: [
        { appId: "spotify",    name: "YT Music",  icon: "qrc:/VoltaApp/icons/ytmusic.svg" },
        { appId: "spotifyapp", name: "Spotify",   icon: "qrc:/VoltaApp/icons/spotify.svg" },
        { appId: "localmusic", name: qsTr("Music"), icon: "qrc:/VoltaApp/icons/localmusic.svg" },
        { appId: "podcast",    name: "Apple Podcast", icon: "qrc:/VoltaApp/icons/podcast.svg" },
        { appId: "bluetooth",  name: "Bluetooth", icon: "qrc:/VoltaApp/icons/bluetooth.svg" }
    ]
    readonly property string selfAppId: "localmusic"
    property bool appMenuOpen: false

    // ── stato ──
    property string tab: "songs"                 // songs | albums | artists | playlists
    property string songFilter: "all"            // all | pc | usb
    property bool searchOpen: false              // unified search
    property bool playerVisible: false           // coda unica
    property var page: null                      // { type: album|artist|playlist|likes, key, title, sub, akey, ctx }
    property bool backendOk: true
    property string toastText: ""
    property int songsTotal: 0
    property var albums: []
    property var artists: []
    property var playlists: []
    property int likesCount: 0
    property string likesAkey: ""
    property var scan: ({ running: false, done: 0, total: 0 })
    property string musicDir: ""
    property var pState: ({ track: null, is_playing: false, progress_ms: 0, duration_ms: 0, shuffle: false, repeat: "off" })
    property var menuTrack: null                 // track of the "⋯" menu
    property bool newPlaylistOpen: false
    property int _lastScan: 0
    property double _usbToastTs: 0
    ListModel { id: songsModel }
    ListModel { id: pageModel }

    // ── utilities ──
    function api(path, cb, err) {
        var x = new XMLHttpRequest()
        x.open("GET", root.backendUrl + path)
        x.timeout = 20000
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return
            var d = null
            try { d = JSON.parse(x.responseText) } catch (e) {}
            if (x.status === 200 && d !== null) { root.backendOk = true; if (cb) cb(d) }
            else { if (x.status === 0) root.backendOk = false; if (err) err(x.status) }
        }
        x.send()
    }
    function fmt(sec) {
        sec = Math.max(0, Math.round(sec || 0))
        var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60
        return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (s < 10 ? "0" : "") + s
    }
    function coverUrl(akey) { return akey ? root.backendUrl + "/cover/" + akey + ".jpg" : "" }
    function toast(t) { root.toastText = t; toastTimer.restart() }
    Timer { id: toastTimer; interval: 2600; onTriggered: root.toastText = "" }

    // ── caricamento ──
    function loadSongs(more) {
        var off = more ? songsModel.count : 0
        root.api("/tracks?limit=500&offset=" + off + (root.songFilter !== "all" ? "&kind=" + root.songFilter : ""), function(d) {
            if (!more) songsModel.clear()
            for (var i = 0; i < d.tracks.length; i++) songsModel.append(d.tracks[i])
            root.songsTotal = d.total
        })
    }
    function loadAlbums() { root.api("/albums", function(d) { root.albums = d.albums }) }
    function loadArtists() { root.api("/artists", function(d) { root.artists = d.artists }) }
    function loadPlaylists() { root.api("/playlists", function(d) { root.playlists = d.playlists; root.likesCount = d.likes; root.likesAkey = d.likes_akey || "" }) }
    function loadSources() {
        root.api("/sources", function(d) {
            root.scan = d.scan; root.musicDir = d.music_dir
            if (d.scan.usb_new && d.scan.usb_new.ts !== root._usbToastTs) {
                if (root._usbToastTs !== 0) root.toast(qsTr("USB drive connected: ") + d.scan.usb_new.label)
                root._usbToastTs = d.scan.usb_new.ts
            }
            if (d.scan.last !== root._lastScan && !d.scan.running) { root._lastScan = d.scan.last; root.reloadAll() }
        })
    }
    function reloadAll() { loadSongs(false); loadAlbums(); loadArtists(); loadPlaylists(); if (root.page) openPage(root.page) }
    function loadStatus() { root.api("/player/status", function(d) { root.pState = d }) }
    Component.onCompleted: { loadSources(); reloadAll(); loadStatus(); root.handleRequest() }

    Timer { interval: 1000; repeat: true; running: root.visible; onTriggered: root.loadStatus() }
    Timer { interval: 4000; repeat: true; running: root.visible; onTriggered: root.loadSources() }

    // ── requests from the rest of the system (music widget, unified search, unified queue) ──
    function handleRequest() {
        var r = root.hub ? root.hub.lmRequest : null
        if (!r) return
        root.hub.lmRequest = null
        root.appMenuOpen = false
        if (r.kind === "queue") { root.searchOpen = false; root.playerVisible = true }
        else if (r.kind === "search") { root.playerVisible = false; root.searchOpen = true }
        else if (r.kind === "album" && r.data && r.data.raw) { root.searchOpen = false; root.playerVisible = false; root.openAlbum(r.data.raw) }
        else if (r.kind === "artist" && r.data && r.data.raw) { root.searchOpen = false; root.playerVisible = false; root.openArtist(r.data.raw) }
    }
    Connections { target: root.hub; function onLmRequestChanged() { root.handleRequest() } }
    onSearchOpenChanged: if (searchOpen && hub) Qt.callLater(function() { _uSearch.focusInput() })

    // ── pagine (album / artista / playlist / Mi piace) ──
    function openPage(p) {
        root.page = p; root.searchOpen = false; root.playerVisible = false
        root.api("/ctx?ctx=" + encodeURIComponent(p.ctx), function(d) {
            pageModel.clear()
            for (var i = 0; i < d.tracks.length; i++) pageModel.append(d.tracks[i])
        })
    }
    function openAlbum(a) { openPage({ type: "album", title: a.album, sub: a.artist + (a.year ? " · " + a.year : ""), akey: a.key, ctx: "album:" + a.key }) }
    function openArtist(a) { openPage({ type: "artist", title: a.name, sub: a.count + qsTr(" tracks"), akey: a.akey, ctx: "artist:" + a.name }) }
    function openPlaylist(p) { openPage({ type: "playlist", title: p.name, sub: p.count + qsTr(" tracks"), akey: p.akey || "", ctx: "playlist:" + p.id, id: p.id }) }
    function openLikes() { openPage({ type: "likes", title: qsTr("Liked songs"), sub: root.likesCount + qsTr(" tracks"), akey: "", ctx: "likes" }) }
    function closePage() { root.page = null }
    readonly property string songsCtx: root.songFilter === "all" ? "all" : "src:" + root.songFilter
    function setSongFilter(f) { root.songFilter = f; root.loadSongs(false) }
    function setTab(t) { root.tab = t; root.page = null; root.searchOpen = false; root.playerVisible = false; root.appMenuOpen = false }

    // ── comandi ──
    function playTrack(id, ctx) { root.api("/play?id=" + id + "&ctx=" + encodeURIComponent(ctx || "all"), function() { root.loadStatus() }) }
    function playAll(ctx, shuffle) { root.api("/play_all?ctx=" + encodeURIComponent(ctx) + (shuffle ? "&shuffle=1" : ""), function() { root.loadStatus() }) }
    function cmd(path) { root.api(path, function() { root.loadStatus() }) }
    function toggleLike(model, idx, listModel) {
        var t = listModel.get(idx)
        root.api("/like?id=" + t.id, function(d) {
            listModel.setProperty(idx, "like", d.like)
            root.loadPlaylists()
        })
    }
    // Adds to the UNIFIED queue (even while YT Music or Spotify is playing)
    function addToQueue(t) {
        if (!root.hub) return
        root.hub.addToQueue("localmusic", root.hub.lmTrack(t))
    }
    readonly property var curTrack: pState.track
    readonly property real progress: pState.duration_ms > 0 ? Math.min(1, pState.progress_ms / pState.duration_ms) : 0

    // ═════════ componenti ═════════
    component Ico: Item {
        id: _ico
        property string src: ""
        property color col: Theme.textPrimary
        property real size: 22
        width: size; height: size
        Image {
            anchors.fill: parent; source: _ico.src; sourceSize: Qt.size(_ico.size * 2, _ico.size * 2); fillMode: Image.PreserveAspectFit
            layer.enabled: true
            layer.effect: MultiEffect { colorization: 1.0; colorizationColor: _ico.col }
        }
    }
    component Cover: Rectangle {
        id: _cv
        property string akey: ""
        radius: 6
        color: root.lightTheme ? "#F0F0F0" : "#262626"            // placeholder = the music widget's
        Text { anchors.centerIn: parent; text: "🎵"; font.pixelSize: Math.max(10, _cv.width * 0.34); visible: _img.status !== Image.Ready }
        Image {
            id: _img
            anchors.fill: parent; asynchronous: true; cache: true; fillMode: Image.PreserveAspectCrop
            source: root.coverUrl(_cv.akey); sourceSize: Qt.size(_cv.width * 2, _cv.height * 2)
            visible: status === Image.Ready
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: _mask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
        }
        Rectangle { id: _mask; visible: false; layer.enabled: true; width: _cv.width; height: _cv.height; radius: _cv.radius }
    }
    component PillBtn: Rectangle {
        id: _pb
        property string label: ""
        property bool filled: true
        signal clicked()
        height: 44; width: _pt.implicitWidth + 40; radius: root.btnRadius
        color: filled ? (_pa.pressed ? Qt.darker(root.accent, 1.2) : root.accent) : (_pa.pressed ? Theme.surfaceElevated : Theme.surface)
        Text { id: _pt; anchors.centerIn: parent; text: _pb.label; font.pixelSize: 16; font.weight: Font.DemiBold
               color: _pb.filled ? "#FFFFFF" : Theme.textPrimary }
        MouseArea { id: _pa; anchors.fill: parent; onClicked: _pb.clicked() }
    }

    // A track row. "lm" = source ListModel, used to change the heart.
    component TrackRow: Rectangle {
        id: _tr
        property var lm: songsModel
        property string ctx: "all"
        property bool inPlaylist: false
        readonly property bool cur: !!root.curTrack && root.curTrack.id === model.id
        width: ListView.view ? ListView.view.width : 600; height: 64
        color: _ra.pressed ? Theme.surface : "transparent"
        Row {
            anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 12; spacing: 14
            Cover { width: 46; height: 46; akey: model.akey; anchors.verticalCenter: parent.verticalCenter }
            Column {
                anchors.verticalCenter: parent.verticalCenter; width: parent.width - 46 - 46 - 34 - 30 - 14 * 4; spacing: 3
                Text { width: parent.width; elide: Text.ElideRight; text: model.title; font.pixelSize: 17; font.weight: Font.DemiBold
                       color: _tr.cur ? root.accent : Theme.textPrimary }
                Text { width: parent.width; elide: Text.ElideRight; font.pixelSize: 13; color: Theme.textSecondary
                       text: model.artist + (model.album ? " · " + model.album : "") }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; width: 46; horizontalAlignment: Text.AlignRight
                   text: root.fmt(model.dur); font.pixelSize: 14; color: Theme.textSecondary }
            Item {
                width: 34; height: 40; anchors.verticalCenter: parent.verticalCenter
                Ico { anchors.centerIn: parent; size: 20; src: model.like ? "qrc:/VoltaApp/icons/heart-full.svg" : "qrc:/VoltaApp/icons/heart-empty.svg"
                      col: model.like ? root.accent : root.iconColor }
                MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: root.toggleLike(model, index, _tr.lm) }
            }
            Item {
                width: 30; height: 40; anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: "⋯"; font.pixelSize: 26; font.weight: Font.Bold; color: root.iconColor }
                MouseArea { anchors.fill: parent; anchors.margins: -4
                            onClicked: { root.menuTrack = { id: model.id, title: model.title, artist: model.artist, album: model.album, akey: model.akey, dur: model.dur, inPlaylist: _tr.inPlaylist }; } }
            }
        }
        MouseArea { id: _ra; anchors.fill: parent; anchors.rightMargin: 74; onClicked: root.playTrack(model.id, _tr.ctx) }
        Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.leftMargin: 80; anchors.right: parent.right; height: 1; color: Theme.divider }
    }

    // Grid card (like Spotify): square or round cover, title, subtitle
    component Card: Item {
        id: _cd
        property string akey: ""
        property string title: ""
        property string sub: ""
        property bool circle: false
        property string iconSrc: ""              // tile without a cover (Liked, new playlist)
        property bool likesTile: false
        property bool removable: false
        signal clicked()
        signal removed()
        readonly property real side: width - 24
        Rectangle {
            id: _cdc
            x: 12; y: 6; width: _cd.side; height: _cd.side
            radius: _cd.circle ? width / 2 : 10
            color: "transparent"
            gradient: _cd.likesTile ? _likesGrad : null
            Gradient { id: _likesGrad; orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#D22C5E" } GradientStop { position: 1; color: "#FF97CD" } }
            Cover { anchors.fill: parent; radius: parent.radius; akey: _cd.akey; visible: !_cd.likesTile }
            Ico { visible: _cd.likesTile; anchors.centerIn: parent; size: _cd.side * 0.34; src: _cd.iconSrc; col: "#FFFFFF" }
            Rectangle { visible: _cd.removable; anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 6; width: 30; height: 30; radius: 15; color: "#99000000"
                Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 14; color: "#FFFFFF" }
                MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: _cd.removed() } }
        }
        Text { x: 12; y: _cdc.y + _cdc.height + 8; width: _cd.side; elide: Text.ElideRight; text: _cd.title
               horizontalAlignment: _cd.circle ? Text.AlignHCenter : Text.AlignLeft
               font.pixelSize: 16; font.weight: Font.DemiBold; color: Theme.textPrimary }
        Text { x: 12; y: _cdc.y + _cdc.height + 30; width: _cd.side; elide: Text.ElideRight; text: _cd.sub
               horizontalAlignment: _cd.circle ? Text.AlignHCenter : Text.AlignLeft
               font.pixelSize: 13; color: Theme.textSecondary }
        MouseArea { anchors.fill: parent; z: -1; onClicked: _cd.clicked() }
    }
    // Card grid
    component CardGrid: GridView {
        id: _gv
        property real cardMin: 200
        readonly property int cols: Math.max(2, Math.floor((width - 24) / cardMin))
        leftMargin: 12; rightMargin: 12; topMargin: 8; bottomMargin: 24
        cellWidth: Math.floor((width - 24) / cols); cellHeight: cellWidth + 60
        clip: true; boundsBehavior: Flickable.StopAtBounds
    }
    component Empty: Column {
        width: parent ? parent.width : 600; spacing: 14
        property string msg: ""
        Item { width: 1; height: 80 }
        Ico { anchors.horizontalCenter: parent.horizontalCenter; size: 64; src: "qrc:/VoltaApp/icons/localmusic.svg"; col: Theme.textHint }
        Text { anchors.horizontalCenter: parent.horizontalCenter; width: parent.width - 80; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
               text: parent.msg; font.pixelSize: 17; color: Theme.textSecondary }
    }

    // ═════════ CONTENUTO ═════════
    Item {
        id: _body
        anchors.fill: parent; anchors.topMargin: root.headerH

        // ── service unreachable ──
        Empty { visible: !root.backendOk; msg: qsTr("The Music service is not responding. Try again in a moment.") }

        // ── TRACKS (list) ──
        Item {
            anchors.fill: parent; visible: root.backendOk && root.tab === "songs" && !root.page
            Row {
                id: _songsTop; x: 20; y: 10; height: 44; spacing: 10
                Repeater {
                    model: [{ id: "all", text: qsTr("All songs") }, { id: "pc", text: qsTr("Local") }, { id: "usb", text: qsTr("USB") }]
                    Rectangle {
                        readonly property bool sel: root.songFilter === modelData.id
                        height: 44; width: _fbT.implicitWidth + 44; radius: root.btnRadius
                        color: sel ? root.accent : (_fbA.pressed ? Theme.surfaceElevated : Theme.surface)
                        Text { id: _fbT; anchors.centerIn: parent; text: modelData.text; font.pixelSize: 16; font.weight: Font.DemiBold
                               color: parent.sel ? "#FFFFFF" : Theme.textPrimary }
                        MouseArea { id: _fbA; anchors.fill: parent; onClicked: root.setSongFilter(modelData.id) }
                    }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; leftPadding: 8; text: root.songsTotal + qsTr(" tracks"); font.pixelSize: 15; color: Theme.textSecondary }
            }
            ListView {
                anchors.top: _songsTop.bottom; anchors.topMargin: 6; anchors.bottom: parent.bottom; width: parent.width
                clip: true; boundsBehavior: Flickable.StopAtBounds; model: songsModel
                delegate: TrackRow { lm: songsModel; ctx: root.songsCtx }
                onAtYEndChanged: if (atYEnd && songsModel.count < root.songsTotal) root.loadSongs(true)
                footer: Item { width: 1; height: 24 }
            }
            Empty { visible: songsModel.count === 0; anchors.top: _songsTop.bottom
                    msg: root.scan.running ? qsTr("Looking for music… ") + root.scan.done + " / " + root.scan.total
                         : root.songFilter === "usb" ? qsTr("No songs on the connected USB drives.")
                         : qsTr("No tracks found.\nPut your music in ") + root.musicDir + qsTr(" or connect a USB drive.") }
        }

        // ── ALBUM (griglia) ──
        CardGrid {
            anchors.fill: parent; visible: root.backendOk && root.tab === "albums" && !root.page
            model: root.albums
            delegate: Card { width: GridView.view.cellWidth; height: GridView.view.cellHeight
                akey: modelData.key; title: modelData.album; sub: modelData.artist + (modelData.year ? " · " + modelData.year : "")
                onClicked: root.openAlbum(modelData) }
            Empty { visible: root.albums.length === 0; msg: qsTr("No albums.") }
        }

        // ── ARTISTS (grid, round covers) ──
        CardGrid {
            anchors.fill: parent; visible: root.backendOk && root.tab === "artists" && !root.page
            model: root.artists
            delegate: Card { width: GridView.view.cellWidth; height: GridView.view.cellHeight
                circle: true; akey: modelData.akey; title: modelData.name
                sub: modelData.albums + qsTr(" albums") + " · " + modelData.count + qsTr(" tracks")
                onClicked: root.openArtist(modelData) }
            Empty { visible: root.artists.length === 0; msg: qsTr("No artists.") }
        }

        // ── PLAYLISTS (grid: Liked, your playlists, new) ──
        Item {
            anchors.fill: parent; visible: root.backendOk && root.tab === "playlists" && !root.page
            Item {
                id: _plTop; x: 20; y: 8; width: parent.width - 40; height: 52
                PillBtn { visible: !root.newPlaylistOpen; label: qsTr("＋ New playlist"); filled: false; onClicked: { root.newPlaylistOpen = true; _plName.text = ""; _plName.forceActiveFocus() } }
                Row { visible: root.newPlaylistOpen; spacing: 10
                    Rectangle { width: 320; height: 44; radius: 10; color: Theme.surfaceInput
                        TextInput { id: _plName; anchors.fill: parent; anchors.margins: 12; font.pixelSize: 17; color: Theme.textPrimary; clip: true
                                    onAccepted: _plOk.clicked()
                                    Text { visible: parent.text === ""; text: qsTr("Playlist name"); color: Theme.textHint; font.pixelSize: 17 } } }
                    PillBtn { id: _plOk; label: qsTr("Create")
                              onClicked: { if (_plName.text.trim() !== "") root.api("/playlists/create?name=" + encodeURIComponent(_plName.text.trim()), function() { root.newPlaylistOpen = false; root.loadPlaylists() }) } }
                    PillBtn { label: qsTr("Cancel"); filled: false; onClicked: root.newPlaylistOpen = false }
                }
            }
            CardGrid {
                anchors.top: _plTop.bottom; anchors.bottom: parent.bottom; width: parent.width
                model: [{ likes: true }].concat(root.playlists)
                delegate: Card { width: GridView.view.cellWidth; height: GridView.view.cellHeight
                    likesTile: !!modelData.likes; iconSrc: modelData.likes ? "qrc:/VoltaApp/icons/heart-full.svg" : ""
                    akey: modelData.likes ? "" : (modelData.akey || "")
                    title: modelData.likes ? qsTr("Liked songs") : modelData.name
                    sub: (modelData.likes ? root.likesCount : modelData.count) + qsTr(" tracks")
                    removable: !modelData.likes
                    onClicked: modelData.likes ? root.openLikes() : root.openPlaylist(modelData)
                    onRemoved: root.api("/playlists/delete?id=" + modelData.id, function() { root.loadPlaylists() }) }
            }
        }

        // ── PAGINA (album / artista / playlist / Mi piace) ──
        Item {
            anchors.fill: parent; visible: root.backendOk && !!root.page
            Item {
                id: _pgHead; width: parent.width; height: 196
                Rectangle { x: 20; y: 12; width: 44; height: 44; radius: 22; color: Theme.surface
                    Text { anchors.centerIn: parent; text: "‹"; font.pixelSize: 30; color: Theme.textPrimary; y: -2 }
                    MouseArea { anchors.fill: parent; onClicked: root.closePage() } }
                Cover { id: _pgCov; x: 84; y: 12; width: 172; height: 172; akey: root.page ? root.page.akey : ""
                        radius: root.page && root.page.type === "artist" ? 86 : 10
                        Ico { visible: !!root.page && root.page.type === "likes"; anchors.centerIn: parent; size: 60
                              src: "qrc:/VoltaApp/icons/heart-full.svg"; col: root.accent } }
                Column { x: 280; y: 14; width: parent.width - 300; spacing: 4
                    Text { text: root.page ? (root.page.type === "album" ? qsTr("ALBUM") : root.page.type === "artist" ? qsTr("ARTIST") : qsTr("PLAYLIST")) : ""
                           font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 1.2; color: Theme.textSecondary }
                    Text { width: parent.width; elide: Text.ElideRight; text: root.page ? root.page.title : ""; font.pixelSize: 34; font.weight: Font.Bold; color: Theme.textPrimary }
                    Text { width: parent.width; elide: Text.ElideRight; text: root.page ? root.page.sub : ""; font.pixelSize: 15; color: Theme.textSecondary }
                    Item { width: 1; height: 14 }
                    Row { spacing: 16
                        Rectangle { width: 60; height: 60; radius: 30; color: _pp.pressed ? Qt.darker(root.accent, 1.2) : root.accent
                            Ico { anchors.centerIn: parent; anchors.horizontalCenterOffset: 2; size: 26; src: "qrc:/VoltaApp/icons/play.svg"; col: "#FFFFFF" }
                            MouseArea { id: _pp; anchors.fill: parent; onClicked: root.playAll(root.page.ctx, false) } }
                        Rectangle { width: 52; height: 52; radius: 26; anchors.verticalCenter: parent.verticalCenter; color: "transparent"; border.width: 1.5; border.color: root.iconColor
                            Ico { anchors.centerIn: parent; size: 22; src: "qrc:/VoltaApp/icons/shuffle.svg"; col: Theme.textPrimary }
                            MouseArea { anchors.fill: parent; onClicked: root.playAll(root.page.ctx, true) } }
                    }
                }
            }
            ListView {
                anchors.top: _pgHead.bottom; anchors.bottom: parent.bottom; width: parent.width
                clip: true; boundsBehavior: Flickable.StopAtBounds; model: pageModel
                delegate: TrackRow { lm: pageModel; ctx: root.page ? root.page.ctx : "all"; inPlaylist: !!root.page && root.page.type === "playlist" }
                footer: Item { width: 1; height: 24 }
            }
        }
    }

    // ═════════ INTESTAZIONE ═════════
    Rectangle {
        id: _hdr; width: parent.width; height: root.headerH; z: 100; color: Theme.bg
        Row {
            anchors.left: parent.left; anchors.leftMargin: 20; y: (32 * root.u - height) / 2; spacing: 18
            Item {
                width: 29; height: 34; anchors.verticalCenter: parent.verticalCenter
                Image { anchors.verticalCenter: parent.verticalCenter; width: 29; height: 29; source: "qrc:/VoltaApp/icons/localmusic.svg"; sourceSize: Qt.size(58, 58); fillMode: Image.PreserveAspectFit }
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.appMenuOpen = !root.appMenuOpen }
            }
            Rectangle { width: 1; height: 21; color: root.dividerColor; anchors.verticalCenter: parent.verticalCenter }
            // Unified search (same magnifier as YT Music / Spotify / Podcasts)
            Item {
                width: 27; height: 27; anchors.verticalCenter: parent.verticalCenter
                Canvas {
                    anchors.fill: parent
                    property color col: root.lightTheme ? "#141414" : "#FFFFFF"
                    onColChanged: requestPaint(); onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
                    Component.onCompleted: requestPaint()
                    onPaint: {
                        var c = getContext("2d"); c.clearRect(0, 0, width, height)
                        var w = width, h = height
                        c.strokeStyle = col; c.lineCap = "round"; c.lineJoin = "round"; c.lineWidth = Math.max(1.6, w * 0.09)
                        c.beginPath(); c.arc(w * .44, h * .44, w * .26, 0, 2 * Math.PI); c.stroke()
                        c.beginPath(); c.moveTo(w * .63, h * .63); c.lineTo(w * .84, h * .84); c.stroke()
                    }
                }
                MouseArea { anchors.fill: parent; anchors.margins: -6
                            onClicked: { root.appMenuOpen = false; root.playerVisible = false; root.searchOpen = true } }
            }
            Rectangle { width: 1; height: 21; color: root.dividerColor; anchors.verticalCenter: parent.verticalCenter }
            // Coda unica
            Item {
                width: 27; height: 27; anchors.verticalCenter: parent.verticalCenter
                Canvas {
                    id: _qIcon
                    anchors.centerIn: parent; width: 22; height: 19.5
                    property color col: root.playerVisible ? root.selectedTextColor : root.iconColor
                    onColChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d"); c.clearRect(0, 0, width, height);
                        var k = width / 178;
                        c.save(); c.scale(k, k); c.translate(-19, -53);
                        c.fillStyle = col; c.strokeStyle = col; c.lineWidth = 10; c.lineJoin = "round"; c.lineCap = "round";
                        c.beginPath(); c.moveTo(29, 58); c.lineTo(63, 78); c.lineTo(29, 98); c.closePath(); c.fill(); c.stroke();
                        c.beginPath(); c.roundedRect(84, 66, 108, 24, 12, 12); c.fill();
                        c.beginPath(); c.roundedRect(24, 122, 168, 24, 12, 12); c.fill();
                        c.beginPath(); c.roundedRect(24, 182, 168, 24, 12, 12); c.fill();
                        c.restore();
                    }
                }
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: { root.appMenuOpen = false; root.searchOpen = false; root.playerVisible = !root.playerVisible } }
            }
            Rectangle { width: 1; height: 21; color: root.dividerColor; anchors.verticalCenter: parent.verticalCenter }
            Row {
                spacing: 20; anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: [{ id: "songs", text: qsTr("Tracks") }, { id: "albums", text: qsTr("Albums") }, { id: "artists", text: qsTr("Artists") },
                            { id: "playlists", text: qsTr("Playlist") }]
                    Item {
                        width: _tl.implicitWidth; height: 48
                        readonly property bool isSel: root.tab === modelData.id && !root.searchOpen && !root.playerVisible && !root.page
                        Text { id: _tl; anchors.centerIn: parent; text: modelData.text; color: parent.isSel ? root.selectedTextColor : root.iconColor; font.pixelSize: 20; font.weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; onClicked: root.setTab(modelData.id) }
                    }
                }
            }
        }
    }

    // ═════════ UNIFIED QUEUE (shared with YT Music / Spotify / Bluetooth) ═════════
    MediaQueuePanel {
        anchors.fill: parent; z: 80
        hub: root.hub
        lightTheme: root.lightTheme
        topPadding: root.headerH
        visible: root.hub !== null && root.playerVisible
        opacity: root.playerVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 240 } }
    }

    // ═════════ UNIFIED SEARCH (YT Music + Spotify + Music) ═════════
    MediaSearchPanel {
        id: _uSearch
        defaultFilter: "localmusic"
        anchors.fill: parent; z: 110
        hub: root.hub
        lightTheme: root.lightTheme
        headerH: root.headerH
        visible: root.hub !== null && root.searchOpen
        opacity: root.searchOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        onClosed: root.searchOpen = false
    }

    // ═════════ TRACK MENU (⋯) ═════════
    Item {
        anchors.fill: parent; z: 300; visible: !!root.menuTrack
        MouseArea { anchors.fill: parent; onClicked: root.menuTrack = null }
        Rectangle {
            anchors.centerIn: parent; width: 340; height: _mCol.height + 20; radius: 14
            color: root.lightTheme ? "#FFFFFF" : "#2A2A2A"; border.color: Theme.border; border.width: 1
            MouseArea { anchors.fill: parent }
            Column {
                id: _mCol; width: parent.width; y: 10
                Text { x: 18; width: parent.width - 36; elide: Text.ElideRight; height: 38; verticalAlignment: Text.AlignVCenter
                       text: root.menuTrack ? root.menuTrack.title : ""; font.pixelSize: 16; font.weight: Font.Bold; color: Theme.textSecondary }
                Rectangle { width: parent.width; height: 48; color: _m2.pressed ? Theme.surface : "transparent"
                    Text { x: 18; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Add to queue"); font.pixelSize: 17; color: Theme.textPrimary }
                    MouseArea { id: _m2; anchors.fill: parent; onClicked: { root.addToQueue(root.menuTrack); root.menuTrack = null } } }
                Rectangle { visible: !!root.menuTrack && root.menuTrack.inPlaylist; width: parent.width; height: visible ? 48 : 0; color: _m3.pressed ? Theme.surface : "transparent"
                    Text { x: 18; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Remove from this playlist"); font.pixelSize: 17; color: Theme.danger }
                    MouseArea { id: _m3; anchors.fill: parent
                                onClicked: { root.api("/playlists/remove?id=" + root.page.id + "&track=" + root.menuTrack.id, function() { root.openPage(root.page); root.loadPlaylists() }); root.menuTrack = null } } }
                Text { visible: root.playlists.length > 0; x: 18; height: 34; verticalAlignment: Text.AlignBottom; text: qsTr("Add to a playlist"); font.pixelSize: 13; font.weight: Font.Bold; color: Theme.textSecondary }
                Repeater {
                    model: root.playlists
                    Rectangle { width: _mCol.width; height: 46; color: _m4.pressed ? Theme.surface : "transparent"
                        Text { x: 18; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.pixelSize: 17; color: root.accent }
                        MouseArea { id: _m4; anchors.fill: parent
                                    onClicked: { root.api("/playlists/add?id=" + modelData.id + "&track=" + root.menuTrack.id, function() { root.toast(qsTr("Added to ") + modelData.name); root.loadPlaylists() }); root.menuTrack = null } } }
                }
                Item { width: 1; height: 6 }
            }
        }
    }

    // ═════════ MENU APP MUSICALI ═════════
    Item {
        anchors.fill: parent; z: 400; visible: root.appMenuOpen
        MouseArea { anchors.fill: parent; onClicked: root.appMenuOpen = false }
        Rectangle {
            x: 20; y: root.headerH - 6; width: 220; height: _menuCol.height + 12; radius: 10
            color: root.lightTheme ? "#FFFFFF" : "#2A2A2A"; border.color: Theme.border; border.width: 1
            MouseArea { anchors.fill: parent }
            Column {
                id: _menuCol; width: parent.width; y: 6
                Repeater {
                    model: root.musicApps
                    Rectangle {
                        width: _menuCol.width; height: 48; color: "transparent"
                        Row { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                            Image { source: modelData.icon; sourceSize: Qt.size(48, 48); width: 24; height: 24; fillMode: Image.PreserveAspectFit; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.name; color: root.selectedTextColor; font.pixelSize: 16; font.weight: modelData.appId === root.selfAppId ? Font.DemiBold : Font.Medium; anchors.verticalCenter: parent.verticalCenter } }
                        MouseArea { anchors.fill: parent; onClicked: { root.appMenuOpen = false; if (modelData.appId !== root.selfAppId) root.switchToApp(modelData.appId) } }
                    }
                }
            }
        }
    }

    // ═════════ Messaggio ═════════
    Rectangle {
        z: 500; visible: root.toastText !== ""; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 24
        radius: 8; color: "#E6000000"; width: _toastT.implicitWidth + 36; height: 42
        Text { id: _toastT; anchors.centerIn: parent; text: root.toastText; color: "white"; font.pixelSize: 15 }
    }
}
