import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtMultimedia
import Qt5Compat.GraphicalEffects
import QtCore

Rectangle {
    id: radioView
    property bool lightTheme: false
    // Without this, content taller than the available space overflows
    // beyond its own bounds instead of stopping — the margin reserved for
    // the dock in AppPanel.qml became useless (same bug already found
    // corretto in PhoneView).
    clip: true

    color: lightTheme ? "#FFFFFF" : "#171717"

    // ── SALVATAGGIO PERSISTENTE PREFERITI ──
    Settings {
        id: radioSettings
        category: "radio"
        property string favoritesJson: "[]"
        property string countryCode: ""          // chosen country (empty = the system's)
    }

    Component.onCompleted: {
        try {
            var loadedFavs = JSON.parse(radioSettings.favoritesJson);
            if (loadedFavs && Array.isArray(loadedFavs)) {
                radioView.favorites = loadedFavs;
            }
        } catch(e) {
            console.log("[Radio] Error loading favorites:", e);
        }
        radioView._initCountry()
    }

    property bool playing: false
    property var hub: null                 // MediaHub (unified queue), injected by AppPanel
    property bool queueVisible: false
    property var nowMap: ({})              // stationuuid -> what it is broadcasting (from the maps service)
    property string metaNow: ""            // dai metadati dello stream in ascolto
    function _cleanNow(t, name) {
        t = (t || "").replace(/^\s+|\s+$/g, "")
        if (t.length < 3 || t === "-" || t.toLowerCase() === (name || "").toLowerCase()) return ""
        return t
    }
    function nowFor(m) {
        var t = radioView.nowMap[m.stationuuid] || ""
        if (m.stationuuid === radioView.playingUuid && radioView.metaNow !== "") t = radioView.metaNow
        return t
    }
    function refreshNow() {
        var lists = [radioView.worldRadios, radioView.favorites, radioView.searchResult]
        var byUrl = {}, urls = []
        for (var l = 0; l < lists.length; l++) {
            var arr = lists[l] || []
            for (var i = 0; i < arr.length; i++) {
                var s = arr[i]
                if (!s || !s.url_resolved || s.url_resolved.indexOf(".m3u8") >= 0 || byUrl[s.url_resolved]) continue
                byUrl[s.url_resolved] = s; urls.push(s.url_resolved)
            }
        }
        if (urls.length === 0) return
        var q = []
        for (var k = 0; k < urls.length; k++) q.push("u=" + encodeURIComponent(urls[k]))
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "http://127.0.0.1:9098/radio-now?" + q.join("&"))
        xhr.timeout = 15000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return
            try {
                var d = JSON.parse(xhr.responseText), m = {}
                for (var u in d) {
                    var st = byUrl[u]
                    if (st) { var t = radioView._cleanNow(d[u], st.name); if (t !== "") m[st.stationuuid] = t }
                }
                radioView.nowMap = m
            } catch (e) {}
        }
        xhr.send()
    }
    Timer { interval: 60000; repeat: true; running: radioView.visible; triggeredOnStart: true; onTriggered: radioView.refreshNow() }
    onPlayingChanged: {
        if (playing) radioPlayer.play()
        else         radioPlayer.stop()      // live stream: it really stops, and on resume it restarts live
    }

    MediaPlayer {
        id: radioPlayer
        audioOutput: AudioOutput { id: audioOut; volume: 1.0 }
        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.PlayingState)
                radioView.playing = true
            else if (playbackState === MediaPlayer.PausedState || playbackState === MediaPlayer.StoppedState)
                radioView.playing = false
        }
        onMetaDataChanged: {
            var t = ""
            try { t = radioPlayer.metaData.stringValue(MediaMetaData.Title) || "" } catch (e) {}
            radioView.metaNow = radioView._cleanNow(t, radioView.playingName)
        }
        onErrorOccurred: function(error, errorString) {
            console.log("[Radio] stream error:", errorString)
            radioView._fallbackResolve(radioView._stationByUuid(radioView.playingUuid))
        }
    }

    // ── STATE ─────────────────────────────────────────────────────────────────
    property var searchResult:   []
    property var favorites:      []

    property string playingUrl:   ""
    property string playingName:  ""
    property string playingLogo:  ""
    property string playingUuid:  ""

    property string view:            "home" // "home" | "direct_tune" | "search"
    property string searchTerm:      ""
    property bool   searchExpanded:  false
    property string directTuneFreq:  ""

    property bool currentIsFav: false
    property var  playingStation: null          // stazione in onda (oggetto completo)
    // On air and among the favorites (for the mini player's heart)
    readonly property bool playingIsFav: radioView.playingUuid !== ""
        && radioView.favorites.some(function(f){ return f.stationuuid === radioView.playingUuid })

    function toggleFavCurrent() {
        if (radioView.playingUuid === "") return
        // It used to look for the station only among the "Italian Top": for those
        // found by search or direct tuning it did nothing
        var station = radioView.playingStation || _stationByUuid(radioView.playingUuid)
        if (station) toggleFav(station)
    }

    function toggleFav(station) {
        var idx = radioView.favorites.findIndex(function(f){ return f.stationuuid === station.stationuuid });
        var f = radioView.favorites.slice();
        if (idx >= 0) {
            f.splice(idx, 1);
        } else {
            f.push(station);
        }
        radioView.favorites = f;
        radioSettings.favoritesJson = JSON.stringify(f);

        if (radioView.playingUuid === station.stationuuid) {
            radioView.currentIsFav = (idx < 0);
        }
    }

    function isFav(station) {
        return radioView.favorites.some(function(f){ return f.stationuuid === station.stationuuid });
    }

    // ════════ RADIO FROM ALL OVER THE WORLD (local service :9098, source Radio Browser) ════════
    property string countryCode: "IT"
    property var    countryList: []            // [{ name, code, count }]
    property var    worldRadios: []            // stations of the chosen country (for Italy: the curated ones first)
    property bool   moreAvailable: false
    property bool   loadingStations: false
    property bool   countryPickerOpen: false
    property string countryFilter: ""
    property int    _stOffset: 0
    property int    _stSeq: 0
    readonly property string svcUrl: "http://127.0.0.1:9098"
    readonly property string countryName: {
        for (var i = 0; i < radioView.countryList.length; i++)
            if (radioView.countryList[i].code === radioView.countryCode) return radioView.countryList[i].name
        return radioView.countryCode
    }
    function logoSrc(m) {
        if (!m) return ""
        if (m.logoUrl) return m.logoUrl
        return m.logo ? radioView.logoBase + m.logo : ""
    }
    function _svcGet(path, cb) {
        var x = new XMLHttpRequest()
        x.open("GET", radioView.svcUrl + path)
        x.timeout = 20000
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return
            var d = null
            if (x.status === 200) { try { d = JSON.parse(x.responseText) } catch (e) {} }
            cb(d)
        }
        x.send()
    }
    function _initCountry() {
        var cc = radioSettings.countryCode
        if (!cc) { var parts = Qt.locale().name.split("_"); cc = (parts.length > 1 ? parts[1] : "IT").toUpperCase() }
        radioView.loadCountry(cc)
        radioView._svcGet("/radio/countries", function(d) { if (d && d.countries) radioView.countryList = d.countries })
    }
    function loadCountry(cc) {
        radioView.countryCode = cc
        radioSettings.countryCode = cc
        radioView.countryPickerOpen = false
        radioView.worldRadios = cc === "IT" ? radioView.italianTopRadios.slice() : []
        radioView._stOffset = 0
        radioView.moreAvailable = false
        radioView.fetchStations()
    }
    function fetchStations() {
        var seq = ++radioView._stSeq
        radioView.loadingStations = true
        radioView._svcGet("/radio/stations?cc=" + radioView.countryCode + "&limit=60&offset=" + radioView._stOffset, function(d) {
            if (seq !== radioView._stSeq) return
            radioView.loadingStations = false
            if (!d || !d.stations) { radioView.moreAvailable = false; return }
            var have = {}, cur = radioView.worldRadios.slice()
            for (var i = 0; i < cur.length; i++) have[cur[i].name.toLowerCase()] = true
            for (var k = 0; k < d.stations.length; k++) {
                var st = d.stations[k]
                if (have[st.name.toLowerCase()]) continue
                have[st.name.toLowerCase()] = true
                cur.push(st)
            }
            radioView.worldRadios = cur
            radioView._stOffset += 60
            radioView.moreAvailable = !!d.more
        })
    }
    function searchWorld(term) {
        var seq = ++radioView._stSeq
        radioView._svcGet("/radio/stations?q=" + encodeURIComponent(term) + "&limit=40", function(d) {
            if (seq !== radioView._stSeq || radioView.view !== "search" || radioView.searchTerm !== term) return
            if (!d || !d.stations) return
            var res = radioView.searchResult.slice(), have = {}
            for (var i = 0; i < res.length; i++) have[res[i].name.toLowerCase()] = true
            for (var k = 0; k < d.stations.length; k++) {
                if (have[d.stations[k].name.toLowerCase()]) continue
                res.push(d.stations[k])
            }
            radioView.searchResult = res
        })
    }
    Timer { id: worldSearchTimer; interval: 450; onTriggered: if (radioView.searchTerm.length >= 2) radioView.searchWorld(radioView.searchTerm) }

    // ── STATIC DATABASE OF ITALIAN STATIONS ────────────────────────────────
    property var italianTopRadios: [
        { name: "RTL 102.5",       url_resolved: "https://dd782ed59e2a4e86aabf6fc508674b59.msvdn.net/live/S97044836/tbbP8T1ZRPBL/playlist_audio.m3u8", logo: "75qudr7.png", stationuuid: "rtl1" },
        { name: "RDS",             url_resolved: "https://stream.rds.radio/audio/rds.stream_aac64/chunklist.m3u8", logo: "rds-logo.png", stationuuid: "rds2" },
        { name: "Radio Deejay",    url_resolved: "https://4c4b867c89244861ac216426883d1ad0.msvdn.net/radiodeejay/radiodeejay/master_ma.m3u8", logo: "radiodeejay.png", stationuuid: "dj3" },
        { name: "Radio 105",       url_resolved: "https://icecast.unitedradio.it/Radio105.mp3", logo: "radio105.png", stationuuid: "1054" },
        { name: "Radio Italia",    url_resolved: "https://radioitaliasmi.akamaized.net/hls/live/2093120/RISMI/stream01/streamPlaylist.m3u8", logo: "radioitalia.png", stationuuid: "ita5" },
        { name: "Radio Kiss Kiss", url_resolved: "https://kisskiss.fluidstream.eu/KissKiss.mp3", logo: "radiokisskiss.png", stationuuid: "kk6" },
        { name: "Virgin Radio",    url_resolved: "https://icecast.unitedradio.it/Virgin.mp3", logo: "virginradio.png", stationuuid: "vr7" },
        { name: "m2o",             url_resolved: "https://elemedia.akamaized.net/pool_1/mp3/m2o/m2o.mp3", logo: "m2o.png", stationuuid: "m2o8" },
        { name: "R101",            url_resolved: "https://icecast.unitedradio.it/R101.mp3", logo: "r101.png", stationuuid: "r1019" },
        { name: "Radio 24",        url_resolved: "https://shoutcast.radio24.it/radio24", logo: "radio24.png", stationuuid: "r2410" },
        { name: "Radio Capital",   url_resolved: "https://elemedia.akamaized.net/pool_1/mp3/RadioCapital/RadioCapital.mp3", logo: "radiocapital.png", stationuuid: "cap11" },
        { name: "RMC Monte Carlo", url_resolved: "https://icecast.unitedradio.it/RMC.mp3", logo: "rmcmontecarlo.png", stationuuid: "rmc13" },
        { name: "Rai Radio 1",     url_resolved: "https://icestreaming.rai.it/1.mp3", logo: "rairadio1.png", stationuuid: "rai1" },
        { name: "Rai Radio 2",     url_resolved: "https://icestreaming.rai.it/2.mp3", logo: "rairadio2.png", stationuuid: "rai2" },
        { name: "Rai Radio 3",     url_resolved: "https://icestreaming.rai.it/3.mp3", logo: "rairadio3.png", stationuuid: "rai3" },
        { name: "Radio Subasio",   url_resolved: "https://icecast.unitedradio.it/Subasio.mp3", logo: "radiosubasio.png", stationuuid: "sub17" },
        { name: "Radio Zeta",      url_resolved: "https://shoutcast.rtl.it/radiozeta", logo: "radiozeta.png", stationuuid: "zet18" },
        { name: "Radio Norba",     url_resolved: "https://edge.radionorba.it/Radionorba.mp3", logo: "radionorba.png", stationuuid: "nor19" },
        { name: "Radio Bruno",     url_resolved: "https://stream.radiobruno.it/bruno.mp3", logo: "radiobruno.png", stationuuid: "bru20" },
        { name: "Radio Sportiva",  url_resolved: "https://stream.radiosportiva.it/sportiva.mp3", logo: "radiosportiva.png", stationuuid: "spo21" },
        { name: "Radio Company",   url_resolved: "https://streaming.radiocompany.com/company.mp3", logo: "radiocompany.png", stationuuid: "com22" },
        { name: "Radio Ibiza",     url_resolved: "https://streaming.radioibiza.it/ibiza.mp3", logo: "radioibiza.png", stationuuid: "ibi23" },
        { name: "Radio Globo",     url_resolved: "https://stream.radioglobo.it/globo.mp3", logo: "radioglobo.png", stationuuid: "glo24" },
        { name: "Discoradio",      url_resolved: "https://stream.discoradio.it/discoradio.mp3", logo: "discoradio.png", stationuuid: "dis25" }
    ]

    function doSearch(term) {
        if (term.length < 2) { view = "home"; return; }
        view = "search";
        var t = term.toLowerCase(); var res = [];
        for (var i = 0; i < worldRadios.length; i++)
            if (worldRadios[i].name.toLowerCase().indexOf(t) >= 0) res.push(worldRadios[i]);
        radioView.searchResult = res;
        worldSearchTimer.restart();      // then search the whole world and add the results
    }

    readonly property string logoBase: appUrl + "/assets/radio_logos/"
    readonly property string rbApi: "https://de1.api.radio-browser.info"

    function _applyStation(station, streamUrl) {
        radioView.playingUrl   = streamUrl;
        radioView.playingName  = station.name;
        radioView.playingLogo  = radioView.logoSrc(station);
        radioView.playingUuid  = station.stationuuid;
        radioView.metaNow      = "";
        radioView.playingStation = station;
        radioPlayer.source     = streamUrl;
        radioPlayer.play();
        radioView.playing      = true;
        radioView.currentIsFav = radioView.isFav(station);
    }

    function playStation(station) {
        if (radioView.playingUuid === station.stationuuid && radioView.playing) {
            radioPlayer.stop();
            radioView.playingUrl = ""; radioView.playingUuid = ""; radioView.playing = false;
            return;
        }
        radioView._retriedStation = "";
        radioView._applyStation(station, station.url_resolved);
    }

    // Resume at startup (see Main.qml tryResumePlayback()): unlike
    // playStation() it does not "switch off" if the requested station is the one
    // already on air — at startup nothing is playing, so it is not needed,
    // here we only need to start, never stop.
    function resumeStation(station) {
        if (!station || !station.url_resolved) return;
        radioView._retriedStation = "";
        radioView._applyStation(station, station.url_resolved);
    }

    property string _retriedStation: ""
    function _fallbackResolve(station) {
        if (!station) return;
        if (radioView._retriedStation === station.stationuuid) return;
        radioView._retriedStation = station.stationuuid;
        var xhr = new XMLHttpRequest();
        var api = radioView.rbApi
                + "/json/stations/search?limit=1&hidebroken=true&order=votes&reverse=true"
                + "&countrycode=" + (station.countrycode || radioView.countryCode) + "&name=" + encodeURIComponent(station.name);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            try {
                if (xhr.status === 200) {
                    var arr = JSON.parse(xhr.responseText);
                    if (arr && arr.length > 0 && arr[0].url_resolved
                        && arr[0].url_resolved !== station.url_resolved) {
                        radioView._applyStation(station, arr[0].url_resolved);
                    }
                }
            } catch (e) {}
        };
        xhr.open("GET", api);
        xhr.send();
    }

    function _stationByUuid(uuid) {
        var lists = [radioView.worldRadios, radioView.favorites, radioView.searchResult]
        for (var l = 0; l < lists.length; l++) {
            var arr = lists[l] || []
            for (var i = 0; i < arr.length; i++)
                if (arr[i].stationuuid === uuid) return arr[i];
        }
        return null;
    }

    // ════════ SCELTA DEL PAESE ════════
    Rectangle {
        id: countryPicker
        z: 20
        visible: radioView.countryPickerOpen
        x: 0; y: navbar.height; width: parent.width; height: parent.height - navbar.height
        color: lightTheme ? "#FFFFFF" : "#171717"
        MouseArea { anchors.fill: parent }          // do not let touches through to the grid

        Rectangle {
            id: ccSearchBox
            x: 32; y: 14; width: parent.width - 64; height: 44; radius: 10
            color: lightTheme ? "#F0F0F0" : "#262626"
            TextInput {
                id: ccSearch
                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                verticalAlignment: TextInput.AlignVCenter
                color: lightTheme ? "#141414" : "#FFFFFF"; font.pixelSize: 17
                onTextChanged: radioView.countryFilter = text.toLowerCase()
                Text { visible: parent.text === ""; text: qsTr("Search for a country…"); color: "#757575"
                       font.pixelSize: 17; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        ListView {
            x: 32; y: 70; width: parent.width - 64; height: parent.height - 80
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: radioView.countryList.filter(function(c) {
                return radioView.countryFilter === "" || c.name.toLowerCase().indexOf(radioView.countryFilter) >= 0
                       || c.code.toLowerCase() === radioView.countryFilter })
            delegate: Rectangle {
                width: ListView.view.width; height: 46; radius: 8
                color: _ccMA.pressed ? (lightTheme ? "#E8E8E8" : "#2A2A2A") : (modelData.code === radioView.countryCode ? (lightTheme ? "#F0F0F0" : "#262626") : "transparent")
                Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData.name
                       color: lightTheme ? "#171717" : "#FFFFFF"; font.pixelSize: 17 }
                Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                       text: modelData.count; color: lightTheme ? "#6E6E6E" : "#A2A3A5"; font.pixelSize: 14 }
                MouseArea { id: _ccMA; anchors.fill: parent; onClicked: radioView.loadCountry(modelData.code) }
            }
        }
    }

    // ════════ UNIFIED QUEUE (shared with Spotify / YT Music / Bluetooth) ════════
    MediaQueuePanel {
        anchors.fill: parent; z: 1
        hub: radioView.hub
        lightTheme: radioView.lightTheme
        topPadding: navbar.height
        visible: radioView.hub !== null && radioView.queueVisible
    }

    Column {
        id: mainCol
        z: 2
        anchors.fill: parent

        // ── NAVBAR STILE TESLA ─────────────────────────────
        Rectangle {
            id: navbar
            width: parent.width; height: 38 * ((Window.window && Window.window.uPx) ? Window.window.uPx : 1.12); color: "transparent"; z: 2

            Row {
                y: (32 * ((Window.window && Window.window.uPx) ? Window.window.uPx : 1.12) - height) / 2
                anchors.left: parent.left
                anchors.leftMargin: 20
                spacing: 16

                // 1. Radio icon (first element on the left) (Original, no color filter)
                Item {
                    width: 26; height: 26
                    anchors.verticalCenter: parent.verticalCenter
                    Image { sourceSize: Qt.size(width * 2, height * 2);
                        id: radioIconImg
                        source: "qrc:/VoltaApp/icons/radio.svg"
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        visible: true
                    }
                }

                // 3. Separatore
                Rectangle {
                    width: 1; height: 18
                    color: lightTheme ? "#777777" : "#414141"
                    anchors.verticalCenter: parent.verticalCenter
                }

                // 2. Search: magnifier
                Item {
                    width: 27; height: 27
                    anchors.verticalCenter: parent.verticalCenter
                    Image { sourceSize: Qt.size(width * 2, height * 2);
                        id: searchIconImg
                        source: "qrc:/VoltaApp/icons/Icons_search_black.svg"
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        visible: false
                    }
                    ColorOverlay {
                        anchors.fill: searchIconImg
                        source: searchIconImg
                        color: lightTheme ? "#141414" : "#FFFFFF"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            radioView.queueVisible = false
                            radioView.searchExpanded = !radioView.searchExpanded
                            if (radioView.searchExpanded) {
                                radioSearch.forceActiveFocus()
                                radioView.view = "search"
                            } else {
                                radioSearch.text = ""
                                radioView.view = "home"
                            }
                        }
                    }
                }

                // 2. Animated text field
                Item {
                    width: radioView.searchExpanded ? 180 : 0
                    visible: width > 0
                    height: 30
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                    TextInput {
                        id: radioSearch
                        width: 180
                        anchors.verticalCenter: parent.verticalCenter
                        color: lightTheme ? "#555555" : "#FFFFFF" // Grigio scuro
                        font.pixelSize: 18
                        onTextChanged: { radioView.searchTerm = text; radioView.doSearch(text) }
                        Text {
                            visible: parent.text === ""
                            text: qsTr("Search...")
                            color: "#757575"
                            font.pixelSize: 18
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // Separatore
                Rectangle {
                    width: 1; height: 18
                    color: lightTheme ? "#777777" : "#414141"
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Queue (the same as YT Music / Spotify / Bluetooth)
                Item {
                    width: 27; height: 27
                    anchors.verticalCenter: parent.verticalCenter
                    Canvas {
                        anchors.centerIn: parent; width: 22; height: 19.5
                        property color col: lightTheme ? "#141414" : "#FFFFFF"
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
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -6
                        onClicked: { radioView.searchExpanded = false; radioSearch.text = ""; radioView.queueVisible = !radioView.queueVisible }
                    }
                }

                // Country: tap to change (radio from all over the world)
                Rectangle {
                    width: _ccTxt.implicitWidth + 22; height: 28; radius: 14
                    anchors.verticalCenter: parent.verticalCenter
                    color: radioView.countryPickerOpen ? (lightTheme ? "#DDDDDD" : "#3A3A3A") : (lightTheme ? "#EFEFEF" : "#2A2A2A")
                    Text { id: _ccTxt; anchors.centerIn: parent; text: radioView.countryCode + " ▾"
                           color: lightTheme ? "#141414" : "#FFFFFF"; font.pixelSize: 15; font.weight: Font.Medium }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -6
                        onClicked: { radioView.queueVisible = false; radioView.searchExpanded = false; radioView.countryFilter = ""
                                     radioView.countryPickerOpen = !radioView.countryPickerOpen }
                    }
                }

                // 5. Separatore
                Rectangle {
                    width: 1; height: 18
                    color: lightTheme ? "#777777" : "#414141"
                    anchors.verticalCenter: parent.verticalCenter
                }

                // 6. Tabs (Stazioni e Sintonia)
                Repeater {
                    model: [
                        { id: "home",        label: qsTr("Stations") },
                        { id: "direct_tune", label: qsTr("Direct tuning") }
                    ]
                    Rectangle {
                        width: _tabLbl.implicitWidth
                        height: 44
                        color: "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            id: _tabLbl
                            anchors.centerIn: parent
                            text: modelData.label
                            color: radioView.view === modelData.id
                                   ? (lightTheme ? "#444444" : "#FFFFFF")
                                   : (lightTheme ? "#555555" : "#A2A3A5")
                            font.pixelSize: 18
                            // Bold removed, uses Medium for the active tab and Normal otherwise
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                radioView.queueVisible = false
                                radioView.view = modelData.id
                                if (modelData.id !== "search") {
                                    radioView.searchExpanded = false
                                    radioSearch.text = ""
                                }
                            }
                        }
                    }
                }
            }
        }

        // ═════════════════════════════════════════════════════════════════════
        //  VISTA 1: STAZIONI RADIO
        // ═════════════════════════════════════════════════════════════════════
        Flickable {
            visible: radioView.view !== "direct_tune" && !radioView.queueVisible
            width: parent.width; height: parent.height - navbar.height
            contentHeight: stationGrid.height + 60; clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: stationGrid
                width: parent.width; topPadding: 18
                spacing: 40

                // --- SEZIONE PREFERITI ---
                Column {
                    width: parent.width
                    visible: radioView.view === "home" && radioView.favorites.length > 0
                    spacing: 16

                    Text {
                        text: qsTr("Favorites")
                        color: lightTheme ? "#171717" : "#FFFFFF"
                        font.pixelSize: 22; font.weight: Font.Medium // Rimosso Bold
                        leftPadding: 32
                    }

                    ListView {
                        width: parent.width; height: 160
                        orientation: ListView.Horizontal
                        spacing: 16
                        leftMargin: 32; rightMargin: 32
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: radioView.favorites

                        delegate: Item {
                            width: 140; height: 160

                            Rectangle {
                                width: 140; height: 140
                                radius: 8
                                color: lightTheme ? "#F0F0F0" : "#2A2A2A"
                                border.width: (radioView.playingUuid === modelData.stationuuid && radioView.playing) ? 2 : 0
                                border.color: lightTheme ? "#171717" : "#FFFFFF"

                                Image {
                                    id: favLogo
                                    anchors.fill: parent; anchors.margins: 1
                                    source: radioView.logoSrc(modelData)
                                    fillMode: Image.PreserveAspectFit
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle { width: favLogo.width; height: favLogo.height; radius: 8 }
                                    }
                                }

                                // OVERLAY VOLUME (NIENTE EMOJI)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: "#B3000000"
                                    visible: radioView.playingUuid === modelData.stationuuid && radioView.playing

                                    Canvas {
                                        anchors.centerIn: parent
                                        width: 24; height: 24
                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.clearRect(0, 0, width, height)
                                            ctx.fillStyle = "#FFFFFF"
                                            ctx.beginPath()
                                            ctx.moveTo(6, 9)
                                            ctx.lineTo(6, 15)
                                            ctx.lineTo(10, 15)
                                            ctx.lineTo(14, 19)
                                            ctx.lineTo(14, 5)
                                            ctx.lineTo(10, 9)
                                            ctx.closePath()
                                            ctx.fill()

                                            ctx.strokeStyle = "#FFFFFF"
                                            ctx.lineWidth = 2
                                            ctx.lineCap = "round"
                                            ctx.beginPath()
                                            ctx.arc(14, 12, 4, -Math.PI/3, Math.PI/3)
                                            ctx.stroke()
                                            ctx.beginPath()
                                            ctx.arc(14, 12, 8, -Math.PI/3, Math.PI/3)
                                            ctx.stroke()
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: radioView.playStation(modelData)
                                }
                            }

                            Text {
                                anchors.bottom: parent.bottom
                                text: modelData.name || ""
                                color: lightTheme ? "#171717" : "#FFFFFF"
                                font.pixelSize: 15; font.weight: Font.Medium // Rimosso DemiBold
                                width: parent.width; elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                } // Fine Preferiti

                // --- ALL STATIONS / SEARCH SECTION ---
                Column {
                    width: parent.width
                    spacing: 16

                    Text {
                        visible: radioView.view === "search" && radioView.searchTerm.length > 0
                        text: qsTr("Results for: ") + radioView.searchTerm
                        color: lightTheme ? "#171717" : "#FFFFFF"
                        font.pixelSize: 22; font.weight: Font.Medium // Rimosso Bold
                        leftPadding: 32
                    }

                    Text {
                        visible: radioView.view === "home"
                        text: qsTr("Stations") + " · " + radioView.countryName
                        color: lightTheme ? "#171717" : "#FFFFFF"
                        font.pixelSize: 22; font.weight: Font.Medium // Rimosso Bold
                        leftPadding: 32
                    }

                    Grid {
                        id: radioGrid
                        x: 32; width: parent.width - 64
                        columns: 3
                        columnSpacing: 16
                        rowSpacing: 16

                        readonly property real cellW: (width - (columns - 1) * columnSpacing) / columns
                        readonly property var activeList: radioView.view === "search"
                                                         ? radioView.searchResult
                                                         : radioView.worldRadios

                        Repeater {
                            model: radioGrid.activeList

                            Rectangle {
                                id: _cell
                                width: radioGrid.cellW; height: 90
                                radius: 8

                                readonly property bool isPlayingThis: radioView.playingUuid === modelData.stationuuid && radioView.playing

                                color: isPlayingThis
                                       ? (lightTheme ? "#DCDCDC" : "#333333")
                                       : (_cellMA.pressed ? (lightTheme ? "#EAEAEA" : "#222222") : "transparent")

                                Row {
                                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 16

                                    Rectangle {
                                        width: 66; height: 66
                                        radius: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: lightTheme ? "#F0F0F0" : "#2A2A2A"

                                        Image {
                                            id: _cellLogo
                                            anchors.fill: parent; anchors.margins: 2
                                            source: radioView.logoSrc(modelData)
                                            fillMode: Image.PreserveAspectFit
                                            layer.enabled: true
                                            layer.effect: OpacityMask {
                                                maskSource: Rectangle { width: _cellLogo.width; height: _cellLogo.height; radius: 6 }
                                            }
                                        }

                                        Text {
                                            visible: _cellLogo.status === Image.Error
                                            anchors.centerIn: parent
                                            text: modelData.name ? modelData.name.charAt(0) : "R"
                                            color: lightTheme ? "#A2A3A5" : "#555"; font.pixelSize: 28; font.weight: Font.Medium
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                        width: parent.width - 66 - 16

                                        Text {
                                            text: modelData.name || ""
                                            color: lightTheme ? "#171717" : "#FFFFFF"
                                            font.pixelSize: 16; font.weight: Font.Medium // Rimosso Bold
                                            width: parent.width; elide: Text.ElideRight
                                        }
                                        Text {
                                            visible: text !== ""
                                            text: radioView.nowFor(modelData) || (radioView.view === "search" ? (modelData.country || "") : "")
                                            color: lightTheme ? "#6E6E6E" : "#A2A3A5"
                                            font.pixelSize: 12
                                            width: parent.width; elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                    }
                                }

                                MouseArea {
                                    id: _cellMA; anchors.fill: parent
                                    onClicked: radioView.playStation(modelData)
                                }
                            }
                        }
                    }

                    Text {
                        visible: radioView.view === "home" && radioView.loadingStations
                        text: qsTr("Loading…")
                        color: lightTheme ? "#A2A3A5" : "#777"
                        font.pixelSize: 16; leftPadding: 32
                    }
                    Rectangle {
                        visible: radioView.view === "home" && radioView.moreAvailable && !radioView.loadingStations
                        x: 32; width: parent.width - 64; height: 48; radius: 8
                        color: _moreMA.pressed ? (lightTheme ? "#E4E4E4" : "#2E2E2E") : (lightTheme ? "#F0F0F0" : "#262626")
                        Text { anchors.centerIn: parent; text: qsTr("Show more stations")
                               color: lightTheme ? "#171717" : "#FFFFFF"; font.pixelSize: 16; font.weight: Font.Medium }
                        MouseArea { id: _moreMA; anchors.fill: parent; onClicked: radioView.fetchStations() }
                    }
                    Text {
                        visible: radioGrid.activeList.length === 0 && radioView.view === "search"
                        text: qsTr("No radio found")
                        color: lightTheme ? "#A2A3A5" : "#555"
                        font.pixelSize: 16; leftPadding: 32
                        width: parent.width - 64; wrapMode: Text.Wrap
                    }
                } // End of "All stations"
            }
        }

        // ═════════════════════════════════════════════════════════════════════
        //  VISTA 2: SINTONIA DIRETTA (Direct Tune)
        // ═════════════════════════════════════════════════════════════════════
        Item {
            visible: radioView.view === "direct_tune" && !radioView.queueVisible
            width: parent.width; height: parent.height - navbar.height

            Item {
                width: 280; height: 380
                anchors.centerIn: parent

                Item {
                    width: 40; height: 30
                    anchors.top: parent.top
                    anchors.right: parent.right

                    Text {
                        anchors.centerIn: parent
                        text: "←"
                        color: lightTheme ? "#171717" : "#FFFFFF"
                        font.pixelSize: 26
                        font.weight: Font.Medium // Rimosso Bold
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (radioView.directTuneFreq.length > 0)
                                radioView.directTuneFreq = radioView.directTuneFreq.substring(0, radioView.directTuneFreq.length - 1)
                        }
                    }
                }

                Grid {
                    id: numGrid
                    anchors.top: parent.top
                    anchors.topMargin: 40
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: 3
                    columnSpacing: 45
                    rowSpacing: 25

                    Repeater {
                        model: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

                        Item {
                            width: 50; height: 45

                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                color: lightTheme ? "#171717" : "#FFFFFF"
                                font.pixelSize: 28
                                font.weight: Font.Medium // Rimosso Bold
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: radioView.directTuneFreq += modelData
                            }
                        }
                    }
                }

                Item {
                    id: zeroKey
                    anchors.top: numGrid.bottom
                    anchors.topMargin: 20
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 50; height: 45

                    Text {
                        anchors.centerIn: parent
                        text: "0"
                        color: lightTheme ? "#171717" : "#FFFFFF"
                        font.pixelSize: 28
                        font.weight: Font.Medium // Rimosso Bold
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: radioView.directTuneFreq += "0"
                    }
                }

                Rectangle {
                    anchors.top: zeroKey.bottom
                    anchors.topMargin: 30
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 180; height: 44
                    radius: 8
                    color: lightTheme ? "#D0D0D0" : "#383838"

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Tune in")
                        color: lightTheme ? "#171717" : "#A2A3A5"
                        font.pixelSize: 16
                        font.weight: Font.Medium // Rimosso DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            console.log("[Radio] Direct tuning on frequency:", radioView.directTuneFreq)
                        }
                    }
                }
            }
        }
    }
}