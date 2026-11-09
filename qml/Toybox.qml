import QtQuick
import QtQuick.Window
import VoltaApp 1.0

// TOYBOX — same interface as Arcade (big box at the top, row of
// vertical cards below). Unlike Arcade the box at the top is not a
// banner with "Launch": it immediately shows the function of the selected card
// (e.g. Emissions). Also reachable from the Theater / Arcade / Toybox menu.
//
// Card covers: volta_os/assets/toybox/<key>.png
// (e.g. emissioni.png). Without an image the card shows the name.
Rectangle {
    id: toybox
    color: lightTheme ? "#FFFFFF" : "#171717"
    clip: true

    property bool lightTheme: false
    property bool active: false

    // Top menu: same conventions as Theater/Arcade
    signal switchToTheater()
    signal switchToArcade()
    // Colorizer: chosen color and paint (AppPanel forwards them to the 3D car)
    signal carColorPicked(string hex)
    signal carFinishPicked(string finish)
    // Full screen (Romance, Album) and global modes (Mars)
    signal requestFullscreen(bool on)
    property bool marsMode: false
    signal marsModeRequested(bool on)

    readonly property string coverBase: appUrl + "/assets/toybox/"

    // Available functions; cards without a key are placeholders for the future
    property var items: [
        { key: "emissioni", name: qsTr("Emissions") },
        { key: "colorizer", name: "Colorizer" },
        { key: "romance",   name: "Romance" },
        { key: "album",     name: "Album" },
        { key: "marte",     name: "Mars" }
    ]
    property int selectedIdx: 0
    readonly property string selectedKey: items[selectedIdx] ? items[selectedIdx].key : ""

    // Exposed to AppPanel: when true (Romance fireplace open) the handle pill
    // at the top must be hidden for a real full-screen display,
    // edge to edge.
    readonly property bool immersiveActive: false
    // The fireplace is a separate screen (Main.qml), above everything: the panel never changes
    signal romanceRequested()

    readonly property color tileEmpty:  lightTheme ? "#E2E2E2" : "#222222"
    readonly property color tileBorder: lightTheme ? "#DDDDDD" : "#242424"

    // ══════════════════════════════════════════════════════════════════════
    //  HEADER BAR — identical to Arcade
    // ══════════════════════════════════════════════════════════════════════
    Item {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 20
        height: 26
        z: 50

        Image {
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            source: "qrc:/VoltaApp/icons/toybox.svg"
            sourceSize: Qt.size(26, 26)
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: 18

            Text {
                text: qsTr("Theater")
                color: lightTheme ? "#444444" : "#A2A3A5"
                font.pixelSize: 20; font.weight: Font.DemiBold
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    onClicked: toybox.switchToTheater()
                }
            }
            Text {
                text: "Arcade"
                color: lightTheme ? "#444444" : "#A2A3A5"
                font.pixelSize: 20; font.weight: Font.DemiBold
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    onClicked: toybox.switchToArcade()
                }
            }
            Text {
                text: qsTr("Toybox")
                color: lightTheme ? "#171717" : "#FFFFFF"
                font.pixelSize: 20; font.weight: Font.DemiBold
                // No MouseArea: we are already on Toybox.
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    //  LAUNCHER — big photo + button + row of cards (like Arcade)
    // ══════════════════════════════════════════════════════════════════════
    // The launcher stays STILL when the fireplace opens/closes: the app panel goes full
    // screen (and back to normal) but the Toybox cards must not resize.
    property bool launcherFrozen: false
    property real _frozenW: 0
    property real _frozenH: 0
    function freezeLauncher() {
        unfreezeTimer.stop()
        _frozenW = launcher.width; _frozenH = launcher.height
        launcherFrozen = true
    }
    Timer { id: unfreezeTimer; interval: 800; onTriggered: toybox.launcherFrozen = false }

    Item {
        id: launcher
        x: 0; y: 0
        width: toybox.launcherFrozen ? toybox._frozenW : toybox.width
        height: toybox.launcherFrozen ? toybox._frozenH : toybox.height

        readonly property real cardRowH: 224

        // ── Big box: the function of the selected card ──
        Item {
            id: hero
            z: 2        // above the row of cards: the sound list can go down that far
            anchors.top: parent.top
            anchors.topMargin: 66
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 40
            height: parent.height - launcher.cardRowH - 30 - 56

            // Emissions: the settings right away, without a banner
            ToyboxEmissions {
                anchors.fill: parent
                visible: toybox.selectedKey === "emissioni"
                lightTheme: toybox.lightTheme
                extraBelow: launcher.cardRowH
            }

            // Colorizer: banner like Arcade, "Customize" opens the window
            ToyboxColorizer {
                anchors.fill: parent
                visible: toybox.selectedKey === "colorizer"
                lightTheme: toybox.lightTheme
                coverBase: toybox.coverBase
                onCustomize: colorizerPopup.open()
            }

            ToyboxBanner {
                anchors.fill: parent
                visible: toybox.selectedKey === "romance"
                lightTheme: toybox.lightTheme; coverBase: toybox.coverBase
                key: "romance"; accent: "#C0561B"
                title: qsTr("Romance mode")
                description: qsTr("Set the right mood with a crackling fireplace on the full screen.")
                buttonText: qsTr("Light the fireplace")
                onButtonClicked: toybox.romanceRequested()
            }

            ToyboxBanner {
                anchors.fill: parent
                visible: toybox.selectedKey === "album"
                lightTheme: toybox.lightTheme; coverBase: toybox.coverBase
                key: "album"; accent: "#3B3F8F"
                title: "Album"
                description: qsTr("Unleash your inner Picasso and share your creations with the critics. Participation is optional.")
                buttonText: qsTr("Draw")
                onButtonClicked: albumView.open()       // not full screen
            }

            ToyboxBanner {
                anchors.fill: parent
                visible: toybox.selectedKey === "marte"
                lightTheme: toybox.lightTheme; coverBase: toybox.coverBase
                key: "marte"; accent: "#8A3B1E"
                title: qsTr("Mars")
                description: qsTr("Turn your map into a map of Mars.")
                toggleText: qsTr("Multi-planetary species")
                toggleChecked: toybox.marsMode
                onToggled: on => toybox.marsModeRequested(on)
            }

            // Placeholder for cards not yet available
            Rectangle {
                anchors.fill: parent
                radius: 8
                visible: toybox.selectedKey === ""
                color: toybox.tileEmpty
                Text {
                    anchors.centerIn: parent
                    text: qsTr("Coming up")
                    color: lightTheme ? "#9A9A9A" : "#6E6F71"
                    font.pixelSize: 18
                }
            }
        }

        // ── Row of vertical cards ──
        ListView {
            id: cardRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            anchors.leftMargin: 20
            height: launcher.cardRowH - 30
            orientation: ListView.Horizontal
            spacing: 16
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: toybox.items

            delegate: Item {
                width: 132; height: cardRow.height
                Rectangle {
                    id: _card
                    anchors.fill: parent
                    radius: 7
                    color: toybox.tileEmpty
                    clip: true

                    // Cover from the toybox/ folder, if present
                    MediaCover {
                        anchors.fill: parent; anchors.margins: 1
                        radius: 6
                        visible: modelData.key !== ""
                        source: modelData.key !== "" ? toybox.coverBase + (modelData.cover ? modelData.cover : modelData.key + ".png") : ""
                    }
                    // Dark gradient at the bottom to read the title over the cover
                    Rectangle {
                        visible: _coverProbe.ok
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        anchors.margins: 1
                        height: 56; radius: 6
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#00000000" }
                            GradientStop { position: 1.0; color: "#B3000000" }
                        }
                    }
                    // Titolo in basso a sinistra
                    Text {
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                        anchors.left: parent.left; anchors.leftMargin: 12
                        width: Math.min(implicitWidth, parent.width - 20)
                        horizontalAlignment: Text.AlignLeft
                        elide: Text.ElideRight
                        visible: modelData.key !== ""
                        text: modelData.name
                        color: _coverProbe.ok ? "#FFFFFF" : (lightTheme ? "#171717" : "#F0F0F0")
                        font.pixelSize: 14; font.weight: Font.DemiBold
                        style: _coverProbe.ok ? Text.Raised : Text.Normal
                        styleColor: "#80000000"
                    }
                    Image {
                        id: _coverProbe
                        visible: false
                        source: modelData.key !== "" ? toybox.coverBase + (modelData.cover ? modelData.cover : modelData.key + ".png") : ""
                        readonly property bool ok: status === Image.Ready
                    }
                    scale: _tMA.pressed ? 0.97 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    // Selected card: no colored border, the poster
                    // becomes slightly lighter/whitish under a
                    // velo bianco semitrasparente.
                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        anchors.margins: 1
                        color: "#FFFFFF"
                        opacity: index === toybox.selectedIdx ? 0.22 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    // Border above the cover (otherwise the image would cover it)
                    Rectangle {
                        anchors.fill: parent
                        radius: 7
                        color: "transparent"
                        border.width: 1
                        border.color: toybox.tileBorder
                    }

                    MouseArea {
                        id: _tMA
                        anchors.fill: parent
                        onClicked: toybox.selectedIdx = index
                    }
                }
            }
        }
    }

    // Colorizer window (above all the Toybox)
    ColorizerPopup {
        id: colorizerPopup
        lightTheme: toybox.lightTheme
        onColorPicked: hex => toybox.carColorPicked(hex)
        onFinishPicked: f => toybox.carFinishPicked(f)
    }
    onActiveChanged: if (!active) closeOverlays()

    // ── Full-screen screens ──
    ToyboxAlbum {
        id: albumView
        anchors.fill: parent; z: 900
        lightTheme: toybox.lightTheme
    }
    // When the Toybox is closed (another app or panel closed) fireplace and album
    // close: reopening it starts again from the launcher.
    function closeOverlays() {
        if (albumView.visible) albumView.close()
        colorizerPopup.close()
    }
    onVisibleChanged: if (!visible) closeOverlays()
}
