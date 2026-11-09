import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import QtCore as Core

Item {
    id: dock

    property string activeApp:    ""
    property bool   showGrid:     false
    property bool   rhd:          false   // right-hand drive: car icon on the right, volume on the left
    property bool   carActive:    false
    property bool   carFullScreen: false
    property int    volume:       50
    // Size of the app icons in the dock (px). Can also be changed
    // with normalizza_icone.py --dock N
    // Measures from the wireframe (1 wireframe px = 72/54 internal dock units):
    property real   iconSize:     28 * 72 / 54   // icons 25 x 25 wireframe px (before 23)
    readonly property real iconPitch:   56.17 * 72 / 54   // icon pitch: 56.17 wireframe px (gap between icons ~33)
    // dock 57.8 wireframe px high (reference 2256x1504): icon center at 30.5 wireframe px from the bottom edge
    readonly property real iconCenterY: dock.height - 30.5 * 72 / 54

    // Complete catalog of the apps (id/name/icon), to resolve the icon of
    // any "custom" or "recent" app. To be connected
    // from Main.qml, e.g.: DockBar { appCatalog: appDrawer.qtApps }
    property var appCatalog: []

    signal carShortPress()
    signal carLongPress()
    signal appSelected(string appId)
    signal volumeUp()
    signal volumeDown()
    signal volumeSet(int value)
    signal showVolumeSlider()

    // ═══ EV-STYLE DOCK LIMIT: 7 icons in all (my apps + recents +
    // the drawer icon). The "recents" automatically occupy all the
    // slots that the custom "my apps" leave free. ═══
    readonly property int totalSlots: 7
    // "My apps" (customizable) have a FIXED cap of 4, independent of
    // the total slots — not "all the free space up to the drawer" as
    // before. The "recents" instead keep dynamically occupying everything
    // that remains free up to totalSlots (drawer included).
    readonly property int maxPinnedApps: 4

    // ═══ CUSTOMIZABLE ICONS ("My apps", before the drawer) ═══
    // Persisted as a CSV string of ids. They are added ONLY by dragging them
    // from the drawer (never the other way around): the only way to remove them from here is the
    // X in edit mode.
    Core.Settings {
        id: dockPrefs
        category: "ui"
        property string pinnedApps: "maps,phone,radio,spotify"
    }
    // apps no longer present (saved in the preferences of earlier versions): they are ignored
    readonly property var _removedApps: ["assistant", "tv", "manual"]
    readonly property var pinnedAppIds: dockPrefs.pinnedApps.length
        ? dockPrefs.pinnedApps.split(",").filter(function (s) { return s.length > 0 && dock._removedApps.indexOf(s) < 0 }).slice(0, dock.maxPinnedApps)
        : []

    function pinApp(appId) {
        if (!appId) return
        var arr = dock.pinnedAppIds.slice()
        if (arr.indexOf(appId) >= 0) return
        if (arr.length >= dock.maxPinnedApps) return // full: a specific icon must be replaced, not added
        arr.push(appId)
        dockPrefs.pinnedApps = arr.join(",")
    }
    function unpinApp(appId) {
        var arr = dock.pinnedAppIds.filter(function (s) { return s !== appId })
        dockPrefs.pinnedApps = arr.join(",")
    }
    // Swaps two customizable icons (edit mode)
    function swapPinned(idA, idB) {
        if (!idA || !idB || idA === idB) return
        var arr = dock.pinnedAppIds.slice()
        var a = arr.indexOf(idA), b = arr.indexOf(idB)
        if (a < 0 || b < 0) return
        arr[a] = idB; arr[b] = idA
        dockPrefs.pinnedApps = arr.join(",")
    }

    function replacePinned(oldId, newId) {
        if (!oldId || !newId || oldId === newId) return
        var arr = dock.pinnedAppIds.slice()
        var idx = arr.indexOf(oldId)
        if (idx < 0) return
        arr = arr.filter(function (s) { return s !== newId }) // niente duplicati
        idx = arr.indexOf(oldId)
        arr[idx] = newId
        dockPrefs.pinnedApps = arr.join(",")
    }

    // ═══ USAGE HISTORY → RECENT ICONS (after the drawer) ═══
    // The history (up to 12 distinct apps, persisted) is longer than
    // what is shown: the visible "recents" are derived from here,
    // limited to the slots that remain free after the custom apps. This way,
    // if you remove a pinned app, another recent one appears right away in its
    // place, taken from the history — without needing to reopen it.
    Core.Settings {
        id: historyPrefs
        category: "ui"
        property string usageHistory: ""
    }
    readonly property var usageHistoryIds: historyPrefs.usageHistory.length
        ? historyPrefs.usageHistory.split(",").filter(function (s) { return s.length > 0 })
        : []

    function recordOpened(appId) {
        if (!appId || appId === "grid") return
        var hist = dock.usageHistoryIds.filter(function (s) { return s !== appId })
        hist.unshift(appId)
        if (hist.length > 12) hist = hist.slice(0, 12)
        historyPrefs.usageHistory = hist.join(",")
    }

    readonly property int recentSlots: Math.max(0, (dock.totalSlots - 1) - dock.pinnedAppIds.length)
    readonly property var recentAppIds: {
        var out = []
        for (var i = 0; i < dock.usageHistoryIds.length && out.length < dock.recentSlots; i++) {
            var id = dock.usageHistoryIds[i]
            if (dock.pinnedAppIds.indexOf(id) < 0 && dock._removedApps.indexOf(id) < 0) out.push(id)
        }
        return out
    }

    // Icons known even if not present in the drawer catalog (e.g. "maps",
    // which is the default background app and does not appear in the drawer itself).
    readonly property var _builtinIcons: ({
        "maps": "qrc:/VoltaApp/icons/nav.svg"
    })
    function iconFor(appId) {
        if (dock._builtinIcons[appId]) return dock._builtinIcons[appId]
        for (var i = 0; i < dock.appCatalog.length; i++) {
            if (dock.appCatalog[i].id === appId) return dock.appCatalog[i].icon
        }
        return "qrc:/VoltaApp/icons/" + appId + ".svg"
    }

    // ═══ EDIT MODE — persistent, not tied to dragging ═══
    // It is activated by dragging an icon from the drawer over the dock, and STAYS
    // active (labels, rows, removal X) until you tap on
    // any other point of the interface — not only during the gesture.
    property bool editMode: false
    property string _dragHoverId: ""

    // ── APIs called by Main.qml, connected to the drawer's dragMoved/dragFinished signals
    // (coordinates in the window root's space) ──
    function _hitTestIcon(row, localX, localY) {
        for (var i = 0; i < row.children.length; i++) {
            var item = row.children[i]
            if (item.appId === undefined) continue
            var topLeft = item.mapToItem(dock, 0, 0)
            if (localX >= topLeft.x && localX <= topLeft.x + item.width &&
                localY >= topLeft.y && localY <= topLeft.y + item.height) {
                return item.appId
            }
        }
        return ""
    }
    function _toLocal(globalX, globalY) {
        var winRoot = dock.Window.window ? dock.Window.window.contentItem : dock
        return winRoot.mapToItem(dock, globalX, globalY)
    }
    function updateDragHover(appId, globalX, globalY) {
        var local = dock._toLocal(globalX, globalY)
        var overDock = local.x >= 0 && local.x <= dock.width && local.y >= -50 && local.y <= dock.height
        dock.editMode = dock.editMode || overDock
        dock._dragHoverId = overDock ? dock._hitTestIcon(pinnedRow, local.x, local.y) : ""
    }
    function handleExternalDrop(appId, globalX, globalY) {
        var local = dock._toLocal(globalX, globalY)
        var overDock = local.x >= 0 && local.x <= dock.width && local.y >= -50 && local.y <= dock.height
        dock._dragHoverId = ""
        if (!overDock) return

        // If the release happens exactly over an already present
        // customizable icon, that one is ALWAYS replaced — full or not, exactly
        // as on EVs. Only if released in an empty space of the dock
        // (not over an icon) is it added at the end, and only if there is still room.
        var targetId = dock._hitTestIcon(pinnedRow, local.x, local.y)
        if (targetId) {
            dock.replacePinned(targetId, appId)
        } else if (dock.pinnedAppIds.length < dock.maxPinnedApps) {
            dock.pinApp(appId)
        }
        dock.editMode = true
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: event.accepted = true
    }

    // NOTE: the scrim that closes edit mode by tapping elsewhere in the
    // UI lives in Main.qml (exactly the same pattern as "drawerScrim", which is
    // the mechanism already proven in the app for this purpose — a MouseArea
    // nested in here inside DockBar did not intercept touches over the open/native
    // apps, so closing only worked over the dock).

    // Increased (26 → 38) to give more room between the top edge of the
    // raised dock and the "MY APPS"/"RECENT APPS" labels (before they were
    // almost stuck to the edge).
    readonly property int editGrowth: 38

    Rectangle {
        id: dockBg
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: dock.editMode ? parent.height + dock.editGrowth : parent.height
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        color: "#000000"
        Rectangle {
            anchors.top: parent.top; width: parent.width; height: 1
            color: "#0DFFFFFF"
        }
    }

    // Anti-touch wall: the whole dock absorbs touches, so the map (or app) underneath never moves.
    // It sits UNDER the icons (declared before them), which keep receiving their own touches.
    MouseArea {
        id: dockWall
        anchors.fill: dockBg
        preventStealing: true
        acceptedButtons: Qt.AllButtons
    }


    // ── LEFT: Car button ──────────────────────────────────────────────────────
    Item {
        id: leftSection
        readonly property real edgeM: 28 * 72 / 54 - (46 - 27 * 72 / 54) / 2
        x: dock.rhd ? parent.width - width - edgeM : edgeM
        anchors.bottom: parent.bottom; anchors.bottomMargin: dock.height - dock.iconCenterY - 23
        width: 46; height: 46

        Image { sourceSize: Qt.size(width * 2, height * 2);
            anchors.centerIn: parent
            source: "qrc:/VoltaApp/icons/car.svg"

            width: dock.iconSize; height: dock.iconSize   // dl73: like the other dock icons
            fillMode: Image.PreserveAspectFit
            opacity: 1.0
        }

        MouseArea {
            id: carArea
            anchors.fill: parent
            property real pressTime: 0
            onPressed:  pressTime = Date.now()
            onReleased: dock.carShortPress()
        }
    }

    // ── CENTER: pinned apps · drawer · divider · recent apps ───────────────────
    Row {
        id: centerRow
        // Right-hand drive: mirrored order (recents on the left, drawer, favorites on the right), also inside the groups.
        // The drag to swap uses the icons' real coordinates, so it works the same.
        LayoutMirroring.enabled: dock.rhd
        LayoutMirroring.childrenInherit: true
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: dock.height - dock.iconCenterY - 26
        spacing: dock.iconPitch - 52

        // ── Customizable apps (dragged from the drawer) ──
        Row {
            id: pinnedRow
            spacing: dock.iconPitch - 52
            Repeater {
                model: dock.pinnedAppIds
                delegate: dockIconDelegate
            }
        }

        // ── App drawer (grid) — fixed, not customizable ──
        Item {
            id: drawerBtn
            width: 52; height: 52
            LayoutMirroring.enabled: false     // the drawer icon (2x2 grid) must not be mirrored
            LayoutMirroring.childrenInherit: true

            Rectangle {
                anchors.centerIn: parent
                width: dock.iconSize * 0.88; height: dock.iconSize * 0.88   // like the Bluetooth icon's square
                radius: dock.iconSize * 0.129
                color: "#2A2A2A"
                border.color: "#40FFFFFF"
                border.width: 1.5

                Grid {
                    anchors.centerIn: parent
                    columns: 2
                    rowSpacing: 3
                    columnSpacing: 3

                    Image { sourceSize: Qt.size(width * 2, height * 2); source: "qrc:/VoltaApp/icons/nav.svg";      width: dock.iconSize * 0.312; height: dock.iconSize * 0.312; fillMode: Image.PreserveAspectFit; smooth: true }
                    Image { sourceSize: Qt.size(width * 2, height * 2); source: "qrc:/VoltaApp/icons/radio.svg";    width: dock.iconSize * 0.312; height: dock.iconSize * 0.312; fillMode: Image.PreserveAspectFit; smooth: true }
                    Image { sourceSize: Qt.size(width * 2, height * 2); source: "qrc:/VoltaApp/icons/phone.svg";    width: dock.iconSize * 0.312; height: dock.iconSize * 0.312; fillMode: Image.PreserveAspectFit; smooth: true }
                    Image { sourceSize: Qt.size(width * 2, height * 2); source: "qrc:/VoltaApp/icons/ytmusic.svg";  width: dock.iconSize * 0.312; height: dock.iconSize * 0.312; fillMode: Image.PreserveAspectFit; smooth: true }
                }
            }

            Rectangle {
                visible: dock.showGrid
                width: 22; height: 2; radius: 1
                color: "#B3E0E0E0"
                anchors.horizontalCenter: parent.horizontalCenter
                // resting on the bottom edge of the screen (bottom edge of the dock)
                anchors.bottom: parent.bottom; anchors.bottomMargin: -(dock.height - dock.iconCenterY - 26)
            }

            MouseArea {
                anchors.fill: parent
                onClicked: dock.appSelected("grid")
                onPressedChanged: parent.opacity = pressed ? 0.6 : 1.0
            }
        }

        // (the drawer/recents separator dash is drawn outside the Row, further below,
        //  so as not to alter the uniform pitch of the icons)

        // ── Recent apps (dynamic, derived from the history) ──
        Row {
            id: recentRow
            spacing: dock.iconPitch - 52
            Repeater {
                model: dock.recentAppIds
                delegate: dockIconDelegate
            }
        }
    }

    // Drawer/recents separator dash, without taking up space in the Row
    Rectangle {
        width: 1; height: 18; radius: 0.5
        color: "#26FFFFFF"
        visible: dock.recentAppIds.length > 0
        x: dock.rhd ? centerRow.x + drawerBtn.x - (dock.iconPitch - 52) / 2 - 0.5
                    : centerRow.x + drawerBtn.x + drawerBtn.width + (dock.iconPitch - 52) / 2 - 0.5
        y: dock.iconCenterY - height / 2
    }

    // Shared delegate for customizable and recent icons.
    Component {
        id: dockIconDelegate

        Item {
            id: iconItem
            width: 52; height: 52

            readonly property string appId: modelData
            readonly property bool pinned: dock.pinnedAppIds.indexOf(appId) >= 0
            property bool isActive: dock.activeApp === appId
            readonly property bool hovered: dock.editMode && dock._dragHoverId === appId

            // No more square/background behind the icon when "hovered"
            // during a drag — only icons, always with a transparent
            // background. The hover indication now goes through a
            // slight opacity on the icon itself (see Image below).

            Image {
                id: dockIconImg
                anchors.centerIn: parent
                source: dock.iconFor(iconItem.appId)
                width: dock.iconSize; height: dock.iconSize
                sourceSize: Qt.size(dock.iconSize * 3, dock.iconSize * 3)   // sharp even for SVGs without width/height
                fillMode: Image.PreserveAspectFit
                smooth: true
                z: swapArea.dragging ? 10 : 0
                opacity: swapArea.dragging ? 1.0 : (iconItem.hovered ? 0.75 : ((iconItem.pinned && dock.editMode) ? 0.5 : 1.0))
                // Follows the finger while it is dragged to swap it
                transform: Translate { id: dragShift; x: 0; y: 0 }
                scale: swapArea.dragging ? 1.25 : 1.0
                Behavior on scale { NumberAnimation { duration: 120 } }
            }

            Rectangle {
                visible: iconItem.isActive && !dock.editMode
                width: 22; height: 2; radius: 1
                color: "#B3E0E0E0"
                anchors.horizontalCenter: parent.horizontalCenter
                // resting on the bottom edge of the screen (bottom edge of the dock)
                anchors.bottom: parent.bottom; anchors.bottomMargin: -(dock.height - dock.iconCenterY - 26)
            }

            MouseArea {
                // "visible" as well as "enabled": in edit mode this
                // area must NEVER be able to open an app — before,
                // "enabled: false" was enough in theory, but for safety (and to
                // leave the touch free for the X above, without stacking
                // ambiguity) we remove it altogether from the touch candidates.
                z: 0
                visible: !dock.editMode
                anchors.fill: parent
                enabled: !dock.editMode
                onClicked: {
                    // local references: appSelected can rebuild the dock and destroy
                    // this icon before recordOpened runs
                    var d = dock, id = iconItem.appId
                    d.appSelected(id)
                    d.recordOpened(id)
                }
                // Holding down any icon enters edit mode
                pressAndHoldInterval: 600
                onPressAndHold: dock.editMode = true
                onPressedChanged: parent.opacity = pressed ? 0.6 : 1.0
            }

            // Edit mode: drag a customizable icon over
            // another to swap their places (recents do not move)
            MouseArea {
                id: swapArea
                z: 1
                visible: iconItem.pinned && dock.editMode
                anchors.fill: parent
                preventStealing: true
                property bool dragging: false
                property real sx: 0
                property real sy: 0
                onPressed: (m) => { sx = m.x; sy = m.y; dragging = false }
                onPositionChanged: (m) => {
                    if (!pressed) return
                    if (!dragging && Math.abs(m.x - sx) + Math.abs(m.y - sy) > 8) dragging = true
                    if (dragging) {
                        dragShift.x = m.x - sx
                        dragShift.y = m.y - sy
                        var p = swapArea.mapToItem(dock, m.x, m.y)
                        var over = dock._hitTestIcon(pinnedRow, p.x, p.y)
                        dock._dragHoverId = over !== iconItem.appId ? over : ""
                    }
                }
                function finish(m) {
                    if (dragging && m) {
                        var p = swapArea.mapToItem(dock, m.x, m.y)
                        var target = dock._hitTestIcon(pinnedRow, p.x, p.y)
                        if (target && target !== iconItem.appId) dock.swapPinned(iconItem.appId, target)
                    }
                    dragging = false
                    dragShift.x = 0; dragShift.y = 0
                    dock._dragHoverId = ""
                }
                onReleased: (m) => finish(m)
                onCanceled: finish(null)
            }

            // Removal X — only on customizable icons, only in
            // edit mode. No background, above the icon's head.
            // The touchable area is now ONLY that of the X itself (with a
            // bit of margin for the touch), no longer the whole icon: tapping
            // the icon must not remove it, only tapping the X.
            MouseArea {
                z: 5
                visible: iconItem.pinned && dock.editMode
                width: 30; height: 30
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: -22
                onClicked: dock.unpinApp(iconItem.appId)

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "white"
                    font.pixelSize: 15
                    font.bold: true
                }
            }
        }
    }

    // ═══ "MY APPS" / "RECENT APPS" LABELS with continuous line ═══
    // They live in the area where the dock itself "rises" (dockBg above),
    // not in a separate panel. "RECENT APPS" stays visible even
    // with no recent apps at the moment (position valid anyway).
    Item {
        id: customizeContent
        visible: dock.editMode
        opacity: dock.editMode ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 6
        width: centerRow.width
        height: 18

        // ── "MY APPS" above the customizable icons ──
        Column {
            spacing: 4
            x: pinnedRow.x + pinnedRow.width / 2 - width / 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("MY APPS")
                color: "#B3FFFFFF"
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 0.5
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(30, pinnedRow.width); height: 1
                color: "#40FFFFFF"
            }
        }

        // ── "RECENT APPS" above the dynamic icons (or where they will appear) ──
        Column {
            spacing: 4
            x: recentRow.x + Math.max(recentRow.width, 30) / 2 - width / 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("RECENT APPS")
                color: "#B3FFFFFF"
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 0.5
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(30, recentRow.width); height: 1
                color: "#40FFFFFF"
            }
        }
    }

    // ── RIGHT: Volume ─────────────────────────────────────────────────────────
    // ── RIGHT: Volume (measures from the wireframe: icon 18 px, right margin 200 px) ──
    Item {
        id: volRow
        x: dock.rhd ? 0 : parent.width - width       // right-hand drive: the volume goes to the left
        anchors.bottom: parent.bottom
        width: 360; height: dock.height
        readonly property real unit: 72 / 54    // internal units per 1 wireframe px
        // Proportions from the volume SVG (Frame_269, 144 x 43): 1 SVG px = 1070/1920 wireframe
        // px = q internal units. Speaker 48 x 43; arrows 8 x 13 with centers at
        // 55.54 px to the left and 56.46 px to the right of the speaker's center.
        readonly property real q: unit * 1070 / 1920
        readonly property real spkCx: dock.rhd ? 209 * unit : width - 209 * unit      // speaker center (at 209 wireframe px from the outer edge)

        // ‹ left arrow (center at 249 wireframe px from the right edge)
        Rectangle {
            width: 56; height: 36; radius: 8; color: "transparent"
            x: volRow.spkCx - 55.542 * volRow.q - width / 2
            y: dock.iconCenterY - height / 2
            Image {
                anchors.centerIn: parent
                source: "qrc:/VoltaApp/icons/vol-left.svg"
                width: 8 * volRow.q; height: 13 * volRow.q      // 8 x 13 px SVG
                sourceSize: Qt.size(width * dock.scale, height * dock.scale)   // sharp even with the dock scaled
            }
            MouseArea {
                anchors.fill: parent
                anchors.topMargin: -18; anchors.bottomMargin: -18   // touch area as tall as the dock
                onClicked: dock.volumeDown()     // also shows the volume banner
                onPressedChanged: parent.color = pressed ? "#1AFFFFFF" : "transparent"
            }
        }

        // speaker (center at 209 wireframe px from the right edge: icon's right margin = 200 px)
        Item {
            z: 10
            width: 40; height: 40
            x: volRow.spkCx - width / 2
            y: dock.iconCenterY - height / 2
            // Altoparlante vettoriale (forme dallo SVG vol-speaker.svg, 48 x 43):
            // mute (volume 0) = cross in place of the waves; otherwise the lit
            // waves are 1 (low), 2 (medium) or 3 (high), the others stay dim.
            Item {
                id: spk
                anchors.centerIn: parent
                width: 48 * volRow.q; height: 43 * volRow.q
                readonly property int level: dock.volume <= 0 ? 0 : (dock.volume <= 33 ? 1 : (dock.volume <= 66 ? 2 : 3))
                Shape {
                    width: 48; height: 43
                    scale: spk.width / 48; transformOrigin: Item.TopLeft
                    preferredRendererType: Shape.CurveRenderer
                    // corpo
                    ShapePath {
                        fillColor: "#D0D1D2"; strokeColor: "transparent"; strokeWidth: 0
                        PathSvg { path: "M7 26.84H2a2 2 0 0 1-2-2v-7.555a2 2 0 0 1 2-2h5l7.683-6.725C15.976 7.43 18 8.347 18 10.065V32.06c0 1.719-2.024 2.637-3.317 1.505z" }
                    }
                    // onda 1
                    ShapePath {
                        fillColor: spk.level === 0 ? "transparent" : (spk.level >= 1 ? "#D0D1D2" : "#4DD0D1D2"); strokeColor: "transparent"; strokeWidth: 0
                        Behavior on fillColor { ColorAnimation { duration: 160 } }
                        PathSvg { path: "M22.182 13.357c.292-.335.83-.394 1.203-.132C26.193 15.196 28 18.269 28 21.72c0 3.258-1.61 6.179-4.154 8.154a.926.926 0 0 1-1.209-.079c-.31-.321-.27-.807.088-1.086 2.182-1.694 3.56-4.197 3.56-6.99 0-2.957-1.546-5.59-3.956-7.281-.373-.262-.439-.746-.147-1.08z" }
                    }
                    // onda 2
                    ShapePath {
                        fillColor: spk.level === 0 ? "transparent" : (spk.level >= 2 ? "#D0D1D2" : "#4DD0D1D2"); strokeColor: "transparent"; strokeWidth: 0
                        Behavior on fillColor { ColorAnimation { duration: 160 } }
                        PathSvg { path: "M29.3 6.347a1 1 0 0 1 1.414.015A21.93 21.93 0 0 1 37 21.759a22.34 22.34 0 0 1-5.762 14.843 1 1 0 0 1-1.476-1.35c3.312-3.598 5.258-8.23 5.238-13.494 0-5.45-2.178-10.388-5.714-13.997a1 1 0 0 1 .014-1.414z" }
                    }
                    // wave 3 (in the SVG it is faded and dimmer: lit = original gradient, off = almost invisible)
                    ShapePath {
                        strokeColor: "transparent"; strokeWidth: 0
                        fillGradient: LinearGradient {
                            x1: 47; y1: 0; x2: 36; y2: 0
                            GradientStop { position: 0.0; color: spk.level === 0 ? "transparent" : (spk.level >= 3 ? "#66FFFFFF" : "#18FFFFFF") }
                            GradientStop { position: 1.0; color: "#00FFFFFF" }
                        }
                        PathSvg { path: "M37.592.312A1 1 0 0 1 39.004.4a32.3 32.3 0 0 1 7.995 21.162 32.3 32.3 0 0 1-7.226 20.256 1 1 0 0 1-1.547-1.267c4.284-5.214 6.79-11.726 6.773-18.99.019-7.667-2.774-14.508-7.495-19.838a1 1 0 0 1 .088-1.411z" }
                    }
                    // cross (mute) in place of the waves
                    ShapePath {
                        fillColor: "transparent"; strokeColor: spk.level === 0 ? "#D0D1D2" : "transparent"; strokeWidth: 3.2
                        capStyle: ShapePath.RoundCap
                        PathSvg { path: "M22.3 14.5L36.3 28.5M36.3 14.5L22.3 28.5" }
                    }
                }
            }
            // Speaker: tap = mute / unmute; swipe right / left = raise / lower the volume.
            // The finger can leave the icon: the touch stays with this area (anti-touch wall, the map does not move).
            // If after the swipe the finger stays still, the volume keeps changing in the same direction until you lift it.
            MouseArea {
                id: spkArea
                anchors.centerIn: parent
                // swipe zone: up to ~440 wide (it narrows if the app icons come close) and as tall as the whole dock
                readonly property real leftSpace: (dock.width - 209 * 72 / 54) - (centerRow.x + centerRow.width) - 10
                width: Math.max(180, Math.min(440, 2 * leftSpace)); height: Math.max(70, 2 * dock.iconCenterY)
                preventStealing: true
                property real pressX: 0
                property real lastX: 0
                property real accum: 0
                property int  dir: 0
                property bool swiped: false
                readonly property real pxPerStep: 14        // one step (5%) every 14 px of swipe
                function step(d) { if (d > 0) dock.volumeUp(); else if (d < 0) dock.volumeDown() }
                onPressed: function(m) { pressX = m.x; lastX = m.x; accum = 0; dir = 0; swiped = false; holdWait.stop(); holdRep.stop() }
                onPositionChanged: function(m) {
                    if (!pressed) return
                    var dx = m.x - lastX; lastX = m.x
                    if (Math.abs(m.x - pressX) > 8) swiped = true
                    if (!swiped) return
                    if (dx !== 0) dir = dx > 0 ? 1 : -1
                    accum += dx
                    while (accum >= pxPerStep)  { accum -= pxPerStep; step(1) }
                    while (accum <= -pxPerStep) { accum += pxPerStep; step(-1) }
                    holdRep.stop(); holdWait.restart()
                }
                onReleased: { holdWait.stop(); holdRep.stop() }
                onCanceled: { holdWait.stop(); holdRep.stop() }
                onClicked: function(m) {
                    if (swiped) return
                    var dx = m.x - width / 2         // distance from the speaker's center
                    if (Math.abs(dx) <= 24) dock.showVolumeSlider()          // altoparlante: muto / riattiva
                    else if (dx < 0 && dx > -80) dock.volumeDown()           // where the left arrow is
                    else if (dx > 0 && dx < 80) dock.volumeUp()              // where the right arrow is
                }
                Timer { id: holdWait; interval: 450; onTriggered: if (spkArea.pressed && spkArea.dir !== 0) holdRep.start() }
                Timer { id: holdRep; interval: 110; repeat: true; onTriggered: spkArea.step(spkArea.dir) }
            }
        }

        // › right arrow (center at 159 wireframe px from the right edge)
        Rectangle {
            width: 56; height: 36; radius: 8; color: "transparent"
            x: volRow.spkCx + 56.458 * volRow.q - width / 2
            y: dock.iconCenterY - height / 2
            Image {
                anchors.centerIn: parent
                source: "qrc:/VoltaApp/icons/vol-right.svg"
                width: 8 * volRow.q; height: 13 * volRow.q
                sourceSize: Qt.size(width * dock.scale, height * dock.scale)
            }
            MouseArea {
                anchors.fill: parent
                anchors.topMargin: -18; anchors.bottomMargin: -18   // touch area as tall as the dock
                onClicked: dock.volumeUp()       // also shows the volume banner
                onPressedChanged: parent.color = pressed ? "#1AFFFFFF" : "transparent"
            }
        }
    }

    Rectangle {
        id: volSlider
        visible: false
        z: 2000
        width: 170; height: 38; radius: 19
        color: "#171717"
        border.color: "#414141"; border.width: 1
        x: volRow.x + volRow.spkCx + 53 * volRow.unit - width    // same position relative to the speaker, from either side
        anchors.bottom: parent.top; anchors.bottomMargin: 6

        Rectangle {
            id: sliderTrack
            anchors.centerIn: parent
            width: parent.width - 24; height: 4; radius: 2
            color: "#414141"

            Rectangle {
                width: sliderTrack.width * (dock.volume / 100)
                height: parent.height; radius: 2; color: "white"
                anchors.left: parent.left
            }

            Rectangle {
                width: 14; height: 14; radius: 7; color: "white"
                anchors.verticalCenter: parent.verticalCenter
                x: sliderTrack.width * (dock.volume / 100) - 7
                layer.enabled: true; layer.smooth: true
            }
        }

        MouseArea {
            x: (parent.width - sliderTrack.width) / 2
            y: (parent.height - 20) / 2
            width: sliderTrack.width
            height: 20
            function vol(mx) {
                return Math.round(Math.max(0, Math.min(1, mx / sliderTrack.width)) * 100)
            }
            onPositionChanged: if (pressed) {
                var v = vol(mouseX)
                dock.volumeSet(v)
                sliderHide.restart()
            }
            onClicked: {
                dock.volumeSet(vol(mouseX))
                sliderHide.restart()
            }
        }

        Timer {
            id: sliderHide
            interval: 3000; repeat: false
            onTriggered: volSlider.visible = false
        }
    }
}
