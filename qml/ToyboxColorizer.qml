import QtQuick
import Qt5Compat.GraphicalEffects
import VoltaApp 1.0

// TOYBOX › COLORIZER — banner in stile Arcade: immagine grande, titolo,
// description and blue "Customize" button that opens the Colorizer window.
// Immagine: volta_os/assets/toybox/colorizer_hero.png
// (if missing it uses colorizer.png, otherwise an illustration drawn here).
Item {
    id: cb

    property bool lightTheme: false
    property string coverBase: appUrl + "/assets/toybox/"

    signal customize()

    // ── Background: image or illustration ──
    Rectangle {
        id: bgRect
        anchors.fill: parent
        radius: 8
        color: cb.lightTheme ? "#E6E6E6" : "#141414"
    }

    Image {
        id: heroImg
        anchors.fill: parent
        source: Files.exists(cb.coverBase + "colorizer_hero.png") ? cb.coverBase + "colorizer_hero.png" : ""
        fillMode: Image.PreserveAspectCrop
        visible: false
        smooth: true
    }
    Image {
        id: heroFallback
        anchors.fill: parent
        source: (heroImg.source.toString() === "" || heroImg.status === Image.Error) ? cb.coverBase + "colorizer.png" : ""
        fillMode: Image.PreserveAspectCrop
        visible: false
        smooth: true
    }
    OpacityMask {
        anchors.fill: parent
        source: heroImg.status === Image.Ready ? heroImg : heroFallback
        maskSource: bgRect
        visible: heroImg.status === Image.Ready || heroFallback.status === Image.Ready
    }

    // Illustration (only without an image): donut and square as in the window
    Item {
        anchors.fill: parent
        visible: heroImg.status !== Image.Ready && heroFallback.status !== Image.Ready
        opacity: 0.55

        Canvas {
            id: deco
            // Sizes also tied to the width and positions further apart:
            // before, the donut and the square were almost touching
            width: Math.min(parent.height * 0.62, parent.width * 0.28, 300); height: width
            x: parent.width * 0.26 - width / 2; anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -30
            onPaint: {
                var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
                var cx = width / 2, cy = height / 2, r = width / 2 - 16
                ctx.lineWidth = 30
                for (var a = 0; a < 360; a += 1) {
                    ctx.beginPath(); ctx.strokeStyle = Qt.hsva(a / 360.0, 1.0, 0.8, 1.0)
                    ctx.arc(cx, cy, r, (a - 0.6) * Math.PI / 180, (a + 0.6) * Math.PI / 180); ctx.stroke()
                }
            }
            onWidthChanged: requestPaint()
            Component.onCompleted: requestPaint()
        }
        Rectangle {
            width: Math.min(parent.height * 0.6, parent.width * 0.28, 300); height: width * 0.9
            anchors.right: parent.right; anchors.rightMargin: parent.width * 0.05
            anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: -30
            radius: 8
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#FFFFFF" }
                GradientStop { position: 1.0; color: "#E0142C" }
            }
            Rectangle {
                anchors.fill: parent; radius: 8
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00000000" }
                    GradientStop { position: 1.0; color: "#FF000000" }
                }
            }
        }
    }

    // Dark veil on the left to read the text (as in the photo)
    Rectangle {
        anchors.fill: parent; radius: 8
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;  color: "#E6000000" }
            GradientStop { position: 0.45; color: "#80000000" }
            GradientStop { position: 0.75; color: "#00000000" }
        }
    }

    // ── Title, description, blue button ──
    Column {
        anchors.left: parent.left; anchors.leftMargin: 44
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -24
        width: Math.min(380, parent.width * 0.45)
        spacing: 12

        Text {
            text: qsTr("Colorizer")
            color: "#FFFFFF"; font.pixelSize: 30; font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            text: qsTr("Change the color of the vehicle's exterior and adjust the paint style.")
            color: "#E0E0E0"; font.pixelSize: 15
            wrapMode: Text.WordWrap
        }
        Item { width: 1; height: 6 }
        Rectangle {
            width: 210; height: 52; radius: 8
            color: _custMA.pressed ? "#1E63D0" : "#2C7BF2"
            Behavior on color { ColorAnimation { duration: 100 } }
            Text {
                anchors.centerIn: parent
                text: qsTr("Customize")
                color: "#FFFFFF"; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            MouseArea { id: _custMA; anchors.fill: parent; onClicked: cb.customize() }
        }
    }
}
