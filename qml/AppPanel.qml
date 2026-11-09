import QtQuick
import QtQuick.Window
import QtWebEngine
import QtCore
import VoltaApp 1.0

Rectangle {
    property bool lightTheme: Window.window.lightTheme
    id: panel

    // Panel background color tied to the REAL one of the open
    // app (each has a slightly different shade: Settings
    // #EFEFEF, Messaggi #FFFFFF, Radio #F2F2F2, dashboard musicali
    // Theme.bg #FFFFFF, Theater #F5F5F5/#262626, app native nere...).
    // Before, the panel always used the same fixed gray: the handle strip
    // at the top (30px, see topHandle) and the margin below the
    // dock therefore ended up a slightly different color from that of
    // the app underneath, creating a visible "rectangle" around
    // the handle pill. Now the handle strip is always
    // the same color as the open app, so the pill seems
    // have a transparent background.
    function appBgColor(appId) {
        switch (appId) {
        case "settings":
        case "phone":       return lightTheme ? "#FFFFFF" : "#171717"
        case "radio":       return lightTheme ? "#FFFFFF" : "#171717"
        case "messages":    return lightTheme ? "#FFFFFF" : "#171717"
        case "spotify":
        case "spotifyapp":  return lightTheme ? "#FFFFFF" : "#171717"
        case "podcast":     return lightTheme ? "#FFFFFF" : "#171717"
        case "localmusic":  return lightTheme ? "#FFFFFF" : "#171717"
        case "theater":     return lightTheme ? "#F5F5F5" : "#262626"
        case "arcade":      return arcadeItem.currentUrl !== "" ? "#000000" : (lightTheme ? "#FFFFFF" : "#171717")
        case "toybox":      return lightTheme ? "#FFFFFF" : "#171717"
        case "calendar":
        case "bluetooth":   return lightTheme ? "#FFFFFF" : "#171717"
        case "camera":
        case "androidauto":
        case "browser":
        case "gnome-video": return "#000000"
        default:            return lightTheme ? "#FFFFFF" : "#171717"
        }
    }
    color: panel.appBgColor(panel.activeApp)

    // Toybox (full-screen Romance screen) asks to hide the
    // handle pill at the top completely for a real
    // edge-to-edge display: see topHandle below and toyboxView.immersiveActive.
    readonly property bool hideTopHandle: panel.activeApp === "toybox" && toyboxView.immersiveActive

    // Site opened in Theater (or web game in Arcade): the top bar becomes that of the full-screen games
    readonly property bool siteBarOpen: (panel.activeApp === "arcade"  && arcadeItem.currentUrl !== "")

    // ══════════════════════════════════════════════════════════════════
    //  STRUCTURAL RULE — the dock must NEVER cover the content of
    //  an app: it must sit there as a fixed margin of the UI, not as a
    //  layer floating above thanks to z-order alone. Any app view
    //  added here (new or existing) MUST have:
    //
    //    anchors.fill: parent
    //    anchors.bottomMargin: panel.bottomInset
    //    Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
    //
    //  6 views that did not do so were found and fixed (PhoneView,
    //  RadioView, YtMusicDashboard, SpotifyDashboard, Settings,
    //  gnomeVideoView) — their content really ended up under the dock,
    //  not just visually covered. An element NESTED inside a view
    //  that already follows this rule (e.g. NativeAppView inside
    //  androidAutoView) does not need its own margin: it automatically
    //  inherits the parent's already reduced size.
    // ══════════════════════════════════════════════════════════════════

    // ESSENTIAL: Masks the excess content without squashing it
    clip: true

    Item {
        anchors.fill: parent
        z: -1
        // grabPermissions: TakeOverForbidden — WITHOUT this, these handlers
        // (which cover the WHOLE app panel) can "steal" the mouse grab
        // from another MouseArea/Handler already active elsewhere (e.g. the
        // drag of an icon from the drawer) as soon as the cursor
        // crosses them: it is the most likely cause of the drag
        // "breaking" only over an open app/the map (where there is nothing
        // similar) and not over the car panel. By denying the possibility of
        // "taking over" a grab already assigned to others, these
        // handlers stay harmless for their original purpose (absorbing
        // drag/wheel/tap when NOBODY already has the grab) but no longer interfere
        // with a drag started elsewhere.
        DragHandler { target: null; grabPermissions: PointerHandler.TakeOverForbidden }
        WheelHandler { target: null; onWheel: (event) => { event.accepted = true } }
        TapHandler { target: null; grabPermissions: PointerHandler.TakeOverForbidden }
        MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons; preventStealing: true }
    }

    property var nativeSurfaces:  ({})
    property var nativeToplevels: ({})
    property var nativeShells:    ({})

    // round78: exposes the Arcade instance to whoever is outside this file —
    // Main.qml needs it for the full-screen game panel (gameOverlay),
    // which must read the state (nativeGameRunning, nativeGameName...) and
    // call arcadeItem.stopNativeGame(). WITHOUT this line the game panel
    // never opens (only the audio is heard).
    property alias arcadeItem: arcadeItem

    property int dockHeight: 72
    property bool appFullscreen: false

    // Space to leave free at the bottom for each app. The dock's height
    // is not enough: appWrapper has a fixed height (maxHeight − handle, so as not to
    // make Chromium recompute the layout) that is TALLER than the panel
    // when it is not full screen (the panel starts 47px lower).
    // That difference ended up hidden under the dock, together with the bottom of
    // Toybox, Arcade and the other apps. Here we add it to the margin.
    readonly property real overflowBelow: Math.max(0, topHandle.height + appWrapper.height - panel.height)
    readonly property real bottomInset: appFullscreen ? 0 : dockHeight + overflowBelow

    signal fullscreenToggle()
    signal romanceRequested()
    property Item fullHost: null
    signal requestAppFullscreen(bool on)

    property real minHeight: 0
    property real maxHeight: parent ? parent.height : 800
    height: minHeight
    property bool isDragging: false
    property bool gripDragging: false     // drag started from the band below the strip

    // The animation ALWAYS reacts, except when your finger is dragging
    Behavior on height {
        enabled: !panel.isDragging
        NumberAnimation { duration: 350; easing.type: Easing.OutQuint }
    }

    signal radioPlayingUpdated(bool val)
    signal sourceActivated(string src)
    signal settingsTheme(string mode, string autoStart, string autoEnd)
    signal settingsMirror(bool rightHand)
    signal settingsAmbient(color c)
    signal settingsAmbientMode(string mode)
    signal settingsAmbientBrightness(int val)
    signal settingsCarColor(color c)
    signal settingsCarFinish(string finish)
    // Toybox: global modes handled by Main.qml
    property bool marsMode: false
    signal marsModeRequested(bool on)
    signal settingsLowPower(bool on)
    signal settingsBrightness(int val)
    signal settingsBlueLight(bool on)
    signal settingsSatNight(string mode)
    signal settingsScreenClean()
    signal settingsAppVisibility(string hiddenCsv)
    signal settingsPhoneDest()
    signal settingsFullScreenMap(bool on)
    signal metaUpdated(string src, var meta)
    signal dragHandlePressed(real globalY)
    signal dragHandleMoved(real globalY)
    signal dragHandleReleased()
    signal openSearch()
    signal requestSwitchApp(string appId)
    signal audioSourceActivated(string source)   // emitted only when a source REALLY starts playing

    // an on-demand service is ready: its app reloads the data
    function serviceReady(name) {
        if (name === "ytmusic") { spotifyDash.checkAuthStatus(); spotifyDash.loadAll() }
        else if (name === "spotify") spotifyAppDash.loadAll()
    }

    function reloadAll() {
        var ids = ["theater", "arcade", "browser", "music", "spotify"]
        for (var i = 0; i < ids.length; i++) {
            var v = getWebView(ids[i])
            if (v && v.reload) v.reload()
        }
    }
    function reloadSpotify() {
        if (typeof spotifyDash !== "undefined") {
            spotifyDash.loadAll()
        }
    }

    property bool   radioIsPlaying: radioViewItem.playing
    property string radioTitle:     radioViewItem.playingName
    property string spotifyQmlTrack:   ""
    property string spotifyQmlArtist:  ""
    property string spotifyQmlCover:   ""
    property bool   spotifyQmlPlaying: false
    property real   spotifyQmlProgressPct: {
        if (panel.audioSrc === "spotify" && spotifyAppDash.durationMs > 0)
            return spotifyAppDash.progressMs / spotifyAppDash.durationMs
        if (panel.audioSrc === "ytmusic" && spotifyDash.durationMs > 0)
            return spotifyDash.progressMs / spotifyDash.durationMs
        return 0
    }

    function spotifyToggle() {
        if (panel.activeApp === "spotifyapp") spotifyAppDash.togglePlay()
        else spotifyDash.togglePlay()
    }
    function spotifyNext()        { spotifyDash.nextTrack() }
    function spotifyPrev()        { spotifyDash.prevTrack() }
    function spotifySeekPct(p)    { spotifyDash.seekPct(p) }
    function spotifyShuffle()     { spotifyDash.shuffleQueue() }

    // ── Updates from the YT Music / Spotify players to the mini player ──
    // When switching player the old one, just paused, kept saying
    // "I'm playing" for 2-3 seconds (late state): the widget went back
    // to its song and then again to the new one. Now:
    //  • for 4 s after the pause its "I'm playing" are ignored;
    //  • a player that is not the current source does not touch title/cover
    //    until it really starts playing.
    property var _pausedByUs: ({})
    function markPausedByUs(src) { var m = panel._pausedByUs; m[src] = Date.now(); panel._pausedByUs = m }
    function dashPlayback(src, track, artist, cover, playing) {
        var t = panel._pausedByUs[src] || 0
        if (src !== panel.audioSrc) {
            if (!playing) return
            if (Date.now() - t < 4000) return
        }
        if (playing) panel._pausedByUs[src] = 0
        panel.spotifyQmlTrack   = track
        panel.spotifyQmlArtist  = artist
        panel.spotifyQmlCover   = cover
        panel.spotifyQmlPlaying = playing
        // With the system player active for this source it is the one that says who
        // suona (Mpris.sourceStartedPlaying in Main): niente doppio cambio
        if (playing && src !== panel.audioSrc && !(typeof Mpris !== "undefined" && Mpris.hasSource(src)))
            panel.audioSourceActivated(src)
    }

    property string audioOwner: ""

    // ── Single multimedia system (see MediaHub.qml) ──
    readonly property var hub: mediaHub
    readonly property bool phoneConnected: mediaHub.phoneConnected
    // No warning until the Bluetooth service has answered at least once
    readonly property bool showPhoneRequired: mediaHub.devicesLoaded && !mediaHub.phoneConnected

    // Settings › Audio › Equalizer (EQ button of the mini player)
    function openEqualizer() {
        panel._settingsTarget = true; _settingsTargetClear.restart()
        panel.requestSwitchApp("settings")
        settingsView.openAudioTab(1)
    }

    // Radio: is the station on air among the favorites? (mini player's heart)
    readonly property bool radioIsFav: radioViewItem.playingIsFav
    function radioToggleFav() { radioViewItem.toggleFavCurrent() }

    // Opens the Settings directly on a page (e.g. "Bluetooth")
    function openSettingsPage(name) {
        panel._settingsTarget = true; _settingsTargetClear.restart()
        panel.requestSwitchApp("settings")
        var i = settingsView.pages.indexOf(name)
        if (i >= 0) settingsView.pageIdx = i
    }

    // Music commands per source: YT Music, Spotify and phone go through the
    // unified queue (MediaHub → MPRIS system player), the radio through its view
    readonly property var _providers: ["ytmusic", "spotify", "bluetooth"]
    function musicToggle(o) {
        if (panel._providers.indexOf(o) >= 0) mediaHub.togglePlay(o)
        else if (o === "radio") radioTogglePlay()
    }
    function musicNext(o) {
        if (panel._providers.indexOf(o) >= 0) mediaHub.next(o)
        else if (o === "radio") radioNext()
    }
    function musicPrev(o) {
        if (panel._providers.indexOf(o) >= 0) mediaHub.prev(o)
        else if (o === "radio") radioPrev()
    }
    function musicSeekPct(o, p) {
        if (o === "spotify" || o === "ytmusic") mediaHub.seekPct(p, o)
    }
    function musicShuffle(o) { mediaHub.toggleShuffle() }

    function spotifyOpenSearch() {
        panel.requestSwitchApp("spotify")
        spotifyDash.searchExpanded = true
    }

    // dl69: opens "Now playing + Queue" of the app that is playing (tap on the music widget)
    function localMusicOpenSearch() { mediaHub.requestLm("search") }
    function openNowPlaying() {
        var s = panel.audioSrc
        if (s === "radio") { panel.requestSwitchApp("radio"); return }
        if (mediaHub.activeProvider === "localmusic") { mediaHub.requestLm("queue"); return }
        if (s === "bluetooth") {
            panel.requestSwitchApp("bluetooth")
            bluetoothView.searchExpanded = false; bluetoothView.playerVisible = true
            return
        }
        var dash = (s === "spotify") ? spotifyAppDash : spotifyDash
        panel.requestSwitchApp(s === "spotify" ? "spotifyapp" : "spotify")
        dash.searchExpanded = false; dash.detailVisible = false; dash.artistVisible = false; dash.playerVisible = true
    }

    function ytmusicOpenSearch() {
        // The YT Music app has id "spotify" (historical name): with "ytmusic" nothing opened
        panel.requestSwitchApp("spotify")
        spotifyDash.searchExpanded = true      // unified search (YT Music + Spotify)
    }

    // ── Lyrics: inside the music app (in the background if you close it: you find them again on reopening) ──
    function _lyricsDash(src) { return src === "ytmusic" ? spotifyDash : (src === "spotify" ? spotifyAppDash : null) }
    function _lyricsAppId(src) { return src === "ytmusic" ? "spotify" : "spotifyapp" }   // YT Music has id "spotify" (historical name)
    // dashboard that has the lyrics open (null = none)
    readonly property var lyricsDash: spotifyDash.lyricsOpen ? spotifyDash : (spotifyAppDash.lyricsOpen ? spotifyAppDash : null)
    function lyricsShownFor(src) {
        var d = panel._lyricsDash(src)
        return !!d && d.lyricsOpen && panel.activeApp === panel._lyricsAppId(src)
    }
    function openLyrics(src) {
        var d = panel._lyricsDash(src)
        if (!d) return
        if (panel.lyricsShownFor(src)) { d.lyricsOpen = false; return }
        var o = (d === spotifyDash) ? spotifyAppDash : spotifyDash
        o.lyricsOpen = false
        d.lyricsOpen = true
        if (d.searchExpanded) d.lyricsGoHome()      // search open: go back to the home so the lyrics are visible
        panel.requestSwitchApp(panel._lyricsAppId(src))
    }

    function radioOpenSearch() {
        panel.requestSwitchApp("radio")
        radioViewItem.view = "search"
    }

    function openRadioFavorites() {
        panel.requestSwitchApp("radio")
        radioViewItem.view = "home"   // favorites are shown inside the radio's "home" view
    }

    property string radioLogo:      radioViewItem.playingLogo
    function radioNext() { if (typeof radioViewItem.skipStation === "function") radioViewItem.skipStation(1) }
    function radioPrev() { if (typeof radioViewItem.skipStation === "function") radioViewItem.skipStation(-1) }
    function radioTogglePlay() { radioViewItem.playing = !radioViewItem.playing }
    function radioStop() { if (radioViewItem.playing) radioViewItem.playing = false }

    // Station on air (full object) and resume at startup — see Main.qml
    // savePlaybackState()/tryResumePlayback()
    readonly property var radioStationData: radioViewItem.playingStation
    function radioResumeStation(station) {
        if (station && typeof radioViewItem.resumeStation === "function")
            radioViewItem.resumeStation(station)
    }

    property string activeApp: ""
    // Opening Settings from the dock: always from the first entry (except "targeted" openings)
    property bool _settingsTarget: false
    Timer { id: _settingsTargetClear; interval: 1500; onTriggered: panel._settingsTarget = false }
    onActiveAppChanged: {
        if (activeApp === "settings") {
            if (!panel._settingsTarget) settingsView.pageIdx = 0
            panel._settingsTarget = false
        }
    }
    property var webAppEntry: null      // web app opened ({id, url, name, icon}, see WebApps.qml)
    function openWebApp(entry) { panel.webAppEntry = entry }
    property string audioSrc:  ""   // which source is REALLY playing (from root.audioSrc), not which app is open on screen

    function getWebView(appId) {
        switch(appId) {
            case "theater":     return theaterItem.webView
            case "arcade":      return arcadeItem.webView
            case "browser":     return browserView.webView
            case "webapp":      return webAppLoader.item ? webAppLoader.item.webView : null
        }
        return null
    }

    // Call from the incoming message notification (see Main.qml): opens
    // the right conversation directly instead of leaving the user on the
    // list having to look for who wrote.
    function selectConversation(number, name) {
        messagesView.openChat(number, name || "")
    }

    // from the call notification: Calls tab (with the dial pad)
    function showPhoneKeypad() { if (phoneLoader.item) phoneLoader.item.activeTab = "calls" }

    Rectangle {
        id: topHandle
        // handle strip: 13 wireframe px (from y 38 to y 51)
        width: parent.width; height: panel.siteBarOpen ? 30 : 13 * ((Window.window && Window.window.uPx) ? Window.window.uPx : 1.12)
        color: "transparent"
        z: 10
        opacity: panel.hideTopHandle ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Rectangle {
            width: 84; height: 2.5; radius: 10
            color: panel.siteBarOpen ? "#8A8B8D" : (lightTheme ? "#D0D1D2" : "#8A8B8D")
            anchors.centerIn: parent
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            cursorShape: Qt.SizeVerCursor
            preventStealing: true

            onPressed: function(mouse) {
                panel.isDragging = true
                var globalY = mapToItem(null, 0, mouse.y).y
                panel.dragHandlePressed(globalY)
            }
            onPositionChanged: function(mouse) {
                var globalY = mapToItem(null, 0, mouse.y).y
                panel.dragHandleMoved(globalY)
            }
            onReleased: {
                panel.isDragging = false
                panel.dragHandleReleased()
            }
            onCanceled: {
                panel.isDragging = false
                panel.dragHandleReleased()
            }
        }

        // Band below the strip: PASSIVE observer (it does not steal touches from the header buttons). If the finger goes down
        // vertically the panel closing starts; the app underneath is deactivated so no button fires.
        Item {
            id: gripBand
            readonly property real _u: (Window.window && Window.window.uPx) ? Window.window.uPx : 1.12
            y: parent.height; width: parent.width; height: 34 * _u
            PointHandler {
                id: gripPH
                property real x0: 0
                property real y0: 0
                onActiveChanged: {
                    if (active) { x0 = point.scenePosition.x; y0 = point.scenePosition.y }
                    else if (panel.gripDragging) {
                        panel.gripDragging = false
                        panel.isDragging = false
                        panel.dragHandleReleased()
                    }
                }
                onPointChanged: {
                    if (!active) return
                    var y = point.scenePosition.y
                    if (!panel.gripDragging) {
                        var dy = y - y0, dx = Math.abs(point.scenePosition.x - x0)
                        if (dy > 14 * gripBand._u && dy > dx) {
                            panel.gripDragging = true
                            panel.isDragging = true
                            panel.dragHandlePressed(y)
                        }
                    } else {
                        panel.dragHandleMoved(y)
                    }
                }
            }
        }
    }

    // The old fullscreen button at the top left has been replaced by the
    // car handle's drag gesture (see onDragEnded in Main.qml)
    // for all the apps that used it: theater, arcade, browser, androidauto.

    Rectangle {
        id: theaterBackBtn
        visible: (panel.activeApp === "arcade"  && arcadeItem.canGoBack)
        z: 200
        x: 0; y: 0
        width: 44; height: 30
        color: backBtnHover.pressed ? "#33FFFFFF" : "transparent"

        Canvas {
            anchors.centerIn: parent
            width: 22; height: 22
            onPaint: {
                var ctx = getContext("2d")
                var s = width / 24.0
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = "#FFFFFF"
                ctx.lineWidth = 2 * s
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(14 * s, 4 * s)
                ctx.lineTo(14 * s, 8 * s)
                ctx.quadraticCurveTo(14 * s, 10 * s, 16 * s, 10 * s)
                ctx.lineTo(20 * s, 10 * s)
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(4 * s, 14 * s)
                ctx.lineTo(8 * s, 14 * s)
                ctx.quadraticCurveTo(10 * s, 14 * s, 10 * s, 16 * s)
                ctx.lineTo(10 * s, 20 * s)
                ctx.stroke()
            }
        }

        TapHandler {
            id: backBtnHover
            onTapped: panel.activeApp === "arcade" ? arcadeItem.goBack() : theaterItem.goBack()
        }
    }

    Item {
        id: appWrapper
        enabled: !panel.gripDragging
        anchors.top: topHandle.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        // ANTI-STUTTERING TRICK: The height always stays fixed at the maximum to
        // avoid the continuous recomputation of Chromium's layout. The parent's clip does the rest.
        height: panel.maxHeight - topHandle.height

        function setupVideoView(view) {
            view.settings.pluginsEnabled = true
            view.settings.playbackRequiresUserGesture = false
            view.settings.allowRunningInsecureContent = false
            view.settings.javascriptCanAccessClipboard = true
            view.settings.localContentCanAccessRemoteUrls = true
        }

        function injectDarkMode(view) {
            if (!view) return
            var css = lightTheme ? "" : "html{filter:invert(0.92) hue-rotate(180deg)!important;}img,video,canvas,svg{filter:invert(1) hue-rotate(180deg)!important;}"
            view.runJavaScript("(function(){" +
                "var s=document.getElementById('_tl_dark');"+
                "if(!s){s=document.createElement('style');s.id='_tl_dark';document.head.appendChild(s);}"+
                "s.textContent='" + css.replace(/'/g, "\'") + "';"+
            "})()")
        }

        // Phone: created when you open the app and stays alive during a call
        // (it counts the duration). It closes when the fade ends (opacity 0).
        Loader {
            id: phoneLoader
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            opacity: panel.activeApp === "phone" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "phone" ? 2 : 0
            enabled: panel.activeApp === "phone"
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            active: panel.activeApp === "phone" || opacity > 0
                    || (PhoneManager.callState || "idle") !== "idle"
            sourceComponent: PhoneView {
                onMessageContact: (number, name) => {
                    panel.requestSwitchApp("messages")
                    panel.selectConversation(number, name)
                }

                BtRequiredOverlay {
                    visible: panel.showPhoneRequired && PhoneManager.callState === "idle"
                    lightTheme: panel.lightTheme
                    appName: qsTr("Phone")
                    onOpenBluetoothSettings: panel.openSettingsPage(qsTr("Bluetooth"))
                }
            }
        }

        RadioView {
            id: radioViewItem; anchors.fill: parent
            hub: mediaHub
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            lightTheme: panel.lightTheme
            opacity: panel.activeApp === "radio" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "radio" ? 2 : 0
            enabled: panel.activeApp === "radio"
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            onPlayingChanged: panel.radioPlayingUpdated(playing)
        }

        YtMusicDashboard {
            id: spotifyDash
            hub: mediaHub
            lightTheme: panel.lightTheme
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            opacity: panel.activeApp === "spotify" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "spotify" ? 2 : 0
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            onSwitchToApp: appId => panel.requestSwitchApp(appId)
            onPlaybackChanged: function(track, artist, cover, playing) {
                panel.dashPlayback("ytmusic", track, artist, cover, playing)
            }
        }

        SpotifyDashboard {
            id: spotifyAppDash
            hub: mediaHub
            lightTheme: panel.lightTheme
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            opacity: panel.activeApp === "spotifyapp" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "spotifyapp" ? 2 : 0
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            onSwitchToApp: appId => panel.requestSwitchApp(appId)
            onPlaybackChanged: function(track, artist, cover, playing) {
                panel.dashPlayback("spotify", track, artist, cover, playing)
            }
        }

        // Podcast: created when you open the app. Playback continues even with the app
        // closed (the audio belongs to podcast_service.py, the commands go through MPRIS in the
        // music widget), so here it stays alive only as long as the podcast is the active player.
        Loader {
            id: podcastLoader
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            opacity: panel.activeApp === "podcast" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "podcast" ? 2 : 0
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            active: panel.activeApp === "podcast" || opacity > 0
                    || (typeof Mpris !== "undefined" && Mpris.activeIdentity === "Podcast")
            sourceComponent: PodcastDashboard {
                lightTheme: panel.lightTheme
                onSwitchToApp: appId => panel.requestSwitchApp(appId)
            }
        }

        // Music (PC files and USB sticks): playback belongs to local_music_service.py and the commands
        // go through MPRIS in the music widget, so the screen is created only when you open the app.
        Loader {
            id: localMusicLoader
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            opacity: panel.activeApp === "localmusic" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "localmusic" ? 2 : 0
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            active: panel.activeApp === "localmusic" || opacity > 0
            sourceComponent: LocalMusicDashboard {
                hub: mediaHub
                lightTheme: panel.lightTheme
                onSwitchToApp: appId => panel.requestSwitchApp(appId)
            }
        }

        LyricsSheet {
            id: lyricsSheet
            readonly property var dash: panel.lyricsDash
            property var _last: null            // the last app with lyrics: needed not to empty the panel while it goes down
            onDashChanged: if (dash) _last = dash
            anchors.fill: parent
            anchors.topMargin: _last ? _last.headerH : 0
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            z: 6
            // visible inside its app (or with the app closed: the panel is off screen); hidden if another app is in front.
            // It does not depend on "dash": so the closing (X) can go down with the animation instead of disappearing abruptly.
            shown: panel.activeApp === "" || panel.activeApp === (_last === spotifyDash ? "spotify" : "spotifyapp")
            lightTheme: panel.lightTheme
            bgColor: panel.lightTheme ? "#FFFFFF" : "#171717"
            open:       !!dash
            title:      _last ? _last.currentTrack : ""
            artist:     _last ? _last.currentArtist : ""
            cover:      _last ? _last.currentCover : ""
            durationMs: _last ? _last.durationMs : 0
            positionMs: _last ? _last.progressMs : 0
            playing:    _last ? _last.isPlaying : false
            onWantOpen: o => { if (!o && dash) dash.lyricsOpen = false }
            onSeekRequested: ms => { if (dash) dash.seekPct(ms / Math.max(1, dash.durationMs)) }
        }

        Settings {
            id: settingsView
            arcade: arcadeItem           // Arcade page: list of games and quick launch
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            opacity: panel.activeApp === "settings" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "settings" ? 2 : 0
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            onThemeModeSelected: (mode, s, e) => panel.settingsTheme(mode, s, e)
            onMirrorSelected: rhd => panel.settingsMirror(rhd)
            onLowPowerSelected: on => panel.settingsLowPower(on)
            onAmbientColorSelected: c => panel.settingsAmbient(c)
            onAmbientModeSelected: mode => panel.settingsAmbientMode(mode)
            onAmbientBrightnessSelected: val => panel.settingsAmbientBrightness(val)
            onCarColorSelected: c => panel.settingsCarColor(c)
            onBrightnessSelected: val => panel.settingsBrightness(val)
            onBlueLightFilterSelected: on => panel.settingsBlueLight(on)
            onSatNightSelected: mode => panel.settingsSatNight(mode)
            onAndroidAutoRestartRequested: androidAutoView.restart()
            onScreenCleanRequested: panel.settingsScreenClean()
            onPhoneDestRequested: panel.settingsPhoneDest()
            onAppVisibilitySelected: hiddenCsv => panel.settingsAppVisibility(hiddenCsv)
            onFullScreenMapSelected: on => panel.settingsFullScreenMap(on)
        }

        Theater {
            id: theaterItem
            overlayHost: panel.fullHost
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

            opacity: panel.activeApp === "theater" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "theater" ? 2 : 0
            active: panel.activeApp === "theater"
            lightTheme: panel.lightTheme
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            onMediaActivated: panel.sourceActivated("theater")
            onRequestFullscreen: function(on) { panel.requestAppFullscreen(on) }
            onOpenAndroidApp: function(key) { }
            onSwitchToArcade: panel.requestSwitchApp("arcade")
            onSwitchToToybox: panel.requestSwitchApp("toybox")
        }

        // Local instance: we do not rely on scoping between files for an id
        // declared elsewhere (SystemHelper is lightweight and stateless anyway).
        // ── WEB APPS (sites added from the Browser): created only when you open one ──
        Loader {
            id: webAppLoader
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            active: panel.activeApp === "webapp" && panel.webAppEntry !== null
            visible: active
            z: 2
            onActiveChanged: if (!active) panel.requestAppFullscreen(false)
            sourceComponent: WebAppView {
                browser: browserView
                entry: panel.webAppEntry
                lightTheme: panel.lightTheme
                onRequestFullscreen: function(on) { panel.requestAppFullscreen(on) }
            }
        }

        SystemHelper { id: sysHelper }

        // ── Unified media playback: queue, search and Bluetooth
        //    shared by YT Music, Spotify and Bluetooth ──
        MediaHub {
            id: mediaHub
            yt: spotifyDash
            sp: spotifyAppDash
            audioSrc: panel.audioSrc
            onSwitchToApp: appId => panel.requestSwitchApp(appId)
            // The phone started playing: it becomes the active source
            // (Main.qml pauses the previous one and updates the widget)
            onBluetoothActivated: panel.audioSourceActivated("bluetooth")
        }

        // ── CARPLAY / ANDROID AUTO — dongle Carlinkit (src/carlink + AndroidAutoView.qml) ──
        // The dongle talks to the phone; the UI shows the video and sends the touches.
        Item {
            id: androidAutoView
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

            opacity: panel.activeApp === "androidauto" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "androidauto" ? 2 : 0
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            // Settings → restart (new resolution): the session is closed again,
            // the phone reconnects with the new margins
            function restart() { Carlink.restart() }

            AndroidAutoView {
                anchors.fill: parent
                shown: androidAutoView.visible
                lightTheme: panel.lightTheme
                fullscreen: panel.appFullscreen
            }
        }

        BrowserApp {
            id: browserView
            nativeShells:    panel.nativeShells
            nativeToplevels: panel.nativeToplevels
            nativeSurfaces:  panel.nativeSurfaces
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

            opacity: panel.activeApp === "browser" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "browser" ? 2 : 0
            active: panel.activeApp === "browser"
            lightTheme: panel.lightTheme
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }

        MessagesApp {
            id: messagesView
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            opacity: panel.activeApp === "messages" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "messages" ? 2 : 0
            lightTheme: panel.lightTheme
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            BtRequiredOverlay {
                visible: panel.showPhoneRequired
                lightTheme: panel.lightTheme
                appName: qsTr("Messages")
                onOpenBluetoothSettings: panel.openSettingsPage(qsTr("Bluetooth"))
            }
        }

        CalendarApp {
            id: calendarView
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            opacity: panel.activeApp === "calendar" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "calendar" ? 2 : 0
            lightTheme: panel.lightTheme
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }

        Arcade {
            id: arcadeItem
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

            opacity: panel.activeApp === "arcade" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "arcade" ? 2 : 0
            active: panel.activeApp === "arcade"
            lightTheme: panel.lightTheme
            // round58+: Bottles/Wine games arrive as native Wayland
            // surfaces ("game" bucket in VoltaCompositor.qml), the same
            // mechanism already used below for Android Auto/video.
            nativeSurfaces:  panel.nativeSurfaces
            nativeToplevels: panel.nativeToplevels
            nativeShells:    panel.nativeShells
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            onMediaActivated: panel.sourceActivated("arcade")
            onRequestFullscreen: function(on) { panel.requestAppFullscreen(on) }
            onSwitchToTheater: panel.requestSwitchApp("theater")
            onSwitchToToybox: panel.requestSwitchApp("toybox")
        }

        // ── TOYBOX — same interface as Arcade (empty tiles for now) ──
        Toybox {
            id: toyboxView
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            opacity: panel.activeApp === "toybox" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "toybox" ? 2 : 0
            enabled: panel.activeApp === "toybox"
            active: panel.activeApp === "toybox"
            lightTheme: panel.lightTheme
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            onSwitchToTheater: panel.requestSwitchApp("theater")
            onSwitchToArcade: panel.requestSwitchApp("arcade")
            onCarColorPicked: hex => panel.settingsCarColor(hex)
            onCarFinishPicked: f => panel.settingsCarFinish(f)
            onRequestFullscreen: function(on) { panel.requestAppFullscreen(on) }
            onRomanceRequested: panel.romanceRequested()
            marsMode: panel.marsMode
            onMarsModeRequested: on => panel.marsModeRequested(on)
        }

        // ── Empty apps, to be developed ──
        CameraApp {
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            opacity: panel.activeApp === "camera" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "camera" ? 2 : 0
            enabled: panel.activeApp === "camera"
            active: panel.activeApp === "camera"
            lightTheme: panel.lightTheme
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }

        BluetoothApp {
            id: bluetoothView
            hub: mediaHub
            onSwitchToApp: appId => panel.requestSwitchApp(appId)
            onOpenBluetoothSettings: panel.openSettingsPage(qsTr("Bluetooth"))
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            opacity: panel.activeApp === "bluetooth" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "bluetooth" ? 2 : 0
            enabled: panel.activeApp === "bluetooth"
            active: panel.activeApp === "bluetooth"
            lightTheme: panel.lightTheme
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }

        Item {
            id: gnomeVideoView
            anchors.fill: parent
            anchors.bottomMargin: panel.bottomInset
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            opacity: panel.activeApp === "gnome-video" ? 1 : 0
            visible: opacity > 0
            z: panel.activeApp === "gnome-video" ? 2 : 0
            property bool launchAttempted: false
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            NativeAppView {
                anchors.fill: parent
                appLabel: "Video"
                shellSurface:    panel.nativeShells["gnome-video"]
                waylandToplevel: panel.nativeToplevels["gnome-video"]
            }

            onVisibleChanged: {
                if (visible && !panel.nativeSurfaces["gnome-video"] && !launchAttempted) {
                    launchAttempted = true
                    sysHelper.runDetached("/bin/sh", ["-c",
                        "gsettings set org.gnome.desktop.wm.preferences button-layout ':' 2>/dev/null; " +
                        "env WAYLAND_DISPLAY=wayland-volta GDK_BACKEND=wayland QT_QPA_PLATFORM=wayland " +
                        qsTr("totem || showtime || gnome-videos")])
                    gvidRetryTimer.restart()
                }
                if (visible && panel.nativeSurfaces["gnome-video"]) launchAttempted = false
            }
            Timer {
                id: gvidRetryTimer; interval: 6000; repeat: false
                onTriggered: if (!panel.nativeSurfaces["gnome-video"]) gnomeVideoView.launchAttempted = false
            }
        }
    }

    // ── Loading spinner in the center of the app (small): apps that are still loading content ──
    readonly property bool appLoadingRaw: {
        var a = panel.activeApp
        if (a === "spotify")    return spotifyDash.ytLoggedIn && spotifyDash.homeShelves.length === 0
        if (a === "spotifyapp") return spotifyAppDash.spLoggedIn && spotifyAppDash.homeShelves.length === 0
        if (a === "podcast")    return podcastLoader.status === Loader.Loading
        var wv = (a === "theater" || a === "arcade" || a === "browser" || a === "webapp") ? panel.getWebView(a) : null
        return !!wv && wv.loading && wv.loadProgress < 100
    }
    property bool appLoading: false          // with a short delay: instant loads do not make the spinner flash
    onAppLoadingRawChanged: { if (appLoadingRaw) loadingDelay.restart(); else { loadingDelay.stop(); appLoading = false } }
    Timer { id: loadingDelay; interval: 350; onTriggered: panel.appLoading = panel.appLoadingRaw }
    Item {
        id: appLoadingOverlay
        z: 60
        width: 44; height: 44
        x: (panel.width - width) / 2
        y: appWrapper.y + (appWrapper.height - panel.bottomInset - height) / 2
        opacity: panel.appLoading ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Rectangle {          // dark background: the spinner is white, visible on the light theme too
            anchors.fill: parent; radius: width / 2
            color: panel.lightTheme ? "#CC171717" : "transparent"
        }
        Spinner { size: 26; anchors.centerIn: parent; running: parent.visible }
    }
}