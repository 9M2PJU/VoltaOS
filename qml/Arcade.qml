import QtQuick
import QtWebEngine
import Qt5Compat.GraphicalEffects
import QtCore as Core
import VoltaApp 1.0

// ARCADE — game launcher in EV style: big header, grid of tiles
// with artwork. The cover and hero of each game are chosen by the user
// from Settings › Arcade (without them, the card shows the name). Games open in the built-in webview.
Rectangle {
    id: arcade
    color: lightTheme ? "#FFFFFF" : "#171717"
    clip: true

    property bool lightTheme: false
    property bool active: false

    // round58+: filled in by AppPanel.qml (same "game" bucket produced by
    // VoltaCompositor.qml for any Wine/Bottles .exe — see normalize()).
    property var nativeSurfaces:  ({})
    property var nativeToplevels: ({})
    property var nativeShells:    ({})

    property string currentUrl: ""
    property string currentName: ""

    // "Back" navigation — driven by the panel's handle (AppPanel)
    property bool canGoBack: currentUrl !== ""
    function goBack() { arcade.currentUrl = "" }

    property alias webView: arcadeWeb

    signal requestFullscreen(bool on)
    signal mediaActivated()
    // Menu Theater/Arcade in alto: preme "Theater" -> chi instanzia Arcade
    // (AppPanel) changes app. Consistent with switchToArcade in Theater.qml.
    signal switchToTheater()
    signal switchToToybox()

    onActiveChanged: { if (!active) currentUrl = ""; else refreshFound() }   // on reopening: games added in the meantime

    // round60: nativeShells is the dictionary SHARED with the other native
    // apps (Android Auto...), so this handler fires for any Wayland
    // surface of the compositor, not just for games — we act
    // only when it concerns us (nativeGameRunning true). See
    // launchTimeoutTimer and endNativeGame below for the reason.
    onNativeShellsChanged: {
        if (!nativeGameRunning) return
        if (nativeShells["game"]) {
            if (!nativeGameSurfaceSeen) {
                nativeGameSurfaceSeen = true
                // round78: there is no longer an estimated timer ("launchHoldMs") deciding
                // when the loading overlay disappears — now it is
                // the real surface arriving that decides it, here.
                nativeGameLaunching = false
                launchTimeoutTimer.stop()
            }
        } else if (nativeGameSurfaceSeen) {
            // It had appeared and has now disappeared by itself (not by our hand,
            // otherwise we would already have left stopNativeGame): the game
            // closed or crashed.
            endNativeGame(nativeGameName + qsTr(" closed unexpectedly."))
        }
    }

    // ── Games ───────────────────────────────────────────────
    property var games: [
        // ── Games installed on Bottles (Wine) ────────────────────────
        // "native: true" + "program"/"executable" instead of "url": the Play
        // button does not open the webview, it launches the game via Bottles/Wine (see
        // launchNativeGame below). Since round58 the game connects as a native
        // Wayland client of our compositor and is really embedded.
        // Since round78 it appears in a dedicated FULL-SCREEN app panel
        // (see gameView in AppPanel.qml), no longer inside Arcade —
        // here only the state and the launch/close functions remain.
        { key: "cuphead", name: "Cuphead",                  accent: "#E85D3B", native: true, program: "Cuphead" },
        { key: "bbr2",    name: "Beach Buggy Racing 2",      accent: "#2FA867", native: true, program: "Beach Buggy Racing 2" },
        { key: "pvz",     name: "Plants vs Zombies",         accent: "#5FAE3E", native: true, program: "Plantes VS Zombie Replanted" },
        { key: "pes2013", name: "Pro Evolution Soccer 2013", accent: "#1667F2", native: true, program: "Pro Evolution Soccer 2013" },
        // Limbo: the "Program" saved by Bottles points to a path with
        // wrong upper/lower case (limbo.exe instead of Limbo.exe) —
        // we launch the exact executable directly with "-e" instead of "-p".
        { key: "limbo",   name: "Limbo",                     accent: "#333333", native: true,
          executable: homeDir + qsTr("/.var/app/com.usebottles.bottles/data/bottles/bottles/pes-2012/drive_c/Program Files (x86)/LIMBO.v2025.09.12/game/Limbo.exe") }
    ]

    // ── Games found in Bottles (map_proxy /games) ──────────────────────
    // Any program added in Bottles, in any bottle, shows up here by
    // itself after the ones above, with the cover chosen by the user (if any).
    property var _found: []
    function refreshFound() {
        var x = new XMLHttpRequest()
        x.open("GET", "http://127.0.0.1:9098/games")
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE || x.status !== 200) return
            try { arcade._found = JSON.parse(x.responseText).games || [] } catch (e) {}
        }
        x.send()
    }
    Component.onCompleted: refreshFound()
    readonly property var allGames: {
        var known = {}
        for (var i = 0; i < games.length; i++) {
            known[(games[i].name || "").toLowerCase()] = true
            if (games[i].program) known[games[i].program.toLowerCase()] = true
        }
        var out = games.slice()
        for (var j = 0; j < _found.length; j++) {
            var f = _found[j]
            if (known[f.name.toLowerCase()] || known[f.program.toLowerCase()]) continue
            out.push({ key: "b_" + f.key, artKey: f.key, name: f.name, accent: "#2C7BF2",
                       native: true, program: f.program, bottle: f.bottle, cover: f.cover, hero: f.hero })
        }
        return out
    }
    // ── Preferenze (Impostazioni › Arcade) ──
    Core.Settings {
        id: arcadePrefs
        category: "arcade"
        property string hiddenJson: "[]"     // keys of the hidden games
    }
    readonly property var hiddenKeys: { try { return JSON.parse(arcadePrefs.hiddenJson) } catch (e) { return [] } }
    function isHidden(key) { return hiddenKeys.indexOf(key) >= 0 }
    function setHidden(key, hidden) {
        var l = hiddenKeys.filter(function(k) { return k !== key })
        if (hidden) l.push(key)
        arcadePrefs.hiddenJson = JSON.stringify(l)
    }
    // quelli mostrati nell'Arcade (allGames, meno i nascosti)
    readonly property var visibleGames: allGames.filter(function(g) { return hiddenKeys.indexOf(g.key) < 0 })

    // Covers and heroes: images chosen by the user, served by map_proxy
    property int artRev: 0          // goes up when a custom cover changes (refreshes the images)
    function artKey(g) { return g.artKey || g.key }
    function artUrl(g, kind) {
        return "http://127.0.0.1:9098/games/art/" + arcade.artKey(g) + "/" + kind
               + "?n=" + encodeURIComponent(g.name) + "&v=" + arcade.artRev
    }
    function coverUrl(g) { return g.cover ? g.cover + "&v=" + arcade.artRev : arcade.artUrl(g, "cover") }
    function heroUrl(g)  { return g.hero  ? g.hero  + "&v=" + arcade.artRev : arcade.artUrl(g, "hero") }
    // Sets (path) or removes (empty path) a custom cover/hero
    function setCustomArt(g, kind, path) {
        var x = new XMLHttpRequest()
        x.open(path ? "POST" : "DELETE", "http://127.0.0.1:9098/games/art/" + arcade.artKey(g) + "/" + kind + "/custom")
        x.setRequestHeader("Content-Type", "application/json")
        x.onreadystatechange = function() { if (x.readyState === XMLHttpRequest.DONE) arcade.artRev++ }
        x.send(path ? JSON.stringify({ path: path }) : "")
    }

    // Selected game (shown in the big photo)
    property int selectedIdx: 0
    readonly property var selectedGame: visibleGames.length > 0
        ? visibleGames[Math.max(0, Math.min(selectedIdx, visibleGames.length - 1))]
        : ({ key: "", name: qsTr("No games"), info: qsTr("Show them in Settings › Arcade"), accent: "#333333" })
    property string nativeGameCover: ""

    function openGame(url, name) {
        arcade.currentName = name
        arcade.currentUrl  = url
    }

    // ── Native games (Bottles/Wine) ───────────────────────────────────
    // All 5 games live in the same bottle "pes 2012" (confirmed
    // from the terminal) — "stop" therefore closes whichever of them is running,
    // without having to track the PID of the launched process.
    readonly property string bottlesBottle: qsTr("pes 2012")
    property bool nativeGameRunning: false
    property string nativeGameName: ""
    property string nativeGameKey: ""
    property string nativeGameAccent: "#2C7BF2"

    // round78: it is no longer tied to a launch animation with an
    // estimated time — it stays true from the tap on "Play" until the
    // real surface arrives (see onNativeShellsChanged above). The
    // fullscreen panel (AppPanel.qml → gameView) only uses it to know whether
    // to still show the cover+loading spinner.
    property bool nativeGameLaunching: false

    // round60: before this round, if the game NEVER sent a Wayland
    // surface (bottle already occupied by a zombie wineserver from
    // a previous test, silent crash, hang...) we were stuck
    // forever on an empty screen: the launcher hidden (nativeGameRunning
    // true) and nothing to show, without any timeout or message —
    // the only way out was to close by hand. "nativeGameSurfaceSeen" +
    // launchTimeoutTimer (below) + onNativeShellsChanged (above) provide
    // an automatic exit.
    property bool nativeGameSurfaceSeen: false
    property int launchTimeoutMs: 20000
    property string launchErrorMessage: ""

    SystemHelper { id: sysHelper }

    function launchNativeGame(game) {
        arcade.nativeGameName = game.name
        arcade.nativeGameKey = game.key
        arcade.nativeGameCover = arcade.coverUrl(game)
        arcade.nativeGameAccent = game.accent || "#2C7BF2"
        arcade.nativeGameRunning = true
        arcade.nativeGameLaunching = true
        arcade.nativeGameSurfaceSeen = false
        arcade.launchErrorMessage = ""
        launchTimeoutTimer.restart()
        // round78: the real game box (cover+spinner while
        // loading, then the full-screen game) now lives in Main.qml,
        // DIRECT sibling of AppPanel inside the Window (see gameView
        // there) — no longer inside AppPanel/Arcade (round77: in there,
        // nested/with a sliding Translate, the video did not
        // vedeva; round78-v1: usare arcade.requestFullscreen faceva
        // resize Arcade itself too, which instead must stay
        // still). Arcade below no longer touches any fullscreen: the
        // new panel covers everything on its own, regardless of
        // how Arcade is set at that moment.
        // round58-65: --env=WAYLAND_DISPLAY=wayland-volta collegava Wine
        // DIRECTLY as a native Wayland client of our compositor.
        // Funzionava (toplevel riconosciuto, classificato, incorporato) MA
        // the game's real content ended up on a child wl_subsurface,
        // not on the main toplevel — and there a QtWaylandCompositor bug
        // (see the round62/63/65 comments in NativeAppView.qml) ALWAYS prevented
        // composition on screen, identical with DXVK or WineD3D,
        // with any Wine runner tried. Not solvable from QML.
        //
        // round66 (ABANDONED): a dedicated "bare" Xwayland, with DISPLAY
        // forced by hand for Wine. Right idea (bypass the subsurfaces),
        // fragile execution: Wine kept ignoring the DISPLAY we
        // passed it and always went back to the native Wayland driver toward the
        // normal desktop — result a Wine window disconnected from our
        // compositor, not what we want.
        //
        // round67 (ABANDONED AT THE TIME): gamescope. It connects to the external
        // compositor with its own "xdg_backend" that REQUIRES
        // the wp_presentation protocol — which our compositor did not
        // have (private Qt header for QWaylandPresentationTime,
        // see VoltaPresentation.h/.cpp). Confirmed in the log: "xdg_backend:
        // Couldn't create Wayland objects", then silent fallback to a
        // HEADLESS backend (invisible, meant for streaming/screen
        // capture, not for showing anything on screen) — that is why nothing
        // appeared, anywhere.
        //
        // round68/68c/71: dedicated "bare" Xwayland as an alternative. It DID
        // connect to our compositor ("Xwayland on :NN" toplevel
        // recognized, confirmed in the log), but it exposed ITS WHOLE virtual X11
        // desktop as a single surface — nothing to do with the game's
        // content itself, just "the desktop the game lives
        // in" (which on top of that required an X11 window manager
        // of its own to get decorations too, seen in the
        // user's screenshot: it is not our bug, it is simply
        // the wrong tool for "one surface per game").
        //
        // round72: we go back to gamescope, because the real obstacle of round67
        // has been removed — we implemented wp_presentation from scratch,
        // without depending on Qt's private class (see
        // VoltaPresentation.h/.cpp, compilata e linkata, confermata attiva
        // in the log: "[Compositor] wp_presentation inizializzato"). gamescope
        // now finds the protocol it needs and, like Waydroid, exposes to OUR
        // compositor A SINGLE clean surface for the game (not
        // the whole X11 desktop like bare Xwayland) — it handles all
        // the complexity of graphics driver/subsurfaces inside itself. See
        // native_game_gamescope_launch.sh in the project root.
        //
        // round77: even with gamescope the REAL content still arrives on
        // wl_subsurfaces (confirmed in the logs: several "handleSubsurfaceAdded"
        // in the same session) — already handled since round62/63 in
        // NativeAppView.qml. The video was still not visible because the
        // box that hosted it (liveGame, here in Arcade) was nested
        // too deep with a sliding Translate transform:
        // moved one level up, sibling of Arcade in
        // AppPanel.qml (round78, see gameView), the video shows.
        var cmd = "'" + appDir + "/scripts/native_game_gamescope_launch.sh' '" + (game.bottle || arcade.bottlesBottle) + "' "
        cmd += game.executable ? ("-e '" + game.executable + "'") : ("-p '" + game.program + "'")
        sysHelper.runDetached("/bin/sh", ["-c", cmd])
    }

    // round78: closing — both from the "minimize" button and from dragging
    // the handle downward in the fullscreen panel (see gameView in
    // AppPanel.qml), called ONCE for both gestures. It is no
    // longer just "stop Bottles": a backup pkill on the
    // gamescope process of this session was also added — extra safety net in
    // case bottles-cli is not enough to really make the process disappear.
    // round80: first /tmp/volta_native_game_gamescope.pid is read (written
    // by native_game_gamescope_launch.sh, which now launches gamescope with
    // "set -m" → that PID is also the pgid of a process group of its own) and
    // SIGTERM is sent to the WHOLE GROUP ("kill -TERM -$P", the minus before
    // = group, not just that process) — so in one go flatpak/bwrap,
    // bottles-cli, wineserver, the game's real executable and gamescope's
    // internal Xwayland also end, not just gamescope itself.
    // After a short wait a safety SIGKILL on the same group for
    // whoever did not stop. bottles-cli stop + the two pkill -f stay
    // as an additional safety net (harmless if they find nothing), but
    // now they are NOT the main mechanism anymore: before, it was enough
    // to leave pieces of the tree alive, causing the conflict reported
    // at the launch of the next game.
    // round86: discovered with "ps aux" that "gamescopereaper" and the "bwrap"
    // that encapsulates bottles-cli ALWAYS SURVIVE the process group
    // kill of round80 — gamescope itself dies (consistent with the logs:
    // "Superficie chiusa"/"Ucciso"), but bwrap isolates its process in its
    // own namespace that the SIGTERM/SIGKILL on the process group does not
    // reach. Real result (not a supposition, confirmed with ps):
    // after EVERY launch a gamescopereaper+bwrap pair stayed hanging for hours
    // on the same bottle "pes 2012" — at that point
    // a later launch finds the bottle already "occupied" by
    // ghost sessions, hence the strange audio-yes/video-no symptoms. Two explicit
    // pkill -f added for these two patterns, which work by process
    // name regardless of process group/namespace.
    // round94: SINGLE CLEANUP, fast and without self-killing, used by
    // stopNativeGame() and endNativeGame(). Two real defects in the
    // precedente (round80/86):
    //  1) "pkill -f 'native_game_gamescope_launch.sh'" inside "sh -c <text>"
    //     ALSO found the shell itself (the pattern is written in its command
    //     line) and killed it halfway: everything that came after
    //     (gamescopereaper, bwrap, removal of the PID file) never ran.
    //     Verified in testing: the shell never reached the next command.
    //     Now the patterns are anchored (^) or use the [x] trick, so
    //     they do not match this shell's command line.
    //  2) "bottles-cli stop" (Python + flatpak, ~4 s) ran BEFORE the pkills:
    //     if another game was opened within those seconds, the cleanup of the
    //     previous one could kill the new launch. With the direct launch
    //     of Wine (round92) it is no longer needed: wineserver
    //     and the Wine processes are closed directly, in under a second.
    function nativeCleanupCmd() {
        return "P=$(cat /tmp/volta_native_game_gamescope.pid 2>/dev/null); " +
            "if [ -n \"$P\" ]; then kill -TERM -\"$P\" 2>/dev/null; sleep 0.3; kill -KILL -\"$P\" 2>/dev/null; fi; " +
            "pkill -9 -f '[n]ative_game_gamescope_launch.sh' 2>/dev/null; " +
            "pkill -9 -f '^[g]amescope' 2>/dev/null; " +
            "pkill -9 -f '^[b]wrap .*(bin/wine start|bottles-cli)' 2>/dev/null; " +
            "if [ -f /tmp/volta_wine_warm ]; then " +
            // round96: "warm" Wine session (VOLTA_HOST=1 in the
            // lancio): wineserver, services.exe e winedevice DEVONO restare
            // alive for the next game. Only the game, the
            // Wine desktop (explorer, tied to gamescope's DISPLAY which
            // sta morendo) e start.exe.
            "pkill -9 -f '^[A-Z]:.windows.system32.[e]xplorer.exe' 2>/dev/null; " +
            "pkill -9 -f '^[A-Z]:.windows.system32.[s]tart.exe' 2>/dev/null; " +
            "else " +
            "pkill -9 -x wineserver 2>/dev/null; " +
            "pkill -9 -f '^[A-Z]:.windows.system32' 2>/dev/null; " +
            "fi; " +
            "pkill -9 -f '^[A-Z]:.Program Files' 2>/dev/null; " +
            "rm -f /tmp/volta_native_game_gamescope.pid; true"
    }

    function stopNativeGame() {
        sysHelper.runDetached("/bin/sh", ["-c", nativeCleanupCmd()])
        resetNativeGameState()
    }

    // round60: shared "back to the launcher" path, used both by the automatic
    // cases — launch timeout (launchTimeoutTimer) or unexpected disappearance
    // of the surface (onNativeShellsChanged) — and by the voluntary
    // close below (see endNativeGame). Empty "message"
    // = close wanted by the user, no banner; otherwise we show the
    // reason for a few seconds instead of silently going back to the launcher
    // as if nothing had happened.
    function endNativeGame(message) {
        // Defensive: if the bottle is really stuck (not just "never
        // started"), we try to stop it anyway — harmless if it is already dead.
        // round86: same robust kill (+ gamescopereaper/bwrap) as
        // stopNativeGame() above, see the comment there.
        sysHelper.runDetached("/bin/sh", ["-c", nativeCleanupCmd()])
        resetNativeGameState()
        arcade.launchErrorMessage = message
        launchErrorTimer.restart()
    }

    function resetNativeGameState() {
        launchTimeoutTimer.stop()
        arcade.nativeGameRunning = false
        arcade.nativeGameLaunching = false
        arcade.nativeGameSurfaceSeen = false
        arcade.nativeGameName = ""
    }

    // round60: it stops by itself as soon as the "game" bucket surface arrives
    // (see onNativeShellsChanged above). If it fires, it means the game
    // never showed up within launchTimeoutMs — bottle occupied by
    // a zombie wineserver, silent crash before creating a window,
    // hang... in any case better to go back to the launcher with a message than
    // stay on an empty full screen forever.
    Timer {
        id: launchTimeoutTimer
        interval: arcade.launchTimeoutMs
        repeat: false
        onTriggered: arcade.endNativeGame(arcade.nativeGameName + qsTr(" didn't start. Try again."))
    }

    // round60: how long launchErrorBanner (below) stays visible before
    // disappearing by itself.
    Timer {
        id: launchErrorTimer
        interval: 4500
        repeat: false
        onTriggered: arcade.launchErrorMessage = ""
    }

    // ══════════════════════════════════════════════════════════════════════
    //  HEADER BAR — fixed at the top, app icon on the left, menu
    //  Theater/Arcade centered over the full width. Exactly the same
    //  style as Theater.qml.
    // ══════════════════════════════════════════════════════════════════════
    Item {
        visible: arcade.currentUrl === ""
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 20
        height: 26
        z: 50

        Image {
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            source: "qrc:/VoltaApp/icons/arcade.svg"
            sourceSize: Qt.size(26, 26)
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: 18

            Text {
                text: qsTr("Theater")
                color: lightTheme ? "#444444" : "#A2A3A5"
                font.pixelSize: 20; font.weight: Font.DemiBold
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    onClicked: arcade.switchToTheater()
                }
            }
            Text {
                text: "Arcade"
                color: lightTheme ? "#171717" : "#FFFFFF"
                font.pixelSize: 20; font.weight: Font.DemiBold
                // No MouseArea: we are already on Arcade.
            }
            Text {
                text: qsTr("Toybox")
                color: lightTheme ? "#444444" : "#A2A3A5"
                font.pixelSize: 20; font.weight: Font.DemiBold
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    onClicked: arcade.switchToToybox()
                }
            }
        }
    }

    // round60: until now, if a game did not start (see
    // launchTimeoutTimer/endNativeGame above) we went back to the launcher without
    // saying anything — it looked like the tap had done nothing.
    Rectangle {
        id: launchErrorBanner
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 64
        z: 70
        radius: 10
        color: "#D4302B2B"
        border.width: 1; border.color: "#33FFFFFF"
        width: errorText.implicitWidth + 32
        height: errorText.implicitHeight + 20
        visible: opacity > 0.001
        opacity: arcade.launchErrorMessage !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Text {
            id: errorText
            anchors.centerIn: parent
            text: arcade.launchErrorMessage
            color: "#FFFFFF"
            font.pixelSize: 15; font.weight: Font.Medium
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    //  LAUNCHER — big photo + Play button + row of vertical cards
    // ══════════════════════════════════════════════════════════════════════
    Item {
        id: launcher
        anchors.fill: parent
        // round58+: also hidden while a native game is really running
        // (round78: now in a separate fullscreen panel, see gameView
        // in AppPanel.qml), not just for the webviews.
        visible: arcade.currentUrl === "" && !arcade.nativeGameRunning

        readonly property real cardRowH: 224

        // ── BIG PHOTO of the selected game (centered, rounded corners) ──
        Item {
            id: hero
            anchors.top: parent.top
            // Before 10 — too little, the Theater/Arcade bar (which sits at
            // margin 20 + ~26px of icon) ended up on top of it. Now the
            // content moves down to leave it room, instead of
            // sovrapporsi.
            anchors.topMargin: 66
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 40
            // -56 extra to compensate for the higher topMargin and keep
            // the bottom edge at the same point as before (it does not push
            // the row of cards below down too).
            height: parent.height - launcher.cardRowH - 30 - 56

            // dedicated hero (<key>_hero.png), with fallback to the card
            Image {
                id: heroImg
                anchors.fill: parent
                source: arcade.heroUrl(arcade.selectedGame)
                fillMode: Image.PreserveAspectCrop
                smooth: true
                visible: status === Image.Ready
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle { width: heroImg.width; height: heroImg.height; radius: 8 }
                }
            }
            Image {
                id: heroFallback
                anchors.fill: parent
                source: arcade.coverUrl(arcade.selectedGame)
                fillMode: Image.PreserveAspectCrop
                smooth: true
                visible: heroImg.status !== Image.Ready && status === Image.Ready
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle { width: heroFallback.width; height: heroFallback.height; radius: 8 }
                }
            }
            // Placeholder if there is no image
            Rectangle {
                anchors.fill: parent; radius: 8
                visible: heroImg.status !== Image.Ready && heroFallback.status !== Image.Ready
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.darker(arcade.selectedGame.accent, 3.2) }
                    GradientStop { position: 1.0; color: lightTheme ? "#FFFFFF" : "#171717" }
                }
                Text {
                    anchors.centerIn: parent
                    text: arcade.selectedGame.name
                    color: "#33FFFFFF"; font.pixelSize: 88; font.weight: Font.Black
                }
            }

            // Pure Black and Short gradient at the bottom (only above the image)
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.bottom: parent.bottom; height: 120
                radius: 8
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00000000" } // Totalmente trasparente
                    GradientStop { position: 0.5; color: "#A6000000" } // Sfuma velocemente a 65% nero
                    GradientStop { position: 1.0; color: "#FF000000" } // Nero opaco solido
                }
            }

            // ── Blue PLAY button + title beside it (raised to detach from the bottom) ──
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 28
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 40
                spacing: 24
                z: 10 // Makes sure it is drawn above the gradient

                Rectangle {
                    id: playBtn
                    width: 210; height: 52; radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: _playMA.pressed ? "#1E63D0" : "#2C7BF2"
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Play game")
                        color: "#FFFFFF"; font.pixelSize: 17; font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: _playMA; anchors.fill: parent
                        onClicked: {
                            if (arcade.selectedGame.native)
                                arcade.launchNativeGame(arcade.selectedGame)
                            else
                                arcade.openGame(arcade.selectedGame.url, arcade.selectedGame.name)
                        }
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Text {
                        text: arcade.selectedGame.name
                        color: "#FFFFFF"
                        font.pixelSize: 26; font.weight: Font.Normal
                        style: Text.Raised; styleColor: "#80000000"
                    }
                    Text {
                        text: arcade.selectedGame.info || ""
                        color: "#E0E0E0"
                        font.pixelSize: 13
                    }
                }
            }
        }

        // ── FILA DI CARD VERTICALI ────────────────────────────────────────
        ListView {
            id: cardRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            anchors.leftMargin: 20
            height: launcher.cardRowH - 30
            orientation: ListView.Horizontal
            spacing: 16
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: arcade.visibleGames

            delegate: Item {
                width: 132; height: cardRow.height
                Rectangle {
                    id: card
                    anchors.fill: parent
                    radius: 8
                    color: lightTheme ? "#FFFFFF" : "#111111"
                    border.width: index === arcade.selectedIdx ? 2 : 1
                    border.color: index === arcade.selectedIdx ? (lightTheme ? "#1667F2" : "#FFFFFF") : (lightTheme ? "#DDDDDD" : "#242424")
                    scale: _cMA.pressed ? 0.97 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    Image {
                        id: cardImg
                        anchors.fill: parent
                        anchors.margins: 1
                        source: arcade.coverUrl(modelData)
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        visible: status === Image.Ready
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle { width: cardImg.width; height: cardImg.height; radius: 8 }
                        }
                    }

                    // Without a cover: the game's initial, large
                    Text {
                        anchors.centerIn: parent
                        visible: cardImg.status !== Image.Ready
                        text: (modelData.name || "?").charAt(0).toUpperCase()
                        color: lightTheme ? "#171717" : "#F0F0F0"; opacity: 0.85
                        font.pixelSize: Math.round(parent.height * 0.42); font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: _cMA
                        anchors.fill: parent
                        // First tap: selects (big photo above). Tap on the already
                        // selected game: launches it directly.
                        onClicked: {
                            if (arcade.selectedIdx === index) {
                                if (modelData.native)
                                    arcade.launchNativeGame(modelData)
                                else
                                    arcade.openGame(modelData.url, modelData.name)
                            } else {
                                arcade.selectedIdx = index
                            }
                        }
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    //  WEBVIEW (game open)
    // ══════════════════════════════════════════════════════════════════════
    // Web profile with data saved to disk (VoltaArcadeData). No "offTheRecord: false":
    // set before storageName it produced the warning "Storage name is empty...".
    // (Qt 6.9's WebEngineProfilePrototype does not work here: instance() is null while
    //  the WebEngineView is created, and setProfile(null) crashes.)
    WebEngineProfile {
        id: arcadeProfile
        storageName: "VoltaArcadeData"
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
        httpUserAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    }

    Item {
        id: webWrap
        anchors.fill: parent
        visible: arcade.currentUrl !== ""
        clip: true

        // Same bottom-to-top slide used in Theater.qml.
        transform: Translate { id: webSlideT; y: 0 }
        NumberAnimation {
            id: webSlideAnim
            target: webSlideT; property: "y"
            to: 0
            duration: 360; easing.type: Easing.OutCubic
        }
        onVisibleChanged: if (visible) {
            webSlideT.y = webWrap.height
            webSlideAnim.restart()
        }

        WebEngineView {
            settings.showScrollBars: false
            id: arcadeWeb
            anchors.fill: parent
            profile: arcadeProfile
            url: arcade.currentUrl
            settings.pluginsEnabled: true
            settings.javascriptEnabled: true
            settings.playbackRequiresUserGesture: false
            settings.javascriptCanAccessClipboard: true
            settings.localContentCanAccessRemoteUrls: true

            lifecycleState: (arcade.active && arcade.currentUrl !== "")
                            ? WebEngineView.LifecycleState.Active
                            : WebEngineView.LifecycleState.Discarded

            onRecentlyAudibleChanged: if (recentlyAudible) arcade.mediaActivated()

            onFullScreenRequested: function(request) {
                request.accept()
                arcade.requestFullscreen(request.toggleOn)
            }
        }
    }

}
