import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import QtCore as Core
import QtWebEngine
import VoltaApp 1.0

Rectangle {
    id: root
    color: Theme.bg
    // Same bug already found in PhoneView: without clip, content taller
    // than the available space ignores the margin reserved for the dock.
    clip: true
    property bool lightTheme: false
    onLightThemeChanged: Theme.light = lightTheme

    // Menu icons and texts in dark gray for the light theme (no pure black)
    property string iconColor: lightTheme ? "#555555" : "#A2A3A5"
    // Dark gray dividers for the light theme
    property string dividerColor: lightTheme ? "#777777" : "#414141"
    property string selectedTextColor: lightTheme ? "#444444" : Theme.textPrimary

    // Header ingrandito
    readonly property real u: (Window.window && Window.window.uPx) ? Window.window.uPx : 1.12
    readonly property real headerH: 38 * ((Window.window && Window.window.uPx) ? Window.window.uPx : 1.12)   // header band: 38 wireframe px (entries centered in the first 32, 6 of margin below)
    property string currentTrackId: ""

    // ── STATO RIPRODUZIONE E CODA ──────────────────────────────────────────
    property bool   isPlaying:     false
    property string currentTrack:  ""
    property string currentArtist: ""
    property string currentCover:  ""
    property bool   currentIsVideo: false
    property real   progressMs:    0
    property real   durationMs:    1
    property var    currentQueue:  []
    signal playbackChanged(string track, string artist, string cover, bool playing)

    // ── Switcher rapido app musicali (menu a tendina nell'header) ──
    property bool appMenuOpen: false
    readonly property string selfAppId: "spotify"          // this dashboard = YT Music
    // The two music apps shown in the menu (icon on the left + name)
    readonly property var musicApps: [
        { appId: "spotify",    name: "YT Music", icon: "qrc:/VoltaApp/icons/ytmusic.svg" },
        { appId: "spotifyapp", name: "Spotify",  icon: "qrc:/VoltaApp/icons/spotify.svg" },
        { appId: "localmusic", name: qsTr("Music"), icon: "qrc:/VoltaApp/icons/localmusic.svg" },
        { appId: "podcast",    name: "Podcasts",   icon: "qrc:/VoltaApp/icons/podcast.svg" },
        { appId: "bluetooth",  name: "Bluetooth", icon: "qrc:/VoltaApp/icons/bluetooth.svg" }
    ]
    signal switchToApp(string appId)

    // Unified media playback (MediaHub, injected by AppPanel):
    // if present, the "queue" screen and the search are the ones shared
    // with the other music apps (YT Music, Spotify, Bluetooth).
    property var hub: null
    onSearchExpandedChanged: if (searchExpanded && hub) Qt.callLater(function() { _uSearch.focusInput() })

    // ── NAVIGAZIONE ──────────────────────────────────────────────────────────
    property string viewTab: "home"
    property bool searchExpanded: false
    property bool playerVisible: false

    function cycleTab(dir) {
        root.searchExpanded = false; root.searchTerm = ""; root.detailVisible = false; root.artistVisible = false; root.playerVisible = false
        var tabs = ["home","recent","library"]
        var i = tabs.indexOf(root.viewTab)
        if (i < 0) i = 0
        root.viewTab = tabs[(i + dir + tabs.length) % tabs.length]
        if(root.viewTab === "library") root.loadLibrary()
    }

    // ── SCREEN HISTORY (back/forward buttons of the header) ──
    property var _navBack: []
    property var _navFwd: []
    property int navBackCount: 0
    property int navFwdCount: 0
    property var _navCur: null
    function _navSnap() {
        return { viewTab: root.viewTab, searchExpanded: root.searchExpanded, searchTerm: root.searchTerm,
                 playerVisible: root.playerVisible,
                 detailVisible: root.detailVisible, detailItem: root.detailItem, detailTracks: root.detailTracks,
                 artistVisible: root.artistVisible, artistData: root.artistData, artistTracks: root.artistTracks,
                 artistAlbums: root.artistAlbums, artistSingles: root.artistSingles }
    }
    function _navKey(s) {
        if (!s) return ""
        var id = ""
        if (s.detailVisible && s.detailItem)
            id = "d:" + (s.detailItem.audioPlaylistId || s.detailItem.browseId || s.detailItem.playlistId || s.detailItem.id || s.detailItem.title || "")
        else if (s.artistVisible && s.artistData)
            id = "a:" + (s.artistData.browseId || s.artistData.title || "")
        return s.viewTab + "|" + (s.searchExpanded ? 1 : 0) + "|" + (s.playerVisible ? 1 : 0) + "|" + id
    }
    // everything that defines the screen is observed; the timer groups multiple changes of the same action
    property var _navWatch: root._navSnap()
    on_NavWatchChanged: _navTimer.restart()
    Timer { id: _navTimer; interval: 30; running: true; onTriggered: root._navCommit() }
    function _navCommit() {
        var now = root._navSnap()
        if (root._navCur === null) { root._navCur = now; return }
        if (root._navKey(now) !== root._navKey(root._navCur)) {
            var b = root._navBack.slice(); b.push(root._navCur)
            if (b.length > 30) b.shift()
            root._navBack = b
            root._navFwd = []
        }
        root._navCur = now
        root.navBackCount = root._navBack.length
        root.navFwdCount = root._navFwd.length
    }
    function _navRestore(s) {
        root._navCur = s
        root.viewTab = s.viewTab
        root.searchTerm = s.searchTerm
        root.searchExpanded = s.searchExpanded
        root.playerVisible = s.playerVisible
        root.detailItem = s.detailItem; root.detailTracks = s.detailTracks; root.detailVisible = s.detailVisible
        root.artistData = s.artistData; root.artistTracks = s.artistTracks
        root.artistAlbums = s.artistAlbums; root.artistSingles = s.artistSingles; root.artistVisible = s.artistVisible
        root.navBackCount = root._navBack.length
        root.navFwdCount = root._navFwd.length
    }
    function navBack() {
        _navTimer.stop(); root._navCommit()
        if (root._navBack.length === 0) return
        var b = root._navBack.slice(); var s = b.pop(); root._navBack = b
        var f = root._navFwd.slice(); f.push(root._navCur); root._navFwd = f
        root._navRestore(s)
    }
    function navForward() {
        _navTimer.stop(); root._navCommit()
        if (root._navFwd.length === 0) return
        var f = root._navFwd.slice(); var s = f.pop(); root._navFwd = f
        var b = root._navBack.slice(); b.push(root._navCur); root._navBack = b
        root._navRestore(s)
    }

    property var homeRecent: []
    property var homeShelves: []

    // translated labels: the internal values (Playlists, Songs...) stay fixed, they are needed by the logic
    function libLabel(k) {
        return k === "Playlists" ? qsTr("Playlists") : k === "Songs" ? qsTr("Tracks") : k === "Albums" ? qsTr("Albums")
             : k === "Artists" ? qsTr("Artists") : k === "Podcasts" ? qsTr("Podcasts") : k
    }
    function secLabel(t) { return t === "Scelte rapide" ? qsTr("Quick picks") : t }
    property string libraryFilter: "Playlists"
    property var libraryItems: []

    property var  detailItem:    null
    property var  detailTracks:  []
    property bool detailVisible: false

    property var  artistData:    null
    property var  artistTracks:  []
    property var  artistAlbums:  []
    property var  artistSingles: []
    property bool artistVisible: false

    property string searchTerm: ""
    property var searchTopResult: null
    property var searchTracks:    []
    property var searchVideos:    []
    property var searchAlbums:    []
    property var searchArtists:   []
    property var searchPlaylists: []

    property var recentSearches: []

    Core.Settings {
        id: spotifySettings
        category: "spotify"
        property string savedSearches: "[]"
    }

    property string _debugMsg: ""
    Rectangle {
        z: 9999; anchors.bottom: root.bottom; anchors.right: root.right; anchors.margins: 16
        radius: 8; color: "#CC000000"; width: _dbgT.implicitWidth + 24; height: 34
        visible: root._debugMsg !== ""
        Text { id: _dbgT; anchors.centerIn: parent; text: root._debugMsg; color: "#FFF"; font.pixelSize: 13 }
        Timer { interval: 4000; running: root._debugMsg !== ""; repeat: false; onTriggered: root._debugMsg = "" }
    }

    function fmtMs(ms) {
        var s = Math.floor(ms / 1000);
        var m = Math.floor(s / 60);
        var sec = s % 60;
        return m + ":" + (sec < 10 ? "0" : "") + sec;
    }

    // Preloads the streams of the first tracks of a list: on tap they start right away
    function prefetch(list) {
        var ids = []
        for (var i = 0; i < (list || []).length && ids.length < 6; i++) {
            var t = list[i]
            if (t && t.videoId && ids.indexOf(t.videoId) < 0) ids.push(t.videoId)
        }
        if (ids.length > 0) scraperGet("/prefetch?ids=" + ids.join(","), function(d) {})
    }

    function scraperGet(path, cb) {
        var xhr = new XMLHttpRequest()
        var sep = path.indexOf("?") !== -1 ? "&" : "?"
        var rnd = Math.floor(Math.random() * 999999)
        var url = "http://127.0.0.1:8099" + path + sep + "_t=" + Date.now() + "_" + rnd
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try { cb(JSON.parse(xhr.responseText)) } catch(e) {}
            }
        }
        xhr.send()
    }

    function getHighResCover(url) {
        if (!url) return "";
        if (url.indexOf("googleusercontent.com") !== -1 && url.indexOf("=") !== -1) {
            return url.split("=")[0] + "=w1000-h1000";
        }
        if (url.indexOf("ytimg.com") !== -1) {
            var base = url.split("?")[0];
            return base.replace("sddefault", "maxresdefault").replace("hqdefault", "maxresdefault");
        }
        return url;
    }

    // Debounce to avoid adding the track twice in a row
    property string _lastEnqueuedId: ""
    property double _lastEnqueuedTime: 0

    function enqueueNext(media) {
        if (!media || !media.videoId) return;

        var now = Date.now();
        if (media.videoId === root._lastEnqueuedId && (now - root._lastEnqueuedTime) < 1500) {
            return;
        }
        root._lastEnqueuedId = media.videoId;
        root._lastEnqueuedTime = now;

        var url = "/player/enqueue_next?videoId=" + encodeURIComponent(media.videoId)
                + "&title=" + encodeURIComponent(media.title||"")
                + "&subtitle=" + encodeURIComponent(media.subtitle||"")
                + "&cover=" + encodeURIComponent(media.cover||"")
                + "&isVideo=" + (media.isVideo ? "true" : "false");
        scraperGet(url, function(d) {
            root._debugMsg = qsTr("Added as next track");
        });
    }

    function playMedia(media) {
        root.commitSearch()
        if (!media.videoId) return;
        root._debugMsg = qsTr("Loading audio...")

        var q = "?title=" + encodeURIComponent(media.title||"")
              + "&subtitle=" + encodeURIComponent(media.subtitle||"")
              + "&cover=" + encodeURIComponent(media.cover||"")
              + (media.startMs > 3000 ? "&start_ms=" + Math.round(media.startMs) : "")   // resume at startup: it already starts from the saved point

        scraperGet("/play/" + media.videoId + q, function(d) {
            if (d.error) { root._debugMsg = "⚠ " + d.error; }
            else { root._applyNowPlaying(media, true) }
        });
    }

    function playContext(tracks, startIdx) {
        if (!tracks || tracks.length === 0) return;
        root._debugMsg = qsTr("Loading playlist...")
        var payload = { index: startIdx || 0, tracks: [] }
        for (var i = 0; i < tracks.length; i++) {
            var t = tracks[i]
            if (!t.videoId) continue
            payload.tracks.push({ videoId: t.videoId, title: t.title||"", subtitle: t.subtitle||"", cover: t.cover||"", isVideo: t.isVideo||false })
        }
        if (payload.tracks.length === 0) { root._debugMsg = qsTr("No playable track"); return }
        var xhr = new XMLHttpRequest()
        xhr.open("POST", "http://127.0.0.1:8099/play_context")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            try {
                var d = JSON.parse(xhr.responseText)
                if (d.status === "error") { root._debugMsg = "⚠ " + (d.error || qsTr("playback unavailable")) }
                else if (d.track) root._applyNowPlaying(d.track, true)
            } catch(e) { root._debugMsg = qsTr("⚠ Music service unreachable") }
        }
        xhr.send(JSON.stringify(payload))
    }

    function _applyNowPlaying(track, playing) {
        root.currentTrack = track.title||"";
        root.currentArtist = track.subtitle||"";
        root.currentCover = track.cover||"";
        root.currentIsVideo = track.isVideo||false;
        root.isPlaying = playing;
        root._debugMsg = ""   // no "▶ track" notice at the bottom right
        // Artist and cover for the system player (mpv only announces the title)
        if (typeof Mpris !== "undefined") Mpris.setTrackHint("ytmusic", root.currentTrack, root.currentArtist, root.currentCover)
        root.playbackChanged(root.currentTrack, root.currentArtist, root.currentCover, playing)
        root.loadRecents()
    }

    // With "repeat one" next/previous restart the same song
    function _restartIfRepeatOne() {
        if (root.repeatMode !== "one" || root.currentTrackId === "") return false
        root.seekPct(0)
        if (!root.isPlaying) root.togglePlay()
        return true
    }
    function nextTrack()    { if (root._restartIfRepeatOne()) return; scraperGet("/player/next", function(d){ if(d && d.track) root._applyNowPlaying(d.track, true) }) }
    function prevTrack()    { if (root._restartIfRepeatOne()) return; scraperGet("/player/prev", function(d){ if(d && d.track) root._applyNowPlaying(d.track, true) }) }
    function seekPct(p)     { scraperGet("/player/seek?pct=" + p, function(d){}) }
    // ── Shuffle / Repeat (state also read by the mini player and the queue) ──
    property bool   shuffleOn: false
    property string repeatMode: "off"          // "off" | "all" | "one"
    property double _lastModeMs: 0
    function _applyModes(d) {
        if (!d) return
        if (typeof d.shuffle !== "undefined") root.shuffleOn = !!d.shuffle
        if (typeof d.repeat === "string") root.repeatMode = d.repeat
    }
    function setShuffle(on) {
        root.shuffleOn = on; root._lastModeMs = Date.now()
        scraperGet("/player/shuffle?state=" + (on ? "1" : "0"), function(d) { root._applyModes(d) })
    }
    function setRepeat(mode) {
        root.repeatMode = mode; root._lastModeMs = Date.now()
        scraperGet("/player/repeat?mode=" + mode, function(d) { root._applyModes(d) })
    }
    function toggleShuffle() { root.setShuffle(!root.shuffleOn) }
    function cycleRepeat()   { root.setRepeat(root.repeatMode === "off" ? "one" : root.repeatMode === "one" ? "all" : "off") }
    function shuffleQueue()  { root.toggleShuffle() }

    property double _lastToggleMs: 0
    function togglePlay() {
        var wantPause = root.isPlaying
        root.isPlaying = !wantPause
        root._lastToggleMs = Date.now()
        root.playbackChanged(root.currentTrack, root.currentArtist, root.currentCover, root.isPlaying)

        scraperGet("/player/pause?state=" + (wantPause ? "1" : "0"), function(d) {
            if (d && typeof d.paused !== "undefined") {
                root.isPlaying = !d.paused
                root.playbackChanged(root.currentTrack, root.currentArtist, root.currentCover, root.isPlaying)
            }
        })
    }

    // Player state: fast (500 ms) when really needed — app open, music
    // playing or YT Music as active source —, otherwise every 5 s (enough to notice
    // if playback starts from outside, e.g. from the phone). Before: 500 ms always.
    Timer {
        interval: (root.visible || root.isPlaying || (root.hub && root.hub.audioSrc === "ytmusic")) ? 500 : 5000
        repeat: true; running: true
        onTriggered: {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", "http://127.0.0.1:8099/player/status?_t=" + Date.now())
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                    try {
                        var d = JSON.parse(xhr.responseText)
                        root.progressMs = d.progress_ms; root.durationMs = d.duration_ms
                        if (d.queue) root.currentQueue = d.queue
                        if (Date.now() - root._lastModeMs > 2000) root._applyModes(d)
                        var t = d.track
                        if (t) {
                            root.currentTrackId = t.videoId || ""
                            if (t.title && t.title !== root.currentTrack) {
                                root._applyNowPlaying(t, d.is_playing)
                            }
                        }
                        if (d.is_playing !== root.isPlaying && (Date.now() - root._lastToggleMs) > 1000) {
                            root.isPlaying = d.is_playing
                            root.playbackChanged(root.currentTrack, root.currentArtist, root.currentCover, root.isPlaying)
                        }
                    } catch(e) {}
                }
            }
            xhr.send()
        }
    }

    function loadHome(fresh) {
        scraperGet("/ui/home" + (fresh ? "?fresh=1" : ""), function(d) {
            root.homeShelves = d.shelves || [];
            if (root.homeShelves.length > 0) root._healStep = 0
        })
    }

    // ── SELF-REPAIR: start without network (or service still starting) ──
    // While the home is empty it retries by itself with increasing waits (4s → 30s),
    // without hammering when the system knows it is offline. As soon as the
    // connection is back, home / recents / library fill in by themselves.
    property int _healStep: 0
    Timer {
        id: healTimer
        interval: Math.min(4000 * (1 + root._healStep), 30000)
        repeat: true
        running: root.homeShelves.length === 0
        onTriggered: {
            var w = root.Window.window
            if (w && w.online === false) return
            root._healStep++
            if (!root.ytLoggedIn) root.checkAuthStatus()
            root.loadHome(true)
            if (root.homeRecent.length === 0) root.loadRecents()
            if (root.libraryItems.length === 0) root.loadLibrary()
        }
    }

    function loadRecents() {
        scraperGet("/ui/recents", function(d) {
            if (d.items && d.items.length > 0) root.homeRecent = d.items
        })
        root.loadRecentSearches()
    }

    function loadRecentSearches() {
        scraperGet("/ui/recent_searches", function(d) {
            if (d.items) root.recentSearches = d.items
        })
    }

    function pushRecentSearch(q) {
        q = (q || "").trim()
        if (q.length < 2) return
        var lst = []
        lst.push(q)
        for (var i = 0; i < root.recentSearches.length; i++) {
            if (root.recentSearches[i].toLowerCase() !== q.toLowerCase())
                lst.push(root.recentSearches[i])
        }
        root.recentSearches = lst.slice(0, 8)
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "http://127.0.0.1:8099/ui/recent_searches/add?q=" + encodeURIComponent(q) + "&_t=" + Date.now())
        xhr.send()
    }

    function loadAll() {
        root.loadHome(false)
        root.loadRecents()
        root.loadLibrary()
    }

    Timer {
        interval: 300000; repeat: true; running: true
        onTriggered: root.loadHome(false)
    }

    // ── LOGIN / LOGOUT ACCOUNT ──────────────────────────────────────────────
    property bool ytLoggedIn: false
    property string ytAvatarUrl: ""
    property string ytAccountName: ""
    property bool avatarMenuOpen: false
    onYtLoggedInChanged: {
        if (ytLoggedIn) loadAccount()
        else { ytAvatarUrl = ""; ytAccountName = ""; avatarMenuOpen = false }
    }
    function loadAccount() {
        // keeps an eye on the internal browser's cookies: they are needed for "Sign out"
        if (_authWebView) _ytCk.watchCookies(_authWebView.profile)
        scraperGet("/auth/account", function(d) {
            root.ytAvatarUrl = d.photo || ""
            root.ytAccountName = d.name || ""
        })
    }
    property bool ytClientConfigured: true
    property bool authPopupVisible: false
    property string authPopupUrl: ""
    property string authStatusText: ""
    property int authPollInterval: 4000
    property bool authJsInjected: false
    property bool authChecked: false        // true after the first check of the login state
    readonly property color authFg: root.iconColor === "#555555" ? "#222222" : "#FFFFFF"

    function checkAuthStatus() {
        scraperGet("/auth/status?verify=1", function(d) {
            root.ytLoggedIn = !!d.loggedIn
            root.ytClientConfigured = !!d.clientConfigured
            root.authChecked = true
        })
    }

    // JS injected into the page: intercepts the first fetch() call to
    // YT Music's internal APIs and captures their headers (authorization,
    // x-goog-authuser), plus the session cookies (document.cookie) — they are
    // exactly the same data you would copy by hand from DevTools.
    SystemHelper { id: _ytCk }

    readonly property string _captureScript: "
        (function() {
            if (window.__ytCaptureV2) return 'already';
            window.__ytCaptureV2 = true;
            window.__ytCapturedHeaders = null;
            function addH(h, src) {
                if (!src) return;
                try {
                    if (typeof Headers !== 'undefined' && src instanceof Headers) {
                        src.forEach(function(v, k) { h[String(k).toLowerCase()] = v; });
                    } else if (Array.isArray(src)) {
                        src.forEach(function(p) { h[String(p[0]).toLowerCase()] = p[1]; });
                    } else {
                        for (var k in src) h[String(k).toLowerCase()] = src[k];
                    }
                } catch (e) {}
            }
            var origFetch = window.fetch;
            window.fetch = function(input, init) {
                try {
                    var url = (typeof input === 'string') ? input : (input && input.url);
                    if (url && url.indexOf('/youtubei/v1/') !== -1) {
                        var h = {};
                        if (input && typeof input === 'object') addH(h, input.headers);
                        if (init) addH(h, init.headers);
                        if (h['authorization']) {
                            h['cookie'] = document.cookie;
                            window.__ytCapturedHeaders = h;
                        }
                    }
                } catch (e) {}
                return origFetch.apply(this, arguments);
            };
            return 'installed';
        })();
    "

    // Google login page that then redirects to YouTube Music (if it does not work: "https://music.youtube.com/")
    readonly property string ytLoginUrl: "https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&uilel=3&hl=it&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26hl%3Dit%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F"

    function startLogin() {
        _ytCk.watchCookies(_authWebView.profile)
        root.authStatusText = qsTr("Sign in with your Google account below: the connection is automatic.")
        root.authJsInjected = false
        root.authPopupUrl = root.ytLoginUrl
        root.authPopupVisible = true
        _captureCheckTimer.restart()
    }

    function injectCaptureScript() {
        if (!_authWebView) return
        _authWebView.runJavaScript(root._captureScript, function() {})
    }

    // The script is injected as soon as each new page starts
    // (onLoadingChanged on the WebEngineView) — here, at every tick, we
    // re-inject it anyway as a safety net (idempotent, harmless
    // if already installed) and check whether it has already captured something.
    function pollCapture() {
        if (!_authWebView) return
        root.injectCaptureScript()
        _authWebView.runJavaScript(
            "JSON.stringify(window.__ytCapturedHeaders || null)",
            function(res) {
                if (!res || res === "null") return
                var headers
                try { headers = JSON.parse(res) } catch(e) { return }
                if (!headers || !headers.cookie) return
                _captureCheckTimer.stop()
                root.authStatusText = qsTr("Login detected, saving data...")
                root.saveBrowserAuth(headers)
            }
        )
    }

    function saveBrowserAuth(headers) {
        // Full cookies from the profile (including HttpOnly ones, which the page does not see)
        var full = _ytCk.cookieHeader("music.youtube.com")
        if (full.length > 0 && full.indexOf("SAPISID=") >= 0) headers.cookie = full
        var xhr = new XMLHttpRequest()
        xhr.open("POST", "http://127.0.0.1:8099/auth/browser_save")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                try {
                    var d = JSON.parse(xhr.responseText)
                    if (d.status === "done" && d.verified === false) {
                        // Saved, but YouTube rejects the requests: do not pretend it works.
                        root.authStatusText = qsTr("YouTube Music rejected this sign-in. Try signing in again in the panel.")
                        if (_authWebView) _authWebView.runJavaScript("window.__ytCapturedHeaders = null;", function() {})
                        _captureCheckTimer.restart()
                    } else if (d.status === "done") {
                        root.authPopupVisible = false
                        root.ytLoggedIn = true
                        root.loadAccount()
                        root.loadAll() // reloads the home with the new account
                    } else {
                        root.authStatusText = d.message || qsTr("Headers captured but saving failed, try again.")
                        // resets the capture, otherwise it stays stuck on the same data
                        if (_authWebView) _authWebView.runJavaScript("window.__ytCapturedHeaders = null;", function() {})
                        _captureCheckTimer.restart()
                    }
                } catch(e) {
                    root.authStatusText = qsTr("Communication error with the service.")
                }
            }
        }
        xhr.send(JSON.stringify({headers: headers}))
    }

    function doLogout() {
        root.avatarMenuOpen = false
        // also signs out of Google in the internal browser, so that at the next sign-in the account can be chosen
        if (_authWebView) { _ytCk.watchCookies(_authWebView.profile); _ytCk.clearGoogleCookies() }
        root.authPopupUrl = ""
        var xhr = new XMLHttpRequest()
        xhr.open("POST", "http://127.0.0.1:8099/auth/logout")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                root.ytLoggedIn = false
                root.loadAll()
            }
        }
        xhr.send()
    }

    function closeAuthPopup() {
        _captureCheckTimer.stop()
        root.authPopupVisible = false
    }

    Timer {
        id: _captureCheckTimer
        interval: 700
        repeat: true
        running: false
        onTriggered: root.pollCapture()
    }

    function setLibraryFilter(filter) { root.libraryFilter = filter; root.loadLibrary(); }

    function loadLibrary() {
        var map = {"Playlists":"playlists", "Songs":"songs", "Albums":"albums", "Artists":"artists", "Podcasts":"podcasts"};
        scraperGet("/ui/library?filter=" + map[root.libraryFilter], function(d) { root.libraryItems = d.items || []; });
    }

    function openDetail(media, allowVideo) {
        root.commitSearch()
        root.searchExpanded = false; root.playerVisible = false;

        var it = {}
        for (var p in media) it[p] = media[p]
        root.detailItem = it
        root.detailTracks = []
        root.detailVisible = true
        root.artistVisible = false

        var primaryId = media.audioPlaylistId
                     || (media.browseId && media.browseId.indexOf('MPREb')===0 ? media.browseId : null)
                     || media.playlistId
                     || media.browseId
                     || media.id;

        var idsToTry = [primaryId]
        if (media.audioPlaylistId && media.audioPlaylistId !== primaryId) idsToTry.push(media.audioPlaylistId)
        if (media.browseId && idsToTry.indexOf(media.browseId) === -1) idsToTry.push(media.browseId)
        if (media.playlistId && idsToTry.indexOf(media.playlistId) === -1) idsToTry.push(media.playlistId)

        function tryFetch(idx) {
            if (idx >= idsToTry.length) {
                root._debugMsg = qsTr("⚠ Unable to open: ") + (media.title || qsTr("item"))
                return
            }
            var reqId = idsToTry[idx]
            if (!reqId) { tryFetch(idx+1); return }

            scraperGet("/playlist/" + reqId + (allowVideo ? "?allow_video=1" : ""), function(d) {
                var arr = []
                for(var k=0; k<(d.tracks||[]).length; k++){
                    var tr = d.tracks[k]; if(!tr) continue;
                    arr.push({num: k+1, title: tr.title, subtitle: tr.subtitle, album: tr.album||"", cover: tr.cover||media.cover||"", duration: tr.duration||"", videoId: tr.videoId||"", type: "Track", isContext: false, isLiked: tr.isLiked||false, isVideo: tr.isVideo||false})
                }

                if(arr.length === 0) {
                    tryFetch(idx+1)
                    return
                }

                if (d.type) it.type = (d.type === "album") ? "Album" : "Playlist"
                if (d.title && !it.title) it.title = d.title
                if (d.cover && !it.cover) it.cover = d.cover

                root.detailItem = it
                root.detailTracks = arr
                root.prefetch(arr)
            })
        }
        tryFetch(0)
    }

    function openArtist(media) {
        root.commitSearch()
        root.searchExpanded = false; root.playerVisible = false;
        var artId = media.browseId || media.id; if(!artId) return;

        root.artistData = {title: media.title||media.name||"", subtitle: qsTr("Artist"), cover: media.cover||"", browseId: artId, type: "Artist", isContext: true}
        root.artistTracks = []
        root.artistAlbums = []
        root.artistSingles = []
        root.artistVisible = true
        root.detailVisible = false

        scraperGet("/artist/" + artId, function(d) {
            var t = d.tracks||[]
            var a = d.albums||[]
            var s = d.singles||[]

            root.artistData = {title: media.title||media.name||d.name||"", subtitle: qsTr("Artist"), cover: media.cover||d.cover||"", browseId: artId, type: "Artist", isContext: true}
            root.artistTracks = t
            root.prefetch(t)
            root.artistAlbums = a
            root.artistSingles = s
        })
    }

    Timer { id: _sd; interval: 200; onTriggered: root.doSearch() }
    function doSearch() {
        if(!root.searchTerm || root.searchTerm.length < 2) { root.searchTopResult=null; root.searchTracks=[]; root.searchVideos=[]; root.searchAlbums=[]; root.searchArtists=[]; root.searchPlaylists=[]; return }
        var q = root.searchTerm
        scraperGet("/search?q="+encodeURIComponent(q), function(d) {
            root.searchTopResult = d.top_result || null
            root.prefetch((d.top_result && d.top_result.videoId ? [d.top_result] : []).concat(d.tracks||[]))
            root.searchTracks = d.tracks||[]; root.searchVideos = d.videos||[]; root.searchAlbums = d.albums||[]; root.searchArtists = d.artists||[]; root.searchPlaylists = d.playlists||[]
        })
    }

    function commitSearch() {
        if (root.searchExpanded && root.searchTerm.length >= 2)
            root.pushRecentSearch(root.searchTerm)
    }

    Component.onCompleted: { Qt.callLater(root.loadAll); Qt.callLater(root.checkAuthStatus) }

    // ════════ COMPONENTI GENERICI UNIFICATI (AL LIVELLO RADICE) ════════════════════════

    component CustomImage: Item {
        id: _cimg
        property alias source: _cimgSrc.source
        property real radius: 6
        property bool isCircle: false
        property int fillMode: Image.PreserveAspectCrop
        property color placeholderColor: Theme.surfaceElevated
        property bool showPlaceholder: true
        property string fallbackText: ""

        Rectangle {
            anchors.fill: parent
            color: _cimg.placeholderColor
            radius: _cimg.isCircle ? width/2 : Math.min(_cimg.radius, 3)
            visible: _cimg.showPlaceholder
        }

        Image {
            id: _cimgSrc
            anchors.fill: parent
            fillMode: _cimg.fillMode
            visible: false
            asynchronous: true
            smooth: true
            mipmap: true
        }

        Item {
            id: _cimgMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            layer.smooth: true
            Rectangle {
                anchors.fill: parent
                radius: _cimg.isCircle ? width/2 : Math.min(_cimg.radius, 3)
                color: "white"
            }
        }

        MultiEffect {
            anchors.fill: _cimgSrc
            source: _cimgSrc
            maskEnabled: true
            maskSource: _cimgMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            visible: _cimgSrc.status === Image.Ready
        }

        Text {
            anchors.centerIn: parent
            visible: _cimg.fallbackText !== "" && _cimgSrc.status !== Image.Ready
            text: _cimg.fallbackText
            color: Theme.textPrimary
            font.pixelSize: parent.width * 0.4
            font.weight: Font.Normal
        }
    }

    component SearchSectionHeader: Item {
        property string title
        property bool showSeeAll: true
        width: parent ? parent.width : 300; height: 32
        Row {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 8
            Image { sourceSize: Qt.size(width * 2, height * 2);
                source: "qrc:/VoltaApp/icons/ytmusic.svg"
                width: 18; height: 18
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: parent.parent.title
                color: Theme.textPrimary; font.pixelSize: 18; font.weight: Font.Normal
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Rectangle {
            visible: parent.showSeeAll
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: _saTxt.implicitWidth + 24; height: 28; radius: 8
            color: lightTheme ? "#D9D9D9" : "#2A2A2A"
            Text {
                id: _saTxt
                text: qsTr("See all")
                anchors.centerIn: parent
                color: lightTheme ? "#111111" : "#FFFFFF"
                font.pixelSize: 12; font.weight: Font.Medium
            }
        }
    }

    component TrackListHeader: Item {
        property bool showDivider: true
        width: parent ? parent.width : 800; height: 38
        Rectangle {
            x: 20; anchors.bottom: parent.bottom; width: parent.width-40; height: 1
            color: Theme.divider
            visible: parent.showDivider
        }
        Row {
            x: 30; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 60
            Text { text: qsTr("SONG"); width: parent.width * 0.35; color: Theme.textHint; font.pixelSize: 12; font.weight: Font.Medium; font.letterSpacing: 0.5 }
            Text { text: qsTr("ARTIST"); width: parent.width * 0.25; color: Theme.textHint; font.pixelSize: 12; font.weight: Font.Medium; font.letterSpacing: 0.5 }
            Text { text: qsTr("ALBUM");   width: parent.width * 0.25; color: Theme.textHint; font.pixelSize: 12; font.weight: Font.Medium; font.letterSpacing: 0.5 }
            Text { text: qsTr("TIME");   width: parent.width * 0.08; color: Theme.textHint; font.pixelSize: 12; font.weight: Font.Medium; font.letterSpacing: 0.5; horizontalAlignment: Text.AlignRight }
        }
    }

    component SwipeQueueIcon: Canvas {
        width: 24; height: 20
        onPaint: {
            var c = getContext("2d"); c.clearRect(0,0,width,height);
            c.fillStyle = "#FFFFFF";
            c.beginPath(); c.moveTo(0,3); c.lineTo(9,8); c.lineTo(0,13); c.closePath(); c.fill();
            c.strokeStyle = "#FFFFFF"; c.lineWidth = 2.5; c.lineCap = "round";
            c.beginPath(); c.moveTo(12, 3); c.lineTo(24, 3); c.stroke();
            c.beginPath(); c.moveTo(12, 8); c.lineTo(24, 8); c.stroke();
            c.beginPath(); c.moveTo(12, 13); c.lineTo(24, 13); c.stroke();
        }
    }

    component PlayerBtn: Rectangle {
        id: _pb
        property string src
        property bool toggle: false      // button with state (Shuffle / Repeat)
        property bool active: false
        property string badge: ""        // e.g. "1" for "repeat one"
        signal clicked()
        width: 64; height: 64; radius: 8
        color: _pbMA.pressed ? Theme.bg : Theme.surfaceElevated
        // Casuale / Ripeti: attivo = nero pieno (bianco pieno col tema scuro), spento = grigio chiaro
        readonly property color onCol:  lightTheme ? "#000000" : "#FFFFFF"
        readonly property color offCol: lightTheme ? "#BDBDBD" : "#5E5E5E"
        Image { sourceSize: Qt.size(width * 2, height * 2);
            anchors.centerIn: parent; source: _pb.src; width: 22; height: 22
            layer.enabled: true
            layer.effect: MultiEffect { colorization: 1; colorizationColor: !_pb.toggle ? (lightTheme ? "black" : "#FFFFFF") : _pb.onCol }
        }
        Rectangle {   // dot: button on (icon always pure white)
            visible: _pb.toggle && _pb.active
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 10
            width: 4; height: 4; radius: 2; color: _pb.onCol
        }
        Text {
            visible: _pb.badge !== ""
            anchors.horizontalCenter: parent.horizontalCenter; anchors.horizontalCenterOffset: 12
            anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -10
            text: _pb.badge; color: _pb.onCol; font.pixelSize: 10; font.weight: Font.Bold
        }
        MouseArea { id: _pbMA; anchors.fill: parent; preventStealing: true; onClicked: _pb.clicked() }
    }

    // ── RIGID ANCHORS IN THE TRACKROW & SWIPE ──
    component TrackRow: Item {
        id: _tr;
        property var trackData;
        property int trackIndex: -1;
        property var contextTracks: null
        property bool showCover: true
        property bool disableSwipe: false

        property bool isPlayingThis: root.currentTrackId !== "" && _tr.trackData && _tr.trackData.videoId === root.currentTrackId

        // Heart state: the shared one (mini player / queue) if known, otherwise the track's
        readonly property bool localLiked: {
            if (!trackData) return false
            var k = "ytmusic:" + (trackData.videoId || "")
            if (root.hub && root.hub.likedMap[k] !== undefined) return root.hub.likedMap[k]
            return !!trackData.isLiked
        }

        width: parent ? parent.width : 800; height: 64

        // Green background for the Swipe with the queue icon
        Rectangle {
            x: 20; width: parent.width - 40; height: 58; radius: 8
            anchors.verticalCenter: parent.verticalCenter
            color: "#1ED760"
            visible: _swipeContainer.x !== 0

            SwipeQueueIcon {
                anchors.left: parent.left; anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                visible: _swipeContainer.x > 0
            }
            SwipeQueueIcon {
                anchors.right: parent.right; anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                visible: _swipeContainer.x < 0
            }
        }

        Item {
            id: _swipeContainer
            x: 0; width: parent.width; height: parent.height
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

            Rectangle {
                id: _trBg
                x: 20; width: parent.width - 40; height: 58; radius: 8
                anchors.verticalCenter: parent.verticalCenter
                color: (_trMA.pressed || _tr.isPlayingThis) ? Theme.surfaceElevated : Theme.bg

                Row {
                    x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter; spacing: 0

                    // COLONNA 1: CANZONE (35%)
                    Item {
                        id: _col1
                        width: parent.width * 0.35; height: 44; anchors.verticalCenter: parent.verticalCenter
                        clip: true

                        CustomImage {
                            id: _trImgRect
                            visible: _tr.showCover
                            width: (_tr.trackData && _tr.trackData.isVideo) ? 78 : 44
                            height: 44; radius: 6
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            source: _tr.trackData ? (_tr.trackData.cover || "") : ""
                        }

                        Text {
                            id: _trIndex
                            visible: !_tr.showCover
                            text: (_tr.trackIndex + 1).toString()
                            color: _tr.isPlayingThis ? Theme.textPrimary : Theme.textSecondary
                            font.pixelSize: 14; font.weight: Font.DemiBold
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            horizontalAlignment: Text.AlignRight
                        }

                        Text {
                            text: _tr.trackData ? (_tr.trackData.title || "") : ""
                            color: Theme.textPrimary
                            font.pixelSize: 15; font.weight: Font.Medium
                            anchors.left: _tr.showCover ? _trImgRect.right : _trIndex.right
                            anchors.leftMargin: 14
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    // COLONNA 2: ARTISTA (25%)
                    Item {
                        id: _col2
                        width: parent.width * 0.25; height: 44; anchors.verticalCenter: parent.verticalCenter
                        clip: true

                        Text {
                            text: _tr.trackData ? (_tr.trackData.subtitle || "") : ""
                            color: Theme.textSecondary; font.pixelSize: 14; font.weight: Font.Medium
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    // COLONNA 3: ALBUM (25%)
                    Item {
                        id: _col3
                        width: parent.width * 0.25; height: 44; anchors.verticalCenter: parent.verticalCenter
                        clip: true

                        Text {
                            text: _tr.trackData ? (_tr.trackData.album || "") : ""
                            color: Theme.textSecondary; font.pixelSize: 14; font.weight: Font.Medium
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    // COLONNA 4: TEMPO (8%)
                    Item {
                        id: _col4
                        width: parent.width * 0.08; height: 44; anchors.verticalCenter: parent.verticalCenter
                        clip: true

                        Text {
                            text: _tr.trackData ? (_tr.trackData.duration || "") : ""
                            color: Theme.textSecondary; font.pixelSize: 14; font.weight: Font.Medium
                            horizontalAlignment: Text.AlignRight
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    // COLONNA 5: CUORE (7%)
                    Item {
                        width: parent.width * 0.07; height: 44; anchors.verticalCenter: parent.verticalCenter
                        Image { sourceSize: Qt.size(width * 2, height * 2);
                            source: _tr.localLiked ? "qrc:/VoltaApp/icons/heart-full.svg" : "qrc:/VoltaApp/icons/heart-empty.svg"
                            width: 18; height: 18
                            anchors.centerIn: parent
                            opacity: 1.0
                            layer.enabled: true
                            layer.effect: MultiEffect { colorization: 1.0; colorizationColor: lightTheme ? Qt.rgba(0.05,0.05,0.08,1) : "#FFFFFF" }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onPressed: function(mouse) { mouse.accepted = true }
                            onClicked: {
                                if (_tr.trackData && _tr.trackData.videoId) {
                                    var nv = !_tr.localLiked;
                                    _tr.trackData.isLiked = nv;
                                    if (root.hub) root.hub.setLiked("ytmusic", _tr.trackData.videoId, nv);
                                    var action = nv ? "LIKE" : "INDIFFERENT";
                                    scraperGet("/player/like/" + _tr.trackData.videoId + "?action=" + action, function(){});
                                }
                            }
                        }
                    }
                }
            }

            MouseArea {
                id: _trMA
                // Under the row's content: before it covered the heart and
                // "stole" its touch, so the heart did nothing
                z: -1
                anchors.fill: parent
                drag.target: _tr.disableSwipe ? null : _swipeContainer
                drag.axis: Drag.XAxis
                drag.minimumX: -100
                drag.maximumX: 100

                onReleased: {
                    if (Math.abs(_swipeContainer.x) > 60) {
                        root.enqueueNext(_tr.trackData)
                    }
                    _swipeContainer.x = 0
                }
                onClicked: {
                    if (_tr.contextTracks && _tr.contextTracks.length > 0)
                        root.playContext(_tr.contextTracks, _tr.trackIndex)
                    else
                        root.playMedia(_tr.trackData)
                }
            }
        }
    }

    component QuickPicksRow: Column {
        id: _qpr
        property string title
        property var items
        // Measures from wireframe 5: left margin 16, cards 200 x 59, 3 columns x 2 rows,
        // column gap ~12.5 and rows 9; title 24 + 5 above the grid
        width: parent ? parent.width : 800; spacing: 14.6 * root.u; bottomPadding: 23 * root.u   // reference photo
        visible: items && items.length > 0

        Text {
            text: root.secLabel(_qpr.title); color: Theme.textPrimary
            font.pixelSize: 16.5 * root.u; font.weight: Font.Bold
            height: 24 * root.u; verticalAlignment: Text.AlignVCenter
            leftPadding: 14.7 * root.u
        }

        Grid {
            x: 14.7 * root.u
            columns: 3
            columnSpacing: 10 * root.u
            rowSpacing: 10 * root.u
            readonly property real cellW: (parent.width - 31 * root.u - 2 * columnSpacing) / 3

            Repeater {
                model: _qpr.items ? _qpr.items.slice(0, 6) : []
                delegate: Item {
                    width: parent.cellW; height: 50 * root.u
                    Rectangle {
                        anchors.fill: parent; radius: 10
                        color: _qpMA.pressed ? Theme.surfaceElevated : (lightTheme ? "#EAEAEA" : Qt.rgba(1,1,1,0.05))
                        Row {
                            anchors.fill: parent; spacing: 10 * root.u
                            // Artwork as big as the card (no frame): rounded corners only on the left
                            Item {
                                width: 50 * root.u; height: 50 * root.u; clip: true
                                CustomImage {
                                    width: 50 * root.u; height: 50 * root.u; radius: 4.5 * root.u
                                    source: modelData.cover||""
                                }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter; spacing: 2 * root.u; width: parent.width - 60 * root.u - 6 * root.u
                                Text { text: modelData.title||""; color: Theme.textPrimary; font.pixelSize: 11.5 * root.u; font.weight: Font.Medium; width: parent.width; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap }
                                Text { text: modelData.subtitle||""; color: Theme.textSecondary; font.pixelSize: 11 * root.u; font.weight: Font.Normal; width: parent.width; elide: Text.ElideRight; maximumLineCount: 1 }
                            }
                        }
                        MouseArea { id: _qpMA; anchors.fill: parent; onClicked: root.playMedia(modelData) }
                    }
                }
            }
        }
    }

    component SectionRow: Column {
        id: _sr; property string title; property var items; property bool isCircle: false
        width: parent ? parent.width : 800; spacing: 8.1 * root.u; bottomPadding: 21 * root.u; visible: typeof items !== "undefined" && items.length > 0
        readonly property bool anySub: { var a = items || []; for (var i = 0; i < a.length; i++) if (a[i] && a[i].subtitle) return true; return false }
        Text { text: root.secLabel(_sr.title); color: Theme.textPrimary; font.pixelSize: 12 * root.u; font.weight: Font.Bold; height: 14 * root.u; verticalAlignment: Text.AlignVCenter; leftPadding: 15.2 * root.u }
        ListView {
            width: parent.width; height: (101.1 + 22 + (_sr.anySub ? 27.9 : 0)) * root.u
            orientation: ListView.Horizontal; spacing: 10.7 * root.u; leftMargin: 15.2 * root.u; rightMargin: 15.2 * root.u; clip: true
            model: _sr.items
            delegate: Item {
                width: 101.1 * root.u; height: (101.1 + 22 + (_sr.anySub ? 27.9 : 0)) * root.u
                Column {
                    width: parent.width
                    spacing: 0
                    Item {
                        width: parent.width; height: parent.width
                        CustomImage {
                            anchors.fill: parent
                            isCircle: _sr.isCircle
                            radius: 4.5 * root.u
                            source: modelData.cover||""
                            MouseArea {
                                anchors.fill: parent;
                                onClicked: {
                                    if(_sr.isCircle || modelData.type==="Artist") root.openArtist(modelData);
                                    else if(modelData.type==="Track") root.playMedia(modelData);
                                    else root.openDetail(modelData, false);
                                }
                            }
                        }
                    }
                    Text { text: modelData.title||""; color: Theme.textPrimary; font.pixelSize: (_sr.isCircle ? 10.5 : 11.5) * root.u; font.weight: Font.Medium; height: 22 * root.u; verticalAlignment: Text.AlignBottom; width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; horizontalAlignment: _sr.isCircle ? Text.AlignHCenter : Text.AlignLeft }
                    Text { visible: text !== ""; text: modelData.subtitle||""; color: Theme.textSecondary; font.pixelSize: 10 * root.u; topPadding: 1.3 * root.u; width: parent.width; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap; lineHeightMode: Text.FixedHeight; lineHeight: 13.3 * root.u; horizontalAlignment: _sr.isCircle ? Text.AlignHCenter : Text.AlignLeft }
                }
            }
        }
    }

    // ════════ INTESTAZIONE (z=100) ════════════════════════════════════════════
    Rectangle {
        id: _hdr; width: parent.width; height: root.headerH; z: 100
        color: Theme.bg

        Row {
            anchors.left: parent.left; anchors.leftMargin: 20; y: (32 * root.u - height) / 2; spacing: 18

            // 1. App icon — first element on the left: opens the menu to switch music app
            Item {
                id: _appSwitcher
                width: _appSwRow.width; height: 34
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: _appSwRow
                    spacing: 7
                    anchors.verticalCenter: parent.verticalCenter
                    Image { sourceSize: Qt.size(width * 2, height * 2);
                        source: "qrc:/VoltaApp/icons/ytmusic.svg"
                        width: 29; height: 29; fillMode: Image.PreserveAspectFit
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent; anchors.margins: -6
                    onClicked: root.appMenuOpen = !root.appMenuOpen
                }
            }

            // Row
            Rectangle { width: 1; height: 21; color: root.dividerColor; anchors.verticalCenter: parent.verticalCenter }

            // 3. Search (before the logo, now swapped in position)
            Item {
                width: 27; height: 27; anchors.verticalCenter: parent.verticalCenter
                Canvas {
                    anchors.fill: parent
                    property color col: lightTheme ? "#141414" : "#FFFFFF"      // same magnifier as Podcast
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
                MouseArea { anchors.fill: parent; onClicked: { root.searchExpanded = true; root.playerVisible = false; root.loadRecentSearches(); if (root.hub) _uSearch.focusInput(); else _si.forceActiveFocus(); } }
            }

            // Row
            Rectangle { width: 1; height: 21; color: root.dividerColor; anchors.verticalCenter: parent.verticalCenter }

            // 3. Queue / Playlist (icon supplied by the user, redrawn in Canvas: follows the theme color)
            Item {
                width: 27; height: 27; anchors.verticalCenter: parent.verticalCenter
                Canvas {
                    id: _qIcon
                    anchors.centerIn: parent; width: 22; height: 19.5
                    property color col: root.iconColor
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
                MouseArea { anchors.fill: parent; onClicked: { root.playerVisible = true; root.searchExpanded = false; root.detailVisible = false; root.artistVisible = false; } }
            }

            // Row
            Rectangle { width: 1; height: 21; color: root.dividerColor; anchors.verticalCenter: parent.verticalCenter }

            // Back / Forward (screen history): two rounded gray buttons
            Row {
                spacing: 16
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    width: 46; height: 34; radius: 6
                    color: root.lightTheme ? "#E7E7E7" : "#26FFFFFF"
                    Canvas {
                        id: _navBackIcon
                        anchors.centerIn: parent; width: 9; height: 15
                        opacity: root.navBackCount > 0 ? 1.0 : 0.4
                        property color col: root.lightTheme ? "#7A7A7A" : "#B5B5B5"
                        onColChanged: requestPaint()
                        onPaint: {
                            var c = getContext("2d"); c.clearRect(0, 0, width, height);
                            c.strokeStyle = col; c.lineWidth = 1.6; c.lineCap = "round"; c.lineJoin = "round";
                            c.beginPath(); c.moveTo(width - 1.5, 1.5); c.lineTo(1.5, height / 2); c.lineTo(width - 1.5, height - 1.5); c.stroke();
                        }
                    }
                    MouseArea { anchors.fill: parent; enabled: root.navBackCount > 0; onClicked: root.navBack() }
                }
                Rectangle {
                    width: 46; height: 34; radius: 6
                    color: root.lightTheme ? "#E7E7E7" : "#26FFFFFF"
                    Canvas {
                        id: _navFwdIcon
                        anchors.centerIn: parent; width: 9; height: 15
                        opacity: root.navFwdCount > 0 ? 1.0 : 0.4
                        property color col: root.lightTheme ? "#7A7A7A" : "#B5B5B5"
                        onColChanged: requestPaint()
                        onPaint: {
                            var c = getContext("2d"); c.clearRect(0, 0, width, height);
                            c.strokeStyle = col; c.lineWidth = 1.6; c.lineCap = "round"; c.lineJoin = "round";
                            c.beginPath(); c.moveTo(1.5, 1.5); c.lineTo(width - 1.5, height / 2); c.lineTo(1.5, height - 1.5); c.stroke();
                        }
                    }
                    MouseArea { anchors.fill: parent; enabled: root.navFwdCount > 0; onClicked: root.navForward() }
                }
            }

            // Row
            Rectangle { width: 1; height: 21; color: root.dividerColor; anchors.verticalCenter: parent.verticalCenter }

            // Menu (Home, Last Played, Library)
            Row {
                spacing: 20
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: [{id:"home",text:qsTr("Home")}, {id:"recent",text:qsTr("Recently played")}, {id:"library",text:qsTr("Library")}]
                    Item {
                        width: _tl.implicitWidth; height: 48
                        readonly property bool isSelected: root.viewTab === modelData.id && !root.detailVisible && !root.artistVisible && !root.playerVisible
                        Text {
                            id: _tl; anchors.centerIn: parent; text: modelData.text
                            color: parent.isSelected ? root.selectedTextColor : root.iconColor
                            font.pixelSize: 20; font.weight: Font.DemiBold
                        }
                        MouseArea { anchors.fill: parent; onClicked: { root.viewTab=modelData.id; root.searchExpanded=false; root.searchTerm=""; root.detailVisible=false; root.artistVisible=false; root.playerVisible=false; _si.text=""; if(modelData.id==="library")root.loadLibrary(); } }
                    }
                }
            }

            // Login/Logout removed on request.
            }

        // ── Account avatar (on the right): tap for "Sign out" ──
        Item {
            id: _avatarBtn
            visible: root.ytLoggedIn
            width: 30; height: 30
            anchors.right: parent.right; anchors.rightMargin: 20
            y: (32 * root.u - height) / 2
            CustomImage {
                anchors.fill: parent
                isCircle: true
                source: root.ytAvatarUrl
                fallbackText: root.ytAccountName.length > 0 ? root.ytAccountName.charAt(0).toUpperCase() : "?"
            }
            MouseArea {
                anchors.fill: parent; anchors.margins: -8
                onClicked: root.avatarMenuOpen = !root.avatarMenuOpen
            }
        }
        }

    // ════════ SIGN-IN SCREEN (z=440): without an account the app is not usable ═══════════
    Rectangle {
        id: _loginGate
        anchors.fill: parent
        z: 440
        visible: !root.ytLoggedIn
        color: Theme.bg
        // blocks every touch toward the app underneath
        MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: (w) => w.accepted = true }

        // until it is known whether the account is connected (the service starts at first opening): spinner, then it retries by itself
        Spinner {
            size: 26
            anchors.centerIn: parent
            visible: !root.authChecked
            running: visible
        }
        Timer {
            interval: 1500; repeat: true
            running: _loginGate.visible && !root.authChecked
            onTriggered: root.checkAuthStatus()
        }

        Column {
            anchors.centerIn: parent
            spacing: 18
            width: Math.min(460, parent.width - 80)
            opacity: root.authChecked ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "qrc:/VoltaApp/icons/ytmusic.svg"
                width: 72; height: 72
                sourceSize: Qt.size(144, 144)
                fillMode: Image.PreserveAspectFit
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: qsTr("Sign in to YouTube Music")
                color: root.authFg
                font.pixelSize: 24; font.weight: Font.DemiBold
            }
            Item { width: 1; height: 6 }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 260; height: 52; radius: 8
                color: _gateMA.pressed ? "#1E63D0" : "#2C7BF2"
                Behavior on color { ColorAnimation { duration: 100 } }
                Text {
                    anchors.centerIn: parent
                    text: qsTr("Sign in")
                    color: "#FFFFFF"; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                MouseArea { id: _gateMA; anchors.fill: parent; enabled: root.authChecked; onClicked: root.startLogin() }
            }
        }
    }

    // ════════ FULL-PANEL ACCOUNT LOGIN PAGE (z=450, above everything else) ═══════════════
    Rectangle {
        id: _authOverlay
        anchors.fill: parent
        z: 450
        visible: root.authPopupVisible
        color: "#FFFFFF"
        MouseArea { anchors.fill: parent }

        WebEngineView {
            settings.showScrollBars: false
            id: _authWebView
            anchors.fill: parent
            lifecycleState: root.authPopupVisible ? WebEngineView.LifecycleState.Active : WebEngineView.LifecycleState.Discarded
            visible: root.authPopupUrl.length > 0
            url: root.authPopupUrl
            // Injects the capture script as soon as possible at every
            // page change (login goes from accounts.google.com to
            // music.youtube.com), instead of waiting for the timer.
            onLoadingChanged: function(loadRequest) {
                if (loadRequest.status === WebEngineView.LoadStartedStatus) {
                    root.injectCaptureScript()
                }
            }
        }
        Rectangle {
            anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 14
            width: 40; height: 40; radius: 20; color: "#CC000000"
            Text { anchors.centerIn: parent; text: "✕"; color: "#FFFFFF"; font.pixelSize: 18 }
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.closeAuthPopup() }
        }
        Rectangle {
            visible: root.authStatusText.length > 0 && root.authStatusText !== qsTr("Sign in with your Google account below: the connection is automatic.")
            anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottomMargin: 12
            width: _stTxt.width + 24; height: _stTxt.height + 16; radius: 8; color: "#CC000000"
            Text { id: _stTxt; anchors.centerIn: parent; text: root.authStatusText; color: "#FFFFFF"; font.pixelSize: 14 }
        }
    }

    // ════════ FINESTRELLA AVATAR «ESCI» (z=420) ═══════════════════════════════
    Item {
        id: _avatarMenuOverlay
        anchors.fill: parent
        z: 420
        visible: root.avatarMenuOpen

        // Click outside the little window → closes
        MouseArea { anchors.fill: parent; onClicked: root.avatarMenuOpen = false }

        Rectangle {
            width: 200
            height: _avCol.height + 12
            x: parent.width - width - 20
            y: root.headerH - 4
            radius: 10
            color: root.lightTheme ? "#FFFFFF" : "#2A2A2A"
            border.color: Theme.border
            border.width: 1

            // Absorbs clicks on the little window without closing it
            MouseArea { anchors.fill: parent }

            Column {
                id: _avCol
                width: parent.width
                y: 6
                Text {
                    visible: root.ytAccountName.length > 0
                    x: 14; width: parent.width - 28; height: 36
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: root.ytAccountName
                    color: root.iconColor
                    font.pixelSize: 15
                }
                Rectangle {
                    visible: root.ytAccountName.length > 0
                    width: parent.width; height: 1; color: root.dividerColor
                }
                Rectangle {
                    width: parent.width; height: 48
                    color: "transparent"
                    Text {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Sign out")
                        color: root.lightTheme ? "#222222" : "#FFFFFF"
                        font.pixelSize: 18
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.doLogout() }
                }
            }
        }
    }

    // ════════ MENU A TENDINA SWITCHER APP MUSICALI (z=400) ════════════════════════
    Item {
        id: _appMenuOverlay
        anchors.fill: parent
        z: 400
        visible: root.appMenuOpen

        // Click outside the menu → closes
        MouseArea { anchors.fill: parent; onClicked: root.appMenuOpen = false }

        Rectangle {
            id: _appMenuCard
            x: 20
            y: root.headerH - 6
            width: 220
            height: _appMenuCol.height + 12
            radius: 10
            color: root.lightTheme ? "#FFFFFF" : "#2A2A2A"
            border.color: Theme.border
            border.width: 1

            // Absorbs clicks on the card without closing the menu
            MouseArea { anchors.fill: parent }

            Column {
                id: _appMenuCol
                width: parent.width
                y: 6
                Repeater {
                    model: root.musicApps
                    Rectangle {
                        width: _appMenuCol.width; height: 48
                        color: "transparent"

                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12
                            Image { sourceSize: Qt.size(width * 2, height * 2);
                                source: modelData.icon
                                width: 24; height: 24; fillMode: Image.PreserveAspectFit
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: modelData.name
                                color: root.selectedTextColor
                                font.pixelSize: 16
                                font.weight: modelData.appId === root.selfAppId ? Font.DemiBold : Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.appMenuOpen = false
                                if (modelData.appId !== root.selfAppId)
                                    root.switchToApp(modelData.appId)
                            }
                        }
                    }
                }
            }
        }
    }

    // ════════ LIBRARY FILTER BAR (FIXED AT THE TOP) (z=90) ════════════════════════
    // ════════ CONTENT (it narrows when the lyrics open; the header stays whole) ════════
    Item {
        id: _lyBody
        x: 0; y: 0
        width: parent.width - root.lyricsInset; height: parent.height
        clip: root.lyricsInset > 0

    Rectangle {
        id: _libTabsHeader
        visible: root.viewTab === "library" && !root.detailVisible && !root.artistVisible && !root.searchExpanded && !root.playerVisible
        width: parent.width; height: 60
        y: root.headerH
        z: 90
        color: Theme.bg

        Row {
            anchors.fill: parent; anchors.margins: 10; anchors.leftMargin: 40; anchors.rightMargin: 40
            spacing: 14
            Repeater {
                model: ["Playlists", "Songs", "Albums", "Artists", "Podcasts"]
                Rectangle {
                    width: (parent.width - (14 * 4)) / 5
                    height: 40
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 6
                    color: root.libraryFilter === modelData ? (lightTheme?"#444444":"#FFFFFF") : (lightTheme?"#EAEAEA":"#333333")
                    Text { text: root.libLabel(modelData); anchors.centerIn: parent; color: root.libraryFilter === modelData ? (lightTheme?"#FFFFFF":"#000000") : (lightTheme?"#555555":Theme.textPrimary); font.pixelSize: 14; font.weight: Font.Medium }
                    MouseArea { anchors.fill: parent; preventStealing: true; onClicked: root.setLibraryFilter(modelData) }
                }
            }
        }
    }

    // ════════ FULL-SCREEN PLAYER SCREEN AND QUEUE (z=80) ════════════════════════
    Rectangle {
        id: _playerScreen; anchors.fill: parent; color: Theme.bg; z: 80
        visible: root.playerVisible && !root.hub; opacity: root.playerVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 240 } }

        Column {
            anchors.fill: parent; anchors.topMargin: root.headerH
            spacing: 20

            // ── Area Player Centrale ──
            Item {
                width: parent.width; height: 280

                Row {
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 40; spacing: 40

                    Column {
                        width: parent.width * 0.55; height: 260

                        Item { width: 1; height: 8 }

                        Text { text: root.currentTrack; color: Theme.textPrimary; font.pixelSize: 42; font.weight: Font.Normal; width: parent.width; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap }
                        Text { text: "🎵 " + root.currentArtist; color: Theme.textSecondary; font.pixelSize: 24; font.weight: Font.Medium; width: parent.width; elide: Text.ElideRight; maximumLineCount: 1 }

                        Item { width: 1; height: 16 }

                        Item {
                            width: parent.width; height: 64
                            Row {
                                spacing: 20
                                PlayerBtn { src: "qrc:/VoltaApp/icons/skip-back.svg"; onClicked: root.prevTrack() }
                                PlayerBtn { src: root.isPlaying ? "qrc:/VoltaApp/icons/pause.svg" : "qrc:/VoltaApp/icons/play.svg"; onClicked: root.togglePlay() }
                                PlayerBtn { src: "qrc:/VoltaApp/icons/skip-forward.svg"; onClicked: root.nextTrack() }
                                PlayerBtn { src: "qrc:/VoltaApp/icons/shuffle.svg"; toggle: true; active: root.shuffleOn; onClicked: root.toggleShuffle() }
                                PlayerBtn { src: "qrc:/VoltaApp/icons/repeat.svg"; toggle: true; active: root.repeatMode !== "off"; badge: root.repeatMode === "one" ? "1" : ""; onClicked: root.cycleRepeat() }
                            }
                        }

                        Item { width: 1; height: 16 }

                        // ── Progress bar with knob ──
                        Item {
                            width: parent.width; height: 40
                            Rectangle {
                                width: parent.width; height: 4; radius: 2; color: Theme.surfaceElevated; anchors.verticalCenter: parent.verticalCenter

                                Rectangle {
                                    id: _pbFill
                                    width: parent.width * (root.durationMs > 0 ? root.progressMs / root.durationMs : 0)
                                    height: parent.height; radius: 2; color: Theme.textPrimary
                                }

                                Rectangle {
                                    width: 12; height: 12; radius: 6; color: Theme.textPrimary
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: _pbFill.width - 6
                                }

                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -10; preventStealing: true
                                    onClicked: function(m) { root.seekPct(m.x / width) }
                                }
                            }
                            Text { text: root.fmtMs(root.progressMs); color: Theme.textSecondary; font.pixelSize: 14; anchors.left: parent.left; anchors.top: parent.bottom; anchors.topMargin: -8 }
                            Text { text: "-" + root.fmtMs(Math.max(0, root.durationMs - root.progressMs)); color: Theme.textSecondary; font.pixelSize: 14; anchors.right: parent.right; anchors.top: parent.bottom; anchors.topMargin: -8 }
                        }
                    }

                    Item {
                        width: parent.width * 0.45 - 40
                        height: 260

                        CustomImage {
                            width: 260
                            height: root.currentIsVideo ? Math.round(260 * 9 / 16) : 260
                            anchors.centerIn: parent
                            radius: 6
                            source: root.getHighResCover(root.currentCover)
                        }
                    }
                }
            }

            // ── Area Coda in Basso ──
            Column {
                width: parent.width; height: parent.height - 300
                spacing: 14
                visible: root.currentQueue && root.currentQueue.length > 0

                Text {
                    text: qsTr("Queue")
                    color: Theme.textPrimary; font.pixelSize: 22; font.weight: Font.Medium
                    leftPadding: 40
                }

                ListView {
                    width: parent.width; height: parent.height - 36
                    clip: true
                    model: root.currentQueue
                    delegate: TrackRow {
                        trackData: modelData
                        showCover: true
                        disableSwipe: true
                    }
                    footer: Item { width: 1; height: 40 }
                }
            }
        }
    }


    // ════════ SEARCH OVERLAY SCREEN (z=110) ════════════════════════════
    Rectangle {
        id: _searchOverlay
        anchors.fill: parent; color: Theme.bg; z: 110
        visible: root.searchExpanded && !root.hub; opacity: root.searchExpanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Item {
            id: _searchTop
            width: parent.width; height: root.headerH + 20
            Row {
                anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 40; spacing: 20
                Text {
                    text: "✕"; color: root.iconColor; font.pixelSize: 24; font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea { anchors.fill: parent; onClicked: { root.searchExpanded = false; root.searchTerm = ""; _si.text = ""; } }
                }
                Rectangle {
                    width: parent.width - 80; height: 44
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 8; color: "transparent"
                    border.color: Theme.surfaceElevated
                    border.width: 1

                    TextInput {
                        id: _si
                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 40
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.textPrimary; font.pixelSize: 16
                        font.weight: Font.Medium
                        onTextChanged: { root.searchTerm = text; _sd.restart() }
                        Text {
                            visible: parent.text === ""
                            text: qsTr("Search songs, albums, artists...")
                            color: Theme.textHint; font.pixelSize: 16; font.weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Rectangle {
                        visible: _si.text !== ""
                        width: 24; height: 24; radius: 12
                        color: lightTheme ? "#E0E0E0" : "#262626"
                        anchors.right: parent.right; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "✕"; color: lightTheme ? "#333" : "#CCC"; font.pixelSize: 12; font.weight: Font.Normal
                            anchors.centerIn: parent
                        }
                        MouseArea { anchors.fill: parent; onClicked: { _si.text = ""; root.searchTerm = ""; } }
                    }
                }
            }
        }

        Flickable {
            anchors.top: _searchTop.bottom; anchors.bottom: parent.bottom; width: parent.width
            contentHeight: _srcCol.childrenRect.height + 80; clip: true

            Column {
                id: _srcCol
                width: parent.width; topPadding: 10; spacing: 24

                Column {
                    visible: root.searchTerm.length === 0
                    width: parent.width; spacing: 20; leftPadding: 40
                    Text { text: qsTr("Recent Searches"); color: Theme.textPrimary; font.pixelSize: 18; font.weight: Font.Medium; visible: root.recentSearches.length > 0 }
                    Repeater {
                        model: root.recentSearches
                        Item {
                            width: _rsRow.implicitWidth; height: _rsRow.implicitHeight
                            Row {
                            id: _rsRow
                            spacing: 16
                            Canvas {
                                width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter
                                onPaint: {
                                    var c = getContext("2d"); c.clearRect(0,0,width,height);
                                    c.strokeStyle = Theme.textHint; c.lineWidth = 1.5; c.lineCap = "round";
                                    c.beginPath(); c.arc(9,9,7.5,0,2*Math.PI); c.stroke();
                                    c.beginPath(); c.moveTo(9,4); c.lineTo(9,9); c.lineTo(12,12); c.stroke();
                                }
                            }
                            Text { text: modelData; color: Theme.textPrimary; font.pixelSize: 16; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    _si.text = modelData
                                    root.searchTerm = modelData
                                    root.doSearch()
                                }
                            }
                        }
                    }
                }

                Column {
                    visible: root.searchTerm.length > 0
                    width: parent.width - 80; x: 40; spacing: 24

                    // ═══ ROW 1: Top Result + Tracks ═══
                    Row {
                        width: parent.width; spacing: 16

                        // ── Top Result: Cover reduced to 190px, stable column at 220px ──
                        Column {
                            id: _topResCol
                            width: 220; spacing: 10
                            // Prefers the real "top result" (of any type:
                            // song, video, artist, album...) and falls back to the first
                            // song found only if the backend did not provide it.
                            readonly property var topRes: root.searchTopResult || (root.searchTracks.length > 0 ? root.searchTracks[0] : null)
                            visible: _topResCol.topRes !== null
                            SearchSectionHeader { title: qsTr("Top result"); showSeeAll: false; width: parent.width }
                            CustomImage {
                                id: _topResImgRect
                                width: 190; height: 190
                                radius: _topResCol.topRes && _topResCol.topRes.type === "Artist" ? 95 : 6
                                source: _topResCol.topRes ? root.getHighResCover(_topResCol.topRes.cover) : ""
                                MouseArea {
                                    anchors.fill: parent; preventStealing: true
                                    onClicked: {
                                        var t = _topResCol.topRes
                                        if (!t) return
                                        if (t.type === "Artist") root.openArtist(t)
                                        else if (t.type === "Track" || t.type === "Video" || t.type === "Episode") root.playMedia(t)
                                        else root.openDetail(t, false)
                                    }
                                }
                            }
                            Item { width: 1; height: 4 }
                            Text {
                                text: _topResCol.topRes ? _topResCol.topRes.title : ""
                                color: Theme.textPrimary; font.pixelSize: 18; font.weight: Font.Normal
                                width: parent.width; elide: Text.ElideRight; maximumLineCount: 1
                            }
                            Text {
                                text: _topResCol.topRes ? _topResCol.topRes.subtitle : ""
                                color: Theme.textSecondary; font.pixelSize: 14
                                width: parent.width; elide: Text.ElideRight; maximumLineCount: 1
                            }
                        }

                        // ── Tracks: Grid widened to the maximum ──
                        Column {
                            width: parent.width - 236; spacing: 10
                            visible: root.searchTracks.length > 1
                            SearchSectionHeader { title: qsTr("Tracks"); width: parent.width }
                            Grid {
                                id: _songsGrid
                                width: parent.width
                                columns: 3; rows: 2
                                columnSpacing: 24; rowSpacing: 24
                                readonly property real cellW: (width - columnSpacing*2) / 3
                                Repeater {
                                    model: root.searchTracks.length > 1 ? root.searchTracks.slice(1, 7) : []
                                    Item {
                                        width: _songsGrid.cellW; height: 68
                                        Row {
                                            anchors.fill: parent; spacing: 14
                                            CustomImage {
                                                width: 68; height: 68
                                                radius: 6
                                                source: modelData.cover
                                            }
                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 82
                                                spacing: 4
                                                Text { text: modelData.title; color: Theme.textPrimary; font.pixelSize: 14; font.weight: Font.Medium; width: parent.width; elide: Text.ElideRight; maximumLineCount: 1 }
                                                Text { text: modelData.subtitle; color: Theme.textSecondary; font.pixelSize: 12; width: parent.width; elide: Text.ElideRight; maximumLineCount: 1 }
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent; preventStealing: true
                                            onClicked: root.playMedia(modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ═══ ROW 2: Albums + Playlists ═══
                    Row {
                        width: parent.width; spacing: 80

                        Column {
                            width: (parent.width - 80) / 2; spacing: 10
                            visible: root.searchAlbums.length > 0
                            SearchSectionHeader { title: qsTr("Albums"); width: parent.width }
                            Grid {
                                id: _albumGrid
                                width: parent.width; columns: 3; columnSpacing: 20; rowSpacing: 20
                                readonly property real cW: (width - columnSpacing*2) / 3
                                Repeater {
                                    model: root.searchAlbums.slice(0, 3)
                                    Item {
                                        width: _albumGrid.cW; height: _albumGrid.cW + 50
                                        CustomImage {
                                            id: _alImg
                                            width: parent.width; height: parent.width
                                            radius: 6
                                            source: root.getHighResCover(modelData.cover)
                                            MouseArea {
                                                anchors.fill: parent; preventStealing: true
                                                onClicked: root.openDetail(modelData, false)
                                            }
                                        }
                                        Text { anchors.top: _alImg.bottom; anchors.topMargin: 8; text: modelData.title; color: Theme.textPrimary; font.pixelSize: 13; font.weight: Font.Normal; width: parent.width; elide: Text.ElideRight; maximumLineCount: 1 }
                                        Text { anchors.top: _alImg.bottom; anchors.topMargin: 28; text: modelData.subtitle; color: Theme.textSecondary; font.pixelSize: 12; width: parent.width; elide: Text.ElideRight; maximumLineCount: 1 }
                                    }
                                }
                            }
                        }

                        Column {
                            width: (parent.width - 80) / 2; spacing: 10
                            visible: root.searchPlaylists.length > 0
                            SearchSectionHeader { title: qsTr("Playlist"); width: parent.width }
                            Grid {
                                id: _playlistGrid
                                width: parent.width; columns: 3; columnSpacing: 20; rowSpacing: 20
                                readonly property real cW: (width - columnSpacing*2) / 3
                                Repeater {
                                    model: root.searchPlaylists.slice(0, 3)
                                    Item {
                                        width: _playlistGrid.cW; height: _playlistGrid.cW + 50
                                        CustomImage {
                                            id: _plImg
                                            width: parent.width; height: parent.width
                                            radius: 6
                                            source: root.getHighResCover(modelData.cover)
                                            MouseArea {
                                                anchors.fill: parent; preventStealing: true
                                                onClicked: root.openDetail(modelData, false)
                                            }
                                        }
                                        Text { anchors.top: _plImg.bottom; anchors.topMargin: 8; text: modelData.title; color: Theme.textPrimary; font.pixelSize: 13; font.weight: Font.Normal; width: parent.width; elide: Text.ElideRight; maximumLineCount: 1 }
                                        Text { anchors.top: _plImg.bottom; anchors.topMargin: 28; text: modelData.subtitle; color: Theme.textSecondary; font.pixelSize: 12; width: parent.width; elide: Text.ElideRight; maximumLineCount: 1 }
                                    }
                                }
                            }
                        }
                    }

                    // ═══ ROW 3: Artists circles + VIDEO ═══
                    Row {
                        width: parent.width; spacing: 80

                        Column {
                            width: (parent.width - 80) / 2; spacing: 10
                            visible: root.searchArtists.length > 0
                            SearchSectionHeader { title: qsTr("Artists"); width: parent.width }
                            Grid {
                                id: _artistsGrid
                                width: parent.width; columns: 3; columnSpacing: 20; rowSpacing: 20
                                readonly property real cW: (width - columnSpacing*2) / 3
                                Repeater {
                                    model: root.searchArtists.slice(0, 3)
                                    Item {
                                        width: _artistsGrid.cW; height: _artistsGrid.cW + 40
                                        CustomImage {
                                            id: _arImg
                                            width: _artistsGrid.cW; height: _artistsGrid.cW
                                            isCircle: true
                                            source: modelData.cover ? root.getHighResCover(modelData.cover) : ""
                                            fallbackText: modelData.title ? modelData.title.charAt(0).toUpperCase() : "?"
                                            MouseArea {
                                                anchors.fill: parent; preventStealing: true
                                                onClicked: root.openArtist(modelData)
                                            }
                                        }
                                        Text {
                                            anchors.top: _arImg.bottom; anchors.topMargin: 10
                                            text: modelData.title; color: Theme.textPrimary
                                            font.pixelSize: 13; font.weight: Font.Medium
                                            width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; horizontalAlignment: Text.AlignHCenter
                                        }
                                    }
                                }
                            }
                        }

                        // ── Sezione Video Sostitutiva ──
                        Column {
                            width: (parent.width - 80) / 2; spacing: 10
                            visible: root.searchVideos.length > 0
                            SearchSectionHeader { title: qsTr("Video"); width: parent.width }
                            Grid {
                                id: _videosGrid
                                width: parent.width; columns: 3; columnSpacing: 20; rowSpacing: 20
                                readonly property real cW: (width - columnSpacing*2) / 3
                                Repeater {
                                    model: root.searchVideos.slice(0, 3)
                                    Item {
                                        width: _videosGrid.cW; height: _videosGrid.cW + 50
                                        CustomImage {
                                            id: _vidImg
                                            width: parent.width; height: parent.width
                                            radius: 6
                                            source: root.getHighResCover(modelData.cover)
                                            MouseArea {
                                                anchors.fill: parent; preventStealing: true
                                                onClicked: root.playMedia(modelData)
                                            }
                                        }
                                        Text { anchors.top: _vidImg.bottom; anchors.topMargin: 8; text: modelData.title; color: Theme.textPrimary; font.pixelSize: 13; font.weight: Font.Normal; width: parent.width; elide: Text.ElideRight; maximumLineCount: 1 }
                                        Text { anchors.top: _vidImg.bottom; anchors.topMargin: 28; text: modelData.subtitle; color: Theme.textSecondary; font.pixelSize: 12; width: parent.width; elide: Text.ElideRight; maximumLineCount: 1 }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ════════ ARTIST SCREEN (z=50) ═══════════════════════════════
    Rectangle {
        id: _artistScreen; anchors.fill: parent; color: Theme.bg; z: 50
        visible: root.artistVisible; opacity: root.artistVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 240 } }
        Flickable {
            x: 0; y: root.headerH; width: parent.width; height: parent.height - root.headerH
            contentHeight: _ac.childrenRect.height + 120; clip: true
            Column {
                id: _ac; width: parent.width; topPadding: 12
                Row {
                    x: 40; spacing: 28; width: parent.width-80; bottomPadding: 24
                    CustomImage {
                        id: _artBigCover
                        width: 190; height: 190; isCircle: true
                        source: root.getHighResCover(root.artistData?(root.artistData.cover||""):"")
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 10; width: parent.width-218
                        Text { text: qsTr("ARTIST"); color: Theme.textHint; font.pixelSize: 12; font.weight: Font.Medium; font.letterSpacing: 1.5 }
                        Text { text: root.artistData?(root.artistData.title||""):""; color: Theme.textPrimary; font.pixelSize: 32; font.weight: Font.Medium; width: parent.width; wrapMode: Text.Wrap }
                    }
                }
                Column { width: parent.width; spacing: 0; visible: root.artistTracks.length > 0
                    Text { text: qsTr("Most played tracks"); color: Theme.textPrimary; font.pixelSize: 20; font.weight: Font.Medium; leftPadding: 40; bottomPadding: 8 }
                    TrackListHeader {}
                    Repeater { model: root.artistTracks; delegate: TrackRow { trackData: modelData; trackIndex: index; contextTracks: root.artistTracks } }
                }
                Item { height: 20; width: 1 }
                SectionRow { title: qsTr("Albums"); items: root.artistAlbums }
                SectionRow { title: qsTr("Singles"); items: root.artistSingles }
                Item { width: 1; height: 60 }
            }
        }
    }

    // ════════ DETTAGLIO playlist/album (z=55) ════════════════════════════════
    Rectangle {
        id: _detailScreen; anchors.fill: parent; color: "transparent"; z: 55
        visible: root.detailVisible; opacity: root.detailVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 240 } }

        // Solid background (like Spotify): no more blurred background with the cover
        Rectangle { anchors.fill: parent; color: Theme.bg }

        // Base background for "Liked" playlist (LM)
        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            opacity: (root.detailItem && root.detailItem.playlistId === "LM") ? 1.0 : 0.0
        }

        Item {
            id: _detailTop
            x: 0; y: root.headerH; width: parent.width
            height: _dTopRow.height + 40
            Row {
                id: _dTopRow
                x: 40; y: 35; spacing: 28; width: parent.width-80

                Item {
                    width: 180; height: 180
                    CustomImage {
                        anchors.fill: parent
                        radius: 6
                        source: root.getHighResCover(root.detailItem?(root.detailItem.cover||""):"")
                        showPlaceholder: root.detailItem && root.detailItem.playlistId !== "LM"
                    }
                    Rectangle {
                        anchors.fill: parent; radius: 8
                        visible: root.detailItem && root.detailItem.playlistId === "LM"
                        gradient: Gradient { GradientStop{position:0;color:"#4A90E2"} GradientStop{position:1;color:"#50E3C2"} }
                        Text { anchors.centerIn: parent; text: "👍"; font.pixelSize: 72; color: "white" }
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 8; width: parent.width-208
                    Text { text: root.detailItem?(root.detailItem.title||""):""; color: Theme.textPrimary; font.pixelSize: 32; font.weight: Font.Normal; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                    Text {
                        text: (root.detailItem?(root.detailItem.type==="Playlist"?qsTr("Playlist"):qsTr("Albums")):"") + (root.detailItem && root.detailItem.subtitle ? " • " + root.detailItem.subtitle : "")
                        color: Theme.textSecondary; font.pixelSize: 15; font.weight: Font.Medium; width: parent.width; elide: Text.ElideRight; maximumLineCount: 1
                    }
                    Text { text: root.detailTracks.length+qsTr(" tracks"); color: Theme.textHint; font.pixelSize: 14 }
                    Row {
                        spacing: 16; topPadding: 6

                        // WHITE CIRCULAR PLAY BUTTON
                        Rectangle {
                            id: _playAllBtn
                            width: 52; height: 52; radius: 26
                            // Light theme: dark button with white triangle (white on white disappeared)
                            color: root.lightTheme ? (_paMA.pressed ? "#333333" : "#171717")
                                                   : (_paMA.pressed ? "#D9D9D9" : "#FFFFFF")
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Canvas {
                                anchors.centerIn: parent; anchors.horizontalCenterOffset: 3
                                width: 18; height: 22
                                property bool lt: root.lightTheme
                                onLtChanged: requestPaint()
                                onPaint: {
                                    var c = getContext("2d"); c.clearRect(0,0,width,height)
                                    c.fillStyle = lt ? "#FFFFFF" : "#000000"
                                    c.beginPath(); c.moveTo(0,0); c.lineTo(0,22); c.lineTo(18,11); c.closePath(); c.fill()
                                }
                            }
                            MouseArea {
                                id: _paMA; anchors.fill: parent; preventStealing: true
                                onClicked: if (root.detailTracks.length > 0) root.playContext(root.detailTracks, 0)
                            }
                        }

                        // CIRCULAR SHUFFLE BUTTON
                        Rectangle {
                            width: 52; height: 52; radius: 26
                            color: "transparent"; border.color: Theme.textSecondary; border.width: 1
                            Image { sourceSize: Qt.size(width * 2, height * 2);
                                anchors.centerIn: parent; width: 22; height: 22
                                source: "qrc:/VoltaApp/icons/shuffle.svg"
                                layer.enabled: true; layer.effect: MultiEffect { colorization: 1.0; colorizationColor: Theme.textPrimary }
                            }
                            MouseArea {
                                anchors.fill: parent; preventStealing: true
                                // Shuffle play of the list: first turns Shuffle on, then starts
                                onClicked: if (root.detailTracks.length > 0) {
                                    var tr = root.detailTracks, i0 = Math.floor(Math.random() * tr.length)
                                    root.shuffleOn = true; root._lastModeMs = Date.now()
                                    root.scraperGet("/player/shuffle?state=1", function(d) { root._applyModes(d); root.playContext(tr, i0) })
                                }
                            }
                        }
                    }
                }
            }
        }

        TrackListHeader {
            id: _detailColHdr
            anchors.top: _detailTop.bottom; anchors.topMargin: 20
            showDivider: false
        }

        ListView {
            x: 0; anchors.top: _detailColHdr.bottom; anchors.topMargin: 4
            width: parent.width; height: _detailScreen.height - (_detailColHdr.y + _detailColHdr.height) - 4
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.detailTracks
            delegate: TrackRow { trackData: modelData; trackIndex: index; contextTracks: root.detailTracks; showCover: false }
            footer: Item { width: 1; height: 60 }
        }
    }


    // ════════ DASHBOARD (z=0) ════════════════════════════════════════════════
    PullRefresh {
        target: _mainFlick
        onRefresh: { root.loadHome(true); root.loadRecents(); root.loadLibrary() }
    }
    Flickable {
        id: _mainFlick; x: 0
        y: root.headerH + (root.viewTab === "library" ? 60 : 0)
        width: parent.width
        height: parent.height - y
        contentHeight: _mc.childrenRect.height + 60; clip: true

        Column {
            id: _mc; width: parent.width; topPadding: 0; spacing: 0

            // ── TAB HOME (Dinamico) ──
            Column {
                visible: root.viewTab==="home"; width: parent.width; spacing: 0; topPadding: 18 * root.u


                Repeater {
                    model: root.homeShelves
                    Item {
                        width: parent.width
                        height: modelData.title === "Scelte rapide" ? _qpRow.height : _secRow.height

                        QuickPicksRow {
                            id: _qpRow
                            title: modelData.title
                            items: modelData.items
                            visible: modelData.title === "Scelte rapide"
                        }

                        SectionRow {
                            id: _secRow
                            title: modelData.title
                            items: modelData.items
                            isCircle: modelData.isCircle === true
                            visible: modelData.title !== "Scelte rapide"
                        }
                    }
                }
            }

            // ── TAB RECENTI ──
            Column {
                visible: root.viewTab==="recent"; width: parent.width; spacing: 0; topPadding: 24
                TrackListHeader { visible: root.homeRecent.length > 0 }
                Repeater {
                    model: root.homeRecent
                    delegate: TrackRow { trackData: modelData; trackIndex: index; contextTracks: root.homeRecent }
                }
            }

            // ── TAB LIBRERIA ──
            Column {
                visible: root.viewTab==="library"; width: parent.width; spacing: 20; topPadding: 24

                GridView {
                    id: _libGrid
                    visible: root.libraryFilter !== "Songs"
                    width: parent.width - 80; x: 40
                    height: Math.ceil(count / 5) * cellHeight
                    cellWidth: width / 5; cellHeight: cellWidth + 60
                    model: root.libraryItems
                    interactive: false
                    delegate: Item {
                        width: _libGrid.cellWidth - 14; height: _libGrid.cellHeight - 14
                        Column {
                            width: parent.width
                            spacing: 8

                            Item {
                                width: parent.width; height: parent.width
                                CustomImage {
                                    anchors.fill: parent
                                    isCircle: root.libraryFilter === "Artists"
                                    radius: 6
                                    source: modelData.cover||""
                                    showPlaceholder: modelData.playlistId !== "LM"
                                    MouseArea {
                                        anchors.fill: parent; preventStealing: true
                                        onClicked: {
                                            if(root.libraryFilter === "Artists") root.openArtist(modelData);
                                            else root.openDetail(modelData, true);
                                        }
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent; visible: modelData.playlistId === "LM"
                                    radius: 8
                                    gradient: Gradient { GradientStop{position:0;color:"#4A90E2"} GradientStop{position:1;color:"#50E3C2"} }
                                    Text { anchors.centerIn: parent; text: "👍"; font.pixelSize: parent.width*0.4; color: "white" }
                                }
                            }

                            Text { text: modelData.title||""; color: Theme.textPrimary; font.pixelSize: 14; font.weight: Font.Normal; width: parent.width; elide: Text.ElideRight; maximumLineCount: 1 }
                            Text { text: modelData.subtitle||""; color: Theme.textSecondary; font.pixelSize: 13; width: parent.width; elide: Text.ElideRight; maximumLineCount: 1 }
                        }
                    }
                }

                Column {
                    visible: root.libraryFilter === "Songs"
                    width: parent.width; spacing: 0
                    TrackListHeader { visible: root.libraryItems.length > 0 }
                    Repeater { model: root.libraryItems; delegate: TrackRow { trackData: modelData; trackIndex: index } }
                }
            }
        }
    }
    }

    // ════════ UNIFIED QUEUE (shared with Spotify / YT Music / Bluetooth) ════════
    MediaQueuePanel {
        anchors.fill: parent; z: 80
        hub: root.hub
        lightTheme: root.lightTheme
        topPadding: root.headerH
        visible: root.hub !== null && root.playerVisible
        opacity: root.playerVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 240 } }
    }

    // ════════ UNIFIED SEARCH (YT Music + Spotify) ════════
    MediaSearchPanel {
        id: _uSearch
        defaultFilter: "ytmusic"   // dl58
        anchors.fill: parent; z: 110
        hub: root.hub
        lightTheme: root.lightTheme
        headerH: root.headerH
        visible: root.hub !== null && root.searchExpanded
        opacity: root.searchExpanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        onClosed: root.searchExpanded = false
    }


    // ════════ LYRICS: state (the real panel is LyricsSheet, inside AppPanel) ════════
    property bool lyricsOpen: false
    property bool lyricsExpanded: false
    property real lyricsInset: 0      // how much the content (not the header) narrows on the right

    // Any touch on the header closes the lyrics (the touch then reaches the buttons below, as always)
    Item {
        z: 101; x: 0; y: 0; width: parent.width; height: root.headerH
        enabled: root.lyricsOpen
        MouseArea { anchors.fill: parent; onPressed: mouse => { mouse.accepted = false; root.lyricsOpen = false } }
    }

    // With the search open, opening the lyrics goes back to the app's home (same effect as the "Home" button at the top)
    function lyricsGoHome() {
        root.viewTab = "home"; root.searchExpanded = false; root.searchTerm = ""
        root.detailVisible = false; root.artistVisible = false; root.playerVisible = false
        _si.text = ""
    }
}