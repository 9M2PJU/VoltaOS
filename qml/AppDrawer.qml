import QtQuick
import QtQuick.Window
import QtCore as Core
import QtQuick.Effects
import VoltaApp 1.0

Rectangle {
    property bool lightTheme: false
    id: drawer
    // Icons equal to the dock's (23 wireframe px); everything else in the drawer
    // (width, margins, cells) scales accordingly compared to the old 34 px.
    readonly property real u: (Window.window && Window.window.uPx) ? Window.window.uPx : 1.12
    readonly property real f: iconSize / 34
    height: contentCol.height + 36 * f
    color: "transparent"
    radius: 10
    border.width: 0

    // Solid black background (no blur: it avoided icon flicker)
    Rectangle {
        anchors.fill: parent
        radius: 10
        color: "#F2000000"
        z: -1
    }

    signal appSelected(string appId)
    signal editRequested()

    // Small "Edit" button above the panel (like the EV "Customize")
    Rectangle {
        id: editPill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 10
        width: editTxt.implicitWidth + 28; height: 26
        radius: 4
        color: editMA.pressed ? "#CC333333" : "#CC000000"
        visible: !drawer.editModeActive
        Text {
            id: editTxt
            anchors.centerIn: parent
            text: qsTr("Edit")
            color: Theme.textSecondary
            font.pixelSize: 12
            font.weight: Font.Medium
        }
        MouseArea { id: editMA; anchors.fill: parent; anchors.margins: -6; onClicked: drawer.editRequested() }
    }

    // Size of the icons in the drawer (px). Can also be changed with
    // normalizza_icone.py --drawer N
    property real iconSize: 25 * u

    // When the dock is in edit mode, tapping an icon here in the
    // drawer must not open the app (the user is customizing the dock,
    // not launching apps) — connected by Main.qml to dockBar.editMode.
    property bool editModeActive: false

    // ═══ DRAGGING toward the dock — GLOBAL coordinates (in the space
    // of the window root), no Qt Drag/DropArea: that
    // mechanism proved unreliable here (native OS drag,
    // z-order between "sibling" components). Whoever listens to these signals (the
    // dock, via Main.qml) does the geometric test on the received point by itself.
    signal dragMoved(string appId, real globalX, real globalY)
    signal dragFinished(string appId, real globalX, real globalY)

    // "Pure" signal (no coordinates/drop logic): it only serves to tell
    // Main.qml "a drag is in progress" / "it is over", so as to be able to
    // temporarily disable the map/app panel input — which
    // otherwise, if the cursor passes over them, can interfere with the
    // mouse grab of this drag (see note in AppPanel.qml).
    signal dragActiveChanged(bool active)

    // "app" = app native Qt, "android" = app Android (Waydroid)
    property string category: "app"

    // ── Calendar icon with the current day ──────────────────────
    property date _calNow: new Date()
    Timer {
        interval: 60000; running: true; repeat: true
        onTriggered: { var n = new Date(); if (n.getDate() !== drawer._calNow.getDate()) drawer._calNow = n }
    }
    function _calSvg(n) {
        return '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="1.886 1.886 60.227 60.227">' + '<defs><linearGradient id="a" x1="32" y1="6" x2="32" y2="58" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#D0D0D0"/></linearGradient>' + '<linearGradient id="b" x1="32" y1="6" x2="32" y2="16" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#E53935"/><stop offset="1" stop-color="#C62828"/></linearGradient>' + '<clipPath id="c"><rect x="6" y="6" width="52" height="52" rx="5"/></clipPath></defs>' + '<rect x="6" y="6" width="52" height="52" rx="5" fill="url(#a)" stroke="#A0A0A0" stroke-width="1"/>' + '<rect x="6" y="6" width="52" height="10" fill="url(#b)" clip-path="url(#c)"/>' + '<text x="32" y="44" font-family="Arial, Helvetica, sans-serif" font-size="28" font-weight="900" fill="#1A1A1A" text-anchor="middle">' + n + '</text></svg>'
    }
    readonly property string calIcon: "data:image/svg+xml;utf8," + encodeURIComponent(drawer._calSvg(drawer._calNow.getDate()))

    property var qtApps: [
        { id: "theater",          name: "Theater",      icon: "qrc:/VoltaApp/icons/video.svg"       },
        { id: "androidauto",      name: "CarPlay / Android Auto", icon: "qrc:/VoltaApp/icons/androidauto.svg" },
        { id: "arcade",           name: "Arcade",       icon: "qrc:/VoltaApp/icons/arcade.svg"      },
        { id: "radio",            name: "Radio",        icon: "qrc:/VoltaApp/icons/radio.svg"       },
        { id: "browser",          name: "Browser",      icon: "qrc:/VoltaApp/icons/chrome.svg"      },
        { id: "messages",         name: qsTr("Messages"),     icon: "qrc:/VoltaApp/icons/messages.svg"    },
        { id: "spotify",          name: "YT Music",     icon: "qrc:/VoltaApp/icons/ytmusic.svg"     },
        { id: "spotifyapp",       name: "Spotify",      icon: "qrc:/VoltaApp/icons/spotify.svg"     },
        { id: "localmusic",       name: qsTr("Music"),      icon: "qrc:/VoltaApp/icons/localmusic.svg"       },
        { id: "podcast",          name: "Podcasts",      icon: "qrc:/VoltaApp/icons/podcast.svg"     },
        { id: "calendar",         name: qsTr("Calendar"),   icon: drawer.calIcon    },
        { id: "settings",         name: "Settings",     icon: "qrc:/VoltaApp/icons/settings.svg", drawerHidden: true },
        { id: "phone",            name: qsTr("Phone"),     icon: "qrc:/VoltaApp/icons/phone.svg"       },
        { id: "toybox",           name: "Toybox",       icon: "qrc:/VoltaApp/icons/toybox.svg"      },
        { id: "camera",           name: "Camera",       icon: "qrc:/VoltaApp/icons/camera.svg"      },
        { id: "bluetooth",        name: "Bluetooth",    icon: "qrc:/VoltaApp/icons/bluetooth.svg"   },
    ]

    property var androidApps: []

    // Ids of the apps hidden from the Settings ("Apps"), separated by
    // comma — e.g. "arcade,browser". Bound to uiPrefs.hiddenApps by
    // Main.qml, so it updates live as soon as a toggle is changed.
    property string hiddenApps: ""

    // List currently shown, based on the selected category and
    // filtered on the hidden apps. "settings" is never filtered: it is the
    // only way to come back here and re-enable the others.
    // Custom order of the icons (dragging an icon onto another
    // in the drawer swaps them). Apps not yet in the list
    // salvato (es. appena aggiunte) finiscono in fondo.
    Core.Settings {
        id: drawerPrefs
        category: "ui"
        property string drawerOrder: ""
    }
    readonly property var _order: drawerPrefs.drawerOrder.length ? drawerPrefs.drawerOrder.split(",") : []

    function _sorted(list) {
        var ord = drawer._order
        if (ord.length === 0) return list
        return list.slice().sort(function(a, b) {
            var ia = ord.indexOf(a.id), ib = ord.indexOf(b.id)
            if (ia < 0) ia = 1000 + list.indexOf(a)
            if (ib < 0) ib = 1000 + list.indexOf(b)
            return ia - ib
        })
    }

    function swapApps(idA, idB) {
        if (!idA || !idB || idA === idB) return
        var ids = drawer._sorted(drawer.qtApps).map(function(a) { return a.id })
        var a = ids.indexOf(idA), b = ids.indexOf(idB)
        if (a < 0 || b < 0) return
        ids[a] = idB; ids[b] = idA
        drawerPrefs.drawerOrder = ids.join(",")
    }

    // Drawer icon under a point (window coordinates), "" if none
    function appAt(globalX, globalY) {
        var winRoot = drawer.Window.window ? drawer.Window.window.contentItem : drawer
        var p = winRoot.mapToItem(appGrid, globalX, globalY)
        for (var i = 0; i < appGrid.children.length; i++) {
            var c = appGrid.children[i]
            if (c.cellAppId === undefined) continue
            if (p.x >= c.x && p.x <= c.x + c.width && p.y >= c.y && p.y <= c.y + c.height) return c.cellAppId
        }
        return ""
    }

    readonly property var apps: {
        var list = drawer._sorted(category === "android" ? androidApps : qtApps)
                         .filter(function(a) { return !a.drawerHidden })
        if (hiddenApps.length === 0) return list
        var hidden = hiddenApps.split(",")
        return list.filter(function(a) { return a.id === "settings" || hidden.indexOf(a.id) === -1 })
    }

    // If the drag stays "hanging" (e.g. the drawer closes halfway through the
    // gesture because an app opened in the meantime), the state must never
    // stay stuck: as soon as the drawer disappears, everything resets.
    onOpacityChanged: if (drawer.opacity === 0) drawer._resetDrag()
    function _resetDrag() {
        dragGhost.visible = false
        dragGhost.parent = drawer
        drawer.dragActiveChanged(false)
    }

    // Just the bare icon, without any background/box behind it. Reparented
    // to the window root during the drag so that it ALWAYS draws
    // above everything (drawer, dock, etc.), regardless of the
    // z-order between components.
    Image {
        id: dragGhost
        parent: drawer
        visible: false
        z: 99999
        width: drawer.iconSize; height: drawer.iconSize
        sourceSize: Qt.size(drawer.iconSize * 3, drawer.iconSize * 3)
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    // Background that absorbs touches: tapping an empty space of the drawer does not close it
    MouseArea { anchors.fill: parent }

    Column {
        id: contentCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18 * drawer.f
        spacing: 12 * drawer.f

        // (Category selector removed: with only one category available
        // it no longer made sense — drawer.category stays "app" by default.)

        // ── WEB APPS (added from the Browser): at the top, separated by a line ──
        Item {
            id: webGrid
            visible: WebApps.list.length > 0
            width: parent.width
            readonly property int count: WebApps.list.length
            readonly property int rows: Math.max(1, Math.ceil(count / appGrid.columns))
            height: visible ? rows * appGrid.cellH + (rows - 1) * appGrid.rowSpacing : 0
            Repeater {
                model: WebApps.list
                Column {
                    spacing: 5 * drawer.u
                    width: appGrid.cellW
                    readonly property int _row: Math.floor(index / appGrid.columns)
                    readonly property int _col: index % appGrid.columns
                    readonly property int _inRow: (_row === webGrid.rows - 1 && webGrid.count % appGrid.columns !== 0)
                                                  ? webGrid.count % appGrid.columns : appGrid.columns
                    x: _col * (appGrid.cellW + appGrid.columnSpacing)
                       + (appGrid.columns - _inRow) * (appGrid.cellW + appGrid.columnSpacing) / 2
                    y: _row * (appGrid.cellH + appGrid.rowSpacing)
                    Item {
                        width: parent.width; height: appGrid.iconBoxH
                        // site icon as it is (PNG, no box behind)
                        Image {
                            id: wIconBg
                            anchors.centerIn: parent
                            width: drawer.iconSize * 0.96; height: width
                            source: modelData.icon
                            sourceSize: Qt.size(drawer.iconSize * 3, drawer.iconSize * 3)
                            fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; asynchronous: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: if (!drawer.editModeActive) drawer.appSelected("web:" + modelData.id)
                        }
                        // edit mode: light circle with a thin "x" to remove the web app
                        Rectangle {
                            visible: drawer.editModeActive
                            x: wIconBg.x - width / 3; y: wIconBg.y - height / 3
                            width: 15 * drawer.u; height: width; radius: width / 2
                            color: _delMA.pressed ? "#8E8E93" : "#AEAEB2"
                            Repeater {
                                model: [45, -45]
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width * 0.46; height: Math.max(1.5, 1.5 * drawer.u); radius: height / 2
                                    color: "#FFFFFF"; rotation: modelData; antialiasing: true
                                }
                            }
                            MouseArea { id: _delMA; anchors.fill: parent; anchors.margins: -8; onClicked: WebApps.remove(modelData.id) }
                        }
                    }
                    Text {
                        text: modelData.name
                        color: Theme.textSecondary
                        font.pixelSize: 10 * drawer.u; font.weight: Font.Medium
                        elide: Text.ElideRight
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
        Rectangle {
            visible: webGrid.visible
            width: parent.width; height: 1
            color: Theme.border
        }

        // EV-style grid: 6 columns, last row centered.
        Item {
            id: appGrid
            width: parent.width
            readonly property int columns: 6
            readonly property real columnSpacing: 8 * drawer.f
            readonly property real rowSpacing: 14 * drawer.f
            readonly property real cellW: (width - columnSpacing * (columns - 1)) / columns
            readonly property real cellH: iconBoxH + 5 * drawer.u + 14 * drawer.u
            readonly property real iconBoxH: drawer.iconSize * 1.4
            readonly property int count: drawer.apps.length
            readonly property int rows: Math.max(1, Math.ceil(count / columns))
            height: rows * cellH + (rows - 1) * rowSpacing

            Repeater {
                model: drawer.apps

                Column {
                    id: cellRoot
                    readonly property string cellAppId: modelData.id
                    spacing: 5 * drawer.u
                    width: appGrid.cellW
                    readonly property int _row: Math.floor(index / appGrid.columns)
                    readonly property int _col: index % appGrid.columns
                    readonly property int _inRow: (_row === appGrid.rows - 1 && appGrid.count % appGrid.columns !== 0)
                                                  ? appGrid.count % appGrid.columns : appGrid.columns
                    x: _col * (appGrid.cellW + appGrid.columnSpacing)
                       + (appGrid.columns - _inRow) * (appGrid.cellW + appGrid.columnSpacing) / 2
                    y: _row * (appGrid.cellH + appGrid.rowSpacing)

                    Rectangle {
                        id: iconBox
                        width: parent.width; height: appGrid.iconBoxH
                        radius: 10
                        color: "transparent"
                        border.width: 0
                        anchors.horizontalCenter: parent.horizontalCenter

                        Image {
                            id: iconImg
                            anchors.centerIn: parent
                            source: modelData.icon
                            width: drawer.iconSize; height: drawer.iconSize
                            sourceSize: Qt.size(drawer.iconSize * 3, drawer.iconSize * 3)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            // the touch area covers the whole cell (icon + name + surrounding space):
                            // so an "almost right" tap opens the app instead of closing the drawer
                            anchors.leftMargin: -appGrid.columnSpacing / 2
                            anchors.rightMargin: -appGrid.columnSpacing / 2
                            anchors.topMargin: -appGrid.rowSpacing / 2
                            anchors.bottomMargin: -(19 * drawer.u + appGrid.rowSpacing / 2)
                            // Do not give up the grab to other "old
                            // style" MouseAreas (e.g. Flickable) during the drag —
                            // additional defense, it does not by itself solve the theft
                            // of the grab by a PointerHandler such as
                            // DragHandler (for that see grabPermissions in
                            // AppPanel.qml + dragActiveChanged below).
                            preventStealing: true
                            property bool dragging: false
                            property real pressX: 0
                            property real pressY: 0

                            onPressed: (mouse) => {
                                // No more dark square behind the icon on
                                // press — only icons, background always
                                // transparent (iconBox.color stays "transparent").
                                dragArea.pressX = mouse.x
                                dragArea.pressY = mouse.y
                                dragArea.dragging = false
                            }

                            onPositionChanged: (mouse) => {
                                if (!dragArea.pressed) return
                                var dx = mouse.x - dragArea.pressX
                                var dy = mouse.y - dragArea.pressY

                                if (!dragArea.dragging && (Math.abs(dx) > 10 || Math.abs(dy) > 10)) {
                                    dragArea.dragging = true
                                    dragGhost.source = modelData.icon
                                    // Reparents to the window root: so
                                    // the ghost draws above the dock (which is a
                                    // "sibling" component, not a child
                                    // of the drawer) instead of staying under it.
                                    var winRoot = drawer.Window.window ? drawer.Window.window.contentItem : drawer
                                    dragGhost.parent = winRoot
                                    dragGhost.visible = true
                                    iconImg.opacity = 0.3
                                    drawer.dragActiveChanged(true)
                                }

                                if (dragArea.dragging) {
                                    var p = dragArea.mapToItem(dragGhost.parent, mouse.x, mouse.y)
                                    dragGhost.x = p.x - dragGhost.width / 2
                                    dragGhost.y = p.y - dragGhost.height / 2
                                    drawer.dragMoved(modelData.id, p.x, p.y)
                                }
                            }

                            onReleased: (mouse) => {
                                iconBox.color = "transparent"
                                iconImg.opacity = 1.0
                                if (dragArea.dragging) {
                                    var p = dragArea.mapToItem(dragGhost.parent, mouse.x, mouse.y)
                                    // Released over another drawer icon:
                                    // they swap places. Otherwise (e.g. over
                                    // the dock) the usual behavior stays.
                                    var over = drawer.appAt(p.x, p.y)
                                    if (over && over !== modelData.id) drawer.swapApps(modelData.id, over)
                                    else drawer.dragFinished(modelData.id, p.x, p.y)
                                    dragGhost.visible = false
                                    dragGhost.parent = drawer
                                    drawer.dragActiveChanged(false)
                                }
                                dragArea.dragging = false
                            }

                            // Qt Quick calls onCanceled when this MouseArea
                            // LOSES the exclusive mouse grab to
                            // someone else (e.g. a DragHandler elsewhere that
                            // "steals" the grab) — it is exactly the moment when
                            // the drag silently "broke" over the
                            // map/open apps. Now, besides cleaning the
                            // local state, we notify Main.qml that the drag
                            // is no longer active.
                            onCanceled: {
                                iconBox.color = "transparent"
                                iconImg.opacity = 1.0
                                dragGhost.visible = false
                                dragGhost.parent = drawer
                                dragArea.dragging = false
                                drawer.dragActiveChanged(false)
                            }

                            onClicked: {
                                if (!dragArea.dragging && !drawer.editModeActive) drawer.appSelected(modelData.id)
                            }
                        }
                    }

                    Text {
                        text: modelData.name
                        color: Theme.textSecondary
                        font.pixelSize: 10 * drawer.u
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }
}
