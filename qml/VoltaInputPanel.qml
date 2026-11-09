// On-screen keyboard — 1:1 layout from the SVG supplied by the user (canvas 1920 x 600,
// panel 500 px high from y = 53 to y = 553).
//
// The whole drawing lives in the SVG's coordinate space ("kb", 1920 x 600) and
// is scaled as a block with root.width / 1920: sizes, spaces, radii (7 px),
// icons and texts therefore stay proportional at any screen width.
// The key text is real text (not outlines), with height/weight taken from the
// SVG: cifre e lettere 36 px DemiBold, "Enter" 22 px, "? # &" 20 px.
//
// Text input goes through the Qt Virtual Keyboard engine
// ("InputContext"), as before: the keyboard attaches by itself to any text
// field with focus ("Qt.inputMethod.visible").
//
// Differences from the SVG (functions that already existed and that the SVG does not show):
//   • language selection: press and hold the space bar (before there was the globe)
//   • "@" and ".com": appear only in the browser's URL bar, shortening the
//     space bar; in the other fields the layout is identical to the SVG.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.VirtualKeyboard
import VoltaApp 1.0

Item {
    id: root

    // ── Stato ────────────────────────────────────────────────────────────
    property bool active: Qt.inputMethod.visible && KeyboardSettings.keyboardEnabled
    property bool symbolMode: false

    // language popup (long press on the space bar) and accents popup
    // (long press on a letter): root-level state, drawn
    // as overlays above all the keys
    property bool langPopupOpen: false
    property var  accentPopupKey: null
    property var  accentPopupVariants: []
    property int  accentPopupHighlight: 0

    // Scale: 1 px of the SVG = s real px. The panel's real height is 500 * s
    // (set by the Loader in Main.qml: width * 500 / 1920).
    readonly property real s: width / 1920
    anchors.left: parent.left
    anchors.right: parent.right
    height: parent.height
    y: active ? 0 : height
    Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    visible: y < height

    property PlainInputMethod plainInputMethod: PlainInputMethod {}

    Component.onCompleted: {
        if (!InputContext.inputEngine.inputMethod)
            InputContext.inputEngine.inputMethod = plainInputMethod
        if (debugMode) console.log("[VKB] VoltaInputPanel caricato — width:", width, "height:", height,
                    qsTr("active iniziale:"), active, "inputMethod impostato:",
                    InputContext.inputEngine.inputMethod !== null)
    }
    onActiveChanged:
        if (debugMode) console.log("[VKB] active ->", active, "(Qt.inputMethod.visible =", Qt.inputMethod.visible, ")")
    Connections {
        target: Qt.inputMethod
        function onVisibleChanged() {
            if (debugMode) console.log("[VKB] Qt.inputMethod.visibleChanged ->", Qt.inputMethod.visible)
        }
    }

    // ── Palette (light = SVG values; dark = as before) ──────────
    readonly property color panelBg:       Theme.light ? "#F0F0F0" : "#1C1C1E"
    readonly property color keyBg:         Theme.light ? "#E0E0E0" : "#3A3A3C"
    readonly property color keyBgPressed:  Theme.light ? "#CFCFCF" : "#57575A"
    readonly property color keyActiveBg:   Theme.light ? "#8E8E96" : "#6E6E72"
    readonly property color keyText:       Theme.light ? "#414141" : "#FFFFFF"
    readonly property color keyTextOnAccent: "#FFFFFF"
    readonly property string fontFamily:   Qt.application.font.family

    // ── SVG measures (px of the 1920 x 600 canvas) ──────────────────────
    readonly property real keyRadius: 7
    readonly property real letterSize: 36
    // sizes of the popups (in SVG space)
    readonly property real accentCellSize: 80
    readonly property real langPopupRowH: 70
    readonly property real langPopupWidth: 640

    // The field with focus: if it is the browser's URL bar we show "@" and ".com".
    readonly property bool isBrowserContext:
        InputContext.inputItem !== null && InputContext.inputItem !== undefined
        && InputContext.inputItem.objectName === "browserUrlBar"

    // ── Popup accenti ─────────────────────────────────────────────────────
    readonly property real accentPopupX: {
        if (!root.accentPopupKey) return 0
        var p = root.accentPopupKey.mapToItem(kb, 0, 0)
        var raw = p.x + root.accentPopupKey.width / 2
                  - (root.accentPopupVariants.length * root.accentCellSize) / 2
        return Math.max(0, Math.min(raw, 1920 - root.accentPopupVariants.length * root.accentCellSize))
    }
    readonly property real accentPopupY: {
        if (!root.accentPopupKey) return 0
        var p = root.accentPopupKey.mapToItem(kb, 0, 0)
        return Math.max(0, p.y - root.accentCellSize - 8)
    }

    function openAccentPopup(keyItem, variants) {
        root.accentPopupKey = keyItem
        root.accentPopupVariants = variants
        root.accentPopupHighlight = 0
    }
    function updateAccentHighlight(xInKb) {
        if (!root.accentPopupKey || root.accentPopupVariants.length === 0) return
        var rel = xInKb - root.accentPopupX
        var idx = Math.floor(rel / root.accentCellSize)
        if (idx < 0) idx = 0
        if (idx > root.accentPopupVariants.length - 1) idx = root.accentPopupVariants.length - 1
        root.accentPopupHighlight = idx
    }
    function commitAccentPopup() {
        if (root.accentPopupKey && root.accentPopupVariants.length > 0) {
            var ch = root.accentPopupVariants[root.accentPopupHighlight]
            InputContext.inputEngine.virtualKeyClick(
                        ch.toUpperCase().charCodeAt(0), ch,
                        InputContext.uppercase ? Qt.ShiftModifier : 0)
        }
        root.accentPopupKey = null
        root.accentPopupVariants = []
    }
    function cancelAccentPopup() {
        root.accentPopupKey = null
        root.accentPopupVariants = []
    }

    function languageName(code) {
        var list = KeyboardSettings.languages
        for (var i = 0; i < list.length; i++)
            if (list[i].code === code) return list[i].name
        return code
    }

    // Light shadow above the panel (in the SVG there is a soft shadow on the top edge)
    Rectangle {
        x: 0; width: root.width
        height: 22 * root.s
        y: -height
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#00000000" }
            GradientStop { position: 1.0; color: Theme.light ? "#22000000" : "#40000000" }
        }
    }

    // Drawing area: SVG coordinates (1920 x 600), scaled as a block. The panel
    // starts at y = 53 of the canvas, so we move it up by 53 * s.
    Item {
        id: kb
        width: 1920
        height: 600
        scale: root.s
        transformOrigin: Item.TopLeft
        y: -53 * root.s

        // Panel (SVG: x 0, y 53, 1921 x 500)
        Rectangle { x: 0; y: 53; width: 1921; height: 500; color: root.panelBg }

        // Safety net: absorbs clicks in the gaps between keys (otherwise the
        // text field loses focus and the keyboard closes by itself).
        MouseArea {
            x: 0; y: 53; width: 1921; height: 500
            onClicked: {}
            onPressed: {}
        }

        // ════════════════════════════════════════════════════════════════
        // Generic key. Position/size in SVG px (x, y, width, height).
        // "boxed" = rettangolo grigio (#E0E0E0, raggio 7). Lettere, cifre e
        // symbols are bare text: "baseline" is the SVG y of the baseline.
        // ════════════════════════════════════════════════════════════════
        component KeyBtn: Item {
            id: keyBtn

            property string baseChar: ""
            readonly property bool isLetterKey: baseChar !== ""
            property string displayChar: ""
            property int  fnKeyCode: 0
            property string fnKeyText: ""
            property string commitText: ""
            property string glyph: ""
            property bool boxed: false
            property real labelSize: root.letterSize
            property int  labelWeight: Font.DemiBold
            property real baseY: 0           // SVG y of the text baseline
            property bool highlighted: false
            property bool repeatable: false
            property var customHandler: null
            property var longPressHandler: null  // pressione prolungata (es. lingua)
            readonly property color fg: highlighted ? root.keyTextOnAccent : root.keyText

            Rectangle {
                visible: keyBtn.boxed
                anchors.fill: parent
                radius: root.keyRadius
                color: keyBtn.highlighted ? root.keyActiveBg
                       : (mouseArea.pressed ? root.keyBgPressed : root.keyBg)
            }

            Text {
                id: lbl
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                y: keyBtn.baseY - keyBtn.y - lbl.baselineOffset
                font.family: root.fontFamily
                font.pixelSize: keyBtn.labelSize
                font.weight: keyBtn.labelWeight
                color: keyBtn.fg
                opacity: (!keyBtn.boxed && mouseArea.pressed) ? 0.4 : 1.0
                text: {
                    if (keyBtn.isLetterKey)
                        return InputContext.uppercase
                                ? keyBtn.baseChar.toUpperCase() : keyBtn.baseChar
                    if (keyBtn.displayChar !== "")
                        return keyBtn.displayChar
                    return keyBtn.glyph
                }
            }

            function activate() {
                if (keyBtn.customHandler !== null) {
                    keyBtn.customHandler()
                } else if (keyBtn.isLetterKey) {
                    var upper = keyBtn.baseChar.toUpperCase()
                    var code = upper.charCodeAt(0)
                    var uc = InputContext.uppercase
                    var text = uc ? upper : keyBtn.baseChar
                    InputContext.inputEngine.virtualKeyClick(code, text, uc ? Qt.ShiftModifier : 0)
                } else if (keyBtn.displayChar !== "") {
                    InputContext.inputEngine.virtualKeyClick(
                                keyBtn.displayChar.charCodeAt(0), keyBtn.displayChar, 0)
                } else if (keyBtn.commitText !== "") {
                    InputContext.commit(keyBtn.commitText)
                } else if (keyBtn.fnKeyCode !== 0) {
                    InputContext.inputEngine.virtualKeyClick(keyBtn.fnKeyCode, keyBtn.fnKeyText, 0)
                }
            }

            function accentVariants() {
                if (!keyBtn.isLetterKey) return []
                var lower = keyBtn.baseChar.toLowerCase()
                var extra = KeyboardSettings.variantsFor(lower)
                if (extra.length === 0) return []
                var uc = InputContext.uppercase
                var list = [uc ? lower.toUpperCase() : lower]
                for (var i = 0; i < extra.length; i++)
                    list.push(uc ? extra[i].toUpperCase() : extra[i])
                return list
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                property bool accentEngaged: false
                property bool longDone: false

                onPressed: {
                    mouseArea.longDone = false
                    if (keyBtn.repeatable) {
                        keyBtn.activate(); repeatDelay.start()
                    } else if (keyBtn.customHandler === null && keyBtn.isLetterKey) {
                        mouseArea.accentEngaged = false
                        var variants = keyBtn.accentVariants()
                        if (variants.length > 0) {
                            accentLongPress.variants = variants
                            accentLongPress.start()
                        }
                    } else if (keyBtn.longPressHandler !== null) {
                        longPressTimer.start()
                    }
                }
                onPositionChanged: (mouse) => {
                    if (mouseArea.accentEngaged) {
                        var p = mouseArea.mapToItem(kb, mouse.x, mouse.y)
                        root.updateAccentHighlight(p.x)
                    }
                }
                onReleased: {
                    repeatDelay.stop(); repeatTimer.stop(); accentLongPress.stop(); longPressTimer.stop()
                    // "accentEngaged" stays true until the next press: it is needed so that
                    // onClicked (which arrives after released) does not also write the
                    // base letter in addition to the confirmed variant.
                    if (mouseArea.accentEngaged) root.commitAccentPopup()
                }
                onCanceled: {
                    repeatDelay.stop(); repeatTimer.stop(); accentLongPress.stop(); longPressTimer.stop()
                    if (mouseArea.accentEngaged) root.cancelAccentPopup()
                }
                onClicked: if (!keyBtn.repeatable && !mouseArea.accentEngaged && !mouseArea.longDone) keyBtn.activate()

                Timer {
                    id: accentLongPress
                    property var variants: []
                    interval: 380
                    onTriggered: {
                        mouseArea.accentEngaged = true
                        root.openAccentPopup(keyBtn, accentLongPress.variants)
                    }
                }
                Timer {
                    id: longPressTimer
                    interval: 500
                    onTriggered: {
                        mouseArea.longDone = true
                        if (keyBtn.longPressHandler) keyBtn.longPressHandler()
                    }
                }
            }
            Timer { id: repeatDelay; interval: 420; onTriggered: repeatTimer.start() }
            Timer { id: repeatTimer; interval: 90; repeat: true; onTriggered: keyBtn.activate() }
        }

        // ── Row 1: q w e r t y u i o p  (centers 130 + 120·i, baseline 159) ──
        Repeater {
            model: root.symbolMode
                   ? ["!","@","#","$","%","^","&","*","(",")"]
                   : ["q","w","e","r","t","y","u","i","o","p"]
            KeyBtn {
                required property string modelData
                required property int index
                x: 70 + 120 * index; y: 96; width: 120; height: 100
                baseY: 159
                baseChar: root.symbolMode ? "" : modelData
                displayChar: root.symbolMode ? modelData : ""
            }
        }
        // Backspace: 192 x 75 a (1291, 108)
        KeyBtn {
            id: backKey
            x: 1291; y: 108; width: 192; height: 75
            boxed: true
            fnKeyCode: Qt.Key_Backspace
            fnKeyText: ""
            repeatable: true
            // ← arrow (30 x 30 icon at (1372, 131))
            Shape {
                x: -backKey.x; y: -backKey.y
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: backKey.fg
                    strokeColor: "transparent"
                    PathSvg { path: "M1385.41 156.413c-.37.375-.88.586-1.41.586s-1.04-.211-1.42-.586l-9-9a2.014 2.014 0 0 1 0-2.828l9-9c.38-.364.89-.565 1.41-.561.53.005 1.03.215 1.4.586s.58.872.58 1.397a1.95 1.95 0 0 1-.56 1.406l-5.41 5.586h19c.53 0 1.04.211 1.41.586.38.375.59.884.59 1.414 0 .531-.21 1.04-.59 1.415-.37.375-.88.585-1.41.585h-19l5.41 5.586a1.985 1.985 0 0 1 0 2.828" }
                }
            }
        }

        // ── Row 2: a s d f g h j k l  (centers 174 + 120·i, baseline 262) ──
        Repeater {
            model: root.symbolMode
                   ? ["?","[","]","{","}",":",";","\"","'"]
                   : ["a","s","d","f","g","h","j","k","l"]
            KeyBtn {
                required property string modelData
                required property int index
                x: 114 + 120 * index; y: 199; width: 120; height: 100
                baseY: 262
                baseChar: root.symbolMode ? "" : modelData
                displayChar: root.symbolMode ? modelData : ""
            }
        }
        // Enter: 219 x 75 at (1218, 211) — "Enter" 22 px, baseline 257
        KeyBtn {
            x: 1218; y: 211; width: 219; height: 75
            boxed: true
            glyph: "Enter"
            labelSize: 22
            baseY: 257
            fnKeyCode: Qt.Key_Return
            fnKeyText: "\n"
        }

        // ── Row 3: z x c v b n m - , .  (centers 231 + 124·i, baseline 365) ──
        Repeater {
            model: root.symbolMode
                   ? ["/","~","_","<",">","=","+","-",",","."]
                   : ["z","x","c","v","b","n","m","-",",","."]
            KeyBtn {
                required property string modelData
                required property int index
                x: 169 + 124 * index; y: 302; width: 124; height: 100
                baseY: 365
                baseChar: (!root.symbolMode && index < 7) ? modelData : ""
                displayChar: (root.symbolMode || index >= 7) ? modelData : ""
            }
        }

        // ── Row 4 ────────────────────────────────────────────
        // Maiuscolo: 182 x 75 a (71, 408)
        KeyBtn {
            id: shiftKey
            x: 71; y: 408; width: 182; height: 75
            boxed: true
            highlighted: InputContext.capsLock || InputContext.shift
            customHandler: function() { InputContext.priv.shiftHandler.toggleShift() }
            Shape {
                x: -shiftKey.x; y: -shiftKey.y
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: shiftKey.fg
                    strokeWidth: 3.125
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "m154.5 449.75 7.5-7.5 7.5 7.5" }
                }
            }
        }
        // Microphone: 111 x 75 at (283, 408) — voice input not connected
        KeyBtn {
            id: micKey
            x: 283; y: 408; width: 111; height: 75
            boxed: true
            Shape {
                x: -micKey.x; y: -micKey.y
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: micKey.fg
                    strokeColor: "transparent"
                    fillRule: ShapePath.OddEvenFill
                    PathSvg { path: "M339.436 432.516a4.22 4.22 0 0 0-4.219 4.218v9.844a4.22 4.22 0 0 0 8.437 0v-9.844a4.22 4.22 0 0 0-4.218-4.218m-5.624 12.656a1.405 1.405 0 1 0-2.812 0v1.406a8.44 8.44 0 0 0 7.031 8.321v1.523h-4.219a1.406 1.406 0 0 0 0 2.812h11.25a1.406 1.406 0 1 0 0-2.812h-4.218v-1.523a8.44 8.44 0 0 0 7.031-8.321v-1.406a1.406 1.406 0 0 0-2.813 0v1.406a5.625 5.625 0 0 1-11.25 0z" }
                }
            }
        }
        // "@" and ".com": only in the browser's URL bar, inside the space bar's
        // space (which shortens accordingly)
        KeyBtn {
            x: 424; y: 408; width: 111; height: 75
            visible: root.isBrowserContext && !root.symbolMode
            boxed: true
            displayChar: "@"
            labelSize: 30
            baseY: 457
        }
        KeyBtn {
            x: 565; y: 408; width: 150; height: 75
            visible: root.isBrowserContext && !root.symbolMode
            boxed: true
            glyph: ".com"
            labelSize: 22
            baseY: 453
            commitText: ".com"
        }
        // Space bar: 619 x 75 at (424, 408); long press = language
        KeyBtn {
            id: spaceKey
            readonly property bool isShort: root.isBrowserContext && !root.symbolMode
            x: isShort ? 745 : 424; y: 408
            width: isShort ? 298 : 619; height: 75
            boxed: true
            fnKeyCode: Qt.Key_Space
            fnKeyText: " "
            longPressHandler: function() { root.langPopupOpen = !root.langPopupOpen }
        }
        // "? # &" / "ABC": 150 x 75 at (1073, 408), 20 px regular text
        KeyBtn {
            x: 1073; y: 408; width: 150; height: 75
            boxed: true
            glyph: root.symbolMode ? "ABC" : "? # &"
            labelSize: 20
            labelWeight: Font.Normal
            baseY: 453
            customHandler: function() { root.symbolMode = !root.symbolMode }
        }
        // ‹  100 x 75 a (1253, 408)
        KeyBtn {
            id: leftKey
            x: 1253; y: 408; width: 100; height: 75
            boxed: true
            fnKeyCode: Qt.Key_Left
            fnKeyText: ""
            repeatable: true
            Shape {
                x: -leftKey.x; y: -leftKey.y
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: leftKey.fg
                    strokeWidth: 3.125
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "m1306.75 453.5-7.5-7.5 7.5-7.5" }
                }
            }
        }
        // ›  100 x 75 a (1383, 408)
        KeyBtn {
            id: rightKey
            x: 1383; y: 408; width: 100; height: 75
            boxed: true
            fnKeyCode: Qt.Key_Right
            fnKeyText: ""
            repeatable: true
            Shape {
                x: -rightKey.x; y: -rightKey.y
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: rightKey.fg
                    strokeWidth: 3.125
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: "m1429.25 438.5 7.5 7.5-7.5 7.5" }
                }
            }
        }

        // ── Numeric keypad: 1-9 (centers 1568 / 1688 / 1808, baselines
        // 159 / 259 / 359) and "0" centered at the bottom (baseline 459) ──────────
        Repeater {
            model: ["1","2","3","4","5","6","7","8","9"]
            KeyBtn {
                required property string modelData
                required property int index
                x: 1508 + 120 * (index % 3); y: 96 + 100 * Math.floor(index / 3)
                width: 120; height: 100
                baseY: 159 + 100 * Math.floor(index / 3)
                displayChar: modelData
            }
        }
        KeyBtn {
            x: 1628; y: 396; width: 120; height: 100
            baseY: 459
            displayChar: "0"
        }

        // ── Overlay: accents popup (long press on a letter) ─────
        Rectangle {
            id: accentOverlay
            z: 10
            visible: root.accentPopupKey !== null
            x: root.accentPopupX
            y: root.accentPopupY
            width: Math.max(1, root.accentPopupVariants.length * root.accentCellSize)
            height: root.accentCellSize
            radius: root.keyRadius
            color: root.keyBg
            border.width: 1
            border.color: Qt.darker(root.keyBg, 1.15)

            Row {
                anchors.fill: parent
                Repeater {
                    model: root.accentPopupVariants
                    delegate: Rectangle {
                        id: accentCell
                        required property string modelData
                        required property int index
                        width: root.accentCellSize
                        height: root.accentCellSize
                        radius: root.keyRadius
                        color: accentCell.index === root.accentPopupHighlight ? root.keyActiveBg : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: accentCell.modelData
                            font.family: root.fontFamily
                            font.weight: Font.DemiBold
                            font.pixelSize: root.letterSize
                            color: accentCell.index === root.accentPopupHighlight ? root.keyTextOnAccent : root.keyText
                        }
                    }
                }
            }
        }

        // ── Overlay: language selection popup (long press on the space bar) ──
        MouseArea {
            z: 10
            x: 0; y: 0; width: 1920; height: 600
            visible: root.langPopupOpen
            onClicked: root.langPopupOpen = false
        }

        Rectangle {
            id: langPopupBox
            z: 11
            visible: root.langPopupOpen
            width: root.langPopupWidth
            height: langPopupCol.height + 16
            radius: root.keyRadius
            color: root.panelBg
            border.width: 1
            border.color: Qt.darker(root.panelBg, 1.15)
            x: spaceKey.x + spaceKey.width / 2 - width / 2
            y: spaceKey.y - height - 8

            Column {
                id: langPopupCol
                x: 8
                y: 8
                width: parent.width - 16
                spacing: 2

                Repeater {
                    model: KeyboardSettings.enabledLanguageCodes
                    delegate: Rectangle {
                        id: langRow
                        required property string modelData
                        width: parent.width
                        height: root.langPopupRowH
                        radius: root.keyRadius
                        color: langRow.modelData === KeyboardSettings.activeLanguage
                               ? root.keyActiveBg
                               : (langMouse.pressed ? root.keyBgPressed : "transparent")
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 20
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.languageName(langRow.modelData)
                            font.family: root.fontFamily
                            font.pixelSize: 28
                            color: langRow.modelData === KeyboardSettings.activeLanguage
                                   ? root.keyTextOnAccent : root.keyText
                        }
                        MouseArea {
                            id: langMouse
                            anchors.fill: parent
                            onClicked: {
                                KeyboardSettings.activeLanguage = langRow.modelData
                                root.langPopupOpen = false
                            }
                        }
                    }
                }
            }
        }
    }
}
