import QtQuick
import QtCore as Core

// ─────────────────────────────────────────────────────────────────────────────
//  MediaHub — THE "BIG PICTURE" OF MEDIA PLAYBACK
//
//  YT Music, Spotify and Bluetooth (music from the phone) are three "providers"
//  of the same system. This object, unique and shared by the three apps,
//  offre:
//   • Now playing: the current track, whatever the provider (even
//     the one playing from the phone over Bluetooth).
//   • A UNIFIED QUEUE: the tracks added from any app, even mixing
//     different providers (e.g. a Spotify track after a YT Music one), followed
//     by the "next ones" of the provider that is playing.
//   • A UNIFIED SEARCH: queries YT Music and Spotify in parallel; the
//     results can be filtered by provider.
//   • The Bluetooth state (connected devices, connected phone) also used
//     by Phone, Messages and the Bluetooth app.
//
//  Provider keys = values of audioSrc in Main.qml:
//     "ytmusic"   → YtMusicDashboard  (servizio :8099, app id "spotify")
//     "spotify"   → SpotifyDashboard  (servizio :8098, app id "spotifyapp")
//     "bluetooth" → telefono via AVRCP (servizio :9097, app id "bluetooth")
//
//  Playback state and commands come from the SYSTEM PLAYER
//  (Mpris, C++ over D-Bus): mpv for YT Music, spotifyd for Spotify,
//  mpris-proxy for the phone. The apps' services remain for search,
//  library and queue (YT Music manages its own queue: next/previous,
//  shuffle and repeat still go through its service). If a player is not
//  present on the bus we fall back to the app's service.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: hub
    visible: false

    // ── Injected by AppPanel ──
    property var yt: null                 // YtMusicDashboard
    property var sp: null                 // SpotifyDashboard
    property string audioSrc: ""          // source that is playing (Main.audioSrc)

    signal switchToApp(string appId)
    signal openBluetoothSettings()
    signal bluetoothActivated()           // the phone started playing

    readonly property var providers: ["ytmusic", "spotify", "localmusic"]      // cercabili
    function providerName(p) {
        return p === "ytmusic" ? qsTr("YT Music") : p === "spotify" ? qsTr("Spotify") : p === "bluetooth" ? qsTr("Bluetooth")
             : p === "localmusic" ? qsTr("Music") : ""
    }
    function providerIcon(p) {
        return p === "ytmusic" ? "qrc:/VoltaApp/icons/ytmusic.svg"
             : p === "spotify" ? "qrc:/VoltaApp/icons/spotify.svg"
             : p === "bluetooth" ? "qrc:/VoltaApp/icons/bluetooth.svg"
             : p === "localmusic" ? "qrc:/VoltaApp/icons/localmusic.svg" : ""
    }
    function providerAppId(p) {
        return p === "ytmusic" ? "spotify" : p === "spotify" ? "spotifyapp" : p === "bluetooth" ? "bluetooth" : p === "localmusic" ? "localmusic" : ""
    }
    function dashFor(p) { return p === "ytmusic" ? hub.yt : p === "spotify" ? hub.sp : null }

    // Unique key of an item (to avoid duplicates)
    function itemKey(it) {
        if (!it) return ""
        var d = it.data || it
        return (it.provider || "") + ":" + (d.videoId || d.id || d.title || "")
    }

    // ══════════════════════ BLUETOOTH ══════════════════════
    readonly property string btUrl: "http://127.0.0.1:9097"

    property var  btDevices: []
    // true after the first valid answer from the Bluetooth service: until it
    // arrives we do not know whether the phone is connected (no empty warnings)
    property bool devicesLoaded: false
    readonly property var connectedDevices: btDevices.filter(function(d) { return d.connected })
    // Phone connected: connected device with "phone" icon (or, if BlueZ
    // gives no icon, any connected device)
    readonly property var connectedPhone: {
        var list = hub.connectedDevices
        for (var i = 0; i < list.length; i++) if (list[i].icon === "phone") return list[i]
        for (var j = 0; j < list.length; j++) if (!list[j].icon) return list[j]
        return null
    }
    readonly property bool phoneConnected: connectedPhone !== null

    property bool   btAvailable: false
    property string btDevice: ""
    property bool   btPlaying: false
    property string btTitle: ""
    property string btArtist: ""
    property string btAlbum: ""
    property real   btProgressMs: 0
    property real   btDurationMs: 1

    function _get(url, cb) {
        // the YT Music / Spotify services start only when needed
        if (url.indexOf(":8099") > 0) Services.ensure("ytmusic")
        else if (url.indexOf(":8098") > 0) Services.ensure("spotify")
        else if (url.indexOf(":8097") > 0) Services.ensure("localmusic")
        var x = new XMLHttpRequest()
        x.open("GET", url + (url.indexOf("?") >= 0 ? "&" : "?") + "_t=" + Date.now())
        x.onreadystatechange = function() {
            if (x.readyState === XMLHttpRequest.DONE) {
                var d = null
                if (x.status === 200) { try { d = JSON.parse(x.responseText) } catch (e) {} }
                if (cb) cb(d)
            }
        }
        try { x.send() } catch (e) {}
    }

    function refreshDevices() {
        _get(hub.btUrl + "/bt/devices", function(d) {
            if (d && d.devices && !d.error) { hub.btDevices = d.devices; hub.devicesLoaded = true }
        })
    }
    // Event-driven Bluetooth: the service answers /bt/wait only when BlueZ signals a
    // change (device, track, play/pause), after 25 s at most. Before, devices were
    // asked every 5 s and the player every second, forever.
    property int _btVer: -1
    property bool _btWaiting: false
    function _btWaitLoop() {
        if (hub._btWaiting) return
        hub._btWaiting = true
        var x = new XMLHttpRequest()
        x.open("GET", hub.btUrl + "/bt/wait?v=" + hub._btVer)
        x.timeout = 40000
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return
            hub._btWaiting = false
            var d = null
            try { d = JSON.parse(x.responseText) } catch (e) {}
            if (x.status !== 200 || !d) { btWaitRetry.interval = 3000; btWaitRetry.restart(); return }
            if (d.v !== hub._btVer) {
                hub._btVer = d.v
                hub.refreshDevices()
                if (!hub.viaMpris("bluetooth")) hub.refreshBtPlayer()
            }
            btWaitRetry.interval = 50; btWaitRetry.restart()
        }
        try { x.send() } catch (e) { hub._btWaiting = false }
    }
    Timer { id: btWaitRetry; interval: 1500; running: true; repeat: false; onTriggered: hub._btWaitLoop() }
    // safety net: one check every 60 s anyway
    Timer { interval: 60000; running: true; repeat: true; onTriggered: hub.refreshDevices() }

    // Track position: BlueZ does not report it continuously, so only WHILE the
    // phone is playing it is re-read every second (with mpris-proxy it already comes from the
    // system player).
    Timer {
        interval: 1000; running: hub.btPlaying && !hub.viaMpris("bluetooth"); repeat: true
        onTriggered: hub.refreshBtPlayer()
    }
    function refreshBtPlayer() {
        hub._get(hub.btUrl + "/bt/player", function(d) {
            if (!d) return
            var wasPlaying = hub.btPlaying
            hub.btAvailable  = !!d.available
            hub.btDevice     = d.device || ""
            hub.btPlaying    = !!d.is_playing
            hub.btTitle      = d.track ? (d.track.title || "") : ""
            hub.btArtist     = d.track ? (d.track.subtitle || "") : ""
            hub.btAlbum      = d.track ? (d.track.album || "") : ""
            hub.btProgressMs = d.progress_ms || 0
            hub.btDurationMs = d.duration_ms || 1
            if (hub.btPlaying && !wasPlaying) hub.bluetoothActivated()
        })
    }

    // ══════════════════════ LETTORE DI SISTEMA (MPRIS) ══════════════════════
    readonly property bool mprisReady: typeof Mpris !== "undefined" && Mpris !== null
    readonly property var  mprisSources: mprisReady ? Mpris.sources : []
    function viaMpris(p) { return hub.mprisSources.indexOf(p) >= 0 }
    // MPRIS state of a source (for the active one: interpolated position)
    function mprisState(p) {
        if (!hub.viaMpris(p)) return null
        if (Mpris.activeSource === p)
            return { title: Mpris.title, artist: Mpris.artist, artUrl: Mpris.artUrl, playing: Mpris.playing,
                     positionMs: Mpris.positionMs, lengthMs: Mpris.lengthMs, shuffle: Mpris.shuffle,
                     loopStatus: Mpris.loopStatus, canSeek: Mpris.canSeek }
        return Mpris.players[p] || null
    }
    function loopToMode(l)  { return l === "Track" ? "one" : l === "Playlist" ? "all" : "off" }
    function modeToLoop(m)  { return m === "one" ? "Track" : m === "all" ? "Playlist" : "None" }

    // Phone via mpris-proxy: same fields as before, now from the system player
    readonly property var btMpris: hub.mprisState("bluetooth")
    onBtMprisChanged: {
        if (!hub.btMpris) return
        var was = hub.btPlaying
        hub.btAvailable  = true
        hub.btPlaying    = hub.btMpris.playing
        // Not all phones/apps send title and artist over AVRCP (mpris-proxy
        // depends on what the phone exposes: it is not something we control from
        // here) — when it is playing but nothing arrives, a generic
        // indication is better than an empty title or the (old) one of the previous track.
        hub.btTitle      = hub.btMpris.title !== "" ? hub.btMpris.title
                           : (hub.btMpris.playing ? qsTr("Playing from phone") : "")
        hub.btArtist     = hub.btMpris.title !== "" ? (hub.btMpris.artist || "") : ""
        hub.btProgressMs = hub.btMpris.positionMs || 0
        hub.btDurationMs = hub.btMpris.lengthMs > 0 ? hub.btMpris.lengthMs : 1
        if (!hub.btDevice && hub.connectedPhone) hub.btDevice = hub.connectedPhone.name || ""
        if (hub.btPlaying && !was) hub.bluetoothActivated()
    }

    function btCommand(cmd) {
        if (hub.viaMpris("bluetooth")) {
            if (cmd === "play") Mpris.playSource("bluetooth")
            else if (cmd === "pause") Mpris.pauseSource("bluetooth")
            else if (cmd === "next") Mpris.nextSource("bluetooth")
            else if (cmd === "prev") Mpris.previousSource("bluetooth")
            return
        }
        var x = new XMLHttpRequest()
        x.open("POST", hub.btUrl + "/bt/player/" + cmd)
        try { x.send() } catch (e) {}
        if (cmd === "play")  hub.btPlaying = true
        if (cmd === "pause") hub.btPlaying = false
    }

    // ══════════════════════ IN RIPRODUZIONE ══════════════════════
    // Provider shown in the widget. If audioSrc is not a provider (e.g. "mpris"
    // for an echo of the system player) we fall back to the one that is playing
    // or has a track loaded: so pause/next/previous in the queue
    // funzionano comunque.
    readonly property string activeProvider: {
        if (audioSrc === "ytmusic" || audioSrc === "spotify" || audioSrc === "bluetooth") return audioSrc
        // Music (PC files / sticks): it announces itself as the "Music" player, which for the widget is a generic source ("mpris")
        if (hub.mprisReady && (audioSrc === "mpris" || audioSrc === "") && Mpris.hasActive && Mpris.activeIdentity === "Musica") return "localmusic"
        // System player: the active one, if it is one of our providers
        if (hub.mprisReady) {
            var a = Mpris.activeSource
            if ((a === "ytmusic" || a === "spotify" || a === "bluetooth") && (Mpris.playing || audioSrc === "mpris" || audioSrc === ""))
                return a
        }
        if (hub.yt && hub.yt.isPlaying) return "ytmusic"
        if (hub.sp && hub.sp.isPlaying) return "spotify"
        if (audioSrc === "mpris" || audioSrc === "") {
            if (hub.btPlaying) return "bluetooth"
            if (hub.yt && hub.yt.currentTrack) return "ytmusic"
            if (hub.sp && hub.sp.currentTrack) return "spotify"
        }
        return ""
    }

    // Last active music provider: repeat/shuffle stay usable even when the widget
    // briefly shows something else (Theater video, external player)
    property string _lastProvider: ""
    onActiveProviderChanged: if (activeProvider === "ytmusic" || activeProvider === "spotify" || activeProvider === "localmusic") _lastProvider = activeProvider
    readonly property string modeProvider: (activeProvider === "ytmusic" || activeProvider === "spotify" || activeProvider === "localmusic") ? activeProvider : _lastProvider

    readonly property var nowPlaying: {
        var p = hub.activeProvider
        if (p === "localmusic" && hub.mprisReady && Mpris.title !== "")
            return { provider: p, title: Mpris.title, subtitle: Mpris.artist, cover: Mpris.artUrl, isPlaying: Mpris.playing,
                     progressMs: Mpris.positionMs, durationMs: Mpris.lengthMs > 0 ? Mpris.lengthMs : 1, isVideo: false, canSeek: Mpris.canSeek }
        var d = hub.dashFor(p)
        var m = hub.mprisState(p)
        if (m && m.title !== "") {
            // Cover: the player's; for YT Music, until it arrives, the app's
            var cover = m.artUrl || (d && d.currentTrack === m.title ? d.currentCover : "")
            return { provider: p, title: m.title, subtitle: m.artist, cover: cover,
                     isPlaying: m.playing, progressMs: m.positionMs, durationMs: m.lengthMs > 0 ? m.lengthMs : 1,
                     isVideo: d ? (d.currentIsVideo || false) : false,
                     device: p === "bluetooth" ? hub.btDevice : "", canSeek: m.canSeek }
        }
        if (p === "bluetooth")
            return { provider: p, title: hub.btTitle, subtitle: hub.btArtist, cover: "",
                     isPlaying: hub.btPlaying, progressMs: hub.btProgressMs, durationMs: hub.btDurationMs,
                     isVideo: false, device: hub.btDevice, canSeek: false }
        if (!d) return null
        return { provider: p, title: d.currentTrack, subtitle: d.currentArtist, cover: d.currentCover,
                 isPlaying: d.isPlaying, progressMs: d.progressMs, durationMs: d.durationMs,
                 isVideo: d.currentIsVideo || false, canSeek: true }
    }
    readonly property bool hasNowPlaying: nowPlaying !== null && nowPlaying.title !== ""

    // ══════════════════════ MUSIC (PC files and sticks) ══════════════════════
    // Provider "localmusic": service :8097 (local_music_service.py). Title, cover and position come from the
    // system player (identity "Music"); the queue and modes are read from the service while Music is the active provider.
    readonly property string lmUrl: "http://127.0.0.1:8097"
    property var  lmQueue: []         // items { id, title, subtitle, cover, duration } in playback order
    property int  lmPos: -1
    property bool lmShuffle: false
    property string lmRepeat: "off"
    function lmCover(akey) { return akey ? hub.lmUrl + "/cover/" + akey + ".jpg" : "" }
    function _fmtSec(sec) {
        sec = Math.max(0, Math.round(sec || 0))
        var m = Math.floor(sec / 60), s = sec % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }
    // Service track → providers' format (title/subtitle/cover/duration)
    function lmTrack(t) {
        return { id: t.id, title: t.title, subtitle: t.artist + (t.album ? " · " + t.album : ""), cover: hub.lmCover(t.akey),
                 duration: hub._fmtSec(t.dur), lmKind: "track" }
    }
    // Service's /search results in the common form: tracks / albums / artists
    function lmSearchShape(d) {
        if (!d) return {}
        var tr = [], al = [], ar = []
        for (var i = 0; i < (d.tracks || []).length; i++) { var t = hub.lmTrack(d.tracks[i]); t.ctx = "search:" + hub.searchTerm; tr.push(t) }
        for (var j = 0; j < (d.albums || []).length; j++) { var a = d.albums[j]
            al.push({ title: a.album, subtitle: a.artist, cover: hub.lmCover(a.key), lmKind: "album", raw: a }) }
        for (var k = 0; k < (d.artists || []).length; k++) { var r = d.artists[k]
            ar.push({ title: r.name, subtitle: r.count + qsTr(" tracks"), cover: hub.lmCover(r.akey), lmKind: "artist", raw: r, type: "Artist" }) }
        return { tracks: tr, albums: al, artists: ar, videos: [], playlists: [] }
    }
    function refreshLm() {
        hub._get(hub.lmUrl + "/player/queue", function(d) {
            if (!d) return
            var out = []
            for (var i = 0; i < (d.queue || []).length; i++) out.push(hub.lmTrack(d.queue[i]))
            hub.lmQueue = out; hub.lmPos = d.pos
        })
        hub._get(hub.lmUrl + "/player/status", function(d) {
            if (!d) return
            hub.lmShuffle = !!d.shuffle; hub.lmRepeat = d.repeat || "off"
        })
    }
    Timer { interval: 2500; repeat: true; triggeredOnStart: true; running: hub.activeProvider === "localmusic" || hub.modeProvider === "localmusic" && hub.hasNowPlaying
            onTriggered: hub.refreshLm() }
    Connections { target: hub; function onActiveProviderChanged() { if (hub.activeProvider === "localmusic") hub.refreshLm() } }

    // Request to the Music app (it opens by itself): { kind: "queue" | "search" | "album" | "artist", data, n }
    property var lmRequest: null
    property int _lmReqN: 0
    function requestLm(kind, data) {
        hub.lmRequest = { kind: kind, data: data || null, n: ++hub._lmReqN }
        hub.switchToApp("localmusic")
    }

    // ══════════════════════ CODA UNICA ══════════════════════
    // userQueue: tracks added by the user that belong to a provider
    // DIFFERENT from the one playing (those of the same provider go
    // directly into its native queue, so they stay in the right order
    // for its controls too). Items: { provider, data }.
    property var userQueue: []

    // "Next" of the provider that is playing
    readonly property var providerQueue: {
        if (hub.activeProvider === "localmusic") {
            var lq = hub.lmQueue, lo = []
            for (var k = hub.lmPos + 1; k < lq.length; k++) lo.push({ provider: "localmusic", data: lq[k] })
            return lo
        }
        var d = hub.dashFor(hub.activeProvider)
        var q = d ? (d.currentQueue || []) : []
        var out = []
        for (var i = 0; i < q.length; i++) out.push({ provider: hub.activeProvider, data: q[i] })
        return out
    }

    // Complete queue in the order in which it will be played
    readonly property var combinedQueue: userQueue.concat(providerQueue)

    function addToQueue(provider, data) {
        if (!data) return
        if (provider === "localmusic" && hub.activeProvider === "localmusic") {
            // Music that is playing: right after the current track of its queue
            hub._get(hub.lmUrl + "/player/enqueue?next=1&id=" + encodeURIComponent(data.id), function() { hub.refreshLm() })
        } else if (provider === hub.activeProvider && hub.dashFor(provider)) {
            // Same provider playing: native queue (right after the current track)
            hub.dashFor(provider).enqueueNext(data)
        } else if (hub.activeProvider === "" || !hub.hasNowPlaying) {
            // Nothing is playing: starts right away
            hub.play(provider, data)
            return
        } else {
            var item = { provider: provider, data: data }
            for (var i = 0; i < hub.userQueue.length; i++)
                if (hub.itemKey(hub.userQueue[i]) === hub.itemKey(item)) return
            hub.userQueue = hub.userQueue.concat([item])
        }
        hub.toast(qsTr("Added to queue · ") + (data.title || ""))
    }

    function removeFromQueue(index) {
        if (index < 0 || index >= hub.userQueue.length) return
        var q = hub.userQueue.slice()
        q.splice(index, 1)
        hub.userQueue = q
    }

    function clearUserQueue() { hub.userQueue = [] }

    // Plays a track on its provider. Main.qml pauses the previous
    // source when the new provider signals that it is playing.
    function play(provider, data) {
        if (provider === "localmusic") {
            if (data) hub._get(hub.lmUrl + "/play?id=" + encodeURIComponent(data.id) + "&ctx=" + encodeURIComponent(data.ctx || "single"), function() { hub.refreshLm() })
            return
        }
        var d = hub.dashFor(provider)
        if (!d || !data) return
        d.playMedia(data)
    }

    // Tap on an item of the unified queue
    function playQueueItem(index) {
        var q = hub.combinedQueue
        if (index < 0 || index >= q.length) return
        var it = q[index]
        if (index >= hub.userQueue.length && it.provider === "localmusic") {   // Music's next ones: jump to that point of its queue
            hub._get(hub.lmUrl + "/player/jump?pos=" + (hub.lmPos + 1 + index - hub.userQueue.length), function() { hub.refreshLm() })
            return
        }
        if (index < hub.userQueue.length) hub.removeFromQueue(index)
        hub.play(it.provider, it.data)
    }

    // ── Controlli unificati (widget musica, coda, app) ──
    // "provider" optional: by default the one shown.
    function togglePlay(provider) {
        var p = provider || hub.activeProvider
        if (p === "localmusic") { hub._get(hub.lmUrl + "/player/pause", function() { hub.refreshLm() }); return }
        if (hub.viaMpris(p)) { Mpris.playPauseSource(p); return }
        if (p === "bluetooth") { hub.btCommand(hub.btPlaying ? "pause" : "play"); return }
        var d = hub.dashFor(p)
        if (d) d.togglePlay()
    }
    function _repeatOneActive(p) {
        return hub.repeatMode === "one" && (p === "ytmusic" || p === "spotify") && hub.hasNowPlaying
    }
    function restartCurrent(p) {
        hub._repKey = ""
        hub.seekPct(0, p)
        var np = hub.nowPlaying
        if (np && !np.isPlaying) hub.togglePlay(p)
    }
    function next(provider) {
        // First the tracks added by the user, then the provider's next ones
        // (with "repeat one" active the song is restarted, see below)
        if (hub.userQueue.length > 0 && !hub._repeatOneActive(provider || hub.activeProvider)) {
            var it = hub.userQueue[0]
            hub.removeFromQueue(0)
            hub.play(it.provider, it.data)
            return
        }
        var p = provider || hub.activeProvider
        // Repeat one: next/previous do not change song, they restart it from the beginning
        if (hub._repeatOneActive(p)) { hub.restartCurrent(p); return }
        // YT Music: mpv plays one track at a time, the queue belongs to its service
        if (p === "localmusic") { hub._get(hub.lmUrl + "/player/next", function() { hub.refreshLm() }); return }
        if (p === "ytmusic") { if (hub.yt) hub.yt.nextTrack(); return }
        if (hub.viaMpris(p)) { Mpris.nextSource(p); return }
        if (p === "bluetooth") { hub.btCommand("next"); return }
        var d = hub.dashFor(p)
        if (d) d.nextTrack()
    }
    function prev(provider) {
        var p = provider || hub.activeProvider
        if (hub._repeatOneActive(p)) { hub.restartCurrent(p); return }
        if (p === "localmusic") { hub._get(hub.lmUrl + "/player/prev", function() { hub.refreshLm() }); return }
        if (p === "ytmusic") { if (hub.yt) hub.yt.prevTrack(); return }
        if (hub.viaMpris(p)) { Mpris.previousSource(p); return }
        if (p === "bluetooth") { hub.btCommand("prev"); return }
        var d = hub.dashFor(p)
        if (d) d.prevTrack()
    }
    // ── Heart: "Like" on YT Music / "Liked Songs" on Spotify ──
    // State per track (provider:id), read from the service at track change and
    // updated right away on tap.
    property var likedMap: ({})
    readonly property string likeKey: {
        var p = hub.activeProvider, d = hub.dashFor(p)
        return (d && d.currentTrackId) ? p + ":" + d.currentTrackId : ""
    }
    readonly property bool canLike: likeKey !== ""
    readonly property bool isLiked: likeKey !== "" && hub.likedMap[likeKey] === true
    onLikeKeyChanged: {
        var k = hub.likeKey
        if (k === "" || hub.likedMap[k] !== undefined) return
        var p = k.split(":")[0], id = k.substring(p.length + 1)
        hub._get(hub.searchUrls[p] + "/player/liked/" + encodeURIComponent(id), function(d) {
            if (!d) return
            var m = Object.assign({}, hub.likedMap); m[k] = !!d.liked; hub.likedMap = m
        })
    }
    // Heart pressed inside an app (track rows): keeps the mini player aligned
    function setLiked(p, id, on) {
        if (!id) return
        var m = Object.assign({}, hub.likedMap); m[p + ":" + id] = on; hub.likedMap = m
    }
    function toggleLike() {
        var k = hub.likeKey
        if (k === "") return
        var p = k.split(":")[0], id = k.substring(p.length + 1)
        var on = !hub.isLiked
        var m = Object.assign({}, hub.likedMap); m[k] = on; hub.likedMap = m
        hub._get(hub.searchUrls[p] + "/player/like/" + encodeURIComponent(id) + "?action=" + (on ? "LIKE" : "INDIFFERENT"),
                 function(d) {
                     if (d && d.status === "error") {          // not saved (e.g. missing login)
                         var m2 = Object.assign({}, hub.likedMap); m2[k] = !on; hub.likedMap = m2
                         hub.toast(qsTr("Unable to save to favorites of ") + hub.providerName(p))
                     }
                 })
    }

    // ── Shuffle / Repeat of the unified queue ──
    // The state comes from the provider that is playing (YT Music / Spotify: their
    // service really reshuffles the following tracks and repeats them). The
    // "user queue" part (tracks added by hand, even from another app) is
    // reshuffled here and put back in order when shuffle is turned off.
    readonly property bool canModes: modeProvider === "ytmusic" || modeProvider === "spotify" || modeProvider === "localmusic"
    // Spotify: shuffle/repeat directly on spotifyd (MPRIS).
    // YT Music: its service handles them, which owns the queue.
    // (spotifyd does not accept Shuffle/Repeat via MPRIS: we go through the Spotify API of the
    //  service, which is also the source of the state. MPRIS stays only if not logged in.)
    readonly property bool _modesViaMpris: hub.modeProvider === "spotify" && hub.viaMpris("spotify")
                                           && (!hub.sp || hub.sp.needsLogin)
    readonly property bool shuffleOn: {
        if (hub.modeProvider === "localmusic") return hub.lmShuffle
        if (hub._modesViaMpris) { var m = hub.mprisState("spotify"); return m ? !!m.shuffle : false }
        var d = hub.dashFor(hub.modeProvider); return d ? d.shuffleOn : false
    }
    // Without login to Spotify's API, spotifyd does not accept Repeat via MPRIS: the state is kept here and the
    // loop is done by the interface (see repeatOneTimer)
    property string _localRepeat: "off"
    readonly property string repeatMode: {
        if (hub.modeProvider === "localmusic") return hub.lmRepeat
        if (hub._modesViaMpris) return hub._localRepeat
        var d = hub.dashFor(hub.modeProvider); return d ? d.repeatMode : "off"
    }
    property var _userQueueOrig: []

    function toggleShuffle() {
        var lm = hub.modeProvider === "localmusic"
        var d = lm ? ({}) : hub.dashFor(hub.modeProvider)
        if (!d) return
        var on = !hub.shuffleOn
        if (on) {
            hub._userQueueOrig = hub.userQueue.slice()
            var q = hub.userQueue.slice()
            for (var i = q.length - 1; i > 0; i--) {
                var j = Math.floor(Math.random() * (i + 1)); var t = q[i]; q[i] = q[j]; q[j] = t
            }
            hub.userQueue = q
        } else if (hub._userQueueOrig.length > 0) {
            // puts back in order the tracks still in the queue; the new ones stay at the end
            var keys = hub._userQueueOrig.map(function(it) { return hub.itemKey(it) })
            var cur = hub.userQueue.slice()
            cur.sort(function(a, b) {
                var ia = keys.indexOf(hub.itemKey(a)), ib = keys.indexOf(hub.itemKey(b))
                return (ia < 0 ? 1e6 : ia) - (ib < 0 ? 1e6 : ib)
            })
            hub.userQueue = cur
            hub._userQueueOrig = []
        }
        if (lm) { hub.lmShuffle = on; hub._get(hub.lmUrl + "/player/shuffle?state=" + (on ? 1 : 0), function() { hub.refreshLm() }) }
        else if (hub._modesViaMpris) Mpris.setSourceShuffle("spotify", on)
        else d.setShuffle(on)
    }
    function cycleRepeat() {
        var lm = hub.modeProvider === "localmusic"
        var d = lm ? ({}) : hub.dashFor(hub.modeProvider)
        if (!d) return
        // First tap = repeat the song (the most common case), then the whole queue, then off
        var m = hub.repeatMode === "off" ? "one" : hub.repeatMode === "one" ? "all" : "off"
        hub.toast(m === "one" ? qsTr("Repeat: this song") : m === "all" ? qsTr("Repeat: whole queue") : qsTr("Repeat: off"))
        if (lm) { hub.lmRepeat = m; hub._get(hub.lmUrl + "/player/repeat?mode=" + m, function() { hub.refreshLm() }) }
        else if (hub._modesViaMpris) { hub._localRepeat = m; Mpris.setSourceLoopStatus("spotify", hub.modeToLoop(m)) }
        else d.setRepeat(m)
    }

    // "Repeat one" guaranteed: if less than ~1 s is left to the end, the track is brought back to 0.
    // It applies to any provider and is a safety net for the services' loops (mpv, Spotify).
    property string _repKey: ""
    Timer {
        id: repeatOneTimer
        interval: 300; repeat: true
        running: hub.repeatMode === "one" && hub.hasNowPlaying && hub.activeProvider !== "localmusic"   // Music repeats by itself (mpv)
        onTriggered: {
            var np = hub.nowPlaying
            if (!np || !np.isPlaying || np.durationMs < 5000) return
            var key = np.provider + ":" + np.title + ":" + np.durationMs
            var left = np.durationMs - np.progressMs
            if (left > 3500) { if (hub._repKey === key) hub._repKey = ""; return }   // restarted: armed again
            if (left > 1000 || hub._repKey === key) return
            hub._repKey = key
            hub.seekPct(0, np.provider)
        }
    }

    function seekPct(pct, provider) {
        var p = provider || hub.activeProvider
        if (p === "localmusic") { hub._get(hub.lmUrl + "/player/seek?pct=" + pct.toFixed(4)); return }
        if (hub.viaMpris(p)) { Mpris.seekSourceToFraction(p, pct); return }
        var d = hub.dashFor(p)
        if (d) d.seekPct(pct)
    }

    // Automatic switch to the next track of the unified queue when the
    // current track is about to end: otherwise the provider would continue with its
    // own next ones ignoring the tracks added from another app.
    property string _advancedFor: ""
    Timer {
        interval: 400; running: hub.userQueue.length > 0; repeat: true
        onTriggered: {
            var np = hub.nowPlaying
            if (!np || !np.isPlaying || np.durationMs < 5000) return
            var key = np.provider + ":" + np.title
            if (hub._advancedFor === key) return
            if (np.durationMs - np.progressMs <= 1200) {
                hub._advancedFor = key
                hub.next()
            }
        }
    }

    // ══════════════════════ UNIFIED SEARCH ══════════════════════
    property string searchTerm: ""
    property string searchFilter: "all"            // "all" | "ytmusic" | "spotify" | "localmusic"
    property var    results: ({ ytmusic: null, spotify: null, localmusic: null })
    property var    loading: ({ ytmusic: false, spotify: false, localmusic: false })
    readonly property bool searching: loading.ytmusic || loading.spotify || loading.localmusic
    property int    _searchSeq: 0

    readonly property var searchUrls: ({ ytmusic: "http://127.0.0.1:8099", spotify: "http://127.0.0.1:8098", localmusic: "http://127.0.0.1:8097" })

    function search(q) {
        q = (q || "").trim()
        hub.searchTerm = q
        var seq = ++hub._searchSeq
        if (q.length < 2) {
            hub.results = { ytmusic: null, spotify: null, localmusic: null }
            hub.loading = { ytmusic: false, spotify: false, localmusic: false }
            return
        }
        hub.loading = { ytmusic: true, spotify: true, localmusic: true }
        for (var i = 0; i < hub.providers.length; i++) (function(p) {
            hub._get(hub.searchUrls[p] + "/search?q=" + encodeURIComponent(q), function(d) {
                if (seq !== hub._searchSeq) return          // risposta vecchia: ignora
                var r = Object.assign({}, hub.results); r[p] = (p === "localmusic") ? hub.lmSearchShape(d) : (d || {})
                hub.results = r
                if (p === "ytmusic" && d && hub.yt)
                    hub.yt.prefetch((d.top_result && d.top_result.videoId ? [d.top_result] : []).concat(d.tracks || []))
                var l = Object.assign({}, hub.loading); l[p] = false
                hub.loading = l
            })
        })(hub.providers[i])
    }

    function _tag(p, list) {
        var out = []
        for (var i = 0; i < (list || []).length; i++) out.push({ provider: p, data: list[i] })
        return out
    }
    function _merge(field) {
        var lists = []
        for (var k = 0; k < hub.providers.length; k++) {
            var p = hub.providers[k]
            lists.push((hub.searchFilter === "all" || hub.searchFilter === p) && hub.results[p] ? hub._tag(p, hub.results[p][field]) : [])
        }
        // Alternates the providers so that all of them appear at the top
        var out = [], n = 0
        for (var j = 0; j < lists.length; j++) n = Math.max(n, lists[j].length)
        for (var i = 0; i < n; i++) for (var m = 0; m < lists.length; m++) if (i < lists[m].length) out.push(lists[m][i])
        return out
    }
    readonly property var resultTracks:    { results; searchFilter; return _merge("tracks") }
    readonly property var resultVideos:    { results; searchFilter; return _merge("videos") }
    readonly property var resultAlbums:    { results; searchFilter; return _merge("albums") }
    readonly property var resultArtists:   { results; searchFilter; return _merge("artists") }
    readonly property var resultPlaylists: { results; searchFilter; return _merge("playlists") }

    // Recent searches shared between apps
    Core.Settings {
        id: hubSettings
        category: "mediahub"
        property string recentJson: "[]"
    }
    readonly property var recentSearches: {
        try { return JSON.parse(hubSettings.recentJson) } catch (e) { return [] }
    }
    function pushRecent(q) {
        q = (q || "").trim()
        if (q.length < 2) return
        var lst = [q]
        var old = hub.recentSearches
        for (var i = 0; i < old.length && lst.length < 8; i++)
            if (old[i].toLowerCase() !== q.toLowerCase()) lst.push(old[i])
        hubSettings.recentJson = JSON.stringify(lst)
    }
    function clearRecent() { hubSettings.recentJson = "[]" }

    // Opens album / playlist / artist in the app of its provider
    function openInProvider(provider, data) {
        if (provider === "localmusic") { hub.requestLm(data.lmKind || "album", data); return }
        var d = hub.dashFor(provider)
        if (!d || !data) return
        hub.switchToApp(hub.providerAppId(provider))
        d.searchExpanded = false
        d.playerVisible = false
        if (data.type === "Artist") d.openArtist(data)
        else d.openDetail(data)
    }

    // ── Short message (shown by the shared panels) ──
    property string toastText: ""
    function toast(t) { hub.toastText = t; toastTimer.restart() }
    Timer { id: toastTimer; interval: 2200; onTriggered: hub.toastText = "" }
}
