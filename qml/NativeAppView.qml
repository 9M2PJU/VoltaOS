import QtQuick
import QtWayland.Compositor

// Renders a native app (XDG toplevel) + its popups/menus.
// Passes the shellSurface (XdgSurface) instead of the surface alone: so
// ShellSurfaceItem with autoCreatePopupItams handles the menus by itself
// (e.g. Spotify's three dots) without crashing the compositor.
Item {
    id: root

    property var shellSurface:     null   // XdgSurface (QWaylandShellSurface)
    property var waylandToplevel:  null
    property string appLabel: qsTr("App")

    // Some clients (e.g. FastCarPlay/SDL2 on Wayland) ignore the compositor's
    // resize requests when the window has a fixed
    // size — known behavior documented by the SDL2 developers
    // themselves. Their buffer stays at the native resolution whatever space we
    // reserve for it, and without this "clip" flag it CROPS it instead of scaling it.
    // By default it stays false: all the other apps (Chrome/GTK) already respect
    // the resize correctly and do not need it.
    property bool scaleToFit: false

    // The gauge (Width/Height/Right-Left/Up-Down) found for the reduced panel must NOT
    // apply in full screen, where the content must fill
    // all the space without corrections.
    property bool isFullscreen: false

    // true: uses Qt's default subsurface handler (right position/size,
    // for Chrome: bubble, toast); false: the full-area one designed for games
    property bool useDefaultSubsurfaces: false

    // Waydroid does not implement sendConfigure and redraws on every configure →
    // no resize jiggle for it, otherwise it flickers forever.
    readonly property bool isWaydroid: false

    // ── Anti "giant flash" veil (browser only, useDefaultSubsurfaces) ─────────
    // On opening the client shows for a moment the last buffer, of a size
    // different from the area, stretched to the full area. Until its surface's
    // size matches (±8 px, stable 60 ms) the requested one, or for
    // at most 1 s, we cover it with a veil; then it fades away.
    property color coverColor: "#171717"
    property bool _covered: false
    readonly property size _srfSize: shellItem.surface ? shellItem.surface.size : Qt.size(0, 0)
    readonly property bool _sizeMatches: !!shellItem.surface
        && Math.abs(_srfSize.width  - root.width)  <= 8
        && Math.abs(_srfSize.height - root.height) <= 8
    on_SizeMatchesChanged: {
        if (!_covered) return
        if (_sizeMatches) revealSoon.restart(); else revealSoon.stop()
    }
    function _armReveal() {
        if (!root.useDefaultSubsurfaces) return
        _covered = true
        revealTimeout.restart()
        if (_sizeMatches) revealSoon.restart(); else revealSoon.stop()
    }
    Timer {
        id: revealSoon
        interval: 60
        onTriggered: {
            if (!root._covered) return
            root._covered = false
            revealTimeout.stop()
            console.log("[NativeAppView] browser: contenuto a misura, scopro")
        }
    }
    Timer {
        id: revealTimeout
        interval: 1000
        onTriggered: {
            if (!root._covered) return
            root._covered = false
            console.log("[NativeAppView] browser: timeout, scopro comunque. superficie",
                        root._srfSize.width, "x", root._srfSize.height, "area", root.width, "x", root.height)
        }
    }

    // Every time the app is SHOWN (opening), it resends the final
    // size: the panel has just finished animating, so a "forced"
    // re-configure is needed or the client stays at the wrong resolution
    // until you click inside it.
    onVisibleChanged: {
        if (visible && shellSurface) {
            root._armReveal()
            if (root.isWaydroid) {
                // Waydroid redraws on every configure → no jiggle (cause of flicker):
                // we send it ONE clean resize at the final size.
                Qt.callLater(shellItem.sendResize)
            } else {
                settleTimer.shots = 0
                settleTimer.restart()
            }
        }
    }

    // ── Placeholder / spinner until the shellSurface is ready ─────────────
    Rectangle {
        anchors.fill: parent
        color: "#171717"
        visible: root.shellSurface === null

        Item {
            anchors.centerIn: parent
            width: 64; height: 80
            Spinner {
                id: spinnerCanvas
                size: 64
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                running: root.shellSurface === null
            }
            Text {
                anchors.top: spinnerCanvas.bottom; anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.appLabel; color: "#555"; font.pixelSize: 12
            }
        }
    }

    // ── ShellSurfaceItem: handles toplevel + popups (menus) as children ─────────
    Item {
        id: clipWrap
        anchors.fill: parent
        clip: true

        // Calibration found by hand for the REDUCED (65%) panel — see
        // conversation: Width 1.00, Height 0.95, Right/Left 0.00, Up/Down -20.00.
        // It does NOT apply to full screen: there the content must fill
        // all the space without corrections (root.isFullscreen true → 1/1/0/0).
        // Calibration removed: it compensated for the old dock margin
        // (when the content ended up under the dock). With the right margin in
        // AppPanel (bottomInset) it only left an empty gray band at the bottom.
        readonly property real calibScaleX: 1.0
        readonly property real calibScaleY: 1.0
        readonly property real calibOffX:   0
        readonly property real calibOffY:   0

        ShellSurfaceItem {
            id: shellItem
            anchors.fill: parent
            // Two transformations in sequence (does not conflict with anchors.fill,
            // unlike direct width/height — same lesson learned
            // from the handle pill's bounce bug). Scale for
            // size, Translate for position.
            transform: [
                Scale {
                    origin.x: shellItem.width / 2; origin.y: shellItem.height / 2
                    xScale: clipWrap.calibScaleX
                    yScale: clipWrap.calibScaleY
                },
                Translate {
                    x: clipWrap.calibOffX
                    y: clipWrap.calibOffY
                }
            ]

            // Avoids assigning "undefined", which crashes the QML engine
            shellSurface: root.shellSurface ? root.shellSurface : null
            visible: root.shellSurface !== null

            // I popup (menu tre pallini, dropdown...) diventano item figli
            // handled and positioned automatically by the compositor.
            autoCreatePopupItems: true

            // round62: the Bottles/Wine games (both DXVK/Vulkan and
            // WineD3D/OpenGL — confirmed with both) do NOT draw their
            // output on the main xdg_toplevel surface, but on
            // a separate child wl_subsurface (confirmed in the log:
            // "QWaylandSurfacePrivate::Subsurface::subsurface_set_desync").
            // Qt's AUTOMATIC subsurface handler (the one that
            // fires by default, same family as autoCreatePopupItems
            // above but for subsurfaces) in this case continuously generates
            // "QQuickItem::stackBefore: Cannot stack X before X, which must
            // be a sibling" — an item asked to place itself before
            // ITSELF, with the same address on both
            // sides of the warning: a Qt bug in the internal reordering
            // of subsurfaces, not something caused by our QML
            // hierarchy. Result: the subsurface is created and sized
            // giusta (confermato: hasContent true, size reale tipo
            // 1242x899) but never reaches the screen — audio yes, video no.
            // We replace the (buggy) automatic handler with a minimal
            // one of our own: we create the item for the subsurface ourselves, without any
            // above/below reordering (we only need it to sit above the
            // content — empty in this case — of the main
            // surface; there is no need to handle multiple subsurfaces in
            // mutual order for a single game).
            //
            // round82: round62 created an item for every subsurface but NEVER
            // destroyed it — this NativeAppView is static (it lives inside
            // gameOverlay in Main.qml) and is reused by ALL the games, one
            // after the other. Result: closing a game and opening
            // another, the old subsurface's item (with its last frame
            // frozen, z:10000) stayed forever a child of shellItem, and
            // the new game's one piled up above/below — exactly
            // the symptom "the old game's frame stays and does not budge
            // from there". Now we keep a list of the ones created, to be able to
            // destroy them all when the shellSurface changes (see
            // onShellSurfaceChanged below) — only one game at a time
            // lives in this item, so every shellSurface change
            // automatically makes ALL the subsurfaces created so far obsolete.
            subsurfaceHandler: root.useDefaultSubsurfaces ? null : _customSubHandler
            QtObject {
                id: _customSubHandler
                property var createdItems: []
                // round84: the shellSurface "observed" the last time
                // we really did cleanup — it serves onShellSurfaceChanged
                // below to tell whether it is a REAL change (new game/no
                // game) or just yet another re-evaluation of the binding with the
                // SAME object (root.nativeShells is RECREATED with
                // Object.assign in Main.qml at EVERY surface ready/closed
                // of ANY app, not just the game — so the binding
                // "shellSurface: root.shellSurface ? root.shellSurface : null"
                // can re-run more often than the
                // value really changes). Without this guard we risk calling
                // destroyAll() even while the game is already drawing,
                // deleting the item that shows the current video.
                property var lastCleanedSurface: undefined
                function handleSubsurfaceAdded(child) {
                    // round89: before adding, we only throw away the "dead"
                    // items (whose Wayland surface no longer exists:
                    // previous game closed) — never the live ones.
                    var alive = []
                    for (var k = 0; k < createdItems.length; k++) {
                        var o = createdItems[k]
                        if (!o) continue
                        if (!o.surface) { o.destroy(); continue }
                        alive.push(o)
                    }
                    createdItems = alive
                    var it = subsurfaceItemComponent.createObject(shellItem, { "surface": child })
                    createdItems.push(it)
                    console.log("[NativeAppView] subsurface added, total now:", createdItems.length)
                }
                function destroyAll() {
                    console.log("[NativeAppView] destroyAll: distruggo", createdItems.length, "subsurface-item")
                    for (var i = 0; i < createdItems.length; i++) {
                        if (createdItems[i]) createdItems[i].destroy()
                    }
                    createdItems = []
                }
            }

            smooth: true
            antialiasing: true
            focusOnClick: true
            inputEventsEnabled: true

            onVisibleChanged: {
                if (visible && shellSurface) {
                    shellItem.forceActiveFocus();
                    shellItem.takeFocus();
                }
            }

            property int lastW: 0
            property int lastH: 0
            // For Waydroid the reflow of the Android UI was handled by `wm size` (from
            // AppPanel) — it was used by Android's native mechanism. Waydroid was
            // removed, but the guard stays harmless for the other clients.
            onWidthChanged:  resizeDebounce.restart()
            onHeightChanged: resizeDebounce.restart()
            onShellSurfaceChanged: {
                // round82: we throw away the subsurface-items of the
                // PREVIOUS shellSurface (see subsurfaceHandler above) — but ONLY if it
                // really changed compared to the last time we
                // cleaned (round84: guard against spurious re-evaluations of the
                // binding — see comment on lastCleanedSurface above —
                // otherwise we risk deleting the item that is
                // drawing the game NOW, while it is still the right one).
                // round89: CAUSE OF THE BLACK SCREEN FOUND IN THE LOG. gamescope's
                // subsurfaces (where the video is) are created BEFORE
                // this handler runs, during the assignment of the new
                // shellSurface (undefined -> surface): the old code
                // considered them "of the previous game" and destroyed them
                // immediately (log: "added 1..7" and then "destroyAll: destroying
                // 7"). Now we clean ONLY when the shellSurface disappears
                // (game closed, null value); the direct A->B change is
                // covered by the cleanup of dead items in
                // handleSubsurfaceAdded.
                if (!shellSurface)
                    _customSubHandler.destroyAll();

                if (shellSurface) {
                    Qt.callLater(sendResize);
                    if (!root.isWaydroid) {
                        settleTimer.shots = 0;
                        settleTimer.restart();
                    }
                }
            }

            // xdg_toplevel states: 1=maximized, 4=activated. Maximized makes
            // GTK/Chromium apps really fill the assigned area (no window
            // piccola scalata e sgranata).
            readonly property var cfgStates: [1, 4]

            // normal configure, with dedup: used during the continuous animation.
            // NOTA: manda sempre root.width/height (l'area RICHIESTA/riservata),
            // not shellItem.width/height (which with scaleToFit becomes the
            // native size) — we still want to ask the client to
            // adapt, even though we know some (SDL2) will ignore it.
            function sendResize() {
                if (!root.waylandToplevel || typeof root.waylandToplevel.sendConfigure !== "function") return;
                var w = Math.floor(root.width);
                var h = Math.floor(root.height);
                if (w < 10 || h < 10 || (w === lastW && h === lastH)) return;
                lastW = w;
                lastH = h;
                root.waylandToplevel.sendConfigure(Qt.size(w, h), cfgStates);
            }

            // FORCED configure with "jiggle": sends a slightly
            // different size and right after the correct one. It forces Chromium/GTK to redo
            // the layout at the final size without having to click inside the app.
            function forceResize() {
                if (!root.waylandToplevel || typeof root.waylandToplevel.sendConfigure !== "function") return;
                var w = Math.floor(root.width);
                var h = Math.floor(root.height);
                if (w < 10 || h < 10) return;
                root.waylandToplevel.sendConfigure(Qt.size(w - 2, h), cfgStates);
                Qt.callLater(function() {
                    if (root.waylandToplevel && typeof root.waylandToplevel.sendConfigure === "function")
                        root.waylandToplevel.sendConfigure(Qt.size(w, h), cfgStates);
                });
                lastW = w;
                lastH = h;
            }
        }

        // round62: item for the subsurface created by hand by
        // subsurfaceHandler (see above) — a simple fill above the
        // (empty) content of the main surface. No handling of
        // position/reordering: one game at a time, a single
        // subsurface, sempre a tutta area.
        //
        // round63: the warning "stackBefore: Cannot stack X before X" does not
        // block anything by itself (stackBefore simply fails, returns without
        // doing anything) — so it is probably NOT what hides the
        // video. More concrete hypothesis: with a custom subsurfaceHandler
        // like ours, Qt no longer has under control WHICH item
        // represents the subsurface (that internal tracking only exists for
        // the automatic handling, the one we replaced) — when
        // the client asks "put me above/below" (place_above/place_below,
        // that is why the warning repeats 3-5 times, one request
        // at a time), Qt tries to reorder something anyway and fails
        // on its own internal item (hence the "double" address in the
        // warning: it is not a coincidence, it is the one catching the request
        // meant for our subsurface). If in the meantime a
        // second item exists — the one Qt still thinks it has to handle,
        // empty/without content — it might end up ABOVE ours by
        // pure child order, hiding it. We therefore force our
        // item always on top with a very high explicit z: it does not solve
        // the cause (it stays an internal Qt bug), but removes any
        // possible ordering interference, ours or Qt's.
        // round65: different lead, found by looking OUTSIDE Qt — two known
        // and documented bugs of winewayland.drv (the Wayland driver INSIDE
        // Wine, not our compositor): GloriousEggroll/proton-ge-custom
        // issue #786 e ValveSoftware/Proton issue #10151. Entrambi
        // describe THE SAME symptom with compositors other than ours
        // (Hyprland, wlroots): "WAYLAND_CreateClientSurface() NEVER calls
        // wl_surface_set_opaque_region on the client subsurface" — the one
        // where the game really draws. On Windows the alpha channel of
        // normal ("non-layered") windows is ignored by DWM, so
        // games leave it at 0/garbage without it mattering — but an "honest"
        // Wayland compositor like ours, seeing a buffer in a
        // format with alpha and NO declared opaque region, does normal
        // alpha-blending: risultato, trasparenza totale. Contenuto presente
        // and correctly sized (consistent with what we see in the logs) but
        // invisible — exactly "audio yes, video no". We cannot
        // patch Wine from here, but we can do on OUR side what
        // Hyprland's "force_rgbx" does (cited in those same threads as a
        // compositor-side workaround): force Qt to completely ignore the
        // alpha channel of this surface, rendering it on an internal
        // texture WITHOUT alpha (RGB) instead of RGBA — the result is
        // always "opaque", whatever garbage is in the real alpha
        // channel. z stays high for the round63 reasons (harmless, it does not
        // male lasciarlo).
        Component {
            id: subsurfaceItemComponent
            WaylandQuickItem {
                anchors.fill: parent
                smooth: true
                antialiasing: true
                z: 10000
                layer.enabled: true
                layer.format: ShaderEffectSource.RGB
            }
        }
    }

    // Veil (see _armReveal): above the surface, which stays visible and therefore
    // continua a ricevere i frame callback.
    Rectangle {
        anchors.fill: parent
        color: root.coverColor
        opacity: root._covered ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }

    // Gives the physical keyboard focus back to the app window
    function refocus() {
        if (shellSurface && shellItem.visible) {
            shellItem.forceActiveFocus();
            shellItem.takeFocus();
        }
    }

    Timer {
        id: resizeDebounce
        interval: 16
        repeat: false
        onTriggered: shellItem.sendResize()
    }

    // After opening, it fires some forced configures while the layout
    // assesta (l'animazione dura ~480ms). Copre fino a ~1.2s.
    Timer {
        id: settleTimer
        property int shots: 0
        interval: 300
        repeat: true
        onTriggered: {
            shellItem.forceResize();
            shots++;
            if (shots >= 4) { stop(); shots = 0; }
        }
    }

    onWaylandToplevelChanged: {
        if (waylandToplevel) {
            Qt.callLater(shellItem.sendResize);
        }
    }

    onShellSurfaceChanged: {
        if (shellSurface) root._armReveal()
        if (shellSurface && shellItem.visible) {
            Qt.callLater(function() {
                shellItem.forceActiveFocus();
                shellItem.takeFocus();
            });
        }
    }
}
