import QtQuick

// ─────────────────────────────────────────────────────────────────────────────
//  AudioFocus — SINGLE AUDIO ARBITER ("one source at a time")
//
//  Philosophy: we do not trust the scattered signals of the individual apps (that was the weak
//  point of the previous versions). Here there is ONE judge that, at regular
//  intervals, queries the REAL state of each source and applies a
//  simple rule: "the last one to start playing wins, all the others are paused".
//
//  Stability:
//   • Self-healing: if an event is lost, the next reconcile fixes it.
//   • Echo-guard: when we force a pause, we ignore for a moment the state of
//     that source, so the resulting "paused" does not re-trigger the logic.
//
//  Sources and how they are controlled (the project's real backends):
//   • ytmusic  → scraper HTTP :8099  (/player/status, /player/pause?state=1)
//   • spotify  → scraper HTTP :8098  (/player/status, /player/pause?state=1)
//   • theater  → WebEngine (YouTube): JS on <video>/<audio>
//   • browser  → WebEngine: JS on <video>/<audio>
//   • radio    → RadioView (appPanel.radioIsPlaying / appPanel.radioStop)
//
//  ytmusic, spotify and bluetooth, when they are present on the system player
//  (Mpris, C++ over D-Bus), are read and paused from there: immediate
//  state, without querying the HTTP services. Switching player between them
//  is already done by Mpris ("the last one to start wins"); here what remains is coordinating them with
//  radio, Theater e browser interni.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: focus

    // ── References injected by Main.qml ──
    property var mainRoot: null      // for getAppWebView(src)
    property var appPanel: null      // for radioIsPlaying / radioStop

    // ── Source that holds the focus now (read-only to the outside) ──
    property string owner: ""

    // ── Configurazione (tarabile a runtime) ──
    property int  reconcileMs: 600   // how often it re-checks the real state
    property int  suppressMs:  1400  // echo-guard window after a forced pause
    property bool debug:       false // true → console log for on-device debugging

    // ── Stato interno ──
    property var _playing:  ({})     // last "is playing" state per source
    property var _suppress: ({})     // timestamp until which to ignore the source

    readonly property var _sources: ["ytmusic", "spotify", "theater", "browser", "radio", "bluetooth"]

    function _now() { return Date.now() }
    function _isSuppressed(s) { return (focus._suppress[s] || 0) > _now() }
    function _log(msg) { if (focus.debug) console.log("[AudioFocus]", msg) }

    // ── Capabilities per source (for the UI: different commands for different apps) ──
    // like: "heart" (Spotify) | "thumb" (YT Music/YouTube) | "none"
    function capabilities(src) {
        switch (src) {
        case "spotify": return { prev: true,  next: true,  seek: true,  shuffle: true,  like: "heart" }
        case "ytmusic": return { prev: true,  next: true,  seek: true,  shuffle: true,  like: "thumb" }
        case "theater": return { prev: false, next: false, seek: true,  shuffle: false, like: "none"  }
        case "browser": return { prev: false, next: false, seek: false, shuffle: false, like: "none"  }
        case "radio":   return { prev: false, next: false, seek: false, shuffle: false, like: "none"  }
        case "bluetooth": return { prev: true, next: true,  seek: false, shuffle: false, like: "none"  }
        }
        return { prev: false, next: false, seek: false, shuffle: false, like: "none" }
    }

    // ── Source-specific PAUSE (+ arms the echo-guard) ──
    function _viaMpris(src) { return typeof Mpris !== "undefined" && Mpris.hasSource(src) }

    function _pause(src) {
        focus._suppress[src] = _now() + focus.suppressMs
        focus._playing[src]  = false
        _log("pausa forzata → " + src)
        if (_viaMpris(src))         Mpris.pauseSource(src)
        else if (src === "ytmusic") _httpGet("http://127.0.0.1:8099/player/pause?state=1")
        else if (src === "spotify") _httpGet("http://127.0.0.1:8098/player/pause?state=1")
        // Music from the phone (AVRCP): same format as the other services
        else if (src === "bluetooth") _httpGet("http://127.0.0.1:9097/bt/player/pause?state=1")
        else if (src === "radio") {
            if (appPanel && typeof appPanel.radioStop === "function") appPanel.radioStop()
        } else if (src === "theater" || src === "browser") {
            var wv = mainRoot ? mainRoot.getAppWebView(src) : null
            if (wv) wv.runJavaScript("document.querySelectorAll('audio,video').forEach(function(e){try{e.pause()}catch(x){}});")
        }
    }

    function _httpGet(url) {
        try {
            var x = new XMLHttpRequest()
            x.open("GET", url + (url.indexOf('?') >= 0 ? '&' : '?') + "_t=" + _now())
            x.send()
        } catch (e) {}
    }

    // Becomes the focus owner: pauses all the others that are playing
    function _setOwner(src) {
        if (focus.owner !== src) _log("nuovo owner: " + src)
        focus.owner = src
        for (var i = 0; i < focus._sources.length; i++) {
            var o = focus._sources[i]
            if (o !== src && focus._playing[o]) _pause(o)
        }
    }

    // Can a source TAKE the focus (become owner)?
    // Webviews (theater/browser) only if they are the foreground app: a video in
    // autoplay/background must NEVER steal the audio from music/radio.
    function _canClaim(src) {
        if (src === "theater" || src === "browser")
            return appPanel && appPanel.activeApp === src
        return true
    }

    // Heart of the logic: receives the real state of a source and decides.
    function _note(src, isPlaying) {
        var was = focus._playing[src] || false
        focus._playing[src] = isPlaying
        if (focus._isSuppressed(src)) return          // echo-guard: ignore for a moment
        if (isPlaying && !was) {                       // rising edge
            if (_canClaim(src)) _setOwner(src)
            else                _pause(src)            // webview in the background that starts → stop it, it does not steal
            return
        }
        if (isPlaying && focus.owner === "") {         // no owner
            if (_canClaim(src)) _setOwner(src)
            else                _pause(src)
            return
        }
        if (isPlaying && focus.owner !== src) { _pause(src); return }  // non-owner that plays → stop it (self-healing)
    }

    // ── PROBE of the real state of each source ──
    function _probeHttp(src, port, path) {
        var x = new XMLHttpRequest()
        x.open("GET", "http://127.0.0.1:" + port + (path || "/player/status") + "?_t=" + _now())
        x.onreadystatechange = function() {
            if (x.readyState === XMLHttpRequest.DONE) {
                if (x.status === 200) {
                    try { _note(src, !!JSON.parse(x.responseText).is_playing) } catch (e) {}
                }
                // If the backend does not answer, we do not touch the state (no false "paused")
            }
        }
        try { x.send() } catch (e) {}
    }

    function _probeWebview(src) {
        var wv = mainRoot ? mainRoot.getAppWebView(src) : null
        if (!wv) { _note(src, false); return }
        wv.runJavaScript(
            "(function(){var m=document.querySelector('audio,video');return !!(m && !m.paused && !m.muted && m.volume>0);})()",
            function(r) { _note(src, !!r) }
        )
    }

    function _probeRadio() {
        _note("radio", appPanel ? !!appPanel.radioIsPlaying : false)
    }

    // ── Optional public APIs (fast-path/manual, if needed in the future) ──
    // Forces a source as owner immediately (useful for physical buttons).
    function claim(src) { _setOwner(src) }
    // Releases the focus without starting anything.
    function release() { focus.owner = "" }

    // ── Reconcile loop: queries ALL the sources at regular intervals ──
    Timer {
        interval: focus.reconcileMs
        running: true
        repeat: true
        onTriggered: {
            _probeMedia("ytmusic", 8099, "")
            _probeMedia("spotify", 8098, "")
            _probeWebview("theater")
            _probeWebview("browser")
            _probeRadio()
            _probeMedia("bluetooth", 9097, "/bt/player")
        }
    }
    function _probeMedia(src, port, path) {
        if (_viaMpris(src)) _note(src, Mpris.isPlaying(src))
        else                _probeHttp(src, port, path || "/player/status")
    }

    // Fast-path: a system player has just started
    Connections {
        target: typeof Mpris !== "undefined" ? Mpris : null
        function onSourceStartedPlaying(src) {
            if (focus._sources.indexOf(src) >= 0) {
                // It is a real start (not an echo): it must be treated as a rising edge
                focus._suppress[src] = 0
                focus._playing[src]  = false
                focus._note(src, true)
            } else {
                // Lettore esterno (browser/altro): ferma radio e video interni
                for (var i = 0; i < focus._sources.length; i++)
                    if (focus._playing[focus._sources[i]]) focus._pause(focus._sources[i])
                focus.owner = ""
            }
        }
    }
}
