import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Shapes
import QtWebSockets
import Qt5Compat.GraphicalEffects
import QtCore as Core
import VoltaApp 1.0
import QtWayland.Compositor
import QtWayland.Compositor.XdgShell

Window {
    id: root
    visible: true

    property var nativeSurfaces:  ({})
    property var nativeToplevels: ({})
    property var nativeShells:    ({})

    readonly property var _fa: Qt.application.arguments.filter(function(x){ return x.indexOf("--window=") === 0 || x.indexOf("--finestra=") === 0 })
    readonly property bool _win: _fa.length > 0
    readonly property var _wh: _win ? _fa[0].substring(_fa[0].indexOf("=") + 1).split("x") : [0, 0]
    visibility: _win ? Window.Windowed : Window.FullScreen
    width:  _win ? parseInt(_wh[0]) : Screen.width
    height: _win ? parseInt(_wh[1]) : Screen.height
    minimumWidth:  _win ? parseInt(_wh[0]) : 0
    maximumWidth: _win ? parseInt(_wh[0]) : 16777215
    minimumHeight: _win ? parseInt(_wh[1]) : 0
    maximumHeight: _win ? parseInt(_wh[1]) : 16777215
    title:  "Volta OS"
    color:  lightTheme ? "#FFFFFF" : "#171717"
    property bool lightTheme: false
    property bool rightHandDrive: false
    property color ambientColor: "#0A84FF"
    // "off" | "on" | "night" — see evalAmbient(). ambientOn is the RESOLVED
    // EFFECTIVE state (off/on right now), the one that one day
    // would drive a real hardware output (LED strip); for now,
    // like ambientColor, it stays application state only — no physical
    // ambient light on this Smart that is actually driven.
    property string ambientMode: "on"
    property bool   ambientOn: true
    property int    ambientBrightness: 100
    property color carColor: "#C8C9CA"
    // Simulated brightness (no real backlight to drive) and blue light
    // filter: applied as veils over the whole window, see at the bottom
    // of the file (after the StatusBar, so they really cover everything).
    property int  screenBrightness: 100
    property bool blueLightFilterOn: false
    property bool screenCleanActive: false

    Core.Settings {
        id: uiPrefs
        category: "ui"
        property string themeMode: "dark"
        property string autoStart: "19:00"
        property string autoEnd:   "07:00"
        property bool   rightHand: false
        property string ambient:   "#0A84FF"
        property string ambientMode: "on"
        property int    ambientBrightness: 100
        property string carColor:  "#C8C9CA"
        property string mapStyle:  "flat"
        property string satNight:  "auto"     // effetto notte satellite: off | on | auto
        property real   homeLat:   0
        property real   homeLon:   0
        property real   workLat:   0
        property real   workLon:   0
        property int    brightness: 100
        property bool   blueLightFilter: false
        property string hiddenApps: ""
        // Resume the last track (or radio station) at startup — Settings
        // › Audio; read by root.tryResumePlayback()
        property bool   resumePlayback: true
        // Toybox
        property bool   marsMode: false
        property bool   lowPower: false            // Impostazioni › Sistema › Modalita' basse prestazioni
        // "Full-screen map" mode (large-EV style) — Settings
        // › Navigation. See carPanelItem/mapLayer/carSlotMapBlur below.
        property bool   fullScreenMap: false
        Component.onCompleted: {
            Theme.lowPower = uiPrefs.lowPower
            root.rightHandDrive = rightHand
            root.ambientColor   = ambient
            root.ambientMode    = ambientMode
            root.ambientBrightness = ambientBrightness
            root.carColor       = carColor
            root.screenBrightness  = brightness
            root.blueLightFilterOn = blueLightFilter
            // Reapplies the real filter at startup if it was active the last
            // time: redshift/gammastep do not "remember" anything by themselves between
            // restarts, so it is up to us to relaunch it here.
            if (blueLightFilter) root.applyBlueLightFilter(true)
            root.evalTheme()
            root.evalAmbient()
        }
    }

    // Brings the color chosen in the Settings to the 3D car (car3DView
    // inside CarPanel) every time it changes — same scheme already used for
    // ambientColor, with the same defensive guard as onCarFullScreenChanged
    // (car3DView might not be ready yet in the very first instants).
    onCarColorChanged: {
        if (carPanelItem && carPanelItem.car3DView)
            carPanelItem.car3DView.carPaintColor = root.carColor
    }

    // "Night" window shared by the automatic theme and the "Night only"
    // ambient lights — a single time to configure (in Display), not two.
    function isNightNow() {
        var now = new Date()
        var cur = now.getHours() * 60 + now.getMinutes()
        var ps = uiPrefs.autoStart.split(":"), pe = uiPrefs.autoEnd.split(":")
        var s = parseInt(ps[0]) * 60 + parseInt(ps[1])
        var e = parseInt(pe[0]) * 60 + parseInt(pe[1])
        return s <= e ? (cur >= s && cur < e) : (cur >= s || cur < e)
    }

    function evalTheme() {
        if (uiPrefs.themeMode === "light") { root.lightTheme = true;  return }
        if (uiPrefs.themeMode === "dark")  { root.lightTheme = false; return }
        root.lightTheme = !root.isNightNow()
    }

    // Night effect of the satellite map
    property bool satNightActive: false
    function evalSatNight() {
        root.satNightActive = uiPrefs.satNight === "on" || (uiPrefs.satNight === "auto" && root.isNightNow())
    }
    Timer {
        interval: 30000; repeat: true; triggeredOnStart: true
        running: true
        onTriggered: root.evalSatNight()
    }

    function evalAmbient() {
        if (uiPrefs.ambientMode === "off") { root.ambientOn = false; return }
        if (uiPrefs.ambientMode === "on")  { root.ambientOn = true;  return }
        root.ambientOn = root.isNightNow() // "night"
    }

    // ── Luci ambientali FISICHE (strisce Bluetooth BLEDOM) ────────────────
    // Service luci_service.py (port 8096). Color/brightness/on-off chosen in
    // Settings → Lights are sent to the strip; they are repeated as soon as
    // the strip (re)connects.
    property bool luciLinked: false
    function luciGet(path, cb) {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return
            var j = null
            if (x.status === 200) { try { j = JSON.parse(x.responseText) } catch (e) {} }
            if (cb) cb(j)
        }
        x.open("GET", "http://127.0.0.1:8096" + path)
        x.send()
    }
    function pushAmbient() {
        if (!root.luciLinked) return
        if (!root.ambientOn) { root.luciGet("/power?on=0"); return }
        var c = root.ambientColor
        root.luciGet("/color?r=" + Math.round(c.r * 255) + "&g=" + Math.round(c.g * 255) + "&b=" + Math.round(c.b * 255), function() {
            root.luciGet("/brightness?v=" + root.ambientBrightness)
        })
    }
    Timer { id: ambPush; interval: 200; repeat: false; onTriggered: root.pushAmbient() }
    onAmbientColorChanged:      ambPush.restart()
    onAmbientOnChanged:         ambPush.restart()
    onAmbientBrightnessChanged: ambPush.restart()
    Timer {
        interval: 4000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: root.luciGet("/status", function(j) {
            var c = !!(j && j.connected)
            if (c && !root.luciLinked) { root.luciLinked = true; ambPush.restart() }
            else root.luciLinked = c
        })
    }

    Timer {
        interval: 30000; repeat: true
        running: uiPrefs.themeMode === "auto"
        onTriggered: root.evalTheme()
    }
    Timer {
        interval: 30000; repeat: true
        running: uiPrefs.ambientMode === "night"
        onTriggered: root.evalAmbient()
    }

    // REAL blue light filter: uses GNOME's native Night Light
    // (gsd-color + Mutter), no longer redshift/gammastep/sct from the terminal.
    // The reason for the change: those tools, launched from inside our
    // process, talked to the Wayland socket of OUR nested compositor
    // ("wayland-volta", VoltaCompositor.qml) which does not implement
    // wlr-gamma-control — they failed silently. But the session on this
    // machine is NOT our bare compositor: it is a real GNOME
    // Shell/Mutter session (confirmed: gsd-color, mutter-x11-frames,
    // gnome-shell all active), with our compositor nested inside
    // as a simple client window. Mutter really owns the physical
    // output, so the gamma it applies also touches the pixels of
    // our UI. gsd-color is already running and listens to dconf: the same
    // gsettings keys that drive GNOME's "Night Light" panel
    // are enough (the one in the screenshot you sent us).
    //
    // Every time THIS switch is used we also force the
    // schedule to "manual" with hours 0–24: so turning on/off
    // from the dashboard always has an immediate effect, without depending on
    // the time of day or on a different schedule set
    // separately in GNOME's system settings.
    function applyBlueLightFilter(on) {
        var schema = "org.gnome.settings-daemon.plugins.color"
        sysHelper.runDetached("gsettings", ["set", schema, "night-light-schedule-automatic", "false"])
        sysHelper.runDetached("gsettings", ["set", schema, "night-light-schedule-from", "0.0"])
        sysHelper.runDetached("gsettings", ["set", schema, "night-light-schedule-to", "24.0"])
        sysHelper.runDetached("gsettings", ["set", schema, "night-light-temperature", "4200"])
        sysHelper.runDetached("gsettings", ["set", schema, "night-light-enabled", on ? "true" : "false"])
    }

    // Sites (browser, theater, web apps) follow the UI theme: prefers-color-scheme
    onLightThemeChanged: { Theme.light = lightTheme; Qt.styleHints.colorScheme = lightTheme ? Qt.Light : Qt.Dark }
    property bool   carFullScreen: true
    property bool   appPanelFull:  false
    property bool   showGrid:      false
    property string activeApp:     ""
    property int    volume:        50
    // Scale diagnostics: prints logical sizes and DPR (look for "[SCALA]" in the terminal)
    Timer { interval: 1500; running: debugMode; repeat: false
        onTriggered: console.log("[SCALE] logical window", root.width + "x" + root.height,
            qsTr("| DPR"), root.screen.devicePixelRatio, qsTr("| fisici"), Math.round(root.width * root.screen.devicePixelRatio) + "x" + Math.round(root.height * root.screen.devicePixelRatio),
            qsTr("| uPx"), root.uPx.toFixed(3)) }
    property var _resumeList: []      // sources that were playing when the music was paused
    property bool resumeGuardOff: false
    property bool _callAudioPaused: false   // music paused by the call in progress
    // During a call or a game the music must stay still: if something starts anyway (e.g. the
    // song that the app resumes by itself at startup) it is paused again.
    Timer {
        id: audioGuard; interval: 400; repeat: true; running: root._callAudioPaused || root.gameRunning
        onTriggered: {
            var hb = appPanel.hub
            if (!hb || root.resumeGuardOff) return
            if ((hb.yt && hb.yt.isPlaying) || (hb.sp && hb.sp.isPlaying) || appPanel.radioIsPlaying) root.pauseAllAudio()
        }
    }
    property bool   carLocked: true        // car lock (status bar); to be connected to the sensor
    property bool   appReady:      false

    property string audioSrc:      ""
    // Last MUSIC source (not video): when Theater/browser/Arcade leave the widget, we go back to this
    property string lastMusicSrc:  ""
    onAudioSrcChanged: {
        if (audioSrc === "ytmusic" || audioSrc === "spotify" || audioSrc === "bluetooth" || audioSrc === "radio")
            lastMusicSrc = audioSrc
    }
    readonly property bool audioSrcIsWeb: audioSrc === "theater" || audioSrc === "browser"
                                          || audioSrc === "arcade" || audioSrc === "chrome"
    // Brings the widget back to the last music (paused): title, artist and cover go back to those of the song
    function restoreMusic() {
        var s = root.lastMusicSrc
        if (s === "") return false
        root.audioSrc = s
        if (s === "ytmusic" || s === "spotify") {
            var d = appPanel.hub ? appPanel.hub.dashFor(s) : null
            if (d && d.currentTrack) {
                root.widgetTitle   = d.currentTrack
                root.widgetArtist  = d.currentArtist || ""
                root.widgetArtwork = d.currentCover || ""
            }
            root.isPlaying = false
        }
        root.applyMpris()
        return true
    }
    // Left Theater/browser/Arcade with the video stopped: the widget goes back to the music
    Timer {
        id: webLeaveTimer
        interval: 1500; repeat: false
        onTriggered: if (root.audioSrcIsWeb && root.activeApp !== root.audioSrc && !audioFocus._playing[root.audioSrc]) root.restoreMusic()
    }
    property real   _lastExplicitSwitchMs: 0
    property string widgetTitle:   "Nothing playing"
    // true half a second after a full-screen app covers everything: the car's 3D stops being drawn
    property bool   carCovered:    false
    // GPS: true if a valid position arrived in the last few seconds (status bar icon)
    property bool   gpsFresh:      false
    property double _gpsLastFix:   0
    // Settings › 3D car: we go back to the car view, where the adjustment / loading is done
    // during the car setup the music stops (the widgets are hidden)
    Connections {
        target: carPanelItem.car3DView
        function onConfiguringChanged() { if (carPanelItem.car3DView.configuring) root.pauseAllExcept("") }
    }
    function showCarView() { root.activeApp = ""; root.appPanelFull = false; root.showGrid = false; root.carFullScreen = true }
    Connections {
        target: CarModels
        function onAdjustRequested() { root.showCarView() }
        function onSetupRequested() { root.showCarView() }
        function onReloadRequested() { root.showCarView() }
    }
    Connections { target: Gps; function onUpdated(d) { root._gpsLastFix = Date.now(); root.gpsFresh = true } }
    Timer { interval: 1000; repeat: true; running: true; onTriggered: root.gpsFresh = (Date.now() - root._gpsLastFix) < 4000 }
    Timer { id: carCoverTimer; interval: 600; onTriggered: root.carCovered = root.appPanelFull }
    property bool   slotMusic:     false   // bottom-left slot: false = blue bar, true = music player
    property real   slotPos:       0       // carousel position 0..1 (animated; follows the finger during the swipe)
    property real   slotHint:      0       // small periodic "peek" that hints at the swipe
    property bool   slotAnimOn:    true
    Behavior on slotPos { enabled: root.slotAnimOn; NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
    readonly property real slotEff: Math.max(0, Math.min(1, slotPos + (slotMusic ? -slotHint : slotHint)))
    readonly property real slotW: 393 * uPx
    readonly property real slotTravel: slotW + 14 * uPx
    function setSlot(m) { root.slotAnimOn = true; root.slotMusic = m; root.slotPos = m ? 1 : 0 }
    onWidgetTitleChanged: {
        // Universal reset: every time the TRACK (title) changes,
        // regardless of whether it comes from the same app
        // (skip/new song) or from a different app — not only when the
        // source changes. QML emits this signal only when the
        // value really CHANGES, so the periodic polling that
        // rewrites the same title does not fire it needlessly.
        if (root.widgetTitle !== "" && root.widgetTitle !== "Nothing playing") {
            root.progressPct = 0
            root.progressSec = 0
            root.durationSec = 0
        }
    }
    property string widgetArtist:  ""
    property string widgetArtwork: ""
    property real   progressSec:   0
    property real   durationSec:   0
    property real   progressPct:   0
    property bool   isPlaying:     false
    property bool   isLiked:       false
    property bool   shuffleOn:     false
    property bool   repeatOn:      false
    property bool   radioPlaying:  false
    property string currentTime:   ""

    property real dragCarStartWidth: 0
    property real dragCarStartX:     0
    property real dragAppStartY:     0
    property bool isDraggingCar:     false
    property bool isDraggingApp:     false
    // finger speed (px/ms) to recognize fast swipes
    property real dragCarVel: 0
    property real dragCarLastX: 0
    property real dragCarLastT: 0
    property real dragAppVel: 0
    property real dragAppLastT: 0

    property bool isTogglingFullscreen: false

    // Full-screen entrance "bottom to top" (same animation
    // as the games panel in Arcade: 320ms, OutCubic) for the apps that
    // require it — Theater and Toybox (Romance mode). The panel goes
    // IMMEDIATELY to full size but starts below the screen (offset = height)
    // and rises to 0. The fsSliding flag switches off the other y animations.
    property bool fsSliding: false
    property real fsSlideOffset: 0
    readonly property var fsSlideApps: ["theater", "toybox"]
    NumberAnimation {
        id: fsSlideAnim
        target: root; property: "fsSlideOffset"
        to: 0; duration: 320; easing.type: Easing.OutCubic
        onStopped: root.fsSliding = false
    }
    function enterFullscreenSlide() {
        fsSlideAnim.stop()
        root.isTogglingFullscreen = false      // niente espansione laterale
        root.fsSliding = true
        root.fsSlideOffset = root.height
        root.appPanelFull = true
        fsSlideAnim.from = root.height
        fsSlideAnim.start()
    }
    function _cancelFullscreenSlide() {
        fsSlideAnim.stop()
        root.fsSliding = false
        root.fsSlideOffset = 0
    }
    property bool isPanelAnimating: false

    // True while an icon is dragged from the drawer toward the dock.
    // Map and app panel are made temporarily non-interactive
    // (see mapLayer/appPanel below) so they cannot "steal" the
    // mouse grab from the drag when the cursor passes over them —
    // it was the cause of the drag that broke only outside the
    // car panel (see also the grabPermissions fix in AppPanel.qml).
    property bool dockDragActive: false
    // Reference unit: 1 px of the wireframe (canvas 1070 px wide) = uPx logical px.
    // Dock, car panel and widgets are defined in wireframe px and scale with the window.
    readonly property real uPx: (width > 0 ? width : 1200) / 1070
    readonly property real dockScale: 54 * uPx / 72              // dock alta 54 px wireframe
    readonly property real dockInnerH: 72 * 57.8 / 54            // internal dock height (internal units): 57.8 wireframe px on screen
    readonly property real dockVisualH: dockBar.height * dockScale   // real height of the dock on screen
    // How much the dock rises in edit mode (same animation as dockBg in DockBar.qml):
    // music, notifications and volume follow it, so they go up and down together.
    property real dockLift: dockBar.editMode ? dockBar.editGrowth * dockScale : 0
    Behavior on dockLift { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    readonly property real carMinW: 411 * uPx                    // reduced car panel: 411 wireframe px

    Timer {
        id: panelAnimTimer
        interval: 400
        onTriggered: root.isPanelAnimating = false
    }

    property real carW: carFullScreen ? width : carMinW

    onCarFullScreenChanged: {
        if (carPanelItem && carPanelItem.car3DView)
            carPanelItem.car3DView.resetView(false, root.carFullScreen)
    }

    Behavior on carW {
        enabled: !root.isDraggingCar
        // id: needed by mapLayer so as NOT to add a second animation on top of
        // this one (see mapLayer below).
        NumberAnimation { id: carWAnim; duration: 400; easing.type: Easing.OutCubic }
    }

    onAppPanelFullChanged: {
        if (appPanelFull) carCoverTimer.restart(); else { carCoverTimer.stop(); carCovered = false }
        root.isPanelAnimating = true
        panelAnimTimer.restart()
    }

    onActiveAppChanged: {
        root.isPanelAnimating = true
        panelAnimTimer.restart()
        if (root.audioSrcIsWeb && activeApp !== root.audioSrc) webLeaveTimer.restart()
        // heavy services: they start only at the first opening of the app that uses them
        if (activeApp === "spotify") Services.ensure("ytmusic")
        else if (activeApp === "spotifyapp") Services.ensure("spotify")
        else if (activeApp === "podcast") Services.ensure("podcast")
        else if (activeApp === "localmusic") Services.ensure("localmusic")

        if (activeApp !== "") {
            carFullScreen = false
            showGrid = false
        }
        // NOTE: before, here there was "root.audioSrc = media[activeApp]" +
        // pauseAllExcept(...) — it fired merely on OPENING an app (even
        // without pressing play), overwriting the music widget with
        // the app just opened and pausing what was
        // really playing. Now audioSrc only changes when
        // audioSourceActivated arrives (real playback confirmed), see
        // the Connections on appPanel above/below.
    }

    SystemHelper { id: sysHelper }

    AudioFocus {
        id: audioFocus
        mainRoot: root
        appPanel: appPanel
    }

    function getHighResArt(url) {
        if (!url) return ""
        if (url.includes("i.scdn.co/image/"))
            return url.replace(/ab67616d00001e02|ab67616d0000b273|00001e02|00004851/g, "ab67616d0000b273")
        if (url.includes("lh3.googleusercontent.com/"))
            return url.replace(/=w\d+-h\d+[^&]*/, "=w1024-h1024-l90-rj")
        return url
    }

    function getAppWebView(src) {
        if (typeof appPanel.getWebView === "function") return appPanel.getWebView(src)
        return null
    }

    Timer {
        interval: 10000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            var d = new Date()
            root.currentTime = String(d.getHours()).padStart(2,"0") + ":" +
                               String(d.getMinutes()).padStart(2,"0")
        }
    }

    function getMetaScript() {
        return `(()=>{
            const ms=navigator.mediaSession;
            const v=document.querySelector('audio')||document.querySelector('video');
            const t2s=t=>{if(!t)return 0;const p=t.split(':').map(Number);return p.length===2?p[0]*60+p[1]:(p.length===3?p[0]*3600+p[1]*60+p[2]:0);};
            const posEl=document.querySelector('[data-testid="playback-position"]');
            const durEl=document.querySelector('[data-testid="playback-duration"]');
            const pp=document.querySelector('[data-testid="control-button-playpause"]');
            const spTitle=document.querySelector('[data-testid="context-item-link"]');
            const spArtist=document.querySelector('[data-testid="context-item-info-artist"]');
            const spArt=document.querySelector('[data-testid="cover-art-image"]');
            const spCur=posEl?t2s(posEl.innerText):null;
            const spDur=durEl?t2s(durEl.innerText):null;
            const isSpPlaying=pp?(pp.getAttribute('aria-label')==='Pausa'||pp.getAttribute('aria-label')==='Pause'):null;
            const sh=document.querySelector('[data-testid="control-button-shuffle"]');
            const rep=document.querySelector('[data-testid="control-button-repeat"]');
            let title=ms&&ms.metadata?ms.metadata.title:document.title||'';
            let artist=ms&&ms.metadata?ms.metadata.artist:'';
            let artwork=ms&&ms.metadata&&ms.metadata.artwork&&ms.metadata.artwork.length?ms.metadata.artwork[ms.metadata.artwork.length-1].src:'';
            if(window.location.host.includes('spotify')){if(spTitle)title=spTitle.innerText;if(spArtist)artist=spArtist.innerText;if(spArt)artwork=spArt.src;}
            return JSON.stringify({
                title:title,artist:artist,artwork:artwork,
                paused:isSpPlaying!==null?!isSpPlaying:(v?v.paused:true),
                current:spCur!==null?spCur:(v&&!isNaN(v.currentTime)?v.currentTime:0),
                duration:spDur!==null?spDur:(v&&!isNaN(v.duration)?v.duration:0),
                shuffle:sh?sh.getAttribute('aria-checked')==='true':false,
                repeat:rep?(rep.getAttribute('aria-checked')==='mixed'||rep.getAttribute('aria-checked')==='true'):false
            });
        })()`;
    }

    Timer {
        id: metaPollTimer
        interval: 1500; repeat: true
        running: root.audioSrc !== "" && root.audioSrc !== "radio" && root.audioSrc !== "mpris"
        onTriggered: {
            var wv = root.getAppWebView(root.audioSrc)
            if (!wv) return
            wv.runJavaScript(root.getMetaScript(), function(result) {
                if (!result) return
                try {
                    var meta = JSON.parse(result)
                    // Title/artist/cover are NO longer updated
                    // from here: the native path already provides them
                    // (spotifyQmlTrack/Artist/Cover), faster and without
                    // the delay of this polling every 1.5s. Having TWO
                    // mechanisms writing on the same fields
                    // caused the flickering "old song, then right one,
                    // then old, then right" — one of the two arrived
                    // late with data not yet updated and
                    // overwrote the correct one already arrived.
                    // We keep here ONLY the data that the native path
                    // does not provide at all: real seconds of duration/
                    // progress (needed for the seek button) and state
                    // shuffle/repeat.
                    root.isPlaying     = !meta.paused
                    root.progressSec   = meta.current  || 0
                    root.durationSec   = meta.duration || 0
                    root.shuffleOn     = meta.shuffle  || false
                    root.repeatOn      = meta.repeat   || false
                    if (root.durationSec > 0) root.progressPct = (root.progressSec / root.durationSec) * 100
                } catch(e) {}
            })
        }
    }

    // ═══ SYSTEM PLAYER (Mpris, C++ over D-Bus) ═══
    // YT Music (mpv), Spotify (spotifyd) and the phone (mpris-proxy)
    // announce themselves on the bus: the widget shows the player that started
    // last, with state/position/commands taken directly from there.
    // (Before there was a WebSocket toward :9002 that had to guess the
    // sorgente confrontando i titoli: rimosso.)
    readonly property bool mprisOk: typeof Mpris !== "undefined" && Mpris !== null
    // Is the widget showing a system player?
    readonly property bool mprisShown: mprisOk && Mpris.hasActive
        && (root.audioSrc === "mpris" || root.audioSrc === Mpris.activeSource)

    function applyMpris() {
        if (!root.mprisShown) return
        if (Mpris.title !== "") root.widgetTitle = Mpris.title
        else if (root.audioSrc === "bluetooth")
            // The phone via AVRCP (mpris-proxy) does not always send title/artist:
            // it depends on the phone/app, it cannot be controlled from here. Better to show
            // something rather than leave the title empty (or the old one).
            root.widgetTitle = appPanel.hub.btDevice || qsTr("Bluetooth")
        root.widgetArtist = Mpris.artist
        if (Mpris.artUrl !== "")
            root.widgetArtwork = root.getHighResArt(Mpris.artUrl)
        else if (root.audioSrc !== "ytmusic")          // YT: the cover arrives a moment later
            root.widgetArtwork = ""
        root.isPlaying   = Mpris.playing
        root.applyMprisPosition()
    }
    function applyMprisPosition() {
        if (!root.mprisShown) return
        root.durationSec = Mpris.lengthMs / 1000
        root.progressSec = Mpris.positionMs / 1000
        root.progressPct = Mpris.progress * 100
    }
    onMprisShownChanged: applyMpris()

    Connections {
        target: root.mprisOk ? Mpris : null
        function onStateChanged()    { root.applyMpris() }
        function onPositionChanged() { root.applyMprisPosition() }
        // A player started: it becomes the widget's source
        function onSourceStartedPlaying(src) {
            var s = (src === "ytmusic" || src === "spotify" || src === "bluetooth") ? src : "mpris"
            // An external browser that is playing does not take the widget away from the music
            if (src === "browser" && root.lastMusicSrc !== "") { root.applyMpris(); return }
            if (root.audioSrc !== s) {
                root.audioSrc = s
                root._lastExplicitSwitchMs = Date.now()
                root.progressPct = 0; root.progressSec = 0; root.durationSec = 0
            }
            root.applyMpris()
        }
    }

    Connections {
        target: carPanelItem
        function onCar3DLoaded() { root.appReady = true }
        function onDragStarted(globalX) {
            root.isDraggingCar = true
            root.dragCarStartX = globalX
            root.dragCarStartWidth = root.carW
            root.dragCarVel = 0; root.dragCarLastX = globalX; root.dragCarLastT = Date.now()
        }
        function onDragMoved(globalX) {
            if (!root.isDraggingCar) return
            var nowT = Date.now(), dtT = nowT - root.dragCarLastT
            if (dtT > 0) {
                var inst = (globalX - root.dragCarLastX) / dtT
                if (root.rightHandDrive) inst = -inst
                root.dragCarVel = root.dragCarVel * 0.6 + inst * 0.4
            }
            root.dragCarLastX = globalX; root.dragCarLastT = nowT
            var delta = (globalX - root.dragCarStartX) * 1.8      // the panel runs a bit ahead of the finger: less distance to travel
            if (root.rightHandDrive) delta = -delta
            // For the apps with the dedicated fullscreen gesture we allow
            // dragging beyond the normal minimum (35%), almost to zero, to
            // give visual feedback while approaching the threshold that
            // makes the APP go full screen (see onDragEnded). For all
            // the other apps the usual minimum stays: 35%.
            var gestureAppsFloor = ["androidauto", "arcade", "browser"]
            var floor = (gestureAppsFloor.indexOf(root.activeApp) >= 0) ? root.width * 0.06 : root.carMinW
            root.carW = Math.max(floor, Math.min(root.width, root.dragCarStartWidth + delta))
        }
        function onDragEnded() {
            root.isDraggingCar = false
            var ratio = root.carW / root.width
            var vNow = (Date.now() - root.dragCarLastT) < 90 ? root.dragCarVel : 0
            var flick = Math.abs(vNow) > 0.7                        // strisciata veloce (> 700 px/s)

            // Gesture dedicated to the apps that used to have the button at the top
            // left (Theater/Arcade/Browser) plus Android Auto: drag
            // the handle to the left beyond this threshold and the APP goes
            // full screen. Threshold kept wide (0.28, just below the starting 35%)
            // on purpose: a short, natural drag must be enough, there is no
            // need to go almost all the way.
            // Note: we do NOT touch isTogglingFullscreen — that flag only serves
            // to animate the fullscreen when it fires from a BUTTON (no
            // finger to follow); here instead, as for the Smart's fullscreen
            // via drag below, the switch is instantaneous.
            var gestureApps = ["androidauto", "arcade", "browser"]
            if (gestureApps.indexOf(root.activeApp) >= 0 && (ratio < 0.28 || (flick && vNow < 0 && !root.carFullScreen))) {
                root.carW = Qt.binding(function() {
                    return root.carFullScreen ? root.width : root.carMinW
                })
                root.appPanelFull = true
                return
            }

            // ASYMMETRIC thresholds (hysteresis) based on the STARTING state,
            // not a single fixed number: before, with a single threshold (0.38)
            // opening was fine (it starts from 0.35, exceeding 0.38 is enough —
            // short drag), but closing from fullscreen was very long
            // (it starts from 1.0, you had to go below 0.38 — almost the whole
            // width). Now: if starting small, exceeding 0.38 is enough to
            // open; if already starting full screen, going below
            // 0.85 (a short drag the other way) is enough to close.
            var goFullScreen
            var moved = (root.carW - root.dragCarStartWidth) / root.width   // displacement relative to the start
            if (flick) goFullScreen = vNow > 0
            else if (root.carFullScreen) goFullScreen = moved > -0.05   // from full screen: a small step back is enough to close
            else goFullScreen = moved > 0.05                           // from reduced: a small step forward is enough to open
            root.carW = Qt.binding(function() {
                return root.carFullScreen ? root.width : root.carMinW
            })
            root.carFullScreen = goFullScreen
        }
    }

    // Car color chosen in the Settings. We use Connections (not a direct
    // handler "onSettingsCarColor:" on AppPanel{}) on purpose: as long as
    // AppPanel.qml does not yet forward Settings.qml's carColorSelected signal
    // as "settingsCarColor", a direct handler on the
    // component would be a fatal QML load error (non-existent
    // property/signal); Connections instead only produces a
    // harmless warning at runtime if the signal is not there yet.
    Connections {
        target: appPanel
        function onSettingsCarColor(c) {
            uiPrefs.carColor = c
            root.carColor = c
        }
        function onSettingsCarFinish(f) {
            if (carPanelItem && carPanelItem.car3DView) carPanelItem.car3DView.carFinish = f
        }
    }

    Connections {
        target: appPanel
        function onDragHandlePressed(globalY) {
            root.isDraggingApp = true
            root.dragAppStartY = globalY
            root.dragAppVel = 0; root.dragAppLastT = Date.now()
        }
        function onDragHandleMoved(globalY) {
            if (!root.isDraggingApp) return
            var delta = globalY - root.dragAppStartY
            var nowA = Date.now(), dtA = nowA - root.dragAppLastT
            if (dtA > 0) root.dragAppVel = root.dragAppVel * 0.6 + (delta / dtA) * 0.4
            root.dragAppLastT = nowA
            var newY = Math.max(root.appRestY, Math.min(root.height, appPanel.y + delta))
            appPanel.y = newY
            root.dragAppStartY = globalY
        }
        function onDragHandleReleased() {
            // A short, natural drag must be enough to close: past ~10% of the screen height
            // (or a light flick down) closes; a flick up keeps it open.
            var vA = (Date.now() - root.dragAppLastT) < 150 ? root.dragAppVel : 0
            var shouldClose = appPanel.y > root.height * 0.10 ? (vA > -0.5) : (vA > 0.3)
            dragReleaseAnim.stop()
            dragReleaseAnim._shouldClose = shouldClose
            dragReleaseAnim.from = appPanel.y
            dragReleaseAnim.to = shouldClose ? root.height + 10 : root.appRestY
            dragReleaseAnim.duration = 550
            dragReleaseAnim.easing.type = Easing.OutExpo
            dragReleaseAnim.start()
        }
    }

    NumberAnimation {
        id: dragReleaseAnim
        target: appPanel
        property: "y"
        property bool _shouldClose: false
        onStopped: {
            if (_shouldClose) {
                root.activeApp = ""
                root.appPanelFull = false
            }
            root.isDraggingApp = false

            appPanel.y = Qt.binding(function() {
                return (root.activeApp === "" ? (root.height + 10)
                     : (root.appPanelFull ? 0 : 38 * root.uPx)) + root.fsSlideOffset   // app panel: top edge at 38 wireframe px
            })
        }
    }

    Timer {
        interval: 4000; running: true; repeat: false
        onTriggered: root.appReady = true
    }

    Timer {
        interval: 3500; running: true; repeat: false
        onTriggered: if (typeof appPanel.preloadSpotify === "function") appPanel.preloadSpotify()
    }

    // dl58: rest position of the app panel (dragging never takes it higher than this)
    readonly property real appRestY: (root.appPanelFull ? 0 : 38 * root.uPx) + root.fsSlideOffset
    property bool online: true
    property bool _netChecked: false

    property bool _reloadIfOnline: false
    function checkConnectivity(reloadIfOnline) {
        if (reloadIfOnline) root._reloadIfOnline = true
        sysHelper.checkNetworkAsync()      // does not block the UI (before: synchronous nmcli every 8 s)
    }
    Connections {
        target: sysHelper
        function onNetworkChecked(ok) {
            root._netChecked = true
            var wasOffline = !root.online
            root.online = ok
            var rl = root._reloadIfOnline
            root._reloadIfOnline = false
            if (ok && (rl || wasOffline)) root.reloadEverything()
        }
    }

    function reloadEverything() {
        console.log("[Net] Connection back — reloading everything")
        if (typeof miniMapView !== "undefined" && miniMapView.reload) miniMapView.reload()
        if (typeof appPanel.reloadAll === "function") appPanel.reloadAll()
        if (typeof appPanel.reloadSpotify === "function") appPanel.reloadSpotify()
    }

    Timer {
        interval: 8000; running: true; repeat: true
        onTriggered: root.checkConnectivity(false)
    }
    Component.onCompleted: {
        Theme.light = lightTheme; Qt.styleHints.colorScheme = lightTheme ? Qt.Light : Qt.Dark; root.checkConnectivity(false)
        // Starts from the real system volume (the same as Settings › Audio)
        var v = sysHelper.getVolume()
        if (v >= 0 && v <= 150) root.volume = Math.min(100, v)
        resumeStartTimer.restart()
    }

    property int  callSeconds: 0
    Timer {
        id: callTimer
        interval: 1000; repeat: true
        running: PhoneManager.callState === "active"
        onTriggered: root.callSeconds += 1
    }
    function _fmtDuration(s) {
        return String(Math.floor(s / 60)).padStart(2, "0") + ":"
             + String(s % 60).padStart(2, "0")
    }

    // CarPlay / Android Auto in use: calls and messages arrive there, not here
    readonly property bool carlinkLive: Carlink.state === "running" && Carlink.videoActive
    // Game running (native or web): the music stays still
    readonly property bool gameRunning: !!appPanel.arcadeItem
        && (appPanel.arcadeItem.nativeGameRunning || (root.activeApp === "arcade" && appPanel.arcadeItem.currentUrl !== ""))
    onGameRunningChanged: {
        if (gameRunning) { root.resumeGuardOff = false; root.pauseAllAudio(); root._resumeList = [] }
    }
    // Calls (and only those) also appear above full-screen apps
    function _callNotify(n) { notifStack.notify(n); callStack.notify(n) }
    function _callDismiss() { notifStack.dismiss("call"); callStack.dismiss("call") }

    Connections {
        target: PhoneManager
        function onCallStateChanged() {
            var st = PhoneManager.callState
            if (root.carlinkLive && st !== "idle") {
                root._callDismiss()
                if (root._callAudioPaused) { root._callAudioPaused = false; root.resumeAfterPause() }
                return
            }
            if (st === "incoming" || st === "dialing" || st === "active") {
                // music stopped RIGHT AWAY for the whole call (at the end what was playing restarts)
                if (!root._callAudioPaused) { root._callAudioPaused = true; root.resumeGuardOff = false; root.pauseAllAudio() }
            } else if (root._callAudioPaused) {
                root._callAudioPaused = false
                root.resumeAfterPause()
            }
            var contact = PhoneManager.callContact || PhoneManager.callNumber
            if (st === "incoming") {
                root.callSeconds = 0
                root._callNotify({
                    id: "call",
                    iconType: "phone",
                    iconColor: "#34C759",
                    title: contact || qsTr("Incoming call"),
                    subtitle: contact !== PhoneManager.callNumber
                              ? PhoneManager.callNumber : qsTr("Calling…"),
                    actionLabel:    qsTr("Answer"),
                    actionColor:    "#34C759",
                    secondaryLabel: qsTr("Decline"),
                    secondaryColor: "#ED4E3B",
                    dismissible: false,
                    onAction:    function() { PhoneManager.answer() },
                    onSecondary: function() { PhoneManager.hangup() }
                })
            } else if (st === "dialing") {
                root.callSeconds = 0
                root._callNotify({
                    id: "call",
                    iconType: "phone",
                    iconColor: "#3D6FE7",
                    title: contact || qsTr("Outgoing call"),
                    subtitle: qsTr("Calling…"),
                    actionLabel: qsTr("End"),
                    actionColor: "#ED4E3B",
                    dismissible: false,
                    onAction: function() { PhoneManager.hangup() }
                })
            } else if (st === "active") {
                root._callNotify({
                    id: "call",
                    iconType: "phone",
                    iconColor: "#34C759",
                    title: contact || qsTr("On a call"),
                    subtitle: root._fmtDuration(root.callSeconds),
                    actionLabel: qsTr("End"),
                    actionColor: "#ED4E3B",
                    dismissible: false,
                    onAction: function() { PhoneManager.hangup() }
                })
            } else {
                root._callDismiss()
                root.callSeconds = 0
            }
        }
    }

    // ── Notifica messaggio in arrivo ────────────────────────────────────
    // PhoneManager.conversations updates every ~8s (see phone_service.py)
    // and also right after one of our own sends — so we cannot notify
    // at every conversationsChanged (continuous false alarm, and we would notify
    // our OWN sent messages too). We compare the message count
    // of each conversation with the previous one: if it increased AND the last
    // message is "them" (not ours), it is a really new incoming message.
    property var _lastMsgCounts: ({})
    // First-start bug: _lastMsgCounts started empty, so at the first
    // load (the whole existing history) EVERY message exceeded
    // the previous count (zero) and fired a notification — a
    // "storm" of notifications for messages read long ago. With this
    // flag, the first round only records the starting counts without
    // notifying anything; real notifications start from the second round on.
    property bool _msgCountsInitialized: false

    property double _msgConnectedAt: Date.now()
    // "20241107T153000" (MAP) -> ms; NaN if not interpretable
    function _mapTsMs(ts) {
        var m = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/.exec(ts || "")
        return m ? new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime() : NaN
    }
    property double _msgSettleUntil: Date.now() + 30000   // on connection the message list reloads from scratch: it is not new stuff
    function _notifyMsg(c, lastMsg) {
        notifStack.notify({
            id: "msg-" + c.number,
            iconType: "message",
            iconColor: "#3D6FE7",
            title: c.name || c.number,
            subtitle: lastMsg.text || qsTr("New message"),
            actionLabel: qsTr("Open"),
            actionColor: "#3D6FE7",
            dismissible: true,
            autoDismissMs: 6000,
            onAction: function() {
                root.activeApp = "messages"
                appPanel.selectConversation(c.number)
            }
        })
    }
    Connections {
        target: PhoneManager
        function onConnectedChanged() {
            root._msgSettleUntil = Date.now() + 30000
            root._msgConnectedAt = Date.now()
            root._lastMsgCounts = ({})
            root._msgCountsInitialized = false
        }
        function onConversationsChanged() {
            var convos = PhoneManager.conversations || []
            var newCounts = {}
            var now = Date.now()
            var settling = now < root._msgSettleUntil
            if (settling) root._msgSettleUntil = Math.max(root._msgSettleUntil, now + 8000)   // while blocks keep arriving, we just record
            var isFirstLoad = !root._msgCountsInitialized || settling
            var fresh = []
            for (var i = 0; i < convos.length; i++) {
                var c = convos[i]
                var count = (c.messages || []).length
                newCounts[c.number] = count
                if (isFirstLoad) continue
                var prevCount = root._lastMsgCounts[c.number] || 0
                // more than 3 messages at once = synchronization, not a new message
                if (count > prevCount && count > 0 && (count - prevCount) <= 3) {
                    var lastMsg = c.messages[count - 1]
                    // old (received before the connection, arrived only with the synchronization): not a notification
                    var tsMs = root._mapTsMs(lastMsg.ts)
                    var isOld = !isNaN(tsMs) && tsMs < root._msgConnectedAt - 120000
                    if (lastMsg.from === "them" && !isOld && !root.carlinkLive) fresh.push({ c: c, m: lastMsg })
                }
            }
            if (fresh.length <= 2) {
                for (var j = 0; j < fresh.length; j++) root._notifyMsg(fresh[j].c, fresh[j].m)
            }
            root._lastMsgCounts = newCounts
            root._msgCountsInitialized = true
        }
    }

    onCallSecondsChanged: {
        if (PhoneManager.callState === "active") {
            root._callNotify({
                id: "call",
                iconType: "phone",
                iconColor: "#34C759",
                title: PhoneManager.callContact || PhoneManager.callNumber || qsTr("On a call"),
                subtitle: root._fmtDuration(root.callSeconds),
                actionLabel: qsTr("End"),
                actionColor: "#ED4E3B",
                dismissible: false,
                onAction: function() { PhoneManager.hangup() }
            })
        }
    }

    onOnlineChanged: {
        if (!root._netChecked) return
        // Before, when coming back online it showed a generic notification (same
        // card as calls/messages) — removed because inconsistent: the error
        // has its own dedicated banner, while "back online" no
        // longer needs an announcement (the banner disappears by itself).
    }

    Connections {
        target: appPanel
        function onRadioIsPlayingChanged() {
            if (appPanel.radioIsPlaying) {
                root.pauseAllExcept("radio")
                root.audioSrc = "radio"
            }
        }
        function onSpotifyQmlTrackChanged() {
            // Before, this handler ALSO set audioSrc/pauseAllExcept
            // on its own (with a guard based on activeApp different
            // from the one used by audioSourceActivated) — two
            // parallel mechanisms that overlapped caused the flicker
            // "shows a song, then the previous one, then settles".
            // Now this handler only UPDATES the metadata
            // when the source is already the right one; the source
            // CHANGE is decided only by audioSourceActivated.
            if (!root.mprisShown && (root.audioSrc === "spotify" || root.audioSrc === "ytmusic") && appPanel.spotifyQmlTrack !== "") {
                root.widgetTitle   = appPanel.spotifyQmlTrack
                root.widgetArtist  = appPanel.spotifyQmlArtist
                root.widgetArtwork = appPanel.spotifyQmlCover
                root.isPlaying     = appPanel.spotifyQmlPlaying
            }
        }
        function onSpotifyQmlProgressPctChanged() {
            if (!root.mprisShown && (root.audioSrc === "spotify" || root.audioSrc === "ytmusic")) {
                root.progressPct = appPanel.spotifyQmlProgressPct * 100
                // Real duration from the provider: without it, the knob of the bar in the
                // mini player stayed hidden and the bar could not be dragged
                var d = appPanel.hub ? appPanel.hub.dashFor(root.audioSrc) : null
                if (d && d.durationMs > 1) {
                    root.durationSec = d.durationMs / 1000
                    root.progressSec = d.progressMs / 1000
                }
            }
        }
        function onSpotifyQmlCoverChanged() {
            if (!root.mprisShown && (root.audioSrc === "spotify" || root.audioSrc === "ytmusic") && appPanel.spotifyQmlCover !== "") {
                root.widgetArtwork = appPanel.spotifyQmlCover
            }
        }
        function onSpotifyQmlArtistChanged() {
            if (!root.mprisShown && (root.audioSrc === "spotify" || root.audioSrc === "ytmusic") && appPanel.spotifyQmlArtist !== "") {
                root.widgetArtist = appPanel.spotifyQmlArtist
            }
        }
        function onSpotifyQmlPlayingChanged() {
            if (!root.mprisShown && (root.audioSrc === "spotify" || root.audioSrc === "ytmusic")) {
                root.isPlaying = appPanel.spotifyQmlPlaying
            }
            // The source change is now decided only by audioSourceActivated
            // (see the note above in onSpotifyQmlTrackChanged) — the same
            // redundant logic that was here has been removed.
        }
    }

    // ── Music from the phone over Bluetooth: metadata in the music widget ──
    function applyBluetoothMeta() {
        if (root.mprisShown) return        // the phone already arrives from the system player
        var h = appPanel.hub
        root.widgetTitle   = h.btTitle !== "" ? h.btTitle : (h.btDevice || qsTr("Bluetooth"))
        root.widgetArtist  = h.btArtist
        root.widgetArtwork = ""
        root.isPlaying     = h.btPlaying
        root.durationSec   = h.btDurationMs > 1 ? h.btDurationMs / 1000 : 0
        root.progressSec   = h.btProgressMs / 1000
        root.progressPct   = h.btDurationMs > 1 ? (h.btProgressMs / h.btDurationMs) * 100 : 0
    }
    Connections {
        target: appPanel.hub
        function onBtTitleChanged()      { if (root.audioSrc === "bluetooth") root.applyBluetoothMeta() }
        function onBtArtistChanged()     { if (root.audioSrc === "bluetooth") root.applyBluetoothMeta() }
        function onBtPlayingChanged()    { if (root.audioSrc === "bluetooth") root.applyBluetoothMeta() }
        function onBtProgressMsChanged() { if (root.audioSrc === "bluetooth") root.applyBluetoothMeta() }
    }

    // ══════════ RIPRENDI RIPRODUZIONE ALL'AVVIO (Impostazioni › Audio) ══════════
    // Periodically saves the track/station in progress; at the next start, if
    // the switch is on, it puts them back on air. Radio is a live stream
    // (no "exact point"): only the last station is resumed. The
    // phone over Bluetooth is NOT manageable from here: the phone decides
    // what plays, we cannot "restart" a track on ITS player.
    Core.Settings {
        id: playbackState
        category: "playback"
        property string lastProvider:    ""     // "ytmusic" | "spotify" | "radio"
        property string lastTrackId:     ""     // videoId (YT Music) / id (Spotify)
        property string lastTitle:       ""
        property string lastArtist:      ""
        property string lastCover:       ""
        property bool   lastIsVideo:     false
        property real   lastPositionMs:  0
        property string lastStationJson: ""     // oggetto stazione radio completo
    }

    function savePlaybackState() {
        if (root.audioSrc === "ytmusic" || root.audioSrc === "spotify") {
            var d = appPanel.hub ? appPanel.hub.dashFor(root.audioSrc) : null
            if (!d || !d.currentTrackId) return
            playbackState.lastProvider   = root.audioSrc
            playbackState.lastTrackId    = d.currentTrackId
            playbackState.lastTitle      = d.currentTrack
            playbackState.lastArtist     = d.currentArtist
            playbackState.lastCover      = d.currentCover
            playbackState.lastIsVideo    = d.currentIsVideo || false
            playbackState.lastPositionMs = d.progressMs || 0
        } else if (root.audioSrc === "radio") {
            var st = appPanel.radioStationData
            if (!st) return
            playbackState.lastProvider    = "radio"
            playbackState.lastStationJson = JSON.stringify(st)
        }
    }
    // Every 4s while something we know how to resume is playing: not at every
    // instant, so "the exact point where it stopped" is accurate to within
    // a few seconds (the final save on clean shutdown, below,
    // reduces the margin in the normal case of shutting down from the UI).
    Timer { interval: 4000; running: true; repeat: true; onTriggered: root.savePlaybackState() }
    Connections {
        target: Qt.application
        function onAboutToQuit() { root.savePlaybackState() }
    }

    property int _resumeTries: 0
    function tryResumePlayback() {
        if (!uiPrefs.resumePlayback) return
        if (root.audioSrc !== "") return   // something else has already started in the meantime
        var p = playbackState.lastProvider
        if (p === "ytmusic" || p === "spotify") {
            if (!playbackState.lastTrackId) return
            if (!appPanel.hub || !appPanel.hub.dashFor(p)) { root._resumeRetry(); return }
            var media = {
                videoId:  playbackState.lastTrackId,   // used by YT Music
                id:       playbackState.lastTrackId,   // used by Spotify
                title:    playbackState.lastTitle,
                subtitle: playbackState.lastArtist,
                cover:    playbackState.lastCover,
                isVideo:  playbackState.lastIsVideo,
                startMs:  playbackState.lastPositionMs   // the service starts the track from here already
            }
            appPanel.hub.play(p, media)
            resumeSeekTimer.targetProvider = p
            resumeSeekTimer.targetId       = playbackState.lastTrackId
            resumeSeekTimer.targetMs       = playbackState.lastPositionMs
            resumeSeekTimer.tries = 0
            resumeSeekTimer.restart()
        } else if (p === "radio") {
            if (!playbackState.lastStationJson) return
            try {
                var station = JSON.parse(playbackState.lastStationJson)
                if (station && station.url_resolved) appPanel.radioResumeStation(station)
            } catch (e) {}
        }
    }
    function _resumeRetry() {
        // A single retry: the YT Music/Spotify services sometimes
        // take a few seconds longer to start at UI boot.
        if (root._resumeTries >= 1) return
        root._resumeTries += 1
        resumeStartTimer.interval = 5000
        resumeStartTimer.restart()
    }
    Timer { id: resumeStartTimer; interval: 4000; repeat: false; onTriggered: root.tryResumePlayback() }
    // The track restarts from zero (playMedia does not accept a position): we
    // wait for the service to confirm the right track AND its real duration,
    // then jump to the saved point with a single seekPct (as a 0..1 fraction,
    // the only unit the YT Music/Spotify services accept for seeking).
    Timer {
        id: resumeSeekTimer
        interval: 300; repeat: true
        property string targetProvider: ""
        property string targetId: ""
        property real   targetMs: 0
        property int    tries: 0
        onTriggered: {
            resumeSeekTimer.tries += 1
            var d = appPanel.hub ? appPanel.hub.dashFor(resumeSeekTimer.targetProvider) : null
            if (d && d.currentTrackId === resumeSeekTimer.targetId && d.durationMs > 1000) {
                // Updated service: the track has already started from the right point, no jump.
                // Old service (starts from zero): we jump as before.
                if (resumeSeekTimer.targetMs > 3000 && (d.progressMs || 0) < resumeSeekTimer.targetMs - 5000)
                    d.seekPct(Math.min(0.97, resumeSeekTimer.targetMs / d.durationMs))
                resumeSeekTimer.stop()
            } else if (resumeSeekTimer.tries >= 20) {
                resumeSeekTimer.stop()
                // In 6s the service (port 8099/8098) never confirmed the
                // track: most likely it had not started yet when
                // abbiamo chiamato playMedia() (scraperGet fallisce in
                // silence if the service does not answer yet, without any
                // error to intercept) — retry from the beginning just once.
                root._resumeRetry()
            }
        }
    }

    function applyCarColor(c) {
        uiPrefs.carColor = c
        root.carColor = c
    }

    function switchToSource(src) {
        if (audioSrc === src) return
        // A Theater/Arcade video does not take the widget: before it showed the Theater icon with the
        // song's title, and with the video closed the play button did not restart the music.
        // The music stops by itself (AudioFocus) and stays in the widget: the play button restarts it.
        if ((src === "theater" || src === "arcade" || src === "browser") && root.lastMusicSrc !== "") return
        audioSrc = src
    }

    // Paused by us on player switch: its "is playing" state
    // is no longer true (its update would only arrive after a few seconds)
    function _markPaused(p) {
        var d = appPanel.hub ? appPanel.hub.dashFor(p) : null
        if (!d) return
        d._lastToggleMs = Date.now()
        d.isPlaying = false
        appPanel.markPausedByUs(p)
    }
    function pauseSource(s) {
        if (s === "theater" || s === "arcade" || s === "browser" || s === "chrome") {
            var wv = root.getAppWebView(s === "chrome" ? "browser" : s)
            if (wv) wv.runJavaScript("document.querySelectorAll('audio,video').forEach(function(e){try{e.pause()}catch(x){}});")
        } else if ((s === "spotify" || s === "spotify-native" || s === "ytmusic" || s === "bluetooth")
                   && root.mprisOk && Mpris.hasSource(s === "spotify-native" ? "spotify" : s)) {
            Mpris.pauseSource(s === "spotify-native" ? "spotify" : s)
            if (s !== "bluetooth") root._markPaused(s === "spotify-native" ? "spotify" : s)
        } else if (s === "mpris" && root.mprisOk) {
            Mpris.pauseAllExcept("")
        } else if (s === "spotify" || s === "spotify-native") {
            // Port 8098 = real Spotify. Before, port 8099 (YtMusic's)
            // was here by mistake — probably a legacy of the
            // old naming confusion between "spotify"/"spotifyapp".
            var x = new XMLHttpRequest()
            x.open("GET", "http://127.0.0.1:8098/player/pause")
            x.send()
            root._markPaused("spotify")
        } else if (s === "ytmusic") {
            // Case NOTHING AT ALL BEFORE: pause YtMusic
            // it literally did nothing, the audio kept
            // playing in the background while the display switched to the
            // new source — hence "you hear the old song with
            // the new metadata". NOTE: here "?state=1" is MANDATORY,
            // because unlike Spotify, YtMusic's endpoint
            // TOGGLES play/pause if you do not specify the state — without
            // this parameter you risk doing the opposite (restarting
            // instead of pausing).
            var y = new XMLHttpRequest()
            y.open("GET", "http://127.0.0.1:8099/player/pause?state=1")
            y.send()
            root._markPaused("ytmusic")
        } else if (s === "radio") {
            if (typeof appPanel.radioStop === "function") appPanel.radioStop()
        } else if (s === "bluetooth") {
            // Music from the phone over Bluetooth (AVRCP)
            appPanel.hub.btCommand("pause")
        }
    }

    // Pauses EVERYTHING that can play (shown source, audio focus
    // owner, players that report playing) + "blind" pause
    // to the two music services (safe: YT uses state=1, Spotify just pauses).
    function pauseAllAudio() {
        var hb = appPanel.hub
        var cand = [root.audioSrc, audioFocus.owner]
        if (hb && hb.yt && hb.yt.isPlaying) cand.push("ytmusic")
        if (hb && hb.sp && hb.sp.isPlaying) cand.push("spotify")
        var seen = {}, was = []
        for (var i = 0; i < cand.length; i++) {
            var s = cand[i]
            if (!s || seen[s]) continue
            seen[s] = true
            var playing = false
            if (s === "ytmusic")        playing = !!(hb && hb.yt && hb.yt.isPlaying)
            else if (s === "spotify")   playing = !!(hb && hb.sp && hb.sp.isPlaying)
            else if (s === "radio")     playing = !!appPanel.radioIsPlaying
            else if (s === "bluetooth") playing = !!(hb && hb.btPlaying)
            else                        playing = (s === root.audioSrc) && root.isPlaying
            if (playing) was.push(s)
            try { root.pauseSource(s) } catch (e) { console.log("[AI] pausa", s, e) }
        }
        // if there was already something to restore (assistant reopened right away), do not lose it
        root._resumeList = was.length > 0 ? was : root._resumeList
        // "blind" pause to the two music services (safe: YT uses state=1, Spotify just pauses)
        if (!seen["ytmusic"]) { var y = new XMLHttpRequest(); y.open("GET", "http://127.0.0.1:8099/player/pause?state=1"); y.send() }
        if (!seen["spotify"]) { var x = new XMLHttpRequest(); x.open("GET", "http://127.0.0.1:8098/player/pause"); x.send() }
        // everything is paused: the widget's icon must show "play" (before it stayed on "pause")
        root.isPlaying = false
    }

    // End of the pause (call, scene, game): resumes what was playing, unless in the meantime
    // something else started
    function resumeAfterPause() {
        var list = root._resumeList
        root._resumeList = []
        if (!list || list.length === 0) return
        var hb = appPanel.hub
        if ((hb && hb.yt && hb.yt.isPlaying) || (hb && hb.sp && hb.sp.isPlaying) || appPanel.radioIsPlaying) return
        for (var i = 0; i < list.length; i++) {
            var s = list[i]
            try {
                if (s === "ytmusic" || s === "spotify") appPanel.musicToggle(s)
                else if (s === "radio") appPanel.radioTogglePlay()
                else if (s === "bluetooth") hb.btCommand("play")
                else if (s === "mpris" && root.mprisOk) Mpris.playPause()
                else if (s === "theater" || s === "arcade" || s === "browser" || s === "chrome") {
                    var wv = root.getAppWebView(s === "chrome" ? "browser" : s)
                    if (wv) wv.runJavaScript("var m=document.querySelector('video,audio'); if(m && m.paused) m.play();")
                }
            } catch (e) { console.log("[AI] ripresa", s, e) }
        }
    }

    function pauseAllExcept(newSrc) {
        // BEFORE this function only changed the variable
        // audioSrc, without ever sending a real pause command to the
        // sorgente precedente — l'audio vecchio continuava a suonare
        // while the widget already showed the new song. Now we
        // REALLY pause everything that is not the new source.
        var oldSrc = root.audioSrc
        if (oldSrc !== "" && oldSrc !== newSrc) {
            root.pauseSource(oldSrc)
        }
        root.audioSrc = newSrc
    }

    // ═══ PODCAST in the miniplayer ═══
    // The podcast service announces itself on the bus as the "Podcast" player: the widget shows
    // the same data as the other players but with podcast buttons.
    readonly property bool podcastMode: root.mprisShown && Mpris.activeIdentity === "Podcast"
    // Music (PC files / sticks): system player "Music", the widget shows the local music icon
    readonly property bool localMusicMode: root.mprisShown && Mpris.activeIdentity === "Musica"
    property real podcastSpeed: 1.0
    readonly property string podcastSpeedText: (Math.round(root.podcastSpeed * 100) / 100).toString().replace(".", ",") + "×"
    function podcastGet(path) {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE || x.status !== 200) return
            try { var j = JSON.parse(x.responseText); if (j && j.speed) root.podcastSpeed = j.speed } catch (e) {}
        }
        x.open("GET", "http://127.0.0.1:8094" + path)
        x.send()
    }
    function podcastSkip(secs) {
        if (!root.mprisOk) return
        var ms = Mpris.positionMs + secs * 1000
        if (Mpris.lengthMs > 0) ms = Math.min(ms, Mpris.lengthMs - 1000)
        Mpris.seekTo(Math.max(0, ms))
    }
    onPodcastModeChanged: if (root.podcastMode) root.podcastGet("/player/state")
    Timer { interval: 4000; repeat: true; running: root.podcastMode; onTriggered: root.podcastGet("/player/state") }

    function handlePlayPause() {
        // The widget shows a video (Theater/browser/Arcade) but the app is no longer open, or an
        // external player has disappeared: the button must restart the SONG, not touch the video.
        if ((root.audioSrcIsWeb && root.activeApp !== root.audioSrc)
            || (root.audioSrc === "mpris" && root.mprisOk && !Mpris.hasActive)) {
            if (root.restoreMusic()) {
                if (root.audioSrc === "bluetooth") appPanel.hub.btCommand("play")
                else appPanel.musicToggle(root.audioSrc)
                return
            }
        }
        if (root.audioSrc === "mpris" && root.mprisOk) { Mpris.playPause(); return }
        // The button acts on the track SHOWN in the widget (audioSrc). Before it used
        // "whoever has audio focus", which could be another source (e.g. the
        // phone over Bluetooth): the pause went to that one and the shown track
        // continuava/ripartiva.
        if (root.audioSrc === "spotify" || root.audioSrc === "ytmusic" || root.audioSrc === "bluetooth") {
            appPanel.musicToggle(root.audioSrc); return
        }
        var o = audioFocus.owner
        if (o === "radio")                       { appPanel.radioTogglePlay(); return }
        if (o === "spotify" || o === "ytmusic" || o === "bluetooth") { appPanel.musicToggle(o); return }
        if (o === "theater" || o === "browser") {
            var wv = root.getAppWebView(o)
            if (wv) wv.runJavaScript("var m=document.querySelector('video,audio'); if(m){ m.paused ? m.play() : m.pause(); }")
            return
        }
        if (audioSrc === "radio")   { appPanel.radioTogglePlay(); return }
        if (audioSrc === "spotify") { appPanel.spotifyToggle();   return }
    }

    function handleSeek(pct) {
        if (root.audioSrc === "mpris" && root.mprisOk) { Mpris.seekToFraction(pct); return }
        var o = (root.audioSrc === "spotify" || root.audioSrc === "ytmusic") ? root.audioSrc : audioFocus.owner
        if (o === "spotify" || o === "ytmusic") { appPanel.musicSeekPct(o, pct); return }
        if (o === "theater" || o === "browser") {
            if (durationSec > 0) {
                var t = pct * durationSec
                var wv = root.getAppWebView(o)
                if (wv) wv.runJavaScript("var m=document.querySelector('video,audio'); if(m) m.currentTime=" + t + ";")
                progressSec = t
            }
            return
        }
        if (audioSrc === "spotify") { appPanel.spotifySeekPct(pct); return }
    }

    Item {
        id: mapLayer
        z: 0
        y: 0

        // Disabled while dragging an icon from the drawer: see
        // note on root.dockDragActive above.
        enabled: !root.dockDragActive

        // "Full-screen map" mode: the map ALWAYS stays full
        // screen as soon as the mode is active (uiPrefs.fullScreenMap),
        // regardless of whether an app is open or not — it is no
        // longer ever narrowed. When an app is open, it simply stays
        // covered on the right by the app panel (appPanel has higher z: 800/1001
        // versus mapLayer's z:0), exactly like a curtain that covers
        // the map without it having to resize underneath — it is precisely
        // this continuous resizing (opening/closing apps) that before
        // caused the perceived delay in going back to full screen. The car
        // stays visible anyway in the free strip on the left thanks to the
        // "camera-only" shift (see mapLibreView.followOffsetPx
        // below), not of the map box itself.
        // Outside this mode: original behavior, unchanged.
        readonly property bool _fullMapHome: uiPrefs.fullScreenMap
        width: _fullMapHome ? root.width : (root.width - root.carMinW)
        height: root.height

        x: _fullMapHome ? 0
                        : (root.rightHandDrive ? -(root.width - root.carMinW) + (root.width - root.carW) : root.carW)
        // "enabled: !root.isDraggingCar" — exactly the same trick already
        // used for "Behavior on carW" above: without it, dragging by hand
        // the edge between car and map this Behavior "chases" with 420ms of
        // delay every micro-movement of the mouse instead of following it 1:1,
        // making the drag visibly sticky/laggy.
        // Delay of the map in "reaching" the car panel: x depends on
        // root.carW, which ALREADY has its own animation (Behavior on carW, 400ms).
        // With a second Behavior here (420ms) on top of that, the map
        // chased the car's edge with an animation inside
        // an animation: if the panel shrank quickly it stayed
        // visibly behind and "came off". Now, while carW is already
        // animating, the map follows it 1:1 (it stays attached like a magnet).
        // The Behavior stays active for the other changes (full-screen map
        // mode on/off, right-hand drive), which do not go through carW.
        Behavior on x     { enabled: !root.isDraggingCar && !carWAnim.running; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: !root.isDraggingCar && !carWAnim.running; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

        opacity: 1.0
        visible: true

        MapLibreView {
            id: mapLibreView
            anchors.fill: parent
            dockClearance: root.dockVisualH + 10 * root.uPx   // navigation panel 10 px from the dock
            active:  mapLayer.visible
            miniActive: miniMapView.active      // fake GPS: it continues even if only the mini one is visible
            lightTheme: root.lightTheme
            // Map locked (no pan/zoom/long press) when an app is open,
            // to avoid accidental drags while using the app.
            // activeApp goes back to "" when the app panel is closed.
            mapLocked: root.activeApp !== ""
            // In "full-screen map" mode, when the map is the big
            // full-screen one, the 5 buttons + compass/recenter
            // move to the side of the music widget (see mapToolsBar) — here
            // they must therefore be hidden so as not to be duplicated.
            externalControls: mapLayer._fullMapHome
            navSlotPos: widgetsContainer.slotShared ? root.slotEff : 0
            navSlotH: musicWidget.baseH
            covered: root.carCovered
            // "Move only the camera" (the user's idea): the map always stays
            // full screen (see mapLayer above) even with an app
            // open — here only the "optical" center of the map is shifted
            // to the right by half of the band covered by the app, so the car
            // (which would otherwise end up at the real screen center, under
            // the app) appears instead in the middle of the free strip on the left
            // (root.carW), as wide as the car panel would normally
            // occupy. 0 = no shift (map not covered).
            followOffsetPx: (uiPrefs.fullScreenMap && root.activeApp !== "" && !root.appPanelFull)
                             ? -(root.width - root.carW) / 2 : 0
            marsMode: uiPrefs.marsMode
            mapStyle: uiPrefs.mapStyle
            satNight: root.satNightActive
            onMapStyleChanged: uiPrefs.mapStyle = mapStyle
            onHomeRequested: {
                if (uiPrefs.homeLat !== 0 || uiPrefs.homeLon !== 0)
                    navigateTo(uiPrefs.homeLat, uiPrefs.homeLon, qsTr("Home", "shortcut"))
                else focusSearch()
            }
            onWorkRequested: {
                if (uiPrefs.workLat !== 0 || uiPrefs.workLon !== 0)
                    navigateTo(uiPrefs.workLat, uiPrefs.workLon, qsTr("Work"))
                else focusSearch()
            }
        }

    }

    CarPanel {
        id: carPanelItem
        z: 100; y: 0; height: parent.height
        rhd: root.rightHandDrive

        // "Full-screen map" mode (Settings › Navigation,
        // large-EV style): the car panel is never seen — it slides
        // off the screen from the side where it already is (left in left-hand drive, right
        // in right-hand drive) instead of just narrowing. In its place,
        // in both cases (no app open or an app open), it is
        // always the SAME map (mapLayer) occupying that space —
        // niente sfocatura/seconda istanza separata.
        readonly property real offscreenX: root.rightHandDrive ? root.width : -width
        x: uiPrefs.fullScreenMap ? offscreenX
                                 : (root.rightHandDrive ? root.width - width : 0)
        // Same trick as "Behavior on carW" below: disabled
        // during the manual dragging of the car/map edge, otherwise
        // that drag would become sticky (it chases the mouse with
        // 420ms of delay instead of following it 1:1).
        // In right-hand drive x depends on the width (which already animates with carW): a second animation on x
        // made the panel chase its own edge (jerks/bounces). It stays active only for the fullScreenMap exit.
        Behavior on x { enabled: !root.isDraggingCar && !carWAnim.running; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        width: root.carW
        fullWidth: root.width
        reducedW: root.carMinW

        // Not just off screen: once the exit animation
        // REALLY ends outside (x has reached offscreenX), the
        // panel switches off completely ("visible: false") so the car's 3D
        // engine stops rendering — no point wasting
        // GPU/CPU on a scene that is no longer seen anyway. As soon as the
        // mode is deactivated it becomes visible RIGHT AWAY (even before it
        // starts coming back in), otherwise it would not be seen coming back in.
        // Paused (not drawn) when a full-screen app covers it completely
        visible: (!uiPrefs.fullScreenMap || Math.abs(x - offscreenX) > 1) && !root.carCovered

        lightTheme: root.lightTheme
        activeApp: root.activeApp
        lowPower: uiPrefs.lowPower
    }

    Item {
        id: miniMapBox
        z: 150
        // Disabled while dragging an icon from the drawer.
        enabled: !root.dockDragActive
        width: Math.min(parent.width * 0.21, 380)
        height: parent.height * 0.36
        y: 0

        x: root.rightHandDrive ? carPanelItem.x : carPanelItem.width - width

        // Before it disappeared with ANY active app (activeApp === "") — now
        // it stays visible unless the big Maps app itself is
        // active (in that case yes, seeing two is redundant). Also,
        // never in "full-screen map" mode: there the car panel (of
        // which this is only a preview) no longer exists at all.
        opacity: (root.carFullScreen && !root.appPanelFull && root.activeApp !== "maps"
                  && !uiPrefs.fullScreenMap && !carPanelItem.car3DView.uiHidden) ? 1 : 0
        visible: opacity > 0.01

        // Before it faded in 550ms, slower than the 350ms with which the car
        // panel shrinks — it stayed visible ~200ms "straddling" above an
        // already shrunk panel. Now it disappears faster than
        // the panel takes to shrink, not after.
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        MapLibreMini {
            id: miniMapView
            anchors.fill: parent
            lightTheme: root.lightTheme
            marsMode: uiPrefs.marsMode
            source: mapLibreView
            active: miniMapBox.opacity > 0.01
        }

        layer.enabled: true
        layer.effect: OpacityMask { maskSource: fadeMask }

        Canvas {
            id: fadeMask
            anchors.fill: parent
            visible: false
            property bool rhd: root.rightHandDrive
            onRhdChanged: requestPaint()
            onWidthChanged:  requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.globalCompositeOperation = "source-over"
                ctx.fillStyle = "white"
                ctx.fillRect(0, 0, width, height)
                ctx.globalCompositeOperation = "destination-out"
                var w36 = width * 0.36
                var gL = rhd ? ctx.createLinearGradient(width, 0, width - w36, 0)
                             : ctx.createLinearGradient(0, 0, w36, 0)
                gL.addColorStop(0.0, "rgba(0,0,0,1)")
                gL.addColorStop(1.0, "rgba(0,0,0,0)")
                ctx.fillStyle = gL
                ctx.fillRect(rhd ? width - w36 : 0, 0, w36, height)
                var gB = ctx.createLinearGradient(0, height, 0, height * 0.66)
                gB.addColorStop(0.0, "rgba(0,0,0,1)")
                gB.addColorStop(1.0, "rgba(0,0,0,0)")
                ctx.fillStyle = gB
                ctx.fillRect(0, height * 0.66, width, height * 0.34)
                var r = Math.max(width, height) * 0.72
                var cx = rhd ? width : 0
                var gC = ctx.createRadialGradient(cx, height, 0, cx, height, r)
                gC.addColorStop(0.0, "rgba(0,0,0,1)")
                gC.addColorStop(0.45, "rgba(0,0,0,0.75)")
                gC.addColorStop(1.0, "rgba(0,0,0,0)")
                ctx.fillStyle = gC
                ctx.fillRect(0, 0, width, height)
                ctx.globalCompositeOperation = "source-over"
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            // dl69: tap on the mini-map = opens the big map
            onClicked: { root.activeApp = ""; root.carFullScreen = false; root.appPanelFull = false; root.showGrid = false }
            onWheel: (w) => { w.accepted = true }
        }
    }

    // ═══ dl85: drag strip on the left edge of the map = drags the car panel ═══
    Item {
        id: carEdgeDrag
        z: 560
        readonly property real stripW: 26 * root.uPx
        width: stripW
        y: 0
        height: root.height - root.dockVisualH
        x: root.rightHandDrive ? (root.width - root.carW - width) : root.carW
        visible: root.activeApp === "" && !root.appPanelFull && !uiPrefs.fullScreenMap && root.carW < root.width - 2
        enabled: visible

        HoverHandler { cursorShape: Qt.SizeHorCursor }
        DragHandler {
            id: carEdgeHandler
            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
                           | PointerHandler.CanTakeOverFromHandlersOfSameType
            onActiveChanged: {
                if (active) carPanelItem.dragStarted(centroid.scenePosition.x)
                else carPanelItem.dragEnded()
            }
            onCentroidChanged: if (active) carPanelItem.dragMoved(centroid.scenePosition.x)
        }
    }
    // ═══ fine dl85 ═══

    Item {
        id: widgetsContainer
        // Before it was 1100 (above the drawer, z:1000) — inverted: the drawer
        // must draw ABOVE the widgets, not below.
        z: 500
        width:  musicWidget.width + mapWrapper.width + mapToolsBar.width
        height: musicWidget.height
        // In "full-screen map" mode the music player always sits
        // fully on the left (never centered, not even at home): it takes the place
        // that before belonged to MapLibreView.qml's "estimated time" panel
        // (its content is now merged inside the "upcoming
        // directions" panel — see mergedEta in MapLibreView.qml).
        readonly property bool mapHomeActive: uiPrefs.fullScreenMap && root.activeApp === "" && !root.appPanelFull
        readonly property real mapS: musicWidget.baseH / 122     // the map widget follows the miniplayer's height
        readonly property real finalWidth: musicWidget.width + 266 * mapS   // dl84: destination width in full screen
        // dl84: car panel progress (0 = reduced, 1 = full screen), taken from its REAL width (follows animation and finger)
        readonly property real fsP: uiPrefs.fullScreenMap ? 0 : Math.max(0, Math.min(1, (root.carW - root.carMinW) / Math.max(1, root.width - root.carMinW)))
        // Full-screen map with a route: the blue bar (MapLibreView › navPanel) takes the place of the
        // player at the bottom left and the player moves to the right
        readonly property bool musicRight: mapHomeActive
        // Right-hand drive: the player (and the notifications, which follow it) sits on the right, under the car panel
        readonly property real _baseX: (root.rightHandDrive && !uiPrefs.fullScreenMap) ? (root.width - width - 7 * root.uPx) : 7 * root.uPx
        x: musicRight ? (root.width - width - 7 * root.uPx)
                      : (_baseX + ((root.width - finalWidth) / 2 - _baseX) * fsP)
        Behavior on x { enabled: uiPrefs.fullScreenMap; NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        anchors.bottom: parent.bottom
        // Full-screen map with an open app: the player stays on the left, therefore above the blue bar (not below)
        // Shared slot: full-screen map + open app + route -> player and blue bar occupy the same
        // place at the bottom left and swap with a swipe
        readonly property bool slotShared: uiPrefs.fullScreenMap && !mapHomeActive && mapLibreView.navPanelH > 0
        anchors.bottomMargin: root.dockVisualH + root.dockLift + 13 * root.uPx   // widgets (music+map+tools) at 13 wireframe px from the dock
        // "visible" ALWAYS true: setting it to false hides the element
        // instantly in QML, before any animation can
        // start — that is why before there was no entry/exit
        // transition, it snapped suddenly. Now the appearance/disappearance
        // goes only through opacity+scale, with real Behaviors to make them visible.
        readonly property bool shouldShow: !(root.carFullScreen && root.showGrid) && !root.appPanelFull && !carPanelItem.car3DView.uiHidden
        visible: true
        enabled: shouldShow   // not clickable while hidden/fading
        opacity: shouldShow ? 1 : 0
        scale: shouldShow ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

        MusicWidget {
            id: musicWidget
            width: 393 * root.uPx   // miniplayer: 393 px wireframe
            // carousel with the blue bar (only with the shared slot): enters from the right while the other exits to the left
            opacity: widgetsContainer.slotShared ? Math.min(1, root.slotEff * 1.6) : 1
            enabled: widgetsContainer.slotShared ? root.slotEff > 0.5 : true
            transform: Translate { x: widgetsContainer.slotShared ? (1 - root.slotEff) * root.slotTravel : 0 }
            anchors.left: parent.left; anchors.bottom: parent.bottom
            Behavior on scale {
                NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
            }
            audioSrc: root.audioSrc
            widgetTitle:   root.audioSrc === "radio" ? (appPanel.radioTitle || qsTr("Radio")) : root.widgetTitle
            widgetArtist:  root.audioSrc === "radio" ? qsTr("Radio")                          : root.widgetArtist
            widgetArtwork: root.audioSrc === "radio" ? appPanel.radioLogo               : root.widgetArtwork
            isPlaying:     root.audioSrc === "radio" ? appPanel.radioIsPlaying          : root.isPlaying
            progressPct:   root.audioSrc === "radio" ? 0                                : root.progressPct
            durationSec:   root.audioSrc === "radio" ? 0                                : root.durationSec
            canSeek:       root.mprisShown ? Mpris.canSeek
                                           : (root.audioSrc !== "radio" && root.audioSrc !== "bluetooth")
            isFullScreen: root.carFullScreen
            // In "full-screen map" mode the car panel really disappears
            // (visible:false, see carPanelItem) — blurring an invisible
            // background produces an empty/transparent texture, and it is
            // exactly this that made the player "half faded toward
            // invisible": the blurred background sampled nothing. Below
            // there is always the map anyway (mapLayer), so it is the right
            // source to blur in this mode.
            blurSource: uiPrefs.fullScreenMap ? mapLayer : carPanelItem
            blurRect: Qt.rect(widgetsContainer.x + x, widgetsContainer.y + y, width, height)
            radioTitle:   appPanel.radioTitle
            radioArtwork: appPanel.radioLogo
            radioPlaying: appPanel.radioIsPlaying
            onPlayPause: root.handlePlayPause()
            podcastMode: root.podcastMode
            localMusicMode: root.localMusicMode
            podcastSpeedText: root.podcastSpeedText
            onPodcastSkip: secs => root.podcastSkip(secs)
            onPodcastSpeed: root.podcastGet("/player/speed?cycle=1")
            onSeek: pct => root.handleSeek(pct)
            // Heart: radio → radio favorites; YT Music / Spotify → "Likes"
            isLiked: root.audioSrc === "radio" ? appPanel.radioIsFav
                                               : (appPanel.hub ? appPanel.hub.isLiked : false)
            onLike: {
                if (root.audioSrc === "radio") appPanel.radioToggleFav()
                else if (appPanel.hub) appPanel.hub.toggleLike()
            }
            // EQ → Impostazioni › Audio › Equalizzatore
            onOpenEqualizer: {
                root.carFullScreen = false
                appPanel.openEqualizer()
            }
            // dl69: tap on cover/title = "Now playing + Queue"
            onClicked: { root.carFullScreen = false; appPanel.openNowPlaying() }
            onRequestAudioFocus: src => root.pauseAllExcept(src)
            onRequestRadioSkip: dir => { if (dir > 0) appPanel.radioNext(); else appPanel.radioPrev() }
            // Shuffle / Repeat go through the unified queue (MediaHub): real state
            // of the provider, with feedback in the widget and in the queue
            shuffleOn:  appPanel.hub ? appPanel.hub.shuffleOn : false
            repeatMode: appPanel.hub ? appPanel.hub.repeatMode : "off"
            onShuffle: if (appPanel.hub) appPanel.hub.toggleShuffle()
            onRepeat:  if (appPanel.hub) appPanel.hub.cycleRepeat()
            modesAvailable: appPanel.hub ? appPanel.hub.canModes : false
            lyricsAvailable: root.audioSrc === "spotify" || root.audioSrc === "ytmusic"
            lyricsOn: appPanel.lyricsShownFor(root.audioSrc)
            onOpenLyrics: { root.carFullScreen = false; appPanel.openLyrics(root.audioSrc) }
            onRequestSpotifyControl: cmd => {
                // Same rule as play/pause: commands to the shown track
                var o = (root.audioSrc === "spotify" || root.audioSrc === "ytmusic" || root.audioSrc === "bluetooth")
                        ? root.audioSrc : audioFocus.owner
                if (cmd === "toggle")      return
                if (root.audioSrc === "mpris" && root.mprisOk) {
                    if (cmd === "next") Mpris.next(); else if (cmd === "prev") Mpris.previous()
                    return
                }
                if (cmd === "next")        appPanel.musicNext(o)
                else if (cmd === "prev")   appPanel.musicPrev(o)
                else if (cmd === "shuffle") appPanel.musicShuffle(o)
                else if (cmd.indexOf("seek:") === 0) appPanel.musicSeekPct(o, parseFloat(cmd.substring(5)))
            }
            onOpenSearch: {
                        root.carFullScreen = false
                        if (root.audioSrc === "radio") appPanel.radioOpenSearch()
                        else if (root.localMusicMode) appPanel.localMusicOpenSearch()
                        else if (root.audioSrc === "ytmusic") appPanel.ytmusicOpenSearch()
                        else appPanel.spotifyOpenSearch()
                    }
        }

        NotificationStack {
            id: notifStack
            anchors.fill: parent
            z: 900
            targetItem: musicWidget
            lightTheme: root.lightTheme
            blurSource: musicWidget
            overlayDx: musicWidget.overlayDx; overlayDy: musicWidget.overlayDy
            overlayDw: musicWidget.overlayDw; overlayDh: musicWidget.overlayDh
            // call microphone: mutes the source that goes to the phone
            // call dial pad: opens the Phone app
            onKeypadRequested: { root.activeApp = "phone"; appPanel.showPhoneKeypad() }
            onMicToggled: function(isMuted) {
                sysHelper.runDetached("sh", ["-c", "\"$HOME/.local/bin/volta_mute.sh\" " + (isMuted ? "1" : "0")])
            }
        }

        Item {
            id: mapWrapper
            // Never in "full-screen map" mode: there the map is already
            // the whole background, a further preview here would make no sense
            // — in its place mapToolsBar appears, right below.
            width: 266 * widgetsContainer.mapS * widgetsContainer.fsP   // dl84
            height: musicWidget.baseH
            opacity: widgetsContainer.fsP   // dl84
            clip: true
            anchors.left: musicWidget.right; anchors.bottom: parent.bottom
            MapWidget {
                id: mapWidgetItem
                s: widgetsContainer.mapS
                anchors.right: parent.right; anchors.top: parent.top
                // Native map: home/work/search and trip data from the navigator
                mapLibre: mapLibreView
                blurSource: carPanelItem
                blurRect: Qt.rect(widgetsContainer.x + mapWrapper.x + mapWidgetItem.x,
                                  widgetsContainer.y + mapWrapper.y + mapWidgetItem.y,
                                  mapWidgetItem.width, mapWidgetItem.height)
                onOpenMap: {
                    // Home / Work / Search / trip from the widget: the real map is needed
                    uiPrefs.marsMode = false
                    root.carFullScreen = false
                    root.activeApp = ""
                    root.showGrid = false
                }
            }
        }

        // ══════ "Full-screen map" mode: the 5 map buttons
        // (satellite/traffic/POI/chargers/weather — hidden from the original
        // vertical column through mapLibreView.externalControls when
        // this bar is visible) here in a horizontal row next to the
        // music widget. The compass/recenter button is NO longer included here:
        // it now lives next to the search bar (recenterPanel in
        // MapLibreView.qml), always visible in this mode. Visible
        // only when the map is "at home" (no app open): with an app
        // open the map still stays full screen underneath (no more
        // blur/second instance), but that portion of the row would be
        // covered by the app panel itself.
        Item {
            id: mapToolsBar
            visible: false   // the 4 buttons now sit in a column below the recenter button (MapLibreView)
            width: 0
            height: 47 * root.uPx       // same side as the map buttons (47 wireframe px)
            anchors.left: musicWidget.right
            anchors.leftMargin: visible ? 10 : 0
            anchors.bottom: parent.bottom
            clip: true
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

            // Same "glass graphics" as the 5 buttons when they are in a column
            // vertical (GlassPanel in MapLibreView.qml): blurred background
            // "mirror" of the map underneath (not a flat solid-color
            // card as before), same radius (6) and same light shadow
            // — so the two groups of buttons really look like the same
            // element, just rotated horizontally. It uses "mapLayer" as the
            // source to blur: it is reachable by id from here (same
            // file, Main.qml) just as "map" is inside the GlassPanel
            // of MapLibreView.qml.
            Rectangle {
                id: mapToolsBg
                anchors.fill: parent
                radius: 10
                color: "black"
                visible: Theme.lowPower
            }
            DropShadow {
            visible: !Theme.lowPower
                anchors.fill: mapToolsBg
                source: mapToolsBg
                horizontalOffset: 0
                verticalOffset: 4
                radius: 12
                samples: 25
                color: "#4A000000"
                transparentBorder: true
            }
            ShaderEffectSource {
                id: mapToolsBgGrab
                anchors.fill: parent
                sourceItem: mapLayer
                sourceRect: {
                    var p = mapToolsBar.mapToItem(mapLayer, 0, 0)
                    return Qt.rect(p.x, p.y, mapToolsBar.width, mapToolsBar.height)
                }
                live: true
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: mapToolsBgGrab
                blurEnabled: true
                blur: 1.0
                blurMax: 48
                autoPaddingEnabled: false
                maskEnabled: true
                maskSource: mapToolsMask
            }
            Rectangle {
                id: mapToolsMask
                anchors.fill: parent
                radius: 10
                visible: false
                layer.enabled: true
                color: "#FFFFFF"
            }
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: root.lightTheme ? "#A0F2F2F2" : "#A0262626"
            }

            Row {
                id: mapToolsRow
                anchors.centerIn: parent
                spacing: 0
                readonly property real cell: 47 * root.uPx     // side of each button

                // Square button: same idea (icon + selected/not-selected
                // tint), same size (56x56,
                // icon 26x26) as the vertical column's buttons in
                // MapLibreView.qml, only designed to sit in a row. An
                // inline "component" is a type in its own right: it does not see the ids
                // outside its own body (e.g. "mapLibreView"), so both
                // the final color ("tint") and the action ("onTap") are
                // computed/passed from the point where each ToolBtn is
                // instantiated below (there "mapLibreView" is visible
                // normally), not inside the definition itself.
                component ToolBtn: Item {
                    readonly property real cellS: parent ? parent.cell : 56
                    width: cellS; height: cellS
                    property string src: ""
                    property color tint: "#888888"
                    property var onTap: null
                    Image {
                        id: btnImg
                        anchors.centerIn: parent
                        source: parent.src
                        width: 26 * parent.cellS / 56; height: 26 * parent.cellS / 56
                        sourceSize: Qt.size(width * 2, height * 2)
                        visible: false
                    }
                    ColorOverlay {
                        anchors.fill: btnImg
                        source: btnImg
                        color: parent.tint
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: if (parent.onTap) parent.onTap()
                    }
                }
                // Same thin divider (cDivider2-equivalent) used between
                // one button and the next in the vertical column, only
                // vertical instead of horizontal since here the row is
                // orizzontale.
                component ToolDivider: Rectangle {
                    width: 1; height: parent.cell * 0.75
                    anchors.verticalCenter: parent.verticalCenter
                    property color tint: "#3A3A3C"
                    color: tint
                }

                // The "back to position"/compass button is NO longer here:
                // it now lives next to the search bar (recenterPanel in
                // MapLibreView.qml), so only the 5 map buttons remain
                // here (it was redundant to have it here too).
                ToolBtn {
                    src: "qrc:/VoltaApp/icons/globo.svg"
                    tint: mapLibreView.mapStyle === "satellite" ? mapLibreView.cSelected : mapLibreView.cUnselected
                    onTap: function() { mapLibreView.mapStyle = (mapLibreView.mapStyle === "satellite" ? "flat" : "satellite") }
                }
                ToolDivider { tint: root.lightTheme ? "#D0D0D0" : "#3A3A3C" }
                ToolBtn {
                    src: "qrc:/VoltaApp/icons/icons_traffic_dark.svg"
                    tint: mapLibreView.cUnselected
                    // No action: same behavior (for now only
                    // decorative) as the equivalent button in the original
                    // vertical column — not introduced/solved here.
                }
                ToolDivider { tint: root.lightTheme ? "#D0D0D0" : "#3A3A3C" }
                ToolBtn {
                    src: "qrc:/VoltaApp/icons/icons_location_dark.svg"
                    tint: mapLibreView.poisEnabled ? mapLibreView.cSelected : mapLibreView.cUnselected
                    onTap: function() { mapLibreView.poisEnabled = !mapLibreView.poisEnabled }
                }
                ToolDivider { tint: root.lightTheme ? "#D0D0D0" : "#3A3A3C" }
                ToolBtn {
                    src: "qrc:/VoltaApp/icons/icons_charge_dark.svg"
                    tint: mapLibreView.cUnselected
                    onTap: function() { mapLibreView.openNearbyPanel("fuel") }
                }
                ToolDivider { tint: root.lightTheme ? "#D0D0D0" : "#3A3A3C" }
                ToolBtn {
                    src: "qrc:/VoltaApp/icons/icons_weather_dark.svg"
                    tint: mapLibreView.weatherEnabled ? mapLibreView.cSelected : mapLibreView.cUnselected
                    onTap: function() { mapLibreView.weatherEnabled = !mapLibreView.weatherEnabled }
                }
            }
        }
    }

    // Connection error banner — black, yellow danger icon on the left, text
    // on the right, always just above the music widget. Before it used the same
    // generic notification system as calls/messages.
    Rectangle {
        id: connErrorBanner
        z: 501   // above widgetsContainer (500), below the drawer (1000)
        // Taller (40→52) and decidedly narrower (full width of the
        // music widget → 65%) — centered above instead of aligned to
        // the full width.
        width: musicWidget.width * 0.65
        height: 52
        radius: 10
        color: "#E6000000"
        x: widgetsContainer.x + (musicWidget.width - width) / 2
        y: widgetsContainer.y - height - 8
        visible: opacity > 0.01
        opacity: (root._netChecked && !root.online && widgetsContainer.shouldShow) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 12; anchors.rightMargin: 12
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "⚠"
                color: "#FFC400"
                font.pixelSize: 18
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("No connection — check the network")
                color: "#FFFFFF"
                font.pixelSize: 13
                elide: Text.ElideRight
                width: parent.width - 28
            }
        }
    }

    MouseArea {
        id: drawerScrim
        z: 999
        anchors.fill: parent
        visible: root.showGrid
        enabled: root.showGrid
        onClicked: root.showGrid = false
    }

    // Exactly the same pattern as drawerScrim, but to exit the dock's
    // edit mode by tapping any point of the UI. It goes here in
    // Main.qml (not inside DockBar.qml) because a MouseArea nested inside
    // the dock component did not intercept touches outside the dock itself
    // (above the map or an open app) — this one, being a direct child
    // of the window like drawerScrim, works everywhere.
    MouseArea {
        id: dockEditScrim
        z: 999
        anchors.fill: parent
        visible: dockBar.editMode
        enabled: dockBar.editMode
        onClicked: dockBar.editMode = false
    }

    AppDrawer {
        id: appDrawer
        z: 1000; width: 600 * appDrawer.f
        x: (root.width - width) / 2
        // When the dock "rises" in edit mode, the drawer also
        // rises by the same amount to stay above it with the same margin
        // — and dynamically goes back to the default position when exiting
        // edit mode, thanks to the same Behavior already present.
        y: root.showGrid ? (root.height - height - (root.dockVisualH + 12 * root.uPx) - (dockBar.editMode ? dockBar.editGrowth * root.dockScale : 0)) : root.height + 10
        opacity: root.showGrid ? 1 : 0
        editModeActive: dockBar.editMode
        hiddenApps: uiPrefs.hiddenApps
        Behavior on y { NumberAnimation { duration: 550; easing.type: Easing.OutExpo } }
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
        onEditRequested: dockBar.editMode = true
        onAppSelected: appId => {
            if (appId.indexOf("web:") === 0) {           // web app added from the Browser
                var wapp = WebApps.byId(appId.substring(4))
                if (wapp) { appPanel.openWebApp(wapp); root.activeApp = "webapp"; root.showGrid = false }
                return
            }
            root.activeApp = appId
            root.showGrid = false
            dockBar.recordOpened(appId)
        }
        // Dragging an icon toward the dock: the drawer only emits the
        // global coordinates (in the window's space), the geometric test
        // and the decision (add/replace) are made by the dock.
        onDragMoved: (appId, gx, gy) => dockBar.updateDragHover(appId, gx, gy)
        onDragFinished: (appId, gx, gy) => dockBar.handleExternalDrop(appId, gx, gy)
        onDragActiveChanged: active => root.dockDragActive = active
    }

    AppPanel {
        id: appPanel
        fullHost: fullscreenHost
        z: root.appPanelFull ? 2050 : 800     // full screen: above the status bar too (z 2000)
        // Disabled while dragging an icon from the drawer: see
        // note on root.dockDragActive above.
        enabled: !root.dockDragActive
        audioSrc: root.audioSrc
        marsMode: uiPrefs.marsMode
        onMarsModeRequested: on => { uiPrefs.marsMode = on }

        onAudioSourceActivated: source => {
            // We capture the OLD source before changing audioSrc:
            // pauseAllExcept looks at root.audioSrc to decide what to
            // pause, so it must be called BEFORE reassigning it,
            // otherwise "old" and "new" turn out identical and nothing
            // mette in pausa nulla.
            var oldSrc = root.audioSrc
            if (oldSrc !== "" && oldSrc !== source) {
                root.pauseSource(oldSrc)
            }

            root.audioSrc = source
            root._lastExplicitSwitchMs = Date.now()

            // We copy the metadata DIRECTLY here, instead of relying
            // only on the reactive binding (onSpotifyQmlTrackChanged): that
            // binding updates spotifyQmlTrack BEFORE audioSrc has
            // been changed, so on the FIRST song its check
            // "audioSrc === source" still failed (audioSrc was the old
            // one at that precise instant) — hence "first song
            // without cover/title, second song ok".
            if (source === "bluetooth") root.applyBluetoothMeta()
            if (source === "spotify" || source === "ytmusic") {
                root.widgetTitle   = appPanel.spotifyQmlTrack  || root.widgetTitle
                root.widgetArtist  = appPanel.spotifyQmlArtist || ""
                root.widgetArtwork = appPanel.spotifyQmlCover  || ""
                root.isPlaying     = appPanel.spotifyQmlPlaying
            }

            // Explicit reset: without this, the progress bar
            // may stay stuck on an old value (from the previous
            // app) until the next update arrives from the poll, instead of
            // starting clean from zero.
            root.progressPct = 0
            root.progressSec = 0
            root.durationSec = 0
            root.applyMpris()           // if it is a system player, real data right away
        }

        appFullscreen: root.appPanelFull

        // isPanelAnimating disabled to avoid recreating the layer during Fullscreen
        layer.enabled: root.isDraggingApp || root.isDraggingCar
        layer.smooth: true

        width: root.appPanelFull ? root.width : (root.width - root.carMinW)
        height: root.appPanelFull ? root.height : (root.height - 38 * root.uPx)   // top edge at y 38 of the wireframe, bottom unchanged

        Behavior on width {
            enabled: root.isTogglingFullscreen
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            enabled: root.isTogglingFullscreen
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }

        x: root.appPanelFull ? 0
           : (root.rightHandDrive ? (root.width - root.carW) - width : root.carW)

        Behavior on x {
            enabled: root.isTogglingFullscreen
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }

        y: (root.activeApp === "" ? (root.height + 10)
            : (root.appPanelFull ? 0 : 38 * root.uPx)) + root.fsSlideOffset
        Behavior on y {
            enabled: !root.isDraggingApp && !root.fsSliding
            NumberAnimation { duration: 420; easing.type: Easing.OutExpo }
        }

        activeApp: root.activeApp
        audioOwner: audioFocus.owner
        onRequestSwitchApp: appId => root.activeApp = appId
        nativeSurfaces:  root.nativeSurfaces
        nativeToplevels: root.nativeToplevels
        nativeShells:    root.nativeShells
        dockHeight: dockBar.height * root.dockScale
        onSourceActivated: src => root.switchToSource(src)
        onSettingsTheme: (mode, s, e) => {
            uiPrefs.themeMode = mode; uiPrefs.autoStart = s; uiPrefs.autoEnd = e; root.evalSatNight()
            root.evalTheme()
        }
        onSettingsLowPower: on => { uiPrefs.lowPower = on; Theme.lowPower = on }
        onSettingsMirror: rhd => {
            uiPrefs.rightHand = rhd
            root.rightHandDrive = rhd
        }
        onSettingsAmbient: c => {
            uiPrefs.ambient = c
            root.ambientColor = c
        }
        onSettingsAmbientMode: mode => {
            uiPrefs.ambientMode = mode
            root.ambientMode = mode
            root.evalAmbient()
        }
        onSettingsAmbientBrightness: val => {
            uiPrefs.ambientBrightness = val
            root.ambientBrightness = val
        }
        onSettingsBrightness: val => {
            uiPrefs.brightness = val
            root.screenBrightness = val
        }
        onSettingsSatNight: mode => { uiPrefs.satNight = mode; root.evalSatNight() }
        onSettingsBlueLight: on => {
            uiPrefs.blueLightFilter = on
            root.blueLightFilterOn = on
            root.applyBlueLightFilter(on)
        }
        onSettingsScreenClean: root.screenCleanActive = true
        onSettingsPhoneDest: {
            // goes back to the map and shows the QR to send the destination from the phone
            uiPrefs.marsMode = false
            root.carFullScreen = false
            root.activeApp = ""
            root.showGrid = false
            mapLibreView.openPhoneQr()
        }
        onSettingsAppVisibility: csv => { uiPrefs.hiddenApps = csv }
        onSettingsFullScreenMap: on => { uiPrefs.fullScreenMap = on }
        onRadioPlayingUpdated: val => {
            if (val) {
                root.pauseAllExcept("radio")
                root.audioSrc = "radio"
            }
        }

        onFullscreenToggle: {
            if (!root.appPanelFull && root.fsSlideApps.indexOf(root.activeApp) >= 0) {
                root.enterFullscreenSlide()
                return
            }
            root._cancelFullscreenSlide()
            root.isTogglingFullscreen = true
            root.appPanelFull = !root.appPanelFull
            Qt.callLater(function() { root.isTogglingFullscreen = false })
        }
        onRequestAppFullscreen: on => {
            if (on && !root.appPanelFull && root.fsSlideApps.indexOf(root.activeApp) >= 0) {
                root.enterFullscreenSlide()
                return
            }
            root._cancelFullscreenSlide()
            root.isTogglingFullscreen = true
            root.appPanelFull = on
            Qt.callLater(function() { root.isTogglingFullscreen = false })
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // GAME (round79) — FULL-SCREEN panel independent of
    // AppPanel/Arcade (which stay still, unchanged): direct sibling
    // of AppPanel here inside root, above DockBar (z:1000) and also above
    // full-screen AppPanel (z:1001) — it always covers everything. It rises/falls
    // with its own Translate, not with requestAppFullscreen.
    // ══════════════════════════════════════════════════════════════════
    // round83: "black screen, audio yes" — EXACTLY the round77 bug
    // (liveGame inside Arcade), back because "transform: Translate" here
    // was an ANCESTOR of the NativeAppView with its custom subsurfaces —
    // the same combination already identified back then as the cause (a
    // transform/GPU transform node above a WaylandQuickItem with a
    // custom subsurfaceHandler does not compose well, known Qt bug
    // cited in the comments of NativeAppView.qml round63-65). The
    // round77 test (gameTestView) that WORKED used "opacity" to
    // show/hide, NOT a transform — no transform node
    // above the NativeAppView. Here no anchors.fill (otherwise direct "y"
    // conflicts with the anchor, another bug already seen: the
    // "bounce of the handle pill") — fixed x/width/height,
    // and the animation moves "y" as a normal property, no longer a Translate.
    Item {
        id: gameOverlay
        x: 0
        y: root.height
        width: root.width
        height: root.height
        z: 2050     // above the status bar (z 2000)

        property bool shown: appPanel.arcadeItem.nativeGameRunning
        visible: gameOverlay.y < root.height

        NumberAnimation {
            id: gameOverlaySlideAnim
            target: gameOverlay; property: "y"
            duration: 320; easing.type: Easing.OutCubic
        }
        onShownChanged: {
            if (shown) {
                gameOverlay.y = root.height
                gameOverlaySlideAnim.to = 0
                gameOverlaySlideAnim.restart()
            } else {
                gameOverlaySlideAnim.to = root.height
                gameOverlaySlideAnim.restart()
            }
        }

        Rectangle { anchors.fill: parent; color: "#000000" }

        NativeAppView {
            anchors.fill: parent
            appLabel: appPanel.arcadeItem.nativeGameName
            shellSurface:    root.nativeShells["game"]
            waylandToplevel: root.nativeToplevels["game"]
            scaleToFit: true
            isFullscreen: true
        }

        // ── Cover + loading bar, until the real surface
        //    arrives. round97: the bar is an ESTIMATE, not a real progress
        //    (we have no real progress signal, only "it arrived
        //    yes/no"): it rises with a soft curve calibrated on the duration
        //    of the LAST launch of the same game (9 s the first time),
        //    it slows down but never stops completely, and snaps to 100% at the
        //    moment the surface really arrives. No written percentage,
        //    precisely so as not to promise a precision that is not there.
        Rectangle {
            id: gameLoadingOverlay
            anchors.fill: parent
            color: "#000000"
            visible: opacity > 0.01
            opacity: !appPanel.arcadeItem.nativeGameSurfaceSeen ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220 } }

            Column {
                anchors.centerIn: parent
                spacing: 26

                Rectangle {
                    id: loadCover
                    width: 220; height: 310; radius: 12
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "#111111"
                    border.width: 1; border.color: "#2AFFFFFF"
                    Image {
                        id: loadCoverImg
                        anchors.fill: parent
                        anchors.margins: 1
                        source: (appPanel.arcadeItem && appPanel.arcadeItem.nativeGameKey)
                                ? appPanel.arcadeItem.nativeGameCover : ""
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        visible: status === Image.Ready
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle { width: loadCoverImg.width; height: loadCoverImg.height; radius: 11 }
                        }
                    }
                }

                // ESTIMATED progress bar (see comment above).
                Item {
                    id: gameProgress
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 220; height: 6

                    property real value: 0
                    property real startMs: 0
                    // Duration of the last successful launch, per game (ms).
                    property var lastMs: ({})

                    function begin() {
                        var k = appPanel.arcadeItem.nativeGameKey
                        var est = Math.max(3000, Math.min(20000, lastMs[k] || 9000))
                        progAnim.stop()
                        finishAnim.stop()
                        value = 0
                        startMs = Date.now()
                        phase1.duration = est
                        progAnim.start()
                    }
                    function end(surfaceSeen) {
                        progAnim.stop()
                        if (surfaceSeen) {
                            var k = appPanel.arcadeItem.nativeGameKey
                            var took = Date.now() - startMs
                            if (took > 1500 && took < 60000) lastMs[k] = took
                            finishAnim.restart()
                        } else {
                            value = 0
                        }
                    }

                    SequentialAnimation {
                        id: progAnim
                        NumberAnimation {
                            id: phase1
                            target: gameProgress; property: "value"
                            to: 0.88; duration: 9000
                            easing.type: Easing.OutSine
                        }
                        NumberAnimation {
                            target: gameProgress; property: "value"
                            to: 0.98; duration: 25000
                            easing.type: Easing.Linear
                        }
                    }
                    NumberAnimation {
                        id: finishAnim
                        target: gameProgress; property: "value"
                        to: 1; duration: 180
                        easing.type: Easing.OutQuad
                    }

                    Connections {
                        target: appPanel.arcadeItem
                        function onNativeGameLaunchingChanged() {
                            if (appPanel.arcadeItem.nativeGameLaunching)
                                gameProgress.begin()
                            else
                                gameProgress.end(appPanel.arcadeItem.nativeGameSurfaceSeen)
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: "#26FFFFFF"
                    }
                    Rectangle {
                        height: parent.height
                        width: Math.max(height, parent.width * gameProgress.value)
                        radius: height / 2
                        color: "#FFFFFF"
                        visible: gameProgress.value > 0
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: appPanel.arcadeItem.nativeGameName
                    color: "#99FFFFFF"
                    font.pixelSize: 14
                    font.letterSpacing: 0.4
                }
            }
        }

        // ── Top bar: same transparent style as the handle of
        //    AppPanel (topHandle) — only the pill, no dark bar
        //    — with the addition of the "minimize" button on the left. Button or
        //    a decisive downward drag close the game
        //    completely (process included, see arcadeItem.stopNativeGame).
        //    round79b: button moved from TapHandler to MouseArea (same
        //    technique as the old closeBtn) + two temporary console.log
        //    to check that press/drag really arrive.
        Rectangle {
            id: gameTopBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 30
            color: "#99000000"
            z: 10

            property bool dragging: false
            property real dragStartY: 0
            property real dragBaseY: 0
            readonly property real closeThreshold: gameOverlay.height * 0.18

            MouseArea {
                anchors.fill: parent
                anchors.margins: -10
                preventStealing: true
                onPressed: (mouse) => {
                    gameTopBar.dragging = true
                    gameTopBar.dragStartY = mouse.y
                    gameTopBar.dragBaseY = gameOverlay.y
                    gameOverlaySlideAnim.stop()
                    console.log("[gameTopBar] press, y locale=", mouse.y)
                }
                onPositionChanged: (mouse) => {
                    if (!gameTopBar.dragging) return
                    var delta = mouse.y - gameTopBar.dragStartY
                    gameOverlay.y = Math.max(0, gameTopBar.dragBaseY + delta)
                }
                onReleased: (mouse) => {
                    if (!gameTopBar.dragging) return
                    gameTopBar.dragging = false
                    console.log("[gameTopBar] release, gameOverlay.y=", gameOverlay.y, "soglia=", gameTopBar.closeThreshold)
                    if (gameOverlay.y > gameTopBar.closeThreshold) {
                        appPanel.arcadeItem.stopNativeGame()
                    } else {
                        gameOverlaySlideAnim.to = 0
                        gameOverlaySlideAnim.restart()
                    }
                }
                onCanceled: {
                    gameTopBar.dragging = false
                    gameOverlaySlideAnim.to = 0
                    gameOverlaySlideAnim.restart()
                }
            }

            Rectangle {
                id: gameCloseBtn
                width: 44; height: 30
                anchors.left: parent.left
                color: _gameCloseMA.pressed ? "#33FFFFFF" : "transparent"
                // round80: "reduce" icon supplied by the user (SVG, viewBox
                // 0 0 24 24 — two rounded corners pointing toward the
                // centro, stroke-width 2). Qui ridisegnata a mano col
                // Canvas (coordinates scaled from the viewBox, rounded corner
                // approximated with quadraticCurveTo) instead of the old
                // chevron "v" rovesciato.
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
                        // Angolo in alto a destra: M14 4 V8 a2,2 0 0 0 2,2 H20
                        ctx.beginPath()
                        ctx.moveTo(14 * s, 4 * s)
                        ctx.lineTo(14 * s, 8 * s)
                        ctx.quadraticCurveTo(14 * s, 10 * s, 16 * s, 10 * s)
                        ctx.lineTo(20 * s, 10 * s)
                        ctx.stroke()
                        // Angolo in basso a sinistra: M4 14 H8 a2,2 0 0 1 2,2 V20
                        ctx.beginPath()
                        ctx.moveTo(4 * s, 14 * s)
                        ctx.lineTo(8 * s, 14 * s)
                        ctx.quadraticCurveTo(10 * s, 14 * s, 10 * s, 16 * s)
                        ctx.lineTo(10 * s, 20 * s)
                        ctx.stroke()
                    }
                }
                MouseArea {
                    id: _gameCloseMA
                    anchors.fill: parent
                    anchors.margins: -4
                    onClicked: {
                        console.log("[gameTopBar] reduce button pressed")
                        appPanel.arcadeItem.stopNativeGame()
                    }
                }
            }

            Rectangle {
                width: 84; height: 2.5; radius: 10
                anchors.centerIn: parent
                color: gameTopBar.dragging ? "#FFFFFF" : "#8A8B8D"
                Behavior on color { ColorAnimation { duration: 100 } }
            }
        }
    }

    // round88: gameDiag (round87) removed — the log showed 13 calls to
    // handleSubsurfaceAdded instead of 7: gameDiag and gameOverlay were
    // BOTH attached to the same surface at the same time (two
    // NativeAppViews on the same shellSurface), a probable conflict
    // in itself — it invalidated the test as a clean isolation. We go back
    // to a single consumer (gameOverlay) so as not to confuse the next
    // round of logs.

    DockBar {
        id: dockBar
        z: 1000; anchors.bottom: parent.bottom; width: parent.width / root.dockScale; height: root.dockInnerH
        scale: root.dockScale; transformOrigin: Item.BottomLeft
        appCatalog: appDrawer.qtApps
        activeApp: root.activeApp; showGrid: root.showGrid
        rhd: root.rightHandDrive
        carActive: root.carFullScreen
        carFullScreen: root.carFullScreen
        volume: root.volume
        onCarShortPress: {
            root.activeApp     = (root.activeApp === "settings") ? "" : "settings"
            root.carFullScreen = false
            root.showGrid      = false
        }
        onVolumeUp: {
            var nv = Math.min(100, root.volume + 5)
            root.volume = nv
            sysHelper.setVolume(nv)
            root.volShown = true; volHideTimer.restart()
        }
        onVolumeDown: {
            var nv = Math.max(0, root.volume - 5)
            root.volume = nv
            sysHelper.setVolume(nv)
            root.volShown = true; volHideTimer.restart()
        }
        onVolumeSet: value => {
            root.volume = value
            sysHelper.setVolume(value)
        }
        // Tap on the dock's speaker: mute / unmute (without banner)
        onShowVolumeSlider: {
            if (root.volume > 0) {
                root._preMuteVol = root.volume
                root.volume = 0
            } else {
                root.volume = root._preMuteVol > 0 ? root._preMuteVol : 40
            }
            sysHelper.setVolume(root.volume)
        }
        onAppSelected: appId => {
            if (appId === "grid") {
                root.showGrid = !root.showGrid
            } else if (appId === "maps") {
                root.activeApp     = ""
                root.carFullScreen = false
                root.appPanelFull  = false
                root.showGrid      = false
                dockBar.recordOpened(appId)
            } else {
                root.activeApp     = (root.activeApp === appId) ? "" : appId
                root.carFullScreen = false
                root.appPanelFull  = false
                root.showGrid      = false
                dockBar.recordOpened(appId)
            }
        }
    }

    // ═══ VOLUME — banner above the music mini player (photo style):
    // light rectangle with rounded corners, speaker on the left,
    // thin track with dark gray fill and, on the right, the
    // (gray) icon of the app that is playing. It only appears with ‹ / ›.
    property bool volShown: false
    property int  _preMuteVol: 40
    Rectangle {
        id: volOverlay
        z: widgetsContainer.shouldShow ? 502 : 5000
        width: musicWidget.width * 0.65
        height: 52
        radius: 10
        color: root.lightTheme ? "#F4F4F4" : "#2B2B2B"
        border.width: 1
        border.color: root.lightTheme ? "#E0E0E0" : "#3A3A3A"
        // Mini player hidden (full-screen app): at the bottom right above the dock
        x: widgetsContainer.shouldShow ? widgetsContainer.x + (musicWidget.width - width) / 2
                                       : root.width - width - 20
        y: widgetsContainer.shouldShow
           ? widgetsContainer.y - height - 8 - (connErrorBanner.opacity > 0.5 ? connErrorBanner.height + 8 : 0)
           : dockBar.y + dockBar.height * (1 - root.dockScale) - height - 10 - root.dockLift
        visible: opacity > 0.01
        opacity: root.volShown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        layer.enabled: visible && !Theme.lowPower
        layer.effect: DropShadow { radius: 10; samples: 21; verticalOffset: 2; color: "#33000000" }

        readonly property color inkColor: root.lightTheme ? "#3C3C3C" : "#D0D0D0"

        // Altoparlante
        Item {
            id: volIcon
            width: 22; height: 22
            anchors.left: parent.left; anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            Image {
                id: volIconImg
                anchors.fill: parent
                source: "qrc:/VoltaApp/icons/vol-speaker.svg"
                sourceSize: Qt.size(44, 44)
                fillMode: Image.PreserveAspectFit
                visible: false
            }
            ColorOverlay { anchors.fill: parent; source: volIconImg; color: volOverlay.inkColor }
            Rectangle {            // mute bar
                anchors.centerIn: parent
                width: 26; height: 2; radius: 1; rotation: -45
                color: volOverlay.inkColor
                visible: root.volume <= 0
            }
        }

        // Icon of the app that is playing, in gray
        Item {
            id: volSrc
            width: 22; height: 22
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            readonly property string src: musicWidget.srcIcon(root.audioSrc)
            Image {
                id: volSrcImg
                anchors.fill: parent
                source: volSrc.src
                sourceSize: Qt.size(44, 44)
                fillMode: Image.PreserveAspectFit
                visible: false
            }
            ColorOverlay {
                anchors.fill: parent; source: volSrcImg
                color: root.lightTheme ? "#9A9A9A" : "#8A8A8A"
                visible: volSrc.src !== ""
            }
        }

        Rectangle {
            id: volTrack
            anchors.left: volIcon.right; anchors.leftMargin: 14
            anchors.right: volSrc.left; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            height: 5; radius: 2.5
            color: root.lightTheme ? "#D9D9D9" : "#4A4A4A"

            Rectangle {
                width: parent.width * (root.volume / 100)
                height: parent.height; radius: 2.5
                color: root.lightTheme ? "#595959" : "#E0E0E0"
                anchors.left: parent.left
                Behavior on width { NumberAnimation { duration: 90 } }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -14
                preventStealing: true
                function calcVol(mx) {
                    return Math.round(Math.max(0, Math.min(1, (mx - 14) / volTrack.width)) * 100)
                }
                function apply(mx) {
                    var v = calcVol(mx)
                    root.volume = v
                    sysHelper.setVolume(v)
                    volHideTimer.restart()
                }
                onPressed: (m) => apply(m.x)
                onPositionChanged: (m) => { if (pressed) apply(m.x) }
            }
        }

        Timer { id: volHideTimer; interval: 3000; repeat: false; onTriggered: root.volShown = false }
    }

    Loader {
        id: waylandLoader
        asynchronous: true
        source: "VoltaCompositor.qml"
        onLoaded: {
            if (item) {
                item.outputWindow = root

                item.surfaceReady.connect(function(surface, toplevel, shellSurface, appId) {
                    console.log("[Main] Superficie Wayland pronta:", appId)
                    var s  = Object.assign({}, root.nativeSurfaces)
                    var t  = Object.assign({}, root.nativeToplevels)
                    var sh = Object.assign({}, root.nativeShells)

                    s[appId]  = surface
                    t[appId]  = toplevel
                    sh[appId] = shellSurface
                    root.nativeSurfaces  = s
                    root.nativeToplevels = t
                    root.nativeShells    = sh
                })
                item.surfaceClosed.connect(function(appId) {
                    var s  = Object.assign({}, root.nativeSurfaces)
                    var t  = Object.assign({}, root.nativeToplevels)
                    var sh = Object.assign({}, root.nativeShells)

                    delete s[appId]
                    delete t[appId]
                    delete sh[appId]
                    root.nativeSurfaces  = s
                    root.nativeToplevels = t
                    root.nativeShells    = sh
                })

                console.log("[Main] Wayland compositor loaded successfully")
            }
        }
        onStatusChanged: {
            if (status === Loader.Error)
                console.log("[Main] Wayland compositor not available — Firefox will open externally")
        }
    }

    StatusBar {
        id: statusBar
        // Fixed part on the right of the UI (the car panel area will come later)
        y: 0
        x: uiPrefs.fullScreenMap ? 0 : (root.rightHandDrive ? 0 : root.carW)
        width: uiPrefs.fullScreenMap ? root.width : root.width - root.carW
        z: 2000
        lightTheme: root.lightTheme
        locked: root.carLocked
        gpsOk: root.gpsFresh || mapLibreView.fakeGps
        latitude: mapLibreView.carLat
        longitude: mapLibreView.carLon
        onLockToggled: root.carLocked = !root.carLocked
        onWeatherTapped: function(gx) { weatherPopup.anchorX = gx; weatherPopup.open = true }
        // Android Auto already has its own indicators (time, status etc.) — our
        // bar above would be redundant while it is the active app.
        visible: root.activeApp !== "androidauto"
    }

    // Weather popup (opens by tapping the degrees in the top bar)
    WeatherPopup {
        id: weatherPopup
        anchors.fill: parent
        z: 2001
        lightTheme: root.lightTheme
        latitude: mapLibreView.carLat
        longitude: mapLibreView.carLon
        uPx: root.uPx
        topY: statusBar.y + statusBar.height + 6 * root.uPx
    }

    // ═══ SIMULATED BRIGHTNESS ═══
    // There is no real backlight to drive from software, so "darker"
    // is obtained by darkening the whole UI with a semi-transparent
    // black veil above everything (dock, app, map, status bar). Below the
    // screen cleaning veil (lower z than that), so the cleaning mode
    // stays readable even at reduced brightness.
    // It does not intercept touch: it is a simple Rectangle without MouseArea.
    Rectangle {
        anchors.fill: parent
        z: 2100
        color: "#000000"
        // Limited to 0.85 maximum opacity: at 0% brightness the
        // screen must still stay usable (like a real display at
        // minimum), not vanish completely under solid black.
        // It ALWAYS applies, to the whole UI including the Settings themselves
        // (like a real backlight: the screen in front of you
        // darkens too while you adjust the slider) — no exceptions, no
        // z-order tricks: the value follows root.screenBrightness in
        // tempo reale tramite semplice binding.
        opacity: root.screenBrightness >= 100 ? 0 : (1 - root.screenBrightness / 100) * 0.85
        visible: opacity > 0
    }

    // (No more fake veil for the blue light filter: now it is GNOME's native
    // Night Light driven via gsettings, see
    // applyBlueLightFilter() above — that one really "exists on Debian",
    // the QML veil was only a visual approximation and nothing more.)

    // ═══ SCREEN CLEANING MODE — like the EV one ═══
    // A full-screen MouseArea (below, implicitly lower z because
    // declared first) absorbs every stray touch anyway while you
    // clean the glass, so you do not open apps or move the map. But the exit
    // is NO longer "press and hold anywhere": now there is a real button (gray
    // pill) with the text inside, and ONLY while holding it a
    // "Exit in 3/2/1" countdown shown beside it starts — you exit
    // only if you reach 0, if you lift your finger earlier it is canceled.
    Rectangle {
        id: cleanOverlay
        anchors.fill: parent
        z: 3000
        color: "#000000"
        visible: root.screenCleanActive
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        // Absorbs the "stray" cleaning touches (not on the button): it does
        // nothing, it only serves to not let the touch through underneath.
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            onPressed: {}
            onPositionChanged: {}
        }

        Column {
            x: 90
            anchors.verticalCenter: parent.verticalCenter
            width: 420
            spacing: 16

            Text {
                text: qsTr("Screen cleaning")
                color: "#FFFFFF"; font.pixelSize: 24; font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: qsTr("Clean the touchscreen with a soft cloth made for monitors and displays. Do not use cleaning products, wet wipes or electrostatic dry cloths.")
                color: "#C7C7C7"; font.pixelSize: 14; wrapMode: Text.WordWrap
                lineHeight: 1.25
            }
            Item { width: 1; height: 12 }

            Row {
                spacing: 16

                Rectangle {
                    id: exitBtn
                    width: 150; height: 56; radius: 10
                    color: exitMA.pressed ? "#5A5A5A" : "#454545"
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        anchors.margins: 10
                        width: parent.width - 20
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Press and hold\nto exit")
                        color: "#FFFFFF"; font.pixelSize: 13; font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }

                    MouseArea {
                        id: exitMA
                        anchors.fill: parent
                        preventStealing: true
                        onPressed: {
                            exitCountdown.value = 3
                            exitCountdown.active = true
                            exitTicker.start()
                        }
                        onReleased: { exitTicker.stop(); exitCountdown.active = false }
                        onCanceled: { exitTicker.stop(); exitCountdown.active = false }
                    }

                    Timer {
                        id: exitTicker
                        interval: 1000; repeat: true
                        onTriggered: {
                            exitCountdown.value -= 1
                            if (exitCountdown.value <= 0) {
                                exitTicker.stop()
                                exitCountdown.active = false
                                root.screenCleanActive = false
                            }
                        }
                    }
                }

                Text {
                    id: exitCountdown
                    property int value: 3
                    property bool active: false
                    visible: active
                    text: qsTr("Exit in ") + value
                    color: "#FFFFFF"; font.pixelSize: 15; font.weight: Font.DemiBold
                    anchors.verticalCenter: exitBtn.verticalCenter
                }
            }
        }
    }

    // ══════════ Tap outside the keyboard = keyboard closes ══════════
    // Before (browser/map worked, YT Music/Spotify did not) every app
    // had to close the keyboard "by hand" (e.g. "urlInput.focus = false"
    // inside its own MouseArea) — forgetting it in one place left the
    // keyboard open there forever. This single full-screen
    // MouseArea replaces that scattered logic: it activates ONLY when the
    // keyboard is really visible, and at every touch it removes focus from the
    // active text field (whatever it is, in whatever app) — it is
    // exactly this that makes the keyboard disappear, not a direct command
    // on it (same automatic mechanism as Qt.inputMethod.visible
    // already used by VoltaInputPanel.qml).
    //
    // "propagateComposedEvents: true" + "mouse.accepted = false" make
    // the touch, after closing the keyboard, continue anyway toward
    // the underlying element (button, search result, map...): the
    // behavior is therefore "a single tap" as on Android, not
    // "one tap to close the keyboard + one to click" — unless
    // the control under the finger is precisely the text field that had
    // focus (e.g. you tap the search bar again): in that case the
    // focus is removed and then immediately retaken, the keyboard stays open,
    // comportamento corretto.
    //
    // lower z than the keyboard Loader below (999999): a tap
    // on the keyboard itself therefore ALWAYS reaches the Loader first, never
    // this MouseArea, which therefore never interferes with the keys.
    MouseArea {
        id: dismissKeyboardCatcher
        anchors.fill: parent
        z: 999998
        enabled: virtualKeyboardLoader.item ? virtualKeyboardLoader.item.active : false
        propagateComposedEvents: true
        onPressed: (mouse) => {
            var fi = root.activeFocusItem
            if (fi && fi !== dismissKeyboardCatcher && fi.objectName !== "browserPageProxy")
                fi.focus = false
            mouse.accepted = false
        }
    }

    // ══════════ On-screen keyboard (Qt Virtual Keyboard) ══════════
    // Last child of the window on purpose: painted above EVERYTHING, dock
    // included. It attaches by itself to any text field of the app —
    // see VoltaInputPanel.qml. If the Qt Virtual Keyboard module is not
    // installed, "source" simply does not resolve and this Loader stays
    // empty: the rest of the app works anyway, just without a keyboard.
    Loader {
        id: virtualKeyboardLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // Height set HERE, on the real parent (the Window, real
        // size) — not inside VoltaInputPanel.qml. There "parent" would be
        // this same Loader: with only "anchors.bottom" and no height
        // of its own, a Loader without a child with implicitHeight stays
        // 0px high, so any internal calculation based on
        // "parent.height" always came out 0 → invisible keyboard even
        // without any QML error (the probable reason why in round32
        // it did not appear at all).
        // keyboard 1:1 from the SVG: panel 500 px high on a canvas 1920 wide
        height: Math.round(parent.width * 500 / 1920)
        z: 999999
        asynchronous: true
        source: "VoltaInputPanel.qml"
        onStatusChanged: {
            if (debugMode || status === Loader.Error) console.log("[Main] virtualKeyboardLoader status:", status,
                        "(0=Null 1=Ready 2=Loading 3=Error)")
            if (status === Loader.Error)
                console.warn("[Main] Qt Virtual Keyboard not available — on-screen keyboard disabled")
        }
    }

    // Rounded top corners: they simulate the screen's curved edges
    Shape {
        id: screenCorners
        readonly property real r: 9 * root.uPx
        anchors.fill: parent
        z: 1000000
        enabled: false
        ShapePath {
            fillColor: "black"; strokeColor: "transparent"; strokeWidth: 0
            PathSvg { path: "M 0,0 L " + screenCorners.r + ",0 A " + screenCorners.r + " " + screenCorners.r + " 0 0 0 0," + screenCorners.r + " Z" }
        }
        ShapePath {
            fillColor: "black"; strokeColor: "transparent"; strokeWidth: 0
            PathSvg { path: "M " + root.width + ",0 L " + (root.width - screenCorners.r) + ",0 A " + screenCorners.r + " " + screenCorners.r + " 0 0 1 " + root.width + "," + screenCorners.r + " Z" }
        }
    }

    // tests: VOLTA_OPEN=app[:page] (e.g. settings:Arcade) opens an app after startup
    Timer {
        interval: 3000; running: debugOpen !== ""
        onTriggered: {
            var p = debugOpen.split(":")
            root.activeApp = p[0]
            if (p.length > 1 && p[0] === "settings") appPanel.openSettingsPage(p[1])
        }
    }

    Connections {
        target: Services
        function onReady(name) { appPanel.serviceReady(name) }
    }

    // ══════ GUIDED SETUP (first launch, or from Settings › System) ══════
    property bool setupOpen: Setup.needed
    Connections {
        target: Setup
        function onOpenRequested() { root.setupOpen = true }
        // map keys changed: map_proxy restarts, then the style is reloaded
        function onSaved(changed) {
            if (changed.indexOf("MAPBOX_TOKEN") >= 0 || changed.indexOf("MAPTILER_KEY") >= 0) setupStyleReload.restart()
        }
    }
    Timer {
        id: setupStyleReload; interval: 4000
        onTriggered: {
            mapLibreView.applyStyle(true)
            if (miniMapView.reloadStyle) miniMapView.reloadStyle()
        }
    }
    Loader {
        anchors.fill: parent
        z: 1000000
        active: root.setupOpen
        source: "SetupWizard.qml"
        onLoaded: {
            item.lightTheme = Qt.binding(function() { return root.lightTheme })
            item.finished.connect(function() { root.setupOpen = false })
        }
    }

    // Full-screen container for the Theater apps: the panel below stays still
    Item { id: fullscreenHost; anchors.fill: parent; z: 8900 }

    // Shared bottom-left slot (full-screen map + open app + route): blue bar | player.
    // Carousel: the finger drags the two widgets, on release it snaps to one or the other. The DragHandler sits in a
    // transparent layer ABOVE the widgets (high z): it sees gestures first and takes them from the controls after a few pixels,
    // but not from the player's progress bar (preventStealing).
    Item {
        id: slotSwipeZone
        z: 590
        visible: widgetsContainer.slotShared
        x: 7 * root.uPx
        width: root.slotW
        height: Math.max(musicWidget.height, mapLibreView.navPanelH)
        y: widgetsContainer.y + widgetsContainer.height - height
        DragHandler {
            id: slotDrag
            target: null
            xAxis.enabled: true; yAxis.enabled: false
            dragThreshold: 10
            property real startPos: 0
            property real lastDx: 0
            onActiveChanged: {
                if (active) {
                    root.slotAnimOn = false; startPos = root.slotPos; lastDx = 0
                    slotHintAnim.stop(); root.slotHint = 0
                } else {
                    var m = root.slotMusic
                    if (Math.abs(lastDx) > root.slotW * 0.16) m = lastDx < 0    // swipe left = player, right = blue bar
                    root.setSlot(m)
                }
            }
            onTranslationChanged: if (active) {
                lastDx = translation.x
                root.slotPos = Math.max(0, Math.min(1, startPos - translation.x / root.slotTravel))
            }
        }
        // every now and then the widget "peeks" to the side: it hints that you can scroll
        SequentialAnimation {
            id: slotHintAnim
            NumberAnimation { target: root; property: "slotHint"; from: 0; to: 0.11; duration: 380; easing.type: Easing.OutCubic }
            PauseAnimation { duration: 120 }
            NumberAnimation { target: root; property: "slotHint"; to: 0; duration: 520; easing.type: Easing.InOutQuad }
        }
        Timer {
            interval: 6500; repeat: true
            running: widgetsContainer.slotShared && !slotDrag.active
            onTriggered: slotHintAnim.restart()
        }
    }

    // Two dots under the slot: which widget is in front. Tapping them switches widget.
    Item {
        id: slotDots
        z: 600
        visible: widgetsContainer.slotShared
        readonly property real gap: 13 * root.uPx
        width: 58; height: 18
        x: 7 * root.uPx + root.slotW / 2 - width / 2
        y: root.height - (root.dockVisualH + root.dockLift) - gap / 2 - height / 2
        Rectangle {          // pill behind the dots: they are visible on any background
            anchors.fill: parent; radius: height / 2
            color: root.lightTheme ? "#CCFFFFFF" : "#99000000"
            border.width: 1; border.color: root.lightTheme ? "#33000000" : "#33FFFFFF"
        }
        Row {
            anchors.centerIn: parent
            spacing: 12
            Repeater {
                model: 2
                Rectangle {
                    width: 8; height: 8; radius: 4
                    readonly property bool cur: (index === 1) === (root.slotEff > 0.5)
                    color: root.lightTheme ? (cur ? "#111111" : "#9A9A9A") : (cur ? "#FFFFFF" : "#7C7D7F")
                    scale: cur ? 1.15 : 1
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on scale { NumberAnimation { duration: 200 } }
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.setSlot(index === 1) }
                }
            }
        }
    }

    // Call notification above the full-screen apps (the app panel sits at z 2050, outside the notifications container)
    Item {
        id: callAnchor
        width: 360 * root.uPx; height: 88 * root.uPx
        x: (root.width - width) / 2; y: 50 * root.uPx
    }
    NotificationStack {
        id: callStack
        anchors.fill: parent
        z: 9100
        visible: root.appPanelFull
        targetItem: callAnchor
        lightTheme: root.lightTheme
        onKeypadRequested: { root.appPanelFull = false; root.activeApp = "phone"; appPanel.showPhoneKeypad() }
        onMicToggled: function(isMuted) {
            sysHelper.runDetached("sh", ["-c", "\"$HOME/.local/bin/volta_mute.sh\" " + (isMuted ? "1" : "0")])
        }
    }

    // Fireplace (Toybox › Romance): full-screen screen above everything; the app panel below does not move
    ToyboxRomance {
        id: romanceOverlay
        anchors.fill: parent
        z: 9000
    }
    Connections {
        target: appPanel
        function onRomanceRequested() { romanceOverlay.open() }
    }
}
