// CarScene.qml — Grafica premium (Riflesso + Ombre, 4 ruote indipendenti)
import QtQuick
import QtQuick.Shapes
import QtQuick3D
import QtQuick3D.Helpers
import QtQuick.Effects
import QtQuick3D.AssetUtils
import QtQuick.Dialogs
import QtCore as Core
import VoltaApp 1.0

Item {
    id: root

    property real panelRatio: 0.35
    property bool lightTheme: false
    // ═══ OPENABLE DOORS (0 = closed, 1 = fully open) — ready for the CAN bus ═══
    // Dal bus basta legare:  doorLeftOpen: canbus.doorFL ? 1 : 0   (idem doorRightOpen)
    // DIAGNOSIS MODE: loads car_body_debug.glb (colored parts) and opens the left door.
    // Set false to return to the normal model.
    property bool debugParts: false
    // ── DEBUG PICK: set true, click (without dragging) the parts that float ──
    property bool pickDebug: false
    property var picks: []
    function _enablePick(n) {
        if (!n || !n.children) return
        for (var i = 0; i < n.children.length; i++) {
            var c = n.children[i]
            if (c && c.pickable !== undefined) c.pickable = true
            root._enablePick(c)
        }
    }
    function doPick(x, y) {
        var r = view.pick(x, y)
        if (!r || !r.objectHit) { console.log("[PICK] no part here"); return }
        var l = r.objectHit.mapPositionFromScene(r.scenePosition)   // RAW coordinates of the model
        var t = l.x.toFixed(3) + "," + l.y.toFixed(3) + "," + l.z.toFixed(3)
        console.log("[PICK] " + t)
        root.picks = root.picks.concat([{ raw: t, scene: r.scenePosition }])
    }
    property real doorLeftOpen: (debugParts || pickDebug) ? 1 : 0
    property real doorRightOpen: 0
    property real doorMaxAngle: 62          // gradi a portiera spalancata
    // The Smart's trunk in TWO pieces: top hatch (rear window) + bottom door.
    // trunkOpen: 0 = closed, 1 = open (opening and closing: first the rear window moves, then the door)
    property real trunkOpen: 0
    property real hatchMaxAngle: 55
    property real flapMaxAngle: 90
    property real _hatch: trunkOpen
    property real _flap: trunkOpen
    Behavior on _hatch { SequentialAnimation {
        PauseAnimation { duration: 0 }
        NumberAnimation { duration: 700; easing.type: Easing.InOutCubic } } }
    Behavior on _flap { SequentialAnimation {
        PauseAnimation { duration: 720 }
        NumberAnimation { duration: 600; easing.type: Easing.InOutCubic } } }
    on_HatchChanged: root._applyDoors()
    on_FlapChanged: root._applyDoors()
    property real _doorL: doorLeftOpen
    property real _doorR: doorRightOpen
    Behavior on _doorL { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
    Behavior on _doorR { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
    on_DoorLChanged: root._applyDoors()
    on_DoorRChanged: root._applyDoors()

    property var _doorNodes: []   // [{ l: Node, r: Node }] per car + reflection
    function _findByName(node, name) {
        if (!node || !node.children) return null
        for (var i = 0; i < node.children.length; i++) {
            var c = node.children[i]
            if (c.objectName === name) return c
            var f = root._findByName(c, name)
            if (f) return f
        }
        return null
    }
    // Qt does not carry the glTF node names to QML: I recognize the two door nodes from
    // the position of their pivot (hinge at x = +-0.68, y = -0.546, z = 0) and from the number of children.
    function _findDoorNodes(node, out) {
        if (!node || !node.children) return
        for (var i = 0; i < node.children.length; i++) {
            var c = node.children[i]
            if (c.position !== undefined && c.children && c.children.length >= 5 && c.children.length < 60
                    && Math.abs(Math.abs(c.position.x) - 0.685) < 0.02
                    && Math.abs(c.position.y + 0.5600) < 0.02 && Math.abs(c.position.z) < 0.02)
                out.push(c)
            root._findDoorNodes(c, out)
        }
    }
    function _findAt(node, x, y, z, out) {
        if (!node || !node.children) return
        for (var i = 0; i < node.children.length; i++) {
            var c = node.children[i]
            if (c.position !== undefined && Math.abs(c.position.x - x) < 0.01
                    && Math.abs(c.position.y - y) < 0.01 && Math.abs(c.position.z - z) < 0.01)
                out.push(c)
            root._findAt(c, x, y, z, out)
        }
    }
    function _setupDoors(loaderItem) {
        var found = []
        root._findDoorNodes(loaderItem, found)
        if (found.length !== 2) { console.log("[CarScene] doors NOT found (found", found.length, "nodi)"); return }
        var a = found[0], b = found[1]
        var h = [], f = []
        root._findAt(loaderItem, 0.0, 0.9315, 1.4754, h)   // rear-window pivot (hinge on the roof)
        root._findAt(loaderItem, 0.0, 1.22, 0.70, f)   // pivot sportello basso
        if (debugMode) console.log("[CarScene] portiere + baule trovati:", h.length, f.length)
        root._doorNodes.push({ r: (a.position.x > 0 ? a : b), l: (a.position.x > 0 ? b : a),
                               hatch: h.length ? h[0] : null, flap: f.length ? f[0] : null })
        root._applyDoors()
    }
    function _applyDoors() {
        for (var i = 0; i < root._doorNodes.length; i++) {
            var d = root._doorNodes[i]
            // doorLeftOpen = vehicle's LEFT door (x>0 side of the model = "DoorR" node)
            d.r.eulerRotation = Qt.vector3d(0, 0, -root._doorL * root.doorMaxAngle)
            d.l.eulerRotation = Qt.vector3d(0, 0,  root._doorR * root.doorMaxAngle)
            if (d.hatch) d.hatch.eulerRotation = Qt.vector3d( root._hatch * root.hatchMaxAngle, 0, 0)
            if (d.flap)  d.flap.eulerRotation  = Qt.vector3d(-root._flap  * root.flapMaxAngle, 0, 0)
        }
    }

    // ═══ TUNING PRESTAZIONI (file opzionale ~/.config/volta_car3d, es. "ao=0,aa=1") ═══
    SystemHelper { id: tuneSys }
    readonly property var _tune: {
        var o = {}
        try {
            var home = Core.StandardPaths.writableLocation(Core.StandardPaths.HomeLocation).toString().replace("file://", "")
            var txt = tuneSys.readTextFile(home + "/.config/volta_car3d")
            var parts = txt.split(/[,\s]+/)
            for (var i = 0; i < parts.length; i++) {
                var kv = parts[i].split("=")
                if (kv.length === 2) o[kv[0]] = parseInt(kv[1])
            }
        } catch (e) {}
        if (debugMode) console.log("[car3d] tuning:", JSON.stringify(o))
        return o
    }
    // Low performance: reflection, ambient occlusion, anti-aliasing and light rays off, reduced resolution
    property bool lowPower: false
    readonly property var _lowTune: ({ refl: 0, ao: 0, aa: 0, beam: 0, rs: 75 })
    function tv(key, def) {
        if (root.lowPower && root._lowTune[key] !== undefined) return root._lowTune[key]
        var v = root._tune[key]
        return (v === undefined || isNaN(v)) ? def : v
    }

    // ═══ LIGHT RAYS (like light filtering through a window, with dust) ═══
    property real beamOpacity: 0.34      // 0 = spento
    // The "cellar" light (rays) disappears when the car panel is small: tt=0 small, 1 full screen
    readonly property real beamFade: Math.max(0, Math.min(1, (root.tt - 0.03) / 0.2))
    property real beamWidth: 3.6         // beam width (scene units)
    property real beamRotationSec: 140   // one slow turn of the beam: the stripes move
    property bool beamDust: true         // pulviscolo in sospensione
    readonly property string _beamTex: "qrc:/VoltaApp/car3d/tex/beamTex.png"

    // ═══ FLOOR ═══
    // Floor texture (rough asphalt/concrete, continuous tile). Intensity 0..1 and repetitions.
    property real floorTexAmount: 1.0
    // dl70: very faint concrete texture (almost imperceptible) in place of the rough one
    readonly property string _floorTexSub: "qrc:/VoltaApp/car3d/tex/floorTexSub.jpg"
    property real floorTexRepeatX: 5   // dl70
    property real floorTexRepeatY: 3   // dl70
    // Reflection blur (0 = sharp, 0.2-0.5 = soft glossy as in the photo)
    property real reflBlur: 0.10   // dl67
    // Pool of light on the floor around the car: radius (scene units) and intensity
    property real poolRadius: 5.5
    property real poolOpacity: 0.55

    property real iblExposure: 0.06
    // values for the Smart
    property real iblExposureCar: 0.30   // dl65
    property real fillBrightnessCar: 0.2   // dl65
    property real bounceBrightnessCar: 0.3   // dl65
    property real carMetal: 0.10   // dl65
    property real carRough: 0.50   // dl65
    property real carCoat: 0.30   // dl65
    property real carCoatRough: 0.25   // dl65
    property real keyBrightnessCar: 0.9   // dl65
    property real rimBrightnessCar: 0.4   // dl65
    property real probeHorizonCar: 0.5
    // Rim lights from behind/side (reflections on the body's edges)
    property real rimBrightness: 1.1
    property real keyBrightness: 2.6
    // Depth below the floor at which the reflection has completely vanished (floor = -0.5)
    property real reflFadeY: -2.0   // dl67
    // In the light theme the fog is white and "washes out" the reflection: we make it act deeper
    property real reflFadeYLight: -2.4

    // ═══ BACKGROUND FOG (fades the floor into the background, behind the car) ═══
    // fogStartOffset: distance beyond the car center where the fade begins
    // fogEndOffset:   distance beyond the car center where the floor = background color
    property real fogStartOffset: 1.6
    property real fogEndOffset: 9.0

    // Diameter of the faded floor (scene units). Adjust 16–30.
    property real floorSize: 32

    // Opacity of the floor above the reflection: lower = more visible reflection
    // Dark theme: dark gray floor above the reflection
    property real floorOpacityDark: 0.78   // it was 0.45: the reflection was too visible
    // Light theme: the floor is almost white, so it must veil less or the reflection disappears
    property real floorOpacityLight: 0.72
    readonly property real floorOpacity: lightTheme ? floorOpacityLight : floorOpacityDark
    // Radius in which the floor stays solid above the reflection (units from the car center).
    // The roof's reflection, seen from above, falls up to ~5 units toward the camera.
    property real floorSolidRadius: 6.5
    readonly property real _floorSolidPos: Math.min(0.9, floorSolidRadius / (floorSize / 2))
    
    // ═══ CAR PAINT COLOR (settable from Settings, as in EV OS) ═══
    Core.Settings {
        id: carPrefs
        category: "ui"
        property string carColor: "#C8C9CA"
        property string carFinish: "lucida"
    }
    // paint texture (orange peel + fine grain) on the body
    property real paintTexStrength: 0.0      // 0 = off, 0.2..0.6 consigliato
    property real paintTexTile: 2.0           // >1 = grana piu' fine
    readonly property string _paintNormData: "qrc:/VoltaApp/car3d/tex/paintNormData.png"
    // texture interni: pelle sedili, moquette pavimento/bagagliaio
    property real seatTexStrength: 0.12
    property real seatTexTile: 5.0
    property real carpetTexStrength: 0.6
    property real carpetTexTile: 1.2
    readonly property string _leatherNormData: "qrc:/VoltaApp/car3d/tex/leatherNormData.png"
    readonly property string _carpetNormData: "qrc:/VoltaApp/car3d/tex/carpetNormData.png"
    readonly property string _carpetColData: "qrc:/VoltaApp/car3d/tex/carpetColData.png"
    // tappetino trapuntato (rombi + cuciture) e fari anteriori
    property real sillTexStrength: 0.0
    property real sillTexTile: 4.0
    readonly property string _sillNormData: "qrc:/VoltaApp/car3d/tex/sillNormData.png"
    readonly property string _beamData: "qrc:/VoltaApp/car3d/tex/beamData.png"
    property bool headlightsOn: false
    property var _lensMats: []
    onHeadlightsOnChanged: root._updateLens()
    function _updateLens() {
        for (var i = 0; i < root._lensMats.length; i++) {
            var e = root._lensMats[i], m = e.m
            if ("emissiveFactor" in m) m.emissiveFactor = root.headlightsOn ? Qt.vector3d(e.k, e.k * 1.03, e.k * 1.07) : Qt.vector3d(0, 0, 0)
        }
    }
    function _mkTex(data, tile, tag) {
        return Qt.createQmlObject('import QtQuick; import QtQuick3D; Texture { tilingModeHorizontal: Texture.Repeat; tilingModeVertical: Texture.Repeat; generateMipmaps: true; mipFilter: Texture.Linear; scaleU: ' + tile + '; scaleV: ' + tile + '; sourceItem: Image { source: "' + data + '" } }', root, tag)
    }
    function _applyInteriorTex(all, which) {
        var lens = []
        for (var k = 0; k < all.length; k++) {
            var m = all[k]
            if (Math.abs(m.metalness - 0.0919) < 0.004 && Math.abs(m.roughness - 0.5137) < 0.004 && root.seatTexStrength > 0) {
                m.normalMap = root._mkTex(root._leatherNormData, root.seatTexTile, "seatN_" + which)
                m.normalStrength = root.seatTexStrength
            } else if (Math.abs(m.metalness - 0.0611) < 0.004 && Math.abs(m.roughness - 0.5333) < 0.004 && root.sillTexStrength > 0) {
                m.normalMap = root._mkTex(root._sillNormData, root.sillTexTile, "sillN_" + which)
                m.normalStrength = root.sillTexStrength
            } else if (Math.abs(m.metalness - 0.0377) < 0.004 && Math.abs(m.roughness - 0.7123) < 0.004) {
                if ("specularAmount" in m) m.specularAmount = 0.05
            } else if (Math.abs(m.metalness - 0.9137) < 0.01 && Math.abs(m.roughness - 0.1141) < 0.004) {
                lens.push({ m: m, k: 0.14 })
            } else if (Math.abs(m.roughness - 0.0731) < 0.0008 && m.metalness < 0.01) {
                lens.push({ m: m, k: 1.0 })
            } else if (Math.abs(m.roughness - 0.0529) < 0.0008 && m.metalness < 0.01) {
                lens.push({ m: m, k: 1.3 })
            } else if (Math.abs(m.metalness - 0.0713) < 0.004 && Math.abs(m.roughness - 0.8271) < 0.004 && root.carpetTexStrength > 0) {
                m.normalMap = root._mkTex(root._carpetNormData, root.carpetTexTile, "carpetN_" + which)
                m.normalStrength = root.carpetTexStrength
                m.baseColorMap = root._mkTex(root._carpetColData, root.carpetTexTile, "carpetC_" + which)
            }
        }
        root._lensMats = root._lensMats.concat(lens)
        root._updateLens()
    }
    // ═══ 3D CAR FROM .glb FILE (the bundled one or the user's) ═══
    // ═══ CAR ADJUSTMENT (position, size, shadow, buttons): saved and restorable ═══
    // Adjustments and color are saved in the car's data (see CarModelManager::saveCurrentMeta).
    Core.Settings { id: carLayoutPrefs; category: "car3d"; property string layout: "" }      // old single save: used only once to migrate
    readonly property var _layoutDefaults: ({ carX: 0, carY: 0, carScale: 1, shX: 0, shZ: 0, shLen: 1, shWid: 1, shLock: false, yawExtra: 0, anchors: ({}) })
    function _mergeLayout(saved) {
        var l = JSON.parse(JSON.stringify(root._layoutDefaults))
        for (var k in l) if (saved && saved[k] !== undefined) l[k] = saved[k]
        return l
    }
    function _loadLayout() {
        var meta = CarModels.currentMeta()
        if (meta.layout !== undefined) return root._mergeLayout(meta.layout)
        // first time with this version: if there was a single save, it becomes that of the car in use
        try { var old = JSON.parse(carLayoutPrefs.layout || "{}"); if (Object.keys(old).length && CarModels.cars.length === 1) return root._mergeLayout(old) } catch (e) {}
        return root._mergeLayout({})
    }
    property var layout: root._loadLayout()
    function _saveLayout() { CarModels.saveCurrentMeta({ layout: root.layout }) }
    function setLayout(key, v) {
        var l = JSON.parse(JSON.stringify(root.layout)); l[key] = v
        root.layout = l; root._saveLayout()
    }
    function resetLayout() { root.layout = root._mergeLayout({}); root._saveLayout() }
    // saves the current color and finish in the data of the car in use (end of the setup)
    function saveCarColor() { CarModels.saveCurrentMeta({ color: "" + carPrefs.carColor, finish: carPrefs.carFinish }) }
    // car change: its adjustments and its color are loaded
    function _applyCarMeta() {
        root.layout = root._loadLayout()
        var m = CarModels.currentMeta()
        if (m.color) carPrefs.carColor = m.color
        else root.saveCarColor()            // car without a saved color: keeps the current one and saves it, so it no longer changes with the other cars
        if (m.finish) carPrefs.carFinish = m.finish
    }
    Connections {
        target: carPrefs
        function onCarColorChanged() { CarModels.saveCurrentMeta({ color: "" + carPrefs.carColor }) }
        function onCarFinishChanged() { CarModels.saveCurrentMeta({ finish: carPrefs.carFinish }) }
    }
    // ── Buttons on the car (lock, hood, trunk): each one is attached to a POINT OF THE CAR (car coordinates),
    // so it follows the car when the panel changes size or the car rotates. The line goes down from the button to that point.
    function anchorFor(key) {
        var a = root.layout.anchors[key]
        if (a) return a
        if (!userCarMain) return null
        var b = userCarMain._bnd
        if (!b) return null
        var s = userCarMain.lengthScale, L = (b.maxz - b.minz) * s, H = (b.maxy - b.miny) * s
        if (key === "lock") return [0, H * 0.95, 0]
        if (key === "rear") return [0, H * 0.80, -L * 0.40]
        return [0, H * 0.70, L * 0.38]                      // hood
    }
    function setAnchor(key, p) {
        var o = JSON.parse(JSON.stringify(root.layout.anchors)); o[key] = [Math.round(p[0] * 1000) / 1000, Math.round(p[1] * 1000) / 1000, Math.round(p[2] * 1000) / 1000]
        root.setLayout("anchors", o)
    }
    // car point -> coordinates of another element (to draw buttons and lines)
    function carPointToItem(local, item) {
        if (!userCarMain) return Qt.point(-1000, 0)
        var sc = userCarMain.mapPositionToScene(Qt.vector3d(local[0], local[1], local[2]))
        var p = view.mapFrom3DScene(sc)
        return view.mapToItem(item, p.x, p.y)
    }
    // the mesh (Model) under the finger/mouse: needed by the setup to choose a part by touching the car
    function pickModelAt(item, x, y) {
        var p = item.mapToItem(view, x, y)
        var r = view.pick(p.x, p.y)
        return (r && r.objectHit) ? r.objectHit : null
    }
    // car point under the finger/mouse (null if the car is not there)
    function pickCarPoint(item, x, y) {
        var p = item.mapToItem(view, x, y)
        var r = view.pick(p.x, p.y)
        if (!r || !r.objectHit) return null
        if (!userCarMain) return null
        var l = userCarMain.mapPositionFromScene(r.scenePosition)
        if (l.y < 0.05) return null                          // the floor is not the car
        return [l.x, l.y, l.z]
    }
    property bool adjustOpen: false           // "Car adjust" panel
    // true during the guided setup and the adjustment: the rest of the interface (odometer, mini-map...) hides
    readonly property bool configuring: carSetup.visible || carAdjust.visible
    property var userCarMain: null                           // istanza dell'auto
    property int _partsRev: 0                                // goes up when the chosen parts change
    function _curIdx() { var l = CarModels.cars; for (var i = 0; i < l.length; i++) if (l[i].current) return i; return 0 }
    function _bindMain() { root.userCarMain = carInstances.objectAt(root._curIdx()) }
    Connections { target: CarModels; function onPartsChanged() { root._partsRev++ } }
    // true: the rest of the interface (odometer, mini-map, widgets...) hides
    readonly property bool uiHidden: configuring
    onTtChanged: { if (root.tt < 0.9) root.userZoom = 1.0 }     // zoom only applies in full screen: with the reduced panel it is reset
    property bool moveButtons: false          // the buttons (lock, trunk, hood) can be dragged
    Connections {
        target: CarModels
        function onCarInstalled() { root.replacing = false; root._carErr = "" }
        function onCurrentChanged() { root._applyCarMeta(); root._bindMain() }
        function onConvertFailed(reason) { root._carErr = reason }
        function onAdjustRequested() { root.adjustOpen = true }
        function onReloadRequested() { root.replacing = true; root.adjustOpen = false }
    }
    // "Load a new model": the current car hides and the blue button appears; "Cancel" brings it back
    property bool replacing: false
    property real hoodOpen: 0
    property real _hood: hoodOpen
    Behavior on _hood { NumberAnimation { duration: 750; easing.type: Easing.InOutCubic } }
    function _has(v) { return v !== undefined && v !== null && v !== "" && (typeof v === "string" || v.length === undefined || v.length > 0) }      // a part can be a mesh or a list of meshes
    readonly property bool hasHood: root.userCarActive && !!root._carInfo.parts && root._has(root._carInfo.parts.hood)
    readonly property bool hasTrunk: root.userCarActive && !!root._carInfo.parts && root._has(root._carInfo.parts.trunk)
    property bool useGlbCar: true
    readonly property bool smartOn: false       // the old car (Smart) is no longer shown: only the user's car is there
    readonly property var _carInfo: { var r = CarModels.revision; return CarModels.carFile !== "" ? CarModels.currentParts() : ({}) }
    readonly property bool userCarActive: root.useGlbCar && _carInfo.ok === true
    readonly property var _fin: root._finishParams(root.carFinish)
    property color carPaintColor: carPrefs.carColor
    // dl68: color with which the floor REFLECTION is drawn (it does not follow the Toybox wrapper)
    property color reflPaintColor: "#8A8B8C"          // medium gray: with the brightness below the reflection it becomes dark gray (not white)

    // ═══ TIPO DI VERNICE (Toybox › Colorizer): "lucida" | "pastello" | "opaca" ═══
    property string carFinish: carPrefs.carFinish
    onCarFinishChanged: root.applyFinish()
    function _finishParams(f) {
        if (f === "opaca")    return { metalness: 0.05, roughness: 0.85, clearcoat: 0.0, clearcoatRough: 0.6 }
        if (f === "pastello") return { metalness: 0.0,  roughness: 0.35, clearcoat: 0.6, clearcoatRough: 0.15 }
        return                       { metalness: root.carMetal, roughness: root.carRough, clearcoat: root.carCoat, clearcoatRough: root.carCoatRough }   // lucida
    }
    function _applyFinishTo(mat, f) {
        if (!mat) return
        var p = root._finishParams(f)
        if ("metalness" in mat) mat.metalness = p.metalness
        if ("roughness" in mat) mat.roughness = p.roughness
        if ("clearcoatAmount" in mat) mat.clearcoatAmount = p.clearcoat
        if ("clearcoatRoughnessAmount" in mat) mat.clearcoatRoughnessAmount = p.clearcoatRough
    }
    // Only the real car: the reflection stays dark and opaque as it is
    function applyFinish() {
        root._applyFinishTo(root._bodyCloneMain, root.carFinish)
        for (var i = 0; i < root._paintTargetsMain.length; i++)
            root._applyFinishTo(root._paintTargetsMain[i], root.carFinish)
    }
    Behavior on carPaintColor { ColorAnimation { duration: 450; easing.type: Easing.OutCubic } }

    readonly property int _bodyMaterialIndex: 3
    readonly property int _bumperMaterialIndex: -1
    readonly property var _bodyExcludedOccurrences: []

    // The reflection uses the same precompiled meshes as the car (CarBodyModel/CarWheelModel):
    // it appears together with the car. Before, the reflection's wheels waited for the first
    // frame + 400 ms and then parsed wheel.glb 4 times with RuntimeLoader.
    property var _paintTargetsMain: []
    property var _paintTargetsRefl: []
    property var _bodyCloneMain: null
    property var _bodyCloneRefl: null

    function _collectAllMaterials(node, out) {
        if (!node || !node.children) return
        for (var i = 0; i < node.children.length; i++) {
            var child = node.children[i]
            if (child.materials !== undefined) {
                for (var m = 0; m < child.materials.length; m++) {
                    var mat = child.materials[m]
                    if (mat && ("baseColor" in mat) && out.indexOf(mat) < 0) {
                        out.push(mat)
                    }
                }
            }
            root._collectAllMaterials(child, out)
        }
    }

    function _collectNodesWithMaterial(node, targetMat, out) {
        if (!node || !node.children) return
        for (var i = 0; i < node.children.length; i++) {
            var child = node.children[i]
            if (child.materials !== undefined) {
                for (var m = 0; m < child.materials.length; m++) {
                    if (child.materials[m] === targetMat) {
                        out.push({ node: child, slot: m })
                    }
                }
            }
            root._collectNodesWithMaterial(child, targetMat, out)
        }
    }

    // Reflection brightness: 1.0 = like the car, 0.25 = dark and faint reflection (EV OS style)
    property real reflBrightness: 0.45   // dl67 (it was 0.55: the reflection came out too light)
    // Reflection opacity per theme (0 = invisible, 1 = full)
    property real reflOpacityDark: 0.90   // dl67
    property real reflOpacityLight: 0.3
    readonly property real reflOpacity: lightTheme ? reflOpacityLight : reflOpacityDark
    function _dimRefl(c) {
        var k = root.reflBrightness
        // desaturates toward gray and darkens
        var l = (c.r + c.g + c.b) / 3
        var sat = 0.8
        return Qt.rgba((l + (c.r - l) * sat) * k, (l + (c.g - l) * sat) * k, (l + (c.b - l) * sat) * k, c.a)
    }

    function _dimReflLoader(loaderItem) {
        var all = []
        root._collectAllMaterials(loaderItem, all)
        for (var r = 0; r < all.length; r++) {
            var rm = all[r]
            rm.baseColor = root._dimRefl(rm.baseColor)
            if ("specularAmount" in rm) rm.specularAmount = rm.specularAmount * root.reflBrightness
            if ("emissiveFactor" in rm) rm.emissiveFactor = Qt.vector3d(0, 0, 0)
        }
    }

    function _applyPaint(targets, col) {
        for (var i = 0; i < targets.length; i++) targets[i].baseColor = col
    }

    function _setupLoader(loaderItem, which) {
        var all = []
        root._collectAllMaterials(loaderItem, all)

        // Diagnostics: list of materials (to calibrate glass/rims/tires)
        if (debugMode && which === "main") {
            for (var d = 0; d < all.length; d++) {
                var dm = all[d]
                console.log("[CarScene] mat", d, "col", dm.baseColor, "met", dm.metalness, "rough", dm.roughness, "opac", dm.opacity)
            }
        }

        // Reflection: darkens and switches off all the materials, so it looks like a real reflection
        // (faint and desaturated) instead of a second full-color car.
        if (which === "refl") {
            for (var r = 0; r < all.length; r++) {
                var rm = all[r]
                rm.baseColor = root._dimRefl(rm.baseColor)
                if ("specularAmount" in rm) rm.specularAmount = rm.specularAmount * root.reflBrightness
                if ("emissiveFactor" in rm) rm.emissiveFactor = Qt.vector3d(0, 0, 0)
            }
        }

        var simple = []
        var bumperMat = all[root._bumperMaterialIndex]
        if (bumperMat) simple.push(bumperMat)

        // the paint is recognized from the metallic/roughness marker (independent of the order of the materials)
        var bodyMat = null
        for (var pi = 0; pi < all.length; pi++) {
            if (Math.abs(all[pi].metalness - 0.6137) < 0.004 && Math.abs(all[pi].roughness - 0.3841) < 0.004) { bodyMat = all[pi]; break }
        }
        if (!bodyMat) bodyMat = all[root._bodyMaterialIndex]
        var bodyClone = null
        if (bodyMat) {
            var occ = []
            root._collectNodesWithMaterial(loaderItem, bodyMat, occ)

            bodyClone = Qt.createQmlObject('import QtQuick3D; PrincipledMaterial { }', root, "bodyClone_" + which)
            bodyClone.baseColor = root.carPaintColor
            if (root.paintTexStrength > 0) {
                var pn = Qt.createQmlObject('import QtQuick; import QtQuick3D; Texture { tilingModeHorizontal: Texture.Repeat; tilingModeVertical: Texture.Repeat; generateMipmaps: true; mipFilter: Texture.Linear; scaleU: ' + root.paintTexTile + '; scaleV: ' + root.paintTexTile + '; sourceItem: Image { source: root._paintNormData } }', root, "paintNormTex_" + which)
                bodyClone.normalMap = pn
                bodyClone.normalStrength = root.paintTexStrength
            }

            var frozenClone = null
            if (root._bodyExcludedOccurrences.length > 0) {
                frozenClone = Qt.createQmlObject('import QtQuick3D; PrincipledMaterial { }', root, "bodyFrozen_" + which)
                frozenClone.baseColor = bodyMat.baseColor
            }

            if (which === "refl") {
                bodyClone.specularAmount = 0.5 * root.reflBrightness
                if (frozenClone) frozenClone.specularAmount = 0.5 * root.reflBrightness
            }

            for (var i = 0; i < occ.length; i++) {
                var target = root._bodyExcludedOccurrences.indexOf(i) >= 0 ? frozenClone : bodyClone
                var mats = occ[i].node.materials
                mats[occ[i].slot] = target
                occ[i].node.materials = mats
            }
        }

        root._applyInteriorTex(all, which)

        if (which === "refl") {
            root._paintTargetsRefl = simple
            root._bodyCloneRefl = bodyClone
        } else {
            root._paintTargetsMain = simple
            root._bodyCloneMain = bodyClone
        }
    }

    function repaintLoader(loaderItem, which) {
        if (which === "main" && root.debugParts) return   // colored parts: no paint
        if (loaderItem.status !== undefined && loaderItem.status !== RuntimeLoader.Success) return
        var setupDone = which === "refl" ? (root._bodyCloneRefl !== null) : (root._bodyCloneMain !== null)
        if (!setupDone) {
            root._setupLoader(loaderItem, which)
        }
        if (which === "refl") {
            root._applyPaint(root._paintTargetsRefl, root._dimRefl(root.reflPaintColor))
            if (root._bodyCloneRefl) root._bodyCloneRefl.baseColor = root._dimRefl(root.reflPaintColor)
        } else {
            root._applyPaint(root._paintTargetsMain, root.carPaintColor)
            if (root._bodyCloneMain) root._bodyCloneMain.baseColor = root.carPaintColor
            root.applyFinish()
        }
    }

    function repaintCarBody() {
        root._applyPaint(root._paintTargetsMain, root.carPaintColor)
        root._applyPaint(root._paintTargetsRefl, root._dimRefl(root.reflPaintColor))
        if (root._bodyCloneMain) root._bodyCloneMain.baseColor = root.carPaintColor
        if (root._bodyCloneRefl) root._bodyCloneRefl.baseColor = root._dimRefl(root.reflPaintColor)
    }
    onCarPaintColorChanged: root.repaintCarBody()

    readonly property real tt: Math.max(0, Math.min(1, (panelRatio - 0.35) / (1.0 - 0.35)))
    function lerp(a, b, k) { return a + (b - a) * k }


    property real targetCamRadius: (root.lerp(root.radiusSmall, root.radiusLarge, root.tt) * root.userZoom)
    property real targetCamFov: root.lerp(root.fovSmall, root.fovLarge, root.tt)
    property real targetPivotY: root.lerp(root.pivotYSmall, root.pivotYLarge, root.tt)
    property real targetCarRot: root.lerp(root.carRotSmallDeg, root.carRotLargeDeg, root.tt)






    property real wheelSpin: 0

    readonly property real carRotSmallDeg: -41.40
    readonly property real carRotLargeDeg: -55.8
    readonly property real radiusSmall: 11.20
    readonly property real radiusLarge: 6.5   // dl68
    readonly property real fovSmall: 35.00
    readonly property real fovLarge: 38
    readonly property real pivotYSmall: -0.10
    // Full screen: camera aim point. Lower = camera lower
    // and car/scene higher in the frame (it was 0.2, then -0.15;
    // now a bit higher: car a bit lower in the frame)
    readonly property real pivotYLarge: 0.02   // dl68

    property real targetAzimuth: 7.9
    property real fsElevationDeg: 4.5   // dl68: camera elevation in fullscreen (it was 6.5)
    property real fsMinElevationDeg: 2.0   // dl70: minimum elevation when dragging in fullscreen (before 14 for everyone)
    property real userZoom: 1.0           // dl70: zoom with fingers (multiplies the camera distance)
    property real zoomMin: 0.75   // dl72
    property real zoomMax: 1.0   // dl71
    property real targetElevation: 17.6
    property real azimuthDeg: 7.9
    property real elevationDeg: 17.6

    property real currentCamRadius: (root.lerp(root.radiusSmall, root.radiusLarge, root.tt) * root.userZoom)
    property real currentCamFov: root.lerp(root.fovSmall, root.fovLarge, root.tt)
    property real currentPivotY: root.lerp(root.pivotYSmall, root.pivotYLarge, root.tt)
    property real currentCarRot: root.lerp(root.carRotSmallDeg, root.carRotLargeDeg, root.tt)

    function resetView(instant, toFullscreen) {
        var targetAz = toFullscreen ? 0 : 7.9
        var targetEl = toFullscreen ? root.fsElevationDeg : 17.6

        var cur = root.azimuthDeg % 360
        if (cur > 180) cur -= 360
        else if (cur <= -180) cur += 360
        root.azimuthDeg = cur

        if (instant) {
            root.azimuthDeg = targetAz
            root.elevationDeg = targetEl
            root.targetAzimuth = targetAz
            root.targetElevation = targetEl
            return
        }
        root.targetAzimuth = targetAz
        root.targetElevation = targetEl
    }

    Component.onCompleted: resetView(true, root.tt > 0.5)

    // True until the camera/car has reached its target. At rest
    // the animation switches off and the scene stops redrawing for nothing.
    readonly property bool _settling:
        Math.abs(root.targetAzimuth   - root.azimuthDeg)       > 0.01
     || Math.abs(root.targetElevation - root.elevationDeg)     > 0.01
     || Math.abs(root.targetCamRadius - root.currentCamRadius) > 0.001
     || Math.abs(root.targetCamFov    - root.currentCamFov)    > 0.01
     || Math.abs(root.targetPivotY    - root.currentPivotY)    > 0.001
     || Math.abs(root.targetCarRot    - root.currentCarRot)    > 0.01

    FrameAnimation {
        running: root._settling
        onTriggered: {
            let speed = 8.0
            let factor = 1.0 - Math.exp(-speed * frameTime)

            let activeAzimuth = root.targetAzimuth
            root.azimuthDeg += (activeAzimuth - root.azimuthDeg) * factor

            root.elevationDeg += (root.targetElevation - root.elevationDeg) * factor

            root.currentCamRadius += (root.targetCamRadius - root.currentCamRadius) * factor
            root.currentCamFov += (root.targetCamFov - root.currentCamFov) * factor
            root.currentPivotY += (root.targetPivotY - root.currentPivotY) * factor
            root.currentCarRot += (root.targetCarRot - root.currentCarRot) * factor

        }
    }

    // ═══ BACKGROUND ═══
    Rectangle {
        id: sceneBg
        anchors.fill: parent
        color: root.lightTheme ? "white" : "#000000"
    }
    // dl63: colored GLOW behind the car (takes the paint color)
    property bool carGlowOn: true
    property real carGlowStrength: 0.40   // dl72
    property real carGlowW: 0.62   // dl71
    property real carGlowH: 0.62   // dl71
    property real carGlowYOffset: 0.08   // dl69
    property real carGlowCut: 0.16   // dl72
    property real carGlowSoft: 0.14   // dl72: height (fraction of the screen) of the gradient at the base of the glow
    property real glowSpeedOut: 3.0   // dl72: disappearance speed (high = fast)
    // dl69: the glow is only there in full screen AND with the camera close to the default framing (azimuth 0, elevation fsElevationDeg)
    readonly property real _glowAz: ((root.azimuthDeg % 360) + 540) % 360 - 180
    // dl71: 'slow' value of the glow: follows _glowView with a relaxed transition (SmoothedAnimation, glowSpeed = units per second)
    property real glowSpeed: 0.45
    property real _glowShown: root._glowView
    Behavior on _glowShown { SmoothedAnimation { velocity: (root._glowView < root._glowShown ? root.glowSpeedOut : root.glowSpeed); easing.type: Easing.InOutSine } }
    readonly property real _glowView: Math.max(0, Math.min(1, (root.panelRatio - 0.85) / 0.15))
            * Math.max(0, Math.min(1, (34 - Math.abs(root._glowAz)) / 24))
            * Math.max(0, Math.min(1, (10 - Math.abs(root.elevationDeg - root.fsElevationDeg)) / 7))
    // dl68: height of the HORIZON on the screen, from the camera's tilt (it does not depend on the car)
    property real carGlowY: 0.5 - 0.5 * Math.tan(root.elevationDeg * Math.PI / 180) / Math.tan(root.currentCamFov * Math.PI / 360) + root.carGlowYOffset
    readonly property color _carGlowCol: {
        var c = root.carPaintColor
        var l = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        if (l < 0.05) return Qt.rgba(0.30, 0.34, 0.42, 1)          // auto nera: alone grigio-azzurro tenue
        var k = l < 0.15 ? Math.min(3, 0.15 / l) : (l > 0.4 ? 0.55 : 1)   // scuri: alone piu' vivo, chiari: piu' morbido
        return Qt.rgba(Math.min(1, c.r * k), Math.min(1, c.g * k), Math.min(1, c.b * k), 1)
    }
    Item {
        id: carGlowItem
        anchors.fill: parent
        visible: opacity > 0.01 && root.carGlowOn && !root.lightTheme && !root.fsdMode
        opacity: root._glowShown
        // dl69: hard cut: below the line (carGlowY + carGlowCut) the "floor" covers the glow
        Item {
            x: 0; y: 0
            width: carGlowItem.width
            height: carGlowItem.height * (root.carGlowY + root.carGlowCut)
            clip: true
            // dl72: faded base: the glow fades toward black instead of being cut off sharply
            Rectangle {
                z: 1
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: carGlowItem.height * root.carGlowSoft
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                    GradientStop { position: 1.0; color: "#000000" }
                }
            }
            Shape {
            id: carGlowShape
            width: 1000; height: 1000
            x: carGlowItem.width * 0.5 - 500
            y: carGlowItem.height * root.carGlowY - 500
            transform: Scale {
                origin.x: 500; origin.y: 500
                xScale: carGlowItem.width * root.carGlowW / root.userZoom / 1000
                yScale: carGlowItem.height * root.carGlowH / root.userZoom / 1000
            }
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: 500; centerY: 500; centerRadius: 500
                    focalX: 500; focalY: 500; focalRadius: 0
                    GradientStop { position: 0.00; color: Qt.alpha(root._carGlowCol, 1.00 * root.carGlowStrength) }
                    GradientStop { position: 0.50; color: Qt.alpha(root._carGlowCol, 0.90 * root.carGlowStrength) }
                    GradientStop { position: 0.75; color: Qt.alpha(root._carGlowCol, 0.55 * root.carGlowStrength) }
                    GradientStop { position: 0.90; color: Qt.alpha(root._carGlowCol, 0.20 * root.carGlowStrength) }
                    GradientStop { position: 1.00; color: Qt.alpha(root._carGlowCol, 0.0) }
                }
                startX: 0; startY: 0
                PathLine { x: 1000; y: 0 }
                PathLine { x: 1000; y: 1000 }
                PathLine { x: 0;    y: 1000 }
                PathLine { x: 0;    y: 0 }
            }
        }
        }
    }

    // Intermediate layer: it sits ABOVE the background and BELOW reflection and 3D car
    // (the mini-map ends up there, assigned by Main.qml through CarPanel.sceneMidLayer).
    Item {
        id: midLayerItem
        anchors.fill: parent
    }
    property alias midLayer: midLayerItem.data
    property alias midItem: midLayerItem   // to attach 2D elements behind the car (car panel lines)

    // ═══ RIFLESSO (vista 3D separata) ═══
    // The reflection is rendered on its own with the same camera and drawn BELOW
    // the main scene with adjustable opacity (reflOpacity).
    Item {
        id: reflLayer
        anchors.fill: parent
        visible: root.tv("refl", 1) !== 0
        opacity: root.reflOpacity
        layer.enabled: true          // always: it also serves to remove any color from the reflection (saturation -1)
        layer.textureSize: reflView.rsf < 1
            ? Qt.size(Math.max(1, Math.round(width * Screen.devicePixelRatio * reflView.rsf)),
                      Math.max(1, Math.round(height * Screen.devicePixelRatio * reflView.rsf)))
            : Qt.size(0, 0)
        layer.effect: MultiEffect {
            saturation: -1.0          // the reflection is always grayscale, whatever color the car has
            blurEnabled: root.reflBlur > 0
            blur: root.reflBlur * Math.min(1.0, reflView.rsf / 0.6)
            blurMax: 40
            autoPaddingEnabled: false
        }

        View3D {
            id: reflView
            readonly property real rsf: Math.max(0.3, Math.min(1.0, root.tv("rrs", 40) / 100))
            x: 0; y: 0
            width: parent.width * rsf
            height: parent.height * rsf
            scale: 1 / rsf
            transformOrigin: Item.TopLeft
            camera: reflCam
            renderMode: View3D.Offscreen

            environment: SceneEnvironment {
                backgroundMode: SceneEnvironment.Transparent
                antialiasingMode: SceneEnvironment.NoAA
                tonemapMode: SceneEnvironment.TonemapModeAces
                lightProbe: Texture { source: "qrc:/VoltaApp/car3d/ferndale_studio_11_1k.hdr" }
                probeExposure: root.iblExposureCar
            probeHorizon: root.probeHorizonCar

                // The reflection fades into the background color as it goes below the floor
                fog: Fog {
                    enabled: true
                    color: root.lightTheme ? "white" : "#000000"
                    depthEnabled: false
                    heightEnabled: true
                    leastIntenseY: -0.5
                    mostIntenseY: root.lightTheme ? root.reflFadeYLight : root.reflFadeY
                    heightCurve: 1.0
                }
            }

            Node {
                position: Qt.vector3d(0, root.currentPivotY, 0)
                eulerRotation.x: -root.elevationDeg
                eulerRotation.y: root.azimuthDeg
                PerspectiveCamera {
                    id: reflCam
                    position: Qt.vector3d(0, 0, root.currentCamRadius)
                    fieldOfView: root.currentCamFov
                    clipNear: 0.1
                    clipFar: 100.0
                }
            }

            DirectionalLight { eulerRotation.x: -80; brightness: root.keyBrightnessCar }
            DirectionalLight { eulerRotation.x: -25; eulerRotation.y: -125; brightness: 0.3 }
            DirectionalLight { eulerRotation.x: -15; eulerRotation.y: 180; brightness: 0.2 }

            Node {
                position.y: -1.0
                scale: Qt.vector3d(1, -1, 1)

                Node {
                    eulerRotation.y: root.currentCarRot
                    UserCar {
                        visible: root.userCarActive && !root.replacing
                        file: root.userCarActive ? CarModels.carFile : ""
                        parts: root._carInfo.parts || ({})
                        names: root._carInfo.names || []
                        mats: root._carInfo.mats || []
                        rows: root._carInfo.rows || []
                        pivots: root._carInfo.pivots || []
                        userYaw: root.layout.yawExtra
                        angles: (root._carInfo.parts && root._carInfo.parts.angles) || ({})
                        position: Qt.vector3d(root.layout.carX, -0.5 + root.layout.carY, 0)
                        userScale: root.layout.carScale
                        hoodOpen: root._hood
                        doorL: root._doorL
                        doorR: root._doorR
                        trunkOpen: root._hatch
                        wheelSpin: root.wheelSpin
                        reflection: true      // reflection: all gray, never colored (not even by the Colorizer)
                        paintColor: root.reflPaintColor
                        brightness: 1.0       // the darkness comes from the veil and the fade: with dark paint the doors seemed to be missing
                        metal: 0.05; rough: 0.85; coat: 0; coatRough: 0.6
                    }
                    CarBodyModel {   // dl72: same model as the car (with doors, trunk...) instead of car_riflesso.glb
                        id: carBodyRefl
                        visible: root.smartOn
                        Component.onCompleted: {
                            carBodyRefl.position = Qt.vector3d(0, -0.5, 0)
                            root.repaintLoader(carBodyRefl, "refl")
                            root._setupDoors(carBodyRefl)
                        }
                    }
                    Node {
                        position: Qt.vector3d(-0.648, -0.2001, 0.893)
                        visible: root.smartOn
                        scale: Qt.vector3d(1.04, 1.04, 1.04)
                        eulerRotation.y: 180
                        CarWheelModel {   // stesse mesh precompilate dell'auto: pronte subito
                            id: wheelRefl0
                            eulerRotation.x: -root.wheelSpin
                            Component.onCompleted: root._dimReflLoader(wheelRefl0)
                        }
                    }
                    Node {
                        position: Qt.vector3d(0.636, -0.2001, 0.893)
                        visible: root.smartOn
                        scale: Qt.vector3d(1.04, 1.04, 1.04)
                        eulerRotation.y: 0
                        CarWheelModel {   // stesse mesh precompilate dell'auto: pronte subito
                            id: wheelRefl1
                            eulerRotation.x: root.wheelSpin
                            Component.onCompleted: root._dimReflLoader(wheelRefl1)
                        }
                    }
                    Node {
                        position: Qt.vector3d(-0.664, -0.1914, -0.95)
                        visible: root.smartOn
                        scale: Qt.vector3d(1.07, 1.07, 1.07)
                        eulerRotation.y: 180
                        CarWheelModel {   // stesse mesh precompilate dell'auto: pronte subito
                            id: wheelRefl2
                            eulerRotation.x: -root.wheelSpin
                            Component.onCompleted: root._dimReflLoader(wheelRefl2)
                        }
                    }
                    Node {
                        position: Qt.vector3d(0.652, -0.1914, -0.95)
                        visible: root.smartOn
                        scale: Qt.vector3d(1.07, 1.07, 1.07)
                        eulerRotation.y: 0
                        CarWheelModel {   // stesse mesh precompilate dell'auto: pronte subito
                            id: wheelRefl3
                            eulerRotation.x: root.wheelSpin
                            Component.onCompleted: root._dimReflLoader(wheelRefl3)
                        }
                    }
                }
            }
        }

    }

    // dl70: dark VEIL above the reflection (makes it less visible). reflVeil: 0 = no veil, 1 = solid black
    property real reflVeil: 0.55
    Rectangle {
        visible: !root.lightTheme && !root.fsdMode && root.reflVeil > 0.01
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: parent.height * 0.5
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 0.2;  color: Qt.rgba(0, 0, 0, root.reflVeil) }
            GradientStop { position: 1.0;  color: Qt.rgba(0, 0, 0, root.reflVeil) }
        }
    }


    View3D {
        id: view
        Repeater3D {
            model: root.pickDebug ? root.picks : []
            Model {
                source: "#Sphere"
                position: modelData.scene
                scale: Qt.vector3d(0.0012, 0.0012, 0.0012)
                materials: PrincipledMaterial { baseColor: "#ff2bd6"; lighting: PrincipledMaterial.NoLighting }
            }
        }
        // Reduced rendering resolution (volta_car3d: rs=percentage, 100 = as it was), then enlarged
        readonly property real rsf: Math.max(0.3, Math.min(1.0, root.tv("rs", 100) / 100))
        x: 0; y: 0
        width: parent.width * rsf
        height: parent.height * rsf
        scale: 1 / rsf
        transformOrigin: Item.TopLeft
        camera: cam
        renderMode: View3D.Offscreen

        environment: sceneEnv
        SceneEnvironment {
            id: sceneEnv
            // Transparent: underneath the background and the blurred reflection are visible
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: root.tv("aa", 2) === 0 ? SceneEnvironment.NoAA : SceneEnvironment.MSAA
            antialiasingQuality: root.tv("aa", 2) === 1 ? SceneEnvironment.Medium : SceneEnvironment.High
            tonemapMode: SceneEnvironment.TonemapModeAces
            lightProbe: Texture { source: "qrc:/VoltaApp/car3d/ferndale_studio_11_1k.hdr" }
            probeExposure: root.iblExposureCar
            probeHorizon: root.probeHorizonCar
            // Ambient occlusion: contact shadows in the gaps, interiors and joints (less "plastic" effect)
            aoEnabled: root.tv("ao", 1) !== 0
            aoStrength: 45
            aoDistance: 0.12
            aoSoftness: 30
            aoSampleRate: 3
            aoBias: 0.01
            aoDither: true

            // Fog moved BEHIND the car: the car stays sharp,
            // the floor fades gradually into the background color.
            fog: Fog {
                enabled: true
                color: root.lightTheme ? "white" : "#000000"
                depthEnabled: true
                depthNear: root.currentCamRadius + root.fogStartOffset
                depthFar:  root.currentCamRadius + root.fogEndOffset
                depthCurve: 1.0
                heightEnabled: false
                leastIntenseY: -0.5
                mostIntenseY: -1.5
                heightCurve: 1.0
            }
        }

        Node {
            id: pivot
            position: Qt.vector3d(0, root.currentPivotY, 0)
            eulerRotation.x: -root.elevationDeg
            eulerRotation.y: root.azimuthDeg

            PerspectiveCamera {
                id: cam
                position: Qt.vector3d(0, 0, root.currentCamRadius)
                fieldOfView: root.currentCamFov
                clipNear: 0.1
                clipFar: 100.0
            }
        }

        // dl63: frontal fill light (brightens the shadowed areas of the Smart)
        DirectionalLight {
            visible: !root.lightTheme
            eulerRotation.x: -12
            eulerRotation.y: 20
            brightness: root.fillBrightnessCar
        }
        // dl65: bounce from below (light floor): brightens the lower part of the body
        DirectionalLight {
            visible: !root.lightTheme
            eulerRotation.x: 35
            eulerRotation.y: 25
            brightness: root.bounceBrightnessCar
            color: "#E8E8EA"
        }
        DirectionalLight {
            eulerRotation.x: -80
            brightness: root.keyBrightnessCar
            castsShadow: root.tv("shadow", 1) !== 0
            shadowMapQuality: Light.ShadowMapQualityMedium
            shadowFactor: 90
            shadowBias: 8
            softShadowQuality: Light.PCF16
        }
        DirectionalLight {
            eulerRotation.x: -25
            eulerRotation.y: -125
            brightness: 0.3 + root.rimBrightnessCar * 0.6
            color: "#DDE8FF"
        }
        // Qt Quick 3D handles at most 4 directional lights: with the dark theme 
        // fill + bounce + main + back light are on, so this one
        // (rear back light) is switched off — before it was on and Qt discarded it anyway
        // ("Too many directional lights in scene, maximum is 4").
        DirectionalLight {
            visible: root.lightTheme
            eulerRotation.x: -15
            eulerRotation.y: 180
            brightness: (0.2 + root.rimBrightnessCar * 0.5)
            color: "#FFF1E0"
        }

        // Soft pool of light on the floor (soft-box above the car), fades to black
        Model {
            depthBias: -8
            visible: !root.lightTheme
            source: "#Rectangle"
            eulerRotation.x: -90
            position: Qt.vector3d(0, -0.497, -0.4)
            castsShadows: false
            receivesShadows: false
            scale: Qt.vector3d(root.poolRadius * 2 / 100, root.poolRadius * 1.5 / 100, 1)
            materials: PrincipledMaterial {
                baseColor: "#B8BCC6"
                lighting: PrincipledMaterial.NoLighting
                alphaMode: PrincipledMaterial.Blend
                opacity: root.poolOpacity * (0.5 + 0.5 * root.tt)
                baseColorMap: Texture {
                    sourceItem: Shape {
                        width: 512; height: 512
                        ShapePath {
                            strokeWidth: -1
                            strokeColor: "transparent"
                            fillGradient: RadialGradient {
                                centerX: 256; centerY: 256; centerRadius: 256
                                focalX: 256; focalY: 256; focalRadius: 0
                                GradientStop { position: 0.00; color: "#FFFFFFFF" }
                                GradientStop { position: 0.20; color: "#B3FFFFFF" }
                                GradientStop { position: 0.45; color: "#59FFFFFF" }
                                GradientStop { position: 0.70; color: "#1AFFFFFF" }
                                GradientStop { position: 0.92; color: "#00FFFFFF" }
                            }
                            startX: 0; startY: 0
                            PathLine { x: 512; y: 0 }
                            PathLine { x: 512; y: 512 }
                            PathLine { x: 0;   y: 512 }
                            PathLine { x: 0;   y: 0 }
                        }
                    }
                }
            }
        }

        Model {
            visible: true
            depthBias: -4
            source: "#Rectangle"
            eulerRotation.x: -90
            position: Qt.vector3d(0, -0.5, 0)
            // Circular floor that fades into the background through the radial mask
            // (fog does not act on NoLighting materials, so the fade is in the texture).
            // floorSize = diameter in scene units: higher = wider glow.
            scale: Qt.vector3d(root.floorSize / 100, root.floorSize / 100, 1)
            materials: PrincipledMaterial {
                baseColor: root.lightTheme ? Qt.rgba(0.88, 0.88, 0.88, root.floorOpacity) : Qt.rgba(0.10, 0.115, 0.15, root.floorOpacity)
                lighting: PrincipledMaterial.NoLighting
                baseColorMap: Texture {
                    sourceItem: Image { source: root._floorTexSub; width: 512; height: 512; smooth: true }
                    tilingModeHorizontal: Texture.Repeat
                    tilingModeVertical: Texture.Repeat
                    scaleU: root.floorTexRepeatX
                    scaleV: root.floorTexRepeatY
                    generateMipmaps: true
                    mipFilter: Texture.Linear
                }
                // Radial gradient generated directly in QML (no PNG to load):
                // white at the center = solid floor, black at the edge = transparent.
                opacityMap: Texture {
                    sourceItem: Shape {
                        width: 512; height: 512
                        ShapePath {
                            strokeWidth: -1
                            strokeColor: "transparent"
                            fillGradient: RadialGradient {
                                centerX: 256; centerY: 256; centerRadius: 256
                                focalX: 256; focalY: 256; focalRadius: 0
                                // solid up to floorSolidRadius (covers the whole area where the reflection is seen),
                                // then fades to the edge of the disc
                                GradientStop { position: 0.0; color: "#FFFFFF" }
                                GradientStop { position: root._floorSolidPos; color: "#FFFFFF" }
                                GradientStop { position: root._floorSolidPos + (0.97 - root._floorSolidPos) * 0.35; color: "#A0A0A0" }
                                GradientStop { position: root._floorSolidPos + (0.97 - root._floorSolidPos) * 0.70; color: "#383838" }
                                GradientStop { position: 0.97; color: "#000000" }
                            }
                            startX: 0; startY: 0
                            PathLine { x: 512; y: 0 }
                            PathLine { x: 512; y: 512 }
                            PathLine { x: 0;   y: 512 }
                            PathLine { x: 0;   y: 0 }
                        }
                    }
                }
                opacityChannel: Material.R
                alphaMode: PrincipledMaterial.Blend
            }
        }

        // ═══ LIGHT RAYS in the 3D scene: they move with the camera ═══
        // Four crossed planes with a soft striped texture + dust.
        Node {
            id: beamRig
            visible: (!root.lightTheme && root.beamOpacity > 0 && root.tv("beam", 1) !== 0 && root.beamFade > Math.max(0.001, root.tv("bmin", 0) / 100))
            position: Qt.vector3d(-0.4, -0.5, -0.5)
            eulerRotation.z: 7
            Node {
                id: beamSpin
                eulerRotation.y: 0
                NumberAnimation on eulerRotation.y {
                    running: beamRig.visible && root.beamRotationSec > 0
                    from: 0; to: 360; loops: Animation.Infinite
                    duration: Math.max(10, root.beamRotationSec) * 1000
                }
                Repeater3D {
                    model: 4
                    delegate: Model {
                        required property int index
                        source: "#Rectangle"
                        // the plane starts from the floor and goes up: pivot at the center, hence a lift of half the height
                        // staggered axes: the planes do not all add up on the same line,
                        // so a narrow bright core does not form at the center
                        position: Qt.vector3d(((index * 37) % 7 - 3) * 0.16, 3.25, ((index * 53) % 7 - 3) * 0.16)
                        eulerRotation.y: index * 45 + 11
                        scale: Qt.vector3d(root.beamWidth * (1.0 + 0.22 * index) / 100, 6.5 / 100, 1)
                        castsShadows: false
                        receivesShadows: false
                        depthBias: -2
                        materials: PrincipledMaterial {
                            lighting: PrincipledMaterial.NoLighting
                            alphaMode: PrincipledMaterial.Blend
                            cullMode: Material.NoCulling
                            baseColorMap: Texture {
                                sourceItem: Image { source: root._beamTex; asynchronous: false; cache: true }
                                generateMipmaps: true
                                mipFilter: Texture.Linear
                            }
                            // each plane "breathes" with its own phase and duration: the light is never uniform
                            property real breathe: 1.0
                            // A plane seen edge-on is a sharp line: I make it fade gently
                            // when it is almost parallel to the view direction (like a real volumetric beam)
                            readonly property real faceFactor: {
                                var d = (beamSpin.eulerRotation.y + index * 45 + 11 - root.azimuthDeg) * Math.PI / 180
                                var f = Math.abs(Math.cos(d))
                                return Math.pow(Math.min(1, f / 0.7), 1.8)
                            }
                            opacity: root.beamOpacity * root.beamFade * 0.6 * breathe * (0.35 + 0.65 * faceFactor) * faceFactor
                            SequentialAnimation on breathe {
                                running: beamRig.visible
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 3800 + index * 1300; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0;  duration: 4600 + index * 900;  easing.type: Easing.InOutSine }
                            }
                        }
                    }
                }
                // Dust: tiny faint dots floating inside the beam
                Repeater3D {
                    model: root.beamDust ? 26 : 0
                    delegate: Model {
                        required property int index
                        readonly property real sd: ((index * 7919) % 1000) / 1000
                        readonly property real sd2: ((index * 104729) % 1000) / 1000
                        source: "#Sphere"
                        castsShadows: false
                        receivesShadows: false
                        scale: Qt.vector3d(1, 1, 1).times((0.00004 + sd * 0.00005))
                        property real baseY: 0.3 + sd2 * 4.6
                        position: Qt.vector3d((sd - 0.5) * 2.4, baseY, (sd2 - 0.5) * 2.4)
                        SequentialAnimation on baseY {
                            running: beamRig.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.5 + sd * 4.2; duration: 9000 + sd * 7000; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0.3 + sd2 * 4.6; duration: 9000 + sd2 * 7000; easing.type: Easing.InOutSine }
                        }
                        materials: PrincipledMaterial {
                            lighting: PrincipledMaterial.NoLighting
                            baseColor: "#EAF0FF"
                            alphaMode: PrincipledMaterial.Blend
                            opacity: 0.16 + sd * 0.18
                        }
                    }
                }
            }
        }

        Node {
            id: carRoot
            eulerRotation.y: root.currentCarRot

            // ═══ REAL SHADOW FROM BLENDER BAKE (INVERTED: BLACK BACKGROUND, WHITE SILHOUETTE) ═══
            Model {
                source: "#Rectangle"
                eulerRotation.x: -90
                position: Qt.vector3d(root.layout.shX, -0.49, root.layout.shZ)
                // Exact dimensions from the model: car 1.757 × 2.694 + fade margin 1.1 per side
                // → plane 3.957 × 4.894 units
                scale: Qt.vector3d(0.039572 * root.layout.shWid, 0.048939 * 1.28 * root.layout.shLen, 1)
                visible: root.userCarActive && !root.replacing
                castsShadows: false
                receivesShadows: false
                depthBias: -10
                materials: PrincipledMaterial {
                    baseColor: "black"
                    lighting: PrincipledMaterial.NoLighting
                    opacity: 0.9
                    opacityMap: Texture { source: "qrc:/VoltaApp/car3d/shadow_car.png" }
                    opacityChannel: Material.R // Reads the red/brightness channel (black background = transparent, white silhouette = black shadow)
                    alphaMode: PrincipledMaterial.Blend
                    depthDrawMode: Material.NeverDepthDraw
                }
            }

            // ═══ FRONT HEADLIGHTS: light beams on the ground (EV style) ═══
            Model {
                id: beamModel
                depthBias: -30
                source: "#Rectangle"
                eulerRotation.x: 90
                position: Qt.vector3d(0, -0.465, 3.65)
                scale: Qt.vector3d(0.056, 0.0506, 1)
                castsShadows: false
                receivesShadows: false
                visible: opacity > 0.01
                opacity: root.headlightsOn ? 0.34 : 0
                Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                materials: PrincipledMaterial {
                    baseColor: "#F4F8FF"
                    lighting: PrincipledMaterial.NoLighting
                    cullMode: Material.NoCulling
                    opacityMap: Texture { sourceItem: Image { source: root._beamData } }
                    opacityChannel: Material.R
                    alphaMode: PrincipledMaterial.Blend
                    depthDrawMode: Material.NeverDepthDraw
                }
            }

            Model {
                id: beamModel2
                depthBias: -30
                source: "#Rectangle"
                eulerRotation.x: 90
                position: Qt.vector3d(0, -0.463, 3.65)
                scale: Qt.vector3d(0.056, 0.0506, 1)
                castsShadows: false
                receivesShadows: false
                visible: opacity > 0.01
                opacity: root.headlightsOn ? 0.34 : 0
                Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                materials: PrincipledMaterial {
                    baseColor: "#F4F8FF"
                    lighting: PrincipledMaterial.NoLighting
                    cullMode: Material.NoCulling
                    opacityMap: Texture { sourceItem: Image { source: root._beamData } }
                    opacityChannel: Material.R
                    alphaMode: PrincipledMaterial.Blend
                    depthDrawMode: Material.NeverDepthDraw
                }
            }

            // L'auto in uso (`userCarMain`).
            Repeater3D {
                id: carInstances
                model: CarModels.cars.length
                onObjectAdded: root._bindMain()
                onObjectRemoved: root._bindMain()
                delegate: UserCar {
                    id: inst
                    required property int index
                    readonly property var gi: CarModels.cars[index] || ({ id: "", file: "", current: false })
                    readonly property bool isCur: !!gi.current
                    readonly property bool wanted: root.useGlbCar && gi.id !== "" && isCur
                    readonly property var cinfo: { var r = root._partsRev; return wanted ? CarModels.partsFor(gi.id) : ({}) }
                    readonly property var meta: wanted && !isCur ? CarModels.metaFor(gi.id) : ({})
                    readonly property var lay: isCur ? root.layout : root._mergeLayout(meta.layout)
                    readonly property bool okInfo: cinfo.ok === true
                    visible: wanted && okInfo && !root.replacing
                    file: (wanted && okInfo) ? gi.file : ""
                    parts: cinfo.parts || ({})
                    names: cinfo.names || []
                    mats: cinfo.mats || []
                    rows: cinfo.rows || []
                    pivots: cinfo.pivots || []
                    userYaw: lay.yawExtra
                    angles: (cinfo.parts && cinfo.parts.angles) || ({})
                    position: Qt.vector3d(lay.carX, -0.5 + lay.carY, 0)
                    userScale: lay.carScale
                    hoodOpen: isCur ? root._hood : 0
                    doorL: isCur ? root._doorL : 0
                    doorR: isCur ? root._doorR : 0
                    trunkOpen: isCur ? root._hatch : 0
                    wheelSpin: isCur ? root.wheelSpin : 0
                    paintColor: isCur ? root.carPaintColor : (meta.color ? meta.color : root.carPaintColor)
                    metal: root._fin.metalness; rough: root._fin.roughness
                    coat: root._fin.clearcoat; coatRough: root._fin.clearcoatRough
                }
            }

            CarBodyModel {
                id: carBodyFast
                visible: !root.debugParts && root.smartOn
                Component.onCompleted: {
                    if (root.debugParts) return
                    carBodyFast.position = Qt.vector3d(0, -0.5, 0)
                    root.repaintLoader(carBodyFast, "main")
                    root._setupDoors(carBodyFast)
                    if (root.pickDebug) root._enablePick(carBodyFast)
                }
            }
            RuntimeLoader {
                id: carLoader
                source: root.debugParts ? appUrl + "/assets/car3d/car_body_debug.glb" : ""
                onStatusChanged: {
                    if (status === RuntimeLoader.Success) {
                        var b = carLoader.bounds
                        var cx = (b.minimum.x + b.maximum.x) / 2
                        var cz = (b.minimum.z + b.maximum.z) / 2
                        carLoader.position = Qt.vector3d(0, -0.5, 0)   // fixed: bounds not reliable with openable nodes
                        root.repaintLoader(carLoader, "main")
                        root._setupDoors(carLoader)
                        if (root.pickDebug) root._enablePick(carLoader)
                    }
                }
            }

            Node {
                position: Qt.vector3d(-0.648, -0.2001, 0.893)
                visible: root.smartOn
                scale: Qt.vector3d(1.04, 1.04, 1.04)
                eulerRotation.y: 180
                CarWheelModel {
                    eulerRotation.x: -root.wheelSpin
                }
            }

            Node {
                position: Qt.vector3d(0.636, -0.2001, 0.893)
                visible: root.smartOn
                scale: Qt.vector3d(1.04, 1.04, 1.04)
                eulerRotation.y: 0
                CarWheelModel {
                    eulerRotation.x: root.wheelSpin
                }
            }

            Node {
                position: Qt.vector3d(-0.664, -0.1914, -0.95)
                visible: root.smartOn
                scale: Qt.vector3d(1.07, 1.07, 1.07)
                eulerRotation.y: 180
                CarWheelModel {
                    eulerRotation.x: -root.wheelSpin
                }
            }

            Node {
                position: Qt.vector3d(0.652, -0.1914, -0.95)
                visible: root.smartOn
                scale: Qt.vector3d(1.07, 1.07, 1.07)
                eulerRotation.y: 0
                CarWheelModel {
                    eulerRotation.x: root.wheelSpin
                }
            }
        }
    }

    MouseArea {
        id: orbitMA
        anchors.fill: parent
        property real lastX: 0
        property real lastY: 0
        property real downX: 0
        property real downY: 0
        // dl70: zoom with two fingers and wheel (only a little: zoomMin..zoomMax)
        PinchHandler {
            id: pinchZoom
            target: null
            minimumPointCount: 2; maximumPointCount: 2
            property real z0: 1
            onActiveChanged: if (active) z0 = root.userZoom
            onActiveScaleChanged: if (active) root.userZoom = Math.max(root.zoomMin, Math.min(root.zoomMax, z0 / Math.pow(activeScale, 0.5)))
        }
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (e) => root.userZoom = Math.max(root.zoomMin, Math.min(root.zoomMax, root.userZoom * (e.angleDelta.y > 0 ? 0.985 : 1.015)))
        }
        onReleased: (m) => {
            if (carSetup.picking && Math.abs(m.x - downX) + Math.abs(m.y - downY) < 12) { carSetup.pickAt(orbitMA, m.x, m.y); return }     // mesh selection: a tap on the car selects the mesh
            if (root.pickDebug && Math.abs(m.x - downX) + Math.abs(m.y - downY) < 6) root.doPick(m.x, m.y)
            // dl70: snap to the default framing (fullscreen) if released almost there
            if (root.tt > 0.9 && !root.fsdMode) {
                var azN = ((root.targetAzimuth % 360) + 540) % 360 - 180
                if (Math.abs(azN) < 7 && Math.abs(root.targetElevation - root.fsElevationDeg) < 3.5) {
                    root.targetAzimuth -= azN
                    root.targetElevation = root.fsElevationDeg
                }
            }
        }

        onPressed: (m) => {
            downX = m.x; downY = m.y
            lastX = m.x
            lastY = m.y
            root.targetAzimuth = root.azimuthDeg
            root.targetElevation = root.elevationDeg
        }

        onPositionChanged: (m) => {
            if (!pressed || pinchZoom.active) return
            root.targetAzimuth -= (m.x - lastX) * 0.15
            root.targetElevation = Math.max(root.tt > 0.5 ? root.fsMinElevationDeg : 14, Math.min(89, root.targetElevation + (m.y - lastY) * 0.15))
            lastX = m.x
            lastY = m.y
        }
    }

    // ═══ NO CAR: blue "Load 3D car" button in place of the car ═══
    property string _carErr: ""
    Column {
        visible: (!root.userCarActive || root.replacing) && !root.fsdMode
        anchors.centerIn: parent
        z: 60
        spacing: 12
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 240; height: 52; radius: 8
            color: _loadCarMA.pressed ? "#1E63D0" : "#2C7BF2"
            Behavior on color { ColorAnimation { duration: 100 } }
            Text { anchors.centerIn: parent; text: qsTr("Load 3D car"); color: "#FFFFFF"; font.pixelSize: 17; font.weight: Font.DemiBold }
            MouseArea { id: _loadCarMA; anchors.fill: parent; onClicked: { root._carErr = ""; carPicker.open() } }
        }
        Text {
            visible: root._carErr !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(root.width - 40, 320); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            text: root._carErr; color: "#FF6B6B"; font.pixelSize: 14
        }
        Text {
            visible: CarModels.converting
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(root.width - 40, 320); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            text: qsTr("Converting the model… it may take a minute.")
            color: root.lightTheme ? "#555555" : "#BBBBBB"; font.pixelSize: 14
        }
        Text {      // changed mind: the previous car comes back
            visible: root.replacing
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Cancel and keep the current car"); color: root.lightTheme ? "#555555" : "#BBBBBB"; font.pixelSize: 14; font.underline: true
            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { root.replacing = false; root._carErr = "" } }
        }
    }
    FileDialog {
        id: carPicker
        title: qsTr("Choose the 3D car file")
        nameFilters: [qsTr("3D car (*.glb *.gltf *.fbx *.obj *.dae *.blend)"), qsTr("All files (*)")]
        onAccepted: {
            var f = selectedFile.toString(), a = CarModels.analyze(f)
            if (a.heavy) { root._pendingFile = f; root._heavyInfo = a; heavyDlg.visible = true }
            else root._carErr = CarModels.installCar(f, false)
        }
    }
    // ═══ AVVISO: MODELLO TROPPO PESANTE ═══
    property string _pendingFile: ""
    property var _heavyInfo: ({})
    Item {
        id: heavyDlg
        anchors.fill: parent
        z: 90
        visible: false
        Rectangle { anchors.fill: parent; color: "#99000000"; MouseArea { anchors.fill: parent } }
        Item {
            id: heavyCard
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 520); height: hCol.height + 48
            GlassPanel { anchors.fill: parent; z: -1; sources: [sceneBg, carGlowItem, reflLayer, view]; lightTheme: root.lightTheme; radius: 18 }
            Column {
                id: hCol
                x: 24; y: 24; width: parent.width - 48; spacing: 14
                Text { width: parent.width; wrapMode: Text.WordWrap; text: qsTr("This model is very heavy")
                       color: root.lightTheme ? "#1D1D1F" : "#FFFFFF"; font.pixelSize: 22; font.weight: Font.DemiBold }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: qsTr("It weighs about %1 MB and has about %2 thousand triangles: the interface may become slow. You can lighten it (less detail and smaller textures), but this does not guarantee the best display.")
                          .arg(Math.round(root._heavyInfo.sizeMB || 0)).arg(Math.round((root._heavyInfo.triangles || 0) / 1000))
                    color: root.lightTheme ? "#555555" : "#BBBBBB"; font.pixelSize: 15
                }
                Rectangle {
                    width: parent.width; height: 52; radius: 10
                    color: _hl.pressed ? "#1E63D0" : "#2C7BF2"
                    Text { anchors.centerIn: parent; text: qsTr("Lighten and load"); color: "#FFFFFF"; font.pixelSize: 17; font.weight: Font.DemiBold }
                    MouseArea { id: _hl; anchors.fill: parent; onClicked: { heavyDlg.visible = false; root._carErr = CarModels.installCar(root._pendingFile, true) } }
                }
                Row {
                    spacing: 10
                    Rectangle {
                        width: (hCol.width - 10) / 2; height: 46; radius: 10
                        color: _hn.pressed ? "#4A4A4A" : "#3A3A3A"
                        Text { anchors.centerIn: parent; text: qsTr("Load as is"); color: "#FFFFFF"; font.pixelSize: 15 }
                        MouseArea { id: _hn; anchors.fill: parent; onClicked: { heavyDlg.visible = false; root._carErr = CarModels.installCar(root._pendingFile, false) } }
                    }
                    Rectangle {
                        width: (hCol.width - 10) / 2; height: 46; radius: 10
                        color: _hc.pressed ? "#4A4A4A" : "#3A3A3A"
                        Text { anchors.centerIn: parent; text: qsTr("Cancel"); color: "#FFFFFF"; font.pixelSize: 15 }
                        MouseArea { id: _hc; anchors.fill: parent; onClicked: heavyDlg.visible = false }
                    }
                }
            }
        }
    }
    // guided setup: starts by itself after loading the car
    CarSetup {
        id: carSetup
        anchors.fill: parent
        z: 70
        rig: userCarMain
        scene: root
        blurSources: [sceneBg, carGlowItem, reflLayer, view]
        lightTheme: root.lightTheme
        visible: root.userCarActive && !root.replacing && !root.fsdMode && !CarModels.configured
        info: visible ? CarModels.inspect(CarModels.carFile) : ({})
    }

    CarAdjust {
        id: carAdjust
        anchors.fill: parent
        z: 71
        scene: root
        blurSources: [sceneBg, carGlowItem, reflLayer, view]
        lightTheme: root.lightTheme
        visible: root.adjustOpen && root.userCarActive && !root.replacing && (!carSetup.visible || (carSetup.cur && carSetup.cur.kind === "adjust"))
        onClosed: { root.adjustOpen = false; if (carSetup.visible && carSetup.cur && carSetup.cur.kind === "adjust") carSetup.next() }
    }

    Rectangle {
        visible: root.pickDebug
        anchors.left: parent.left; anchors.bottom: parent.bottom
        anchors.margins: 12
        width: 420; height: 44 + Math.ceil(root.picks.length / 2) * 20; radius: 8
        color: "#CC000000"
        Column {
            anchors.fill: parent; anchors.margins: 10; spacing: 2
            Text { color: "#FFD400"; font.pixelSize: 13; font.bold: true
                   text: "PICK: click the parts that float (tap here = reset)" }
            Grid {
                columns: 2; columnSpacing: 14; rowSpacing: 2
                Repeater {
                    model: root.picks
                    Text { color: "white"; font.pixelSize: 12; text: (index + 1) + ") " + modelData.raw }
                }
            }
        }
        MouseArea { anchors.fill: parent; onClicked: root.picks = [] }
    }

}
