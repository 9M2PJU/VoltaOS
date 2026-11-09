import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import QtQuick3D

Item {
    property alias sceneMidLayer: car3DView.midLayer
    id: carPanel

    property bool   rhd:           false   // right-hand drive: panel on the right, handle on the left side (toward the map), mirrored tools
    property real   fullWidth:     parent ? parent.width : 600
    // Width of the 'reduced' panel in px (Main.qml sets it to 410)
    property real   reducedW:      fullWidth * 0.35
    property bool   lightTheme:    false
    readonly property bool _lt: lightTheme
    property bool lowPower: false
    // Needed to limit the pill's "owl" animation to only the apps
    // that really support the fullscreen drag gesture.
    property string activeApp:     ""

    property bool isFullyOpen: width >= (fullWidth - 5)

    // Exposed to allow resetting the 3D view from outside (Main.qml).
    property alias car3DView: car3DView

    signal car3DLoaded()
    signal dragStarted(real globalX)
    signal dragMoved(real globalX)
    signal dragEnded()

    property real panelProgress: {
        var minW = reducedW
        var range = fullWidth - minW
        if (range <= 0) return 0
        return Math.max(0, Math.min(1, (width - minW) / range))
    }

    property bool show3D: true

    Rectangle {
        id: mainRect
        anchors.fill: parent
        color:        carPanel._lt ? "#F0F0F0" : "#171717"
        border.color: carPanel._lt ? "#D0D1D2" : "#171717"
        border.width: 1

        clip: true

        // ════════ VISTA AUTO 3D NATIVA (Qt Quick 3D) ════════
        CarScene {
            id: car3DView

            // We fix the sizes and move the X, so as not to break the Framebuffer on resize
            width:  carPanel.fullWidth
            height: parent.height
            x: (parent.width - width) / 2
            y: 0

            // 0.35 (ridotto) → 1.0 (fullscreen)
            panelRatio: carPanel.fullWidth > 0
                        ? Math.max(carPanel.reducedW / carPanel.fullWidth, Math.min(1.0, carPanel.width / carPanel.fullWidth))
                        : 0.35
            lightTheme: carPanel._lt
            lowPower: carPanel.lowPower

            Component.onCompleted: carPanel.car3DLoaded()
        }

        // ════════ STRUMENTI SOVRAPPOSTI (KM/H E SEGNALI) ════════
        SpeedBar {
            id: speedBar
            opacity: car3DView.uiHidden ? 0 : 1; visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 220 } }
            x: carPanel.rhd ? parent.width - width - 8 : 8; y: 46; z: 10
            height: 190
            fillPct: 0 // To be connected to the real GPS if you want
        }

        SpeedCluster {
            id: speedCluster
            opacity: car3DView.uiHidden ? 0 : 1; visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 220 } }
            x: carPanel.rhd ? parent.width - width - 24 : 24; y: 12; z: 10
            lightTheme: carPanel._lt
            rhd:        carPanel.rhd
            gear:       "P"
            speedValue: "0"
            speedUnit:  "km/h"
            headlightOn: true
            seatbeltOn:  true
        }

        Rectangle {
            id: speedLimitSign
            z: 10
            opacity: car3DView.uiHidden ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 220 } }
            property bool reduced: mainRect.width < carPanel.fullWidth - 5
            // limit of the stretch you are driving (Mapbox, during navigation); without data the sign disappears
            visible: reduced && Nav.navigating && Nav.speedLimit > 0

            // European sign: circle, thick red border, white background,
            // just the number — no "SPEED LIMIT" text (this is not how
            // EU signs are made, unlike the US-style one
            // replaced here). Moved to the right as requested.
            width: 40; height: 40; radius: 20
            color: "#FFFFFF"
            border.color: "#D3232B"
            border.width: 5

            x: carPanel.rhd ? 18 : parent.width - width - 40   // next to the handle (in right-hand drive: closer to the edge)
            anchors.top: parent.top
            anchors.topMargin: 16

            Text {
                anchors.centerIn: parent
                text: Nav.speedLimit > 0 ? String(Nav.speedLimit) : ""
                color: "#111111"
                font.pixelSize: 17
                font.weight: Font.Bold
            }
        }

        // ════════ "APRI VANO POSTERIORE" + LUCCHETTO PORTIERE ════════
        // Positions as fractions of the panel: adjustable below (lockX/lockY, rearX/rearY, lineEndY).
        // Visible only with the car in normal view (reduced panel, not rotated).
        Item {
            id: callouts
            anchors.fill: parent
            z: 10
            readonly property real u: (Window.window && Window.window.uPx) ? Window.window.uPx : 1.12
            readonly property bool fullMode: carPanel.panelProgress > 0.5   // dl67: posizioni diverse in fullscreen
            readonly property bool hasCar: (car3DView.userCarActive && !car3DView.replacing)
            readonly property bool shown: callouts.hasCar && !car3DView.fsdMode && ((carPanel.panelProgress < 0.15 && Math.abs(car3DView.azimuthDeg - 7.9) < 12)
                                                                 || (carPanel.panelProgress > 0.85 && Math.abs(car3DView.azimuthDeg) < 12)) || (car3DView.moveButtons && callouts.hasCar)
            visible: opacity > 0.01
            opacity: shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            property real lockX: callouts.fullMode ? callouts.full_lockX : 0.50      // lock center (fraction of the width)
            property real lockY: (callouts.fullMode ? callouts.full_lockY : 0.27)      // centro lucchetto (frazione dell'altezza)
            property real rearX: callouts.fullMode ? callouts.full_rearX : 0.68      // left edge of the "Trunk" text = x of the line
            property real rearY: (callouts.fullMode ? callouts.full_rearY : 0.22)      // top of the text
            property real lockLineEndY: (callouts.fullMode ? callouts.full_lockLineEndY : 0.325)  // how far the line goes down below the lock
            property real lineEndY: (callouts.fullMode ? callouts.full_lineEndY : 0.345)   // how far the line goes down toward the rear of the car
            // dl67: positions in FULLSCREEN (fractions of the whole panel)
            property real full_lockX: 0.52   // dl68
            property real full_lockY: 0.17   // dl68
            property real full_lockLineEndY: 0.245   // dl68
            property real full_rearX: 0.67   // dl68
            property real full_rearY: 0.165   // dl68
            property real full_lineEndY: 0.30   // dl68
            // hood (front): same heights as the trunk, to the left of the car
            property real hoodX: callouts.fullMode ? 0.36 : 0.30
            // ── Button geometry ──
            // With a user car each button is attached to a point of the car (projected onto the screen): it follows the car
            // when the panel shrinks or grows. The line starts from the point and goes up by lineLen; the button sits on top.
            readonly property bool useAnch: car3DView.userCarActive
            property int tick: 0
            Timer { interval: 40; repeat: true; running: callouts.visible && callouts.useAnch; onTriggered: callouts.tick++ }
            readonly property real lineLen: 0.13 * callouts.height
            // {x: line position, top: top of the line (button), end: bottom of the line}
            function geo(key) {
                var _t = callouts.tick
                if (callouts.useAnch) {
                    var a = car3DView.anchorFor(key)
                    if (!a) return { x: -1000, top: 0, end: 0 }
                    var pt = car3DView.carPointToItem(a, callouts)
                    return { x: pt.x, top: pt.y - callouts.lineLen, end: pt.y }
                }
                if (key === "lock") return { x: callouts.lockX * callouts.width, top: callouts.lockY * callouts.height, end: callouts.lockLineEndY * callouts.height }
                if (key === "rear") return { x: callouts.rearX * callouts.width, top: callouts.rearY * callouts.height, end: callouts.lineEndY * callouts.height }
                return { x: callouts.hoodX * callouts.width, top: callouts.rearY * callouts.height, end: callouts.lineEndY * callouts.height }
            }
            readonly property var gLock: callouts.geo("lock")
            readonly property var gRear: callouts.geo("rear")
            readonly property var gHood: callouts.geo("hood")

            readonly property color inkMain: carPanel._lt ? "#414141" : "#D0D2D0"
            readonly property color lineCol: carPanel._lt ? "#6E6F71" : "#EDEEEF"
            readonly property color inkSoft: carPanel._lt ? "#8A8B8D" : "#8A8B8D"
            readonly property bool doorsOpen: car3DView.doorLeftOpen > 0.5 || car3DView.doorRightOpen > 0.5

            // ── Lock: closed = doors closed, open = doors open; a tap opens/closes them all ──
            Item {
                id: lockBtn
                readonly property real body: 14 * callouts.u          // larghezza corpo lucchetto
                width: 40 * callouts.u; height: 40 * callouts.u
                x: callouts.gLock.x - width / 2
                y: callouts.gLock.top - height / 2

                // chiuso (Vector.svg 20 x 28)
                Item {
                    anchors.centerIn: parent
                    width: 20 * (lockBtn.body / 20); height: 28 * (lockBtn.body / 20)
                    visible: !callouts.doorsOpen
                    Shape {
                        width: 20; height: 28
                        scale: lockBtn.body / 20; transformOrigin: Item.TopLeft
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: callouts.inkMain; strokeColor: "transparent"; strokeWidth: 0
                            fillRule: ShapePath.OddEvenFill
                            PathSvg { path: qsTr("M5 12h10V8A5 5 0 0 0 5 8zm13 0a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H2a2 2 0 0 1-2-2V14a2 2 0 0 1 2-2V8a8 8 0 1 1 16 0z") }
                        }
                    }
                }
                // aperto (lock.svg: bbox 14..33 x 14..33.286, corpo largo 14.284)
                Item {
                    anchors.centerIn: parent
                    width: 19 * (lockBtn.body / 14.284); height: 19.286 * (lockBtn.body / 14.284)
                    visible: callouts.doorsOpen
                    Shape {
                        width: 19; height: 19.286
                        scale: lockBtn.body / 14.284; transformOrigin: Item.TopLeft
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: callouts.inkMain; strokeColor: "transparent"; strokeWidth: 0
                            fillRule: ShapePath.OddEvenFill
                            PathSvg { path: "M10 7.857h7a2 2 0 0 1 2 2v7.429a2 2 0 0 1-2 2H6.716a2 2 0 0 1-2-2V9.857a2 2 0 0 1 2-2H8V5a3 3 0 0 0-6 0v5H0V5a5 5 0 0 1 10 0z" }
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !car3DView.moveButtons
                    onClicked: {
                        var v = callouts.doorsOpen ? 0 : 1
                        car3DView.doorLeftOpen = v
                        car3DView.doorRightOpen = v
                    }
                }
            }

            // ── Line + text "Open / Trunk" (tap = opens/closes the trunk) ──
            Column {
                id: rearTxt
                visible: callouts.hasCar && car3DView.hasTrunk
                x: callouts.gRear.x + 8 * callouts.u
                y: callouts.gRear.top
                spacing: 1 * callouts.u
                Text { text: (car3DView.trunkOpen > 0.5) ? qsTr("Close") : qsTr("Open"); color: callouts.inkSoft; font.pixelSize: 11 * callouts.u; font.weight: Font.Medium }
                Text { text: qsTr("Trunk"); color: carPanel._lt ? "#171717" : "#E0E0E0"; font.pixelSize: 11 * callouts.u; font.weight: Font.DemiBold }
            }
            MouseArea {
                x: rearTxt.x - 8 * callouts.u; y: rearTxt.y - 8 * callouts.u
                width: rearTxt.width + 16 * callouts.u; height: rearTxt.height + 16 * callouts.u
                enabled: rearTxt.visible && !car3DView.moveButtons
                onClicked: car3DView.trunkOpen = (car3DView.trunkOpen > 0.5) ? 0 : 1
            }

            // ── Line + text "Open / Hood" (tap = opens/closes the hood): only there if the car has a hood ──
            Column {
                id: hoodTxt
                visible: car3DView.hasHood
                x: callouts.gHood.x + 8 * callouts.u
                y: callouts.gHood.top
                spacing: 1 * callouts.u
                Text { text: (car3DView.hoodOpen > 0.5) ? qsTr("Close") : qsTr("Open"); color: callouts.inkSoft; font.pixelSize: 11 * callouts.u; font.weight: Font.Medium }
                Text { text: qsTr("Hood"); color: carPanel._lt ? "#171717" : "#E0E0E0"; font.pixelSize: 11 * callouts.u; font.weight: Font.DemiBold }
            }
            MouseArea {
                x: hoodTxt.x - 8 * callouts.u; y: hoodTxt.y - 8 * callouts.u
                width: hoodTxt.width + 16 * callouts.u; height: hoodTxt.height + 16 * callouts.u
                enabled: hoodTxt.visible && !car3DView.moveButtons
                onClicked: car3DView.hoodOpen = (car3DView.hoodOpen > 0.5) ? 0 : 1
            }

            // ── "Move the buttons" mode: each button can be dragged where needed for its own model ──
            component Mover: MouseArea {
                property string key
                z: 30
                visible: car3DView.moveButtons
                preventStealing: true
                // the finger is on the button; the car's point is lineLen lower
                function drag(m) {
                    var p = mapToItem(callouts, m.x, m.y)
                    var a = car3DView.pickCarPoint(callouts, p.x, p.y + callouts.lineLen)
                    if (a) car3DView.setAnchor(key, a)
                }
                onPressed: m => drag(m)
                onPositionChanged: m => { if (pressed) drag(m) }
                Rectangle { anchors.fill: parent; color: "#332C7BF2"; border.color: "#2C7BF2"; border.width: 2; radius: 8 }
            }
            Mover { key: "lock"; x: lockBtn.x - 6 * callouts.u; y: lockBtn.y - 6 * callouts.u; width: lockBtn.width + 12 * callouts.u; height: lockBtn.height + 12 * callouts.u }
            Mover { key: "rear"; visible: car3DView.moveButtons && rearTxt.visible
                    x: rearTxt.x - 8 * callouts.u; y: rearTxt.y - 8 * callouts.u; width: rearTxt.width + 16 * callouts.u; height: rearTxt.height + 16 * callouts.u }
            Mover { key: "hood"; visible: car3DView.moveButtons && hoodTxt.visible
                    x: hoodTxt.x - 8 * callouts.u; y: hoodTxt.y - 8 * callouts.u; width: hoodTxt.width + 16 * callouts.u; height: hoodTxt.height + 16 * callouts.u }
        }

        // Callout lines: attached to the scene's intermediate layer, so
        // drawn BEHIND the 3D model (visible but they do not go over the car).
        Item {
            id: calloutLines
            parent: car3DView.midItem
            anchors.fill: parent
            z: 50
            opacity: callouts.opacity
            visible: opacity > 0.01
            // panel -> scene coordinates (the scene is centered and wider than the panel)
            readonly property real offX: car3DView.x

            // line below the lock
            Rectangle {
                x: callouts.gLock.x - calloutLines.offX - width / 2
                y: callouts.gLock.top + lockBtn.body * 0.7 + 3 * callouts.u
                width: Math.max(1, 1 * callouts.u)
                height: Math.max(0, callouts.gLock.end - y)
                color: callouts.lineCol
            }
            // line below "Open trunk"
            Rectangle {
                visible: callouts.hasCar && car3DView.hasTrunk
                x: callouts.gRear.x - calloutLines.offX
                y: callouts.gRear.top
                width: Math.max(1, 1 * callouts.u)
                height: Math.max(0, callouts.gRear.end - y)
                color: callouts.lineCol
            }
            // line below "Open hood"
            Rectangle {
                visible: car3DView.hasHood
                x: callouts.gHood.x - calloutLines.offX
                y: callouts.gHood.top
                width: Math.max(1, 1 * callouts.u)
                height: Math.max(0, callouts.gHood.end - y)
                color: callouts.lineCol
            }
        }
    }

    // ── PANEL DRAG HANDLE ──
    Item {
        id: sideHandle
        opacity: car3DView.uiHidden ? 0 : 1; visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 220 } }
        width: 130; height: parent.height
        x: carPanel.rhd ? 0 : parent.width - width      // on the edge facing the map
        z: 110

        Rectangle {
            id: handlePill
            // same distance from the edge as AppPanel's handle: 13 wireframe px strip, centered pill
            readonly property real _u: (Window.window && Window.window.uPx) ? Window.window.uPx : 1.12
            width: 2.5; height: 84; radius: 10
            color: carPanel._lt ? "#D0D1D2" : "#8A8B8D"
            anchors.verticalCenter: parent.verticalCenter
            x: carPanel.rhd ? 6.5 * _u - width / 2 : parent.width - 6.5 * _u - width / 2

            // Periodic hint "you can drag me to the left": the
            // pill slides a bit to the left and comes back with a bounce,
            // every now and then — not a continuous loop, just a discreet reminder.
            // NOTE: we animate a transform (Translate), not "x" directly —
            // "x" is already governed by anchors.centerIn, which would always win
            // the conflict and make the animation invisible.
            transform: Translate { id: nudgeT; x: 0 }

            SequentialAnimation {
                id: hintNudge
                loops: 1
                NumberAnimation {
                    target: nudgeT; property: "x"
                    from: 0; to: carPanel.rhd ? 14 : -14
                    duration: 260; easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: nudgeT; property: "x"
                    from: carPanel.rhd ? 14 : -14; to: 0
                    duration: 480; easing.type: Easing.OutBack
                    easing.overshoot: 2.2
                }
            }
            Timer {
                // Only for the apps that really support the fullscreen gesture
                // via drag (see onDragEnded in Main.qml) — before it
                // started with ANY active app, even those without that
                // gesture, which was misleading.
                readonly property var gestureApps: ["androidauto", "theater", "arcade", "browser"]
                interval: 6000
                running: !dragArea.pressed && gestureApps.indexOf(carPanel.activeApp) >= 0
                repeat: true
                onTriggered: if (!dragArea.pressed) { hintNudge.restart(); hintLabelAnim.restart() }
            }
        }

        // Animated label that accompanies the pill's movement. Always in English, in all languages.
        Text {
            id: hintLabel
            text: carPanel.rhd ? "Drag right  \u203A" : "\u2039  Drag left"
            anchors.verticalCenter: parent.verticalCenter
            x: carPanel.rhd ? 26 : parent.width - width - 26
            color: carPanel._lt ? "#5A5B5D" : "#C8C9CA"
            font.pixelSize: 15; font.weight: Font.Medium; font.letterSpacing: 0.4
            opacity: 0
            transform: Translate { id: hintLabelT; x: 0 }
            SequentialAnimation {
                id: hintLabelAnim
                ParallelAnimation {
                    NumberAnimation { target: hintLabel; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { target: hintLabelT; property: "x"; from: carPanel.rhd ? -10 : 10; to: carPanel.rhd ? 6 : -6; duration: 460; easing.type: Easing.OutCubic }
                }
                PauseAnimation { duration: 700 }
                NumberAnimation { target: hintLabel; property: "opacity"; to: 0; duration: 420; easing.type: Easing.InCubic }
            }
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            cursorShape: Qt.SizeHorCursor
            preventStealing: true

            property real startX: 0

            onPressed: function(mouse) {
                startX = mapToItem(null, mouse.x, 0).x
                carPanel.dragStarted(startX)
            }
            onPositionChanged: function(mouse) {
                var globalX = mapToItem(null, mouse.x, 0).x
                carPanel.dragMoved(globalX)
            }
            onReleased: {
                carPanel.dragEnded()
            }
            onCanceled: {
                carPanel.dragEnded()
            }
        }
    }
}