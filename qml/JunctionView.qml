import QtQuick

// Illustration of the lane to take ("junction view" style):
// road in perspective with the lanes of the next maneuver; the ones to use
// are blue with a white arrow and, if exiting right/left, they
// split from the carriageway and curve toward that side.
//
// lanes: list of { directions: [...], active: bool, activeDirection: "..." }
Item {
    id: jv
    property var lanes: []
    property bool lightTheme: false
    implicitHeight: 170

    // colori
    readonly property color skyTop:    lightTheme ? "#9EC7EE" : "#16263A"
    readonly property color skyBottom: lightTheme ? "#DCEBF7" : "#2A4058"
    readonly property color grass:     lightTheme ? "#A9C99A" : "#2B4331"
    readonly property color asphalt:   lightTheme ? "#3B3E45" : "#34373E"
    readonly property color pathBlue:  "#1E7BFF"

    onLanesChanged: cv.requestPaint()
    onLightThemeChanged: cv.requestPaint()
    onWidthChanged: cv.requestPaint()
    onHeightChanged: cv.requestPaint()

    function sideOf(dir) {
        if (!dir) return 0
        if (dir.indexOf("right") >= 0) return 1
        if (dir.indexOf("left") >= 0 || dir === "uturn") return -1
        return 0
    }

    Canvas {
        id: cv
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            var ctx = getContext("2d")
            var W = width, H = height
            ctx.reset()
            if (W < 10 || H < 10) return

            var lanes = jv.lanes || []
            var N = lanes.length
            var hor = H * 0.24                      // linea d'orizzonte

            // ── background: sky + meadow, cut with rounded corners ──
            ctx.save()
            var r = 12
            ctx.beginPath()
            ctx.moveTo(r, 0); ctx.lineTo(W - r, 0); ctx.quadraticCurveTo(W, 0, W, r)
            ctx.lineTo(W, H - r); ctx.quadraticCurveTo(W, H, W - r, H)
            ctx.lineTo(r, H); ctx.quadraticCurveTo(0, H, 0, H - r)
            ctx.lineTo(0, r); ctx.quadraticCurveTo(0, 0, r, 0)
            ctx.closePath()
            ctx.clip()
            var g = ctx.createLinearGradient(0, 0, 0, hor + 4)
            g.addColorStop(0, jv.skyTop); g.addColorStop(1, jv.skyBottom)
            ctx.fillStyle = g
            ctx.fillRect(0, 0, W, hor + 4)
            ctx.fillStyle = jv.grass
            ctx.fillRect(0, hor, W, H - hor)
            if (N === 0) { ctx.restore(); return }

            // ── geometria ──
            var cx = W / 2
            var lw = Math.min(W * 0.92 / Math.max(N, 1), 78)   // larghezza corsia a z=1 (px)
            var Hh = H - hor
            function px(X, z) { return cx + X * lw / z }
            function py(z)    { return hor + Hh / z }

            // exit side: from the first active lane
            var side = 0
            for (var i = 0; i < N; i++) {
                if (lanes[i].active) {
                    var d = lanes[i].activeDirection || (lanes[i].directions.length > 0 ? lanes[i].directions[0] : "")
                    side = jv.sideOf(d)
                    break
                }
            }
            function bend(z) {
                var u = Math.max(0, z - 1.5)
                return 0.075 * u * u
            }
            // X of a point of lane i (offset u inside the lane, 0..1) at depth z
            function laneX(i, u, z) {
                var X = (i + u - N / 2)
                if (side !== 0 && lanes[i].active) X += side * bend(z)
                return X
            }
            var ZMAX = 26
            var STEPS = 44
            function zAt(k) {                       // denser sampling nearby
                var t = k / STEPS
                return 1 + (ZMAX - 1) * t * t
            }

            // polygon between two edges (u0..u1 inside lane i) for z in [za, zb]
            function band(i, u0, u1, za, zb) {
                var pts = []
                var n = Math.max(2, Math.round(STEPS * (zb - za) / (ZMAX - 1)))
                var k
                for (k = 0; k <= n; k++) {
                    var z = za + (zb - za) * k / n
                    pts.push([px(laneX(i, u0, z), z), py(z)])
                }
                for (k = n; k >= 0; k--) {
                    var z2 = za + (zb - za) * k / n
                    pts.push([px(laneX(i, u1, z2), z2), py(z2)])
                }
                return pts
            }
            function fillPoly(pts, color) {
                ctx.beginPath()
                ctx.moveTo(pts[0][0], pts[0][1])
                for (var k = 1; k < pts.length; k++) ctx.lineTo(pts[k][0], pts[k][1])
                ctx.closePath()
                ctx.fillStyle = color
                ctx.fill()
            }

            // ── asphalt, lane by lane (active ones in blue) ──
            // first the "straight" lanes, then the ones that split off (on top)
            var order = []
            for (i = 0; i < N; i++) if (!(side !== 0 && lanes[i].active)) order.push(i)
            for (i = 0; i < N; i++) if (side !== 0 && lanes[i].active) order.push(i)
            for (var oi = 0; oi < order.length; oi++) {
                i = order[oi]
                var z0 = 1, z1 = ZMAX
                fillPoly(band(i, 0, 1, z0, z1), lanes[i].active ? jv.pathBlue : jv.asphalt)
            }

            // ── segnaletica ──
            var white = "rgba(255,255,255,0.92)"
            var hw = 0.035
            function line(i, u, za, zb, color) {
                fillPoly(band(i, u - hw, u + hw, za, zb), color)
            }
            for (i = 0; i < N; i++) {
                var exitI = side !== 0 && lanes[i].active
                // left edge: solid if it is the edge of the carriageway or of a different group
                var leftSolid  = (i === 0) || (exitI !== (side !== 0 && lanes[i - 1].active))
                var rightSolid = (i === N - 1) || (exitI !== (side !== 0 && lanes[i + 1].active))
                if (leftSolid) line(i, 0.02, 1, ZMAX, white)
                if (rightSolid) line(i, 0.98, 1, ZMAX, white)
                if (!rightSolid) {          // dashes between lanes of the same group
                    for (var zz = 1.0; zz < ZMAX; zz += 1.7) line(i, 1.0, zz, Math.min(zz + 0.8, ZMAX), white)
                }
            }

            // ── frecce bianche sulle corsie attive ──
            function arrow(i) {
                var dir = lanes[i].activeDirection || (lanes[i].directions.length > 0 ? lanes[i].directions[0] : "straight")
                var sd = jv.sideOf(dir)
                // lane center; the arrow follows the curve only if it is an exit lane
                function ax(z) { return laneX(i, 0.5, z) }
                var zs = 1.25, zh = 3.1, zt = 4.3
                var left = [], right = []
                var n = 6, k
                for (k = 0; k <= n; k++) {
                    var z = zs + (zh - zs) * k / n
                    left.push([px(ax(z) - 0.085, z), py(z)])
                    right.push([px(ax(z) + 0.085, z), py(z)])
                }
                var pts = left.slice()
                pts.push([px(ax(zh) - 0.30, zh), py(zh)])
                pts.push([px(ax(zt), zt), py(zt)])
                pts.push([px(ax(zh) + 0.30, zh), py(zh)])
                for (k = right.length - 1; k >= 0; k--) pts.push(right[k])
                // ombra
                ctx.save()
                ctx.translate(2, 3)
                fillPoly(pts, "rgba(0,0,0,0.28)")
                ctx.restore()
                fillPoly(pts, "#FFFFFF")
            }
            for (i = 0; i < N; i++) if (lanes[i].active) arrow(i)
            ctx.restore()
        }
    }
}
