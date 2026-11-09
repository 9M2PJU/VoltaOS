import QtQuick

// Bar at the top of full-screen screens (Theater apps, fireplace): identical to the one in
// the games — back button on the left, gray pill in the center. Dragging the pill
// downward closes, like the apps' handle.
Rectangle {
    id: bar
    height: 30
    color: "#000000"
    signal backRequested()

    // pillola dell'handle
    Rectangle { width: 84; height: 2.5; radius: 10; color: "#8A8B8D"; anchors.centerIn: parent }
    MouseArea {
        anchors.fill: parent; anchors.leftMargin: 50
        property real y0: 0
        onPressed: mouse => y0 = mouse.y
        onPositionChanged: mouse => { if (mouse.y - y0 > 36) { y0 = 1e9; bar.backRequested() } }
    }

    Rectangle {
        x: 0; y: 0; width: 44; height: 30
        color: _bm.pressed ? "#33FFFFFF" : "transparent"
        Canvas {
            anchors.centerIn: parent
            width: 22; height: 22
            onPaint: {
                var ctx = getContext("2d")
                var s = width / 24.0
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = "#FFFFFF"; ctx.lineWidth = 2 * s
                ctx.lineCap = "round"; ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(14 * s, 4 * s); ctx.lineTo(14 * s, 8 * s)
                ctx.quadraticCurveTo(14 * s, 10 * s, 16 * s, 10 * s); ctx.lineTo(20 * s, 10 * s)
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(4 * s, 14 * s); ctx.lineTo(8 * s, 14 * s)
                ctx.quadraticCurveTo(10 * s, 14 * s, 10 * s, 16 * s); ctx.lineTo(10 * s, 20 * s)
                ctx.stroke()
            }
        }
        MouseArea { id: _bm; anchors.fill: parent; onClicked: bar.backRequested() }
    }
}
