import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import QtQuick.Effects
import QtLocation
import QtPositioning
import QtWebSockets
import Qt5Compat.GraphicalEffects
import QtCore
import QtCore as Core
import QtQuick.VirtualKeyboard   // needed: EnterKeyAction (the on-screen keyboard's "Search" key)
import VoltaApp 1.0

Item {
    id: root

    property bool lightTheme: false
    property bool active: true

    // ── Map lock: when an app is open above the map, no dragging,
    // zoom (pinch/wheel) or long press, to avoid accidental movements
    // while using the app. Simple taps stay active.
    // Da Main.qml:  mapLocked: <app aperta>
    property bool mapLocked: false

    // Toybox › Mars: the map becomes Mars and the whole navigation
    // interface (search, route, panels) disappears beneath it.
    property bool marsMode: false

    property string mapStyle: "flat"

    // Toggle POI e Meteo
    property bool poisEnabled: false
    property bool weatherEnabled: false

    // Set by Main.qml in "full-screen map" mode: the column
    // of buttons below (compass/recenter + the 5) must be hidden because it
    // shows up elsewhere, in a horizontal row next to the music widget
    // (mapToolsBar) — it avoids showing it twice.
    property bool externalControls: false

    // ── Measures from the wireframe (canvas 1070 px wide): search bar 243 x 47 at 10 px
    // from the map's left edge and 41 px from the top; "reposition" button 47 x 47 at
    // 10 px from the right edge and 41 px from the top. Everything scales with the window width.
    readonly property real uPx: (Window.window ? Window.window.width : 1200) / 1070
    readonly property real mapPad: 10 * uPx      // margine laterale/spaziatura standard
    readonly property real topPad: 41 * uPx      // distance from the top edge
    readonly property real panelW: 243 * uPx     // width of the search bar and aligned panels
    readonly property real barH: 47 * uPx        // bar height / button side
    readonly property real fS: barH / 56         // factor for the content drawn on 56 px
    // Distance from the bottom of the navigation panel (10 px above the dock). Set by Main.qml.
    property real dockClearance: 69

    // "Full-screen map" mode + an app open on the side: here the
    // "upcoming directions" panel shows ONLY the current turn in
    // top (no list of next turns, no destination, no
    // arrival/remaining time) — with the app open the space on the left is more
    // precious and the user asked to reduce the navigation panel to
    // a minimum in this specific case. Without an open app (map
    // "at home" in full screen) all the extended content stays instead.
    readonly property bool compactNav: externalControls && mapLocked
    // height of the blue bar at the bottom left (0 if absent): Main.qml moves the player above it with an app open
    readonly property real navPanelH: navPanel.visible ? navPanel.height : 0
    // Bottom-left slot shared with the music player (full-screen map + open app):
    // Main.qml sets navSlotMusic when the player must be shown; a swipe on the blue bar swaps it.
    property real navSlotPos: 0          // 0 = blue bar in front, 1 = slid away (carousel, driven by Main.qml)
    readonly property real navSlotW: 393 * uPx            // same width as the player (full-screen map)
    property real navSlotH: 122 * uPx                      // same height as the player (Main.qml: musicWidget.baseH)
    readonly property real navSlotTravel: navSlotW + 14 * uPx
    // Left margin of the panels below the search bar: in full-screen map the 4 buttons sit
    // in a column below the recenter button, so the panels shift to the right of the column
    readonly property real leftInset: externalControls ? (mapPad * 2 + barH) : mapPad

    // Set by Main.qml in "full-screen map" mode when an app
    // is open on the side (map that stays full screen, no longer narrowed
    // — see mapLayer in Main.qml): how many pixels to shift the map center
    // "optically" to the right, so that the car/arrow stays visible in the
    // free strip on the left instead of ending up under the app. 0 = none
    // shift (normal behavior, real center = screen center).
    property real followOffsetPx: 0

    // Converts a "real" coordinate (e.g. car position) into the coordinate
    // that, if put at the center of the map, makes that point appear shifted
    // by "followOffsetPx" pixels to the left of the real screen center — that is: since
    // we want the car to appear on the left, we must center the map a bit more
    // to the right of the real point. It uses map.fromCoordinate/toCoordinate (pixel <->
    // coordinate) to compute the equivalent lat/lon offset, then
    // applies it in the opposite direction to the final center.
    function coordinateForCenterBias(coord, brg) {
        if (followOffsetPx === 0 || !map) return coord
        var c0 = map.fromCoordinate(map.center, false)
        var c1 = map.toCoordinate(Qt.point(c0.x + followOffsetPx, c0.y), false)
        var dLat = c1.latitude  - map.center.latitude
        var dLon = c1.longitude - map.center.longitude
        if (brg !== undefined) {   // dl82: same shift, recomputed for the map's arrival angle
            var kx = Math.cos(map.center.latitude * Math.PI / 180)
            var e = dLon * kx, n = dLat
            var mag = Math.sqrt(e * e + n * n)
            var cb = map.bearing * Math.PI / 180
            if (e * Math.cos(cb) - n * Math.sin(cb) < 0) mag = -mag       // verso (destra/sinistra) dello spostamento
            var tb = brg * Math.PI / 180
            dLon = mag * Math.cos(tb) / kx
            dLat = -mag * Math.sin(tb)
        }
        return QtPositioning.coordinate(coord.latitude - dLat, coord.longitude - dLon)
    }

    // ── Auto-hide of the tool buttons
    property bool toolsVisible: true
    property bool covered: false      // a full-screen app covers the map: periodic checks stop
    Timer {
        id: toolsHideTimer
        interval: 4000
        onTriggered: root.toolsVisible = false
    }
    function pokeToolsVisibility() {
        root.toolsVisible = true
        toolsHideTimer.restart()
    }

    // Night effect on the satellite (Settings › Navigation: Off / On / Auto)
    property bool satNight: false

    readonly property int styleIndex: {
        var base = mapStyle === "satellite" ? (satNight ? 3 : 2) : (lightTheme ? 1 : 0)
        // The POIs are no longer switched on in the style (MapTiler's were almost only
        // parking lots): root.mapPois below draws them, with the app's icons.
        return base * 4 + (weatherEnabled ? 1 : 0)
    }

    // Every assignment of activeMapType reloads the WHOLE map, even if the style is
    // the same: at startup it happened twice in a row (onStyleIndexChanged and then
    // Component.onCompleted, both with style 8) and the map showed up late.
    property int _appliedStyle: -1
    function applyStyle(force) {
        if (map.supportedMapTypes.length <= styleIndex) return
        if (!force && root._appliedStyle === styleIndex) return
        root._appliedStyle = styleIndex
        if (debugMode) console.log("[mappa] stile", styleIndex, "dopo", Date.now() - root._t0, "ms")
        map.activeMapType = map.supportedMapTypes[styleIndex]
    }
    readonly property double _t0: Date.now()
    onStyleIndexChanged: applyStyle()

    Component.onCompleted: {
        map.center = coordinateForCenterBias(QtPositioning.coordinate(carLat, carLon))
        applyStyle()
    }

    property real carLat: 45.4642
    property real carLon: 9.1900

    property string currentStreet: ""
    property string currentCity: ""

    // ── Ricerche recenti / preferiti
    // dl74: copy saved in the "ui" category (like dock and drawer): recents and favorites are not lost on closing
    Core.Settings {   // dl75
        id: navPersist
        category: "ui"
        property string recentJson: ""
        property string favoriteJson: ""
    }

    // Old location of recents/favorites: now they are only saved in navPersist (above),
    // here they are read once as a fallback for those who had data saved before.
    Core.Settings {   // dl75
        id: navHistorySettings
        property string recentSearchesJson: "[]"
        property string favoritePlacesJson: "[]"
        property string fuelKind: "benzina"
    }

    // ── Casa / Lavoro
    Core.Settings {   // dl75
        id: homeWorkSettings
        property string homePlaceJson: ""
        property string workPlaceJson: ""
    }

    property var homePlace: {
        try {
            return homeWorkSettings.homePlaceJson !== "" ? JSON.parse(homeWorkSettings.homePlaceJson) : null
        } catch(e) {
            return null
        }
    }

    property var workPlace: {
        try {
            return homeWorkSettings.workPlaceJson !== "" ? JSON.parse(homeWorkSettings.workPlaceJson) : null
        } catch(e) {
            return null
        }
    }

    function setHomePlace(lat, lon, address) {
        var p = { lat: lat, lon: lon, address: address || "" }
        root.homePlace = p
        homeWorkSettings.homePlaceJson = JSON.stringify(p)
    }

    function setWorkPlace(lat, lon, address) {
        var p = { lat: lat, lon: lon, address: address || "" }
        root.workPlace = p
        homeWorkSettings.workPlaceJson = JSON.stringify(p)
    }

    function navigateHome() {
        if (!root.homePlace) return
        if (root.addingStop) { root.commitStopFromSearch({ lat: root.homePlace.lat, lon: root.homePlace.lon, name: qsTr("Home", "shortcut"), address: root.homePlace.address }); searchInput.text = ""; searchInput.focus = false; return }   // dl92
        root.navigateTo(root.homePlace.lat, root.homePlace.lon, qsTr("Home", "shortcut"), root.homePlace.address, {})
        searchInput.text = ""
        searchInput.focus = false
    }

    function navigateWork() {
        if (!root.workPlace) return
        if (root.addingStop) { root.commitStopFromSearch({ lat: root.workPlace.lat, lon: root.workPlace.lon, name: qsTr("Work"), address: root.workPlace.address }); searchInput.text = ""; searchInput.focus = false; return }   // dl92
        root.navigateTo(root.workPlace.lat, root.workPlace.lon, qsTr("Work"), root.workPlace.address, {})
        searchInput.text = ""
        searchInput.focus = false
    }

    property var recentSearches: {
        try {
            return JSON.parse(navPersist.recentJson !== "" ? navPersist.recentJson : navHistorySettings.recentSearchesJson)
        } catch(e) {
            return []
        }
    }

    property var favoritePlaces: {
        try {
            return JSON.parse(navPersist.favoriteJson !== "" ? navPersist.favoriteJson : navHistorySettings.favoritePlacesJson)
        } catch(e) {
            return []
        }
    }

    function addRecentSearch(name, address, lat, lon, meta) {
        meta = meta || {}
        var list = root.recentSearches.slice()
        list = list.filter(function(it) {
            return !(it.name === name && it.lat === lat && it.lon === lon)
        })
        list.unshift({
            name: name,
            address: address || "",
            lat: lat,
            lon: lon,
            ts: Date.now(),
            isBusiness: !!meta.isBusiness,
            category: meta.category || "",
            phone: meta.phone || "",
            website: meta.website || ""
        })
        if (list.length > 25) list = list.slice(0, 25)
        root.recentSearches = list
        navPersist.recentJson = JSON.stringify(list)   // dl74
    }

    function dateLabelFor(ts) {
        var now = new Date()
        var d = new Date(ts)
        var diffDays = Math.round((new Date(now.getFullYear(), now.getMonth(), now.getDate()) -
                                    new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000)
        if (diffDays <= 0) return qsTr("Today")
        if (diffDays === 1) return qsTr("Yesterday")
        return diffDays + qsTr(" days ago")
    }

    property var recentSearchGroups: {
        var groups = []
        var mapObj = {}
        for (var i = 0; i < root.recentSearches.length; i++) {
            var item = root.recentSearches[i]
            var label = root.dateLabelFor(item.ts)
            if (!mapObj[label]) {
                mapObj[label] = { label: label, items: [] }
                groups.push(mapObj[label])
            }
            mapObj[label].items.push(item)
        }
        return groups
    }

    property string searchTab: "recenti"
    // BUG fixed: before it was "searchInput.activeFocus && searchInput.text
    // === ''" — it closed at the INSTANT the search lost focus.
    // Tapping a "Recent"/"Favorite" entry (an element INSIDE this
    // same panel, not the search) makes the search lose focus
    // in the same tap that should open the place card: the
    // panel disappeared a moment before the tap really reached the
    // entry's MouseArea, so it seemed that nothing happened. Now
    // closing on focus loss has a short tolerance, just enough
    // time for the tap on an entry to complete its action.
    property bool searchDropdownOpen: false
    // dl91: true if there is a panel (search, results, nearby, place card) above the map
    readonly property bool _searchPanelOpen: root.searchDropdownOpen || searchResultsPanel.visible
                                            || nearbyPanel.visible || placeDetailsPanel.visible
                                        || editTripPanel.visible   // dl92
    Connections {
        target: searchInput
        function onActiveFocusChanged() {
            if (searchInput.activeFocus && searchInput.text === "") {
                _searchDropdownCloseGrace.stop()
                root.searchDropdownOpen = true
            }
            // No closing on focus loss: every tap with the keyboard open makes it
            // disappear (and removes focus from the field), but the list must stay to be able to scroll it.
            // It closes by tapping the map, choosing a place or with Esc.
        }
        function onTextChanged() {
            if (searchInput.text !== "") {
                _searchDropdownCloseGrace.stop()
                root.searchDropdownOpen = false
            } else if (searchInput.activeFocus) {
                _searchDropdownCloseGrace.stop()
                root.searchDropdownOpen = true
            }
        }
    }
    Timer {
        id: _searchDropdownCloseGrace
        interval: 250
        repeat: false
        onTriggered: root.searchDropdownOpen = false
    }

    // ── OWN POIs on the map (OpenStreetMap via map_proxy /map-pois) ──
    // Niente parcheggi; benzina, colonnine, ristoranti, farmacie, supermercati,
    // hotels, attractions... with the app's poi_*.svg icons. The more you zoom, the more
    // categories appear (and nearby icons are thinned out by the server).
    property var mapPois: []
    property bool selectedFromOwnPoi: false   // place chosen by tapping an own POI: no gray pin
    property Item mapItem: map                // for the drawer's blurred background (Main.qml)
    property var _poiReq: null
    // Stable model: at every response ONLY the changed POIs are added/removed
    // (before the whole array was replaced and all the icons were recreated = flicker)
    ListModel { id: poiModel }
    function _poiKey(p) { return p.lat.toFixed(5) + "," + p.lon.toFixed(5) + "," + p.icon }
    function _applyPois(list, merge) {
        list = list || []
        var want = {}
        for (var i = 0; i < list.length; i++) want[root._poiKey(list[i])] = list[i]
        var have = {}
        for (var j = poiModel.count - 1; j >= 0; j--) {
            var it = poiModel.get(j)
            var w = want[it.key]
            if (!w) { if (!merge) poiModel.remove(j); continue }
            have[it.key] = true
            if (it.tier !== w.tier) poiModel.setProperty(j, "tier", w.tier)
            if (w.minz !== undefined && it.minz !== w.minz) poiModel.setProperty(j, "minz", w.minz)
            if (it.poiName !== w.name) poiModel.setProperty(j, "poiName", w.name)
        }
        for (var k = 0; k < list.length; k++) {
            var p = list[k], key = root._poiKey(p)
            if (have[key]) continue
            have[key] = true
            poiModel.append({ key: key, lat: p.lat, lon: p.lon, icon: p.icon,
                              poiName: p.name || "", tier: p.tier === undefined ? 3 : p.tier,
                              minz: p.minz === undefined ? 14 : p.minz,
                              category: p.category || "" })
        }
    }
    property int _poiSeq: 0

    function _poiViewBox() {
        // With the map tilted (3D, navigation) the top corners fall above the horizon and
        // toCoordinate() gives nothing: before, in that case no POI was requested. Now the row
        // of points at the top goes down until the coordinates are valid.
        var W = map.width, H = map.height
        var s = 90, n = -90, w = 180, e = -180, got = 0
        function take(c) {
            if (!c || !c.isValid) return false
            s = Math.min(s, c.latitude);  n = Math.max(n, c.latitude)
            w = Math.min(w, c.longitude); e = Math.max(e, c.longitude)
            got++
            return true
        }
        var rows = [0, 0.12, 0.25, 0.4, 0.55]
        for (var r = 0; r < rows.length; r++) {
            var y = H * rows[r]
            if (take(map.toCoordinate(Qt.point(0, y), false)) & take(map.toCoordinate(Qt.point(W, y), false))) break
        }
        take(map.toCoordinate(Qt.point(0, H), false))
        take(map.toCoordinate(Qt.point(W, H), false))
        if (got < 3) return null
        return { s: s, w: w, n: n, e: e }
    }

    function refreshMapPois(force) {
        if (!root.poisEnabled || map.width < 10 || map.height < 10) return
        var b = root._poiViewBox()
        if (!b) return
        var z = map.zoomLevel
        // Below zoom 14 nothing is shown: the already loaded icons stay in memory
        if (z < 13.8) return
        var cur = root._poiReq
        // The area is requested ONCE (with each icon's minimum zoom): changing zoom does not reload
        // anything, it is only requested when moving outside the already loaded area.
        if (!force && cur && b.s >= cur.s && b.n <= cur.n && b.w >= cur.w && b.e <= cur.e) return
        var dLat = (b.n - b.s) * 0.5, dLon = (b.e - b.w) * 0.5
        var req = { s: b.s - dLat, w: b.w - dLon, n: b.n + dLat, e: b.e + dLon, z: z }
        root._poiReq = req
        var seq = ++root._poiSeq
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || seq !== root._poiSeq) return
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText)
                    root._applyPois(d.pois, d.pending > 0)   // tiles arriving: no icon is removed (before they disappeared and reappeared)
                    if (d.pending > 0) poiRetryTimer.restart()      // altre tessere in arrivo
                } catch (e) {}
            } else {
                root._poiReq = null
                poiRetryTimer.restart()
            }
        }
        xhr.open("GET", "http://127.0.0.1:9098/map-pois?full=1&s=" + req.s + "&w=" + req.w + "&n=" + req.n
                        + "&e=" + req.e)
        xhr.send()
    }


    // ── TRAFFIC LIGHTS and STOP SIGNS on the map (OpenStreetMap via map_proxy /map-signals) ──
    // They only appear at close zoom, so as not to crowd the map.
    property bool trafficControlsEnabled: true
    readonly property real trafficMinZoom: 16.3
    property var _sigReq: null
    property int _sigSeq: 0
    ListModel { id: sigModel }
    function _applySignals(list) {
        list = list || []
        var want = {}
        for (var i = 0; i < list.length; i++)
            want[list[i].kind + list[i].lat.toFixed(6) + "," + list[i].lon.toFixed(6)] = list[i]
        var have = {}
        for (var j = sigModel.count - 1; j >= 0; j--) {
            var k0 = sigModel.get(j).key
            if (!want[k0]) sigModel.remove(j); else have[k0] = true
        }
        for (var k in want) {
            if (have[k]) continue
            var it = want[k]
            sigModel.append({ key: k, lat: it.lat, lon: it.lon, kind: it.kind })
        }
    }
    function refreshSignals(force) {
        if (!root.trafficControlsEnabled || map.width < 10 || map.height < 10) return
        if (map.zoomLevel < root.trafficMinZoom) {
            if (sigModel.count > 0) root._applySignals([])
            root._sigReq = null
            return
        }
        var b = root._poiViewBox()
        if (!b) return
        var cur = root._sigReq
        if (!force && cur && b.s >= cur.s && b.n <= cur.n && b.w >= cur.w && b.e <= cur.e) return
        var dLat = (b.n - b.s) * 0.3, dLon = (b.e - b.w) * 0.3
        var req = { s: b.s - dLat, w: b.w - dLon, n: b.n + dLat, e: b.e + dLon }
        root._sigReq = req
        var seq = ++root._sigSeq
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || seq !== root._sigSeq) return
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText)
                    root._applySignals(d.items)
                    if (d.pending > 0) sigRetryTimer.restart()
                } catch (e) {}
            } else {
                root._sigReq = null
                sigRetryTimer.restart()
            }
        }
        xhr.open("GET", "http://127.0.0.1:9098/map-signals?s=" + req.s + "&w=" + req.w
                        + "&n=" + req.n + "&e=" + req.e)
        xhr.send()
    }
    Timer {
        interval: 1000; repeat: true
        running: root.trafficControlsEnabled && root.visible && !root.covered
        onTriggered: root.refreshSignals(false)
    }
    Timer { id: sigRetryTimer; interval: 3000; onTriggered: root.refreshSignals(true) }

    // ── SPEED CAMERAS: alert when there is one ahead (OpenStreetMap via map_proxy /map-speedcams) ──
    property bool speedCamsEnabled: true     // false = no alerts nor icons
    property bool speedCamVoice: true        // false = on-screen alert only, without voice
    property var _cams: []
    property bool _camHave: false
    property real _camLat: 0
    property real _camLon: 0
    property int _camSeq: 0
    property var camAlert: null              // {id, kind, dist, limit}
    property var _camSaid: ({})              // id -> istante dell'annuncio vocale
    ListModel { id: camModel }

    function _camDist(lat1, lon1, lat2, lon2) {
        var dLat = (lat2 - lat1) * 111320
        var dLon = (lon2 - lon1) * 111320 * Math.cos(lat1 * Math.PI / 180)
        return Math.sqrt(dLat * dLat + dLon * dLon)
    }
    function _camBearing(lat1, lon1, lat2, lon2) {
        var dLon = (lon2 - lon1) * Math.PI / 180
        var y = Math.sin(dLon) * Math.cos(lat2 * Math.PI / 180)
        var x = Math.cos(lat1 * Math.PI / 180) * Math.sin(lat2 * Math.PI / 180)
              - Math.sin(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.cos(dLon)
        return (Math.atan2(y, x) * 180 / Math.PI + 360) % 360
    }
    function _camAngDiff(a, b) {
        var d = Math.abs(((a - b) % 360 + 540) % 360 - 180)
        return d
    }
    function _applyCams(list) {
        root._cams = list || []
        var want = {}
        for (var i = 0; i < root._cams.length; i++) {
            var c = root._cams[i]
            want[c.kind + c.lat.toFixed(6) + "," + c.lon.toFixed(6)] = c
        }
        var have = {}
        for (var j = camModel.count - 1; j >= 0; j--) {
            var k0 = camModel.get(j).key
            if (!want[k0]) camModel.remove(j); else have[k0] = true
        }
        for (var k in want) {
            if (have[k]) continue
            camModel.append({ key: k, lat: want[k].lat, lon: want[k].lon, kind: want[k].kind })
        }
    }
    function refreshCams(force) {
        if (!root.speedCamsEnabled) return
        var moved = root._camHave ? root._camDist(root._camLat, root._camLon, root.carLat, root.carLon) : 1e9
        if (!force && root._camHave && moved < 1200) return
        // stopped and already loaded: nothing else needed
        if (!force && root._camHave && root.speedKmh < 5) return
        var seq = ++root._camSeq
        var lat = root.carLat, lon = root.carLon
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || seq !== root._camSeq) return
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText)
                    root._applyCams(d.items)
                    root._camLat = lat; root._camLon = lon
                    root._camHave = d.pending === 0 || (d.items && d.items.length > 0)
                    if (d.pending > 0) camRetryTimer.restart()
                } catch (e) {}
            } else {
                camRetryTimer.restart()
            }
        }
        xhr.open("GET", "http://127.0.0.1:9098/map-speedcams?lat=" + lat.toFixed(6) + "&lon=" + lon.toFixed(6) + "&r=3500")
        xhr.send()
    }
    function _camSpeak(a) {
        if (!root.speedCamVoice) return
        var m = Math.max(50, Math.round(a.dist / 50) * 50)
        var what = a.kind === "tutor" ? qsTr("Speed camera (Tutor)") : (a.kind === "redlight" ? qsTr("Red light camera") : qsTr("Speed camera"))
        var txt = what + " tra " + m + " metri" + (a.limit > 0 ? qsTr(", limit ") + a.limit : "")
        var xhr = new XMLHttpRequest()
        xhr.open("POST", "http://127.0.0.1:8097/speak")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify({ text: txt, rate: "+8%" }))
    }
    function evalCamAlert() {
        if (!root.speedCamsEnabled || root.speedKmh < 8 || root._cams.length === 0) {
            if (root.camAlert !== null) root.camAlert = null
            return
        }
        var warn = Math.max(350, Math.min(1000, root.speedKmh * 8))
        var hd = root.bearingRot
        var best = null
        for (var i = 0; i < root._cams.length; i++) {
            var c = root._cams[i]
            var d = root._camDist(root.carLat, root.carLon, c.lat, c.lon)
            if (d > warn || d < 25) continue
            if (root._camAngDiff(root._camBearing(root.carLat, root.carLon, c.lat, c.lon), hd) > 40) continue
            if (c.dir !== null && c.dir !== undefined && root._camAngDiff(c.dir, hd) > 75) continue
            if (best === null || d < best.dist)
                best = { id: c.kind + c.lat.toFixed(6) + "," + c.lon.toFixed(6), kind: c.kind, dist: d, limit: c.limit || 0 }
        }
        root.camAlert = best
        if (best !== null) {
            var now = Date.now()
            var said = root._camSaid[best.id]
            if (!said || now - said > 300000) {
                root._camSaid[best.id] = now
                root._camSpeak(best)
            }
        }
    }
    Timer {
        interval: 3000; repeat: true
        running: root.speedCamsEnabled && root.active
        onTriggered: root.refreshCams(false)
    }
    Timer { id: camRetryTimer; interval: 5000; onTriggered: root.refreshCams(true) }
    Timer {
        interval: 1000; repeat: true
        running: root.speedCamsEnabled && root.active
        onTriggered: root.evalCamAlert()
    }


    onPoisEnabledChanged: {
        if (poisEnabled) refreshMapPois(true)
        else { root._applyPois([]); root._poiReq = null; root._poiSeq++ }
    }
    Timer {          // checks whether the view has left the already loaded area
        interval: 900; repeat: true
        running: root.poisEnabled && root.visible && !root.covered
        onTriggered: root.refreshMapPois(false)
    }
    Timer {          // retry if the server still had tiles to download / error
        id: poiRetryTimer
        interval: 2500; repeat: false
        onTriggered: root.refreshMapPois(true)
    }

    property string nearbyPanelType: ""
    property var nearbyPlaces: []
    property bool nearbyLoading: false
    property bool _nearbyWasFollowing: false
    // list closed: if we were following the car before, we go back to following it
    onNearbyPanelTypeChanged: {
        if (nearbyPanelType === "" && _nearbyWasFollowing) {
            _nearbyWasFollowing = false
            followCar = true
        }
    }

    // price (e.g. "1.789") of the chosen fuel for a gas station in the list, "" if unknown
    function fuelPriceText(pl) {
        if (!pl || !pl.prices) return ""
        var v = pl.prices.benzina
        return v ? Number(v).toFixed(3).replace(".", ",") : ""
    }

    function openNearbyPanel(kind, lat, lon) {
        var aLat = (lat !== undefined && lat !== null) ? lat : root.carLat
        var aLon = (lon !== undefined && lon !== null) ? lon : root.carLon
        if (root.nearbyPanelType === "")
            root._nearbyWasFollowing = (lat === undefined || lat === null) && root.followCar
        root.nearbyPanelType = kind
        root.nearbyPlaces = []
        root.nearbyLoading = true

        if (lat !== undefined && lat !== null) {
            root.followCar = false
            root.flyTo(QtPositioning.coordinate(aLat, aLon), root.freeZoom, 800)
        }

        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                root.nearbyLoading = false
                if (xhr.status === 200) {
                    try {
                        var arr = JSON.parse(xhr.responseText)
                        // We add the letters directly here so QML never gets them wrong
                        for(var i=0; i<arr.length; i++) {
                            arr[i].markerLetter = String.fromCharCode(65 + i)
                        }
                        root.nearbyPlaces = arr
                        root.fitToNearby(aLat, aLon)
                    } catch(e) {}
                }
            }
        }
        xhr.open("GET", "http://127.0.0.1:9098/nearby-places?type=" + kind + "&lat=" + aLat + "&lon=" + aLon)
        xhr.send()
    }

    // ═══ dl82: smoothed map angle + camera shift for the arrival angle ═══
    property real _mapBearing: 0
    readonly property real _bearingTarget: !Nav.navigating ? root._freeBearing :   // dl86
        (root.followCar ? root.bearingRot : root._mapBearing)   // dl83: you move the map -> the orientation stays
    // it only runs until the angle has reached the target (before always, even
    // with the car stopped: it kept the UI redrawing 60 times per second for nothing)
    readonly property bool _bearingMoving: Math.abs(((root._bearingTarget - root._mapBearing) % 360 + 540) % 360 - 180) > 1e-6
    FrameAnimation {
        running: root.visible && root._bearingMoving
        onTriggered: {
            var tgt = root._bearingTarget
            var diff = ((tgt - root._mapBearing) % 360 + 540) % 360 - 180
            if (Math.abs(diff) < 0.02) {
                var fin = ((tgt % 360) + 360) % 360
                if (Math.abs(root._mapBearing - fin) > 1e-6) root._mapBearing = fin
                return
            }
            var tau = Math.abs(diff) < 8 ? 0.07 : 0.30
            var k = 1 - Math.exp(-Math.min(0.1, frameTime) / tau)
            root._mapBearing = ((root._mapBearing + diff * k) % 360 + 360) % 360
        }
    }
    // ═══ fine dl82 ═══

    // ═══ dl86: user map rotation + arrow always up outside navigation ═══
    property real _freeBearing: 0                                   // map angle chosen with fingers/mouse (outside navigation)
    // The arrow always points in the car's real direction (even outside navigation):
    // rotating the map with two fingers it turns together with the map. Before, outside navigation,
    // it always looked up (= it followed the map's angle) and seemed stuck.
    readonly property real _arrHdg: root.bearingRot
    function _rotateMap(b) {
        b = ((b % 360) + 360) % 360
        root.followCar = false
        root._mapBearing = b                                        // immediately, without smoothing: it follows the fingers
        if (!Nav.navigating) root._freeBearing = b
        root.pokeToolsVisibility()
    }
    // ═══ fine dl86 ═══


    // ═══ dl81: stretch already traveled drawn up to the arrow ═══
    property int   _trvCount: 0          // vertices already in the static polyline
    property var   _trvLive: []          // [ultimo vertice, freccia]
    property alias trvStaticPath: trvOutS.path   // read by the mini-map
    function _trvClear() {
        trvOutS.path = []; trvInS.path = []
        root._trvCount = 0
        root._trvLive = []
    }
    function _trvUpdate(q) {
        var la = root._rLat, lo = root._rLon
        var need = q.i + 1                                  // vertices 0..i are behind the arrow
        if (root._trvCount > need) root._trvClear()         // the arrow went back: I rebuild
        if (root._trvCount === 0) {
            var arr = []
            for (var k = 0; k < need; k++) arr.push(QtPositioning.coordinate(la[k], lo[k]))
            trvOutS.path = arr; trvInS.path = arr
            root._trvCount = need
        } else {
            for (var j = root._trvCount; j < need; j++) {
                var c = QtPositioning.coordinate(la[j], lo[j])
                trvOutS.addCoordinate(c); trvInS.addCoordinate(c)
            }
            root._trvCount = need
        }
        root._trvLive = [QtPositioning.coordinate(la[q.i], lo[q.i]), QtPositioning.coordinate(q.lat, q.lon)]
    }
    on_RidingChanged: if (!root._riding) root._trvClear()
    // ═══ fine dl81 ═══

    // ═══ dl78: freccia GL ═══
    readonly property real _arrZoomQ: Math.round(map.zoomLevel * 16) / 16   // dl83: the arrow follows the zoom in steps (less drawing work)
    // false: the arrow is A SINGLE element (image with shadow) that moves, rotates and zooms
    // all together. true: three separate geographic polygons (shadow, white, red), which during
    // animated zooms (navigation start, preview) get out of step with each other.
    property bool arrowGL: false
    property real arrowPxW: 26           // dl79
    property real arrowPxH: 30           // dl79
    // dl79: outer (white) and inner (red) outline of the map-arrow.svg icon, as fractions of width and height, center = (0, 0)
    readonly property var _arrOuter: [[-0.0055,-0.3486],[-0.1018,-0.3887],[-0.1791,-0.421],[-0.2374,-0.4456],[-0.2765,-0.4625],[-0.3091,-0.476],[-0.3367,-0.4857],[-0.3593,-0.4916],[-0.3768,-0.4937],[-0.4247,-0.4863],[-0.4642,-0.4644],[-0.4908,-0.4308],[-0.5,-0.3886],[-0.4986,-0.3759],[-0.4949,-0.3619],[-0.4889,-0.3468],[-0.4806,-0.3305],[-0.4567,-0.2816],[-0.3861,-0.137],[-0.2688,0.1034],[-0.1049,0.4396],[-0.0878,0.463],[-0.0628,0.4818],[-0.0326,0.4946],[0.0001,0.4999],[0.0251,0.4988],[0.0485,0.4936],[0.0703,0.4844],[0.0903,0.4712],[0.1012,0.4603],[0.1125,0.4443],[0.1242,0.4233],[0.1363,0.3974],[0.1577,0.352],[0.22,0.2211],[0.3229,0.0047],[0.4666,-0.2972],[0.4823,-0.3292],[0.4939,-0.3557],[0.4995,-0.3803],[0.4974,-0.4066],[0.4809,-0.4419],[0.452,-0.4685],[0.4142,-0.4849],[0.3708,-0.4898],[0.357,-0.4883],[0.3409,-0.4846],[0.3227,-0.4786],[0.3023,-0.4704],[0.2767,-0.4597],[0.219,-0.4358],[0.1292,-0.3988],[0.0072,-0.3486],[0.0057,-0.348],[0.0041,-0.3477],[0.0025,-0.3474],[0.0008,-0.3474],[-0.0008,-0.3474],[-0.0024,-0.3477],[-0.004,-0.3481],[-0.0055,-0.3486]]
    readonly property var _arrRed: [[0.0012,-0.2893],[-0.0825,-0.3242],[-0.1662,-0.3592],[-0.2502,-0.3943],[-0.3342,-0.4296],[-0.3486,-0.4353],[-0.3608,-0.4393],[-0.3709,-0.4418],[-0.379,-0.4426],[-0.4017,-0.4392],[-0.4213,-0.429],[-0.4354,-0.4136],[-0.4415,-0.3941],[-0.441,-0.3875],[-0.4389,-0.3792],[-0.4352,-0.3691],[-0.4298,-0.3573],[-0.2707,-0.0314],[-0.1562,0.2035],[-0.0861,0.3473],[-0.0606,0.4001],[-0.0544,0.4125],[-0.0486,0.4224],[-0.043,0.4299],[-0.0378,0.4349],[-0.0176,0.4453],[0.005,0.4491],[0.0278,0.446],[0.0483,0.4359],[0.0531,0.4312],[0.0584,0.4238],[0.0642,0.414],[0.0706,0.4015],[0.0761,0.39],[0.0816,0.3785],[0.0869,0.367],[0.0922,0.3556],[0.2357,0.0544],[0.2838,-0.0467],[0.332,-0.1479],[0.3801,-0.2492],[0.4283,-0.3506],[0.4342,-0.364],[0.4383,-0.3753],[0.4405,-0.3845],[0.4408,-0.3915],[0.4304,-0.4164],[0.4082,-0.4325],[0.3793,-0.4384],[0.3491,-0.4328],[0.2987,-0.4122],[0.2486,-0.3917],[0.199,-0.3712],[0.1497,-0.3506],[0.0012,-0.2893]]
    function _arrowPoly(pts, k, bx, by) {
        if (!root.arrowGL) return []
        var lat = root.carLat, lon = root.carLon
        var mpp = 156543.03392 * Math.cos(lat * Math.PI / 180) / Math.pow(2, root._arrZoomQ)   // meters per pixel
        var W = root.arrowPxW * mpp * k, H = root.arrowPxH * mpp * k
        var th = root._arrHdg * Math.PI / 180   // dl86
        var st = Math.sin(th), ct = Math.cos(th)
        var kLon = 111320 * Math.cos(lat * Math.PI / 180)
        var out = []
        for (var i = 0; i < pts.length; i++) {
            var x = (pts[i][0] + bx) * W
            var y = (pts[i][1] + by) * H
            out.push(QtPositioning.coordinate(lat + (-x * st + y * ct) / 111320, lon + (x * ct + y * st) / kLon))
        }
        return out
    }
    // ═══ fine dl78 ═══

    // ═══ dl76/dl77: the arrow slides along the route polyline (no shortcuts in curves, no jumps) ═══
    property var    _rLat: []
    property var    _rLon: []
    property var    _rCum: []
    property string _rSig: ""
    property int    _rSeg: 0
    property bool   _rFresh: true
    property real   carS: 0              // distance (m) traveled along the route
    property string _rMidSig: ""
    property bool   _rDirty: true       // dl82: the navigator's route has changed: to be re-read
    Timer { id: rBuildTimer; interval: 1600; repeat: false; onTriggered: if (Nav.hasRoute) root._rBuild() }   // dl83
    property bool   _riding: false
    property double _rLastFixMs: 0
    property real   _sFix: 0             // dl77: distanza dell'ultimo fix agganciato
    property double _sFixMs: 0

    function _rBuild() {
        if (!root._rDirty && root._rLat.length >= 2) return true   // dl82: no re-reading if the route has not changed
        var pts = Nav.routeCoordinates
        if (!pts || pts.length < 2) { root._rSig = ""; root._rLat = []; return false }
        var n = pts.length
        var sig = n + "|" + pts[0].latitude + "|" + pts[n - 1].latitude + "|" + pts[n >> 1].longitude
        if (sig === root._rSig) { root._rDirty = false; return root._rLat.length >= 2 }
        var la = new Array(n), lo = new Array(n), cu = new Array(n)
        cu[0] = 0
        for (var i = 0; i < n; i++) {
            la[i] = pts[i].latitude; lo[i] = pts[i].longitude
            if (i > 0) {
                var dy = (la[i] - la[i - 1]) * 111320
                var dx = (lo[i] - lo[i - 1]) * 111320 * Math.cos(la[i] * Math.PI / 180)
                cu[i] = cu[i - 1] + Math.sqrt(dx * dx + dy * dy)
            }
        }
        root._rLat = la; root._rLon = lo; root._rCum = cu
        root._rSig = sig; root._rSeg = 0; root._rFresh = true; root._trvClear(); root._rDirty = false
        if (root._riding) {   // dl82: route changed (recalculation): I bring the arrow back into the new reference
            var cs = root._rLocate(root.carLat, root.carLon, root.bearingRot)
            if (cs >= 0) root.carS = cs; else root._riding = false
        }
        return true
    }

    // dl80: distance along the route of the point (lat, lon). Sequential (window -20 m / +200 m around carS) when the arrow
    // is already following the route; otherwise full search. It prefers the segments with the same direction as the car (hdg). -1 if > 40 m.
    function _rLocate(lat, lon, hdg) {
        var la = root._rLat, lo = root._rLon, cu = root._rCum
        var n = la.length
        var kx = 111320 * Math.cos(lat * Math.PI / 180), ky = 111320
        var s0 = root.carS
        var hasHdg = (hdg !== undefined && hdg !== null && !isNaN(hdg))
        for (var pass = 0; pass < 2; pass++) {
            var full = !root._riding || root._rFresh || pass === 1
            var a = 0, b = n - 2
            if (!full) {
                a = Math.max(0, Math.min(n - 2, root._rSeg))
                while (a > 0 && cu[a] > s0 - 20) a--
                b = a
                while (b < n - 2 && cu[b + 1] <= s0 + 200) b++
            }
            var bestC = 1e18, bestD = 1e18, bs = 0, bi = 0
            for (var i = a; i <= b; i++) {
                var bx = (lo[i + 1] - lo[i]) * kx, by = (la[i + 1] - la[i]) * ky
                var ax = (lon - lo[i]) * kx, ay = (lat - la[i]) * ky
                var L2 = bx * bx + by * by
                var t = L2 > 0 ? Math.max(0, Math.min(1, (ax * bx + ay * by) / L2)) : 0
                var ex = ax - t * bx, ey = ay - t * by
                var dist = Math.sqrt(ex * ex + ey * ey)
                var sv = cu[i] + t * Math.sqrt(L2)
                var cost = dist
                if (hasHdg && L2 > 1) {
                    var sb = Math.atan2(bx, by) * 180 / Math.PI
                    var dh = Math.abs(((sb - hdg) % 360 + 540) % 360 - 180)
                    if (dh > 100) cost += 25
                }
                if (!full) cost += (sv >= s0 ? 0.03 * (sv - s0) : 0.5 * (s0 - sv))
                if (cost < bestC) { bestC = cost; bestD = dist; bi = i; bs = sv }
            }
            if (bestD <= 40) { root._rSeg = bi; root._rFresh = false; return bs }
            if (full) break
        }
        return -1
    }


    // point of the polyline at distance s
    function _rPos(s) {
        var cu = root._rCum, la = root._rLat, lo = root._rLon
        var n = cu.length
        if (s <= 0) return { lat: la[0], lon: lo[0], i: 0 }
        if (s >= cu[n - 1]) return { lat: la[n - 1], lon: lo[n - 1], i: n - 2 }
        var a = 0, b = n - 1
        while (b - a > 1) { var m = (a + b) >> 1; if (cu[m] <= s) a = m; else b = m }
        var seg = cu[b] - cu[a]
        var t = seg > 0 ? (s - cu[a]) / seg : 0
        return { lat: la[a] + (la[b] - la[a]) * t, lon: lo[a] + (lo[b] - lo[a]) * t, i: a }
    }

    function _rBearing(s) {
        var p1 = root._rPos(s - 4), p2 = root._rPos(s + 10)
        var dy = p2.lat - p1.lat
        var dx = (p2.lon - p1.lon) * Math.cos(p1.lat * Math.PI / 180)
        if (Math.abs(dx) + Math.abs(dy) < 1e-9) return root.bearingRot
        var b = Math.atan2(dx, dy) * 180 / Math.PI
        return b < 0 ? b + 360 : b
    }

    // called at every snapped GPS fix: true if the arrow is now driven by the route
    function _rideFix(lat, lon, hdg) {
        var mid = Nav.routeMidpoint   // dl82
        var midSig = mid ? (mid.latitude + "," + mid.longitude) : ""
        if (midSig !== root._rMidSig) { root._rMidSig = midSig; root._rDirty = true }
        var before = root._rSig
        if (!root._rBuild()) return false
        if (root._riding && root._rSig !== before) {
            // route recalculated: I bring the arrow's current distance into the new reference
            var cs = root._rLocate(root.carLat, root.carLon, root.bearingRot)
            if (cs < 0) root._riding = false
            else root.carS = cs
        }
        var sNew = root._rLocate(lat, lon, hdg)
        if (sNew < 0) return false
        var now = Date.now()
        if (!root._riding) {
            root._riding = true
            root.carS = sNew
            root._rPlace(0)
        } else if (Math.abs(sNew - root.carS) > 120) {
            root.carS = sNew                       // salto grande (nuovo percorso/ripartenza)
        }
        // the jittery GPS does not make the target go back (if it backs up slightly, it stays where it is)
        if (sNew < root._sFix && root._sFix - sNew < 25 && now - root._sFixMs < 4000) sNew = root._sFix
        root._sFix = sNew
        root._sFixMs = now
        return true
    }

    // positions arrow and orientation on the point carS of the polyline
    function _rPlace(dt) {
        var q = root._rPos(root.carS)
        root.carLat = q.lat
        root.carLon = q.lon
        root._trvUpdate(q)   // dl81
        var tb = root._rBearing(root.carS)
        var cur = root.bearingRot
        var diff = ((tb - cur) % 360 + 540) % 360 - 180
        var k = dt > 0 ? 1 - Math.exp(-dt / 0.12) : 1
        root.bearingRot = ((cur + diff * k) % 360 + 360) % 360   // dl78: sempre 0-360
    }

    // A single "beat" per frame, in fixed order: 1) the arrow advances along the
    // route, 2) the map follows it (only once, before it was moved twice:
    // at the carLat change and then carLon), 3) the arrow is redrawn.
    // It only runs when there is something to do (arrow moving, map to
    // move, arrow to redraw): with the car stopped the UI can stop redrawing.
    property bool _followDirty: false
    FrameAnimation {
        id: frameTick
        running: root.visible && (root._riding || root._followDirty)
        onTriggered: {
            if (root._riding) root._rideStep(Math.min(0.1, frameTime))
            if (root._followDirty) { root._followDirty = false; root.followPosition() }
        }
    }
    // the arrow advances at the real speed and lets itself be gently corrected toward the GPS fix
    function _rideStep(dt) {
            if (root._rLat.length < 2) return
            var v = root.speedKmh / 3.6
            var age = Date.now() - root._sFixMs
            var vEff = age > 3000 ? 0 : v                       // without recent fixes I do not extrapolate
            var tgt = root._sFix + vEff * age / 1000
            var s = root.carS + vEff * dt
            s += (tgt - s) * (1 - Math.exp(-dt / 1.5))
            root.carS = Math.max(0, s)
            root._rPlace(dt)
    }
    // ═══ fine dl76 ═══

    Behavior on carLat { enabled: !root._riding; NumberAnimation { duration: 450; easing.type: Easing.Linear } }
    Behavior on carLon { enabled: !root._riding; NumberAnimation { duration: 450; easing.type: Easing.Linear } }

    property real bearingRot: 0
    property real speedKmh: 0
    property bool gpsReceived: false
    property bool followCar: true


    property real _lastFixLat: 0
    property real _lastFixLon: 0
    readonly property real bearingMinSpeed: 4.0

    readonly property real navZoomDef:   17
    readonly property real freeZoom:     16.5
    readonly property real maneuverZoom: 18

    // ── Navigation Auto-Start Timer (Silent) ──
    property int autoStartCount: 5
    Timer {
        id: autoNavTimer
        interval: 1000
        repeat: true
        // Not during the preview from a place's card: there it starts only with the button
        running: root.inPreview && !root.placePreview
        onTriggered: {
            root.autoStartCount -= 1
            if (root.autoStartCount <= 0) {
                stop()
                if (root.inPreview) {
                    root.followCar = true
                    Nav.startNavigation()
                }
            }
        }
    }

    signal searchRequested()
    signal homeRequested()
    signal workRequested()

    function distanceKmTo(lat, lon) {
        var R = 6371.0
        var dLat = (lat - root.carLat) * Math.PI / 180
        var dLon = (lon - root.carLon) * Math.PI / 180
        var a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                Math.cos(root.carLat * Math.PI / 180) * Math.cos(lat * Math.PI / 180) *
                Math.sin(dLon/2) * Math.sin(dLon/2)
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return R * c
    }

    function distanceKmToPoint(lat1, lon1, lat2, lon2) {
        var R = 6371.0;
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLon = (lon2 - lon1) * Math.PI / 180;
        var a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                Math.sin(dLon/2) * Math.sin(dLon/2);
        return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    function isPointNearRoute(coord, path) {
        if (!path || path.length === 0) return false;
        for (var i=0; i<path.length; i+=3) {
            if (root.distanceKmToPoint(coord.latitude, coord.longitude, path[i].latitude, path[i].longitude) < 0.6) {
                return true;
            }
        }
        return false;
    }

    function formatCategory(cat) {
        if (!cat || cat.length === 0) return ""
        var first = cat.split(",")[0].trim()
        if (first.length === 0) return ""
        return first.charAt(0).toUpperCase() + first.slice(1)
    }

    readonly property var _poiIconRules: [
        [/\bpizz(a|eria)\b/, "poi_pizza.svg"],
        [/\bbaker(y|ies)\b|\bpanetter|\bpanifi/, "poi_bakery.svg"],
        [/\bfast[ ]?food\b|\bkebab\b|\bburger\b|\btakeaway\b/, "poi_fastfood.svg"],
        [/\bcaf(e|é)\b|\bcoffee\b|\bcaffetteria\b/, "poi_cafe.svg"],
        [/\bbar\b|\bpub\b|\bwine bar\b|\bcocktail\b|\benoteca\b/, "poi_bar.svg"],
        [/\brestaurant\b|\bristorant|\btrattoria\b|\bosteria\b|\bsteak\b|\bseafood\b|\bfood\b|\bdining\b/, "poi_restaurant.svg"],
        [/\bpharmac|\bfarmaci/, "poi_pharmacy.svg"],
        [/\bdentist/, "poi_dentist.svg"],
        [/\bemergency\b|\burgent care\b|\bpronto soccorso\b/, "poi_emergency.svg"],
        [/\bhospital\b|\bospedale\b|\bclinic|\bhealth care\b/, "poi_hospital.svg"],
        [/\bcar wash\b|\bautolavaggio\b/, "poi_car_wash.svg"],
        [/\bbus\b|\btransit\b/, "poi_bus.svg"],
        [/\bairport\b|\baeroporto\b|\bflight\b/, "poi_airport.svg"],
        [/\bev station\b|\belectric vehicle\b|\bcharging\b|\bcolonnina\b/, "poi_ev_station.svg"],
        [/\btrain\b|\brailway\b|\bstazione ferroviaria\b/, "poi_train.svg"],
        [/\bparking\b|\bparcheggio\b/, "poi_parking.svg"],
        [/\bfuel\b|\bgas station\b|\bpetrol\b|\bbenzinaio\b|\bdistributore\b/, "poi_gas_station.svg"],
        [/\bcar repair\b|\bmeccanico\b|\bofficina\b|\bgarage\b|\btire\b|\bautomotive\b/, "poi_car_repair.svg"],
        [/\bmall\b|\bcentro commerciale\b|\bshopping cent(re|er)\b/, "poi_mall.svg"],
        [/\bconvenience\b|\bkiosk\b|\bminimarket\b/, "poi_convenience_store.svg"],
        [/\bsupermarket\b|\bhypermarket\b|\bgrocery\b|\balimentari\b/, "poi_grocery.svg"],
        [/\bcloth(es|ing)\b|\babbigliamento\b|\bboutique\b|\bfashion\b/, "poi_clothing.svg"],
        [/\bshopping\b/, "poi_shopping_cart.svg"],
        [/\bshop\b|\bstore\b|\bnegozio\b|\bretail\b/, "poi_storefront.svg"],
        [/\bstadium\b|\bstadio\b|\barena\b|\bsports? complex\b/, "poi_stadium.svg"],
        [/\bgym\b|\bfitness\b|\bpalestra\b/, "poi_gym.svg"],
        [/\bcomedy\b|\bcabaret\b/, "poi_comedy_club.svg"],
        [/\btheat(er|re)\b|\bcinema\b|\bmovie\b/, "poi_theater.svg"],
        [/\battraction\b|\btourist\b|\blandmark\b|\bmonument\b|\bmuseo\b|\bmuseum\b/, "poi_attractions.svg"],
        [/\bhotel\b|\bmotel\b|\balbergo\b|\bresort\b/, "poi_hotel.svg"],
        [/\bb&b\b|\bbed and breakfast\b|\bguest ?house\b|\bhostel\b|\baffittacamere\b/, "poi_guesthouse.svg"],
        [/\bforest\b|\bforesta\b|\bbosco\b|\bnature reserve\b/, "poi_forest.svg"],
        [/\bpark\b|\bparco\b|\bgarden\b|\bgiardino\b/, "poi_park.svg"],
        [/\bbeach\b|\bspiaggia\b|\blido\b/, "poi_beach.svg"],
        [/\bmosque\b|\bmoschea\b/, "poi_mosque.svg"],
        [/\bchurch\b|\bchiesa\b|\bworship\b|\bcattedral|\bbasilica\b/, "poi_church.svg"],
        [/\bschool\b|\bscuola\b|\buniversity\b|\bcollege\b|\buniversità\b/, "poi_school.svg"]
    ]

    function poiIconSource(isBusiness, category) {
        if (!isBusiness) return "qrc:/VoltaApp/icons/poi_generic.svg"
        var c = " " + (category || "").toLowerCase().replace(/[_\-\/]/g, " ") + " "
        for (var i = 0; i < root._poiIconRules.length; i++) {
            if (root._poiIconRules[i][0].test(c)) return "qrc:/VoltaApp/icons/" + root._poiIconRules[i][1]
        }
        return "qrc:/VoltaApp/icons/poi_storefront.svg"
    }

    function navigateTo(lat, lon, name, address, meta) {
        root._rememberAddr(lat, lon, address)   // dl92
        Nav.requestRoute(lon, lat, name || qsTr("Destination"))
        root.addRecentSearch(name || qsTr("Destination"), address || "", lat, lon, meta)
    }

    // Navigation that starts RIGHT AWAY (without preview + wait)
    function navigateNow(lat, lon, name, address, meta) {
        root.addRecentSearch(name || qsTr("Destination"), address || "", lat, lon, meta)
        if (Nav.navigating) Nav.stopNavigation()
        root._startWhenReady = true
        Nav.requestRoute(lon, lat, name || qsTr("Destination"))
    }

    property var selectedPlace: null
    property bool placeDetailsOpen: false
    // Route preview shown while the place card is open
    // (Start route / Home / Work): the route is calculated right on opening,
    // so "Start route" starts instantly instead of waiting for preview + 5 s.
    property bool placePreview: false
    property bool _startWhenReady: false

    function _routeMatchesSelected() {
        var p = root.selectedPlace, d = Nav.destination
        if (!p || !Nav.hasRoute || !d || !d.isValid) return false
        return Math.abs(d.latitude - p.lat) < 0.0005 && Math.abs(d.longitude - p.lon) < 0.0005
    }
    function _previewPlaceRoute(lat, lon, name) {
        if (Nav.navigating) return            // during a navigation we do not touch the active route
        root.placePreview = true
        root._startWhenReady = false
        Nav.requestRoute(lon, lat, name || qsTr("Destination"))
    }

    // ── Logic to avoid duplicating the pin above an existing one ──
    readonly property bool selectedPlaceIsNearby: {
        if (!root.selectedPlace || root.nearbyPanelType === "") return false
        for (var i = 0; i < root.nearbyPlaces.length; i++) {
            if (Math.abs(root.nearbyPlaces[i].lat - root.selectedPlace.lat) < 0.00001 &&
                Math.abs(root.nearbyPlaces[i].lon - root.selectedPlace.lon) < 0.00001) {
                return true
            }
        }
        return false
    }

    function openPlaceDetails(lat, lon, name, address, meta) {
        meta = meta || {}
        root.selectedFromOwnPoi = !!meta.own
        var isBiz = !!meta.isBusiness
        var hasName = !!name && name.length > 0
        var hasPhone = !!meta.phone && meta.phone.length > 0
        var hasWebsite = !!meta.website && meta.website.length > 0

        root.selectedPlace = {
            name: hasName ? name : qsTr("Selected location"),
            address: address || "",
            lat: lat, lon: lon,
            isBusiness: isBiz,
            category: meta.category || "",
            phone: hasPhone ? meta.phone : "",
            website: hasWebsite ? meta.website : "",
            loading: false
        }
        root.placeDetailsOpen = true
        searchInput.focus = false
        root.searchDropdownOpen = false
        root._previewPlaceRoute(lat, lon, hasName ? name : qsTr("Destination"))

    }

    function reverseGeocodeAndOpenPin(lat, lon) {
        root.openPlaceDetails(lat, lon, lat.toFixed(5) + ", " + lon.toFixed(5), "", {isBusiness: false})

        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText)
                    var title = d.street ? d.street : (d.city ? d.city : qsTr("Selected location"))
                    var addr = []
                    if (d.street) addr.push(d.street)
                    if (d.city) addr.push(d.city)

                    var p = root.selectedPlace
                    if (p && p.lat === lat && p.lon === lon) {
                        // the preview route had started with the provisional name
                        // (the coordinates): now that the street is there, update that too
                        if (root._routeMatchesSelectedCoords(lat, lon)) Nav.setDestinationName(title)
                        root.selectedPlace = {
                            name: title,
                            address: addr.join("\n"),
                            lat: lat, lon: lon,
                            isBusiness: false,
                            category: "",
                            phone: "",
                            website: "",
                            loading: false
                        }
                    }
                } catch(e){}
            }
        }
        xhr.open("GET", "http://127.0.0.1:9098/reverse-geocode?lat=" + lat + "&lon=" + lon)
        xhr.send()
    }

    function closePlaceDetails() {
        // Card closed without starting: remove the route preview
        if (root.placePreview && !Nav.navigating && !root._startWhenReady) Nav.clearRoute()
        root.placePreview = false
        root.placeDetailsOpen = false
        root.selectedPlace = null
    }

    function confirmPlaceDirections() {
        if (!root.selectedPlace) return
        var p = root.selectedPlace
        var meta = { isBusiness: p.isBusiness, category: p.category, phone: p.phone, website: p.website }
        var ready = root.placePreview && root._routeMatchesSelected()
        root.placePreview = false               // the route now stays: do not delete it on closing
        root.closePlaceDetails()
        root.nearbyPanelType = ""
        root.addRecentSearch(p.name || qsTr("Destination"), p.address || "", p.lat, p.lon, meta)
        if (ready) {
            // Preview already ready: we start right away (with the place's current name, not the one
            // the route was calculated with, e.g. the coordinates of the tapped point)
            Nav.setDestinationName(p.name || qsTr("Destination"))
            root.followCar = true
            Nav.startNavigation()
        } else {
            // Route still being calculated (or navigating to something else): it starts as soon as it arrives
            root._startWhenReady = true
            if (!(Nav.hasRoute && root._routeMatchesSelectedCoords(p.lat, p.lon)))
                Nav.requestRoute(p.lon, p.lat, p.name || qsTr("Destination"))
        }
    }
    function _routeMatchesSelectedCoords(lat, lon) {
        var d = Nav.destination
        return d && d.isValid && Math.abs(d.latitude - lat) < 0.0005 && Math.abs(d.longitude - lon) < 0.0005
    }

    readonly property bool selectedPlaceIsFavorite: {
        if (!root.selectedPlace) return false
        for (var fi = 0; fi < root.favoritePlaces.length; fi++) {
            var f = root.favoritePlaces[fi]
            if (f.lat === root.selectedPlace.lat && f.lon === root.selectedPlace.lon) return true
        }
        return false
    }

    function togglePlaceFavorite() {
        if (!root.selectedPlace) return
        var p = root.selectedPlace
        var list = root.favoritePlaces.slice()
        var idx = -1
        for (var i = 0; i < list.length; i++) {
            if (list[i].lat === p.lat && list[i].lon === p.lon) {
                idx = i; break
            }
        }
        if (idx >= 0) {
            list.splice(idx, 1)
        } else {
            list.unshift({
                name: p.name,
                address: p.address,
                lat: p.lat,
                lon: p.lon,
                isBusiness: p.isBusiness,
                category: p.category,
                phone: p.phone,
                website: p.website
            })
        }
        root.favoritePlaces = list
        navPersist.favoriteJson = JSON.stringify(list)   // dl74
    }

    // ── Maneuver list: open (preview / dragged down) or collapsed to 1 row ──
    property bool navExpanded: false
    // scale factor of the navigation panels (reference graphic ~300 wide)
    readonly property real navK: root.panelW / 300
    readonly property bool navListOpen: inPreview || navExpanded
    property var frozenMans: []          // copy of the list while it is open: it does not change under the fingers
    function setNavExpanded(on) {
        if (!Nav.navigating) return
        if (on) frozenMans = Nav.upcomingManeuvers
        navExpanded = on
        if (on) { followCar = false; fitToRoute() }     // top-down view of the route
        else    { recenter() }                          // torna a seguire l'auto
    }

    function recenter() {
        if (!Nav.navigating) root._freeBearing = 0   // dl86: outside navigation the compass brings north to the top
        navExpanded = false
        followCar = true
        var here = coordinateForCenterBias(QtPositioning.coordinate(carLat, carLon), Nav.navigating ? bearingRot : 0)   // dl82
        flyTo(here, Nav.navigating ? navZoomDef : freeZoom, 800)
    }

    function stopNav() {
        Nav.stopNavigation()
        Nav.clearRoute()
    }

    function getCardinal(deg) {
        var directions = ["N", "NE", "E", "SE", "S", "SW", "O", "NO"]
        var index = Math.round(((deg % 360) + 360) % 360 / 45) % 8
        return directions[index]
    }

    Plugin {
        id: mapPlugin
        name: "maplibre"
        PluginParameter {
            name: "maplibre.map.styles"
            value: "http://127.0.0.1:9098/style.json?s=dark&v=3"
                 + ",http://127.0.0.1:9098/style.json?s=dark&w=1&v=3"
                 + ",http://127.0.0.1:9098/style.json?s=dark&poi=1&v=3"
                 + ",http://127.0.0.1:9098/style.json?s=dark&poi=1&w=1&v=3"
                 + ",http://127.0.0.1:9098/style.json?s=light&v=3"
                 + ",http://127.0.0.1:9098/style.json?s=light&w=1&v=3"
                 + ",http://127.0.0.1:9098/style.json?s=light&poi=1&v=3"
                 + ",http://127.0.0.1:9098/style.json?s=light&poi=1&w=1&v=3"
                 + ",http://127.0.0.1:9098/style.json?s=sat&v=5"
                 + ",http://127.0.0.1:9098/style.json?s=sat&w=1&v=5"
                 + ",http://127.0.0.1:9098/style.json?s=sat&poi=1&v=5"
                 + ",http://127.0.0.1:9098/style.json?s=sat&poi=1&w=1&v=5"
                 + ",http://127.0.0.1:9098/style.json?s=sat&n=1&v=6"
                 + ",http://127.0.0.1:9098/style.json?s=sat&n=1&w=1&v=6"
                 + ",http://127.0.0.1:9098/style.json?s=sat&n=1&poi=1&v=6"
                 + ",http://127.0.0.1:9098/style.json?s=sat&n=1&poi=1&w=1&v=6"
        }
    }

    Map {
        id: map
        anchors.fill: parent
        plugin: mapPlugin
        // if the styles arrive after creation, apply the right one as soon as they are ready
        onSupportedMapTypesChanged: root.applyStyle()
        zoomLevel: root.freeZoom

        tilt: 0
        maximumTilt: 65
        Behavior on tilt { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

        copyrightsVisible: false
        bearing: root._mapBearing   // dl82: smoothed in _mapBearing (see FrameAnimation)

        MapPolyline {
            visible: root.inPreview && Nav.hasAltRoute
            line.width: 6
            line.color: "#8A8F98"
            path: Nav.altRouteDisplayCoordinates
        }

        MapPolyline {
            visible: Nav.hasRoute && !root._legMode   // dl94
            line.width: 9
            line.color: "#1B3A6B"
            path: Nav.routeDisplayCoordinates
        }

        MapPolyline {
            visible: Nav.hasRoute && !root._legMode   // dl94
            line.width: 6
            line.color: "#0A84FF"
            path: Nav.routeDisplayCoordinates
        }

        // ═══ dl92: preview with stops: first leg blue, following legs gray ═══
        MapItemView {
            model: root._legMode ? Nav.legPaths : []
            delegate: MapPolyline {
                visible: index >= root._legDone   // dl94
                line.width: 9
                line.color: index === root._legDone ? "#1B3A6B" : "#45484E"
                path: modelData
            }
        }
        MapItemView {
            model: root._legMode ? Nav.legPaths : []
            delegate: MapPolyline {
                visible: index >= root._legDone   // dl94
                line.width: 6
                line.color: index === root._legDone ? "#0A84FF" : "#8A8F98"
                path: modelData
            }
        }

        MapItemView {     // not Repeater: inside Map the lines of a Repeater are not drawn
            model: Nav.trafficSegments
            delegate: MapPolyline {
                visible: modelData.color !== "#0A84FF" && !root._legPreview   // dl92
                line.width: 6
                line.color: modelData.color
                // NavigationManager puts the points in "coordinates" (before "path" was read here,
                // which does not exist: the traffic colors never appeared)
                path: (modelData && modelData.coordinates) ? modelData.coordinates : []
            }
        }

        // ═══ dl81: route traveled up to the arrow (static + "live" piece updated at every frame) ═══
        MapPolyline { id: trvOutS; visible: root._riding && Nav.navigating; line.width: 9; line.color: "#3A4A62" }
        MapPolyline { id: trvInS;  visible: root._riding && Nav.navigating; line.width: 6; line.color: "#5F7290" }
        MapPolyline { visible: root._riding && Nav.navigating && root._trvLive.length > 1; line.width: 9; line.color: "#3A4A62"; path: root._trvLive }
        MapPolyline { visible: root._riding && Nav.navigating && root._trvLive.length > 1; line.width: 6; line.color: "#5F7290"; path: root._trvLive }

        // ── Vignetta Rotta Principale (Stile Fumetto) ──
        MapQuickItem {
            visible: root.inPreview
            coordinate: Nav.routeMidpoint
            anchorPoint.x: 0
            anchorPoint.y: 38
            sourceItem: Item {
                width: routeTimeText.implicitWidth + 24
                height: 38
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.fillStyle = "#2072EF"
                        ctx.beginPath()
                        var r = 8
                        var t = 8
                        ctx.moveTo(r, 0)
                        ctx.lineTo(width - r, 0)
                        ctx.arcTo(width, 0, width, r, r)
                        ctx.lineTo(width, height - t - r)
                        ctx.arcTo(width, height - t, width - r, height - t, r)
                        ctx.lineTo(t, height - t)
                        ctx.lineTo(0, height)
                        ctx.lineTo(0, height - t - r)
                        ctx.arcTo(0, 0, r, 0, r)
                        ctx.closePath()
                        ctx.fill()
                    }
                }
                Text {
                    id: routeTimeText
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -4
                    text: Nav.remainingDuration > 0 ? Nav.remainingDuration + " min" : ""
                    color: "#FFFFFF"
                    font.pixelSize: 16
                    font.bold: true
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: Nav.selectRoute(0)
                }
            }
        }

        // ── Vignetta Rotta Alternativa (Stile Fumetto Grigio) ──
        MapQuickItem {
            visible: root.inPreview && Nav.hasAltRoute
            coordinate: Nav.altRouteMidpoint
            anchorPoint.x: 0
            anchorPoint.y: 38
            sourceItem: Item {
                width: altTimeText.implicitWidth + 24
                height: 38
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.fillStyle = "#5C5E62"
                        ctx.beginPath()
                        var r = 8
                        var t = 8
                        ctx.moveTo(r, 0)
                        ctx.lineTo(width - r, 0)
                        ctx.arcTo(width, 0, width, r, r)
                        ctx.lineTo(width, height - t - r)
                        ctx.arcTo(width, height - t, width - r, height - t, r)
                        ctx.lineTo(t, height - t)
                        ctx.lineTo(0, height)
                        ctx.lineTo(0, height - t - r)
                        ctx.arcTo(0, 0, r, 0, r)
                        ctx.closePath()
                        ctx.fill()
                    }
                }
                Text {
                    id: altTimeText
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -4
                    text: Nav.altRouteDuration > 0 ? Nav.altRouteDuration + " min" : ""
                    color: "#FFFFFF"
                    font.pixelSize: 16
                    font.bold: true
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: Nav.selectRoute(1)
                }
            }
        }

        MapQuickItem {
            visible: Nav.hasRoute   // dl93: standard pin also in the preview with stops
            coordinate: Nav.destination
            anchorPoint.x: 16
            anchorPoint.y: 36
            sourceItem: Image {
                source: "qrc:/VoltaApp/icons/map-pin.svg"
                sourceSize.width: 32
                sourceSize.height: 36
                width: 32
                height: 36
            }
        }

        // Intermediate stops: same pin as the arrival, with the stop's number
        MapItemView {
            model: Nav.waypoints
            delegate: MapQuickItem {
                coordinate: modelData
                anchorPoint.x: 16
                anchorPoint.y: 36
                // dl93: same pin as the arrival, without number
                sourceItem: Image {
                    source: "qrc:/VoltaApp/icons/map-pin.svg"
                    sourceSize: Qt.size(32, 36)
                    width: 32
                    height: 36
                }
            }
        }

        // ── Black pin (meta.svg) for the place selected by tapping the map ──
        MapQuickItem {
            visible: root.placeDetailsOpen && root.selectedPlace !== null && !root.selectedPlaceIsNearby && !root.selectedFromOwnPoi
            coordinate: root.selectedPlace ? QtPositioning.coordinate(root.selectedPlace.lat, root.selectedPlace.lon) : QtPositioning.coordinate(0, 0)
            anchorPoint.x: 16
            anchorPoint.y: 36
            sourceItem: Image {
                source: "qrc:/VoltaApp/icons/meta.svg"
                sourceSize: Qt.size(64, 72)
                width: 32
                height: 36
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
        }

        // ── Dots on the upcoming maneuvers + blue signs with the road (like EVs) ──
        MapItemView {
            model: Nav.navigating ? Nav.upcomingManeuvers.slice(0, 3) : []
            delegate: MapQuickItem {
                visible: modelData.lat !== undefined && !root.placeDetailsOpen && map.zoomLevel >= 13.5
                coordinate: QtPositioning.coordinate(modelData.lat || 0, modelData.lon || 0)
                anchorPoint.x: 7
                anchorPoint.y: 7
                z: 8
                sourceItem: Item {
                    width: 14; height: 14
                    Rectangle {          // dot on the route
                        anchors.fill: parent
                        radius: 8
                        color: "#FFFFFF"
                        border.width: 3
                        border.color: "#0A84FF"
                    }
                    Rectangle {          // sign with the road name (first two maneuvers)
                        id: roadTag
                        visible: index < 2 && (modelData.name || modelData.ref) !== ""
                        x: 20; y: -height - 6
                        height: 26
                        width: tagRow.width + 16
                        radius: 8
                        color: "#0A6FD6"
                        border.width: 1; border.color: "#CCFFFFFF"
                        Row {
                            id: tagRow
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle {      // badge with the road number (e.g. A4)
                                visible: (modelData.ref || "") !== ""
                                height: 18; width: refTxt.implicitWidth + 10
                                radius: 3; color: "#FFFFFF"
                                anchors.verticalCenter: parent.verticalCenter
                                Text { id: refTxt; anchors.centerIn: parent; text: modelData.ref || ""
                                       color: "#0A3D7A"; font.pixelSize: 11; font.weight: Font.Bold }
                            }
                            Text {
                                visible: (modelData.name || "") !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name || ""
                                color: "#FFFFFF"; font.pixelSize: 13; font.weight: Font.Bold
                                width: Math.min(implicitWidth, 190)
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        // ── Traffic lights and stop signs (the app's icons, only at close zoom) ──
        MapItemView {
            model: sigModel
            delegate: MapQuickItem {
                visible: root.nearbyPanelType === "" && map.zoomLevel >= root.trafficMinZoom
                coordinate: QtPositioning.coordinate(model.lat, model.lon)
                readonly property bool isStop: model.kind === "stop"
                anchorPoint.x: isStop ? 11 : 8
                anchorPoint.y: isStop ? 11 : 13
                z: 4
                sourceItem: Image {
                    width: isStop ? 22 : 16
                    height: isStop ? 22 : 26
                    source: isStop ? "qrc:/VoltaApp/icons/map_stop.svg" : "qrc:/VoltaApp/icons/map_semaforo.svg"
                    sourceSize: isStop ? Qt.size(66, 66) : Qt.size(48, 78)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }
        }

        // ── Speed cameras (small red square with lens, from zoom 14) ──
        MapItemView {
            model: camModel
            delegate: MapQuickItem {
                visible: root.speedCamsEnabled && root.nearbyPanelType === "" && map.zoomLevel >= 14
                coordinate: QtPositioning.coordinate(model.lat, model.lon)
                anchorPoint.x: 13
                anchorPoint.y: 13
                z: 4
                sourceItem: Rectangle {
                    width: 26; height: 26; radius: 8
                    color: model.kind === "redlight" ? "#C9302C" : "#E0443E"
                    border.width: 2; border.color: "#FFFFFF"
                    Rectangle {
                        anchors.centerIn: parent
                        width: 12; height: 12; radius: 6
                        color: "transparent"
                        border.width: 2; border.color: "#FFFFFF"
                        Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: "#FFFFFF" }
                    }
                }
            }
        }

        // ── Own POIs (the app's icons) ──
        MapItemView {
            model: poiModel
            delegate: MapQuickItem {
                visible: root.nearbyPanelType === "" && map.zoomLevel >= model.minz   // with a list open (gas stations, parking...) the POIs disappear
                coordinate: QtPositioning.coordinate(model.lat, model.lon)
                anchorPoint.x: 15
                anchorPoint.y: 15
                z: 5 - model.tier
                sourceItem: Item {
                    width: 30
                    height: 30
                    Image {
                        id: poiImg
                        anchors.fill: parent
                        source: "qrc:/VoltaApp/icons/" + model.icon
                        sourceSize: Qt.size(60, 60)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    Text {
                        visible: map.zoomLevel >= 16.2 && model.tier <= 3
                        anchors.top: poiImg.bottom
                        anchors.topMargin: 1
                        anchors.horizontalCenter: poiImg.horizontalCenter
                        width: Math.min(implicitWidth, 130)
                        text: model.poiName
                        elide: Text.ElideRight
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: root.cText
                        style: Text.Outline
                        styleColor: root.lightTheme ? "#E6FFFFFF" : "#D9000000"
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: root.openPlaceDetails(model.lat, model.lon, model.poiName, "",
                                                         { isBusiness: true, own: true, category: model.category })
                    }
                }
            }
        }

        // ── Letter icons on the map (With Shadow, White and perfectly centered) ──
        MapItemView {
            model: root.nearbyPanelType !== "" ? root.nearbyPlaces : []
            delegate: MapQuickItem {
                coordinate: QtPositioning.coordinate(modelData.lat, modelData.lon)
                anchorPoint.x: 16
                anchorPoint.y: 32
                sourceItem: Item {
                    width: 32
                    height: 32
                    Image { sourceSize: Qt.size(width * 2, height * 2);
                        id: nearPinImg
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        source: "qrc:/VoltaApp/icons/poi_empty.svg"
                    }
                    DropShadow {
                        anchors.fill: nearPinImg
                        source: nearPinImg
                        horizontalOffset: 0
                        verticalOffset: 2
                        radius: 4
                        samples: 9
                        color: "#6A000000"
                        transparentBorder: true
                    }
                    Text {
                        anchors.centerIn: nearPinImg
                        anchors.horizontalCenterOffset: 1.5 // Spostata leggermente a destra
                        anchors.verticalCenterOffset: -1 // Optically centered relative to the drop
                        text: modelData.markerLetter || ""
                        color: "#FFFFFF" // Bianche
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        onClicked: {
                            root.openPlaceDetails(modelData.lat, modelData.lon, modelData.name, modelData.address, {
                                isBusiness: true,
                                category: root.nearbyPanelType === "fuel" ? qsTr("Gas station") :
                                          root.nearbyPanelType === "parking" ? qsTr("Parking") : qsTr("Restaurant")
                            })
                        }
                    }
                }
            }
        }

        // ═══ dl78: navigation arrow as a GEOGRAPHIC polygon (drawn by MapLibre together with the blue line) ═══
        MapPolygon {   // dl79: ombra
            visible: root.arrowGL
            color: "#66000000"
            border.width: 0
            path: root._arrowPoly(root._arrOuter, 1.06, 0.0, -0.035)
        }
        MapPolygon {   // contorno bianco
            visible: root.arrowGL
            color: "#FFFFFF"
            border.width: 0
            path: root._arrowPoly(root._arrOuter, 1.0, 0.0, 0.0)
        }
        MapPolygon {   // riempimento rosso
            visible: root.arrowGL
            color: "#FF3A3A"
            border.width: 0
            path: root._arrowPoly(root._arrRed, 1.0, 0.0, 0.0)
        }

        MapQuickItem {
            visible: !root.arrowGL   // dl78
            coordinate: QtPositioning.coordinate(root.carLat, root.carLon)
            anchorPoint.x: 16
            anchorPoint.y: 16
            sourceItem: Item {
                width: 32
                height: 32
                rotation: root._arrHdg - map.bearing   // dl86
                Image {
                    id: arrowImg
                    anchors.centerIn: parent
                    source: "qrc:/VoltaApp/icons/map-arrow.svg"
                    sourceSize.width: 26
                    sourceSize.height: 29
                    width: 26
                    height: 29
                    visible: Theme.lowPower
                }
                DropShadow {
            visible: !Theme.lowPower
                    anchors.fill: arrowImg
                    source: arrowImg
                    horizontalOffset: 0
                    verticalOffset: 3
                    radius: 8
                    samples: 17
                    color: "#4A000000"
                    transparentBorder: true
                }
            }
        }

        WheelHandler {
            enabled: !root.mapLocked && !root.mapMuted   // kbMuro
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                if (root._overSearchUi(point.scenePosition)) return   // dl89
                root.pokeToolsVisibility()
                root.followCar = false
                flyAnim.stop()
                zoomEaseAnim.stop()
                map.zoomLevel = Math.max(4, Math.min(20,
                    map.zoomLevel + (event.angleDelta.y > 0 ? 0.4 : -0.4)))
            }
        }

        PinchHandler {
            id: pinch
            enabled: !root.mapLocked && !root.mapMuted   // kbMuro
            target: null
            property real startZoom: 0
            property bool rotLatched: false   // dl86
            property bool rotSkip: false
            property real rotAccum: 0
            property real rotLast: 0
            property real rotBase: 0
            property real rotStartB: 0
            property real rotNow: rotation
            onRotNowChanged: {   // dl86: beyond ~10 degrees of two-finger rotation the map turns
                if (!active) return
                if (rotSkip) { rotSkip = false; rotLast = rotNow; return }
                var d = ((rotNow - rotLast) % 360 + 540) % 360 - 180
                rotLast = rotNow
                rotAccum += d
                if (!rotLatched) {
                    if (Math.abs(rotAccum) < 10) return
                    rotLatched = true; rotBase = rotAccum; rotStartB = root._mapBearing
                }
                root._rotateMap(rotStartB - (rotAccum - rotBase))
            }
            onActiveChanged: {
                if (active) {
                    root.pokeToolsVisibility()
                    startZoom = map.zoomLevel
                    rotLatched = false; rotAccum = 0; rotSkip = true; rotLast = rotNow   // dl86
                    root.followCar = false
                }
            }
            onActiveScaleChanged: {
                map.zoomLevel = Math.max(4, Math.min(20,
                    pinch.startZoom + Math.log2(pinch.activeScale)))
            }
        }

        Timer {
            // inertia: after release the map continues and slows down (time constant ~0.4 s)
            id: kineticPan
            interval: 16; repeat: true
            property real vx: 0
            property real vy: 0
            property double lastT: 0
            property double pinchT: 0          // last moment the pinch changed
            function begin(x, y) { vx = x; vy = y; lastT = Date.now(); start() }
            onTriggered: {
                var t = Date.now(), dt = Math.min(50, t - lastT) / 1000
                lastT = t
                var k = Math.exp(-dt / 0.4)
                vx *= k; vy *= k
                if (Math.sqrt(vx * vx + vy * vy) < 25 || root.mapLocked) { stop(); return }
                map.pan(-vx * dt, -vy * dt)
                root.clampMapBounds()
            }
        }

        PointHandler {
            onActiveChanged: {
                if (active) kineticPan.stop()      // qualsiasi tocco ferma l'inerzia
                // dl89: where did the touch start? over a search panel -> the map does not use it
                root._uiPress = active ? root._overSearchUi(point.scenePressPosition) : false
            }
        }

        Connections { target: pinch; function onActiveChanged() { kineticPan.pinchT = Date.now() } }

        DragHandler {   // dl86: dragged right button = rotates the map
            enabled: !root.mapLocked && !root._uiPress   // dl89
            target: null
            acceptedButtons: Qt.RightButton
            // mouse only: on touch "acceptedButtons" filters nothing, and dragging with
            // one finger also made the map rotate (with a finger it rotates only with two)
            acceptedDevices: PointerDevice.Mouse
            onTranslationChanged: (delta) => root._rotateMap(root._mapBearing - delta.x * 0.4)
        }

        DragHandler {
            // dl91: with a panel open the map cannot take the grab from lists and buttons
            grabPermissions: root._searchPanelOpen
                ? (PointerHandler.CanTakeOverFromHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByItems)
                : (PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByItems)
            property real vx: 0
            property real vy: 0
            property double lastT: 0
            property real px: 0
            property real py: 0
            onActiveChanged: {
                if (active) { kineticPan.stop(); vx = 0; vy = 0; lastT = Date.now(); px = 0; py = 0 }
                else if (Date.now() - lastT < 90 && !pinch.active && Date.now() - kineticPan.pinchT > 350 && Math.sqrt(vx * vx + vy * vy) > 150) {
                    var f = Math.min(1, 4000 / Math.sqrt(vx * vx + vy * vy))        // velocita' massima 4000 px/s
                    kineticPan.begin(vx * f, vy * f)
                }
            }
            onActiveTranslationChanged: {
                var t = Date.now(), dt = t - lastT
                var ddx = activeTranslation.x - px, ddy = activeTranslation.y - py
                px = activeTranslation.x; py = activeTranslation.y
                if (dt > 0 && dt < 100) { vx = vx * 0.5 + (ddx / dt * 1000) * 0.5; vy = vy * 0.5 + (ddy / dt * 1000) * 0.5 }
                else if (dt >= 100) { vx = 0; vy = 0 }
                if (pinch.active || Math.sqrt(vx * vx + vy * vy) > 6000) { vx = 0; vy = 0 }   // pinch or center jump: no inertia
                lastT = t
            }
            enabled: !root.mapLocked && !root.mapMuted   // kbMuro
            target: null
            onTranslationChanged: (delta) => {
                root.pokeToolsVisibility()
                root.followCar = false
                flyAnim.stop()
                zoomEaseAnim.stop()
                map.pan(-delta.x, -delta.y)
                root.clampMapBounds()
            }
        }

        TapHandler {
            enabled: !root.mapMuted   // kbMuro
            onTapped: (eventPoint) => {
                var c = map.toCoordinate(eventPoint.position)

                // Selects the route by tapping freely anywhere on the gray line
                if (root.inPreview) {
                    if (Nav.hasAltRoute && root.isPointNearRoute(c, Nav.altRouteDisplayCoordinates)) {
                        Nav.selectRoute(1)
                        return
                    }
                    if (Nav.hasRoute && root.isPointNearRoute(c, Nav.routeDisplayCoordinates)) {
                        Nav.selectRoute(0)
                        return
                    }
                }

                searchInput.focus = false
                root.searchDropdownOpen = false
                root.closePlaceDetails()
                root.pokeToolsVisibility()
            }
        }

        TapHandler {
            enabled: !root.mapLocked && !root.mapMuted   // kbMuro
            longPressThreshold: 0.5
            onLongPressed: {
                var c = map.toCoordinate(point.position)
                root.reverseGeocodeAndOpenPin(c.latitude, c.longitude)
            }
        }
    }

    // Initial cover: hides MapLibre's yellow background until the style is loaded.
    // map_proxy.py starts before the QML, so it usually already answers at the first check:
    // in that case the cover disappears almost immediately (~0.5 s). Only if the proxy was
    // not up yet (slow cold start) the style must be reloaded and it waits a bit longer.
    // Before: first check after 500 ms, on the "light" style (downloaded from the internet even
    // with the dark theme), then a fixed 1.5 s + 0.5 s of fade = 2.5-3 s of blank screen.
    Rectangle {
        id: mapStartCover
        anchors.fill: parent
        color: root.lightTheme ? "#EEF0F2" : "#15171A"
        visible: opacity > 0
        property bool proxyUp: false
        property int tries: 0
        Timer {
            id: coverPoll; interval: 100; repeat: true; running: true; triggeredOnStart: true
            onTriggered: {
                if (mapStartCover.proxyUp) { stop(); return }
                mapStartCover.tries++
                if (mapStartCover.tries > 100) { stop(); coverFade.start(); return }   // 10 s: show anyway
                var first = mapStartCover.tries === 1
                var x = new XMLHttpRequest()
                x.open("GET", "http://127.0.0.1:9098/ping")
                x.onreadystatechange = function() {
                    if (x.readyState !== XMLHttpRequest.DONE || x.status !== 200 || mapStartCover.proxyUp) return
                    mapStartCover.proxyUp = true
                    coverPoll.stop()
                    if (!first) {
                        // the map had asked for the style with the proxy off: I reload it right away
                        // instead of waiting for MapLibre's automatic retries
                        var n = map.supportedMapTypes.length
                        if (n > 1) { map.activeMapType = map.supportedMapTypes[(root.styleIndex + 1) % n]; root.applyStyle(true) }
                    }
                    coverHold.interval = first ? 350 : 900
                    coverHold.start()
                }
                x.send()
            }
        }
        Timer { id: coverHold; interval: 350; onTriggered: coverFade.start() }
        NumberAnimation { id: coverFade; target: mapStartCover; property: "opacity"; to: 0; duration: 250 }
    }

    onCarLatChanged: root._followDirty = true
    onCarLonChanged: root._followDirty = true

    function clampMapBounds() {
        var lon = map.center.longitude
        var lat = map.center.latitude
        // before locked on Europe (lon -25..45, lat 25..72): now the whole world,
        // keeping only the poles out (the map's projection makes no sense there)
        var clampedLon = Math.max(-180, Math.min(180, lon))
        var clampedLat = Math.max(-82, Math.min(82, lat))
        if (clampedLon !== lon || clampedLat !== lat) {
            map.center = QtPositioning.coordinate(clampedLat, clampedLon)
        }
    }

    function followPosition() {
        if (!followCar || flyAnim.running) return
        var target = coordinateForCenterBias(QtPositioning.coordinate(carLat, carLon))
        var c = map.center
        var dLat = (target.latitude  - c.latitude) * 111320
        var dLon = (target.longitude - c.longitude) * 111320 * Math.cos(carLat * Math.PI / 180)
        if (Math.sqrt(dLat * dLat + dLon * dLon) < 0.5) return
        map.center = target
    }

    // When an app is opened/closed in "full-screen map" mode,
    // Main.qml updates "followOffsetPx" — here the camera shift
    // toward the new "distorted" position is animated gently, instead
    // of waiting for the next GPS update (which with the car stopped
    // might not arrive at all) or of jumping abruptly. The zoom
    // stays unchanged (-1 = "do not change").
    onFollowOffsetPxChanged: {
        if (followCar)
            flyTo(coordinateForCenterBias(QtPositioning.coordinate(carLat, carLon)), -1, 450)
    }

    // ── Camera flight "MapLibre/Mapbox style" (van Wijk & Nuij, 2003) ──────────
    // Before, center (in degrees) and zoom were animated separately: going from
    // preview (zoom ~10) to navigation (zoom 17) the camera at first barely
    // moved and at the end "shot" onto the car, because at high zoom every degree is worth
    // 128 times more pixels. Here zoom and movement are computed together on the optimal
    // path: the perceived speed on the screen stays constant, with a slight
    // pull-back halfway if the two points are far apart.
    property real _flyT: 0
    property var  _fly: null
    NumberAnimation {
        id: flyAnim
        target: root; property: "_flyT"; from: 0; to: 1
        easing.type: Easing.InOutQuad
        onFinished: root.followPosition()
    }
    on_FlyTChanged: if (flyAnim.running && root._fly) root._flyStep(root._flyT)

    function _merc(c) {      // coordinate -> Mercator "world" coordinates (0..1)
        var lat = Math.max(-85, Math.min(85, c.latitude)) * Math.PI / 180
        return { x: (c.longitude + 180) / 360,
                 y: (1 - Math.log(Math.tan(lat) + 1 / Math.cos(lat)) / Math.PI) / 2 }
    }
    function _unmerc(x, y) {
        var n = Math.PI - 2 * Math.PI * y
        return QtPositioning.coordinate(180 / Math.PI * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n))), x * 360 - 180)
    }
    function flyTo(coord, zoom, dur) {
        var d = dur === undefined ? 800 : dur
        flyAnim.stop()
        var z0 = map.zoomLevel
        var z1 = (zoom === undefined || zoom < 0) ? z0 : zoom
        var p0 = root._merc(map.center), p1 = root._merc(coord)
        var rho = 1.42                                   // same value as MapLibre GL
        var px = Math.max(map.width, map.height, 1)
        var w0 = px / (256 * Math.pow(2, z0))            // larghezza vista in unita' "mondo"
        var w1 = px / (256 * Math.pow(2, z1))
        var dx = p1.x - p0.x, dy = p1.y - p0.y
        var u1 = Math.sqrt(dx * dx + dy * dy)
        var f = { p0: p0, dx: dx, dy: dy, u1: u1, w0: w0, z0: z0, z1: z1, rho: rho }
        if (u1 < 1e-9) {                                 // zoom only, no movement
            f.S = Math.abs(Math.log(w1 / w0)) / rho
            f.dir = w1 < w0 ? -1 : 1
        } else {
            var r2 = rho * rho
            var b0 = (w1 * w1 - w0 * w0 + r2 * r2 * u1 * u1) / (2 * w0 * r2 * u1)
            var b1 = (w1 * w1 - w0 * w0 - r2 * r2 * u1 * u1) / (2 * w1 * r2 * u1)
            f.r0 = Math.log(Math.sqrt(b0 * b0 + 1) - b0)
            var r1 = Math.log(Math.sqrt(b1 * b1 + 1) - b1)
            f.S = (r1 - f.r0) / rho
        }
        if (!isFinite(f.S) || f.S <= 0) {                // already arrived: just set it
            map.center = coord; map.zoomLevel = z1
            root.followPosition()
            return
        }
        root._fly = f
        root._flyT = 0
        flyAnim.duration = d
        flyAnim.start()
    }
    function _flyStep(t) {
        var f = root._fly
        var s = t * f.S, w, u
        if (f.u1 < 1e-9) {
            w = f.w0 * Math.exp(f.dir * f.rho * s); u = 0
        } else {
            var r = f.rho * s + f.r0
            var cr0 = (Math.exp(f.r0) + Math.exp(-f.r0)) / 2, sr0 = (Math.exp(f.r0) - Math.exp(-f.r0)) / 2
            var cr = (Math.exp(r) + Math.exp(-r)) / 2
            var tr = (Math.exp(2 * r) - 1) / (Math.exp(2 * r) + 1)
            w = f.w0 * cr0 / cr
            u = f.w0 / (f.rho * f.rho) * (cr0 * tr - sr0)
        }
        var k = f.u1 < 1e-9 ? 0 : Math.max(0, Math.min(1, u / f.u1))
        if (t >= 1) { k = 1; w = f.w0 * Math.pow(2, f.z0 - f.z1) }
        map.zoomLevel = f.z0 + Math.log(f.w0 / w) / Math.LN2
        map.center = root._unmerc(f.p0.x + f.dx * k, f.p0.y + f.dy * k)
    }

    NumberAnimation {
        id: zoomEaseAnim
        target: map
        property: "zoomLevel"
        duration: 700
        easing.type: Easing.OutCubic
    }

    function easeZoom(to) {
        if (zoomEaseAnim.running && Math.abs(zoomEaseAnim.to - to) < 0.12) return
        zoomEaseAnim.stop()
        zoomEaseAnim.from = map.zoomLevel
        zoomEaseAnim.to = to
        zoomEaseAnim.start()
    }

    // Pulls back/shifts the map so that ALL the markers A, B, C, D... of the
    // list (plus the starting point) are visible to the right of the panel.
    function fitToNearby(refLat, refLon) {
        var pts = root.nearbyPlaces
        if (!pts || pts.length === 0 || !map) return
        var minLat = refLat, maxLat = refLat, minLon = refLon, maxLon = refLon
        for (var i = 0; i < pts.length; i++) {
            var la = Number(pts[i].lat), lo = Number(pts[i].lon)
            if (isNaN(la) || isNaN(lo)) continue
            if (la < minLat) minLat = la
            if (la > maxLat) maxLat = la
            if (lo < minLon) minLon = lo
            if (lo > maxLon) maxLon = lo
        }
        // minimum area, so as not to zoom too much with a few very close points
        if (maxLat - minLat < 0.004) { minLat -= 0.002; maxLat += 0.002 }
        if (maxLon - minLon < 0.004) { minLon -= 0.002; maxLon += 0.002 }

        var rect = QtPositioning.rectangle(
                    QtPositioning.coordinate(maxLat, minLon),
                    QtPositioning.coordinate(minLat, maxLon))

        var oldC = map.center
        var oldZ = map.zoomLevel
        map.fitViewportToGeoShape(rect, 140)
        var tC = map.center
        var tZ = Math.max(4, Math.min(17, map.zoomLevel - 0.35))
        // shifts the center to the left by half a panel (312px) so the markers
        // end up in the free part on the right of the list
        map.zoomLevel = tZ
        var p0 = map.fromCoordinate(tC, false)
        var shifted = map.toCoordinate(Qt.point(p0.x - 156, p0.y), false)
        map.center = oldC
        map.zoomLevel = oldZ

        root.followCar = false
        root.flyTo(shifted, tZ, 900)
    }

    function fitToRoute() {
        var pts = Nav.routeDisplayCoordinates   // the simplified points are enough for the box
        if (!pts || pts.length < 2) return

        var minLat = 90, maxLat = -90, minLon = 180, maxLon = -180
        for (var i = 0; i < pts.length; i++) {
            var c = pts[i]
            if (c.latitude  < minLat) minLat = c.latitude
            if (c.latitude  > maxLat) maxLat = c.latitude
            if (c.longitude < minLon) minLon = c.longitude
            if (c.longitude > maxLon) maxLon = c.longitude
        }

        var rect = QtPositioning.rectangle(
                    QtPositioning.coordinate(maxLat, minLon),
                    QtPositioning.coordinate(minLat, maxLon))

        var oldC = map.center
        var oldZ = map.zoomLevel

        map.fitViewportToGeoShape(rect, 200)
        var tC = map.center
        var tZ = map.zoomLevel
        // "Camera-only" shift (app open, full-screen map):
        // computed here at tZ (the destination zoom), not at oldZ, because
        // the pixel<->coordinate conversion depends on the zoom level —
        // using the wrong zoom would make the route preview appear
        // shifted by the wrong number of pixels once it arrives at the
        // destination. Before this fix the preview always appeared
        // at the real screen center, under the open app, invisible.
        map.zoomLevel = tZ
        var biasedC = root.coordinateForCenterBias(tC)
        map.center = oldC
        map.zoomLevel = oldZ

        root.followCar = false
        // Keeps a much more distant and comfortable view
        root.flyTo(biasedC, Math.max(4, tZ - 1.5), 900)
    }

    Connections {
        target: Nav
        function onRouteChanged() {
            root._rDirty = true; if (Nav.hasRoute) rBuildTimer.restart()   // dl83: when the flight is over   // dl82: prepares the route already in preview
            if (Nav.hasRoute && !Nav.navigating) {
                if (root._startWhenReady) {
                    // "Start route" pressed before the calculation finished
                    root._startWhenReady = false
                    root.followCar = true
                    Nav.startNavigation()
                    return
                }
                fitTimer.restart()
                root.autoStartCount = 5
                if (!root.placePreview) autoNavTimer.restart()
            }
        }
        function onNavigatingChanged() {
            root.navExpanded = false
            // coordinateForCenterBias here: without it, when navigation
            // started the camera first flew to the real screen center
            // (under the open app) and only at the next GPS update
            // (via followPosition) corrected itself toward the left — hence the
            // route that "started at the center and then moved".
            var here = root.coordinateForCenterBias(QtPositioning.coordinate(root.carLat, root.carLon), 0)
            if (Nav.navigating) {
                autoNavTimer.stop()
                root.followCar = true
                // dl82: initial angle = route direction (not the old one) and camera computed for that angle
                if (root._rBuild()) {
                    var s0 = root._rLocate(root.carLat, root.carLon, undefined)
                    if (s0 >= 0) root.bearingRot = root._rBearing(s0)
                }
                here = root.coordinateForCenterBias(QtPositioning.coordinate(root.carLat, root.carLon), root.bearingRot)
                root.flyTo(here, root.navZoomDef, 1500)   // anteprima -> navigazione: volo morbido
            } else {
                root._freeBearing = 0   // dl86
                root.flyTo(here, root.freeZoom, 900)
            }
        }
        function onRouteFailed(reason) {
            root._startWhenReady = false
            root._toastText = (reason && reason.length)
                ? reason : qsTr("Unable to calculate the route")
            toast.opacity = 1
            toastTimer.restart()
        }
    }

    Timer {
        id: fitTimer
        interval: 0
        repeat: false
        onTriggered: root.fitToRoute()
    }

    property string _toastText: ""
    Rectangle {
        id: toast
        z: 6000
        opacity: 0
        radius: 10
        color: "#E6222222"
        border.color: "#40FFFFFF"
        border.width: 1
        width: Math.min(root.width - 40, toastLabel.implicitWidth + 36)
        height: toastLabel.implicitHeight + 24
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 120
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text {
            id: toastLabel
            anchors.centerIn: parent
            width: parent.width - 36
            text: root._toastText
            color: "white"
            font.pixelSize: 15
            font.bold: false
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }
    Timer {
        id: toastTimer
        // Before 3200ms — too little to read a message while driving,
        // especially the error one (see NavigationManager::onRouteReply).
        interval: 5000
        repeat: false
        onTriggered: toast.opacity = 0
    }

    // Current street and city: requested only if we moved at least 25 m
    // (before every 8 s even when stopped: ~10,000 geocoding calls per day)
    property real _geoLat: 0
    property real _geoLon: 0
    Timer {
        interval: 8000
        running: root.gpsReceived
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root._geoLat !== 0 && root._camDist(root._geoLat, root._geoLon, root.carLat, root.carLon) < 25) return
            root._geoLat = root.carLat; root._geoLon = root.carLon
            var xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE && xhr.status !== 200) root._geoLat = 0   // retry at the next round
                if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                    try {
                        var d = JSON.parse(xhr.responseText)
                        if (d.street) root.currentStreet = d.street
                        if (d.city) root.currentCity = d.city
                    } catch (e) {}
                }
            }
            xhr.open("GET", "http://127.0.0.1:9098/reverse-geocode?lat=" + root.carLat + "&lon=" + root.carLon)
            xhr.send()
        }
    }

    // GPS: from the receiver read directly in C++ (GpsService, context property
    // "Gps"), 10 times per second. Before it went through map_service.py and a WebSocket
    // that also had to be reconnected by hand.
    Connections {
        target: Gps
        enabled: root.active || root.miniActive
        function onUpdated(d) { root.handleGpsFix(d) }
    }
    function handleGpsFix(d) {
        try {
            if (!d.fix) return
            root.speedKmh = (d.speed || 0) * 3.6

            if (root.gpsReceived) {
                var dLat = (d.lat - root._lastFixLat) * 111320
                var dLon = (d.lon - root._lastFixLon) * 111320 * Math.cos(d.lat * Math.PI / 180)
                var moved = Math.sqrt(dLat * dLat + dLon * dLon)

                var deadband = root.speedKmh < 3.0 ? 25.0 : 1.5
                if (moved < deadband) return
            }
            root._lastFixLat = d.lat
            root._lastFixLon = d.lon

            if (!root._riding && root.speedKmh >= root.bearingMinSpeed && d.bearing !== undefined)   // dl77
                root.bearingRot = d.bearing

            Nav.updatePosition(d.lat, d.lon, root.bearingRot, root.speedKmh)

            if ((Nav.snapped || (root._riding && Nav.navigating && Date.now() - root._sFixMs < 4000))   // dl80
                    && root._rideFix(Nav.snapped ? Nav.snappedPosition.latitude : d.lat, Nav.snapped ? Nav.snappedPosition.longitude : d.lon,
                                     (d.bearing !== undefined && root.speedKmh >= root.bearingMinSpeed) ? d.bearing : root.bearingRot)) {
                // dl76: the arrow slides along the route (see _rideFix / onCarSChanged)
            } else if (Nav.snapped) {
                root._riding = false   // dl77
                root.carLat = Nav.snappedPosition.latitude
                root.carLon = Nav.snappedPosition.longitude
                root.bearingRot = Nav.routeBearing
            } else {
                root._riding = false   // dl77
                root.carLat = d.lat
                root.carLon = d.lon
            }

            if (!root.gpsReceived) { root.gpsReceived = true; root.followCar = true }

            if (root.followCar && Nav.navigating && !flyAnim.running) {
                var target = Nav.distanceToManeuver < 150
                             ? root.maneuverZoom
                             : Nav.zoomForSpeed(root.speedKmh)
                root.easeZoom(target)
            }
        } catch (e) { console.log("[MapLibre] GPS err:", e) }
    }
    // ── FAKE GPS (tests only) ──
    // Active if ~/.config/volta_fake_gps exists (read every 3 s, no restart).
    // Content: "lat,lon" of the start, optional ",meters_per_step" (default 15 every 0.5 s).
    // Choose a destination and start navigation: the fake car follows the real route.
    SystemHelper { id: fakeGpsSys }
    property bool fakeGps: false
    // The mini-map (full-screen car panel) shows the same fake car: the big map
    // keeps "driving" even when it is not visible, and passes the position with this signal.
    property bool miniActive: false
    signal fakeFix(real lat, real lon, real bearing)
    property real _fgLat: 45.4642
    property real _fgLon: 9.1900
    property real _fgDist: 0
    property real _fgStep: 15
    property real _fgBearing: 0
    function _fgMeters(aLat, aLon, bLat, bLon) {
        var dLat = (bLat - aLat) * 111320
        var dLon = (bLon - aLon) * 111320 * Math.cos(aLat * Math.PI / 180)
        return Math.sqrt(dLat * dLat + dLon * dLon)
    }
    Timer {
        interval: 3000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: {
            var home = StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace("file://", "")
            var txt = fakeGpsSys.readTextFile(home + "/.config/volta_fake_gps").trim()
            var on = txt !== ""
            if (on && !root.fakeGps) {
                var p = txt.split(",")
                var la = parseFloat(p[0]), lo = parseFloat(p[1]), st = parseFloat(p[2])
                if (!isNaN(la) && !isNaN(lo)) { root._fgLat = la; root._fgLon = lo }
                root._fgStep = (!isNaN(st) && st > 0) ? st : 15
                root._fgDist = 0
            }
            root.fakeGps = on
        }
    }
    Connections {
        target: Nav
        function onRouteChanged() { root._fgDist = 0 }
        function onNavigatingChanged() { root._fgDist = 0 }
    }
    Timer {
        interval: 1000; repeat: true
        running: root.fakeGps && (root.active || root.miniActive) && !root.navExpanded
        onTriggered: {
            var spd = 0
            var pts = Nav.routeCoordinates
            if (Nav.navigating && pts && pts.length > 1) {
                root._fgDist += root._fgStep
                var rem = root._fgDist, i = 0, seg = 0
                for (; i < pts.length - 1; i++) {
                    seg = root._fgMeters(pts[i].latitude, pts[i].longitude,
                                         pts[i + 1].latitude, pts[i + 1].longitude)
                    if (rem <= seg) break
                    rem -= seg
                }
                if (i >= pts.length - 1) {
                    root._fgLat = pts[pts.length - 1].latitude
                    root._fgLon = pts[pts.length - 1].longitude
                } else {
                    var f = seg > 0 ? rem / seg : 0
                    var a = pts[i], b = pts[i + 1]
                    root._fgLat = a.latitude  + (b.latitude  - a.latitude)  * f
                    root._fgLon = a.longitude + (b.longitude - a.longitude) * f
                    var y = Math.sin((b.longitude - a.longitude) * Math.PI / 180) * Math.cos(b.latitude * Math.PI / 180)
                    var x = Math.cos(a.latitude * Math.PI / 180) * Math.sin(b.latitude * Math.PI / 180)
                          - Math.sin(a.latitude * Math.PI / 180) * Math.cos(b.latitude * Math.PI / 180)
                            * Math.cos((b.longitude - a.longitude) * Math.PI / 180)
                    root._fgBearing = (Math.atan2(y, x) * 180 / Math.PI + 360) % 360
                    spd = 60 / 3.6
                }
            }
            root.handleGpsFix({
                fix: true, lat: root._fgLat, lon: root._fgLon,
                speed: spd, bearing: root._fgBearing })
            root.fakeFix(root._fgLat, root._fgLon, root._fgBearing)
        }
    }
    // ── fine GPS FITTIZIO ──
    Behavior on bearingRot { enabled: !root._riding; RotationAnimation { duration: 500; direction: RotationAnimation.Shortest } }

    // Turn icons: Material Symbols (weight 600), colored with the theme color
    // Trip bar: arrival | duration and distance, destination, progress line, End | •••
    component EtaBlock : EtaPanel {
        id: eta
        k: root.navK
        cText: root.cText
        cSubtle: root.cSubtle
        arrival: Nav.arrivalTime !== "" ? Nav.arrivalTime : "--:--"
        duration: eta.fmtDur(Nav.remainingDuration)
        distance: eta.fmtBig(Nav.remainingDistance)
        destination: root._nextStopName   // dl95
        progress: Nav.progress
        traffic: Nav.trafficFractions
        onStopRequested: root.stopNav()
        onRecenterRequested: root.recenter()
        onAddStopRequested: root.beginAddStop()
        onEditTripRequested: root.openEditTrip()   // dl92
        canAddStop: Nav.waypointCount < Nav.maxStops - 1   // dl92
        function fmtDur(min) {
            if (min <= 0) return qsTr("-- min")
            var h = Math.floor(min / 60), m = min % 60
            return h > 0 ? (h + " h " + m + " min") : (m + " min")
        }
        function fmtBig(m) {
            if (m <= 0) return qsTr("-- km")
            return m >= 100000 ? (Math.round(m / 1000) + " km") : root.fmtDist(m)
        }
    }

    component TurnIcon : Item {
        id: turnIcon
        property string type: ""
        property string modifier: ""
        property color  color: "#F5F5F5"
        // traffico a sinistra (UK, ecc.): rotonde in senso orario, inversione a destra
        property bool leftHandTraffic: false
        // Icons: "TurnByTurn Maneuvers" set (icons/mn_*.svg), chosen from Mapbox/OSRM's type/modifier
        readonly property string glyph: {
            var t = type, m = modifier
            var left  = m.indexOf("left")  >= 0
            var right = m.indexOf("right") >= 0
            var rot   = leftHandTraffic ? "cw" : "ccw"
            var dirName = ""      // straight / left / right / sharp_left / slight_right ...
            if (m === "uturn")             dirName = "uturn"
            else if (m === "sharp left")   dirName = "sharp_left"
            else if (m === "sharp right")  dirName = "sharp_right"
            else if (m === "slight left")  dirName = "slight_left"
            else if (m === "slight right") dirName = "slight_right"
            else if (m === "left")         dirName = "left"
            else if (m === "right")        dirName = "right"
            else if (m === "straight")     dirName = "straight"

            if (t === "arrive")
                return "destination"
            if (t === "depart" && dirName === "")
                return "depart"
            if (t === "exit roundabout" || t === "exit rotary")
                return "roundabout_exit_" + rot
            if (t === "roundabout" || t === "rotary" || t === "roundabout turn")
                return dirName === "" ? ("roundabout_" + rot)
                                      : ("roundabout_" + dirName + "_" + rot)
            if (m === "uturn")
                return leftHandTraffic ? "uturn_cw" : "uturn_ccw"
            if (t === "merge")
                return left ? "merge_left" : (right ? "merge_right" : "merge")
            if (t === "fork")
                return left ? "fork_left" : (right ? "fork_right" : "straight")
            if (dirName === "" || dirName === "straight")
                return "straight"
            return "turn_" + dirName
        }
        Image {
            id: turnImg
            anchors.fill: parent
            source: "qrc:/VoltaApp/icons/mn_" + turnIcon.glyph + ".svg"
            sourceSize: Qt.size(Math.max(64, turnIcon.width * 2), Math.max(64, turnIcon.height * 2))
            fillMode: Image.PreserveAspectFit
            smooth: true
            visible: false
        }
        MultiEffect {
            anchors.fill: turnImg
            source: turnImg
            colorization: 1.0
            colorizationColor: turnIcon.color
        }
    }

    function fmtDist(m) {
        return m >= 1000 ? (m / 1000).toFixed(1) + " km" : Math.round(m) + " m"
    }

    readonly property color cPanelBg:    root.lightTheme ? "#EBE8E8EA" : "#EB141414"
    readonly property color cText:       root.lightTheme ? "#141414"   : "#F5F5F5"
    readonly property color cSubtle:     root.lightTheme ? "#737373"   : "#A3A3A3"
    readonly property color cDivider:    root.lightTheme ? "#14000000" : "#14FFFFFF"
    readonly property color cDivider2:   root.lightTheme ? "#1A000000" : "#1AFFFFFF"

    readonly property color cSelected:   root.lightTheme ? "#000000"   : "#FFFFFF"
    readonly property color cUnselected: "#888888"

    readonly property color cIconBadge:  root.lightTheme ? "#D0D0D2"   : "#2C2C2C"

    readonly property bool inPreview: Nav.hasRoute && !Nav.navigating
    // dl92: preview with stops: first leg blue, following legs gray, black pins
    readonly property bool _legPreview: root.inPreview && Nav.waypointCount > 0
    // dl94: the legs (blue = current, gray = toward the later stops) also apply during navigation
    readonly property bool _legMode: Nav.hasRoute && Nav.legPaths.length > 1
    // legs already completed (stops reached): no longer drawn
    // dl95: name of the NEXT arrival (first stop if there are any, otherwise the destination)
    readonly property string _nextStopName: (Nav.stops.length > 0 && Nav.stops[0].name)
                                            ? Nav.stops[0].name : Nav.destinationName
    readonly property int _legDone: Math.max(0, Nav.legPaths.length - 1 - Nav.waypointCount)

    component GlassPanel : Item {
        id: gPanel
        property real radius: 10
        default property alias contentData: contentContainer.data

        Rectangle {
            id: shadowCaster
            anchors.fill: parent
            radius: gPanel.radius
            color: "black"
            visible: false
        }

        DropShadow {
            visible: !Theme.lowPower
            anchors.fill: shadowCaster
            source: shadowCaster
            horizontalOffset: 0
            verticalOffset: 4
            radius: 12
            samples: 25
            color: "#4A000000"
            transparentBorder: true
        }

        ShaderEffectSource {
            id: bgGrab
            anchors.fill: parent
            sourceItem: Theme.lowPower ? null : map
            sourceRect: {
                var p = gPanel.mapToItem(map, 0, 0)
                return Qt.rect(p.x, p.y, gPanel.width, gPanel.height)
            }
            live: true
            visible: false
        }

        MultiEffect {
            visible: !Theme.lowPower
            anchors.fill: parent
            source: bgGrab
            // as long as the initial cover is there, no blur (the panel stays solid)
            opacity: mapStartCover.opacity > 0 ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 400 } }
            blurEnabled: true
            blur: 1.0
            blurMax: 16
            autoPaddingEnabled: false
            maskEnabled: true
            maskSource: roundMask
        }

        Rectangle {
            id: roundMask
            anchors.fill: parent
            radius: gPanel.radius
            visible: false
            layer.enabled: true
            color: "#FFFFFF"
        }

        Rectangle {
            anchors.fill: parent
            radius: gPanel.radius
            color: Theme.lowPower ? (root.lightTheme ? "#F2F2F2" : "#262626") : root.cPanelBg
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onWheel: (w)=>w.accepted=true
                onClicked: {}
            }
        }

        Item {
            id: contentContainer
            anchors.fill: parent
        }
    }

    // "Full-screen map" mode (root.externalControls): the compass/recenter
    // button comes back here, to the left of the search bar — exactly the same
    // block that was in the vertical column below (same
    // Canvas that rotates with "map.bearing" in real time, same N/S/E/W
    // text), only repositioned: not a new icon, the same as before.
    // In normal mode it stays where it always was (vertical
    // column at the top right, together with the 5 buttons below).
    GlassPanel {
        id: recenterPanel
        width: root.barH; height: root.barH; radius: 10
        z: 50

        // Position with numeric x/y instead of multiple anchors in a ternary:
        // alternating several anchor.line between a value and "undefined" is fragile in
        // QML (crossed bindings may stay not cleaned up correctly
        // when switching between modes several times), and it is the cause
        // of the reported bug ("the north button took the place of the search
        // bar" after opening and closing an app). With simple x/y
        // there is no ambiguity: one value at a time, always consistent.
        x: root.externalControls ? root.mapPad : (parent.width - width - root.mapPad)
        y: root.topPad

        Rectangle {
            anchors.fill: parent
            radius: recenterPanel.radius
            color: recenterMa.pressed ? (root.lightTheme ? "#1A000000" : "#1AFFFFFF") : "transparent"
        }

        // ── Carousel compass (like EVs): the labels N NE E SE S SW W NW slide
        //    horizontally in an arc when the map rotates; the one in front
        //    (your heading) sits at the center, bigger and solid.
        //    Below, the navigation arrow stays still, pointing forward.
        Item {
            id: compassRing
            // drawn on 56 x 56 and scaled to the button's size
            width: 56; height: 56
            scale: parent.width / 56
            transformOrigin: Item.TopLeft
            clip: true
            readonly property color tint: !root.followCar ? root.cSelected : root.cUnselected
            // Proportions from the button's SVG (canvas 1000 x 1000 -> here 56 x 56): labels 8.4 px high
            // (cap 150/1000), at ±22.5° they sit at ±12 px from the center, rotated by ±22°; arrow
            // ~14.6 px wide and ~14.9 px high with the center at 35.7 px from the top.
            readonly property real pxPerDeg: 0.53
            Repeater {
                model: ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
                Text {
                    // angular distance from the front direction: -180..180
                    readonly property real delta: ((index * 45 - map.bearing) % 360 + 540) % 360 - 180
                    readonly property real near: Math.max(0, 1 - Math.abs(delta) / 45)
                    visible: Math.abs(delta) < 75
                    text: modelData
                    color: compassRing.tint
                    font.pixelSize: 9.4 + 4.4 * near
                    font.weight: near > 0.3 ? Font.Bold : Font.Medium
                    opacity: Math.min(1.0, 0.25 + 1.5 * near)   // at ±22.5° (as in the SVG) fully visible
                    x: compassRing.width / 2 + delta * compassRing.pxPerDeg - width / 2
                    // vertical center: 12.5 at the front, goes down to 17 at ±22.5° (as in the SVG)
                    y: 12.5 + 4.5 * Math.min(1.6, Math.pow(delta / 22.5, 2)) - height / 2
                    rotation: Math.max(-30, Math.min(30, delta * 0.98))
                }
            }
            // Navigation arrow: same path as the SVG (canvas 1000 x 1000) scaled to 56 px
            Shape {
                id: compassArrow
                scale: 56 / 1000
                transformOrigin: Item.TopLeft
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: compassRing.tint
                    strokeColor: "transparent"
                    PathSvg { path: "M 484,518 Q 500,492 516,518 L 618,744 Q 630,770 615,771 Q 606,772 588,757 Q 500,672 412,757 Q 394,772 385,771 Q 370,770 382,744 Z" }
                }
            }
        }

        MouseArea {
            id: recenterMa
            anchors.fill: parent
            onClicked: root.recenter()
        }
    }

    GlassPanel {
        id: searchBarPanel
        anchors.top: parent.top
        anchors.topMargin: root.topPad
        // In "full-screen map" mode the search bar makes room,
        // to its left, for the compass/recenter button (recenterPanel,
        // above) — otherwise it stays where it always was, at the left edge.
        anchors.left: root.externalControls ? recenterPanel.right : parent.left
        anchors.leftMargin: root.mapPad
        width: root.panelW
        height: root.barH
        radius: 10
        visible: root.nearbyPanelType === "" && !(root.editTripOpen && !root.addingStop) &&   // dl92
                 (!Nav.navigating || root.toolsVisible || root.addingStop || searchInput.activeFocus || searchInput.text !== "")
        z: 50

        // The whole bar (icon, margins, space above and below the text) brings focus to the search:
        // before the tap only counted if it fell exactly on the text line
        MouseArea {
            anchors.fill: parent
            onPressed: searchInput.forceActiveFocus()
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 20 * root.fS
            anchors.rightMargin: 20 * root.fS
            spacing: 12 * root.fS

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 24 * root.fS
                height: 24 * root.fS
                opacity: 0.8
                Image {
                    id: searchImg
                    anchors.fill: parent
                    source: "qrc:/VoltaApp/icons/Icons_search_black.svg"
                    sourceSize: Qt.size(48 * root.fS, 48 * root.fS)
                    visible: false
                }
                ColorOverlay {
                    anchors.fill: searchImg
                    source: searchImg
                    color: root.cText
                }
            }

            TextInput {
                id: searchInput
                width: parent.width - 36 * root.fS - (root.addingStop ? 82 * root.fS : 0)   // dl92
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                color: root.cText
                font.pixelSize: 17 * root.fS
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                selectByMouse: true
                activeFocusOnPress: true
                EnterKeyAction.actionId: EnterKeyAction.Search
                EnterKeyAction.label: qsTr("Search")
                onTextChanged: searchDebounce.restart()
                Keys.onReturnPressed: { searchDebounce.stop(); root.doSearch() }
                Keys.onEnterPressed:  { searchDebounce.stop(); root.doSearch() }
                Keys.onEscapePressed: { searchInput.text = ""; root.poiSearchResults = []; root.addingStop = false; root.searchDropdownOpen = false }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text === ""
                    text: root.addingStop ? qsTr("Search for the stop to add") : qsTr("Search destination")
                    color: root.cSubtle
                    font.pixelSize: 17 * root.fS
                }
            }
        }
        Timer { id: searchDebounce; interval: 350; onTriggered: root.doSearch() }

        // dl92: while searching for a stop: Cancel (goes back to how it was, or to Edit route)
        MouseArea {
            visible: root.addingStop
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 92 * root.fS
            onClicked: root.cancelAddStop()
            Text {
                anchors.centerIn: parent
                text: qsTr("Cancel")
                color: "#4C9BFF"
                font.pixelSize: 16 * root.fS
                font.weight: Font.DemiBold
            }
        }

    }

    GlassPanel {
        id: searchDropdownPanel
        anchors.top: searchBarPanel.bottom
        anchors.topMargin: root.mapPad
        anchors.left: parent.left
        anchors.leftMargin: root.leftInset
        anchors.bottom: parent.bottom
        // Same reason as nearbyPanel/placeDetailsPanel: in
        // "full-screen map" mode more bottom margin so as not to reach
        // into the music player's band.
        anchors.bottomMargin: root.externalControls ? 211 : 88
        width: root.panelW
        radius: 10
        visible: root.searchDropdownOpen
        z: 51
        clip: true
        TapHandler { id: _dropTap; gesturePolicy: TapHandler.DragThreshold; grabPermissions: PointerHandler.ApprovesTakeOverByAnything }

        Column {
            id: dropdownHeader
            width: parent.width

            Row {
                width: parent.width
                height: 60
                spacing: 10
                leftPadding: 14
                rightPadding: 14
                topPadding: 10
                bottomPadding: 10

                Rectangle {
                    width: (parent.width - 24 - 10) / 2
                    height: 40
                    radius: 8
                    color: "transparent"
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Image { sourceSize: Qt.size(width * 2, height * 2);
                            id: homeIco
                            source: "qrc:/VoltaApp/icons/home.svg"
                            width: 17
                            height: 17
                            anchors.verticalCenter: parent.verticalCenter
                            layer.enabled: true
                            layer.effect: MultiEffect { colorization: 1.0; colorizationColor: root.cText }
                        }
                        Text { text: qsTr("Home", "shortcut"); color: root.cText; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.searchDropdownOpen = false; root.navigateHome() }
                    }
                }

                Rectangle {
                    width: (parent.width - 24 - 10) / 2
                    height: 40
                    radius: 8
                    color: "transparent"
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Image { sourceSize: Qt.size(width * 2, height * 2);
                            id: workIco
                            source: "qrc:/VoltaApp/icons/work.svg"
                            width: 17
                            height: 17
                            anchors.verticalCenter: parent.verticalCenter
                            layer.enabled: true
                            layer.effect: MultiEffect { colorization: 1.0; colorizationColor: root.cText }
                        }
                        Text { text: qsTr("Work"); color: root.cText; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.searchDropdownOpen = false; root.navigateWork() }
                    }
                }
            }

            Item {
                width: parent.width
                height: 40

                ListView {
                    id: tabsRow
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    leftMargin: 8
                    rightMargin: 16
                    spacing: 4
                    model: [qsTr("Recent"), qsTr("Favorites"), qsTr("Gas stations"), qsTr("Restaurants")]

                    delegate: Item {
                        width: tabLabel.implicitWidth + 24
                        height: tabsRow.height

                        readonly property bool isSelected: (index === 0 && root.searchTab === "recenti") ||
                                                           (index === 1 && root.searchTab === "preferiti") ||
                                                           (index === 2 && root.nearbyPanelType === "fuel") ||
                                                           (index === 3 && root.nearbyPanelType === "restaurant")

                        Text {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 13
                            font.weight: parent.isSelected ? Font.DemiBold : Font.Normal
                            color: parent.isSelected ? root.cText : root.cSubtle
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (index === 0) { root.nearbyPanelType = ""; root.searchTab = "recenti" }
                                else if (index === 1) { root.nearbyPanelType = ""; root.searchTab = "preferiti" }
                                else if (index === 2) { root.searchTab = ""; root.openNearbyPanel("fuel") }
                                else if (index === 3) { root.searchTab = ""; root.openNearbyPanel("restaurant") }
                            }
                        }
                    }
                }
            }
        }

        Flickable {
            id: dropdownFlick
            anchors.top: dropdownHeader.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            contentWidth: width
            contentHeight: contentCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: contentCol
                width: parent.width

                Column {
                    width: parent.width
                    visible: root.searchTab === "recenti"

                    Repeater {
                        model: root.recentSearchGroups
                        Column {
                            width: parent.width
                            Text {
                                text: modelData.label
                                color: root.cSubtle
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                leftPadding: 20
                                topPadding: 14
                                bottomPadding: 4
                            }
                            Repeater {
                                model: modelData.items
                                Item {
                                    width: parent.width
                                    height: 76

                                    Column {
                                        id: recDistCol
                                        width: 52
                                        anchors.right: parent.right
                                        anchors.rightMargin: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 52
                                            height: 52
                                            radius: 8
                                            color: root.cIconBadge
                                            Column {
                                                anchors.centerIn: parent
                                                spacing: 2
                                                Image { sourceSize: Qt.size(width * 2, height * 2);
                                                    id: recIco
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: 28
                                                    height: 28
                                                    fillMode: Image.PreserveAspectFit
                                                    source: "qrc:/VoltaApp/icons/poi_generic.svg"
                                                }
                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: root.distanceKmTo(modelData.lat, modelData.lon).toFixed(1) + " km"
                                                    color: root.cSubtle
                                                    font.pixelSize: 10
                                                }
                                            }
                                        }
                                    }

                                    Column {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 16
                                        anchors.right: recDistCol.left
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2
                                        Text { text: modelData.name; color: root.cText; font.pixelSize: 14; elide: Text.ElideRight; width: parent.width }
                                        Text { text: modelData.address; color: root.cSubtle; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width; visible: modelData.address !== "" }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (root.addingStop) { root.commitStopFromSearch(modelData); searchInput.text = ""; searchInput.focus = false; return }   // dl92
                                            root.openPlaceDetails(modelData.lat, modelData.lon, modelData.name, modelData.address, {
                                                isBusiness: modelData.isBusiness, category: modelData.category,
                                                phone: modelData.phone, website: modelData.website
                                            })
                                            searchInput.text = ""
                                            searchInput.focus = false
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: root.recentSearches.length === 0
                        text: qsTr("No recent searches")
                        color: root.cSubtle
                        font.pixelSize: 14
                        leftPadding: 20
                        topPadding: 24
                        bottomPadding: 24
                    }
                }

                Column {
                    width: parent.width
                    visible: root.searchTab === "preferiti"

                    Repeater {
                        model: root.favoritePlaces
                        Item {
                            width: parent.width
                            height: 76

                            Column {
                                id: favDistCol
                                width: 52
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 52
                                    height: 52
                                    radius: 8
                                    color: root.cIconBadge
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Image { sourceSize: Qt.size(width * 2, height * 2);
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 28
                                            height: 28
                                            fillMode: Image.PreserveAspectFit
                                            source: "qrc:/VoltaApp/icons/poi_generic.svg"
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: root.distanceKmTo(modelData.lat, modelData.lon).toFixed(1) + " km"
                                            color: root.cSubtle
                                            font.pixelSize: 10
                                        }
                                    }
                                }
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.right: favDistCol.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text { text: modelData.name; color: root.cText; font.pixelSize: 14; elide: Text.ElideRight; width: parent.width }
                                Text { text: modelData.address; color: root.cSubtle; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width; visible: modelData.address !== "" }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (root.addingStop) { root.commitStopFromSearch(modelData); searchInput.text = ""; searchInput.focus = false; return }   // dl92
                                    root.openPlaceDetails(modelData.lat, modelData.lon, modelData.name, modelData.address, {
                                        isBusiness: modelData.isBusiness, category: modelData.category,
                                        phone: modelData.phone, website: modelData.website
                                    })
                                    searchInput.text = ""
                                    searchInput.focus = false
                                }
                            }
                        }
                    }

                    Text {
                        visible: root.favoritePlaces.length === 0
                        text: qsTr("No favorites yet")
                        color: root.cSubtle
                        font.pixelSize: 14
                        leftPadding: 20
                        topPadding: 24
                        bottomPadding: 24
                    }
                }
            }
        }
    }

    GlassPanel {
        id: nearbyPanel
        anchors.top: parent.top
        anchors.topMargin: root.topPad
        anchors.left: parent.left
        anchors.leftMargin: root.leftInset
        anchors.bottom: parent.bottom
        // In "full-screen map" mode the music player sits at the
        // bottom left (see widgetsContainer in Main.qml: bottomMargin 88 +
        // height ~107 = ~195px occupied from the bottom): a margin of 88 here
        // (meant for normal mode) makes the list reach right
        // into that band, visually "disturbing" the music player
        // below — here the panel stops higher up, well above.
        anchors.bottomMargin: root.externalControls ? 211 : 88
        width: root.panelW
        radius: 10
        visible: root.nearbyPanelType !== "" && !root.placeDetailsOpen
        z: 52
        clip: true

        Column {
            id: nearbyCol
            width: parent.width

            Item {
                id: nearbyHeader
                width: parent.width
                height: 52
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.nearbyPanelType === "fuel" ? qsTr("Gas stations nearby")
                        : root.nearbyPanelType === "parking" ? qsTr("Parking nearby")
                        : qsTr("Restaurants nearby")
                    color: root.cText
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"
                    color: root.cSubtle
                    font.pixelSize: 18
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        onClicked: root.nearbyPanelType = ""
                    }
                }
            }
        }

        Flickable {
            id: nearbyFlick
            anchors.top: nearbyCol.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            contentWidth: width
            contentHeight: nearbyListCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: nearbyListCol
                width: parent.width

                Row {
                    visible: root.nearbyLoading
                    leftPadding: 20; topPadding: 20; bottomPadding: 20
                    spacing: 10
                    Spinner { size: 20; anchors.verticalCenter: parent.verticalCenter; running: parent.visible }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Searching…")
                        color: root.cSubtle
                        font.pixelSize: 14
                    }
                }
                Text {
                    visible: !root.nearbyLoading && root.nearbyPlaces.length === 0
                    text: qsTr("No results nearby")
                    color: root.cSubtle
                    font.pixelSize: 14
                    leftPadding: 20
                    topPadding: 20
                    bottomPadding: 20
                }

                Repeater {
                    model: root.nearbyPlaces
                    Item {
                        width: parent.width
                        height: 78

                        Rectangle {
                            id: distBadge
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 52
                            height: 52
                            radius: 8
                            color: root.cIconBadge
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                Item {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 28
                                    height: 28
                                    Image { sourceSize: Qt.size(width * 2, height * 2);
                                        anchors.fill: parent
                                        fillMode: Image.PreserveAspectFit
                                        source: "qrc:/VoltaApp/icons/poi_empty.svg"
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        anchors.horizontalCenterOffset: 1.5 // Spostata leggermente a destra
                                        anchors.verticalCenterOffset: -1 // Centered because of the drop
                                        text: modelData.markerLetter || ""
                                        color: "#FFFFFF"
                                        font.pixelSize: 13
                                        font.bold: true
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.distanceKm.toFixed(1) + " km"
                                    color: root.cSubtle
                                    font.pixelSize: 9
                                }
                            }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.right: distBadge.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Row {
                                width: parent.width; spacing: 6
                                Text { id: _nmT; text: modelData.name; color: root.cText; font.pixelSize: 15; elide: Text.ElideRight
                                       width: Math.min(implicitWidth, parent.width - (_prP.visible ? _prP.width + 6 : 0)) }
                                Rectangle {
                                    id: _prP
                                    readonly property string pt: root.fuelPriceText(modelData)
                                    visible: pt !== ""
                                    anchors.verticalCenter: _nmT.verticalCenter
                                    height: 17; radius: 3; width: _prT.implicitWidth + 12
                                    color: root.lightTheme ? "#3A3A3A" : "#F2F2F2"
                                    Text { id: _prT; anchors.centerIn: parent; text: _prP.pt + " \u20ac"; font.pixelSize: 11; font.weight: Font.DemiBold
                                           color: root.lightTheme ? "#FFFFFF" : "#1A1A1A" }
                                }
                            }
                            Text { text: modelData.address || ""; color: root.cSubtle; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.openPlaceDetails(modelData.lat, modelData.lon, modelData.name, modelData.address, {
                                    isBusiness: true,
                                    category: root.nearbyPanelType === "fuel" ? qsTr("Gas station")
                                        : root.nearbyPanelType === "parking" ? qsTr("Parking")
                                        : qsTr("Restaurant")
                                })
                                searchInput.text = ""
                                searchInput.focus = false
                            }
                        }
                    }
                }
            }
        }
    }

    GlassPanel {
        id: searchResultsPanel
        anchors.top: searchBarPanel.bottom
        anchors.topMargin: root.mapPad
        anchors.left: parent.left
        anchors.leftMargin: root.leftInset
        width: root.panelW
        radius: 10
        visible: searchBarPanel.visible && searchInput.text !== "" && root.combinedSearchResults.length > 0
        z: 49
        height: Math.min(Math.max(76, suggestions.implicitHeight), root.height - y - (root.externalControls ? 211 : 88))
        clip: true
        TapHandler { id: _resTap; gesturePolicy: TapHandler.DragThreshold; grabPermissions: PointerHandler.ApprovesTakeOverByAnything }

        Flickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: suggestions.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
        Column {
            id: suggestions
            width: parent.width
            Repeater {
                model: root.combinedSearchResults.slice(0, 8)
                Item {
                    width: suggestions.width
                    height: 76

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        anchors.right: locIconContainer.left
                        anchors.rightMargin: 12
                        spacing: 2
                        Text {
                            text: modelData.name
                            color: root.cText
                            font.pixelSize: 16
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        Text {
                            text: modelData.address
                            color: root.cSubtle
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Column {
                        id: locIconContainer
                        width: 52
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 52
                            height: 52
                            radius: 8
                            color: root.cIconBadge
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                Image { sourceSize: Qt.size(width * 2, height * 2);
                                    id: resLocImg
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 28
                                    height: 28
                                    fillMode: Image.PreserveAspectFit
                                    source: "qrc:/VoltaApp/icons/poi_generic.svg"
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.distanceKmTo(modelData.lat, modelData.lon).toFixed(1) + " km"
                                    color: root.cSubtle
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        height: 1
                        color: root.cDivider
                        visible: index < Math.min(root.combinedSearchResults.length, 8) - 1
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (root.addingStop) {
                                root.commitStopFromSearch(modelData)   // dl92
                            } else {
                                root.openPlaceDetails(modelData.lat, modelData.lon, modelData.name, modelData.address, {
                                    isBusiness: modelData.isBusiness, category: modelData.category,
                                    phone: modelData.phone, website: modelData.website
                                })
                            }
                            searchInput.text = ""
                            searchInput.focus = false
                            root.poiSearchResults = []
                        }
                    }
                }
            }
        }
        }   // Flickable
    }

    // ═══ dl92: "Edit route" panel (in place of the search) ═══
    GlassPanel {
        id: editTripPanel
        anchors.top: parent.top
        anchors.topMargin: root.topPad
        anchors.left: parent.left
        anchors.leftMargin: root.leftInset
        width: root.panelW
        radius: 10
        z: 56
        visible: root.editTripOpen && !root.addingStop
        clip: true
        readonly property real s: root.uPx
        readonly property real rowH: Math.round(64 * s)
        readonly property real titleH: Math.round(46 * s)
        readonly property real addH: Math.round(54 * s)
        readonly property real btnH: Math.round(48 * s)
        readonly property real padX: Math.round(14 * s)
        readonly property bool canAdd: root.editStops.length < Nav.maxStops
        height: titleH + root.editStops.length * rowH + (canAdd ? addH : 0) + btnH + Math.round(26 * s)

        Connections {
            target: Nav
            function onRouteChanged() { if (!Nav.hasRoute && root.editTripOpen) root.closeEditTrip(false) }
        }

        Text {
            x: 0; y: 0
            width: parent.width
            height: editTripPanel.titleH
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Edit route")
            color: root.cText
            font.pixelSize: Math.round(15 * editTripPanel.s)
            font.weight: Font.DemiBold
        }

        Item {
            id: etList
            y: editTripPanel.titleH
            width: parent.width
            height: root.editStops.length * editTripPanel.rowH
            property int dragIdx: -1
            property int dropIdx: -1

            Repeater {
                model: root.editStops
                delegate: Item {
                    id: etRow
                    width: etList.width
                    height: editTripPanel.rowH
                    readonly property real s: editTripPanel.s
                    readonly property bool dragging: etHandleDrag.active
                    property real dragOff: 0
                    readonly property int slot: {
                        var d = etList.dragIdx, t = etList.dropIdx
                        if (d < 0 || index === d) return index
                        if (d < t && index > d && index <= t) return index - 1
                        if (d > t && index >= t && index < d) return index + 1
                        return index
                    }
                    y: slot * height + (dragging ? dragOff : 0)
                    z: dragging ? 10 : 0
                    Behavior on y { enabled: !etRow.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: root.lightTheme ? "#18000000" : "#22FFFFFF"
                        visible: etRow.dragging
                    }

                    // ≡ handle to drag
                    Item {
                        id: etHandle
                        x: editTripPanel.padX
                        width: Math.round(40 * etRow.s)
                        height: parent.height
                        Column {
                            anchors.centerIn: parent
                            spacing: Math.round(4 * etRow.s)
                            Repeater {
                                model: 2
                                Rectangle { width: Math.round(16 * etRow.s); height: Math.max(2, Math.round(2 * etRow.s)); radius: 1; color: root.cSubtle }
                            }
                        }
                        DragHandler {
                            id: etHandleDrag
                            target: null
                            xAxis.enabled: false
                            grabPermissions: PointerHandler.CanTakeOverFromAnything
                            onActiveChanged: {
                                if (active) {
                                    etList.dragIdx = index
                                    etList.dropIdx = index
                                    etRow.dragOff = 0
                                } else {
                                    var d = etList.dragIdx, t = etList.dropIdx
                                    etList.dragIdx = -1
                                    etList.dropIdx = -1
                                    etRow.dragOff = 0
                                    if (d >= 0 && t >= 0 && d !== t) root.moveEditStop(d, t)
                                }
                            }
                            onTranslationChanged: {
                                if (!active) return
                                etRow.dragOff = translation.y
                                var t = Math.round((index * etRow.height + translation.y) / etRow.height)
                                etList.dropIdx = Math.max(0, Math.min(root.editStops.length - 1, t))
                            }
                        }
                    }

                    // stop dot + line toward the next stop
                    Image {   // dl93: map's arrival pin
                        id: etRing
                        x: editTripPanel.padX + Math.round(44 * etRow.s)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(22 * etRow.s)
                        height: Math.round(25 * etRow.s)
                        source: "qrc:/VoltaApp/icons/map-pin.svg"
                        sourceSize: Qt.size(64, 72)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    Rectangle {
                        visible: index < root.editStops.length - 1 && !etRow.dragging
                        x: etRing.x + etRing.width / 2 - width / 2
                        y: parent.height / 2 + etRing.height / 2 + 2
                        width: 2
                        height: parent.height - etRing.height - 4
                        color: root.cSubtle
                        opacity: 0.45
                    }

                    // nome e indirizzo
                    Column {
                        x: etRing.x + etRing.width + Math.round(12 * etRow.s)
                        width: parent.width - x - Math.round(52 * etRow.s)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            width: parent.width
                            text: modelData.name
                            color: root.cText
                            font.pixelSize: Math.round(14 * etRow.s)
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: !!modelData.address
                            text: modelData.address || ""
                            color: root.cSubtle
                            font.pixelSize: Math.round(11 * etRow.s)
                            elide: Text.ElideRight
                        }
                    }

                    // X: removes the stop (the last remaining one cannot be removed)
                    Item {
                        visible: root.editStops.length > 1
                        anchors.right: parent.right
                        anchors.rightMargin: editTripPanel.padX - Math.round(6 * etRow.s)
                        width: Math.round(40 * etRow.s); height: parent.height
                        Rectangle { anchors.centerIn: parent; width: Math.round(14 * etRow.s); height: Math.max(2, Math.round(2 * etRow.s)); rotation: 45; color: root.cSubtle }
                        Rectangle { anchors.centerIn: parent; width: Math.round(14 * etRow.s); height: Math.max(2, Math.round(2 * etRow.s)); rotation: -45; color: root.cSubtle }
                        MouseArea { anchors.fill: parent; onClicked: root.removeEditStop(index) }
                    }
                }
            }
        }

        // + Aggiungi
        Item {
            id: etAdd
            visible: editTripPanel.canAdd
            y: etList.y + etList.height
            width: parent.width
            height: editTripPanel.addH
            Item {
                id: etPlus
                x: editTripPanel.padX + Math.round(10 * editTripPanel.s)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(20 * editTripPanel.s); height: width
                Rectangle { anchors.centerIn: parent; width: parent.width; height: Math.max(2, Math.round(2 * editTripPanel.s)); color: root.cSubtle }
                Rectangle { anchors.centerIn: parent; height: parent.height; width: Math.max(2, Math.round(2 * editTripPanel.s)); color: root.cSubtle }
            }
            Text {
                x: editTripPanel.padX + Math.round(46 * editTripPanel.s) + Math.round(32 * editTripPanel.s)
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Add")
                color: root.cSubtle
                font.pixelSize: Math.round(14 * editTripPanel.s)
            }
            MouseArea { anchors.fill: parent; onClicked: root.beginAddStop() }
        }

        // Fine / Annulla
        Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: editTripPanel.padX
            anchors.rightMargin: editTripPanel.padX
            anchors.bottomMargin: Math.round(13 * editTripPanel.s)
            spacing: Math.round(10 * editTripPanel.s)
            Rectangle {
                width: (parent.width - parent.spacing) / 2
                height: editTripPanel.btnH
                radius: 8
                color: "#1F6BFF"
                Text { anchors.centerIn: parent; text: qsTr("Done"); color: "#FFFFFF"; font.pixelSize: Math.round(15 * editTripPanel.s); font.weight: Font.DemiBold }
                MouseArea { anchors.fill: parent; onClicked: root.closeEditTrip(true) }
            }
            Rectangle {
                width: (parent.width - parent.spacing) / 2
                height: editTripPanel.btnH
                radius: 8
                color: root.lightTheme ? "#E3E3E5" : "#2E2E30"
                Text { anchors.centerIn: parent; text: qsTr("Cancel"); color: root.cSubtle; font.pixelSize: Math.round(15 * editTripPanel.s); font.weight: Font.DemiBold }
                MouseArea { anchors.fill: parent; onClicked: root.closeEditTrip(false) }
            }
        }
    }

    // ── SPEED CAMERA ALERT (top center) ──
    Rectangle {
        id: camBanner
        visible: root.camAlert !== null
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.topPad
        z: 70
        width: Math.round(300 * root.uPx)
        height: Math.round(68 * root.uPx)
        radius: 10
        color: root.cPanelBg
        readonly property bool over: root.camAlert !== null && root.camAlert.limit > 0 && root.speedKmh > root.camAlert.limit + 3
        border.width: 3
        border.color: over ? "#E0443E" : "#F5A524"
        Row {
            anchors.centerIn: parent
            spacing: 16
            // limit (if known) or symbol
            Rectangle {
                width: 46; height: 46; radius: 23
                anchors.verticalCenter: parent.verticalCenter
                color: "#FFFFFF"
                border.width: 5; border.color: "#D62B35"
                visible: root.camAlert !== null && root.camAlert.limit > 0
                Text { anchors.centerIn: parent; text: root.camAlert ? root.camAlert.limit : ""; color: "#111111"; font.pixelSize: 19; font.weight: Font.Bold }
            }
            Rectangle {
                width: 46; height: 46; radius: 8
                anchors.verticalCenter: parent.verticalCenter
                color: "#E0443E"
                visible: root.camAlert !== null && !(root.camAlert.limit > 0)
                Rectangle {
                    anchors.centerIn: parent
                    width: 22; height: 22; radius: 11
                    color: "transparent"; border.width: 3; border.color: "#FFFFFF"
                    Rectangle { anchors.centerIn: parent; width: 7; height: 7; radius: 4; color: "#FFFFFF" }
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: !root.camAlert ? "" : (root.camAlert.kind === "tutor" ? qsTr("Speed camera (Tutor)") : (root.camAlert.kind === "redlight" ? qsTr("Traffic light camera") : qsTr("Speed camera")))
                    color: camBanner.over ? "#E0443E" : root.cSubtle
                    font.pixelSize: 15; font.weight: Font.Medium
                }
                Text {
                    text: root.camAlert ? ("tra " + (root.camAlert.dist >= 950 ? (root.camAlert.dist / 1000).toFixed(1) + " km" : Math.max(50, Math.round(root.camAlert.dist / 10) * 10) + " m")) : ""
                    color: camBanner.over ? "#E0443E" : root.cText
                    font.pixelSize: 24; font.weight: Font.DemiBold
                }
            }
        }
    }

    // ── DESTINAZIONE DAL TELEFONO ──
    // The phone sends a link/address (small page opened with the QR); here a "Go / Ignore" card arrives.
    property var phoneDest: null          // {lat, lon, name, address} waiting for confirmation
    property bool phoneQrOpen: false
    property string phoneQrSrc: ""
    property bool phoneNetReady: true

    function pollPhoneDest() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "http://127.0.0.1:9098/phone-dest/pending?lat=" + root.carLat + "&lon=" + root.carLon)
        xhr.timeout = 3000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return
            try {
                var items = JSON.parse(xhr.responseText).items || []
                if (items.length > 0) {
                    var d = items[items.length - 1]
                    root.phoneQrOpen = false
                    // arrived from the phone (Share): navigation starts right away
                    if (d.auto) root.navigateNow(d.lat, d.lon, d.name, d.address)
                    else root.phoneDest = d
                }
            } catch (e) {}
        }
        xhr.send()
    }
    function openPhoneQr() {
        root.phoneQrSrc = ""
        root.phoneQrOpen = true
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "http://127.0.0.1:9098/phone-dest/info")
        xhr.timeout = 3000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var ok = false
            try { ok = JSON.parse(xhr.responseText).ready === true } catch (e) {}
            root.phoneNetReady = ok
            if (ok) root.phoneQrSrc = "http://127.0.0.1:9098/phone-dest/qr.svg?t=" + Date.now()
        }
        xhr.send()
    }
    Timer {
        interval: 2000          // before 600 ms; ntfy delivers in ~1 s anyway
        repeat: true
        running: false          // "destination from the phone" feature not published
        triggeredOnStart: true
        onTriggered: root.pollPhoneDest()
    }

    Rectangle {
        id: phoneCard
        visible: root.phoneDest !== null
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.topPad + Math.round(76 * root.uPx)
        z: 72
        width: Math.round(340 * root.uPx)
        height: Math.round(128 * root.uPx)
        radius: 10
        color: root.cPanelBg
        border.width: 2
        border.color: "#0A84FF"
        MouseArea { anchors.fill: parent }
        Column {
            anchors.fill: parent
            anchors.margins: Math.round(12 * root.uPx)
            spacing: Math.round(4 * root.uPx)
            Text {
                text: qsTr("From phone")
                color: "#0A84FF"
                font.pixelSize: Math.round(12 * root.uPx)
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: root.phoneDest ? root.phoneDest.name : ""
                color: root.cText
                font.pixelSize: Math.round(18 * root.uPx)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.phoneDest ? root.phoneDest.address : ""
                visible: text !== ""
                color: root.cSubtle
                font.pixelSize: Math.round(12 * root.uPx)
                elide: Text.ElideRight
            }
            Item { width: 1; height: Math.round(4 * root.uPx) }
            Row {
                spacing: Math.round(10 * root.uPx)
                Rectangle {
                    width: Math.round(150 * root.uPx); height: Math.round(40 * root.uPx); radius: height / 2
                    color: "#0A84FF"
                    Text { anchors.centerIn: parent; text: qsTr("Go"); color: "white"; font.pixelSize: Math.round(16 * root.uPx); font.weight: Font.DemiBold }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var d = root.phoneDest
                            root.phoneDest = null
                            if (d) root.navigateNow(d.lat, d.lon, d.name, d.address)
                        }
                    }
                }
                Rectangle {
                    width: Math.round(150 * root.uPx); height: Math.round(40 * root.uPx); radius: height / 2
                    color: root.lightTheme ? "#1A000000" : "#26FFFFFF"
                    Text { anchors.centerIn: parent; text: qsTr("Dismiss"); color: root.cText; font.pixelSize: Math.round(16 * root.uPx) }
                    MouseArea { anchors.fill: parent; onClicked: root.phoneDest = null }
                }
            }
        }
    }

    Item {
        id: phoneQrOverlay
        visible: root.phoneQrOpen
        anchors.fill: parent
        z: 90
        MouseArea { anchors.fill: parent; onClicked: root.phoneQrOpen = false }
        Rectangle { anchors.fill: parent; color: "#99000000" }
        Rectangle {
            anchors.centerIn: parent
            width: Math.round(320 * root.uPx)
            height: qrCol.implicitHeight + Math.round(32 * root.uPx)
            radius: 10
            color: root.cPanelBg
            border.width: 1
            border.color: root.lightTheme ? "#22000000" : "#33FFFFFF"
            MouseArea { anchors.fill: parent }
            Column {
                id: qrCol
                anchors.centerIn: parent
                width: parent.width - Math.round(32 * root.uPx)
                spacing: Math.round(10 * root.uPx)
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Send destination from phone")
                    color: root.cText
                    font.pixelSize: Math.round(16 * root.uPx)
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.round(210 * root.uPx); height: width
                    color: "white"; radius: 8
                    Image {
                        anchors.fill: parent; anchors.margins: 6
                        source: root.phoneQrSrc
                        sourceSize.width: 400; sourceSize.height: 400
                        fillMode: Image.PreserveAspectFit
                        cache: false
                    }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: root.cSubtle
                    font.pixelSize: Math.round(12 * root.uPx)
                    text: root.phoneNetReady
                          ? qsTr("Scan with your phone and save the page: the Google Maps link you type or paste there arrives here. To send with «Share», use the same address in HTTP Shortcuts.")
                          : qsTr("The car isn't connected to the internet: as soon as it is, the channel starts by itself.")
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.round(120 * root.uPx); height: Math.round(36 * root.uPx); radius: height / 2
                    color: root.lightTheme ? "#1A000000" : "#26FFFFFF"
                    Text { anchors.centerIn: parent; text: qsTr("Close"); color: root.cText; font.pixelSize: Math.round(14 * root.uPx) }
                    MouseArea { anchors.fill: parent; onClicked: root.phoneQrOpen = false }
                }
            }
        }
    }

    // ── NAVIGATION MANEUVER BANNER ──
    GlassPanel {
        id: maneuverBanner
        anchors.top: parent.top
        anchors.topMargin: searchBarPanel.visible ? (searchBarPanel.y + searchBarPanel.height + root.mapPad) : root.topPad
        Behavior on anchors.topMargin { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        anchors.left: parent.left
        anchors.leftMargin: root.leftInset
        width: root.panelW
        radius: 10
        visible: (Nav.navigating || (root.inPreview && !root.placePreview)) && Nav.instruction !== "" && !root.placeDetailsOpen
        z: 50
        height: Math.min(manCol.y + manCol.implicitHeight + Math.round(12 * root.navK),
                         root.height - upcomingBox.reservedBottom - maneuverBanner.y)

        // Gestures: only on the maneuvers area (not on the trip bar, where End and ••• are)
        Item {
            id: gestureZone
            x: 0; y: 0
            width: parent.width
            height: manCol.y + upcomingBox.y + upcomingBox.height + Math.round(8 * root.navK)
            // Drag down (or tap) the collapsed panel -> opens the list and top-down view.
            // CanTakeOverFromAnything: it takes the grab from the map too (DragHandler of the same type).
            DragHandler {
                id: expandDrag
                target: null
                enabled: Nav.navigating && !root.compactNav && !root.navExpanded
                grabPermissions: PointerHandler.CanTakeOverFromAnything
                dragThreshold: 4
                property bool fired: false
                onActiveChanged: if (active) fired = false
                onTranslationChanged: {
                    if (active && !fired && translation.y > 30) { fired = true; root.setNavExpanded(true) }
                }
            }
            TapHandler {
                enabled: Nav.navigating && !root.compactNav && !root.navExpanded
                onTapped: root.setNavExpanded(true)
            }
        }

        Column {
            id: manCol
            width: parent.width - Math.round(55 * root.navK)
            x: Math.round(30 * root.navK)
            y: Math.round(22 * root.navK)
            spacing: Math.round(34 * root.navK)

            Item {
                width: parent.width
                height: Math.round(60 * root.navK)
                // With the list open: drag up or tap here to collapse it
                DragHandler {
                    target: null
                    enabled: root.navExpanded
                    grabPermissions: PointerHandler.CanTakeOverFromAnything
                    dragThreshold: 4
                    property bool fired: false
                    onActiveChanged: if (active) fired = false
                    onTranslationChanged: {
                        if (active && !fired && translation.y < -30) { fired = true; root.setNavExpanded(false) }
                    }
                }
                TapHandler {
                    enabled: root.navExpanded
                    onTapped: root.setNavExpanded(false)
                }
                TurnIcon {
                    id: bannerIcon
                    x: 0
                    y: Math.round(8 * root.navK)
                    width: Math.round(58 * root.navK)
                    height: width
                    type: Nav.maneuverType
                    modifier: Nav.maneuverModifier
                    color: root.cText
                }
                Text {
                    x: Math.round(66 * root.navK)
                    y: Math.round(2 * root.navK)
                    text: root.fmtDist(Nav.distanceToManeuver)
                    color: root.cText
                    font.pixelSize: Math.round(26 * root.navK)
                    font.weight: Font.Normal
                }
                Text {
                    x: Math.round(66 * root.navK)
                    y: Math.round(41 * root.navK)
                    width: parent.width - x
                    text: Nav.nextStreet !== "" ? Nav.nextStreet : Nav.instruction
                    color: root.cSubtle
                    font.pixelSize: Math.round(16 * root.navK)
                    font.weight: Font.Medium
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }
            }

            // ── Lane guidance: lane arrows, the ones to use highlighted ──
            Item {
                id: laneBox
                width: parent.width
                readonly property var lanes: Nav.laneGuidance
                visible: lanes.length > 0
                height: visible ? 36 : 0
                Row {
                    anchors.centerIn: parent
                    spacing: 0
                    Repeater {
                        model: laneBox.lanes
                        Row {
                            spacing: 0
                            Rectangle {      // thin separator between one lane and the next
                                visible: index > 0
                                width: 1; height: 24
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.cDivider2
                            }
                            Item {
                                width: 34; height: 36
                                TurnIcon {
                                    anchors.centerIn: parent
                                    width: 28; height: 28
                                    modifier: modelData.active && modelData.activeDirection !== ""
                                              ? modelData.activeDirection
                                              : (modelData.directions.length > 0 ? modelData.directions[0] : "straight")
                                    color: root.cText
                                    opacity: modelData.active ? 1.0 : 0.3
                                }
                            }
                        }
                    }
                }
            }

            // ── Lane illustration (junction view): the lane to take in blue ──
            // With the real lane data where Mapbox provides it; otherwise,
            // for exits/forks, a generic 3-lane version.
            JunctionView {
                id: junctionView
                width: parent.width
                lightTheme: root.lightTheme
                readonly property var realLanes: Nav.laneGuidance
                readonly property bool isExit: (Nav.maneuverType === "off ramp" || Nav.maneuverType === "fork")
                                               && Nav.distanceToManeuver < 700
                readonly property var genericLanes: {
                    var m = Nav.maneuverModifier || ""
                    var left = m.indexOf("left") >= 0
                    var mk = function(a, dir) { return { directions: [dir], active: a, activeDirection: a ? dir : "" } }
                    var d = left ? "slight left" : "slight right"
                    return left ? [mk(true, d), mk(false, "straight"), mk(false, "straight")]
                                : [mk(false, "straight"), mk(false, "straight"), mk(true, d)]
                }
                lanes: realLanes.length > 0 ? realLanes : (isExit ? genericLanes : [])
                visible: !root.compactNav && !root.navListOpen && lanes.length > 0
                height: visible ? 170 : 0
            }

            // ── Prossime manovre ──
            // Preview or dragged down: all, scrollable. While driving: only the first row.
            Item {
                id: upcomingBox
                width: parent.width
                clip: true
                visible: height > 0      // also with an app open: the second turn stays under the first
                readonly property var srcList: root.navExpanded ? root.frozenMans : Nav.upcomingManeuvers
                readonly property int total: Math.max(0, srcList.length - 1)
                // space occupied by the rest of the panel (everything except this list)
                readonly property real otherH: {
                    var h = 0, n = 0
                    for (var i = 0; i < manCol.children.length; i++) {
                        var c = manCol.children[i]
                        if (c === upcomingBox || !c.visible) continue
                        h += c.height; n++
                    }
                    return h + n * manCol.spacing
                }
                // at the bottom: dock + (separate blue bar, if present)
                readonly property real reservedBottom: root.dockClearance + root.mapPad
                                                       + (navPanel.visible ? navPanel.height + root.mapPad : 0)
                readonly property real maxH: Math.max(0, root.height - reservedBottom - maneuverBanner.y
                                                       - manCol.y - Math.round(12 * root.navK) - otherH)
                readonly property real rowH: Math.round(40 * root.navK)
                readonly property real rowGap: Math.round(16 * root.navK)
                readonly property real fullH: total * rowH + Math.max(0, total - 1) * rowGap
                readonly property real openH: Math.min(fullH, maxH)
                readonly property real closedH: total > 0 ? rowH : 0
                height: root.navListOpen ? openH : closedH
                Behavior on height { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

                ListView {
                    id: listFlick
                    anchors.fill: parent
                    clip: true
                    spacing: upcomingBox.rowGap
                    interactive: root.navListOpen && contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 0
                    // the 1st entry of upcomingManeuvers is already in the big banner
                    model: upcomingBox.srcList.slice(1)
                    Connections {
                        target: root
                        function onNavListOpenChanged() { if (!root.navListOpen) listFlick.positionViewAtBeginning() }
                    }
                    delegate: Item {
                        width: ListView.view.width
                        height: upcomingBox.rowH
                        TurnIcon {
                            id: upIcon
                            x: 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(34 * root.navK)
                            height: width
                            type: modelData.type
                            modifier: modelData.modifier
                            color: root.cText
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Math.round(66 * root.navK)
                            anchors.right: upDist.left
                            anchors.rightMargin: Math.round(12 * root.navK)
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.street || modelData.instruction || qsTr("Turn")
                            color: root.cSubtle
                            font.pixelSize: Math.round(15 * root.navK)
                            font.weight: Font.Medium
                            maximumLineCount: 1
                            elide: Text.ElideRight
                        }
                        Text {
                            id: upDist
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.fmtDist(modelData.distance)
                            color: root.cSubtle
                            font.pixelSize: Math.round(15 * root.navK)
                            font.weight: Font.Medium
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: root.navListOpen ? Math.round(40 * root.navK) : 0
                clip: true
                opacity: root.navListOpen ? 1 : 0
                Behavior on height { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 250 } }
                // Hidden with an app open in full-screen mode
                // (root.compactNav): only the current turn at the top remains.
                visible: !root.compactNav && height > 0
                Image { sourceSize: Qt.size(width * 2, height * 2);
                    id: destIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 28
                    source: "qrc:/VoltaApp/icons/mn_destination.svg"
                    fillMode: Image.PreserveAspectFit
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: root.cText
                    }
                }
                Text {
                    anchors.left: destIcon.right
                    anchors.leftMargin: 20
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._nextStopName !== "" ? root._nextStopName : qsTr("Destination")   // dl95
                    color: root.cText
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }
            }

            // "Full-screen map" mode WITHOUT an open app (map "at
            // home"): here, at the bottom of the "upcoming directions" panel, the
            // same content that in normal mode sits in the separate
            // "navPanel" panel further below (arrival/remaining time, blue
            // progress bar, "End"/•••-recenter) — merged here because a
            // separate panel at the bottom left always collided with the music
            // player (which in this mode is also all on the left).
            // With an open app (root.compactNav) this also disappears:
            // only the current turn at the top, "no remaining time etc"
            // as requested.
            EtaBlock {
                id: mergedEta
                width: parent.width
                yOff: Math.round(9 * root.navK)
                bleedL: manCol.x
                bleedR: maneuverBanner.width - manCol.x - manCol.width
                visible: false   // the blue bar is now the separate panel at the bottom left (navPanel), in place of the music player
            }
        }

        // Light divider between the current turn and the next (as wide as the whole box)
        Rectangle {
            x: 0
            width: maneuverBanner.width
            y: manCol.y + upcomingBox.y - Math.round(manCol.spacing / 2) + Math.round(8 * root.navK)
            height: 1
            color: root.cDivider2
            visible: upcomingBox.visible && upcomingBox.total > 0
        }
    }

    // ── NAVIGATION BOTTOM PANEL (Blue Track and Red Pointer restored) ──
    // "Full-screen map" mode (root.externalControls): this
    // separate panel is no longer needed — its content (arrival/remaining
    // time/blue bar/End) is now merged directly at the bottom of the
    // "upcoming directions" panel (mergedEta inside manCol, above),
    // because keeping it separate at the bottom left always collided with the music
    // player (also all on the left in this mode). So here it stays
    // visible ONLY in normal mode, in its original position
    // (sempre in basso a sx).
    // from the car panel's map widget: opens the trip bar's three-dots menu
    function openTripMenu() {
        if (!Nav.hasRoute) return
        var e = etaPanel
        e.menuOpen = true
    }

    GlassPanel {
        id: navPanel
        anchors.left: parent.left
        // In full-screen map the blue bar is as wide as the music player (and aligned with it)
        anchors.leftMargin: root.externalControls ? 7 * root.uPx : root.mapPad
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.dockClearance
        width: root.externalControls ? root.navSlotW : root.panelW
        radius: 10
        visible: Nav.hasRoute && !(root.inPreview && root.placePreview)
        z: 45
        // carousel with the player: it slides to the left and fades
        opacity: Math.min(1, (1 - root.navSlotPos) * 1.6)
        enabled: root.navSlotPos < 0.5
        transform: Translate { x: -root.navSlotPos * root.navSlotTravel }
        height: etaPanel.height

        EtaBlock {
            id: etaPanel
            growMenu: true   // dl92
            x: 0; y: 0
            width: parent.width
            // in full-screen map: as tall as the music player (the scale follows the height, texts included)
            k: root.externalControls ? root.navSlotH / 127.3 : root.navK
            padX: Math.round(15 * etaPanel.k)
        }
    }

    GlassPanel {
        id: placeDetailsPanel
        anchors.top: parent.top
        anchors.topMargin: root.topPad
        anchors.left: parent.left
        anchors.leftMargin: root.leftInset
        // Same reason as nearbyPanel above: in "full-screen
        // map" mode more bottom margin is needed (211 instead of 144) so as not to
        // reach into the band occupied by the music player.
        height: Math.min(parent.height - (root.externalControls ? 211 : 144), detailsCol.implicitHeight)
        width: root.panelW
        radius: 10
        visible: root.placeDetailsOpen && root.selectedPlace !== null
        clip: true
        z: 60

        Flickable {
            id: detailsFlick
            anchors.fill: parent
            contentWidth: width
            contentHeight: detailsCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: detailsCol
                width: parent.width
                spacing: 0

                Item {
                    width: parent.width
                    height: 56

                    Item {
                        id: pdBackBtn
                        visible: root.nearbyPanelType !== ""
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 40
                        Image { sourceSize: Qt.size(width * 2, height * 2);
                            id: backIco
                            anchors.centerIn: parent
                            width: 24
                            height: 24
                            source: "qrc:/VoltaApp/icons/chevron-right.svg"
                            visible: false
                        }
                        ColorOverlay {
                            anchors.fill: backIco
                            source: backIco
                            color: root.cText
                            rotation: 180
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.closePlaceDetails()
                        }
                    }

                    Text {
                        anchors.left: pdBackBtn.visible ? pdBackBtn.right : parent.left
                        anchors.leftMargin: pdBackBtn.visible ? 0 : 16
                        anchors.right: pdCloseBtn.left
                        anchors.rightMargin: 8
                        anchors.top: parent.top
                        anchors.topMargin: 16
                        text: root.selectedPlace ? root.selectedPlace.name : ""
                        color: root.cText
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Text {
                        id: pdCloseBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.top: parent.top
                        anchors.topMargin: 16
                        text: "\u2715"
                        color: root.cSubtle
                        font.pixelSize: 18
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -12
                            onClicked: {
                                root.nearbyPanelType = ""
                                root.closePlaceDetails()
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    visible: root.selectedPlace && root.selectedPlace.isBusiness
                    spacing: 4

                    Text {
                        leftPadding: 16
                        visible: root.selectedPlace && root.formatCategory(root.selectedPlace.category) !== ""
                        text: root.selectedPlace ? root.formatCategory(root.selectedPlace.category) : ""
                        color: root.cSubtle
                        font.pixelSize: 13
                    }

                    Text {
                        leftPadding: 16
                        bottomPadding: 8
                        visible: root.selectedPlace && root.selectedPlace.openInfo !== ""
                        text: (root.selectedPlace && root.selectedPlace.openInfo) ? root.selectedPlace.openInfo : ""
                        color: "#1E8E3E"
                        font.pixelSize: 13
                    }

                    Item {
                        width: parent.width
                        height: 62
                        Row {
                            anchors.centerIn: parent
                            spacing: 18

                            Rectangle {
                                width: 44
                                height: 44
                                radius: 8
                                color: root.cIconBadge
                                Image { sourceSize: Qt.size(width * 2, height * 2);
                                    id: bNavIco
                                    anchors.centerIn: parent
                                    width: 22
                                    height: 22
                                    source: "qrc:/VoltaApp/icons/navigation.svg"
                                    visible: false
                                }
                                ColorOverlay {
                                    anchors.fill: bNavIco
                                    source: bNavIco
                                    color: root.cText
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.confirmPlaceDirections()
                                }
                            }
                            Rectangle {
                                width: 44
                                height: 44
                                radius: 8
                                color: root.cIconBadge
                                Image { sourceSize: Qt.size(width * 2, height * 2);
                                    id: bCallIco
                                    anchors.centerIn: parent
                                    width: 20
                                    height: 20
                                    source: "qrc:/VoltaApp/icons/phone.svg"
                                    visible: false
                                }
                                ColorOverlay {
                                    anchors.fill: bCallIco
                                    source: bCallIco
                                    color: (root.selectedPlace && root.selectedPlace.phone !== "") ? root.cText : root.cSubtle
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (root.selectedPlace.phone !== "") Qt.openUrlExternally("tel:" + root.selectedPlace.phone)
                                    }
                                }
                            }
                            Rectangle {
                                width: 44
                                height: 44
                                radius: 8
                                color: root.cIconBadge
                                Image { sourceSize: Qt.size(width * 2, height * 2);
                                    id: bWebIco
                                    anchors.centerIn: parent
                                    width: 20
                                    height: 20
                                    source: "qrc:/VoltaApp/icons/language.svg"
                                    visible: false
                                }
                                ColorOverlay {
                                    anchors.fill: bWebIco
                                    source: bWebIco
                                    color: (root.selectedPlace && root.selectedPlace.website !== "") ? root.cText : root.cSubtle
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (root.selectedPlace.website !== "") Qt.openUrlExternally("https://" + root.selectedPlace.website)
                                    }
                                }
                            }
                            Rectangle {
                                width: 44
                                height: 44
                                radius: 8
                                color: root.cIconBadge
                                Image { sourceSize: Qt.size(width * 2, height * 2);
                                    id: bFavIco
                                    anchors.centerIn: parent
                                    width: 20
                                    height: 20
                                    source: root.selectedPlaceIsFavorite ? "qrc:/VoltaApp/icons/star-full.svg" : "qrc:/VoltaApp/icons/star-empty.svg"
                                    visible: false
                                }
                                ColorOverlay {
                                    anchors.fill: bFavIco
                                    source: bFavIco
                                    color: root.cText
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.togglePlaceFavorite()
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 46
                        Image { sourceSize: Qt.size(width * 2, height * 2);
                            id: pdParkIco
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            height: 24
                            source: "qrc:/VoltaApp/icons/parking-badge.svg"
                            visible: false
                        }
                        ColorOverlay {
                            anchors.fill: pdParkIco
                            source: pdParkIco
                            color: root.cText
                        }
                        Text {
                            anchors.left: pdParkIco.right
                            anchors.leftMargin: 12
                            anchors.right: pdParkChevron.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Parking nearby")
                            color: root.cText
                            font.pixelSize: 14
                        }
                        Image { sourceSize: Qt.size(width * 2, height * 2);
                            id: pdParkChevron
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18
                            height: 18
                            source: "qrc:/VoltaApp/icons/chevron-right.svg"
                            visible: false
                        }
                        ColorOverlay {
                            anchors.fill: pdParkChevron
                            source: pdParkChevron
                            color: root.cSubtle
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (!root.selectedPlace) return
                                var p = root.selectedPlace
                                root.closePlaceDetails()
                                root.openNearbyPanel("parking", p.lat, p.lon)
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 1
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 16
                            height: 1
                            color: root.cDivider2
                        }
                    }

                    Item {
                        width: parent.width
                        height: 56
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.selectedPlace ? root.selectedPlace.address : ""
                            color: root.cSubtle
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                }

                Column {
                    width: parent.width
                    visible: root.selectedPlace && !root.selectedPlace.isBusiness
                    spacing: 12
                    topPadding: 4
                    bottomPadding: 6

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 32
                        spacing: 12
                        Rectangle {
                            width: (parent.width - 12) / 2
                            height: 50
                            radius: 8
                            color: root.cIconBadge
                            Image { sourceSize: Qt.size(width * 2, height * 2);
                                id: pNavIco
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                source: "qrc:/VoltaApp/icons/navigation.svg"
                                visible: false
                            }
                            ColorOverlay {
                                anchors.fill: pNavIco
                                source: pNavIco
                                color: root.cText
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.confirmPlaceDirections()
                            }
                        }
                        Rectangle {
                            width: (parent.width - 12) / 2
                            height: 50
                            radius: 8
                            color: root.cIconBadge
                            Image { sourceSize: Qt.size(width * 2, height * 2);
                                id: pFavIco
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                source: root.selectedPlaceIsFavorite ? "qrc:/VoltaApp/icons/star-full.svg" : "qrc:/VoltaApp/icons/star-empty.svg"
                                visible: false
                            }
                            ColorOverlay {
                                anchors.fill: pFavIco
                                source: pFavIco
                                color: root.cText
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.togglePlaceFavorite()
                            }
                        }
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 32
                        height: 104
                        radius: 8
                        color: root.cIconBadge
                        Column {
                            anchors.fill: parent
                            Item {
                                width: parent.width
                                height: 52
                                Image { sourceSize: Qt.size(width * 2, height * 2);
                                    id: pHomeIco
                                    anchors.left: parent.left
                                    anchors.leftMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 20
                                    height: 20
                                    source: "qrc:/VoltaApp/icons/home.svg"
                                    visible: false
                                }
                                ColorOverlay {
                                    anchors.fill: pHomeIco
                                    source: pHomeIco
                                    color: root.cText
                                }
                                Text {
                                    anchors.left: pHomeIco.right
                                    anchors.leftMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("Set as Home")
                                    color: root.cText
                                    font.pixelSize: 15
                                    font.weight: Font.Medium
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "+"
                                    color: root.cSubtle
                                    font.pixelSize: 22
                                    font.weight: Font.Light
                                }
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    height: 1
                                    color: root.cDivider2
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (!root.selectedPlace) return
                                        root.setHomePlace(root.selectedPlace.lat, root.selectedPlace.lon, root.selectedPlace.address)
                                        root._toastText = qsTr("Home set")
                                        toast.opacity = 1
                                        toastTimer.restart()
                                    }
                                }
                            }
                            Item {
                                width: parent.width
                                height: 52
                                Image { sourceSize: Qt.size(width * 2, height * 2);
                                    id: pWorkIco
                                    anchors.left: parent.left
                                    anchors.leftMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 20
                                    height: 20
                                    source: "qrc:/VoltaApp/icons/work.svg"
                                    visible: false
                                }
                                ColorOverlay {
                                    anchors.fill: pWorkIco
                                    source: pWorkIco
                                    color: root.cText
                                }
                                Text {
                                    anchors.left: pWorkIco.right
                                    anchors.leftMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("Set as Work")
                                    color: root.cText
                                    font.pixelSize: 15
                                    font.weight: Font.Medium
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "+"
                                    color: root.cSubtle
                                    font.pixelSize: 22
                                    font.weight: Font.Light
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (!root.selectedPlace) return
                                        root.setWorkPlace(root.selectedPlace.lat, root.selectedPlace.lon, root.selectedPlace.address)
                                        root._toastText = qsTr("Work set")
                                        toast.opacity = 1
                                        toastTimer.restart()
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 40
                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: root.selectedPlace ? root.selectedPlace.name : ""
                                color: root.cText
                                font.pixelSize: 13
                            }
                            Text {
                                text: root.selectedPlace ? root.selectedPlace.address.replace("\n", ", ") : ""
                                color: root.cSubtle
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                width: 220
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: (root.selectedPlace ? root.distanceKmTo(root.selectedPlace.lat, root.selectedPlace.lon).toFixed(1) : "0") + " km"
                            color: root.cSubtle
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }
    }

    Column {
        // In full-screen map (root.externalControls) the column sits on the left, below the recenter button;
        // in normal mode it stays at the top right.
        x: root.externalControls ? root.mapPad : (parent.width - width - root.mapPad)
        y: root.topPad + root.barH + root.mapPad
        spacing: root.mapPad
        z: 50

        // The compass/recenter button is no longer here (it became
        // "recenterPanel", above together with the search bar): this
        // column now contains only the 5 buttons below.
        GlassPanel {
            width: root.barH
            height: (root.barH * 4) + 3
            radius: 10
            opacity: (root.externalControls || root.toolsVisible) ? 1.0 : 0.0
            enabled: root.externalControls || root.toolsVisible
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

            Column {
                anchors.fill: parent

                Item {
                    width: root.barH
                    height: root.barH
                    Image {
                        id: globeImg
                        anchors.centerIn: parent
                        source: "qrc:/VoltaApp/icons/globo.svg"
                        width: 29.5 * root.fS; height: 29.5 * root.fS
                        sourceSize: Qt.size(width * 2, height * 2)
                        visible: false
                    }
                    ColorOverlay {
                        anchors.fill: globeImg
                        source: globeImg
                        color: root.mapStyle === "satellite" ? root.cSelected : root.cUnselected
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.mapStyle = (root.mapStyle === "satellite" ? "flat" : "satellite")
                        }
                    }
                }

                Rectangle { width: root.barH * 0.75; height: 1; color: root.cDivider2; anchors.horizontalCenter: parent.horizontalCenter }

                Item {
                    width: root.barH
                    height: root.barH
                    Image {
                        id: locImg
                        anchors.centerIn: parent
                        source: "qrc:/VoltaApp/icons/icons_location_dark.svg"
                        width: 29 * root.fS; height: 29 * root.fS
                        sourceSize: Qt.size(width * 2, height * 2)
                        visible: false
                    }
                    ColorOverlay {
                        anchors.fill: locImg
                        source: locImg
                        color: root.poisEnabled ? root.cSelected : root.cUnselected
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.poisEnabled = !root.poisEnabled
                    }
                }

                Rectangle { width: root.barH * 0.75; height: 1; color: root.cDivider2; anchors.horizontalCenter: parent.horizontalCenter }

                Item {
                    width: root.barH
                    height: root.barH
                    Image {
                        id: chargeImg
                        anchors.centerIn: parent
                        source: "qrc:/VoltaApp/icons/icons_charge_dark.svg"
                        width: 30.5 * root.fS; height: 30.5 * root.fS
                        sourceSize: Qt.size(width * 2, height * 2)
                        visible: false
                    }
                    ColorOverlay {
                        anchors.fill: chargeImg
                        source: chargeImg
                        color: root.cUnselected
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.openNearbyPanel("fuel")
                    }
                }

                Rectangle { width: root.barH * 0.75; height: 1; color: root.cDivider2; anchors.horizontalCenter: parent.horizontalCenter }

                Item {
                    width: root.barH
                    height: root.barH
                    Image {
                        id: weatherImg
                        anchors.centerIn: parent
                        source: "qrc:/VoltaApp/icons/icons_weather_dark.svg"
                        width: 25.5 * root.fS; height: 25.5 * root.fS
                        sourceSize: Qt.size(width * 2, height * 2)
                        visible: false
                    }
                    ColorOverlay {
                        anchors.fill: weatherImg
                        source: weatherImg
                        color: root.weatherEnabled ? root.cSelected : root.cUnselected
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.weatherEnabled = !root.weatherEnabled
                    }
                }
            }
        }
    }

    property var poiSearchResults: []
    function poiSearch(q) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var list = JSON.parse(xhr.responseText)
                        if (searchInput.text.trim() === q) root.poiSearchResults = list
                    } catch(e) {}
                } else {
                    root.poiSearchResults = []
                }
            }
        }
        xhr.open("GET", "http://127.0.0.1:9098/poi-search?q=" + encodeURIComponent(q) +
                        "&lat=" + root.carLat + "&lon=" + root.carLon)
        xhr.send()
    }

    readonly property var combinedSearchResults: {
        var out = []
        for (var i = 0; i < root.poiSearchResults.length; i++) {
            var p = root.poiSearchResults[i]
            out.push({
                name: p.name,
                address: p.address,
                lat: p.lat,
                lon: p.lon,
                isBusiness: p.isBusiness !== undefined ? p.isBusiness : true,
                category: p.category || "",
                phone: p.phone || "",
                website: p.website || ""
            })
        }
        return out
    }

    function doSearch() {
        var q = searchInput.text.trim()
        if (q.length < 2) {
            root.poiSearchResults = []
            return
        }
        root.poiSearch(q)
    }

    // The map ignores touches while the on-screen keyboard is up (the first tap is used to close it)
    // and while the finger is pressed on a search panel (otherwise, as soon as the keyboard disappears
    // mid-gesture, the map takes the drag). With the keyboard disabled the active search
    // field does NOT block the map.
    readonly property bool mapMuted: (Qt.inputMethod.visible && KeyboardSettings.keyboardEnabled)
                                     || _dropTap.pressed || _resTap.pressed || root._uiPress   // dl89

    // dl89: true while the finger is pressed starting from a panel above the map
    // (search, recents, results, nearby, place card). Set by the map's PointHandler
    // at the start of the touch, reset on release.
    property bool _uiPress: false
    function _overSearchUi(p) {
        var ps = [searchBarPanel, searchDropdownPanel, searchResultsPanel, nearbyPanel, placeDetailsPanel, editTripPanel]
        for (var i = 0; i < ps.length; i++) {
            var it = ps[i]
            if (!it || !it.visible) continue
            var q = it.mapFromItem(null, p.x, p.y)
            if (q.x >= 0 && q.y >= 0 && q.x <= it.width && q.y <= it.height) return true
        }
        return false
    }

    function focusSearch() {
        searchInput.forceActiveFocus()
    }

    // "Add stop": the search bar opens and the chosen place becomes a stop of the route
    property bool addingStop: false
    // ═══ dl92: modifica percorso ═══
    property bool editTripOpen: false
    property var  editStops: []                 // [{name, address, lat, lon}], the last one is the destination
    property var  _stopAddr: ({})               // known addresses, by lat/lon
    function _stopKey(lat, lon) { return Number(lat).toFixed(4) + "," + Number(lon).toFixed(4) }
    function _rememberAddr(lat, lon, addr) {
        if (!addr) return
        var m = root._stopAddr
        m[root._stopKey(lat, lon)] = addr
        root._stopAddr = m
    }
    function showToast(text) {
        root._toastText = text
        toast.opacity = 1
        toastTimer.restart()
    }
    // a place chosen during the search for a stop
    function commitStopFromSearch(it) {
        root._rememberAddr(it.lat, it.lon, it.address)
        var nm = (it.name && it.name.length) ? it.name : qsTr("Stop")
        if (root.editTripOpen) {
            var s = root.editStops.slice()
            s.push({ name: nm, address: it.address || "", lat: it.lat, lon: it.lon })
            root.editStops = s
        } else {
            Nav.addWaypoint(it.lon, it.lat, nm)
        }
        root.addingStop = false
        searchInput.text = ""
        searchInput.focus = false
        root.poiSearchResults = []
        root.searchDropdownOpen = false
    }
    function cancelAddStop() {
        root.addingStop = false
        searchInput.text = ""
        searchInput.focus = false
        root.poiSearchResults = []
        root.searchDropdownOpen = false
    }
    function openEditTrip() {
        if (!Nav.hasRoute) return
        var st = Nav.stops, s = []
        for (var i = 0; i < st.length; i++)
            s.push({ name: st[i].name, address: root._stopAddr[root._stopKey(st[i].lat, st[i].lon)] || "",
                     lat: st[i].lat, lon: st[i].lon })
        root.editStops = s
        root.addingStop = false
        searchInput.text = ""
        searchInput.focus = false
        root.searchDropdownOpen = false
        root.poiSearchResults = []
        root.closePlaceDetails()
        root.editTripOpen = true
    }
    function closeEditTrip(apply) {
        if (apply && root.editStops.length > 0) {
            var cur = Nav.stops, same = (cur.length === root.editStops.length)
            for (var i = 0; same && i < cur.length; i++)
                if (Math.abs(cur[i].lat - root.editStops[i].lat) > 1e-6
                    || Math.abs(cur[i].lon - root.editStops[i].lon) > 1e-6) same = false
            if (!same) {
                for (var j = 0; j < root.editStops.length; j++)
                    root._rememberAddr(root.editStops[j].lat, root.editStops[j].lon, root.editStops[j].address)
                Nav.setStops(root.editStops)      // recalculates and shows the preview
            }
        }
        root.editTripOpen = false
        root.addingStop = false
    }
    function removeEditStop(i) {
        if (root.editStops.length <= 1) return
        var s = root.editStops.slice()
        s.splice(i, 1)
        root.editStops = s
    }
    function moveEditStop(from, to) {
        var s = root.editStops.slice()
        var it = s.splice(from, 1)[0]
        s.splice(to, 0, it)
        root.editStops = s
    }
    function beginAddStop() {
        if (!Nav.navigating && !Nav.hasRoute) return
        if (root.editTripOpen ? root.editStops.length >= Nav.maxStops : Nav.waypointCount >= Nav.maxStops - 1) {
            root.showToast(qsTr("You can add at most two stops"))
            return
        }
        root.addingStop = true
        searchInput.text = ""
        searchInput.forceActiveFocus()
    }

    GlassPanel {
        id: locationBox
        visible: root.gpsReceived && (root.currentStreet !== "" || root.currentCity !== "")
        // Full-screen map: at the bottom center, between the blue bar (left) and the music player (right);
        // normal mode: at the bottom right as always. numeric x/y (no alternating anchors).
        x: root.externalControls ? (parent.width - width) / 2 : (parent.width - width - 16)
        y: parent.height - height - (root.externalControls ? root.dockClearance + 4 : 88)
        z: 50
        radius: 10
        width: locationBoxCol.width + 22
        height: locationBoxCol.height + 14

        Column {
            id: locationBoxCol
            anchors.centerIn: parent
            spacing: 2

            Text {
                text: root.currentStreet
                color: root.lightTheme ? "#171717" : "#F0F0F0"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 240)
            }
            Text {
                text: root.currentCity
                color: root.lightTheme ? "#5A5A5C" : "#A2A3A5"
                font.pixelSize: 11
                font.weight: Font.Medium
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 240)
            }
        }
    }

    // ══════════ MARS (Toybox) — covers the map and panels ══════════
    Loader {
        anchors.fill: parent
        z: 100000
        active: root.marsMode
        visible: active
        sourceComponent: MarsMap {
            carLat: root.carLat
            carLon: root.carLon
            carBearing: root.bearingRot
            lightTheme: root.lightTheme
            interactive: !root.mapLocked
        }
    }

}
// dl93
// dl94
// dl95
