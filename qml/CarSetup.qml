import QtQuick
import VoltaApp 1.0

// Guided setup of the 3D car. For each part (doors, hood, trunk, wheels, paint) the car moves it (or colors it pink)
// and asks "is it this one?". If not, the list of all the meshes opens on the right: each tap highlights the mesh on the car, you can
// choose more than one for the same part, then confirm. At the end everything is saved in auto.json.
Item {
    id: setup
    property var rig: null                  // UserCar
    property var scene: null                // CarScene (to open the adjustment of position, size, shadow and buttons)
    property var blurSources: []          // what to blur behind the panels
    property bool lightTheme: false
    signal finished()

    property var info: ({})                 // CarModels.inspect(file)
    property var result: ({})
    property var steps: []
    property int step: 0                    // index in steps; steps.length = final screen
    property bool asked: false              // false = the initial question "does it have openable doors, hood and trunk?" is shown
    property string mode: "confirm"         // "confirm" = part test, "pick" = choice from the list
    property var sel: []                    // meshes chosen in the list (node indices, or material names for the paint)
    property bool showAllNodes: false
    property real curAngle: 60              // opening degrees of the part being tested (slider)
    readonly property var defaultAngles: ({ doorL: 62, doorR: 62, doorRL: 62, doorRR: 62, hood: 30, trunk: 30 })

    readonly property bool ready: rig && rig.loaded && rig.setupDone
    readonly property var cur: step < steps.length ? steps[step] : null
    readonly property string kind: cur ? cur.kind : ""
    readonly property bool isHinged: kind.indexOf("door") === 0 || kind === "hood" || kind === "trunk"
    readonly property var curList: (cur && result[kind] !== undefined) ? result[kind] : []
    readonly property bool found: curList.length > 0
    readonly property bool picking: mode === "pick" && cur !== null && kind !== "adjust"

    function _names(v) { if (v === undefined || v === null || v === "") return []; if (typeof v === "string") return [v]; if (v.length === undefined) return [v]; var o = []; for (var i = 0; i < v.length; i++) o.push(v[i]); return o }

    function buildSteps() {
        var det = info.parts || {}
        var l = [ { kind: "doorL", title: qsTr("Left door"), what: qsTr("the left door") },
                  { kind: "doorR", title: qsTr("Right door"), what: qsTr("the right door") } ]
        if (_names(det.doorRL).length) l.push({ kind: "doorRL", title: qsTr("Rear left door"), what: qsTr("the rear left door") })
        if (_names(det.doorRR).length) l.push({ kind: "doorRR", title: qsTr("Rear right door"), what: qsTr("the rear right door") })
        l.push({ kind: "hood", title: qsTr("Hood"), what: qsTr("the front hood") })
        l.push({ kind: "trunk", title: qsTr("Trunk"), what: qsTr("the rear trunk") })
        l.push({ kind: "wheels", title: qsTr("Wheels"), what: qsTr("the wheels") })
        l.push({ kind: "paint", title: qsTr("Color"), what: qsTr("the body") })
        l.push({ kind: "adjust", title: qsTr("Position and size"), what: "" })
        return l
    }

    function begin() {
        var det = info.parts || {}
        steps = buildSteps()
        result = { doorL: _names(det.doorL).slice(), doorR: _names(det.doorR).slice(), doorRL: _names(det.doorRL).slice(), doorRR: _names(det.doorRR).slice(),
                   hood: _names(det.hood).slice(), trunk: _names(det.trunk).slice(), wheels: _names(det.wheels).slice(), paint: _names(det.paint).slice(),
                   angles: { doorL: 62, doorR: 62, doorRL: 62, doorRR: 62, hood: 30, trunk: 30 } }
        step = 0; mode = "confirm"; sel = []
        asked = false                      // first the question; the part test starts after the answer
        if (rig) { rig.stopPreview(); rig.clearHighlight() }
    }
    // answer to the initial question: Yes / I don't know = full setup; No = skip to the paint
    function answerOpenable(kindAnswer) {
        asked = true
        mode = "confirm"
        if (kindAnswer === "no") {
            for (var i = 0; i < steps.length; i++) if (steps[i].kind === "paint") { step = i; break }
        } else step = 0
        show()
    }

    // shows the test for the current step
    function show() {
        if (!rig) return
        rig.clearHighlight()
        if (!cur) { rig.stopPreview(); return }
        if (kind === "adjust") { rig.stopPreview(); if (scene) scene.adjustOpen = true; return }
        if (kind === "wheels") {
            if (found) rig.previewWheelsOf(curList); else rig.stopPreview()
            return
        }
        if (kind === "paint") {
            if (found) rig.previewMaterials(curList); else rig.stopPreview()
            return
        }
        curAngle = result.angles[kind] !== undefined ? result.angles[kind] : defaultAngles[kind]
        if (found) { if (!rig.previewPart(curList, kind, curAngle)) rig.stopPreview() } else rig.stopPreview()
    }
    function yes() {
        if (isHinged) result.angles[kind] = Math.round(curAngle)
        next()
    }
    function skip() {             // "the car does not have this part"
        result[kind] = []
        next()
    }
    function next() {
        if (rig) { rig.stopPreview(); rig.clearHighlight() }
        step++; mode = "confirm"; sel = []
        show()
    }

    // ── selector: list of all the meshes (or materials) ──
    readonly property bool materialsMode: kind === "paint"
    readonly property var pickItems: {
        var out = []
        if (!info.names) return out
        if (materialsMode) {
            var mn = info.materialNames || []
            for (var m = 0; m < mn.length; m++) out.push({ key: mn[m], label: mn[m], depth: 0 })
            return out
        }
        var all = showAllNodes || info.names.length <= 120
        for (var i = 0; i < info.names.length; i++) {
            if (!info.names[i]) continue
            var d = info.depths ? info.depths[i] : 0
            if (!all && d > 2 && !(info.pivots && info.pivots[i])) continue
            out.push({ key: i, label: info.names[i], depth: d })
        }
        return out
    }
    signal scrollTo(int itemIndex)
    // a tap on the car during the choice: selects the mesh under the finger (or its materials, for the paint)
    function pickAt(item, x, y) {
        if (!scene || !rig) return
        var hit = scene.pickModelAt(item, x, y)
        if (!hit) return
        var idx = rig._nodes.indexOf(hit)
        if (idx < 0) return
        if (materialsMode) {
            var names = [], mm = rig.mats[idx] || []
            for (var i = 0; i < mm.length; i++) if (mm[i] && names.indexOf(mm[i]) < 0) names.push(mm[i])
            var all = names.length > 0 && names.every(function(n) { return sel.indexOf(n) >= 0 })
            var l = sel.filter(function(n) { return !(all && names.indexOf(n) >= 0) })
            if (!all) for (var k = 0; k < names.length; k++) if (l.indexOf(names[k]) < 0) l.push(names[k])
            sel = l
            applyHighlight()
            return
        }
        if (!showAllNodes) showAllNodes = true            // the touched mesh may be hidden in the reduced list
        toggle(idx)
        for (var j = 0; j < pickItems.length; j++) if (pickItems[j].key === idx) { scrollTo(j); break }
    }
    function openPicker() {
        if (!rig) return
        rig.stopPreview()
        mode = "pick"
        if (materialsMode) sel = curList.slice()
        else {
            var idx = []
            for (var i = 0; i < curList.length; i++) { var k = info.names.indexOf(curList[i]); if (k >= 0) idx.push(k) }
            sel = idx
        }
        applyHighlight()
    }
    function toggle(key) {
        var l = sel.slice(), p = l.indexOf(key)
        if (p >= 0) l.splice(p, 1); else l.push(key)
        sel = l
        applyHighlight()
    }
    function applyHighlight() {
        if (!rig) return
        if (materialsMode) { if (sel.length) rig.previewMaterials(sel); else rig.stopPreview() }
        else rig.highlightNodes(sel)
    }
    function confirmPick() {
        if (materialsMode) result[kind] = sel.slice()
        else {
            var nm = []
            for (var i = 0; i < sel.length; i++) nm.push(info.names[sel[i]])
            result[kind] = nm
        }
        if (rig) { rig.stopPreview(); rig.clearHighlight() }
        mode = "confirm"
        show()
    }
    function cancelPick() {
        if (rig) { rig.stopPreview(); rig.clearHighlight() }
        mode = "confirm"
        show()
    }

    function save() {
        if (rig) { rig.stopPreview(); rig.clearHighlight() }
        var r = JSON.parse(JSON.stringify(result))
        r.yaw = rig ? rig.autoYaw : 0
        CarModels.saveParts(r)
        if (scene) scene.saveCarColor()              // the colorizer color is also saved with the car
        finished()
    }
    function skipAll() {         // use the automatic detection as is
        if (rig) { rig.stopPreview(); rig.clearHighlight() }
        asked = true; mode = "confirm"; step = steps.length
    }
    onReadyChanged: if (ready && visible) begin()
    onVisibleChanged: if (visible) { if (ready) begin() } else if (rig) { rig.stopPreview(); rig.clearHighlight() }

    readonly property color fg: lightTheme ? "#1D1D1F" : "#FFFFFF"
    readonly property color sub: lightTheme ? "#555555" : "#BBBBBB"
    readonly property color btn2: lightTheme ? "#D5D5D5" : "#3A3A3A"
    readonly property color btn2Down: lightTheme ? "#C8C8C8" : "#4A4A4A"

    // reusable secondary button
    component Btn2: Rectangle {
        property string label
        signal clicked()
        height: 46; radius: 10
        color: _ma.pressed ? setup.btn2Down : setup.btn2
        Text { anchors.centerIn: parent; width: parent.width - 16; horizontalAlignment: Text.AlignHCenter; text: parent.label; color: setup.fg; font.pixelSize: 15; wrapMode: Text.WordWrap }
        MouseArea { id: _ma; anchors.fill: parent; onClicked: parent.clicked() }
    }
    component BtnBlue: Rectangle {
        property string label
        signal clicked()
        height: 52; radius: 10
        color: _mb.pressed ? "#1E63D0" : "#2C7BF2"
        Text { anchors.centerIn: parent; text: parent.label; color: "#FFFFFF"; font.pixelSize: 17; font.weight: Font.DemiBold }
        MouseArea { id: _mb; anchors.fill: parent; onClicked: parent.clicked() }
    }

    // ═══════ LEFT CARD ═══════
    Rectangle {
        id: card
        visible: !(setup.cur && setup.cur.kind === "adjust")
        // in full screen it sits on the left (map and widgets are on the right and below); with the small panel, above the dock
        readonly property bool wide: setup.width > 1100
        x: wide ? 24 : (parent.width - width) / 2
        y: wide ? (parent.height - height) / 2 + parent.height * 0.08 : parent.height - height - 150
        width: wide ? 400 : Math.min(parent.width - 32, 520)
        height: col.height + 40
        radius: 18
        color: "transparent"
        MouseArea { anchors.fill: parent }
        GlassPanel { anchors.fill: parent; z: -1; sources: setup.blurSources; lightTheme: setup.lightTheme; radius: 18 }

        Column {
            id: col
            x: 24; y: 20; width: parent.width - 48; spacing: 12

            // ── caricamento ──
            Text {
                visible: !setup.ready
                width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                text: qsTr("Loading the car…")
                color: setup.fg; font.pixelSize: 18
            }

            // ── domanda iniziale ──
            Column {
                visible: setup.ready && !setup.asked
                width: parent.width; spacing: 12
                Text { width: parent.width; wrapMode: Text.WordWrap
                       text: qsTr("Does your model have openable doors, hood and trunk?")
                       color: setup.fg; font.pixelSize: 22; font.weight: Font.DemiBold }
                Text { width: parent.width; wrapMode: Text.WordWrap
                       text: qsTr("If you are not sure, choose \"I don't know\": we will try moving each part together.")
                       color: setup.sub; font.pixelSize: 15 }
                BtnBlue { width: parent.width; label: qsTr("Yes"); onClicked: setup.answerOpenable("yes") }
                Row {
                    spacing: 10
                    Btn2 { width: (parent.parent.width - 10) / 2; label: qsTr("No"); onClicked: setup.answerOpenable("no") }
                    Btn2 { width: (parent.parent.width - 10) / 2; label: qsTr("I don't know"); onClicked: setup.answerOpenable("unknown") }
                }
            }

            // ── step: part test ──
            Column {
                visible: setup.ready && setup.asked && setup.cur !== null && !setup.picking
                width: parent.width; spacing: 10
                Text { text: qsTr("Step %1 of %2").arg(setup.step + 1).arg(setup.steps.length); color: setup.sub; font.pixelSize: 13 }
                Text { width: parent.width; wrapMode: Text.WordWrap
                       text: setup.cur ? setup.cur.title : ""; color: setup.fg; font.pixelSize: 24; font.weight: Font.DemiBold }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: !setup.found
                          ? qsTr("I could not find this part on my own. Choose it from the mesh list, or skip if the car does not have it.")
                          : setup.kind === "wheels" ? qsTr("Are the wheels turning? If you cannot see them, rotate the car with your finger.")
                          : setup.kind === "paint" ? qsTr("Is the pink part the body? If you cannot see it, rotate the car with your finger.")
                          : qsTr("Look at the car: is the part that moves %1? If you cannot see it, rotate the car with your finger.").arg(setup.cur ? setup.cur.what : "")
                    color: setup.sub; font.pixelSize: 16
                }
                // how far it opens
                Column {
                    visible: setup.isHinged && setup.found
                    width: parent.width; spacing: 6
                    Text { text: qsTr("How far it opens"); color: setup.sub; font.pixelSize: 14 }
                    // same look as the brightness slider in the Settings
                    Rectangle {
                        id: slBar
                        width: parent.width; height: 46; radius: 10
                        color: setup.lightTheme ? "#E3E3E3" : "#2E2E2E"
                        border.width: 1; border.color: setup.lightTheme ? "#D8D8D8" : "#454545"
                        clip: true
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; x: 12; width: parent.width - 24; height: 4; radius: 2
                                    color: setup.lightTheme ? "#DDDDDD" : "#333333" }
                        Rectangle {
                            id: slThumb
                            readonly property real lo: 5
                            readonly property real hi: 120
                            width: 74; height: parent.height; radius: 10
                            color: setup.lightTheme ? "#FFFFFF" : "#A2A3A5"
                            border.width: 1; border.color: setup.lightTheme ? "#D8D8D8" : "#454545"
                            x: ((setup.curAngle - lo) / (hi - lo)) * (slBar.width - width)
                            Text { anchors.centerIn: parent; text: Math.round(setup.curAngle) + "°"
                                   color: setup.lightTheme ? "#171717" : "#FFFFFF"; font.pixelSize: 15; font.weight: Font.DemiBold }
                        }
                        MouseArea {
                            anchors.fill: parent; preventStealing: true
                            function upd(mx) {
                                var safeX = Math.max(0, Math.min(mx - slThumb.width / 2, slBar.width - slThumb.width))
                                var f = safeX / (slBar.width - slThumb.width)
                                if (isNaN(f)) f = 0
                                setup.curAngle = slThumb.lo + f * (slThumb.hi - slThumb.lo)
                                if (setup.rig) setup.rig.previewMax = setup.curAngle
                            }
                            onPressed: m => upd(m.x)
                            onPositionChanged: m => { if (pressed) upd(m.x) }
                        }
                    }
                }
                BtnBlue { visible: setup.found; width: parent.width; label: qsTr("Yes, that's it"); onClicked: setup.yes() }
                Row {
                    spacing: 10
                    Btn2 { width: (parent.parent.width - 10) / 2; label: setup.found ? qsTr("No, I'll choose from the list") : qsTr("Choose from the list"); onClicked: setup.openPicker() }
                    Btn2 { width: (parent.parent.width - 10) / 2; label: qsTr("The car does not have it"); onClicked: setup.skip() }
                }
            }

            // ── step: choice from the list ──
            Column {
                visible: setup.ready && setup.asked && setup.picking
                width: parent.width; spacing: 10
                Text { text: qsTr("Step %1 of %2").arg(setup.step + 1).arg(setup.steps.length); color: setup.sub; font.pixelSize: 13 }
                Text { width: parent.width; wrapMode: Text.WordWrap
                       text: setup.cur ? setup.cur.title : ""; color: setup.fg; font.pixelSize: 24; font.weight: Font.DemiBold }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: setup.materialsMode
                          ? qsTr("Tap the body materials in the list on the right: they turn pink on the car. You can choose more than one.")
                          : qsTr("Tap the meshes of the \"%1\" part in the list on the right: they turn pink on the car. If the part is made of several meshes, choose all the ones you need.").arg(setup.cur ? setup.cur.title : "")
                    color: setup.sub; font.pixelSize: 15
                }
                Text { text: qsTr("Selected: %1").arg(setup.sel.length); color: setup.fg; font.pixelSize: 15; font.weight: Font.DemiBold }
                BtnBlue { width: parent.width; label: qsTr("Confirm selection"); onClicked: setup.confirmPick() }
                Btn2 { width: parent.width; label: qsTr("Cancel"); onClicked: setup.cancelPick() }
            }

            // ── fine ──
            Column {
                visible: setup.ready && setup.asked && setup.cur === null
                width: parent.width; spacing: 12
                Text { width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                       text: qsTr("Done!"); color: setup.fg; font.pixelSize: 26; font.weight: Font.DemiBold }
                Text { width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                       text: qsTr("Your car is ready: doors, hood, trunk, wheels and color.")
                       color: setup.sub; font.pixelSize: 16 }
                BtnBlue { width: parent.width; label: qsTr("Done"); onClicked: setup.save() }
            }

            // skip everything (use the automatic detection)
            Text {
                visible: setup.ready && setup.asked && setup.cur !== null && !setup.picking
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: qsTr("Skip setup"); color: setup.sub; font.pixelSize: 13; font.underline: true
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: setup.skipAll() }
            }
        }
    }

    // ═══════ MESH LIST (on the right) ═══════
    Rectangle {
        id: pickPanel
        visible: setup.picking
        width: Math.min(setup.width * 0.3, 380)
        height: Math.min(setup.height * 0.74, 760)
        x: setup.width - width - 24
        y: 60
        radius: 18
        color: "transparent"
        MouseArea { anchors.fill: parent }
        GlassPanel { anchors.fill: parent; z: -1; sources: setup.blurSources; lightTheme: setup.lightTheme; radius: 18 }

        Column {
            anchors.fill: parent; anchors.margins: 14; spacing: 8
            Row {
                width: parent.width
                Text { width: parent.width - 150; text: setup.materialsMode ? qsTr("Materials") : qsTr("Car meshes")
                       color: setup.fg; font.pixelSize: 18; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    visible: !setup.materialsMode && (setup.info.names ? setup.info.names.length > 120 : false)
                    width: 150; height: 32; radius: 16
                    color: setup.showAllNodes ? "#2C7BF2" : setup.btn2
                    Text { anchors.centerIn: parent; text: setup.showAllNodes ? qsTr("Main ones only") : qsTr("Show all"); color: setup.showAllNodes ? "#FFFFFF" : setup.fg; font.pixelSize: 13 }
                    MouseArea { anchors.fill: parent; onClicked: setup.showAllNodes = !setup.showAllNodes }
                }
            }
            ListView {
                id: list
                Connections { target: setup; function onScrollTo(i) { list.positionViewAtIndex(i, ListView.Center) } }
                width: parent.width; height: parent.height - 40
                clip: true
                model: setup.pickItems
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    readonly property bool on: setup.sel.indexOf(modelData.key) >= 0
                    width: list.width; height: 38; radius: 8
                    color: on ? "#2C7BF2" : (_pm.pressed ? setup.btn2Down : "transparent")
                    Text {
                        x: 10 + modelData.depth * 14; width: parent.width - x - 34
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label; elide: Text.ElideRight
                        color: on ? "#FFFFFF" : setup.fg; font.pixelSize: 14
                    }
                    Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                           visible: on; text: "✓"; color: "#FFFFFF"; font.pixelSize: 16 }
                    MouseArea { id: _pm; anchors.fill: parent; onClicked: setup.toggle(modelData.key) }
                }
            }
        }
    }
}
