import QtQuick
import QtQuick.Window
import QtQuick.Effects
import VoltaApp 1.0

// ─────────────────────────────────────────────────────────────────────────────
//  UNIFIED QUEUE — "Now playing + Up next" screen shared by YT Music,
//  Spotify and Bluetooth (same look as the old YT Music player
//  screen). Shows the current track whatever the provider (also
//  music from the phone over Bluetooth) and MediaHub's unified queue.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: qp
    color: Theme.bg

    property var hub: null
    property bool lightTheme: false
    property real topPadding: 80             // altezza intestazione dell'app
    // 1 px of the wireframe (canvas 1070 wide) in real px: the whole screen scales with the display
    readonly property real u: (Window.window && Window.window.uPx) ? Window.window.uPx : 1.12

    readonly property var np: hub ? hub.nowPlaying : null
    readonly property bool hasTrack: hub ? hub.hasNowPlaying : false
    readonly property color iconCol: lightTheme ? "#555555" : "#A2A3A5"

    function fmtMs(ms) {
        var s = Math.floor(Math.max(0, ms) / 1000)
        var m = Math.floor(s / 60), sec = s % 60
        return m + ":" + (sec < 10 ? "0" : "") + sec
    }
    function cover(url) {
        if (!url) return ""
        if (url.indexOf("googleusercontent.com") !== -1 && url.indexOf("=") !== -1) return url.split("=")[0] + "=w1000-h1000"
        if (url.indexOf("ytimg.com") !== -1) return url.split("?")[0].replace("sddefault", "maxresdefault").replace("hqdefault", "maxresdefault")
        return url
    }

    component CtrlBtn: Rectangle {
        id: _cb
        property string src
        property bool enabledBtn: true
        property bool toggle: false      // button with state (Shuffle / Repeat)
        property bool active: false
        property string badge: ""
        signal clicked()
        width: 48 * qp.u; height: 49 * qp.u; radius: 10
        opacity: enabledBtn ? 1 : 0.35
        color: _m.pressed ? Theme.bg : Theme.surfaceElevated
        // Casuale / Ripeti: attivo = nero pieno (bianco pieno col tema scuro), spento = grigio chiaro
        readonly property color onCol:  qp.lightTheme ? "#000000" : "#FFFFFF"
        readonly property color offCol: qp.lightTheme ? "#BDBDBD" : "#5E5E5E"
        Image { sourceSize: Qt.size(width * 2, height * 2);
            anchors.centerIn: parent; source: _cb.src; width: 17 * qp.u; height: 17 * qp.u
            layer.enabled: true
            layer.effect: MultiEffect { colorization: 1; colorizationColor: !_cb.toggle ? (qp.lightTheme ? "black" : "#FFFFFF") : _cb.onCol }
        }
        Rectangle {   // dot: button on (icon always pure white)
            visible: _cb.toggle && _cb.active
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 7 * qp.u
            width: 3 * qp.u; height: 3 * qp.u; radius: 1.5 * qp.u; color: _cb.onCol
        }
        Text {
            visible: _cb.badge !== ""
            anchors.horizontalCenter: parent.horizontalCenter; anchors.horizontalCenterOffset: 9 * qp.u
            anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -8 * qp.u
            text: _cb.badge; color: _cb.onCol; font.pixelSize: 8 * qp.u; font.weight: Font.Bold
        }
        MouseArea { id: _m; anchors.fill: parent; preventStealing: true; enabled: _cb.enabledBtn; onClicked: _cb.clicked() }
    }


    // ── Stato vuoto ──
    Column {
        anchors.centerIn: parent
        spacing: 12
        visible: !qp.hasTrack && (!qp.hub || qp.hub.combinedQueue.length === 0)
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Nothing playing"); color: Theme.textPrimary; font.pixelSize: 22 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Start a track from YT Music, Spotify or the phone via Bluetooth")
            color: Theme.textSecondary; font.pixelSize: 14
        }
    }

    Column {
        anchors.fill: parent
        anchors.topMargin: qp.topPadding
        spacing: 0
        visible: qp.hasTrack || (qp.hub && qp.hub.combinedQueue.length > 0)

        // ── Current track ── (measures from the wireframe, in wireframe px * u; origin = under the header)
        //   title 267 x 22 at (15, 25) · artist 266 x 15 at (16, 56) · 5 buttons 48 x 49 at y 88,
        //   evenly spaced over 271 px (from x 15) · cover 156 x 163 at 25 px from the right edge, y 20
        Item {
            id: _now
            width: parent.width; height: 200 * qp.u
            visible: qp.hasTrack

            Text {
                x: 15 * qp.u; y: 25 * qp.u
                width: 267 * qp.u; height: 22 * qp.u
                verticalAlignment: Text.AlignVCenter
                text: qp.np ? qp.np.title : ""
                color: Theme.textPrimary; font.pixelSize: 23.7 * qp.u
                elide: Text.ElideRight; maximumLineCount: 1
            }
            Text {
                x: 15 * qp.u; y: 56 * qp.u
                width: 266 * qp.u; height: 15 * qp.u
                verticalAlignment: Text.AlignVCenter
                text: qp.np ? qp.np.subtitle : ""
                color: Theme.textSecondary; font.pixelSize: 16 * qp.u; font.weight: Font.Medium
                elide: Text.ElideRight; maximumLineCount: 1
            }

            // 5 evenly spaced buttons: 5 x 48 + 4 gaps of 7.75 = 271 px
            Row {
                x: 15 * qp.u; y: 88 * qp.u
                spacing: (271 - 5 * 48) / 4 * qp.u
                CtrlBtn { src: "qrc:/VoltaApp/icons/skip-back.svg"; onClicked: qp.hub.prev() }
                CtrlBtn { src: qp.np && qp.np.isPlaying ? "qrc:/VoltaApp/icons/pause.svg" : "qrc:/VoltaApp/icons/play.svg"; onClicked: qp.hub.togglePlay() }
                CtrlBtn { src: "qrc:/VoltaApp/icons/skip-forward.svg"; onClicked: qp.hub.next() }
                CtrlBtn {
                    src: "qrc:/VoltaApp/icons/shuffle.svg"; toggle: true
                    visible: qp.hub && qp.hub.canModes
                    active: qp.hub && qp.hub.shuffleOn
                    onClicked: qp.hub.toggleShuffle()
                }
                CtrlBtn {
                    src: "qrc:/VoltaApp/icons/repeat.svg"; toggle: true
                    visible: qp.hub && qp.hub.canModes
                    active: qp.hub && qp.hub.repeatMode !== "off"
                    badge: qp.hub && qp.hub.repeatMode === "one" ? "1" : ""
                    onClicked: qp.hub.cycleRepeat()
                }
            }

            // Progress bar (the Bluetooth phone does not support seeking), as wide as the buttons
            Item {
                id: _prog
                x: 15 * qp.u; y: 150 * qp.u
                width: _now.width - 181 * qp.u - 15 * qp.u - 15 * qp.u; height: 28 * qp.u
                readonly property real pct: qp.np && qp.np.durationMs > 1 ? Math.min(1, qp.np.progressMs / qp.np.durationMs) : 0
                Rectangle {
                    id: _track
                    width: parent.width; height: 4; radius: 2; color: Theme.surfaceElevated
                    anchors.top: parent.top; anchors.topMargin: 4
                    Rectangle { id: _fill; width: parent.width * (_seekMA.pressed ? _seekMA.dragPct : _prog.pct); height: parent.height; radius: 2; color: Theme.textPrimary }
                    Rectangle {
                        width: _seekMA.pressed ? 18 : 12; height: width; radius: width / 2
                        color: Theme.textPrimary; anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(_track.width - width, (_seekMA.pressed ? _seekMA.dragPct * _track.width : _fill.width) - width / 2))
                        visible: qp.np && qp.np.canSeek !== false && qp.np.durationMs > 1
                    }
                    // Draggable knob: the seek happens on release
                    MouseArea {
                        id: _seekMA
                        anchors.fill: parent; anchors.margins: -10; preventStealing: true
                        enabled: qp.np && qp.np.canSeek !== false && qp.np.durationMs > 1
                        property real dragPct: 0
                        function pctAt(x) { return Math.max(0, Math.min(1, (x - 10) / _track.width)) }
                        onPressed: function(m) { dragPct = pctAt(m.x) }
                        onPositionChanged: function(m) { if (pressed) dragPct = pctAt(m.x) }
                        onReleased: function(m) { qp.hub.seekPct(pctAt(m.x)) }
                    }
                }
                Text { text: qp.np ? qp.fmtMs(qp.np.progressMs) : ""; color: Theme.textSecondary; font.pixelSize: 12 * qp.u; anchors.left: parent.left; anchors.top: _track.bottom; anchors.topMargin: 4 }
                Text { text: qp.np && qp.np.durationMs > 1 ? "-" + qp.fmtMs(qp.np.durationMs - qp.np.progressMs) : ""; color: Theme.textSecondary; font.pixelSize: 12 * qp.u; anchors.right: parent.right; anchors.top: _track.bottom; anchors.topMargin: 4 }
            }

            // Cover 156 x 163 at 25 px from the right edge, 20 px below the header
            MediaCover {
                width: 156 * qp.u
                height: qp.np && qp.np.isVideo ? Math.round(156 * qp.u * 9 / 16) : 163 * qp.u
                x: parent.width - 25 * qp.u - width
                y: 20 * qp.u + (163 * qp.u - height) / 2
                source: qp.np ? qp.cover(qp.np.cover) : ""
                placeholderIcon: qp.np ? qp.hub.providerIcon(qp.np.provider) : ""
            }
        }

        // ── Coda ──
        Item {
            width: parent.width
            height: parent.height - (qp.hasTrack ? 200 * qp.u : 0)

            Row {
                id: _qHdr
                x: 15 * qp.u; spacing: 16
                Text { text: qsTr("Queue"); color: Theme.textPrimary; font.pixelSize: 22; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    visible: qp.hub && qp.hub.userQueue.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Clear")
                    color: Theme.accent; font.pixelSize: 14; font.weight: Font.Medium
                    MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: qp.hub.clearUserQueue() }
                }
            }

            Text {
                anchors.top: _qHdr.bottom; anchors.topMargin: 18; x: 15 * qp.u
                visible: qp.hub && qp.hub.combinedQueue.length === 0
                text: qp.np && qp.np.provider === "bluetooth"
                      ? qsTr("The phone doesn't report upcoming tracks. Add tracks from YT Music or Spotify: they'll play after this one.")
                      : qsTr("No tracks in queue")
                color: Theme.textSecondary; font.pixelSize: 14
                width: parent.width - 40 * qp.u; wrapMode: Text.WordWrap
            }

            ListView {
                id: _qList
                anchors.top: _qHdr.bottom; anchors.topMargin: 10
                anchors.bottom: parent.bottom
                width: parent.width
                clip: true
                model: qp.hub ? qp.hub.combinedQueue : []
                boundsBehavior: Flickable.StopAtBounds
                footer: Item { width: 1; height: 40 }

                delegate: Item {
                    id: _row
                    width: _qList.width
                    readonly property bool isUser: qp.hub && index < qp.hub.userQueue.length
                    readonly property bool firstOfGroup: index === 0 || (qp.hub && index === qp.hub.userQueue.length)
                    readonly property var d: modelData.data || {}
                    height: 64 + (firstOfGroup ? 30 : 0)

                    Text {
                        visible: _row.firstOfGroup
                        x: 15 * qp.u; y: 6
                        text: _row.isUser ? qsTr("Added by you") : qsTr("Next from ") + qp.hub.providerName(modelData.provider)
                        color: Theme.textSecondary; font.pixelSize: 13; font.weight: Font.DemiBold
                    }

                    Item {
                        y: _row.firstOfGroup ? 30 : 0
                        width: parent.width; height: 64

                        Rectangle { anchors.fill: parent; color: _rowMA.pressed ? Theme.surface : "transparent" }

                        MediaCover {
                            id: _rc
                            x: 15 * qp.u; width: 48; height: 48; radius: 3
                            anchors.verticalCenter: parent.verticalCenter
                            source: _row.d.cover || ""
                            placeholderIcon: qp.hub.providerIcon(modelData.provider)
                        }
                        Column {
                            anchors.left: _rc.right; anchors.leftMargin: 16
                            anchors.right: _prov.left; anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Text { text: _row.d.title || ""; color: Theme.textPrimary; font.pixelSize: 16; font.weight: Font.Medium; width: parent.width; elide: Text.ElideRight }
                            Text { text: _row.d.subtitle || ""; color: Theme.textSecondary; font.pixelSize: 13; width: parent.width; elide: Text.ElideRight }
                        }
                        MouseArea { id: _rowMA; anchors.fill: parent; onClicked: qp.hub.playQueueItem(index) }

                        // Provider icon + removal (only for added tracks)
                        Row {
                            id: _prov
                            anchors.right: parent.right; anchors.rightMargin: 25 * qp.u
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 18
                            Image { sourceSize: Qt.size(width * 2, height * 2);
                                source: qp.hub.providerIcon(modelData.provider)
                                width: 20; height: 20; fillMode: Image.PreserveAspectFit
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                visible: _row.isUser
                                text: "✕"; color: qp.iconCol; font.pixelSize: 18
                                anchors.verticalCenter: parent.verticalCenter
                                MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: qp.hub.removeFromQueue(index) }
                            }
                        }
                    }
                }
            }
        }
    }

    // Short message (e.g. "Added to queue")
    Rectangle {
        z: 10
        anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.margins: 16
        radius: 8; color: "#CC000000"
        width: _toastT.implicitWidth + 24; height: 34
        visible: qp.hub && qp.hub.toastText !== ""
        Text { id: _toastT; anchors.centerIn: parent; text: qp.hub ? qp.hub.toastText : ""; color: "#FFF"; font.pixelSize: 13 }
    }
}
