import QtQuick

// LYRICS PANEL — full screen in the app area. Slides up from the bottom.
// Closes with the X at the top right or by pressing the widget's "lyrics" button again.
// It lives inside the music app: if you close the app it stays there in the background and you find it again on reopening.
Item {
    id: sh
    clip: true
    property bool shown: true      // false = hidden (another app is in front) without losing state
    visible: vis > 1 && shown

    // ── Ingressi ─────────────────────────────────────────────────────────
    property bool   open: false
    property bool   lightTheme: false
    property color  bgColor: lightTheme ? "#FFFFFF" : "#171717"
    property string title: ""
    property string artist: ""
    property string cover: ""
    property real   durationMs: 0
    property real   positionMs: 0
    property bool   playing: false

    signal wantOpen(bool o)
    signal seekRequested(real ms)

    // height visible now (0 = closed, height = fully open)
    property real vis: 0
    Behavior on vis { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    Binding { target: sh; property: "vis"; value: sh.open ? sh.height : 0 }

    // Under the panel: absorbs touches so they do not reach the app behind
    MouseArea { anchors.fill: parent; enabled: sh.visible; preventStealing: true; onWheel: wheel => wheel.accepted = true }

    LyricsPanel {
        id: lp
        x: 0
        y: sh.height - sh.vis
        width: sh.width
        height: sh.height
        active: sh.visible && sh.open
        lightTheme: sh.lightTheme
        bgColor: sh.bgColor
        cover: sh.cover
        title: sh.title; artist: sh.artist
        durationMs: sh.durationMs; positionMs: sh.positionMs; playing: sh.playing
        onSeekRequested: ms => sh.seekRequested(ms)
        onCloseRequested: sh.wantOpen(false)
    }
}
