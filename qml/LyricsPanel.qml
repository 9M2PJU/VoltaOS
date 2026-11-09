import QtQuick
import QtQuick.Effects

// SYNCED LYRICS — panel on the right of the music apps, BitChord /
// Apple Music style: the line being sung is big and white, the others are
// gray and blurred as they get further away; the text scrolls by itself.
//
// Sources (like BitChord, all queried together, the first in the list that has a text wins
// a tempo e credibile): lrc.red › BiniLyrics › BetterLyrics › BetterLyrics Portato › LyricsPlus ›
// Unison › KuGou › LRCLIB. No key, no account.
// Better no lyrics than wrong lyrics: every answer goes through a check (title, version,
// artist, duration, last line within the end of the track) before being accepted.
// If none has timed lyrics but some have plain ones, they are shown static and without highlighting.
//
// Background: the cover's main color, faded from top to bottom (Apple Music / Spotify).
// The hosting app only passes title, artist, cover, duration and position.
Item {
    id: lp
    clip: true

    // ── Ingressi ─────────────────────────────────────────────────────────
    property bool   active: false          // lyrics are only downloaded if visible
    property string title: ""
    property string artist: ""
    property string cover: ""            // cover url (colors the background)
    property real   durationMs: 0
    property real   positionMs: 0
    property bool   playing: false
    property bool   lightTheme: false
    property color  bgColor: lightTheme ? "#FFFFFF" : "#171717"
    // Timing tweak: positive = the lyrics arrive earlier.
    property int    syncOffsetMs: 0

    signal seekRequested(real ms)
    signal closeRequested()

    // ── Stato ────────────────────────────────────────────────────────────
    property string phase: "idle"          // idle | loading | ok | plain | none
    property var    lines: []              // [{ t: ms, text: "..." }]
    property string plainText: ""
    property string sourceName: ""
    property int    cur: -1

    // With the cover the background is colored and dark: text always white.
    readonly property bool  colored: lp.tinted
    readonly property color fgOn:  colored ? "#FFFFFF" : (lightTheme ? "#111111" : "#FFFFFF")
    readonly property color fgOff: colored ? "#FFFFFF" : (lightTheme ? "#8E8E8E" : "#7A7A7A")
    readonly property real  fs:    Math.max(24, Math.min(46, width * 0.082))
    readonly property real  padX:  Math.round(width * 0.075)
    readonly property int   leadMs: 150    // the line lights up a moment earlier

    // ── Cover's main color ────────────────────────────────
    property color tintTop: "#000000"
    property color tintBottom: "#000000"
    property bool  tinted: false
    Behavior on tintTop    { ColorAnimation { duration: 600 } }
    Behavior on tintBottom { ColorAnimation { duration: 600 } }

    onCoverChanged: {
        lp.tinted = false
        if (lp.cover !== "") _cv.loadImage(lp.cover)
    }

    // Small off-screen canvas: reads the cover's pixels (32x32) to find the dominant color.
    Canvas {
        id: _cv
        width: 32; height: 32; opacity: 0
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate
        onImageLoaded: requestPaint()
        onPaint: {
            if (lp.cover === "" || !isImageLoaded(lp.cover)) return
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, 32, 32)
            ctx.drawImage(lp.cover, 0, 0, 32, 32)
            lp.applyTint(ctx.getImageData(0, 0, 32, 32).data)
        }
    }
    Component.onCompleted: if (lp.cover !== "") _cv.loadImage(lp.cover)

    // Most "present" color of the cover: vivid colors count more, black/white/grays almost nothing.
    function dominant(d) {
        var bins = {}, best = null, bestW = 0
        for (var i = 0; i + 3 < d.length; i += 4) {
            var r = d[i], g = d[i + 1], b = d[i + 2], a = d[i + 3]
            if (a < 200) continue
            var mx = Math.max(r, g, b), mn = Math.min(r, g, b)
            var v = mx / 255, sat = mx === 0 ? 0 : (mx - mn) / mx
            var w = 0.25 + sat
            if (v < 0.16) w *= 0.05
            if (sat < 0.12 && v > 0.9) w *= 0.15
            var k = ((r >> 5) << 6) | ((g >> 5) << 3) | (b >> 5)
            var o = bins[k]
            if (!o) o = bins[k] = { w: 0, n: 0, r: 0, g: 0, b: 0 }
            o.w += w; o.n++; o.r += r; o.g += g; o.b += b
            if (o.w > bestW) { bestW = o.w; best = o }
        }
        if (!best) return null
        return [best.r / best.n, best.g / best.n, best.b / best.n]
    }
    function rgb2hsl(r, g, b) {
        r /= 255; g /= 255; b /= 255
        var mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, h = 0, s = 0
        if (mx !== mn) {
            var dd = mx - mn
            s = l > 0.5 ? dd / (2 - mx - mn) : dd / (mx + mn)
            if (mx === r) h = (g - b) / dd + (g < b ? 6 : 0)
            else if (mx === g) h = (b - r) / dd + 2
            else h = (r - g) / dd + 4
            h /= 6
        }
        return [h, s, l]
    }
    function applyTint(data) {
        var c = lp.dominant(data)
        if (!c) { lp.tinted = false; return }
        var hsl = lp.rgb2hsl(c[0], c[1], c[2])
        var h = hsl[0], s = Math.min(1, hsl[1] * 1.08), l = hsl[2]
        // dark enough that white text is always readable
        var lt = Math.max(0.22, Math.min(0.36, l))
        lp.tintTop = Qt.hsla(h, s, Math.min(0.46, lt + 0.05), 1)
        lp.tintBottom = Qt.hsla(h, s * 0.9, lt * 0.52, 1)
        lp.tinted = true
    }

    // ── Cache e richieste ────────────────────────────────────────────────
    property var    _cache: ({})
    property int    _req: 0
    property string _loadedKey: ""
    property var    _abort: null
    readonly property string key: lp.title + "|" + lp.artist + "|" + Math.round(lp.durationMs / 1000)

    onActiveChanged: if (active) _debounce.restart()
    onKeyChanged: if (active) _debounce.restart()

    Timer { id: _debounce; interval: 500; onTriggered: lp.refresh() }
    Timer { id: _dog; interval: 14000; onTriggered: if (lp._abort) lp._abort() }

    function refresh() {
        if (!lp.active || lp.title === "") return
        var k = lp.key
        if (k === lp._loadedKey) return
        lp._loadedKey = k
        var id = ++lp._req
        lp.lines = []; lp.plainText = ""; lp.sourceName = ""; lp.cur = -1
        var c = lp._cache[k]
        if (c) { lp._apply(c); return }
        lp.phase = "loading"
        lp._run(id, k)
    }

    function _apply(r) {
        lp.sourceName = r.source || ""
        if (r.lines && r.lines.length) { lp.lines = r.lines; lp.phase = "ok"; lp._needFollow = true }
        else if (r.plain) { lp.plainText = r.plain; lp.phase = "plain" }
        else lp.phase = "none"
    }

    // ── Name cleanup (like BitChord does: removes "feat.", "Official Video"…) ──
    function cleanTitle(s) {
        var t = String(s || "")
        t = t.replace(/\s*[\(\[]\s*(feat|ft|featuring|with)\b[^\)\]]*[\)\]]/ig, " ")
        t = t.replace(/\s+(feat|ft|featuring)\.?\s+.*$/i, "")
        t = t.replace(/\s*[\(\[]\s*(official\s*)?(music\s*)?(video|audio|visuali[sz]er|lyrics?\s*video|lyrics?|m\/?v|hd|hq|4k|full\s*song)\s*[\)\]]/ig, " ")
        t = t.replace(/\s*[\(\[]\s*official\s*[\)\]]/ig, " ")
        t = t.replace(/\s+/g, " ").trim().replace(/[,\-–—]+$/, "").trim()
        return t !== "" ? t : String(s || "").trim()
    }
    function cleanArtist(s) {
        var a = String(s || "").replace(/\s*-\s*Topic$/i, "")
        a = a.split(" • ")[0].replace(/^\s*🎵\s*/, "").trim()
        return a
    }
    function firstArtist(s) {
        return cleanArtist(s).split(/\s*(?:,|&|;|\sfeat\.?\s|\sft\.?\s|\sx\s|\/)\s*/i)[0].trim()
    }
    function stripParen(s) {
        var r = String(s || "").replace(/[\(（].*?[\)）]/g, "").trim()
        return r !== "" ? r : String(s || "")
    }
    function enc(s) { return encodeURIComponent(s) }

    // ── Name comparison: it avoids taking the lyrics of another song / version ──
    function norm(v) {
        var t = String(v || "")
        try { t = t.normalize("NFD") } catch (e) {}
        return t.replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9\u0080-￿]+/g, " ").trim()
    }
    // "Song (Live) - 2011 Remaster" -> "song"
    function coreOf(v) {
        var t = String(v || "").replace(/[\(\[][^\)\]]*[\)\]]/g, " ").split(" - ")[0]
        var n = lp.norm(t)
        return n !== "" ? n : lp.norm(v)
    }
    readonly property var versionWords: ["live", "remix", "remixed", "mix", "acoustic", "unplugged", "instrumental",
        "karaoke", "cappella", "acapella", "demo", "edit", "version", "cover", "sped", "slowed", "reverb", "nightcore",
        "lofi", "orchestral", "extended"]
    // words that make a recording different (live, remix...): "Remastered" does not count
    function versionOf(v) {
        var s = String(v || ""), extra = ""
        var re = /[\(\[][^\)\]]*[\)\]]/g, m
        while ((m = re.exec(s)) !== null) extra += " " + m[0]
        var i = s.indexOf(" - ")
        if (i >= 0) extra += " " + s.substring(i + 3)
        var out = [], ws = lp.norm(extra).split(" ")
        for (var k = 0; k < ws.length; k++) if (lp.versionWords.indexOf(ws[k]) >= 0 && out.indexOf(ws[k]) < 0) out.push(ws[k])
        return out.sort().join(",")
    }
    function artistsOf(v) {
        var parts = String(v || "").split(/\s*(?:,|&|;|\/|\s+and\s+|\s+x\s+|\s+with\s+|\s+feat\.?\s+|\s+ft\.?\s+)\s*/i), out = []
        for (var i = 0; i < parts.length; i++) { var n = lp.norm(parts[i]); if (n !== "") out.push(n) }
        return out
    }
    function artistsOverlap(a, b) {
        var A = lp.artistsOf(a), B = lp.artistsOf(b)
        if (!A.length || !B.length) return true
        for (var i = 0; i < A.length; i++) if (B.indexOf(A[i]) >= 0) return true
        return false
    }
    // same track: same title (without parentheses), same version words, at least one artist in common
    function matches(hitTitle, hitArtist, title, artist) {
        if (!hitTitle) return false
        return lp.coreOf(hitTitle) === lp.coreOf(title) && lp.versionOf(hitTitle) === lp.versionOf(title)
               && lp.artistsOverlap(hitArtist, artist)
    }
    // more lenient (KuGou: names are often transliterated): same title, or common artist and one title inside the other
    function matchesLoose(hitTitle, hitArtist, title, artist) {
        if (!hitTitle) return false
        var a = lp.coreOf(hitTitle), b = lp.coreOf(title)
        if (a === b) return lp.versionOf(hitTitle) === lp.versionOf(title)
        return lp.artistsOf(hitArtist).length > 0 && lp.artistsOverlap(hitArtist, artist) && a !== "" && b !== ""
               && (a.indexOf(b) >= 0 || b.indexOf(a) >= 0) && lp.versionOf(hitTitle) === lp.versionOf(title)
    }
    // Final check on any timed lyrics: enough lines, and the end of the text matches the end of the track
    function sane(lines, secs, name) {
        if (!lines || !lines.length) return null
        var n = 0, last = 0
        for (var i = 0; i < lines.length; i++) if (lines[i].text !== "") { n++; last = lines[i].t }
        var why = ""
        if (n < 4) why = qsTr("few lines (") + n + ")"
        else if (secs > 0 && last > secs * 1000 + 12000) why = qsTr("ends after the track (") + Math.round(last / 1000) + qsTr("s on ") + secs + "s)"
        else if (secs > 0 && last < secs * 1000 * 0.4) why = qsTr("ends too early (") + Math.round(last / 1000) + qsTr("s on ") + secs + "s)"
        if (why !== "") { console.log("[testi] scartato " + (name || "?") + ": " + why); return null }
        return lines
    }

    // ── HTTP ─────────────────────────────────────────────────────────────
    property var _mock: null                 // tests only: function(url, cb)
    function httpGet(url, cb, timeoutMs) {
        if (lp._mock) { lp._mock(url, cb); return }
        var done = false
        var x = new XMLHttpRequest()
        x.timeout = timeoutMs || 6000
        x.onreadystatechange = function() {
            if (x.readyState !== 4 || done) return
            done = true
            var st = x.status, tx = ""
            try { tx = x.responseText } catch (e) { tx = "" }
            try { cb(st, tx) } catch (e2) { console.log("[lyrics] error:", e2) }
        }
        try { x.open("GET", url); x.setRequestHeader("Accept", "application/json"); x.send() }
        catch (e3) { if (!done) { done = true; try { cb(0, "") } catch (e4) {} } }
    }
    function safeJson(tx) { try { return JSON.parse(tx) } catch (e) { return null } }

    // ── Reading the formats ──────────────────────────────────────
    // Sorts, removes double gaps and adds an initial gap if the intro is long.
    function normalize(arr) {
        arr.sort(function(a, b) { return a.t - b.t })
        var out = [], any = false
        for (var i = 0; i < arr.length; i++) {
            var it = arr[i]
            if (it.text === "") {
                if (out.length && out[out.length - 1].text === "") continue
            } else any = true
            out.push(it)
        }
        if (!any) return null
        if (out[0].text !== "" && out[0].t >= 8000) out.unshift({ t: 0, text: "" })
        return out
    }

    // "[mm:ss.xx] text" (also several times on the same line, and <mm:ss.xx> per word)
    function parseLrc(lrc) {
        var out = [], rows = String(lrc || "").split(/\r?\n/)
        var re = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i], stamps = [], m, last = 0
            re.lastIndex = 0
            while ((m = re.exec(row)) !== null) {
                var f = 0
                if (m[3]) f = parseInt(m[3], 10) * (m[3].length === 1 ? 100 : (m[3].length === 2 ? 10 : 1))
                stamps.push(parseInt(m[1], 10) * 60000 + parseInt(m[2], 10) * 1000 + f)
                last = re.lastIndex
            }
            if (!stamps.length) continue
            var text = row.substring(last).replace(/<\d+:\d+(?:[.:]\d+)?>/g, "").replace(/\s+/g, " ").trim()
            for (var j = 0; j < stamps.length; j++) out.push({ t: stamps[j], text: text })
        }
        return lp.normalize(out)
    }

    // Apple Music TTML: one <p begin="..."> per line, with the syllables in <span>.
    function parseTime(s) {
        if (!s) return NaN
        s = String(s).trim()
        if (/ms$/.test(s)) return parseFloat(s)
        s = s.replace(/s$/, "")
        var p = s.split(":"), v = 0
        for (var i = 0; i < p.length; i++) v = v * 60 + parseFloat(p[i])
        return v * 1000
    }
    function decodeEntities(s) {
        return s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"")
                .replace(/&apos;|&#39;/g, "'")
                .replace(/&#(\d+);/g, function(_, n) { return String.fromCharCode(parseInt(n, 10)) })
                .replace(/&amp;/g, "&")
    }
    // Removes the <span>s of translation, transliteration and background vocals.
    function stripRoleSpans(inner) {
        var re = /<span\b[^>]*ttm:role="x-(?:bg|translation|roman)"[^>]*>/ig, m
        while ((m = re.exec(inner)) !== null) {
            var depth = 1, tag = /<(\/?)span\b[^>]*>/ig, t
            tag.lastIndex = re.lastIndex
            while (depth > 0 && (t = tag.exec(inner)) !== null) {
                if (t[1]) depth--
                else if (!/\/>$/.test(t[0])) depth++
            }
            var end = depth === 0 ? tag.lastIndex : inner.length
            inner = inner.substring(0, m.index) + inner.substring(end)
            re.lastIndex = m.index
        }
        return inner
    }
    function parseTtml(x) {
        var out = [], re = /<p\b([^>]*)>([\s\S]*?)<\/p>/ig, m
        while ((m = re.exec(x)) !== null) {
            var b = /\bbegin="([^"]+)"/.exec(m[1])
            if (!b) continue
            var t = lp.parseTime(b[1])
            if (isNaN(t)) continue
            var inner = lp.stripRoleSpans(m[2])
            var text = lp.decodeEntities(inner.replace(/<br\s*\/?>/ig, " ").replace(/<[^>]+>/g, "")).replace(/\s+/g, " ").trim()
            out.push({ t: t, text: text })
        }
        return lp.normalize(out)
    }

    // Answer from an "envelope" provider: JSON containing TTML/LRC, or plain text.
    function parseProvider(raw) {
        var s = String(raw || "").replace(/^﻿/, "").trim()
        if (s === "") return null
        var v = s
        for (var n = 0; n < 3; n++) {
            var j = lp.safeJson(v)
            if (j === null || typeof j === "number" || typeof j === "boolean") break
            if (typeof j === "string") { v = j.trim(); continue }
            var keys = ["ttml", "ttmlContent", "lyrics", "lrc", "content", "syncedLyrics", "data", "result"]
            var nx = null
            for (var k = 0; k < keys.length && nx === null; k++) {
                var c = j[keys[k]]
                if (typeof c === "string" && c.trim() !== "") nx = c.trim()
                else if (c && typeof c === "object") nx = JSON.stringify(c)
            }
            if (nx === null) return null
            v = nx
        }
        if (/&lt;tt/i.test(v)) v = lp.decodeEntities(v)
        if (/<tt[\s>]/i.test(v) || /w3\.org\/ns\/ttml/i.test(v)) return lp.parseTtml(v)
        return lp.parseLrc(v)
    }

    // Base64 → UTF-8 text (done by hand: it does not depend on how Qt.atob handles bytes)
    function b64Utf8(b64) {
        var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        var bytes = [], buf = 0, bits = 0
        for (var i = 0; i < b64.length; i++) {
            var c = b64.charAt(i)
            if (c === "=") break
            var v = chars.indexOf(c)
            if (v < 0) continue
            buf = (buf << 6) | v; bits += 6
            if (bits >= 8) { bits -= 8; bytes.push((buf >> bits) & 255) }
        }
        var out = "", p = 0
        while (p < bytes.length) {
            var b = bytes[p++]
            if (b < 128) out += String.fromCharCode(b)
            else if (b >= 192 && b < 224 && p < bytes.length) out += String.fromCharCode(((b & 31) << 6) | (bytes[p++] & 63))
            else if (b >= 224 && b < 240 && p + 1 < bytes.length) { var b2 = bytes[p++], b3 = bytes[p++]; out += String.fromCharCode(((b & 15) << 12) | ((b2 & 63) << 6) | (b3 & 63)) }
            else if (b >= 240 && p + 2 < bytes.length) {
                var c2 = bytes[p++], c3 = bytes[p++], c4 = bytes[p++]
                var cp = ((b & 7) << 18) | ((c2 & 63) << 12) | ((c3 & 63) << 6) | (c4 & 63)
                cp -= 0x10000; out += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 1023))
            }
        }
        return out
    }

    // ── Fonte 1: LRCLIB ──────────────────────────────────────────────────
    function srcLrclib(title, artist, secs, cb) {      // cb(lines|null, plain|null)
        var base = "https://lrclib.net/api/"
        var fa = lp.firstArtist(artist)
        function pickSearch(arr) {
            if (!arr || !arr.length) return { lines: null, plain: null }
            var best = null, bestD = 1e9, plain = null
            for (var i = 0; i < arr.length; i++) {
                var h = arr[i]
                if (!h) continue
                if (!lp.matches(h.trackName || h.name, h.artistName, title, artist)) continue     // another track or another version
                var d = (secs > 0 && h.duration > 0) ? Math.abs(h.duration - secs) : 0
                if (h.syncedLyrics && String(h.syncedLyrics).trim() !== "" && d <= 6 && d < bestD) { best = h; bestD = d }
                if (!plain && h.plainLyrics && d <= 6) plain = h.plainLyrics
            }
            var L = best ? lp.parseLrc(best.syncedLyrics) : null
            return { lines: L, plain: plain }
        }
        var q1 = "track_name=" + lp.enc(title) + "&artist_name=" + lp.enc(artist)
        lp.httpGet(base + "get?" + q1 + (secs > 0 ? "&duration=" + secs : ""), function(st, tx) {
            var d = lp.safeJson(tx), plain = null
            if (st === 200 && d) {
                if (d.syncedLyrics && String(d.syncedLyrics).trim() !== "") {
                    var L = lp.parseLrc(d.syncedLyrics)
                    if (L) { cb(L, null); return }
                }
                if (d.plainLyrics) plain = d.plainLyrics
            }
            lp.httpGet(base + "search?" + q1, function(st2, tx2) {
                var r = pickSearch(st2 === 200 ? lp.safeJson(tx2) : null)
                if (r.lines) { cb(r.lines, null); return }
                lp.httpGet(base + "search?q=" + lp.enc(fa + " " + title), function(st3, tx3) {
                    var r3 = pickSearch(st3 === 200 ? lp.safeJson(tx3) : null)
                    cb(r3.lines, r3.lines ? null : (plain || r.plain || r3.plain))
                })
            })
        })
    }

    // ── Source 2: BetterLyrics (Apple Music timings) ─────────────────────
    function srcBetter(title, artist, secs, cb) {
        var url = "https://lyrics-api.boidu.dev/getLyrics?s=" + lp.enc(title) + "&a=" + lp.enc(artist)
                  + (secs > 0 ? "&d=" + secs : "")
        lp.httpGet(url, function(st, tx) {
            if (st !== 200) { cb(null); return }
            cb(lp.parseProvider(tx))
        })
    }

    // ── Fonte 3: KuGou ───────────────────────────────────────────────────
    function kugouStripCredits(lrc) {
        var ls = String(lrc).split(/\r?\n/).filter(function(l) { return /^\[\d{2}:\d{2}\.\d{2,3}\]/.test(l) })
        if (!ls.length) return ""
        var credit = /^.+\][^\[]+[:：].+$/
        var headCut = 0
        for (var i = Math.min(30, Math.floor(ls.length / 2)); i >= 0; i--) if (credit.test(ls[i])) { headCut = i + 1; break }
        var body = ls.slice(headCut), tailCut = 0
        for (var j = 0; j <= Math.min(30, Math.floor(body.length / 2)); j++)
            if (credit.test(body[body.length - 1 - j])) { tailCut = j + 1; break }
        return body.slice(0, body.length - tailCut).join("\n")
    }
    function srcKugou(title, artist, secs, cb) {
        var kw = lp.stripParen(title) + " - " + lp.stripParen(artist)
        function download(c) {
            lp.httpGet("https://lyrics.kugou.com/download?fmt=lrc&charset=utf8&client=pc&ver=1&id=" + lp.enc(c.id)
                       + "&accesskey=" + lp.enc(c.accesskey), function(st, tx) {
                var d = st === 200 ? lp.safeJson(tx) : null
                if (!d || !d.content) { cb(null); return }
                cb(lp.parseLrc(lp.kugouStripCredits(lp.b64Utf8(d.content))))
            })
        }
        function byKeyword() {
            lp.httpGet("https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword=" + lp.enc(kw)
                       + (secs > 0 ? "&duration=" + (secs * 1000) : ""), function(st, tx) {
                var d = st === 200 ? lp.safeJson(tx) : null
                if (d && d.candidates && d.candidates.length) download(d.candidates[0]); else cb(null)
            })
        }
        function tryHash(hashes, i) {
            if (i >= hashes.length) { byKeyword(); return }
            lp.httpGet("https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&hash=" + lp.enc(hashes[i]), function(st, tx) {
                var d = st === 200 ? lp.safeJson(tx) : null
                if (d && d.candidates && d.candidates.length) download(d.candidates[0]); else tryHash(hashes, i + 1)
            })
        }
        lp.httpGet("https://mobileservice.kugou.com/api/v3/search/song?version=9108&plat=0&pagesize=8&showtype=0&keyword="
                   + lp.enc(kw), function(st, tx) {
            var d = st === 200 ? lp.safeJson(tx) : null, list = []
            try {
                var info = d.data.info
                for (var i = 0; i < info.length; i++) {
                    var df = Math.abs((info[i].duration || 0) - secs)
                    if (!lp.matchesLoose(info[i].songname, info[i].singername, title, artist)) continue
                    if (secs <= 0 || df <= 8) list.push({ hash: info[i].hash, df: df })
                }
                list.sort(function(a, b) { return a.df - b.df })
            } catch (e) { list = [] }
            tryHash(list.slice(0, 3).map(function(x) { return x.hash }), 0)
        })
    }

    // ── Source: lrc.red (Apple Music, per-syllable timing, indexed by ISRC code) ──
    function _ttmlAt(url, cb) {
        lp.httpGet(url, function(st, tx) { cb(st === 200 ? lp.parseTtml(tx) : null) })
    }
    function srcLrcRed(title, artist, secs, cb) {
        lp.httpGet("https://lrc.red/search.json?q=" + lp.enc((title + " " + artist).trim()), function(st, tx) {
            var d = st === 200 ? lp.safeJson(tx) : null, hits = d && d.hits ? d.hits : [], best = null, bestD = 1e9
            for (var i = 0; i < hits.length; i++) {
                var h = hits[i]
                if (!h || !h.isrc || !/^[A-Z]{2}[A-Z0-9]{3}\d{7}$/.test(String(h.isrc).toUpperCase())) continue
                if (!lp.matches(h.title, h.artist, title, artist)) continue
                var df = (secs > 0 && h.duration > 0) ? Math.abs(h.duration - secs) : 0
                if (df > 3) continue
                if (df < bestD) { best = h; bestD = df }
            }
            if (!best) { cb(null); return }
            lp._ttmlAt("https://lrc.red/s/" + String(best.isrc).toUpperCase() + ".ttml", cb)
        })
    }

    // ── Source: BiniLyrics (same catalog, searches by name and says which recording it is) ──
    function srcBini(title, artist, secs, cb) {
        lp.httpGet("https://lrc.red/api/v1?track=" + lp.enc(title) + "&artist=" + lp.enc(artist)
                   + (secs > 0 ? "&duration=" + secs : ""), function(st, tx) {
            var d = st === 200 ? lp.safeJson(tx) : null, rs = d && d.results ? d.results : [], best = null, bestD = 1e9
            for (var i = 0; i < rs.length; i++) {
                var h = rs[i]
                if (!h || !h.lyricsUrl) continue
                if (!lp.matches(h.track_name, h.artist_name, title, artist)) continue
                var df = (secs > 0 && h.duration > 0) ? Math.abs(h.duration - secs) : 0
                if (df > 4) continue                      // another recording (single / album / live)
                if (df < bestD) { best = h; bestD = df }
            }
            if (!best) { cb(null); return }
            lp._ttmlAt(best.lyricsUrl, cb)
        })
    }

    // ── Source: BetterLyrics Ported (QQ Music timings) ──
    function srcPortato(title, artist, secs, cb) {
        var url = "https://lyrics-api.boidu.dev/qq/getLyrics?s=" + lp.enc(title) + "&a=" + lp.enc(artist)
                  + (secs > 0 ? "&d=" + secs : "")
        lp.httpGet(url, function(st, tx) { cb(st === 200 ? lp.parseProvider(tx) : null) })
    }

    // ── Source: LyricsPlus (the volunteer mirrors: all asked together, the first to answer counts) ──
    readonly property var lyricsPlusMirrors: [
        "https://lyricsplus.prjktla.my.id", "https://lyricsplus.atomix.one", "https://lyricsplus.binimum.org",
        "https://lyricsplus.prjktla.workers.dev", "https://lyricsplus-seven.vercel.app", "https://lyrics-plus-backend.vercel.app"]
    function parseLyricsPlus(tx) {
        var d = lp.safeJson(tx)
        if (!d || !d.lyrics || !d.lyrics.length) return null
        var out = []
        for (var i = 0; i < d.lyrics.length; i++) {
            var l = d.lyrics[i]
            if (!l || typeof l.time !== "number") continue
            var text = ""
            if (l.syllabus && l.syllabus.length) {
                for (var k = 0; k < l.syllabus.length; k++) text += (l.syllabus[k].text || "")
            }
            if (text.trim() === "") text = l.text || ""
            out.push({ t: l.time, text: String(text).replace(/\s+/g, " ").trim() })
        }
        return lp.normalize(out)
    }
    function srcLyricsPlus(title, artist, secs, cb) {
        var left = lp.lyricsPlusMirrors.length, done = false
        var q = "/v2/lyrics/get?title=" + lp.enc(title) + "&artist=" + lp.enc(artist) + (secs > 0 ? "&duration=" + secs : "")
        for (var i = 0; i < lp.lyricsPlusMirrors.length; i++) {
            lp.httpGet(lp.lyricsPlusMirrors[i] + q, function(st, tx) {
                if (done) return
                var L = st === 200 ? lp.parseLyricsPlus(tx) : null
                if (L) { done = true; cb(L); return }
                if (--left <= 0) { done = true; cb(null) }
            })
        }
    }

    // ── Fonte: Unison (testi mandati dagli ascoltatori: a volte e' l'unico posto) ──
    function srcUnison(title, artist, secs, cb) {         // cb(lines, plain)
        lp.httpGet("https://unison.boidu.dev/lyrics?song=" + lp.enc(title) + "&artist=" + lp.enc(artist)
                   + (secs > 0 ? "&duration=" + secs : ""), function(st, tx) {
            var d = st === 200 ? lp.safeJson(tx) : null
            if (!d || d.success !== true || !d.data || !d.data.lyrics) { cb(null, null); return }
            var e = d.data, text = String(e.lyrics)
            if (String(e.format || "").toLowerCase() === "ttml") { cb(lp.parseTtml(text), null); return }
            if (String(e.syncType || "").toLowerCase() === "plain") { cb(null, text); return }
            cb(lp.parseLrc(text), null)
        })
    }

    // ── Coordination: all together, the first in the list with credible timed lyrics wins ──
    readonly property var sourceDefs: [
        { name: "lrc.red",      run: "srcLrcRed" },
        { name: "BiniLyrics",   run: "srcBini" },
        { name: "BetterLyrics", run: "srcBetter" },
        { name: "Portato",      run: "srcPortato" },
        { name: "LyricsPlus",   run: "srcLyricsPlus" },
        { name: "Unison",       run: "srcUnison" },
        { name: "KuGou",        run: "srcKugou" },
        { name: "LRCLIB",       run: "srcLrclib" }
    ]
    function _run(id, k) {
        var title = lp.cleanTitle(lp.title), artist = lp.cleanArtist(lp.artist)
        var secs = Math.round(lp.durationMs / 1000)
        if (secs < 5) secs = 0                       // duration not yet known
        var defs = lp.sourceDefs
        var res = [], plain = "", finished = false
        for (var z = 0; z < defs.length; z++) res.push(undefined)
        function finish(r) {
            if (finished) return
            finished = true; _dog.stop(); lp._abort = null
            if (id !== lp._req) return
            lp._cache[k] = r
            console.log("[testi] " + (r.source || (r.plain ? qsTr("plain text only") : qsTr("no source")))
                        + " lines=" + (r.lines ? r.lines.length : 0) + qsTr(" for \"") + title + "\" - \"" + artist + "\" (" + secs + "s)")
            lp._apply(r)
        }
        function evaluate() {
            for (var i = 0; i < res.length; i++) {
                if (res[i] === undefined) return
                if (res[i]) { finish({ source: defs[i].name, lines: res[i], plain: "" }); return }
            }
            finish({ source: "", lines: null, plain: plain })
        }
        function settle(i, lines, pl) {
            if (id !== lp._req || finished) return
            res[i] = lp.sane(lines, secs, defs[i].name) || null
            if (pl && !plain) plain = pl
            evaluate()
        }
        lp._abort = function() {
            for (var i = 0; i < res.length; i++) if (res[i] === undefined) res[i] = null
            evaluate()
        }
        _dog.restart()
        for (var n = 0; n < defs.length; n++) {
            (function(i) {
                try { lp[defs[i].run](title, artist, secs, function(l, p) { settle(i, l, p) }) }
                catch (e) { console.log("[lyrics] error in " + defs[i].name + ":", e); settle(i, null) }
            })(n)
        }
    }

    // ── Position: interpolated between one reading and the next ────────────────
    property real _baseMs: 0
    property real _baseAt: 0
    function _estimate() { return lp.playing ? lp._baseMs + (Date.now() - lp._baseAt) : lp._baseMs }
    function _rebase(force) {
        if (force || !lp.playing || Math.abs(lp.positionMs - lp._estimate()) > 600) {
            lp._baseMs = lp.positionMs; lp._baseAt = Date.now()
        }
    }
    onPositionMsChanged: _rebase(false)
    onPlayingChanged: _rebase(true)

    function indexAt(ms) {
        var L = lp.lines
        if (!L.length || ms < L[0].t) return -1
        var lo = 0, hi = L.length - 1
        while (lo < hi) { var mid = (lo + hi + 1) >> 1; if (L[mid].t <= ms) lo = mid; else hi = mid - 1 }
        return lo
    }

    property bool _needFollow: false
    property real _userUntil: 0
    onCurChanged: _needFollow = true

    Timer {
        interval: 120; repeat: true
        running: lp.active && lp.phase === "ok"
        onTriggered: {
            var i = lp.indexAt(lp._estimate() + lp.syncOffsetMs + lp.leadMs)
            if (i !== lp.cur) lp.cur = i
            if (lp._needFollow && Date.now() > lp._userUntil && rep.count === lp.lines.length) {
                lp._needFollow = false
                lp.follow()
            }
        }
    }

    function follow() {
        var it = lp.cur >= 0 ? rep.itemAt(lp.cur) : null
        var target = it ? (col.y + it.y - lp.anchorY) : 0
        target = Math.max(0, Math.min(target, Math.max(0, fl.contentHeight - fl.height)))
        followAnim.stop(); followAnim.from = fl.contentY; followAnim.to = target; followAnim.start()
    }

    // ══════════════ VISTA ══════════════
    // Background: theme tint, then the cover's color faded toward the bottom
    Rectangle { anchors.fill: parent; color: lp.bgColor }
    Rectangle {
        anchors.fill: parent
        opacity: lp.tinted ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 500 } }
        gradient: Gradient {
            GradientStop { position: 0.0; color: lp.tintTop }
            GradientStop { position: 1.0; color: lp.tintBottom }
        }
    }

    // Background -> header: from the header color (top) to the cover color, very long and soft
    // (smootherstep: starts and arrives with zero slope, almost over the whole height)
    Rectangle {
        x: 0; y: 0; width: parent.width; height: lp.bgH
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 1.0) }
            GradientStop { position: lp._bp(0.0000); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 1.000) }
            GradientStop { position: lp._bp(0.0357); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 1.000) }
            GradientStop { position: lp._bp(0.0714); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.997) }
            GradientStop { position: lp._bp(0.1071); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.990) }
            GradientStop { position: lp._bp(0.1429); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.977) }
            GradientStop { position: lp._bp(0.1786); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.957) }
            GradientStop { position: lp._bp(0.2143); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.931) }
            GradientStop { position: lp._bp(0.2500); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.896) }
            GradientStop { position: lp._bp(0.2857); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.855) }
            GradientStop { position: lp._bp(0.3214); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.807) }
            GradientStop { position: lp._bp(0.3571); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.754) }
            GradientStop { position: lp._bp(0.3929); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.695) }
            GradientStop { position: lp._bp(0.4286); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.632) }
            GradientStop { position: lp._bp(0.4643); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.567) }
            GradientStop { position: lp._bp(0.5000); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.500) }
            GradientStop { position: lp._bp(0.5357); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.433) }
            GradientStop { position: lp._bp(0.5714); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.368) }
            GradientStop { position: lp._bp(0.6071); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.305) }
            GradientStop { position: lp._bp(0.6429); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.246) }
            GradientStop { position: lp._bp(0.6786); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.193) }
            GradientStop { position: lp._bp(0.7143); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.145) }
            GradientStop { position: lp._bp(0.7500); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.104) }
            GradientStop { position: lp._bp(0.7857); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.069) }
            GradientStop { position: lp._bp(0.8214); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.043) }
            GradientStop { position: lp._bp(0.8571); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.023) }
            GradientStop { position: lp._bp(0.8929); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.010) }
            GradientStop { position: lp._bp(0.9286); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.003) }
            GradientStop { position: lp._bp(0.9643); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.000) }
            GradientStop { position: lp._bp(1.0000); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.000) }
        }
    }

    Item {
        id: _fadeMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                // at the top the text fades gently UNDER title and cover (no hard cut)
                GradientStop { position: 0.00;      color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: lp._fp(0.0); color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: lp._fp(0.2); color: Qt.rgba(1, 1, 1, 0.104) }
                GradientStop { position: lp._fp(0.4); color: Qt.rgba(1, 1, 1, 0.352) }
                GradientStop { position: lp._fp(0.6); color: Qt.rgba(1, 1, 1, 0.648) }
                GradientStop { position: lp._fp(0.8); color: Qt.rgba(1, 1, 1, 0.896) }
                GradientStop { position: lp._fp(1.0); color: Qt.rgba(1, 1, 1, 1) }
                GradientStop { position: 0.88; color: Qt.rgba(1, 1, 1, 1) }
                GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
    }

    readonly property real hdrH: 150
    // the text is full below fadeY1 and disappears completely above fadeY0
    readonly property real fadeY0: hdrH
    readonly property real fadeY1: Math.max(hdrH + 40, Math.min(hdrH + 190, anchorY))
    // fade ABOVE the text: short, it only serves to cover the text behind the title
    readonly property real mergeH: hdrH + 70
    function _gp(u) { var p0 = hdrH / mergeH; return p0 + (1 - p0) * u }
    // fade BELOW the text: very long (from the header down to below the current line), so the color transition is soft
    readonly property real bgH: lp.height * 0.95
    function _bp(u) { var p0 = hdrH * 0.5 / bgH; return p0 + (1 - p0) * u }
    readonly property color hdrFg: lightTheme ? "#161616" : "#FFFFFF"
    function _fp(t) { return Math.min(0.6, (fadeY0 + (fadeY1 - fadeY0) * t) / Math.max(1, lp.height)) }
    // where the current line stops (from the top of the panel)
    readonly property real anchorY: hdrH + 0.30 * (lp.height - hdrH)

    Flickable {
        id: fl
        anchors.fill: parent
        visible: lp.phase === "ok"
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: col.y + col.height + height * 0.7
        onMovementStarted: { followAnim.stop(); lp._userUntil = Date.now() + 3500 }
        // fade at the top and bottom: gradient mask (works on any background)
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: _fadeMask }

        NumberAnimation { id: followAnim; target: fl; property: "contentY"; duration: 520; easing.type: Easing.OutCubic }

        Column {
            id: col
            x: lp.padX; y: lp.anchorY
            width: fl.width - lp.padX * 2
            spacing: 0

            Repeater {
                id: rep
                model: lp.lines
                delegate: Item {
                    id: row
                    required property int index
                    required property var modelData
                    readonly property int  dist: index - lp.cur
                    readonly property bool isActive: dist === 0
                    // line inside (or near) the visible area: only these get the blur effect
                    readonly property real _top: row.y + col.y - fl.contentY
                    readonly property bool inView: _top > -fl.height * 0.6 && _top < fl.height * 1.6
                    readonly property bool isGap: modelData.text === ""
                    width: col.width
                    height: isGap ? (isActive ? lp.fs * 1.5 : 0) : txt.contentHeight * (isActive ? 1.0 : 0.9) + lp.fs * 0.62
                    visible: height > 0.5
                    Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                    Text {
                        id: txt
                        visible: !row.isGap
                        width: parent.width
                        text: row.modelData.text
                        wrapMode: Text.Wrap
                        font.pixelSize: lp.fs
                        font.weight: Font.ExtraBold
                        font.letterSpacing: -lp.fs * 0.025
                        lineHeight: 1.05
                        color: row.isActive ? lp.fgOn : lp.fgOff
                        opacity: row.isActive ? 1.0 : (lp.colored ? Math.max(0.22, 0.5 - Math.abs(row.dist) * 0.05) : Math.max(0.35, 0.9 - Math.abs(row.dist) * 0.12))
                        transformOrigin: Item.TopLeft
                        scale: row.isActive ? 1.0 : 0.9
                        Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 320 } }
                        Behavior on color   { ColorAnimation  { duration: 320 } }
                        layer.enabled: !row.isActive && row.inView && !Theme.lowPower
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            blurEnabled: true; blurMax: 24
                            blur: Math.min(1.0, 0.3 + Math.abs(row.dist) * 0.25)
                        }
                    }
                    // Pausa strumentale: tre puntini
                    Row {
                        visible: row.isGap && row.isActive
                        spacing: lp.fs * 0.3
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater { model: 3; Rectangle { width: lp.fs * 0.3; height: width; radius: width / 2; color: lp.fgOn; opacity: 0.8 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !row.isGap
                        onClicked: { lp._userUntil = 0; lp.cur = -2; lp.seekRequested(row.modelData.t) }
                    }
                }
            }
        }
    }

    // Text without timings (only when no source has the synced one)
    Flickable {
        anchors.fill: parent
        visible: lp.phase === "plain"
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: _plain.height + lp.height * 0.3
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: _fadeMask }
        Text {
            id: _plain
            x: lp.padX; y: lp.hdrH + 40; width: parent.width - lp.padX * 2
            text: lp.plainText
            wrapMode: Text.Wrap
            color: lp.fgOn; opacity: 0.85
            font.pixelSize: lp.fs * 0.62; font.weight: Font.DemiBold
            lineHeight: 1.18
        }
    }
    Text {
        visible: lp.phase === "plain"
        x: lp.padX; y: lp.hdrH + 8
        text: qsTr("Unsynced lyrics")
        color: lp.fgOff; opacity: lp.colored ? 0.6 : 1; font.pixelSize: 14
    }

    // Status messages
    Text {
        visible: lp.phase === "loading" || lp.phase === "none" || (lp.phase === "idle" && lp.active)
        anchors.centerIn: parent
        text: lp.phase === "none" ? qsTr("Lyrics not found") : (lp.title === "" ? qsTr("No track playing") : qsTr("Looking for lyrics…"))
        color: lp.fgOff; font.pixelSize: 20; font.weight: Font.Medium
    }

    // Short fade above the text: header color (opaque where the title is), then it fades out. Hides the text behind the title.
    Rectangle {
        x: 0; y: 0; width: parent.width; height: lp.mergeH
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 1.0) }
            GradientStop { position: lp._gp(0.0000); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 1.000) }
            GradientStop { position: lp._gp(0.0625); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.990) }
            GradientStop { position: lp._gp(0.1250); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.962) }
            GradientStop { position: lp._gp(0.1875); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.916) }
            GradientStop { position: lp._gp(0.2500); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.854) }
            GradientStop { position: lp._gp(0.3125); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.778) }
            GradientStop { position: lp._gp(0.3750); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.691) }
            GradientStop { position: lp._gp(0.4375); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.598) }
            GradientStop { position: lp._gp(0.5000); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.500) }
            GradientStop { position: lp._gp(0.5625); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.402) }
            GradientStop { position: lp._gp(0.6250); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.309) }
            GradientStop { position: lp._gp(0.6875); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.222) }
            GradientStop { position: lp._gp(0.7500); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.146) }
            GradientStop { position: lp._gp(0.8125); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.084) }
            GradientStop { position: lp._gp(0.8750); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.038) }
            GradientStop { position: lp._gp(0.9375); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.010) }
            GradientStop { position: lp._gp(1.0000); color: Qt.rgba(lp.bgColor.r, lp.bgColor.g, lp.bgColor.b, 0.000) }
        }
    }

    // ── Header: big cover, title and artist below; X to close ──────────
    Item {
        id: _hdr
        x: 0; y: 0; width: parent.width; height: lp.hdrH
        MouseArea { anchors.fill: parent }
        Item {
            id: _thumbMask
            width: 112; height: 112; visible: false; layer.enabled: true
            Rectangle { anchors.fill: parent; radius: 2; color: "white" }
        }
        Image {
            id: _thumb
            x: lp.padX; anchors.verticalCenter: parent.verticalCenter
            width: 112; height: 112
            source: lp.cover; sourceSize: Qt.size(224, 224)
            fillMode: Image.PreserveAspectCrop; asynchronous: true
            visible: lp.cover !== "" && status === Image.Ready
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: _thumbMask }
        }
        Column {
            x: lp.padX + (_thumb.visible ? 112 + 24 : 0)
            width: parent.width - x - 110
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text {
                width: parent.width; text: lp.title
                color: lp.hdrFg; font.pixelSize: 34; font.weight: Font.DemiBold; elide: Text.ElideRight
            }
            Text {
                visible: text !== ""
                width: parent.width; text: lp.cleanArtist(lp.artist)
                color: lp.hdrFg; opacity: 0.62; font.pixelSize: 24; elide: Text.ElideRight
            }
        }
        // X (two lines: does not depend on a font), no circle
        Item {
            id: _x
            width: 84; height: 84
            anchors.right: parent.right; anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            opacity: _xMA.pressed ? 0.5 : 1.0
            Behavior on opacity { NumberAnimation { duration: 90 } }
            Rectangle { anchors.centerIn: parent; width: 34; height: 4; radius: 2; rotation: 45;  color: lp.hdrFg }
            Rectangle { anchors.centerIn: parent; width: 34; height: 4; radius: 2; rotation: -45; color: lp.hdrFg }
            MouseArea { id: _xMA; anchors.fill: parent; onClicked: lp.closeRequested() }
        }
    }
}
