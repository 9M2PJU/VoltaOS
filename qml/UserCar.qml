import QtQuick
import QtQuick3D
import QtQuick3D.AssetUtils

// 3D car from a .glb file (the bundled one or the user's). It recognizes doors, hood,
// trunk, wheels and paint by itself (names read from CarModels, which takes them from the file) and animates them.
// The node origin is on the ground, at the center of the car; front = +Z.
Node {
    id: rig

    property string file: ""                  // absolute path of the .glb
    property var parts: ({})                  // {doorL, doorR, hood, trunk, wheelFL.., paint[]} (CarModels.currentParts().parts)
    property var names: []                    // node names, in file order
    property var rows: []                     // for each node: "F" front, "B" back, "" unknown
    property var pivots: []                   // for each node: true if it has its own position (hinge / axis)
    property real userYaw: 0                  // rotates the car by this many degrees (user's choice)
    property real autoYaw: 0                  // 180 if the model has the front on the wrong side (detected automatically)
    property var mats: []                     // for each node, the names of its materials
    property real targetLength: 3.4           // length of the car in the scene (cars of every size are brought to this)
    property real doorL: 0                    // 0 = chiusa, 1 = aperta
    property real doorR: 0
    property real trunkOpen: 0
    property real hoodOpen: 0
    property real wheelSpin: 0                // gradi
    property color paintColor: "#C8C9CA"
    property real metal: 0.1
    property real rough: 0.5
    property real coat: 0.3
    property real coatRough: 0.25
    property var angles: ({})                 // {doorL, doorR, hood, trunk}: opening degrees chosen by the user
    property real doorMax: 62
    property real trunkMax: 30
    property real hoodMax: 30
    property real brightness: 1.0             // < 1: darker car (used for the reflection)
    property bool reflection: false           // true: it is the floor reflection, all dark gray (no colors, no emissives)

    readonly property bool loaded: loader.status === RuntimeLoader.Success
    onFileChanged: { setupDone = false; rigged = false; _bnd = null }   // new file: the previous car disappears until the new one is ready
    property bool setupDone: false            // true when detection and paint are ready
    property bool rigged: false               // true if the parts have been matched to the nodes
    property real lengthScale: 1
    property var nodeCount: 0
    signal ready()

    Node {
        id: holder
        visible: rig.setupDone          // until scaling is done the car would be huge and crooked: it is not shown
        scale: Qt.vector3d(rig.lengthScale, rig.lengthScale, rig.lengthScale)
        eulerRotation.y: rig._yawDeg
        RuntimeLoader {
            id: loader
            source: rig.file !== "" ? "file://" + rig.file : ""
            onStatusChanged: {
                if (status === RuntimeLoader.Success) setupTimer.restart()
                else if (status === RuntimeLoader.Error) console.log("[3D car] error:", errorString)
            }
        }
    }
    // wait one frame: the scene transforms must be ready
    Timer { id: setupTimer; interval: 30; onTriggered: rig._setup() }
    onPartsChanged: if (loaded) setupTimer.restart()

    // ── quaternioni (w, x, y, z) ──
    function _qmul(a, b) {
        return Qt.quaternion(a.scalar * b.scalar - a.x * b.x - a.y * b.y - a.z * b.z,
                             a.scalar * b.x + b.scalar * a.x + a.y * b.z - a.z * b.y,
                             a.scalar * b.y + b.scalar * a.y + a.z * b.x - a.x * b.z,
                             a.scalar * b.z + b.scalar * a.z + a.x * b.y - a.y * b.x)
    }
    function _qaxis(ax, deg) {
        var l = Math.sqrt(ax.x * ax.x + ax.y * ax.y + ax.z * ax.z) || 1
        var h = deg * Math.PI / 360, s = Math.sin(h) / l
        return Qt.quaternion(Math.cos(h), ax.x * s, ax.y * s, ax.z * s)
    }

    // ── misura e posizione: lunghezza voluta x scala scelta dall'utente, appoggiata a terra e centrata ──
    property real userScale: 1
    property var _bnd: null
    property real _yawDeg: 0
    function _place() {
        if (!_bnd) return
        var s = rig.targetLength / _bnd.len * rig.userScale
        rig.lengthScale = s
        var x = -(_bnd.minx + _bnd.maxx) / 2 * s, z = -(_bnd.minz + _bnd.maxz) / 2 * s
        var a = rig._yawDeg * Math.PI / 180, c = Math.cos(a), sn = Math.sin(a)
        holder.position = Qt.vector3d(x * c + z * sn, -_bnd.miny * s, -x * sn + z * c)      // the rotation also applies to the centering shift
    }
    onUserScaleChanged: _place()
    on_YawDegChanged: _place()
    onUserYawChanged: if (loaded) _yawDeg = (parts.yaw !== undefined ? parts.yaw : autoYaw) + userYaw

    // ── node tree ──
    property var _nodes: []
    function _walk(n, out) {
        for (var i = 0; i < n.children.length; i++) {
            var c = n.children[i]
            if (c.position === undefined) continue
            out.push(c)
            rig._walk(c, out)
        }
    }
    function _nodeByName(nm) {
        if (!nm) return null
        var i = rig.names.indexOf(nm)
        return (i >= 0 && i < rig._nodes.length) ? rig._nodes[i] : null
    }
    property var _rigged: []        // parts that open: [{ kind, sign, parts: [{ node, q0, pos0, axis, pivot }] }]
    // rotates vector v around the unit axis k by an angle (degrees): Rodrigues' formula
    function _rot(v, k, deg) {
        var t = deg * Math.PI / 180, c = Math.cos(t), s = Math.sin(t)
        var kv = k.crossProduct(v), kd = k.dotProduct(v)
        return v.times(c).plus(kv.times(s)).plus(k.times(kd * (1 - c)))
    }
    // ── transforms computed by hand from the nodes' properties (position, rotation, scale) ──
    // Qt's scene transforms are not used: they update with a delay and, if read too early
    // or with an already rotated part, they give wrong positions (doors and hood opening the wrong way).
    // REAL copy of the quaternion: reading n.rotation would give a reference that changes along with the node (the parts would spin on themselves)
    function _qcopy(q) { return Qt.quaternion(q.scalar, q.x, q.y, q.z) }
    function _qconj(q) { return Qt.quaternion(q.scalar, -q.x, -q.y, -q.z) }
    function _qrot(q, v) {
        var r = rig._qmul(rig._qmul(q, Qt.quaternion(0, v.x, v.y, v.z)), rig._qconj(q))
        return Qt.vector3d(r.x, r.y, r.z)
    }
    function _chain(node) {            // node, parent, ... up to rig (excluded); null if rig is not reached
        var out = [], n = node, guard = 0
        while (n && n !== rig && guard++ < 200) { out.push(n); n = n.parent }
        return n === rig ? out : null
    }
    function _toRig(chain, p) {        // point in the node's system -> car's system
        for (var i = 0; i < chain.length; i++) {
            var n = chain[i]
            p = Qt.vector3d(p.x * n.scale.x, p.y * n.scale.y, p.z * n.scale.z)
            p = rig._qrot(n.rotation, p).plus(n.position)
        }
        return p
    }
    function _dirToLocal(chain, d) {   // direction in the car's system -> node's system
        for (var i = chain.length - 1; i >= 0; i--) d = rig._qrot(rig._qconj(chain[i].rotation), d)
        return d
    }
    // point in the car's system -> node's system (inverse of _toRig)
    function _fromRig(chain, p) {
        for (var i = chain.length - 1; i >= 0; i--) {
            var n = chain[i]
            p = rig._qrot(rig._qconj(n.rotation), p.minus(n.position))
            p = Qt.vector3d(p.x / n.scale.x, p.y / n.scale.y, p.z / n.scale.z)
        }
        return p
    }
    function _names(v) { if (v === undefined || v === null || v === "") return []; if (typeof v === "string") return [v]; if (v.length === undefined) return [v]; var o = []; for (var i = 0; i < v.length; i++) o.push(v[i]); return o }

    // ── A part that opens (door, hood, trunk) can be made of SEVERAL meshes: all rotate together around the same
    // hinge. The hinge is the origin of the first mesh if it has a position of its own; otherwise it is put on the right edge of the box
    // of the part (door: front edge, outside; hood: rear edge; trunk: front edge). The direction is chosen by trying: the
    // portiera deve spostarsi verso l'esterno, cofano e baule devono alzarsi.
    function _partHinge(nameList, kind) {
        var list = rig._names(nameList), nodes = [], lo = null, hi = null
        for (var i = 0; i < list.length; i++) {
            var n = rig._nodeByName(list[i])
            if (!n) continue
            var ch = rig._chain(n)
            var bb = CarModels.partBounds(rig.file, list[i])
            if (!ch || bb.length < 6) continue
            nodes.push(n)
            for (var c = 0; c < 8; c++) {
                var q = rig._toRig(ch, Qt.vector3d((c & 1) ? bb[3] : bb[0], (c & 2) ? bb[4] : bb[1], (c & 4) ? bb[5] : bb[2]))
                lo = lo ? Qt.vector3d(Math.min(lo.x, q.x), Math.min(lo.y, q.y), Math.min(lo.z, q.z)) : q
                hi = hi ? Qt.vector3d(Math.max(hi.x, q.x), Math.max(hi.y, q.y), Math.max(hi.z, q.z)) : q
            }
        }
        if (!nodes.length) return null
        var isDoor = kind.indexOf("door") === 0
        var left = (kind === "doorL" || kind === "doorRL")
        var centre = lo.plus(hi).times(0.5)
        var first = nodes[0], chF = rig._chain(first)
        var pivot
        if (first.position.length() > 1e-3) pivot = rig._toRig(chF, Qt.vector3d(0, 0, 0))
        else if (isDoor) pivot = Qt.vector3d(centre.x >= 0 ? hi.x : lo.x, centre.y, hi.z)       // bordo davanti, lato esterno
        else if (kind === "hood") pivot = Qt.vector3d(centre.x, centre.y, lo.z)                  // edge toward the windshield
        else pivot = Qt.vector3d(centre.x, centre.y, hi.z)                                       // baule: bordo verso l'abitacolo
        var axisRig = isDoor ? Qt.vector3d(0, 1, 0) : Qt.vector3d(1, 0, 0)
        var d = centre.minus(pivot), d2 = rig._rot(d, axisRig, 20)
        var gain = isDoor ? (left ? (d2.x - d.x) : (d.x - d2.x)) : (d2.y - d.y)
        var out = { kind: kind, sign: gain >= 0 ? 1 : -1, parts: [] }
        for (var k = 0; k < nodes.length; k++) {
            var nd = nodes[k], chP = rig._chain(nd.parent) || []
            out.parts.push({ node: nd, q0: rig._qcopy(nd.rotation), pos0: Qt.vector3d(nd.position.x, nd.position.y, nd.position.z),
                             axis: rig._dirToLocal(chP, axisRig), pivot: rig._fromRig(chP, pivot) })
        }
        if (debugMode) console.log("[auto 3D]", kind, JSON.stringify(list), "pivot", pivot, "d", d, "verso", out.sign > 0 ? "+" : "-")
        return out
    }
    function _setHinge(h, deg) {
        var q = rig._qaxis(h.parts[0].axis, 0)   // (initialization for the type)
        for (var i = 0; i < h.parts.length; i++) {
            var p = h.parts[i]
            q = rig._qaxis(p.axis, deg * h.sign)
            p.node.rotation = rig._qmul(q, p.q0)
            p.node.position = rig._qrot(q, p.pos0.minus(p.pivot)).plus(p.pivot)
        }
    }
    function _resetHinge(h) {
        for (var i = 0; i < h.parts.length; i++) { h.parts[i].node.rotation = h.parts[i].q0; h.parts[i].node.position = h.parts[i].pos0 }
    }

    // ── preview for the guided setup ──
    property real previewT: 0
    property real previewMax: -1          // gradi usati dall'anteprima (-1 = quelli salvati)
    property var _pv: null
    property var _pvPaint: []
    property var _pvWheels: []
    SequentialAnimation {
        id: pvAnim; loops: Animation.Infinite
        NumberAnimation { target: rig; property: "previewT"; from: 0; to: 1; duration: 1100; easing.type: Easing.InOutCubic }
        PauseAnimation { duration: 700 }
        NumberAnimation { target: rig; property: "previewT"; from: 1; to: 0; duration: 1100; easing.type: Easing.InOutCubic }
        PauseAnimation { duration: 500 }
    }
    onPreviewMaxChanged: _pvApply()
    onPreviewTChanged: _pvApply()
    function _pvApply() {
        if (!_pv) return
        var max = previewMax >= 0 ? previewMax : rig._maxFor(_pv.kind)
        rig._setHinge(_pv, previewT * max)
    }
    function stopPreview() {
        pvAnim.stop(); spinAnim.stop(); previewMax = -1
        if (_pv) { rig._resetHinge(_pv); _pv = null }
        for (var i = 0; i < _pvPaint.length; i++) _pvPaint[i].m.baseColor = _pvPaint[i].c
        _pvPaint = []
        for (var w = 0; w < _pvWheels.length; w++) _pvWheels[w].node.rotation = _pvWheels[w].q0
        _pvWheels = []
        rig._spinExtra = 0
        rig.previewT = 0
        rig._applyAll()
        if (_paintMats.length) rig._repaint()          // the paint goes back to the chosen color, the test one does not stay
    }
    // shows how the part made of the meshes `nameList` moves (kind: doorL, doorR, doorRL, doorRR, hood, trunk)
    function previewPart(nameList, kind, maxDeg) {
        stopPreview()
        previewMax = maxDeg !== undefined ? maxDeg : -1
        var h = rig._partHinge(nameList, kind)
        if (!h) return false
        _pv = h
        pvAnim.start()
        return true
    }
    // colors bright pink the materials with these names, to show what changes color
    function previewMaterials(matNames) {
        stopPreview()
        var saved = []
        for (var i = 0; i < rig._nodes.length; i++) {
            var n = rig._nodes[i]
            if (n.materials === undefined || !rig.mats[i]) continue
            for (var m = 0; m < n.materials.length && m < rig.mats[i].length; m++) {
                var mt = n.materials[m]
                if (mt && matNames.indexOf(rig.mats[i][m]) >= 0 && saved.every(function(x) { return x.m !== mt })) {
                    var c0 = mt.baseColor                                  // COPY of the color (otherwise it would follow the pink)
                    saved.push({ m: mt, c: Qt.rgba(c0.r, c0.g, c0.b, c0.a) })
                    mt.baseColor = "#ff2d95"
                }
            }
        }
        _pvPaint = saved
        return saved.length > 0
    }
    property real _spinExtra: 0
    NumberAnimation { id: spinAnim; target: rig; property: "_spinExtra"; from: 0; to: 360; duration: 1600; loops: Animation.Infinite }
    function previewWheels() { stopPreview(); spinAnim.start() }
    // makes the wheels `nameList` spin (each around its own origin)
    function previewWheelsOf(nameList) {
        stopPreview()
        var list = rig._names(nameList), out = []
        for (var i = 0; i < list.length; i++) {
            var wn = rig._nodeByName(list[i]); if (!wn) continue
            out.push({ node: wn, q0: rig._qcopy(wn.rotation), axis: rig._dirToLocal(rig._chain(wn) || [], Qt.vector3d(1, 0, 0)) })
        }
        _pvWheels = out
        spinAnim.start()
        return out.length > 0
    }
    function stopWheels() { spinAnim.stop(); rig._spinExtra = 0; rig._spin() }
    on_SpinExtraChanged: { if (rigged) _spin(); for (var i = 0; i < _pvWheels.length; i++) _pvWheels[i].node.rotation = rig._qmul(_pvWheels[i].q0, rig._qaxis(_pvWheels[i].axis, _spinExtra)) }

    // ── highlight mesh (pink, unlit): the setup's selector ──
    property var _hl: []
    property var _hlMat: null
    function clearHighlight() {
        for (var i = 0; i < _hl.length; i++) _hl[i].node.materials = _hl[i].orig
        _hl = []
    }
    function highlightNodes(indices) {
        clearHighlight()
        if (!_hlMat) _hlMat = Qt.createQmlObject('import QtQuick3D; PrincipledMaterial { baseColor: "#ff2d95"; lighting: PrincipledMaterial.NoLighting }', rig, "hlMat")
        var out = [], stack = []
        for (var i = 0; i < indices.length; i++) if (indices[i] >= 0 && indices[i] < _nodes.length) stack.push(_nodes[indices[i]])
        var seen = []
        while (stack.length) {
            var n = stack.pop()
            if (seen.indexOf(n) >= 0) continue
            seen.push(n)
            if (n.materials !== undefined && n.materials.length > 0) {
                var orig = [], rep = []
                for (var m = 0; m < n.materials.length; m++) { orig.push(n.materials[m]); rep.push(_hlMat) }
                n.materials = rep
                out.push({ node: n, orig: orig })
            }
            for (var c = 0; c < n.children.length; c++) if (n.children[c].position !== undefined) stack.push(n.children[c])
        }
        _hl = out
    }

    function _setup() {
        rig.setupDone = false
        rig._resetPose()
        // 1. nodes: RuntimeLoader's tree has a few more nodes (containers) at the beginning
        var flat = []
        rig._walk(loader, flat)
        var off = flat.length - rig.names.length
        rig._nodes = off >= 0 ? flat.slice(off) : []
        // the meshes must be "touchable": they are needed to choose a part by touching the car, to move the buttons and for the touch in the garage
        for (var pi = 0; pi < rig._nodes.length; pi++) if (rig._nodes[pi].pickable !== undefined) rig._nodes[pi].pickable = true
        // 2. orientation: the front of the car must be toward +Z. The "front" and "rear" meshes are compared (FL, FR / RL, RR...)
        rig._yawDeg = 0
        var zF = 0, nF = 0, zB = 0, nB = 0
        if (off >= 0)
            for (var i = 0; i < rig._nodes.length && i < rig.rows.length; i++) {
                if (!rig.pivots[i] || !rig.rows[i]) continue
                var ch = rig._chain(rig._nodes[i]); if (!ch) continue
                var z = rig._toRig(ch, Qt.vector3d(0, 0, 0)).z
                if (rig.rows[i] === "F") { zF += z; nF++ } else if (rig.rows[i] === "B") { zB += z; nB++ }
            }
        rig.autoYaw = (nF > 0 && nB > 0 && zF / nF < zB / nB) ? 180 : 0
        rig._yawDeg = (rig.parts.yaw !== undefined ? rig.parts.yaw : rig.autoYaw) + rig.userYaw
        // 3. measures: the car is brought to the wanted length, resting on the ground and centered
        var b = loader.bounds
        var len = b.maximum.z - b.minimum.z
        if (len > 0.1) {
            rig._bnd = { minx: b.minimum.x, maxx: b.maximum.x, miny: b.minimum.y, maxy: b.maximum.y, minz: b.minimum.z, maxz: b.maximum.z, len: len }
            rig._place()
        }
        rig._rigged = []
        rig._wheels = []
        if (off >= 0 && rig.names.length > 0) {
            var kinds = ["doorL", "doorR", "doorRL", "doorRR", "hood", "trunk"]
            for (var k = 0; k < kinds.length; k++) {
                var hg = rig._partHinge(rig.parts[kinds[k]], kinds[k])
                if (hg) rig._rigged.push(hg)
            }
            // wheels: "wheels" list, or the four old keys wheelFL...
            var wl = rig._names(rig.parts.wheels)
            if (!wl.length) wl = [].concat(rig._names(rig.parts.wheelFL), rig._names(rig.parts.wheelFR), rig._names(rig.parts.wheelRL), rig._names(rig.parts.wheelRR))
            for (var w = 0; w < wl.length; w++) {
                var wn = rig._nodeByName(wl[w])
                if (wn) rig._wheels.push({ node: wn, q0: rig._qcopy(wn.rotation),
                                           axis: rig._dirToLocal(rig._chain(wn) || [], Qt.vector3d(1, 0, 0)) })
            }
            rig.rigged = rig._rigged.length > 0 || rig._wheels.length > 0
            // 4. vernice
            rig._collectPaint()
        } else {
            console.log("[3D car] the nodes do not match the file: no animated doors/wheels (", flat.length, "contro", rig.names.length, ")")
        }
        rig._applyAll()
        rig.setupDone = true
        rig.ready()
    }
    property var _wheels: []
    // puts all the parts back in the closed position (before recomputing): a rotated part would skew the calculations
    function _resetPose() {
        clearHighlight()
        if (_pv) { rig._resetHinge(_pv); _pv = null }
        pvAnim.stop(); spinAnim.stop(); _spinExtra = 0; previewT = 0
        for (var i = 0; i < _rigged.length; i++) rig._resetHinge(_rigged[i])
        for (var j = 0; j < _wheels.length; j++) _wheels[j].node.rotation = _wheels[j].q0
    }

    function _maxFor(kind) {
        var a = rig.angles || {}
        if (a[kind] !== undefined && a[kind] !== null) return a[kind]
        return kind.indexOf("door") === 0 ? doorMax : (kind === "trunk" ? trunkMax : hoodMax)
    }
    onAnglesChanged: if (rigged) _applyAll()
    // v = 0..1. The rear doors follow the front ones on the same side.
    function _apply(kind, v) {
        var max = rig._maxFor(kind)
        for (var i = 0; i < rig._rigged.length; i++)
            if (rig._rigged[i].kind === kind) rig._setHinge(rig._rigged[i], v * max)
    }
    function _applyAll() {
        rig._apply("doorL", rig.doorL); rig._apply("doorRL", rig.doorL)
        rig._apply("doorR", rig.doorR); rig._apply("doorRR", rig.doorR)
        rig._apply("trunk", rig.trunkOpen)
        rig._apply("hood", rig.hoodOpen)
        rig._spin()
    }
    function _spin() {
        for (var i = 0; i < rig._wheels.length; i++) {
            var w = rig._wheels[i]
            w.node.rotation = rig._qmul(w.q0, rig._qaxis(w.axis, rig.wheelSpin + rig._spinExtra))
        }
    }
    onDoorLChanged: if (rigged) { _apply("doorL", doorL); _apply("doorRL", doorL) }
    onDoorRChanged: if (rigged) { _apply("doorR", doorR); _apply("doorRR", doorR) }
    onTrunkOpenChanged: if (rigged) _apply("trunk", trunkOpen)
    onHoodOpenChanged: if (rigged) _apply("hood", hoodOpen)
    onWheelSpinChanged: if (rigged) _spin()

    // ── vernice ──
    property var _paintMats: []
    function _collectPaint() {
        var want = rig._names(rig.parts.paint)
        var out = []
        for (var i = 0; i < rig._nodes.length; i++) {
            var n = rig._nodes[i]
            if (n.materials === undefined || !rig.mats[i]) continue
            for (var m = 0; m < n.materials.length && m < rig.mats[i].length; m++) {
                if (want.indexOf(rig.mats[i][m]) >= 0 && n.materials[m] && out.indexOf(n.materials[m]) < 0)
                    out.push(n.materials[m])
            }
        }
        rig._paintMats = out
        rig._repaint()
        rig._dimAll()
    }
    // Reflection: ALL materials (glass, headlights, interiors, tires, chrome) become gray and dark,
    // emissives are turned off. Before, only the paint was touched and the rest showed in full color.
    function _dimAll() {
        if (!rig.reflection) return
        var seen = []
        for (var i = 0; i < rig._nodes.length; i++) {
            var n = rig._nodes[i]
            if (n.materials === undefined) continue
            for (var m = 0; m < n.materials.length; m++) {
                var mat = n.materials[m]
                if (!mat || seen.indexOf(mat) >= 0) continue
                seen.push(mat)
                // The mirror (negative scale) flips the faces' winding: with only the front face the outer
                // sheet metal (one-sided surface) disappeared and only pillars, wheels and interiors were seen ("skeleton").
                if ("cullMode" in mat) mat.cullMode = Material.NoCulling
                if (rig._paintMats.indexOf(mat) >= 0) continue          // the paint is handled by _repaint()
                if ("baseColor" in mat) {
                    var c = mat.baseColor, l = (c.r + c.g + c.b) / 3 * rig.brightness
                    mat.baseColor = Qt.rgba(l, l, l, c.a)
                }
                if ("emissiveFactor" in mat) mat.emissiveFactor = Qt.vector3d(0, 0, 0)
                if ("specularAmount" in mat) mat.specularAmount = mat.specularAmount * rig.brightness
            }
        }
    }
    function _repaint() {
        for (var i = 0; i < rig._paintMats.length; i++) {
            var m = rig._paintMats[i]
            var pl = (rig.paintColor.r + rig.paintColor.g + rig.paintColor.b) / 3
            m.baseColor = rig.reflection
                ? Qt.rgba(pl * rig.brightness, pl * rig.brightness, pl * rig.brightness, 1)       // reflection: never colored
                : Qt.rgba(rig.paintColor.r * rig.brightness, rig.paintColor.g * rig.brightness, rig.paintColor.b * rig.brightness, 1)
            if ("baseColorMap" in m) m.baseColorMap = null
            // reflection: matte, non-metallic paint, so it does not mirror the bright environment (it came out white) and stays dark gray
            if ("metalness" in m) m.metalness = rig.reflection ? 0.0 : rig.metal
            if ("roughness" in m) m.roughness = rig.reflection ? 0.9 : rig.rough
            if ("clearcoatAmount" in m) m.clearcoatAmount = rig.reflection ? 0.0 : rig.coat
            if ("clearcoatRoughnessAmount" in m) m.clearcoatRoughnessAmount = rig.reflection ? 0.6 : rig.coatRough
        }
    }
    onPaintColorChanged: _repaint()
    onMetalChanged: _repaint()
    onRoughChanged: _repaint()
    onCoatChanged: _repaint()
    onCoatRoughChanged: _repaint()
}
