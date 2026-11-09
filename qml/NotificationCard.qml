import QtQuick
import QtQuick.Effects

// Notification card: positioned ABSOLUTELY above the targetItem (music widget).
// Horizontal swipe to remove; if dismissible=false it bounces back.
Rectangle {
    id: card

    property Item   targetItem: null
    property Item   blurSource: null                // source for "glass" blur
    property string entryId: ""
    property string iconType: "info"
    property color  iconColor: "#ED4E3B"
    property string title: ""
    property string subtitle: ""
    property string actionLabel: ""
    property color  actionColor: "#3D6FE7"
    // Optional second action (e.g. Decline/End next to Answer).
    // If empty, it behaves as before with a single button.
    property string secondaryLabel: ""
    property color  secondaryColor: "#ED4E3B"
    property bool   dismissible: true
    property int    autoDismissMs: 0
    property bool   lightTheme: false

    property int    stackDepth: 0
    property int    totalCount: 1

    signal dismissed()
    signal actionTriggered()
    signal secondaryTriggered()

    // Size: slightly smaller than the target to create the
    // "notification above the widget" effect (symmetric inset of ~14px per side)
    // Same position and size as the player (see MusicWidget):
    // a bit wider and lower than the music player, which stays visible underneath.
    property real overlayDx: 0
    property real overlayDy: 0
    property real overlayDw: 0
    property real overlayDh: 0
    width: targetItem ? Math.max(120, targetItem.width + overlayDw) : 300
    height: targetItem ? Math.max(60, targetItem.height + overlayDh) : 88

    radius: 10
    // Transparent: on top there are blur + veil. Cards without blurSource
    // fall back to a solid color thanks to the fallback in the veil.
    color: "transparent"
    clip: false     // false to show the shadow under the card
    // Barely perceptible border to separate from the blur (glass effect)
    border.width: 1
    border.color: card.lightTheme ? "#33FFFFFF" : "#22FFFFFF"

    // Soft three-dimensional shadow under the card (gentle, diffuse)
    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowBlur: 1.0             // sfocatura massima → alone morbido
        shadowColor: "#33000000"    // 20% opacity → not "hard"
        shadowVerticalOffset: 10
        shadowHorizontalOffset: 0
        paddingRect: Qt.rect(0, 0, 0, 30)   // more space below for the glow
    }

    // ── BLUR "APPLE-STYLE" ──────────────────────────────────────────
    // Captures what is behind the card, blurs it, and puts a
    // semi-transparent veil on top for the glass effect between the card and the music.
    Item {
        anchors.fill: parent
        visible: card.blurSource !== null && !Theme.lowPower

        ShaderEffectSource {
            id: cardBgGrab
            anchors.fill: parent
            sourceItem: card.blurSource
            // Source in blurSource coordinates; starts from the card's
            // real position on the screen
            sourceRect: card.blurSource
                ? Qt.rect(card.mapToItem(card.blurSource, 0, 0).x,
                          card.mapToItem(card.blurSource, 0, 0).y,
                          card.width, card.height)
                : Qt.rect(0, 0, 1, 1)
            live: true
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: cardBgGrab
            blurEnabled: true
            blur: 1.0
            blurMax: 48
            autoPaddingEnabled: false
            maskEnabled: true
            maskSource: cardRoundMask
        }
        Rectangle {
            id: cardRoundMask
            anchors.fill: parent
            radius: 10
            visible: false
            layer.enabled: true
            color: "#FFFFFF"
        }
    }
    // Translucent dark veil (or solid if there is no blur)
    Rectangle {
        anchors.fill: parent
        radius: 10
        color: (card.blurSource !== null && !Theme.lowPower)
               ? (card.lightTheme ? "#A0F2F2F2" : "#A0262626")
               : (card.lightTheme ? "#F2F2F2" : "#262626")
    }


    // (the cards behind rise higher and are only seen as a tab)
    property real swipeX: 0
    readonly property real targetSceneX: targetItem ? targetItem.mapToItem(parent, 0, 0).x : 0
    readonly property real targetSceneY: targetItem ? targetItem.mapToItem(parent, 0, 0).y : 0

    // Top card: sits JUST above the music (small offset, the shrunk
    // music peeks out under the card like an iOS "tab").
    // Cards behind: each rises 14px more.
    readonly property real peekY: targetSceneY + overlayDy - stackDepth * 14
    readonly property real hideY: targetSceneY - height - 40

    // Horizontally centered above the target (card narrower than the music widget)
    readonly property real centerOffset: overlayDx
    x: targetSceneX + centerOffset + swipeX
    // stack effect scale (cards behind slightly smaller)
    transform: Scale {
        origin.x: card.width / 2; origin.y: card.height / 2
        xScale: 1 - card.stackDepth * 0.04
        yScale: 1 - card.stackDepth * 0.04
    }
    opacity: 1 - stackDepth * 0.18

    Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

    // Y: enters from the top with a bounce, leaves with the ejection NumberAnimation
    Behavior on y {
        enabled: !expelAnim.running
        NumberAnimation { duration: 480; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
    }
    Behavior on swipeX {
        enabled: !swipeDrag.active && !expelAnim.running
        NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
    }

    // ── Horizontal swipe (top card only) ─────────────────────
    DragHandler {
        id: swipeDrag
        target: null
        enabled: card.stackDepth === 0
        yAxis.enabled: false
        onActiveChanged: if (!active) card._releaseSwipe()
        onTranslationChanged: {
            if (!active) return
            var t = translation.x
            if (!card.dismissible) {
                // Rubber-band logaritmico
                t = Math.sign(t) * (Math.log(1 + Math.abs(t) / 30) * 40)
            }
            card.swipeX = t
        }
    }
    function _releaseSwipe() {
        var threshold = card.width * 0.4
        if (card.dismissible && Math.abs(swipeX) > threshold) {
            expelAnim.to = swipeX > 0 ? card.width + 80 : -card.width - 80
            expelAnim.restart()
        } else {
            swipeX = 0
        }
    }
    NumberAnimation {
        id: expelAnim; target: card; property: "swipeX"
        duration: 220; easing.type: Easing.OutCubic
        onFinished: card.dismissed()
    }

    // Auto dismiss
    Timer {
        id: autoDismissTimer
        interval: Math.max(1, card.autoDismissMs)
        running: card.autoDismissMs > 0
        repeat: false
        onTriggered: {
            expelAnim.to = -card.width - 80
            expelAnim.restart()
        }
    }

    // Entry from the top: starts from hideY and goes to peekY thanks to the Behavior on y
    Component.onCompleted: {
        y = hideY
        entryTimer.restart()
    }
    onPeekYChanged: if (!entryTimer.running) y = peekY
    Timer {
        id: entryTimer; interval: 10; repeat: false
        onTriggered: card.y = card.peekY
    }

    // ════════ CALL LAYOUT (like the EV notification) ════════
    property string layoutType: ""
    readonly property bool callMode: layoutType === "call"
    property bool incomingCall: false
    property bool micMuted: false
    signal micToggled(bool m)
    signal keypadRequested()

    component CallBtn: Rectangle {
        id: cb
        signal clicked()
        default property alias content: cbHolder.data
        radius: 8
        color: cbMa.pressed ? (card.lightTheme ? "#CFCFD3" : "#555558")
                            : (card.lightTheme ? "#E4E4E6" : "#3A3A3C")
        Item { id: cbHolder; anchors.fill: parent }
        MouseArea { id: cbMa; anchors.fill: parent; onClicked: cb.clicked() }
    }

    Item {
        id: callBox
        visible: card.callMode
        anchors.fill: parent
        anchors.margins: 10

        // number/name + duration
        Row {
            id: callTop
            anchors.top: parent.top; anchors.topMargin: 4
            anchors.left: parent.left; anchors.leftMargin: 6
            width: parent.width - 12
            spacing: 10
            Text {
                id: ctTitle
                text: card.title
                color: card.lightTheme ? "#171717" : "#FFFFFF"
                font.pixelSize: 21; font.weight: Font.DemiBold
                elide: Text.ElideRight
                width: Math.min(implicitWidth, callTop.width - ctSub.width - callTop.spacing)
                height: 30; verticalAlignment: Text.AlignVCenter
            }
            Text {
                id: ctSub
                text: card.subtitle
                color: card.lightTheme ? "#757575" : "#A2A3A5"
                font.pixelSize: 17
                elide: Text.ElideRight
                visible: !card.incomingCall
                width: visible ? Math.min(implicitWidth, callTop.width * 0.42) : 0
                height: 30; verticalAlignment: Text.AlignVCenter
            }
        }

        // three flat buttons (two if the call is incoming)
        Row {
            id: callBtns
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 42
            spacing: 8
            readonly property int n: card.incomingCall ? 2 : 3
            readonly property real bw: (width - spacing * (n - 1)) / n

            // dial pad (no function for now: DTMF sending is missing in the service)
            CallBtn {
                visible: !card.incomingCall
                width: callBtns.bw; height: parent.height
                onClicked: card.keypadRequested()
                Canvas {
                    anchors.centerIn: parent; width: 22; height: 22
                    property color col: card.lightTheme ? "#555555" : "#D0D0D2"
                    onColChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d"); c.clearRect(0, 0, width, height); c.fillStyle = col
                        for (var r = 0; r < 3; r++) for (var q = 0; q < 3; q++) {
                            c.beginPath(); c.arc(3 + q * 8, 3 + r * 8, 2.2, 0, Math.PI * 2); c.fill()
                        }
                    }
                }
            }

            // microphone on/off (without arrows)
            CallBtn {
                visible: !card.incomingCall
                width: callBtns.bw; height: parent.height
                onClicked: { card.micMuted = !card.micMuted; card.micToggled(card.micMuted) }
                Canvas {
                    anchors.centerIn: parent; width: 24; height: 28
                    property color col: card.lightTheme ? "#555555" : "#D0D0D2"
                    property bool mm: card.micMuted
                    onColChanged: requestPaint()
                    onMmChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d"); c.clearRect(0, 0, width, height)
                        c.fillStyle = col; c.strokeStyle = col; c.lineWidth = 2; c.lineCap = "round"
                        c.beginPath(); c.arc(12, 8, 4.5, Math.PI, 0); c.lineTo(16.5, 14); c.arc(12, 14, 4.5, 0, Math.PI); c.closePath(); c.fill()
                        c.beginPath(); c.arc(12, 14, 8, 0, Math.PI); c.stroke()
                        c.beginPath(); c.moveTo(12, 22); c.lineTo(12, 26); c.stroke()
                        if (mm) {
                            c.strokeStyle = "#ED4E3B"; c.lineWidth = 3
                            c.beginPath(); c.moveTo(3, 3); c.lineTo(21, 25); c.stroke()
                        }
                    }
                }
            }

            // answer (incoming call only)
            CallBtn {
                visible: card.incomingCall
                width: callBtns.bw; height: parent.height
                onClicked: card.actionTriggered()
                Image {
                    id: ansImg
                    anchors.centerIn: parent; width: 24; height: 24
                    source: "qrc:/VoltaApp/icons/phone.svg"; fillMode: Image.PreserveAspectFit
                    layer.enabled: true
                    layer.effect: MultiEffect { colorization: 1.0; colorizationColor: "#34C759"; brightness: 0.35 }
                }
            }

            // termina / rifiuta (rosso)
            CallBtn {
                width: callBtns.bw; height: parent.height
                onClicked: card.incomingCall ? card.secondaryTriggered() : card.actionTriggered()
                Image {
                    anchors.centerIn: parent; width: 24; height: 24
                    source: "qrc:/VoltaApp/icons/phone.svg"; fillMode: Image.PreserveAspectFit
                    rotation: 135
                    layer.enabled: true
                    layer.effect: MultiEffect { colorization: 1.0; colorizationColor: "#E53935"; brightness: 0.35 }
                }
            }
        }
    }

    // Contenuto card
    Row {
        visible: !card.callMode
        anchors.fill: parent
        anchors.leftMargin: 18; anchors.rightMargin: 14
        spacing: 14

        Item {
            width: 46; height: 46
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent; radius: width / 2
                color: card.iconColor
                Behavior on color { ColorAnimation { duration: 300 } }
            }
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var c = getContext("2d"); c.clearRect(0,0,width,height);
                    c.strokeStyle = "#FFFFFF"; c.lineWidth = 3.5; c.lineCap = "round"; c.lineJoin = "round"
                    switch (card.iconType) {
                    case "check":
                        c.beginPath(); c.moveTo(14, 24); c.lineTo(21, 31); c.lineTo(33, 17); c.stroke()
                        break
                    case "wifi-off":
                        c.beginPath(); c.arc(23,30,3,0,Math.PI*2); c.fillStyle="#FFFFFF"; c.fill()
                        for (var i=1;i<=3;i++){ c.beginPath()
                            c.arc(23,30,6*i,-Math.PI*0.75,-Math.PI*0.25); c.stroke() }
                        c.beginPath(); c.moveTo(12,12); c.lineTo(34,34); c.stroke()
                        break
                    case "phone":
                        c.beginPath()
                        c.moveTo(14,20); c.lineTo(20,14); c.lineTo(26,20); c.lineTo(22,24)
                        c.lineTo(28,30); c.lineTo(32,26); c.lineTo(38,32); c.lineTo(32,38); c.stroke()
                        break
                    case "bt":
                        c.beginPath(); c.moveTo(18,14); c.lineTo(30,26); c.lineTo(22,34)
                        c.moveTo(22,14); c.lineTo(30,22); c.lineTo(18,34); c.stroke()
                        break
                    case "message":
                        // Speech bubble with a tail, same stroke style as the other icons.
                        c.beginPath()
                        c.moveTo(14,16); c.lineTo(32,16); c.lineTo(32,30)
                        c.lineTo(20,30); c.lineTo(16,36); c.lineTo(18,30)
                        c.lineTo(14,30); c.closePath(); c.stroke()
                        // three dots inside, suggesting a text message
                        c.fillStyle = "#FFFFFF"
                        for (var dx = 0; dx < 3; dx++) {
                            c.beginPath(); c.arc(19 + dx*4.5, 23, 1.4, 0, Math.PI*2); c.fill()
                        }
                        break
                    case "info":
                    default:
                        c.beginPath(); c.arc(23,17,2.5,0,Math.PI*2); c.fillStyle="#FFFFFF"; c.fill()
                        c.beginPath(); c.moveTo(23,23); c.lineTo(23,35); c.stroke()
                    }
                }
                Connections {
                    target: card
                    function onIconTypeChanged() { parent.requestPaint() }
                }
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 46 - 14 - (actionBtn.visible ? (actionBtn.width + 14) : 0)
            spacing: 3
            Text {
                text: card.title
                color: card.lightTheme ? "#171717" : "#FFFFFF"
                font.pixelSize: 15; font.weight: Font.DemiBold
                elide: Text.ElideRight; width: parent.width
            }
            Text {
                text: card.subtitle
                visible: card.subtitle !== ""
                color: card.lightTheme ? "#757575" : "#A2A3A5"
                font.pixelSize: 12
                elide: Text.ElideRight; width: parent.width
            }
        }

        // Secondary button (e.g. Decline) — appears to the left of the primary
        Rectangle {
            id: secondaryBtn
            visible: card.secondaryLabel !== ""
            width: secondaryText.implicitWidth + 28; height: 36; radius: 18
            anchors.verticalCenter: parent.verticalCenter
            color: secondaryMa.pressed ? Qt.darker(card.secondaryColor, 1.2) : card.secondaryColor
            Text {
                id: secondaryText
                anchors.centerIn: parent; text: card.secondaryLabel
                color: "#FFFFFF"; font.pixelSize: 13; font.weight: Font.DemiBold
            }
            MouseArea {
                id: secondaryMa; anchors.fill: parent
                onClicked: card.secondaryTriggered()
            }
        }
        Rectangle {
            id: actionBtn
            visible: card.actionLabel !== ""
            width: actionText.implicitWidth + 32; height: 36; radius: 18
            anchors.verticalCenter: parent.verticalCenter
            color: actionMa.pressed ? Qt.darker(card.actionColor, 1.2) : card.actionColor
            Text {
                id: actionText
                anchors.centerIn: parent; text: card.actionLabel
                color: "#FFFFFF"; font.pixelSize: 13; font.weight: Font.DemiBold
            }
            MouseArea {
                id: actionMa; anchors.fill: parent
                onClicked: card.actionTriggered()
            }
        }
    }
}
