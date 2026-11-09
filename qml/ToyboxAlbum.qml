import QtQuick
import QtQuick.Effects
import VoltaApp 1.0

// ─────────────────────────────────────────────────────────────────────────────
//  TOYBOX › ALBUM — full-screen freehand drawing.
//  Top bar: Marker / Eraser · color · size
//  ‹ 12 › · Publish (saves the drawing) · Undo · Fill · Exit.
//  I disegni pubblicati finiscono in volta_os/data/album/
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: al
    color: lightTheme ? "#F2F2F2" : "#000000"
    visible: false

    property bool lightTheme: false
    readonly property string albumDir: appDir + "/data/album"

    // Interface colors (toolbar/pop-up), readapted based
    // to the theme; the drawing CANVAS (bgColor) instead follows the user's last "Fill"
    // and is reset to the base color only if the
    // drawing is still empty (see open()).
    readonly property color uiBg:      lightTheme ? "#E6E6E6" : "#1C1C1C"
    readonly property color uiBg2:     lightTheme ? "#D6D6D6" : "#262626"
    readonly property color uiBtnSel:  lightTheme ? "#B6B6B6" : "#4A4A4A"
    readonly property color uiBtnPress:lightTheme ? "#C9C9C9" : "#333333"
    readonly property color uiText:    lightTheme ? "#171717" : "#FFFFFF"
    readonly property color uiPop:     lightTheme ? "#EDEDED" : "#2A2A2A"
    readonly property color uiPopBrd:  lightTheme ? "#CACACA" : "#3A3A3A"

    signal closed()

    // Strumento e stile
    property string tool: "pen"            // "pen" | "eraser"
    property color penColor: "#FFFFFF"
    property int penSize: 12
    property color bgColor: "#000000"      // background color ("Fill")

    // History for "Undo": strokes and fills in the order
    // { type: "stroke", tool, color, size, pts: [x,y,x,y,...] } | { type: "fill", color, prev }
    property var history: []
    property var _current: null
    property bool _fullRedraw: true
    property string toast: ""

    readonly property var swatchColors: [
        "#FFFFFF", "#9E9E9E", "#424242", "#000000", "#E53935", "#FF7043",
        "#FFB300", "#FDD835", "#C0CA33", "#43A047", "#00ACC1", "#1E88E5",
        "#3949AB", "#8E24AA", "#D81B60", "#F48FB1", "#8D6E63", "#E8C9A0"
    ]

    SystemHelper { id: sysHelper }

    function open() {
        sysHelper.runDetached("/bin/mkdir", ["-p", al.albumDir])
        // Canvas still empty (no drawing in progress): restarts from the
        // base color right for the current theme (white sheet in light,
        // black board in dark) instead of always staying black.
        if (al.history.length === 0) {
            al.bgColor = al.lightTheme ? "#FFFFFF" : "#000000"
            al.penColor = al.lightTheme ? "#171717" : "#FFFFFF"
        }
        al.visible = true
        al._fullRedraw = true
        canvas.requestPaint()
    }
    function close() {
        colorPop.visible = false
        al.visible = false
        al.closed()
    }
    function undo() {
        if (al.history.length === 0) return
        var h = al.history.slice()
        var last = h.pop()
        if (last.type === "fill") al.bgColor = last.prev
        al.history = h
        al._fullRedraw = true
        canvas.requestPaint()
    }
    function fill() {
        al.history = al.history.concat([{ type: "fill", color: al.penColor, prev: al.bgColor }])
        al.bgColor = al.penColor
    }
    function publish() {
        colorPop.visible = false
        var name = "disegno_" + Qt.formatDateTime(new Date(), "yyyyMMdd_HHmmss") + ".png"
        drawArea.grabToImage(function(result) {
            // the folder is created a moment before; retry if needed
            var ok = result.saveToFile(al.albumDir + "/" + name)
            if (!ok) ok = result.saveToFile(al.albumDir + "/" + name)
            al.toast = ok ? qsTr("Drawing saved to the album") : qsTr("Unable to save the drawing")
            toastTimer.restart()
        })
    }

    function _drawStroke(ctx, st, fromIdx) {
        ctx.globalCompositeOperation = st.tool === "eraser" ? "destination-out" : "source-over"
        ctx.strokeStyle = st.tool === "eraser" ? "#000000" : st.color
        ctx.fillStyle = ctx.strokeStyle
        ctx.lineWidth = st.size
        ctx.lineCap = "round"; ctx.lineJoin = "round"
        var p = st.pts
        if (p.length === 2) {                       // single tap: a dot
            ctx.beginPath(); ctx.arc(p[0], p[1], st.size / 2, 0, 2 * Math.PI); ctx.fill()
            return
        }
        var start = Math.max(0, fromIdx - 2)
        ctx.beginPath()
        ctx.moveTo(p[start], p[start + 1])
        for (var i = start + 2; i < p.length; i += 2) ctx.lineTo(p[i], p[i + 1])
        ctx.stroke()
    }

    // ── Drawing area (background + strokes) ──
    Item {
        id: drawArea
        anchors.fill: parent
        anchors.topMargin: toolbar.height

        Rectangle { anchors.fill: parent; color: al.bgColor }

        Canvas {
            id: canvas
            anchors.fill: parent
            renderStrategy: Canvas.Immediate
            property int _drawnUpTo: 0
            onPaint: {
                var ctx = getContext("2d")
                if (al._fullRedraw) {
                    ctx.globalCompositeOperation = "source-over"
                    ctx.clearRect(0, 0, width, height)
                    for (var i = 0; i < al.history.length; i++)
                        if (al.history[i].type === "stroke") al._drawStroke(ctx, al.history[i], 0)
                    if (al._current) al._drawStroke(ctx, al._current, 0)
                    al._fullRedraw = false
                    _drawnUpTo = al._current ? al._current.pts.length : 0
                } else if (al._current) {
                    al._drawStroke(ctx, al._current, _drawnUpTo)
                    _drawnUpTo = al._current.pts.length
                }
            }
            onWidthChanged: { al._fullRedraw = true; requestPaint() }
            onHeightChanged: { al._fullRedraw = true; requestPaint() }
        }

        MouseArea {
            anchors.fill: parent
            preventStealing: true
            onPressed: (m) => {
                colorPop.visible = false
                al._current = { type: "stroke", tool: al.tool, color: al.penColor.toString(), size: al.penSize, pts: [m.x, m.y] }
                canvas._drawnUpTo = 0
                canvas.requestPaint()
            }
            onPositionChanged: (m) => {
                if (!al._current) return
                al._current.pts.push(m.x, m.y)
                canvas.requestPaint()
            }
            onReleased: {
                if (!al._current) return
                al.history = al.history.concat([al._current])
                al._current = null
            }
        }
    }

    // ── Toolbar ──
    component ToolBtn: Rectangle {
        id: tb
        property string label
        property bool selected: false
        property bool enabledBtn: true
        signal clicked()
        height: 44; width: Math.max(88, _tbT.implicitWidth + 28); radius: 8
        color: selected ? al.uiBtnSel : (_tbMA.pressed ? al.uiBtnPress : "transparent")
        opacity: enabledBtn ? 1 : 0.4
        Text {
            id: _tbT
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 12)
            horizontalAlignment: Text.AlignHCenter
            text: tb.label; color: al.uiText
            font.pixelSize: 14; font.weight: tb.selected ? Font.DemiBold : Font.Medium
            wrapMode: Text.WordWrap; maximumLineCount: 2
        }
        MouseArea { id: _tbMA; anchors.fill: parent; enabled: tb.enabledBtn; onClicked: tb.clicked() }
    }

    Rectangle {
        id: toolbar
        width: parent.width; height: 68
        color: al.uiBg
        z: 10

        Row {
            anchors.left: parent.left; anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            // Pennarello / Gomma
            Rectangle {
                width: _toolsRow.width + 8; height: 52; radius: 8
                color: al.uiBg2
                anchors.verticalCenter: parent.verticalCenter
                Row {
                    id: _toolsRow
                    anchors.centerIn: parent; spacing: 4
                    ToolBtn { label: qsTr("Marker"); selected: al.tool === "pen"; onClicked: al.tool = "pen" }
                    ToolBtn { label: qsTr("Eraser"); selected: al.tool === "eraser"; onClicked: al.tool = "eraser" }
                }
            }

            // Color
            Rectangle {
                id: colorBtn
                width: 44; height: 30; radius: 8
                anchors.verticalCenter: parent.verticalCenter
                color: al.penColor
                border.width: 2; border.color: al.uiText
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: colorPop.visible = !colorPop.visible }
            }

            // Dimensione ‹ 12 ›
            Rectangle {
                width: 110; height: 44; radius: 8
                color: al.uiBg2
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    text: "‹"; color: al.uiText; font.pixelSize: 26
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: al.penSize = Math.max(2, al.penSize - 2) }
                }
                Text {
                    anchors.centerIn: parent
                    text: al.penSize; color: al.uiText; font.pixelSize: 20; font.weight: Font.DemiBold
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    text: "›"; color: al.uiText; font.pixelSize: 26
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: al.penSize = Math.min(60, al.penSize + 2) }
                }
            }
        }

        Row {
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            ToolBtn { label: qsTr("Publish"); enabledBtn: al.history.length > 0; onClicked: al.publish() }
            ToolBtn { label: qsTr("Cancel"); enabledBtn: al.history.length > 0; onClicked: al.undo() }
            ToolBtn { label: qsTr("Fill"); onClicked: al.fill() }
            ToolBtn { label: qsTr("Sign out"); onClicked: al.close() }
        }
    }

    // ── Tavolozza colori ──
    Rectangle {
        id: colorPop
        visible: false
        z: 20
        x: colorBtn.mapToItem(al, 0, 0).x - 12
        y: toolbar.height + 6
        width: 6 * 44 + 5 * 8 + 24; height: 3 * 44 + 2 * 8 + 24
        radius: 10
        color: al.uiPop
        border.width: 1; border.color: al.uiPopBrd
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowColor: "#80000000"; shadowVerticalOffset: 4 }
        Grid {
            anchors.centerIn: parent
            columns: 6; spacing: 8
            Repeater {
                model: al.swatchColors
                Rectangle {
                    width: 44; height: 44; radius: 8
                    color: modelData
                    border.width: Qt.colorEqual(al.penColor, modelData) ? 3 : 1
                    border.color: Qt.colorEqual(al.penColor, modelData) ? "#2C7BF2" : "#555555"
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { al.penColor = modelData; al.tool = "pen"; colorPop.visible = false }
                    }
                }
            }
        }
    }

    // Messaggio breve
    Rectangle {
        z: 30
        anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottomMargin: 30
        radius: 8; color: "#CC000000"
        width: _toastT.implicitWidth + 28; height: 40
        visible: al.toast !== ""
        Text { id: _toastT; anchors.centerIn: parent; text: al.toast; color: "#FFFFFF"; font.pixelSize: 14 }
        Timer { id: toastTimer; interval: 2500; onTriggered: al.toast = "" }
    }
}
