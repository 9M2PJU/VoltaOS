import QtQuick
import QtWayland.Compositor
import QtWayland.Compositor.XdgShell
import VoltaApp 1.0

WaylandCompositor {
    id: comp
    socketName: "wayland-volta"

    // The REAL window we render on. Main.qml sets it
    // (item.outputWindow = root) AFTER the load. We create the WaylandOutput
    // only at that point: if it were created before with window null, Qt
    // initializes it without a QQuickWindow and then refuses to assign it
    // ("not supported after QWaylandOutput has been initialized") →
    // integrazione EGL rotta e null texture.
    property var outputWindow: null
    property var _output: null

    onOutputWindowChanged: {
        if (outputWindow && !_output) {
            _output = outputComponent.createObject(comp, { "window": outputWindow })
            console.log("[Compositor] WaylandOutput created on the real window")
        }
    }

    Component {
        id: outputComponent
        WaylandOutput {
            compositor: comp
            sizeFollowsWindow: true
        }
    }

    // ── wp_viewporter / wp_presentation: same "late creation" logic
    // as WaylandOutput above, but here the problem is not the missing
    // real window — it is that Qt attaches the extensionContainer of these
    // extensions only if the QML parent is "adopted" inside
    // initialize(), and it is not guaranteed to happen before something else
    // checks it. We create them dynamically ONLY when comp.created is
    // already true, and set extensionContainer by hand through
    // attachAndInitialize() (our own method, see VoltaViewporter.h and
    // VoltaPresentation.h) before initializing them — no more race on
    // when the automatic adoption kicks in.
    //
    // PresentationTime (wp_presentation): nei round56-58 avevamo provato
    // to hook Qt's INTERNAL class (QWaylandPresentationTime) and
    // abandoned because in this Qt installation it has no public
    // header (only qwaylandpresentationtime_p.h, private — not
    // subclassable by external code). VoltaPresentation.h no longer
    // depends on that class: it implements the protocol from scratch starting from
    // the official XML spec (see that file and
    // CMakeLists.txt), so it can be registered like any
    // other QML_NAMED_ELEMENT of ours, exactly like Viewporter.
    property var _viewporter: null
    property var _presentation: null
    // round72: the last two protocols required by gamescope (read its
    // real source code — see VoltaRelativePointer.h/
    // VoltaPointerConstraints.h for the reason). Exactly the same logic of
    // late creation + attachAndInitialize() as the two extensions above.
    property var _relativePointer: null
    property var _pointerConstraints: null

    // Single function called both by onCreatedChanged (normal case:
    // "created" becomes true AFTER this handler is already connected) and
    // by Component.onCompleted (safety net: if "created" were already
    // true at the moment the handler connects, onCreatedChanged would
    // never fire because there is no real "change" to observe).
    // The guards on _viewporter/_presentation make the double call
    // innocua.
    function attachLateExtensions() {
        if (!comp.created) return
        if (!_viewporter) {
            _viewporter = viewporterComponent.createObject(comp)
            _viewporter.attachAndInitialize(comp)
            console.log("[Compositor] Viewporter (wp_viewporter) attaccato")
        }
        if (!_presentation) {
            _presentation = presentationComponent.createObject(comp)
            _presentation.attachAndInitialize(comp)
            console.log("[Compositor] PresentationTime (wp_presentation) attaccato")
        }
        if (!_relativePointer) {
            _relativePointer = relativePointerComponent.createObject(comp)
            _relativePointer.attachAndInitialize(comp)
            console.log("[Compositor] RelativePointerManager (zwp_relative_pointer_manager_v1) attaccato")
        }
        if (!_pointerConstraints) {
            _pointerConstraints = pointerConstraintsComponent.createObject(comp)
            _pointerConstraints.attachAndInitialize(comp)
            console.log("[Compositor] PointerConstraints (zwp_pointer_constraints_v1) attaccato")
        }
    }

    onCreatedChanged: attachLateExtensions()
    Component.onCompleted: attachLateExtensions()

    Component {
        id: viewporterComponent
        Viewporter { }
    }

    Component {
        id: presentationComponent
        PresentationTime { }
    }

    Component {
        id: relativePointerComponent
        RelativePointerManager { }
    }

    Component {
        id: pointerConstraintsComponent
        PointerConstraints { }
    }

    // wp_presentation requires notifying the pending feedbacks
    // when a frame has REALLY been drawn on screen — the only place
    // where we know it for sure is the real output window
    // (outputWindow, set by Main.qml), not the compositor itself.
    // frameSwapped is a normal Qt signal of QQuickWindow, so it is
    // reachable from QML with a simple Connections (no additional
    // C++ is needed just for this hookup).
    property int _fpsCount: 0
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: { if (debugMode) console.log("[FPS]", comp._fpsCount); comp._fpsCount = 0 }
    }

    Connections {
        target: comp.outputWindow
        function onFrameSwapped() {
            comp._fpsCount++
            if (comp._presentation) comp._presentation.notifyFramePresented()
        }
    }

    // superficie + toplevel + shellSurface(XdgSurface) + appId normalizzato
    signal surfaceReady(var surface, var toplevel, var shellSurface, string appId)
    signal surfaceClosed(string appId)

    // Asks the clients (Chromium/Electron) to use SERVER-side decorations:
    // this way Spotify does NOT draw its light-blue titlebar (CSD). We draw
    // no decoration → clean full-panel window.
    XdgDecorationManagerV1 {
        preferredMode: XdgToplevel.ServerSideDecoration
    }

    XdgShell {
        onToplevelCreated: function(toplevel, xdgSurface) {
            console.log("[Compositor] Nuovo toplevel XDG in arrivo")
            var surf = xdgSurface.surface

            // round61: initial xdg-shell handshake MISSING until now — the
            // protocol expects the compositor to send a configure
            // (size+states) RIGHT after the toplevel is created, before
            // the client makes its first commit. Until now we sent it
            // only later, from NativeAppView (sendResize), when the user
            // opened the panel — "tolerant" clients (GTK/Chromium/SDL2)
            // are content anyway, which is why Chrome/Spotify/Android
            // Auto have always worked. DXVK (Cuphead and the other
            // Bottles/Wine games) is not: it creates its Vulkan swapchain on the wl_surface
            // RIGHT AWAY, before even being attached to a NativeAppView, and
            // without a valid geometry vkGetPhysicalDeviceSurfaceCapabilitiesKHR
            // fails with VK_ERROR_SURFACE_LOST_KHR in a loop for the whole
            // game session (confirmed: it shows up down in the log right after
            // "Nuovo toplevel XDG in arrivo", even BEFORE "Superficie
            // pronta"). By sending the initial configure here (real output
            // size, maximized+activated states — same
            // convention as NativeAppView) the Vulkan client starts with
            // a valid surface; the "real" resize toward the
            // panel area arrives anyway shortly after from NativeAppView, when the
            // UI attaches it.
            if (typeof toplevel.sendConfigure === "function") {
                var initW = comp.outputWindow ? comp.outputWindow.width  : 1920
                var initH = comp.outputWindow ? comp.outputWindow.height : 1080
                toplevel.sendConfigure(Qt.size(initW, initH), [1, 4])
            }

            function normalize(rawId, rawTitle) {
                var id = (rawId || "").toLowerCase()
                var title = (rawTitle || "").toLowerCase()

                // IMPORTANT: check "spotify" BEFORE "chrome" — the app_id of
                // Chrome in kiosk mode on open.spotify.com contains BOTH
                // strings (e.g. "chrome-open.spotify.com__-default"), so the check order
                // decides which bucket the surface is assigned to.
                if (id.indexOf("spotify") >= 0) return "spotify-native"
                if (id.indexOf("chrome") >= 0 || id.indexOf("chromium") >= 0) return "chrome"
                if (id.indexOf("calendar") >= 0) return "calendar"
                if (id.indexOf("totem") >= 0 || id.indexOf("showtime") >= 0
                    || id.indexOf("gnome.videos") >= 0) return "gnome-video"
                // FastCarPlay (Android Auto/CarPlay via dongle Carlinkit): l'app_id
                // that SDL2 sets on Wayland is not guaranteed/predictable, so
                // we recognize it from the window TITLE, which we know for sure
                // to be "Fast Car Play vX.X".
                if (title.indexOf("car play") >= 0) return "androidauto"
                // Bottles/Wine games, round58-65 (NATIVE Wayland clients of
                // wayland-volta, --env=WAYLAND_DISPLAY forced by the launch
                // command): their app_id was the name of the Windows
                // executable (e.g. "cuphead.exe", "wineboot.exe" during the
                // prefix boot). Abandoned because of a QtWaylandCompositor
                // bug on subsurfaces (see
                // NativeAppView.qml) — kept for compatibility, in case
                // it is needed again someday.
                if (id.indexOf(".exe") >= 0) return "game"
                // round67: gamescope (see native_game_gamescope_launch.sh
                // and launchNativeGame() in Arcade.qml) hosts Wine inside
                // itself and exposes to OUR compositor a single
                // surface with ITS app_id, "gamescope" — not the name
                // of the game's .exe, which stays hidden inside gamescope.
                // A generic "game" bucket is fine anyway: Arcade launches one
                // game at a time, there is no need to tell which.
                if (id.indexOf("gamescope") >= 0) return "game"
                // round72: dedicated Xwayland bridge (round68/68c/71, see
                // native_game_xwayland_launch.sh e launchNativeGame() in
                // Arcade.qml). Xwayland connects to OUR compositor
                // as A SINGLE Wayland client, exposing its whole virtual X11
                // "desktop" as a single surface with
                // app_id "org.freedesktop.Xwayland" e titolo "Xwayland on
                // :NN" — not the name of the game's .exe, which stays inside
                // that surface. Without this check the surface
                // ended up in the "org.freedesktop.xwayland" bucket (no
                // panel listens to it) and the game, although connected to our
                // compositor, was never shown by Arcade:
                // risultato, sembrava "esterno". Bucket generico "game"
                // is fine here for the same reason as the gamescope case
                // above: Arcade launches one game at a time.
                if (id.indexOf("xwayland") >= 0 || title.indexOf("xwayland") >= 0) return "game"
                return id || "unknown"
            }

            // Waydroid (and others) set the app_id AFTER showing content:
            // if we classify only at hasContent we take it empty → "unknown" and
            // the panel never captures the surface. So we re-classify
            // also when the app_id arrives/changes.
            var lastAppId = null
            function emitReady() {
                if (!surf.hasContent) return
                var appId = normalize(toplevel.appId, toplevel.title)
                if (appId === lastAppId) return
                if (lastAppId !== null) comp.surfaceClosed(lastAppId)  // the classification has changed
                lastAppId = appId
                console.log("[Compositor] Superficie pronta:", appId, "(appId grezzo:", toplevel.appId, "titolo:", toplevel.title, ")")
                comp.surfaceReady(surf, toplevel, xdgSurface, appId)
            }

            surf.onHasContentChanged.connect(function() {
                if (surf.hasContent) emitReady()
            })

            toplevel.onAppIdChanged.connect(function() {
                console.log("[Compositor] app_id aggiornato →", toplevel.appId)
                emitReady()
            })

            toplevel.onTitleChanged.connect(function() {
                console.log("[Compositor] titolo aggiornato →", toplevel.title)
                emitReady()
            })

            surf.onSurfaceDestroyed.connect(function() {
                var appId = (lastAppId !== null) ? lastAppId : normalize(toplevel.appId)
                console.log("[Compositor] Superficie chiusa:", appId)
                comp.surfaceClosed(appId)
            })
        }

        // Popups (menus, dropdowns, Spotify's "three dots") are rendered
        // as child items thanks to autoCreatePopupItems in NativeAppView.
        onPopupCreated: function(popup, xdgSurface) {
            console.log("[Compositor] Popup XDG creato (menu/dropdown)")
        }
    }

    // ── NOTE: XWayland is not available in this Qt build, so
    // external apps like FastCarPlay (Android Auto/CarPlay) are launched
    // as WAYLAND clients of THIS compositor (WAYLAND_DISPLAY=wayland-volta)
    // instead of being embedded via X11 — see Theater.qml.
}