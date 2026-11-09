import QtQuick
import QtQuick.Window
import QtQuick.Effects
import VoltaApp 1.0

Item {
    property bool lightTheme: Window.window.lightTheme
    id: widget
    // Single height of the bottom widgets (music / map / notifications)
    // 103 px of the wireframe (canvas 1070 wide): scales with the window width
    // Wireframe 2 (miniplayer): canvas 1070 wide -> k = real px per wireframe px
    readonly property real k: (Window.window ? Window.window.width : 1200) / 1070
    readonly property real baseH: 100 * k
    height: baseH

    property string audioSrc:        ""
    property string widgetTitle:     "Nothing playing"
    property string widgetArtist:    ""
    property string widgetArtwork:   ""
    property real   progressPct:     0
    property real   progressSec:     0
    property real   durationSec:     0
    property bool   isPlaying:       false
    property bool   isLiked:         false
    property bool   shuffleOn:       false
    property bool   repeatOn:        false
    property string repeatMode:      "off"      // "off" | "all" | "one"
    property bool   canSeek:         true       // the player allows seeking within the track
    property bool   modesAvailable:  audioSrc === "spotify" || audioSrc === "ytmusic"
    property bool   isFullScreen:    false
    property string _spotifyTrackId: ""

    property Item blurSource: null
    property rect blurRect: Qt.rect(0, 0, 0, 0)

    signal clicked()
    signal playPause()
    signal prev()
    signal next()
    signal like()
    signal shuffle()
    signal repeat()
    signal seek(real pct)
    signal openSearch()
    signal openEqualizer()
    // Podcast: dedicated buttons in the miniplayer (prev./next episode, -15 s, +30 s, speed)
    property bool   podcastMode:      false
    property bool   localMusicMode:   false      // "Music" player (PC files / sticks)
    property string podcastSpeedText: "1×"
    signal podcastSkip(int secs)
    signal podcastSpeed()
    signal openLyrics()
    property bool lyricsAvailable: false
    property bool lyricsOn: false

    signal requestAudioFocus(string src)
    signal requestRadioSkip(int dir)
    property bool _wasSpotifyPlaying: false

    property string radioTitle:   ""
    property string radioArtwork: ""
    property bool   radioPlaying: false

    function fmt(s) {
        s = Math.max(0, Math.floor(s))
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
    // Radio: it is a live stream, there is no previous/next track and it cannot be paused:
    // next/previous are off (light gray) and in place of play/pause there is the "stop" square
    readonly property bool isRadio: audioSrc === "radio"
    function srcIcon(src) {
        if (podcastMode && src === "mpris") return "qrc:/VoltaApp/icons/podcast.svg"
        if (localMusicMode && src === "mpris") return "qrc:/VoltaApp/icons/localmusic.svg"
        var m = {
            "spotify": "qrc:/VoltaApp/icons/spotify.svg",
            "ytmusic": "qrc:/VoltaApp/icons/ytmusic.svg",
            "theater": "qrc:/VoltaApp/icons/video.svg",
            "music":   "qrc:/VoltaApp/icons/music.svg",
            "radio":   "qrc:/VoltaApp/icons/radio.svg",
            "mpris":   "qrc:/VoltaApp/icons/bluetooth.svg",
            "bluetooth": "qrc:/VoltaApp/icons/bluetooth.svg"
        }
        return m[src] || ""
    }
    function cleanArtworkUrl(url) {
        if (!url) return ""
        if (url.indexOf("ytimg.com") !== -1) return url.split("?")[0]
        return url
    }

    readonly property real artH: 51 * k      // cover 50x51, top band 51
    readonly property real artW: 50 * k

    signal requestSpotifyControl(string cmd)

    Connections {
        target: widget
        function onPlayPause() {
            if (widget.audioSrc === "radio") return
            widget.requestSpotifyControl("toggle")
        }
        function onPrev() {
            if (widget.audioSrc === "radio") { widget.requestRadioSkip(-1); return }
            widget.requestSpotifyControl("prev")
        }
        function onNext() {
            if (widget.audioSrc === "radio") { widget.requestRadioSkip(1); return }
            widget.requestSpotifyControl("next")
        }
        function onSeek(pct) {
            // Seeking is already done by Main (handleSeek): forwarding it from here as well
            // sent it twice
        }
    }

    // Position/size of the notification layer relative to the player (Main.qml reads them from here)
    readonly property int overlayDx: -4
    readonly property int overlayDy: 4
    readonly property int overlayDw: 8
    readonly property int overlayDh: 0

    Rectangle {
        id: musicBox
        visible: true
        x: 0; y: 0
        width: parent.width; height: widget.baseH
        color: "transparent"; radius: 6 * widget.k; clip: true

        // Very light shadow — barely perceptible, only to detach the
        // widget slightly from the background, not a strong shadow like the
        // notification cards.
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.8
            shadowColor: "#20000000"
            shadowVerticalOffset: 4
            shadowHorizontalOffset: 0
            paddingRect: Qt.rect(0, 0, 0, 12)
        }

        Item {
            anchors.fill: parent
            visible: widget.blurSource !== null && !Theme.lowPower

            ShaderEffectSource {
                id: bgGrab
                anchors.fill: parent
                sourceItem: widget.blurSource
                sourceRect: widget.blurRect
                live: true
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: bgGrab
                blurEnabled: true
                blur: 1.0
                blurMax: 48
                autoPaddingEnabled: false
                maskEnabled: true
                maskSource: roundMask
            }
            Rectangle {
                id: roundMask
                anchors.fill: parent
                radius: 6 * widget.k
                visible: false
                layer.enabled: true
                color: "#FFFFFF"
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: 6 * widget.k
            color: (widget.blurSource !== null && !Theme.lowPower) ? (lightTheme ? "#A0F2F2F2" : "#A0262626") : (lightTheme ? "#F2F2F2" : "#262626")
        }

        // SWIPE AND CLICK ON THE BACKGROUND COMPLETELY REMOVED.
        // dl69: tap on the top band (cover + title) = signal clicked(); the buttons above stay clickable
        MouseArea {
            x: 0; y: 0; width: parent.width; height: widget.artH
            onClicked: widget.clicked()
        }

        Row {
            id: topRow
            width: parent.width; height: widget.artH

            // Cover with the top left corner rounded like the
            // widget: same technique as the Spotify / YT Music covers
            // (hidden image + MultiEffect with rounded mask).
            Item {
                id: artBox
                width: widget.artW; height: widget.artH

                Rectangle {
                    anchors.fill: parent
                    radius: 2 * widget.k; topLeftRadius: 6 * widget.k
                    color: lightTheme ? "#F0F0F0" : "#262626"
                }
                Image {
                    id: artImg
                    anchors.fill: parent
                    source: widget.cleanArtworkUrl(widget.widgetArtwork)
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                    asynchronous: true
                    smooth: true; mipmap: true
                }
                Item {
                    id: artMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    layer.smooth: true
                    Rectangle {
                        anchors.fill: parent
                        radius: 2 * widget.k; topLeftRadius: 6 * widget.k
                        color: "white"
                    }
                }
                MultiEffect {
                    anchors.fill: artImg
                    source: artImg
                    maskEnabled: true
                    maskSource: artMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                    visible: widget.widgetArtwork !== "" && artImg.status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent; text: "🎵"; font.pixelSize: 24 * widget.k
                    visible: widget.widgetArtwork === "" || artImg.status !== Image.Ready
                }
            }

            Item {
                id: trackInfo
                width: topRow.width - widget.artW; height: widget.artH

                Column {
                    // title + artist vertically centered in the top band
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left; anchors.leftMargin: 12 * widget.k
                    width: srRow.visible ? parent.width - srRow.width - 12 * widget.k : parent.width - 24 * widget.k
                    spacing: 3 * widget.k; clip: true

                    Item {
                        width: parent.width; height: 12 * widget.k

                        Text {
                            id: titleText
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: widget.widgetTitle === "Nothing playing" ? qsTr("Nothing playing") : widget.widgetTitle
                            color: lightTheme ? "#F2171717" : "#F2D0D1D2"; font.pixelSize: 12 * widget.k; font.weight: Font.Normal
                            clip: true; elide: Text.ElideNone
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.top: parent.top
                            width: 28 * widget.k; height: parent.height
                            visible: titleText.implicitWidth > titleText.width
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: lightTheme ? "#F2F2F2" : "#262626" }
                            }
                        }
                    }

                    Item {
                        width: parent.width; height: 14 * widget.k
                        visible: widget.widgetArtist !== ""

                        // Icon of the app that is playing (Spotify, YT Music, Bluetooth, radio...)
                        // in place of the old wave, in grayscale (not colored).
                        Image {
                            id: appSrcIcon
                            readonly property string _app: widget.srcIcon(widget.audioSrc)
                            source: _app !== "" ? _app : "qrc:/VoltaApp/icons/wave.svg"
                            sourceSize: Qt.size(width, height)
                            fillMode: Image.PreserveAspectFit
                            width: 12 * widget.k; height: 12 * widget.k
                            anchors.verticalCenter: parent.verticalCenter
                            opacity: _app !== "" ? 0.6 : 0.22
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                saturation: -1.0
                                colorization: appSrcIcon._app !== "" ? 0.0 : (lightTheme ? 1.0 : 0.0)
                                colorizationColor: Qt.rgba(0.05,0.05,0.08,1)
                            }
                        }
                        Text {
                            id: artistText
                            anchors.left: parent.left; anchors.leftMargin: 16 * widget.k
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: widget.widgetArtist
                            color: lightTheme ? "#4D171717" : "#4DFFFFFF"; font.pixelSize: 11 * widget.k; font.weight: Font.Medium
                            clip: true; elide: Text.ElideNone
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.top: parent.top
                            width: 28 * widget.k; height: parent.height
                            visible: artistText.implicitWidth > artistText.width
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: lightTheme ? "#F2F2F2" : "#262626" }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: progressRow
            // on the boundary between the top band and the controls band
            y: widget.artH - height / 2
            z: 2
            width: parent.width; height: 6 * widget.k

            // the line is as wide as the whole miniplayer; the knob always sits at the
            // end of the filled part (only at the extremes 0% / 100% is it kept inside
            // the widget, so there it moves by at most half a knob)
            readonly property real m: 0
            readonly property real trackW: Math.max(1, width - 2 * m)
            Rectangle {
                x: progressRow.m; width: progressRow.trackW
                anchors.top: parent.top; anchors.bottom: parent.bottom
                anchors.topMargin: 2 * widget.k; anchors.bottomMargin: 2 * widget.k
                color: lightTheme ? "#18171717" : "#18FFFFFF"; radius: 1
            }
            // While dragging the bar follows the finger; the real
            // seek happens on release.
            property bool dragging: false
            property real dragPct: 0
            property bool holding: false     // after release, until the real position arrives
            readonly property real shownPct: (dragging || holding) ? dragPct * 100 : widget.progressPct
            Timer { id: seekHold; interval: 1200; onTriggered: progressRow.holding = false }

            Rectangle {
                id: progressFill
                x: progressRow.m
                y: 2 * widget.k; height: 2 * widget.k; radius: 1
                width: progressRow.trackW * (Math.max(0, Math.min(100, progressRow.shownPct)) / 100)
                color: lightTheme ? "#DD171717" : "#DDFFFFFF"
                Behavior on width { enabled: !progressRow.dragging && !progressRow.holding; NumberAnimation { duration: 300; easing.type: Easing.Linear } }
            }
            // Pallino trascinabile
            Rectangle {
                id: seekKnob
                readonly property real d: (progressRow.dragging ? 14 : 10) * widget.k
                width: d; height: d; radius: d / 2
                x: Math.max(0, Math.min(progressRow.width - width, progressFill.x + progressFill.width - width / 2))
                anchors.verticalCenter: progressFill.verticalCenter
                color: lightTheme ? "#171717" : "#FFFFFF"
                border.width: lightTheme ? 0 : 1
                border.color: "#33000000"
                visible: widget.durationSec > 0 && widget.canSeek
                // no animation of its own on x: it follows the filled bar, so it does not detach
                Behavior on width { NumberAnimation { duration: 120 } }
            }

            MouseArea {
                id: seekMouseArea
                // Touch area taller than the bar (6px) to catch
                // the knob easily with a finger
                anchors.fill: parent
                anchors.topMargin: -12; anchors.bottomMargin: -10
                preventStealing: true
                enabled: widget.durationSec > 0 && widget.canSeek
                function pctAt(mx) { return Math.max(0, Math.min(1, (mx - progressRow.m) / progressRow.trackW)) }
                onPressed: function(mouse) {
                    progressRow.dragPct = pctAt(mouse.x)
                    progressRow.dragging = true
                }
                onPositionChanged: function(mouse) {
                    if (pressed) progressRow.dragPct = pctAt(mouse.x)
                }
                onReleased: function(mouse) {
                    var p = pctAt(mouse.x)
                    progressRow.dragPct = p
                    progressRow.holding = true         // stays there until the real position arrives
                    seekHold.restart()
                    progressRow.dragging = false
                    widget.seek(p)
                }
                onCanceled: progressRow.dragging = false
            }
        }

        // Shuffle and Repeat: in the top row, to the right of title/artist
        Row {
            id: srRow
            visible: widget.modesAvailable
            // Aligned to the columns of the bottom buttons: Shuffle above EQ, Repeat above Search
            // (same grid: 6 columns with 12 px at the sides)
            readonly property real colW: widget.width / 6
            anchors.right: parent.right; anchors.rightMargin: 0
            y: (widget.artH - height) / 2
            height: 34 * widget.k; spacing: 0

            component SrBtn: Rectangle {
                property string src
                property bool active: false
                signal clicked()
                width: srRow.colW; height: 34 * widget.k; radius: 8 * widget.k
                color: _srMA.pressed ? (lightTheme ? "#20000000" : "#20FFFFFF") : "transparent"
                id: _sb
                property string badge: ""
                // Acceso = bianco pieno (nero col tema chiaro), spento = grigio
                readonly property color onCol:  lightTheme ? "#000000" : "#FFFFFF"
                readonly property color offCol: lightTheme ? "#A8A8A8" : "#7C7D80"
                Image {
                    anchors.centerIn: parent
                    source: _sb.src
                    // Lucide icons fill 92% of the box, EQ/Search only 57-67%:
                    // 14 px box = glyph ~13 px, i.e. like EQ
                    width: 14 * widget.k; height: 14 * widget.k
                    sourceSize: Qt.size(width * 2, height * 2)
                    layer.enabled: true
                    layer.smooth: true
                    layer.effect: MultiEffect { colorization: 1.0; colorizationColor: _sb.active ? _sb.onCol : _sb.offCol }
                }
                Text {
                    visible: _sb.badge !== ""
                    x: parent.width / 2 + 6 * widget.k; y: 6 * widget.k
                    text: _sb.badge; color: _sb.onCol; font.pixelSize: 9 * widget.k; font.weight: Font.Bold
                }
                MouseArea { id: _srMA; anchors.fill: parent; preventStealing: true; onClicked: _sb.clicked() }
            }

            SrBtn { visible: widget.lyricsAvailable; src: "qrc:/VoltaApp/icons/lyrics.svg"; active: widget.lyricsOn; onClicked: widget.openLyrics() }
            SrBtn { src: "qrc:/VoltaApp/icons/shuffle.svg"; active: widget.shuffleOn; onClicked: widget.shuffle() }
            SrBtn {
                src: "qrc:/VoltaApp/icons/repeat.svg"
                active: widget.repeatMode !== "off"
                badge: widget.repeatMode === "one" ? "1" : ""
                onClicked: widget.repeat()
            }
        }

        Item {
            // controls band of the wireframe: 393x49, all icons centered in width
            y: widget.artH
            width: parent.width; height: widget.baseH - widget.artH

            Row {
                id: controlsRow
                anchors.fill: parent
                spacing: 0

                readonly property real btnW: width / 6

                component WidgetBtn: Rectangle {
                    property string src
                    property bool isLike: false
                    property bool isSearch: false
                    property string label: ""
                    property bool flip: false
                    property bool lit: false
                    property bool big: false
                    property bool dimmed: false         // off: light gray and not clickable
                    property bool isStop: false         // "stop" square in place of the icon
                    property real activeOpacity: 0.85   // for shuffle/repeat: on/off state
                    signal clicked()

                    width: controlsRow.btnW; height: controlsRow.height
                    radius: 8 * widget.k
                    color: (_btnMA.pressed && !dimmed) ? (lightTheme ? "#20000000" : "#20FFFFFF") : "transparent"

                    Rectangle {      // quadrato "stop" (radio in onda)
                        visible: parent.isStop
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 2 * widget.k
                        width: 15 * widget.k; height: 15 * widget.k; radius: 2.5 * widget.k
                        color: lightTheme ? Qt.rgba(0.05, 0.05, 0.08, 1) : "#FFFFFF"
                    }

                    Image {
                        visible: !parent.isSearch && parent.src !== "" && !parent.isStop
                        mirror: parent.flip
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 2 * widget.k   // icon center of the wireframe: 2 px below the band center
                        source: parent.src
                        width: (parent.big ? 27 : (parent.isLike ? 18.5 : 19.5)) * widget.k
                        height: (parent.big ? 27 : (parent.isLike ? 18.5 : 19.5)) * widget.k
                        sourceSize: Qt.size(width, height)
                        layer.smooth: true
                        opacity: 1.0
                        layer.enabled: true
                        layer.effect: MultiEffect { colorization: 1.0; colorizationColor: lightTheme ? Qt.rgba(0.05,0.05,0.08,1) : "#FFFFFF" }
                    }

                    Image {
                        visible: parent.isSearch
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 2 * widget.k
                        source: "qrc:/VoltaApp/icons/search_w.svg"
                        width: 19.5 * widget.k; height: 19.5 * widget.k
                        sourceSize: Qt.size(width, height)
                        layer.smooth: true
                        opacity: 1.0
                        layer.enabled: true
                        layer.effect: MultiEffect { colorization: 1.0; colorizationColor: lightTheme ? Qt.rgba(0.05,0.05,0.08,1) : "#FFFFFF" }
                    }

                    Text {
                        visible: parent.label !== ""
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: (parent.src !== "" ? 3 : 2) * widget.k
                        text: parent.label
                        color: parent.lit ? "#A855F7" : (lightTheme ? "#0D0D14" : "#FFFFFF")
                        font.pixelSize: (parent.src !== "" ? 7.5 : 14) * widget.k
                        font.weight: Font.Bold
                    }
                    MouseArea {
                        id: _btnMA
                        anchors.fill: parent
                        preventStealing: true
                        enabled: !parent.dimmed
                        onClicked: parent.clicked()
                    }
                }

                WidgetBtn { src: "qrc:/VoltaApp/icons/skip-back.svg"; dimmed: widget.isRadio; opacity: widget.isRadio ? 0.28 : 1.0; onClicked: widget.prev() }
                WidgetBtn { visible: widget.podcastMode; src: "qrc:/VoltaApp/icons/rewind-15.svg"; big: true; onClicked: widget.podcastSkip(-15) }
                WidgetBtn { src: widget.isPlaying ? "qrc:/VoltaApp/icons/pause.svg" : "qrc:/VoltaApp/icons/play.svg"
                            isStop: widget.isRadio && widget.isPlaying; onClicked: widget.playPause() }
                WidgetBtn { visible: widget.podcastMode; src: "qrc:/VoltaApp/icons/forward-30.svg"; big: true; onClicked: widget.podcastSkip(30) }
                WidgetBtn { src: "qrc:/VoltaApp/icons/skip-forward.svg"; dimmed: widget.isRadio; opacity: widget.isRadio ? 0.28 : 1.0; onClicked: widget.next() }
                WidgetBtn { visible: widget.podcastMode; label: widget.podcastSpeedText; lit: widget.podcastSpeedText !== "1×"; onClicked: widget.podcastSpeed() }
                WidgetBtn {
                    isLike: true
                    visible: !widget.podcastMode
                    src: widget.isLiked ? "qrc:/VoltaApp/icons/heart-full.svg" : "qrc:/VoltaApp/icons/heart-empty.svg"
                    onClicked: widget.like()
                }
                WidgetBtn { id: eqBtn; visible: !widget.podcastMode; src: "qrc:/VoltaApp/icons/eq_w.svg"; onClicked: widget.openEqualizer() }
                WidgetBtn { id: searchBtn; visible: !widget.podcastMode; isSearch: true; onClicked: widget.openSearch() }
            }
        }
    }
}