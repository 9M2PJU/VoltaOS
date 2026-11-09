import QtQuick
import QtQuick.Effects
import QtCore as Core
import VoltaApp 1.0

// ─────────────────────────────────────────────────────────────────────────────
//  TOYBOX › EMISSIONS — "Emissions test mode"
//
//  On the left: title, description and sound selection.
//  On the right: the same cabin diagram as Settings › Audio ›
//  Balance, but instead of the dot there is the pink cushion. The cushion can be
//  dragged (or tap the cabin to move it) along the left–right
//  bar: moving it does NOT start anything. Tapping the cushion starts the sound,
//  balanced between the left and right speakers according to its position.
//
//  File audio: volta_os/assets/toybox-audio/<chiave>.<estensione>
//  (any format mpv can read: mp3, wav, ogg, m4a…). Keys:
//    squartapantaloncini, falcon_heavy, puzzetta_assurda, tanfo_neurale,
//    puzzetta_nolosa, puzzetta_verificata
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: em

    property bool lightTheme: false
    // Space available BELOW the panel (the row of cards): the sound list
    // only opens downward and can go down that far
    property real extraBelow: 0

    readonly property string audioDir: appDir + "/assets/toybox-audio"

    // Available sounds (key "" = no sound, "random" = random)
    readonly property var sounds: [
        { key: "",                    name: "No sound" },
        { key: "squartapantaloncini", name: "Pants Ripper" },
        { key: "falcon_heavy",        name: "Falcon Heavy" },
        { key: "puzzetta_assurda",    name: "Absurd toot" },
        { key: "tanfo_neurale",       name: "Neural stench" },
        { key: "puzzetta_nolosa",     name: "Boring toot" },
        { key: "puzzetta_verificata", name: "Verified toot" },
        { key: "random",              name: "Random" }
    ]

    // Choices remembered between one start and the next
    Core.Settings {
        id: emPrefs
        category: "toybox"
        property int    soundIdx: 6          // "Verified toot"
        property real   cushionPos: 0.0      // -1 sinistra … 0 centro … +1 destra
    }

    readonly property color txt:     lightTheme ? "#171717" : "#FFFFFF"
    readonly property color txtSub:  lightTheme ? "#5A5A5A" : "#A2A3A5"
    readonly property color panelBg: lightTheme ? "#FFFFFF" : "#1E1E1E"
    readonly property color ctrlBg:  lightTheme ? "#F0F0F0" : "#2A2A2A"
    readonly property color ctrlBrd: lightTheme ? "#D8D8D8" : "#3A3A3A"
    readonly property color popupBg: lightTheme ? "#FFFFFF" : "#2A2A2A"

    SystemHelper { id: sysHelper }

    // Blue "verified" check mark, only for "Verified toot"
    component VerifiedBadge: Rectangle {
        width: 18; height: 18; radius: 9
        color: "#2C7BF2"
        Text { anchors.centerIn: parent; text: "✓"; color: "#FFFFFF"; font.pixelSize: 11; font.weight: Font.Bold }
    }

    // ── Riproduzione bilanciata ──
    // mpv (already used by YT Music) with a "pan" filter: the gain of each
    // channel follows the cushion's position, like the car's balance.
    function play() {
        var s = em.sounds[emPrefs.soundIdx]
        if (!s || s.key === "") return
        var key = s.key
        if (key === "random") {
            var pool = em.sounds.filter(function(x) { return x.key !== "" && x.key !== "random" })
            key = pool[Math.floor(Math.random() * pool.length)].key
        }
        var b = Math.max(-1, Math.min(1, emPrefs.cushionPos))
        // (channels swapped compared to the first version, which came out inverted
        // sugli altoparlanti dell'auto)
        var gl = Math.min(1, 1 + b).toFixed(2)
        var gr = Math.min(1, 1 - b).toFixed(2)
        var af = "--af=lavfi=[aformat=channel_layouts=stereo,pan=stereo|c0=" + gl + "*c0|c1=" + gr + "*c1]"
        // The shell is only needed to find the file whatever the extension;
        // key, folder and filter are passed as arguments ($1 $2 $3), never
        // interpolated into the command.
        var shArgs = ["-c",
            'f=$(ls "$2/$1".* 2>/dev/null | head -n1); [ -n "$f" ] && exec mpv --no-video --really-quiet --no-terminal --load-scripts=no "$3" "$f"',
            "toybox", key, em.audioDir, af]
        // With the system player the music ducks while the effect plays
        // and goes back up at the end; otherwise it just starts as before
        if (typeof Mpris !== "undefined" && Mpris) Mpris.playEffect("/bin/sh", shArgs, 0.2)
        else sysHelper.runDetached("/bin/sh", shArgs)
        puff.restart()
    }

    // ══════════════ PANEL ══════════════
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: em.panelBg

        // ── Colonna sinistra: testi + selezione suono ──
        Column {
            id: leftCol
            anchors.left: parent.left; anchors.leftMargin: 44
            anchors.top: parent.top; anchors.topMargin: 40
            width: Math.min(360, parent.width - cabinBox.width - 120)
            spacing: 14

            Text {
                width: parent.width
                text: qsTr("Emissions test mode")
                color: em.txt; font.pixelSize: 26; font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: qsTr("Play a smelly prank on one of your passengers, in any seat.")
                color: em.txtSub; font.pixelSize: 15
                wrapMode: Text.WordWrap
            }
            Item { width: 1; height: 8 }

            // Sound selector (opens the list)
            Rectangle {
                id: soundBtn
                width: parent.width; height: 52; radius: 8
                color: em.ctrlBg
                border.width: 1; border.color: em.ctrlBrd
                Row {
                    anchors.left: parent.left; anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text {
                        text: em.sounds[emPrefs.soundIdx] ? em.sounds[emPrefs.soundIdx].name : ""
                        color: em.txt; font.pixelSize: 16; font.weight: Font.Medium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    VerifiedBadge {
                        visible: em.sounds[emPrefs.soundIdx] && em.sounds[emPrefs.soundIdx].key === "puzzetta_verificata"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Canvas {
                    anchors.right: parent.right; anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: 13; height: 8
                    rotation: soundList.visible ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 160 } }
                    property color col: em.txtSub
                    onColChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d"); c.clearRect(0, 0, width, height)
                        c.strokeStyle = col; c.lineWidth = 2; c.lineCap = "round"; c.lineJoin = "round"
                        c.beginPath(); c.moveTo(1.5, 1.5); c.lineTo(width / 2, height - 1.5); c.lineTo(width - 1.5, 1.5); c.stroke()
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: soundList.visible = !soundList.visible }
            }

            Text {
                width: parent.width
                text: qsTr("Place the cushion on a seat, then tap it.")
                color: em.txtSub; font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
        }

        // ── Cabin with the cushion (same diagram as the balance) ──
        Rectangle {
            id: cabinBox
            anchors.right: parent.right; anchors.rightMargin: 32
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height - 48
            width: Math.min(height * 1.3, parent.width * 0.55)
            radius: 8
            color: em.lightTheme ? "#DCDCDC" : "#242424"
            clip: true

            Item {
                id: cabin
                anchors.fill: parent

                readonly property real trackLFrac: 0.16
                readonly property real trackRFrac: 0.84
                readonly property real trackYFrac: 0.5

                Image {
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    asynchronous: true
                    source: "qrc:/VoltaApp/images/cabin_balance.png"
                }

                // Vertical line that follows the cushion
                Rectangle {
                    width: 3; radius: 1.5
                    height: cabin.height
                    color: "#FFFFFF"; opacity: 0.55
                    x: track.x + cushion.x + cushion.width / 2 - width / 2
                }

                Item {
                    id: track
                    x: cabin.width * cabin.trackLFrac
                    y: cabin.height * cabin.trackYFrac
                    width: cabin.width * (cabin.trackRFrac - cabin.trackLFrac)
                    height: 1

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 3; radius: 1.5
                        color: "#FFFFFF"; opacity: 0.55
                    }
                    // Center tick
                    Rectangle {
                        anchors.centerIn: parent
                        width: 30; height: 30; radius: 15
                        color: "transparent"
                        border.width: 3; border.color: "#FFFFFF"
                    }

                    // The pink cushion in place of the dot
                    Image {
                        id: cushion
                        width: 64; height: 64 * (sourceSize.height > 0 ? sourceSize.height / sourceSize.width : 1.08)
                        anchors.verticalCenter: parent.verticalCenter
                        source: "qrc:/VoltaApp/images/whoopee_cushion.png"
                        fillMode: Image.PreserveAspectFit
                        smooth: true; mipmap: true
                        x: ((emPrefs.cushionPos + 1) / 2) * (parent.width - width)
                        Behavior on x { enabled: !cabinMouse.pressed; NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                        transformOrigin: Item.Center

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true; shadowBlur: 0.6
                            shadowColor: "#80000000"; shadowVerticalOffset: 3
                        }

                        // "Puff" when the sound starts
                        SequentialAnimation {
                            id: puff
                            NumberAnimation { target: cushion; property: "scale"; to: 0.82; duration: 90; easing.type: Easing.OutQuad }
                            NumberAnimation { target: cushion; property: "scale"; to: 1.12; duration: 140; easing.type: Easing.OutQuad }
                            NumberAnimation { target: cushion; property: "scale"; to: 1.0;  duration: 260; easing.type: Easing.OutBack }
                        }
                    }
                }

                // Moves the cushion (tap or drag on the cabin);
                // tap ON the cushion without dragging = sound.
                MouseArea {
                    id: cabinMouse
                    anchors.fill: parent
                    preventStealing: true
                    readonly property real snapPx: 14
                    property bool onCushion: false
                    property bool moved: false
                    property real startX: 0
                    property real startY: 0

                    function hitCushion(mx, my) {
                        var p = cushion.mapToItem(cabin, 0, 0)
                        var pad = 10
                        return mx >= p.x - pad && mx <= p.x + cushion.width + pad
                            && my >= p.y - pad && my <= p.y + cushion.height + pad
                    }
                    function upd(mx) {
                        var localX = mx - track.x - cushion.width / 2
                        var usable = track.width - cushion.width
                        var half = usable / 2
                        if (Math.abs(localX - half) <= snapPx) { emPrefs.cushionPos = 0; return }
                        emPrefs.cushionPos = Math.max(-1, Math.min(1, (localX / usable) * 2 - 1))
                    }
                    onPressed: (m) => {
                        soundList.visible = false
                        onCushion = hitCushion(m.x, m.y)
                        moved = false
                        startX = m.x; startY = m.y
                        if (!onCushion) upd(m.x)
                    }
                    onPositionChanged: (m) => {
                        if (!pressed) return
                        if (!moved && Math.abs(m.x - startX) + Math.abs(m.y - startY) > 8) moved = true
                        if (moved || !onCushion) upd(m.x)
                    }
                    onReleased: {
                        if (onCushion && !moved) em.play()
                    }
                }
            }
        }
    }

    // ── Sound list (above the panel, as in the photo) ──
    Rectangle {
        id: soundList
        visible: false
        z: 50
        x: leftCol.x
        y: leftCol.y + soundBtn.y + soundBtn.height + 6
        width: leftCol.width
        // Always downward; if there is no room for all the entries it scrolls
        height: Math.min(listCol.height + 12, em.height + em.extraBelow - y - 12)
        radius: 8
        color: em.popupBg
        border.width: 1; border.color: em.ctrlBrd

        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowColor: "#60000000"; shadowVerticalOffset: 4 }

        Flickable {
            anchors.fill: parent; anchors.topMargin: 6; anchors.bottomMargin: 6
            contentHeight: listCol.height
            boundsBehavior: Flickable.StopAtBounds
            clip: true
        Column {
            id: listCol
            width: parent.width
            Repeater {
                model: em.sounds
                Rectangle {
                    width: listCol.width; height: 44
                    // Selected entry: highlighted (the blue check mark is part of the name
                    // of "Verified toot", not a selection mark)
                    color: _sMA.pressed || index === emPrefs.soundIdx ? em.ctrlBg : "transparent"
                    Row {
                        anchors.left: parent.left; anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Text {
                            text: modelData.name
                            color: index === emPrefs.soundIdx ? em.txt : em.txtSub
                            font.pixelSize: 15
                            font.weight: index === emPrefs.soundIdx ? Font.DemiBold : Font.Normal
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        VerifiedBadge { visible: modelData.key === "puzzetta_verificata"; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea {
                        id: _sMA
                        anchors.fill: parent
                        onClicked: { emPrefs.soundIdx = index; soundList.visible = false }
                    }
                }
            }
        }
        }
    }
}
