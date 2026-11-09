import QtQuick
import QtQuick.Window
import QtQuick.Effects
import VoltaApp 1.0

// PODCAST APP — iTunes catalog + RSS feeds, playback from the podcast_service.py service (port 8094).
// Tabs: Home · New · Charts · Library; search; podcast page; full-screen player.
// The playback state (title, cover, play/pause) reaches the mini player from the system player (MPRIS).
Rectangle {
    id: root
    color: Theme.bg
    clip: true
    property bool lightTheme: false
    onLightThemeChanged: Theme.light = lightTheme

    property var hub: null                       // (not used: playback does not go through MediaHub)
    signal switchToApp(string appId)

    property string backendUrl: "http://127.0.0.1:8094"
    readonly property color accent: "#A855F7"
    readonly property color accentSoft: lightTheme ? "#EBDDFB" : "#3A2656"
    property string iconColor: lightTheme ? "#555555" : "#A2A3A5"
    property string dividerColor: lightTheme ? "#777777" : "#414141"
    property string selectedTextColor: lightTheme ? "#444444" : Theme.textPrimary
    readonly property real u: (Window.window && Window.window.uPx) ? Window.window.uPx : 1.12
    readonly property real headerH: 38 * u

    readonly property var musicApps: [
        { appId: "spotify",    name: "YT Music",  icon: "qrc:/VoltaApp/icons/ytmusic.svg" },
        { appId: "spotifyapp", name: "Spotify",   icon: "qrc:/VoltaApp/icons/spotify.svg" },
        { appId: "localmusic", name: qsTr("Music"), icon: "qrc:/VoltaApp/icons/localmusic.svg" },
        { appId: "podcast",    name: "Podcasts",   icon: "qrc:/VoltaApp/icons/podcast.svg" },
        { appId: "bluetooth",  name: "Bluetooth", icon: "qrc:/VoltaApp/icons/bluetooth.svg" }
    ]
    readonly property string selfAppId: "podcast"
    property bool appMenuOpen: false

    // ── Navigazione ──
    property string tab: "home"                  // home | browse | news | charts | library
    property string libTab: "shows"              // shows | saved | history
    property bool searchOpen: false
    property bool playerOpen: false
    property bool detailOpen: false
    property bool episodesOpen: false              // full list of a podcast's episodes
    property bool categoryOpen: false             // page of a category (opened from Explore, Search…)
    property var category: ({ id: "", name: "", color: "#6D28D9" })
    property var catData: ({ id: "", top: [], discover: [], all: [] })
    property bool catBusy: false
    property string chartGenre: ""

    // ── Data ──
    property bool backendOk: true
    property string toastText: ""
    property var continueList: []
    property var newList: []
    property var topShows: []
    property var browseData: ({ hero: [], shelves: [] })
    property var browseGenres: []
    property string browseSeed: ""
    property bool browseBusy: false
    property var genreShelves: []                // [{id,name,items}]
    property var chartShows: []
    property bool chartsBusy: false
    property bool chartEpsBusy: false
    property var subsList: []
    property var historyList: []
    property var genres: []
    property var pState: ({ active: false, playing: false, pos: 0, dur: 0, speed: 1, sleepLeft: 0, canNext: false, canPrev: false, ep: null })

    ListModel { id: chartEpModel }
    ListModel { id: savedModel }
    ListModel { id: newModel }
    ListModel { id: browseEpModel }
    ListModel { id: catEpModel }
    ListModel { id: listModel }
    readonly property int listCount: listModel.count
    readonly property int detailRowCount: detailModel.count
    property real browseTs: 0
    ListModel { id: historyModel }
    ListModel { id: detailModel }
    ListModel { id: searchEpModel }
    ListModel { id: queueModel }

    property var detail: ({ feed: "", id: "", title: "", author: "", cover: "", desc: "", genre: "", total: 0, subscribed: false, persons: [], trailer: null })
    property bool detailLoading: false
    property bool detailAsc: false
    property int detailShown: 30
    property var detailAll: []
    property bool descExpanded: false

    property string searchTerm: ""
    property var searchShows: []
    property bool searchBusy: false
    property string searchMsg: ""

    // ═════════ Utilities ═════════
    function api(path, cb, err) {
        var x = new XMLHttpRequest()
        x.open("GET", root.backendUrl + path)
        x.timeout = 40000
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return
            var d = null
            try { d = JSON.parse(x.responseText) } catch (e) {}
            if (x.status === 200 && d !== null) { root.backendOk = true; if (cb) cb(d) }
            else {
                if (x.status === 0) root.backendOk = false
                if (err) err(x.status, d)
            }
        }
        x.send()
    }
    function q(s) { return encodeURIComponent(s === undefined || s === null ? "" : String(s)) }
    function toast(t) { root.toastText = t; _toastTimer.restart() }
    function fmt(sec) {
        sec = Math.max(0, Math.floor(sec || 0))
        var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60
        var ss = (s < 10 ? "0" : "") + s
        return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss
    }
    function relTime(ep) {
        var d = Math.floor(Date.now() / 1000 - (ep.date || 0))
        if (!ep.date || d < 0) return (ep.dateLabel || "").toUpperCase()
        if (d < 3600) return Math.max(1, Math.floor(d / 60)) + qsTr(" MIN AGO")
        if (d < 86400) { var h = Math.floor(d / 3600); return h + (h === 1 ? qsTr(" HR AGO") : qsTr(" HRS AGO")) }
        if (d < 7 * 86400) return Math.floor(d / 86400) + qsTr(" D AGO")
        return (ep.dateLabel || "").toUpperCase()
    }
    function fmtMin(sec) {
        sec = Math.floor(sec || 0)
        if (sec <= 0) return ""
        var m = Math.round(sec / 60)
        if (m < 60) return Math.max(1, m) + " min"
        return Math.floor(m / 60) + " h " + (m % 60 > 0 ? (m % 60) + " min" : "")
    }
    function fmtLeft(sec) {
        sec = Math.floor(sec || 0)
        if (sec <= 0) return ""
        var m = Math.round(sec / 60)
        if (m < 60) return Math.max(1, m) + qsTr(" min left")
        return Math.floor(m / 60) + " h " + (m % 60 > 0 ? (m % 60) + " min " : "") + qsTr("left")
    }
    function normEp(e) {
        return {
            ek: e.ek || "", guid: e.guid || "", feed: e.feed || "", title: e.title || "", desc: e.desc || "",
            podcast: e.podcast || "", cover: e.cover || "", audio: e.audio || "", dateLabel: e.dateLabel || "",
            date: e.date || 0, dur: Math.floor(e.dur || 0), pos: Math.floor(e.pos || 0), done: !!e.done, saved: !!e.saved
        }
    }
    function fill(model, arr) {
        model.clear()
        for (var i = 0; i < arr.length; i++) model.append(normEp(arr[i]))
    }
    function epOf(m) {
        return { ek: m.ek, guid: m.guid, feed: m.feed, title: m.title, desc: m.desc, podcast: m.podcast, cover: m.cover,
                 audio: m.audio, dateLabel: m.dateLabel, date: m.date, dur: m.dur, pos: m.pos, done: m.done, saved: m.saved }
    }
    function isCurrent(ep) {
        var c = root.pState.ep
        return !!(c && ep && c.guid === ep.guid && (c.feed || "") === (ep.feed || ""))
    }
    function showOf(p) { return { id: p.id || "", title: p.title || "", author: p.author || "", cover: p.cover || "", feed: p.feed || "" } }

    // ═════════ Caricamenti ═════════
    function loadHome() {
        api("/continue", function(d) { root.continueList = d.episodes || [] })
        api("/new", function(d) { root.newList = d.episodes || []; fill(newModel, root.newList) })
        api("/subs", function(d) { root.subsList = d.subs || [] })
        api("/genres", function(d) { root.genres = d.genres || [] })
        api("/charts", function(d) { root.topShows = d.items || [] }, function(c, d) { if (c === 429) root.toast((d && d.error) || qsTr("Try again shortly")) })
        if (root.genreShelves.length < _shelfTimer.ids.length) { _shelfTimer.shelf = 0; root.genreShelves = []; _shelfTimer.restart() }
    }
    function loadLibrary() {
        api("/subs", function(d) { root.subsList = d.subs || [] })
        api("/saved", function(d) { fill(savedModel, d.episodes || []) })
        api("/history", function(d) { root.historyList = d.episodes || []; fill(historyModel, root.historyList) })
    }
    function loadBrowse(fresh) {
        if (!fresh && root.browseData.hero.length + root.browseData.shelves.length > 0 && Date.now() - root.browseTs < 600000) return
        root.browseBusy = true
        var seed = String(Date.now())
        api("/browse?seed=" + seed, function(d) {
            root.browseData = { hero: d.hero || [], shelves: d.shelves || [] }
            root.browseGenres = d.genres || []; root.browseSeed = d.seed || seed; root.browseBusy = false; root.browseTs = Date.now()
        }, function(c, d) { root.browseBusy = false; root.toast(qsTr("Explore is unavailable at the moment")) })
        api("/top_episodes?genre=", function(d) {
            var a = (d.episodes || []).slice()
            for (var i = a.length - 1; i > 0; i--) { var j = Math.floor(Math.random() * (i + 1)); var t = a[i]; a[i] = a[j]; a[j] = t }
            fill(browseEpModel, a.slice(0, 6))
        })
    }
    function genreInfo(id) {
        var l = root.browseGenres.length > 0 ? root.browseGenres : root.genres
        for (var i = 0; i < l.length; i++) if (l[i].id === id) return { id: id, name: l[i].name, color: l[i].color || "#6D28D9" }
        return { id: id, name: id, color: "#6D28D9" }
    }
    function openCategory(g) {
        if (root.searchOpen) closeSearch()
        root.category = genreInfo(g)
        root.detailOpen = false; root.playerOpen = false; root.appMenuOpen = false; root.episodesOpen = false
        root.categoryOpen = true
        loadCategory(true)
    }
    function loadCategory(fresh) {
        var g = root.category.id
        if (!g) return
        if (!fresh && root.catData.id === g && root.catData.all.length > 0) return
        root.catBusy = true
        if (root.catData.id !== g) { root.catData = { id: g, top: [], discover: [], all: [] }; catEpModel.clear() }
        api("/category?genre=" + q(g) + "&seed=" + Date.now(), function(d) {
            if (g !== root.category.id) return
            root.catData = { id: g, top: d.top || [], discover: d.discover || [], all: d.all || [] }
            if (d.genre) root.category = { id: g, name: d.genre.name, color: d.genre.color || root.category.color }
            root.catBusy = false
        }, function(c, d) { root.catBusy = false; root.toast(qsTr("Category unavailable at the moment")) })
        if (fresh || catEpModel.count === 0)
            api("/top_episodes?genre=" + q(g), function(d) { if (g === root.category.id) fill(catEpModel, (d.episodes || []).slice(0, 8)) })
    }
    function loadNews() { api("/new", function(d) { root.newList = d.episodes || []; fill(newModel, root.newList) }) }
    function loadCharts() {
        root.chartsBusy = true; root.chartEpsBusy = true
        var g = root.chartGenre
        api("/charts?genre=" + q(g), function(d) { if (g === root.chartGenre) { root.chartShows = d.items || []; root.chartsBusy = false } },
            function(c, d) { root.chartsBusy = false; root.chartShows = []; root.toast(c === 429 ? qsTr("Too many requests, try again shortly") : qsTr("Chart unavailable")) })
        api("/top_episodes?genre=" + q(g), function(d) { if (g === root.chartGenre) { fill(chartEpModel, d.episodes || []); root.chartEpsBusy = false } },
            function(c, d) { root.chartEpsBusy = false; chartEpModel.clear() })
    }
    function refreshState() {
        api("/player/state", function(d) { root.pState = d })
    }
    // ── SCREEN HISTORY (back/forward buttons of the header, like YT Music) ──
    property var _navBack: []
    property var _navFwd: []
    property int navBackCount: 0
    property int navFwdCount: 0
    property var _navCur: null
    function _navSnap() {
        return { tab: root.tab, searchOpen: root.searchOpen, searchTerm: root.searchTerm, playerOpen: root.playerOpen,
                 detailOpen: root.detailOpen, detail: root.detail, categoryOpen: root.categoryOpen, category: root.category, episodesOpen: root.episodesOpen }
    }
    function _navKey(s) {
        if (!s) return ""
        var id = (s.detailOpen && s.detail) ? "d:" + (s.detail.id || s.detail.feed || s.detail.title || "") : ""
        var cid = s.categoryOpen && s.category ? "c:" + s.category.id : ""
        return s.tab + "|" + (s.searchOpen ? 1 : 0) + "|" + (s.playerOpen ? 1 : 0) + "|" + cid + "|" + id + "|" + (s.episodesOpen ? 1 : 0)
    }
    // everything that defines the screen is observed; the timer groups multiple changes of the same action
    property var _navWatch: root._navSnap()
    on_NavWatchChanged: _navTimer.restart()
    Timer { id: _navTimer; interval: 30; running: true; onTriggered: root._navCommit() }
    function _navCommit() {
        var now = root._navSnap()
        if (root._navCur === null) { root._navCur = now; return }
        if (root._navKey(now) !== root._navKey(root._navCur)) {
            var b = root._navBack.slice(); b.push(root._navCur)
            if (b.length > 30) b.shift()
            root._navBack = b
            root._navFwd = []
        }
        root._navCur = now
        root.navBackCount = root._navBack.length
        root.navFwdCount = root._navFwd.length
    }
    function _navRestore(s) {
        root._navCur = s
        if (root.tab !== s.tab) { root.tab = s.tab; loadTab(s.tab) }
        root.playerOpen = s.playerOpen
        root.categoryOpen = s.categoryOpen
        if (s.categoryOpen) { root.category = s.category; loadCategory(false) }
        if (s.detailOpen) { openShow(s.detail); root.episodesOpen = !!s.episodesOpen }
        else {
            root.detailOpen = false
            if (s.searchOpen) { root.searchOpen = true; if (_si.text !== s.searchTerm) _si.text = s.searchTerm }
            else if (root.searchOpen) closeSearch()
        }
        root.navBackCount = root._navBack.length
        root.navFwdCount = root._navFwd.length
    }
    function navBack() {
        _navTimer.stop(); root._navCommit()
        if (root._navBack.length === 0) return
        var b = root._navBack.slice(); var s = b.pop(); root._navBack = b
        var f = root._navFwd.slice(); f.push(root._navCur); root._navFwd = f
        root._navRestore(s)
    }
    function navForward() {
        _navTimer.stop(); root._navCommit()
        if (root._navFwd.length === 0) return
        var f = root._navFwd.slice(); var s = f.pop(); root._navFwd = f
        var b = root._navBack.slice(); b.push(root._navCur); root._navBack = b
        root._navRestore(s)
    }
    function loadTab(t) {
        if (t === "home") loadHome()
        else if (t === "browse") loadBrowse(false)
        else if (t === "news") loadNews()
        else if (t === "charts") { if (root.genres.length === 0) api("/genres", function(d) { root.genres = d.genres || [] }); loadCharts() }
        else if (t === "library") loadLibrary()
    }
    function setTab(t) {
        root.tab = t; root.detailOpen = false; root.searchOpen = false; root.playerOpen = false; root.categoryOpen = false; root.episodesOpen = false
        loadTab(t)
    }
    function openShow(p) {
        root.detail = { feed: p.feed || "", id: p.id || "", title: p.title || p.podcast || "", author: p.author || "", cover: p.cover || "",
                        desc: "", genre: "", total: 0, subscribed: false, persons: [], trailer: null }
        detailModel.clear(); root.detailAll = []; root.detailShown = 30; root.descExpanded = false
        root.detailOpen = true; root.searchOpen = false; root.playerOpen = false; root.detailLoading = true; root.episodesOpen = false
        loadDetail(false)
    }
    function loadDetail(fresh) {
        var feed = root.detail.feed, id = root.detail.id
        api("/podcast?feed=" + q(feed) + "&id=" + q(id) + (fresh ? "&fresh=1" : ""), function(d) {
            if ((d.feed || "") !== (root.detail.feed || "") && root.detail.feed !== "") return
            root.detail = { feed: d.feed, id: d.id || id, title: d.title || root.detail.title, author: d.author || root.detail.author,
                            cover: d.cover || root.detail.cover, desc: d.desc || "", genre: d.genre || "", total: d.total || 0, subscribed: !!d.subscribed,
                            persons: d.persons || [], trailer: d.trailer || null }
            root.detailAll = d.episodes || []
            rebuildDetail()
            root.detailLoading = false
        }, function(c, d) { root.detailLoading = false; root.toast(qsTr("Podcast unreachable") + (d && d.error ? ": " + d.error : "")) })
    }
    function rebuildDetail() {
        var a = root.detailAll.slice()
        fill(detailModel, a.slice(0, 1))                      // on the page: only the latest episode
        if (root.detailAsc) a.reverse()
        fill(listModel, a.slice(0, root.detailShown))         // "Show all": full list, in pages
    }
    function setDetailSub(v) {
        var d = root.detail, n = {}
        for (var k in d) n[k] = d[k]
        n.subscribed = v
        root.detail = n                      // new object: so the button really updates
    }
    function toggleSub(p) {
        var want = !root.detail.subscribed
        setDetailSub(want)                   // immediately: the button changes on touch, without waiting for the network
        api("/subs/toggle?feed=" + q(p.feed) + "&id=" + q(p.id) + "&title=" + q(p.title) + "&author=" + q(p.author) + "&cover=" + q(p.cover), function(d) {
            if (root.detail.feed === p.feed) setDetailSub(d.subscribed)
            root.toast(d.subscribed ? qsTr("✓  You subscribed to ") + p.title : qsTr("Subscription cancelled"))
            api("/subs", function(r) { root.subsList = r.subs || [] })
        }, function() {
            if (root.detail.feed === p.feed) setDetailSub(!want)
            root.toast(qsTr("Couldn't change the subscription"))
        })
    }
    function isSubscribed(feed) { for (var i = 0; i < root.subsList.length; i++) if (root.subsList[i].feed === feed) return true; return false }

    function playEp(ep) {
        var p = "/play?feed=" + q(ep.feed) + "&guid=" + q(ep.guid) + "&audio=" + q(ep.audio) + "&title=" + q(ep.title) +
                "&podcast=" + q(ep.podcast) + "&cover=" + q(ep.cover) + "&dur=" + q(ep.dur) + "&date=" + q(ep.date)
        api(p, function(d) { if (d.state) root.pState = d.state },
            function(c, d) { root.toast(c === 503 ? qsTr("Playback unavailable (python-mpv missing)") : qsTr("Unable to play") + (d && d.error ? ": " + d.error : "")) })
    }
    function playLatest() {
        if (root.detailAll.length === 0) return
        // resumes the most recently started episode; otherwise the newest unlistened one
        var best = null
        for (var i = 0; i < root.detailAll.length; i++) { var e = root.detailAll[i]; if (e.pos > 15 && !e.done) { best = e; break } }
        if (!best) for (var j = 0; j < root.detailAll.length; j++) if (!root.detailAll[j].done) { best = root.detailAll[j]; break }
        if (!best) best = root.detailAll[0]
        playEp(best)
    }
    function toggleSaved(ep) {
        api("/saved/toggle?feed=" + q(ep.feed) + "&guid=" + q(ep.guid) + "&audio=" + q(ep.audio) + "&title=" + q(ep.title) + "&podcast=" + q(ep.podcast) + "&cover=" + q(ep.cover) + "&dur=" + q(ep.dur),
            function(d) { root.toast(d.saved ? qsTr("Saved for later") : qsTr("Removed from saved")); patchEp(ep, { saved: d.saved }); if (root.tab === "library") loadLibrary() })
    }
    function toggleDone(ep) {
        var on = !ep.done
        api("/mark?feed=" + q(ep.feed) + "&guid=" + q(ep.guid) + "&done=" + (on ? 1 : 0) + "&audio=" + q(ep.audio) + "&title=" + q(ep.title),
            function(d) { patchEp(ep, { done: d.done, pos: d.done ? ep.pos : 0 }); root.toast(d.done ? qsTr("Marked as played") : qsTr("Marked as unplayed")) })
    }
    function patchEp(ep, ch) {
        var models = [detailModel, listModel, savedModel, newModel, historyModel, chartEpModel, searchEpModel, browseEpModel, catEpModel]
        for (var m = 0; m < models.length; m++)
            for (var i = 0; i < models[m].count; i++) {
                var it = models[m].get(i)
                if (it.guid === ep.guid && it.feed === ep.feed) for (var k in ch) models[m].setProperty(i, k, ch[k])
            }
        for (var i2 = 0; i2 < root.detailAll.length; i2++) if (root.detailAll[i2].guid === ep.guid) for (var k2 in ch) root.detailAll[i2][k2] = ch[k2]
    }
    function doSearch() {
        var t = root.searchTerm.trim()
        if (t.length < 2) { root.searchShows = []; searchEpModel.clear(); root.searchMsg = ""; return }
        root.searchBusy = true; root.searchMsg = ""
        api("/search?q=" + q(t), function(d) {
            if (t !== root.searchTerm.trim()) return
            root.searchBusy = false; root.searchShows = d.podcasts || []; fill(searchEpModel, d.episodes || [])
            if ((d.podcasts || []).length === 0 && (d.episodes || []).length === 0) root.searchMsg = qsTr("No results for “") + t + "”"
        }, function(c, d) {
            root.searchBusy = false
            root.searchMsg = c === 429 ? qsTr("Too many searches in a row: try again in a few seconds.") : (c === 0 ? qsTr("Podcast service unreachable.") : qsTr("Search failed."))
        })
    }
    function openSearch() {
        root.searchOpen = true; root.playerOpen = false; root.appMenuOpen = false
        if (root.genres.length === 0) api("/genres", function(d) { root.genres = d.genres || [] })
        Qt.callLater(function() { _si.forceActiveFocus() })
    }
    function closeSearch() { root.searchOpen = false; _si.text = ""; root.searchTerm = ""; root.searchShows = []; searchEpModel.clear(); root.searchMsg = ""; Qt.inputMethod.hide() }

    function speedText(x) {
        x = x || 1
        return (Math.round(x * 100) / 100).toString().replace(".", ",") + "×"
    }
    function loadQueue() {
        api("/player/queue", function(d) {
            queueModel.clear()
            var a = d.items || []
            for (var i = 0; i < a.length; i++) { var e = normEp(a[i]); e.qi = a[i].qi; queueModel.append(e) }
        })
    }
    function jumpTo(qi) { api("/player/jump?i=" + qi, function(d) { root.pState = d; root.loadQueue() }) }
    readonly property string curGuid: root.pState.ep ? root.pState.ep.guid : ""
    onCurGuidChanged: if (root.playerOpen) loadQueue()
    onPlayerOpenChanged: if (root.playerOpen) loadQueue()

    function cmd(path) { api(path, function(d) { root.pState = d }) }
    function togglePlay() { cmd("/player/toggle") }
    function seekRel(s) { cmd("/player/seek?rel=" + s) }
    function seekPct(p) { cmd("/player/seek?pct=" + p) }
    function nextEp() { cmd("/player/next") }
    function prevEp() { cmd("/player/prev") }
    function cycleSpeed() {
        var s = [1.0, 1.25, 1.5, 1.75, 2.0, 0.8]
        var cur = root.pState.speed || 1, i = 0
        for (var k = 0; k < s.length; k++) if (Math.abs(s[k] - cur) < 0.01) i = k
        cmd("/player/speed?x=" + s[(i + 1) % s.length])
    }
    function cycleSleep() {
        var left = root.pState.sleepLeft || 0
        var mins = [0, 15, 30, 45, 60]
        var curMin = left <= 0 ? 0 : (left <= 15 * 60 ? 15 : left <= 30 * 60 ? 30 : left <= 45 * 60 ? 45 : 60)
        var i = mins.indexOf(curMin)
        var nx = mins[(i + 1) % mins.length]
        cmd("/player/sleep?min=" + nx)
        root.toast(nx === 0 ? qsTr("Sleep timer turned off") : qsTr("Stops in ") + nx + " minuti")
    }

    // ═════════ Timer ═════════
    Timer { id: _toastTimer; interval: 2800; onTriggered: root.toastText = "" }
    // playback state: only with the app visible
    Timer { interval: 1000; repeat: true; running: root.visible; triggeredOnStart: true; onTriggered: root.refreshState() }
    // the service starts a few seconds after the interface: retry until it answers
    Timer {
        id: _retry; interval: 3000; repeat: true; running: root.visible && !root.backendOk
        onTriggered: { root.backendOk = true; root.setTab(root.tab) }
    }
    // category shelves: one at a time, so as not to exceed iTunes' request limit
    Timer {
        id: _shelfTimer; interval: 2500; repeat: false
        property int shelf: 0
        readonly property var ids: [{ id: "1311", name: "Notizie" }, { id: "1303", name: "Commedia" }, { id: "1488", name: "True crime" }]
        onTriggered: {
            if (shelf >= ids.length) return
            var g = ids[shelf]
            root.api("/charts?genre=" + g.id, function(d) {
                var a = root.genreShelves.slice(); a.push({ id: g.id, name: g.name, items: d.items || [] }); root.genreShelves = a
            })
            shelf++; restart()
        }
    }
    // no network requests until the app is opened
    property bool _started: false
    onVisibleChanged: {
        if (!visible) return
        root.refreshState()
        if (!root._started) { root._started = true; root.setTab("home") }
        else if (root.tab === "home") root.loadHome()
    }
    Component.onCompleted: if (root.visible) Qt.callLater(function() { if (!root._started) { root._started = true; root.setTab("home") } })

    // ═════════ Componenti ═════════
    component Glyph: Canvas {
        id: _g
        property string kind: "play"
        property color col: Theme.textPrimary
        width: 24; height: 24
        onKindChanged: requestPaint()
        onColChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.clearRect(0, 0, width, height)
            var w = width, h = height
            c.fillStyle = col; c.strokeStyle = col; c.lineCap = "round"; c.lineJoin = "round"; c.lineWidth = Math.max(1.6, w * 0.09)
            function tri(x1, y1, x2, y2, x3, y3) { c.beginPath(); c.moveTo(x1, y1); c.lineTo(x2, y2); c.lineTo(x3, y3); c.closePath(); c.fill() }
            switch (kind) {
            case "play": tri(w * .3, h * .18, w * .82, h * .5, w * .3, h * .82); break
            case "pause":
                c.fillRect(w * .26, h * .2, w * .17, h * .6); c.fillRect(w * .57, h * .2, w * .17, h * .6); break
            case "next": tri(w * .2, h * .22, w * .64, h * .5, w * .2, h * .78); c.fillRect(w * .68, h * .22, w * .1, h * .56); break
            case "prev": tri(w * .8, h * .22, w * .36, h * .5, w * .8, h * .78); c.fillRect(w * .22, h * .22, w * .1, h * .56); break
            case "check": c.beginPath(); c.moveTo(w * .2, h * .53); c.lineTo(w * .42, h * .74); c.lineTo(w * .82, h * .28); c.stroke(); break
            case "plus": c.beginPath(); c.moveTo(w * .5, h * .2); c.lineTo(w * .5, h * .8); c.moveTo(w * .2, h * .5); c.lineTo(w * .8, h * .5); c.stroke(); break
            case "close": c.beginPath(); c.moveTo(w * .25, h * .25); c.lineTo(w * .75, h * .75); c.moveTo(w * .75, h * .25); c.lineTo(w * .25, h * .75); c.stroke(); break
            case "bookmark": c.beginPath(); c.moveTo(w * .3, h * .16); c.lineTo(w * .7, h * .16); c.lineTo(w * .7, h * .84); c.lineTo(w * .5, h * .68); c.lineTo(w * .3, h * .84); c.closePath(); c.stroke(); break
            case "bookmarkOn": c.beginPath(); c.moveTo(w * .3, h * .16); c.lineTo(w * .7, h * .16); c.lineTo(w * .7, h * .84); c.lineTo(w * .5, h * .68); c.lineTo(w * .3, h * .84); c.closePath(); c.fill(); break
            case "search": c.beginPath(); c.arc(w * .44, h * .44, w * .26, 0, Math.PI * 2); c.stroke(); c.beginPath(); c.moveTo(w * .64, h * .64); c.lineTo(w * .84, h * .84); c.stroke(); break
            case "queue": c.fillRect(w * .16, h * .24, w * .68, h * .09); c.fillRect(w * .16, h * .46, w * .68, h * .09); c.fillRect(w * .16, h * .68, w * .42, h * .09); break
            case "chevron": c.beginPath(); c.moveTo(w * .15, h * .3); c.lineTo(w * .5, h * .7); c.lineTo(w * .85, h * .3); c.stroke(); break
            case "mic":
                c.beginPath(); c.roundedRect(w * .38, h * .12, w * .24, h * .4, w * .12, w * .12); c.fill()
                c.beginPath(); c.arc(w * .5, h * .46, w * .22, 0.1 * Math.PI, 0.9 * Math.PI); c.stroke()
                c.beginPath(); c.moveTo(w * .5, h * .68); c.lineTo(w * .5, h * .85); c.moveTo(w * .36, h * .85); c.lineTo(w * .64, h * .85); c.stroke(); break
            case "back15": case "fwd30":
                var fw = kind === "fwd30"
                c.save(); if (!fw) { c.translate(w, 0); c.scale(-1, 1) }
                c.lineWidth = Math.max(1.5, w * 0.07)
                c.beginPath(); c.arc(w * .5, h * .554, w * .35, -1.111, 4.253, false); c.stroke()
                tri(w * .54, h * .24, w * .335, h * .095, w * .335, h * .385)
                c.restore()
                c.font = "bold " + Math.round(h * .38) + "px sans-serif"; c.textAlign = "center"; c.textBaseline = "middle"
                c.fillText(fw ? "30" : "15", w * .5, h * .575)
                break
            case "moon":
                c.beginPath(); c.moveTo(w * .62, h * .12)
                c.bezierCurveTo(w * .28, h * .16, w * .12, h * .50, w * .28, h * .74)
                c.bezierCurveTo(w * .44, h * .96, w * .80, h * .90, w * .90, h * .62)
                c.bezierCurveTo(w * .64, h * .76, w * .40, h * .52, w * .62, h * .12)
                c.closePath(); c.fill(); break
            }
        }
    }

    component Cover: Item {
        id: _cv
        property alias source: _img.source
        property real radius: 6
        property bool isCircle: false
        Rectangle {
            anchors.fill: parent; radius: _cv.radius
            gradient: Gradient {      // elegant light gray until the cover is ready
                GradientStop { position: 0.0; color: root.lightTheme ? "#EEEEF0" : "#4A4A4E" }
                GradientStop { position: 1.0; color: root.lightTheme ? "#DEDEE2" : "#36363A" }
            }
        }
        Image { id: _img; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; visible: false; asynchronous: true; smooth: true; mipmap: true; sourceSize: Qt.size(width * 2, height * 2) }
        Item {
            id: _mask; anchors.fill: parent; visible: false; layer.enabled: true; layer.smooth: true
            Rectangle { anchors.fill: parent; radius: _cv.radius; color: "white" }
        }
        MultiEffect {
            anchors.fill: _img; source: _img; maskEnabled: true; maskSource: _mask
            maskThresholdMin: 0.5; maskSpreadAtMin: 1.0; visible: _img.status === Image.Ready
        }
    }

    component SmallBtn: Item {
        id: _sb
        property string kind: "check"
        property bool on: false
        signal clicked()
        width: 44; height: 44
        Rectangle { anchors.centerIn: parent; width: 36; height: 36; radius: 18; color: _sbMA.pressed ? Theme.surfaceElevated : "transparent" }
        Glyph { anchors.centerIn: parent; width: 22; height: 22; kind: _sb.kind; col: _sb.on ? root.accent : root.iconColor }
        MouseArea { id: _sbMA; anchors.fill: parent; preventStealing: true; onClicked: _sb.clicked() }
    }

    component Pill: Rectangle {
        id: _pill
        property string label: ""
        property bool active: false
        signal clicked()
        height: 40; width: _pt.implicitWidth + 36; radius: 6
        color: active ? (root.lightTheme ? "#444444" : "#FFFFFF") : (root.lightTheme ? "#EAEAEA" : "#333333")
        Text { id: _pt; anchors.centerIn: parent; text: _pill.label; font.pixelSize: 15; font.weight: Font.Medium
               color: _pill.active ? (root.lightTheme ? "#FFFFFF" : "#000000") : (root.lightTheme ? "#555555" : Theme.textPrimary) }
        MouseArea { anchors.fill: parent; preventStealing: true; onClicked: _pill.clicked() }
    }

    component SectionTitle: Item {
        id: _st
        property string text: ""
        property bool more: false
        signal clicked()
        width: parent ? parent.width : 400; height: 44
        Text { x: 20; anchors.verticalCenter: parent.verticalCenter; text: _st.text; color: Theme.textPrimary; font.pixelSize: 20; font.weight: Font.Bold }
        Glyph { visible: _st.more; x: 20 + _tt.implicitWidth + 10; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; rotation: -90; kind: "chevron"; col: root.iconColor }
        Text { id: _tt; visible: false; text: _st.text; font.pixelSize: 20; font.weight: Font.Bold }
        MouseArea { anchors.fill: parent; enabled: _st.more; onClicked: _st.clicked() }
    }

    // Podcast card (square cover + title + author), with optional chart number
    component ShowCard: Item {
        id: _sc
        property var show: ({})
        property int rank: 0
        property real cw: 132
        width: cw; height: cw + 56
        Cover { id: _scc; width: parent.width; height: parent.width; radius: 8; source: _sc.show.cover || "" }
        Rectangle {
            visible: _sc.rank > 0; x: 6; y: 6; width: _rk.implicitWidth + 12; height: 22; radius: 11; color: "#CC000000"
            Text { id: _rk; anchors.centerIn: parent; text: _sc.rank; color: "white"; font.pixelSize: 13; font.weight: Font.Bold }
        }
        Text { y: _scc.height + 6; width: parent.width; text: _sc.show.title || ""; color: Theme.textPrimary; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight; maximumLineCount: 1 }
        Text { y: _scc.height + 26; width: parent.width; text: _sc.show.author || ""; color: Theme.textSecondary; font.pixelSize: 12; elide: Text.ElideRight; maximumLineCount: 1 }
        MouseArea { anchors.fill: parent; onClicked: root.openShow(_sc.show) }
    }

    // Episode row
    // Large row for the full episode list (cover, "3 HOURS AGO", title, duration)
    component EpisodeBig: Item {
        id: _eb
        property var ep: ({})
        readonly property bool cur: root.isCurrent(ep)
        readonly property bool curPlaying: cur && root.pState.playing
        width: parent ? parent.width : 600; height: 126
        Rectangle {
            x: 14; width: parent.width - 28; height: 114; radius: 10; anchors.verticalCenter: parent.verticalCenter
            color: (_ebMA.pressed || _eb.cur) ? Theme.surfaceElevated : Theme.surface
            Cover { id: _ebc; x: 10; anchors.verticalCenter: parent.verticalCenter; width: 94; height: 94; radius: 8; source: _eb.ep.cover || "" }
            Rectangle { visible: _eb.cur; anchors.fill: _ebc; radius: 8; color: "#88000000"
                        Glyph { anchors.centerIn: parent; width: 28; height: 28; kind: _eb.curPlaying ? "pause" : "play"; col: "white" } }
            Column {
                x: 10 + 94 + 16; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x - 150; spacing: 3
                Text { width: parent.width; elide: Text.ElideRight; font.pixelSize: 13; font.weight: Font.Bold; font.letterSpacing: 0.4; color: Theme.textSecondary
                       text: root.relTime(_eb.ep) }
                Text { width: parent.width; text: _eb.ep.title || ""; maximumLineCount: 2; wrapMode: Text.WordWrap; elide: Text.ElideRight
                       color: _eb.cur ? root.accent : (_eb.ep.done ? Theme.textSecondary : Theme.textPrimary); font.pixelSize: 19; font.weight: Font.Bold }
                Item {
                    width: parent.width; height: 16
                    Text { id: _ebd; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 14; color: Theme.textSecondary
                           text: _eb.ep.done ? qsTr("Played") : ((_eb.ep.pos > 15 && _eb.ep.dur > 0) ? root.fmtMin(_eb.ep.dur - _eb.ep.pos) + " rimanenti" : root.fmtMin(_eb.ep.dur)) }
                    Rectangle { visible: _eb.ep.pos > 15 && !_eb.ep.done && _eb.ep.dur > 0; x: _ebd.implicitWidth + 10; anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(90, parent.width - x); height: 4; radius: 2; color: Theme.surfaceElevated
                                Rectangle { width: parent.width * Math.min(1, _eb.ep.pos / Math.max(1, _eb.ep.dur)); height: parent.height; radius: 2; color: root.accent } }
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 0
                SmallBtn { kind: _eb.ep.saved ? "bookmarkOn" : "bookmark"; on: !!_eb.ep.saved; onClicked: root.toggleSaved(_eb.ep) }
                SmallBtn { kind: "check"; on: !!_eb.ep.done; onClicked: root.toggleDone(_eb.ep) }
                Item {
                    width: 46; height: 46; anchors.verticalCenter: parent.verticalCenter
                    Glyph { anchors.centerIn: parent; width: 24; height: 24; kind: _eb.curPlaying ? "pause" : "play"; col: _ebPl.pressed ? Theme.textSecondary : Theme.textPrimary }
                    MouseArea { id: _ebPl; anchors.fill: parent; preventStealing: true; onClicked: { if (_eb.cur) root.togglePlay(); else root.playEp(_eb.ep) } }
                }
            }
            MouseArea { id: _ebMA; anchors.fill: parent; z: -1; onClicked: { if (_eb.cur) root.togglePlay(); else root.playEp(_eb.ep) } }
        }
    }

    component EpisodeRow: Item {
        id: _er
        property var ep: ({})
        property bool showPodcast: true
        property int rank: 0
        readonly property bool cur: root.isCurrent(ep)
        readonly property bool curPlaying: cur && root.pState.playing
        width: parent ? parent.width : 600; height: 84

        Rectangle {
            x: 14; width: parent.width - 28; height: 76; radius: 8; anchors.verticalCenter: parent.verticalCenter
            color: (_erMA.pressed || _er.cur) ? Theme.surfaceElevated : "transparent"

            Text { visible: _er.rank > 0; x: 8; anchors.verticalCenter: parent.verticalCenter; width: 30; horizontalAlignment: Text.AlignHCenter
                   text: _er.rank; color: Theme.textSecondary; font.pixelSize: 16; font.weight: Font.DemiBold }
            Cover { id: _erc; x: _er.rank > 0 ? 42 : 10; anchors.verticalCenter: parent.verticalCenter; width: 56; height: 56; radius: 6; source: _er.ep.cover || "" }
            Rectangle {   // "now playing" indicator on the cover
                visible: _er.cur; anchors.fill: _erc; radius: 6; color: "#88000000"
                Glyph { anchors.centerIn: parent; width: 24; height: 24; kind: _er.curPlaying ? "pause" : "play"; col: "white" }
            }
            Column {
                x: _erc.x + 56 + 14; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - 150; spacing: 2
                Text { width: parent.width; elide: Text.ElideRight; font.pixelSize: 12; font.weight: Font.Medium; color: Theme.textSecondary
                       text: { var a = []; if (_er.showPodcast && _er.ep.podcast) a.push(_er.ep.podcast); if (_er.ep.dateLabel) a.push(_er.ep.dateLabel); return a.join("  ·  ") } }
                Text { width: parent.width; text: _er.ep.title || ""; maximumLineCount: 2; wrapMode: Text.WordWrap; elide: Text.ElideRight
                       color: _er.cur ? root.accent : (_er.ep.done ? Theme.textSecondary : Theme.textPrimary); font.pixelSize: 16; font.weight: Font.DemiBold }
                Item {
                    width: parent.width; height: 14
                    Text { id: _durT; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12; color: Theme.textSecondary
                           text: _er.ep.done ? qsTr("Played") : ((_er.ep.pos > 15 && _er.ep.dur > 0) ? root.fmtMin(_er.ep.dur - _er.ep.pos) + " rimanenti" : root.fmtMin(_er.ep.dur)) }
                    Rectangle { visible: _er.ep.pos > 15 && !_er.ep.done && _er.ep.dur > 0; x: _durT.implicitWidth + 10; anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(90, parent.width - x); height: 4; radius: 2; color: Theme.surfaceElevated
                                Rectangle { width: parent.width * Math.min(1, _er.ep.pos / Math.max(1, _er.ep.dur)); height: parent.height; radius: 2; color: root.accent } }
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; spacing: 0
                SmallBtn { kind: _er.ep.saved ? "bookmarkOn" : "bookmark"; on: !!_er.ep.saved; onClicked: root.toggleSaved(_er.ep) }
                SmallBtn { kind: "check"; on: !!_er.ep.done; onClicked: root.toggleDone(_er.ep) }
                Item {
                    width: 44; height: 44; anchors.verticalCenter: parent.verticalCenter
                    Glyph { anchors.centerIn: parent; width: 24; height: 24; kind: _er.curPlaying ? "pause" : "play"; col: _plMA.pressed ? Theme.textSecondary : Theme.textPrimary }
                    MouseArea { id: _plMA; anchors.fill: parent; preventStealing: true
                                onClicked: { if (_er.cur) root.togglePlay(); else root.playEp(_er.ep) } }
                }
            }
            MouseArea { id: _erMA; anchors.fill: parent; z: -1; onClicked: { if (_er.cur) root.togglePlay(); else root.playEp(_er.ep) } }
        }
    }

    // Average color of a cover (for the background of the "Up next" cards)
    component DomColor: Item {
        id: _dc
        property string source: ""
        property color base: "#3A3A3D"                       // until the cover is ready
        readonly property color shade: Qt.hsla(base.hslHue < 0 ? 0 : base.hslHue, Math.min(0.7, base.hslSaturation), Math.min(0.40, Math.max(0.14, base.hslLightness)), 1)
        readonly property color tint: Qt.hsla(base.hslHue < 0 ? 0 : base.hslHue, Math.min(0.9, base.hslSaturation + 0.1), 0.80, 1)
        width: 8; height: 8; opacity: 0.01
        Canvas {
            id: _dcv
            width: 8; height: 8; renderTarget: Canvas.Image; renderStrategy: Canvas.Immediate
            onImageLoaded: requestPaint()
            onPaint: {
                if (_dc.source === "" || !isImageLoaded(_dc.source)) return
                var c = getContext("2d")
                c.clearRect(0, 0, 8, 8)
                c.drawImage(_dc.source, 0, 0, 8, 8)
                var d = c.getImageData(0, 0, 8, 8).data, r = 0, g = 0, b = 0, w = 0
                for (var i = 0; i < d.length; i += 4) {
                    var mx = Math.max(d[i], d[i + 1], d[i + 2]), mn = Math.min(d[i], d[i + 1], d[i + 2])
                    var k = 1 + (mx - mn) / 40               // vivid colors weigh more than grays
                    r += d[i] * k; g += d[i + 1] * k; b += d[i + 2] * k; w += k
                }
                if (w > 0) _dc.base = Qt.rgba(r / w / 255, g / w / 255, b / w / 255, 1)
            }
        }
        function load() { if (source !== "") _dcv.loadImage(source) }
        onSourceChanged: load()
        Component.onCompleted: load()
    }

    // Vertical "Up next" card: cover, date, title, time left and bar with the podcast name
    component EpisodeCard: Item {
        id: _ec
        property var ep: ({})
        readonly property bool cur: root.isCurrent(ep)
        readonly property bool curPlaying: cur && root.pState.playing
        width: 190; height: 318
        DomColor { id: _ecd; source: _ec.ep.cover || "" }
        Rectangle {
            anchors.fill: parent; radius: 10; clip: true
            color: _ecd.shade
            Behavior on color { ColorAnimation { duration: 250 } }
            // card body: tap = play / pause
            MouseArea { id: _ecMA; anchors.fill: parent; onClicked: { if (_ec.cur) root.togglePlay(); else root.playEp(_ec.ep) } }
            Rectangle { anchors.fill: parent; color: "white"; opacity: _ecMA.pressed ? 0.10 : 0 }

            Cover { id: _ecc; x: 28; y: 18; width: parent.width - 56; height: width; radius: 8; source: _ec.ep.cover || "" }
            Rectangle {
                visible: _ec.cur; anchors.fill: _ecc; radius: 8; color: "#66000000"
                Glyph { anchors.centerIn: parent; width: 34; height: 34; kind: _ec.curPlaying ? "pause" : "play"; col: "white" }
            }
            Text { x: 16; y: _ecc.y + _ecc.height + 12; width: parent.width - 32; text: (_ec.ep.dateLabel || "").toUpperCase(); color: _ecd.tint; font.pixelSize: 12; font.weight: Font.Medium; elide: Text.ElideRight }
            Text { x: 16; y: _ecc.y + _ecc.height + 30; width: parent.width - 32; height: 58; text: _ec.ep.title || ""; color: "white"; font.pixelSize: 15; font.weight: Font.DemiBold
                   wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight; lineHeight: 1.05 }
            Row {
                x: 16; y: parent.height - 40 - 28; spacing: 8; height: 16
                Rectangle { visible: _ec.ep.pos > 15 && _ec.ep.dur > 0; width: 34; height: 3; radius: 1.5; anchors.verticalCenter: parent.verticalCenter; color: "#55FFFFFF"
                            Rectangle { width: parent.width * Math.min(1, _ec.ep.pos / Math.max(1, _ec.ep.dur)); height: parent.height; radius: 1.5; color: "white" } }
                Text { anchors.verticalCenter: parent.verticalCenter; color: _ecd.tint; font.pixelSize: 12
                       text: (_ec.ep.pos > 15 && _ec.ep.dur > 0) ? root.fmtLeft(_ec.ep.dur - _ec.ep.pos) : root.fmtMin(_ec.ep.dur) }
            }
            // bottom bar: podcast name → opens the podcast page
            Rectangle {
                id: _ecf; x: 0; y: parent.height - 40; width: parent.width; height: 40; color: "#33000000"
                Rectangle { anchors.fill: parent; color: "white"; opacity: _ecfMA.pressed ? 0.12 : 0 }
                Text { x: 16; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52; text: _ec.ep.podcast || ""; color: "white"; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight }
                Glyph { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; rotation: -90; kind: "chevron"; col: "white" }
                MouseArea { id: _ecfMA; anchors.fill: parent; onClicked: root.openShow({ feed: _ec.ep.feed, title: _ec.ep.podcast, cover: _ec.ep.cover }) }
            }
        }
    }

    // Compact tile for "Latest episodes" (3 columns): cover, date, title, duration
    component EpisodeTile: Item {
        id: _et
        property var ep: ({})
        readonly property bool cur: root.isCurrent(ep)
        readonly property bool curPlaying: cur && root.pState.playing
        height: 104
        Rectangle {
            x: 6; y: 5; width: parent.width - 12; height: parent.height - 10; radius: 8
            color: (_etMA.pressed || _et.cur) ? Theme.surfaceElevated : Theme.surface
            Cover { id: _etc; x: 10; anchors.verticalCenter: parent.verticalCenter; width: 78; height: 78; radius: 6; source: _et.ep.cover || "" }
            Rectangle { visible: _et.cur; anchors.fill: _etc; radius: 6; color: "#77000000"
                        Glyph { anchors.centerIn: parent; width: 26; height: 26; kind: _et.curPlaying ? "pause" : "play"; col: "white" } }
            Column {
                x: 10 + 78 + 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x - 10; spacing: 2
                Text { width: parent.width; elide: Text.ElideRight; font.pixelSize: 12; font.weight: Font.Medium; color: Theme.textSecondary
                       text: ((_et.ep.dateLabel || "").toUpperCase()) }
                Text { width: parent.width; text: _et.ep.title || ""; maximumLineCount: 2; wrapMode: Text.WordWrap; elide: Text.ElideRight
                       color: _et.cur ? root.accent : (_et.ep.done ? Theme.textSecondary : Theme.textPrimary); font.pixelSize: 15; font.weight: Font.DemiBold }
                Text { width: parent.width; elide: Text.ElideRight; font.pixelSize: 12; color: Theme.textSecondary
                       text: _et.ep.done ? qsTr("Played") : ((_et.ep.pos > 15 && _et.ep.dur > 0) ? root.fmtLeft(_et.ep.dur - _et.ep.pos) : root.fmtMin(_et.ep.dur)) }
            }
            MouseArea { id: _etMA; anchors.fill: parent; z: -1; onClicked: { if (_et.cur) root.togglePlay(); else root.playEp(_et.ep) } }
        }
    }

    // Wide card (Explore: "News of the day")
    component WideTile: Item {
        id: _wt
        property var show: ({})
        width: 228; height: 128
        Cover { anchors.fill: parent; radius: 8; source: _wt.show.cover || "" }
        Rectangle { anchors.fill: parent; radius: 8; color: "#22000000"; visible: _wtMA.pressed }
        MouseArea { id: _wtMA; anchors.fill: parent; onClicked: root.openShow(_wt.show) }
    }
    // Explore shelf: title (with arrow toward the category) and horizontal scrolling
    component BrowseShelf: Column {
        id: _bs
        property var sh: ({})
        width: parent ? parent.width : 600
        visible: !!(sh.items && sh.items.length > 0)
        SectionTitle { text: _bs.sh.title || ""; more: !!_bs.sh.genre; onClicked: root.openCategory(_bs.sh.genre) }
        ListView {
            visible: _bs.sh.kind !== "wide"
            width: parent.width; height: visible ? 188 : 0; orientation: ListView.Horizontal; spacing: 14; leftMargin: 20; rightMargin: 20; clip: true
            model: _bs.sh.kind !== "wide" ? _bs.sh.items : []
            delegate: ShowCard { show: modelData }
        }
        ListView {
            visible: _bs.sh.kind === "wide"
            width: parent.width; height: visible ? 128 : 0; orientation: ListView.Horizontal; spacing: 14; leftMargin: 20; rightMargin: 20; clip: true
            model: _bs.sh.kind === "wide" ? _bs.sh.items : []
            delegate: WideTile { show: modelData }
        }
        Item { width: 1; height: 12 }
    }

    component Shelf: Column {
        id: _sh
        property string title: ""
        property var items: []
        property bool ranked: false
        width: parent ? parent.width : 600
        visible: items && items.length > 0
        SectionTitle { text: _sh.title }
        ListView {
            width: parent.width; height: 188; orientation: ListView.Horizontal; spacing: 14; leftMargin: 20; rightMargin: 20; clip: true
            model: _sh.items
            delegate: ShowCard { show: modelData; rank: _sh.ranked ? index + 1 : 0 }
        }
        Item { width: 1; height: 10 }
    }

    // ═════════ INTESTAZIONE ═════════
    Rectangle {
        id: _hdr; width: parent.width; height: root.headerH; z: 100; color: Theme.bg
        Row {
            anchors.left: parent.left; anchors.leftMargin: 20; y: (32 * root.u - height) / 2; spacing: 18

            // 1. App icon: opens the menu to switch music app
            Item {
                id: _appSwitcher; width: 29; height: 34; anchors.verticalCenter: parent.verticalCenter
                Image { source: "qrc:/VoltaApp/icons/podcast.svg"; sourceSize: Qt.size(58, 58); width: 29; height: 29; fillMode: Image.PreserveAspectFit; anchors.verticalCenter: parent.verticalCenter }
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.appMenuOpen = !root.appMenuOpen }
            }
            Rectangle { width: 1; height: 21; color: root.dividerColor; anchors.verticalCenter: parent.verticalCenter }
            // 2. Search
            Item {
                width: 27; height: 27; anchors.verticalCenter: parent.verticalCenter
                Glyph { anchors.fill: parent; kind: "search"; col: root.lightTheme ? "#141414" : "#FFFFFF" }
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.openSearch() }
            }
            Rectangle { width: 1; height: 21; color: root.dividerColor; anchors.verticalCenter: parent.verticalCenter }
            // 3. Coda / lettore
            Item {
                width: 27; height: 27; anchors.verticalCenter: parent.verticalCenter
                Canvas {
                    id: _qIcon
                    anchors.centerIn: parent; width: 22; height: 19.5
                    property color col: root.iconColor
                    onColChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d"); c.clearRect(0, 0, width, height);
                        var k = width / 178;
                        c.save(); c.scale(k, k); c.translate(-19, -53);
                        c.fillStyle = col; c.strokeStyle = col; c.lineWidth = 10; c.lineJoin = "round"; c.lineCap = "round";
                        c.beginPath(); c.moveTo(29, 58); c.lineTo(63, 78); c.lineTo(29, 98); c.closePath(); c.fill(); c.stroke();
                        c.beginPath(); c.roundedRect(84, 66, 108, 24, 12, 12); c.fill();
                        c.beginPath(); c.roundedRect(24, 122, 168, 24, 12, 12); c.fill();
                        c.beginPath(); c.roundedRect(24, 182, 168, 24, 12, 12); c.fill();
                        c.restore();
                    }
                }
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: { root.playerOpen = !root.playerOpen; root.searchOpen = false; root.detailOpen = false } }
            }
            Rectangle { width: 1; height: 21; color: root.dividerColor; anchors.verticalCenter: parent.verticalCenter }
            // 4. Back / Forward (screen history): two rounded gray buttons
            Row {
                spacing: 16; anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    width: 46; height: 34; radius: 6
                    color: root.lightTheme ? "#E7E7E7" : "#26FFFFFF"
                    Canvas {
                        id: _navBackIcon
                        anchors.centerIn: parent; width: 9; height: 15
                        opacity: root.navBackCount > 0 ? 1.0 : 0.4
                        property color col: root.lightTheme ? "#7A7A7A" : "#B5B5B5"
                        onColChanged: requestPaint()
                        onPaint: {
                            var c = getContext("2d"); c.clearRect(0, 0, width, height);
                            c.strokeStyle = col; c.lineWidth = 1.6; c.lineCap = "round"; c.lineJoin = "round";
                            c.beginPath(); c.moveTo(width - 1.5, 1.5); c.lineTo(1.5, height / 2); c.lineTo(width - 1.5, height - 1.5); c.stroke();
                        }
                    }
                    MouseArea { anchors.fill: parent; enabled: root.navBackCount > 0; onClicked: root.navBack() }
                }
                Rectangle {
                    width: 46; height: 34; radius: 6
                    color: root.lightTheme ? "#E7E7E7" : "#26FFFFFF"
                    Canvas {
                        id: _navFwdIcon
                        anchors.centerIn: parent; width: 9; height: 15
                        opacity: root.navFwdCount > 0 ? 1.0 : 0.4
                        property color col: root.lightTheme ? "#7A7A7A" : "#B5B5B5"
                        onColChanged: requestPaint()
                        onPaint: {
                            var c = getContext("2d"); c.clearRect(0, 0, width, height);
                            c.strokeStyle = col; c.lineWidth = 1.6; c.lineCap = "round"; c.lineJoin = "round";
                            c.beginPath(); c.moveTo(1.5, 1.5); c.lineTo(width - 1.5, height / 2); c.lineTo(1.5, height - 1.5); c.stroke();
                        }
                    }
                    MouseArea { anchors.fill: parent; enabled: root.navFwdCount > 0; onClicked: root.navForward() }
                }
            }
            Rectangle { width: 1; height: 21; color: root.dividerColor; anchors.verticalCenter: parent.verticalCenter }
            // 5. Tabs
            Row {
                spacing: 20; anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: [{ id: "home", text: qsTr("Home") }, { id: "browse", text: qsTr("Explore") }, { id: "charts", text: qsTr("Charts") }, { id: "library", text: qsTr("Library") }]
                    Item {
                        width: _tl.implicitWidth; height: 48
                        readonly property bool isSel: root.tab === modelData.id && !root.detailOpen && !root.searchOpen && !root.playerOpen
                        Text { id: _tl; anchors.centerIn: parent; text: modelData.text; color: parent.isSel ? root.selectedTextColor : root.iconColor; font.pixelSize: 20; font.weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; onClicked: root.setTab(modelData.id) }
                    }
                }
            }
        }
    }

    // ═════════ TAB CONTENT ═════════
    Item {
        id: _body
        anchors.top: _hdr.bottom; anchors.bottom: parent.bottom; width: parent.width

        // Service unreachable
        Column {
            visible: !root.backendOk; anchors.centerIn: parent; spacing: 10; z: 5
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Podcast service starting…"); color: Theme.textPrimary; font.pixelSize: 20; font.weight: Font.DemiBold }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Retrying by itself every few seconds."); color: Theme.textSecondary; font.pixelSize: 14 }
        }

        // ── HOME ──
        PullRefresh { target: _homeFlick; onRefresh: root.loadHome() }
        Flickable {
            id: _homeFlick
            anchors.fill: parent; visible: root.tab === "home"; clip: true
            contentWidth: width; contentHeight: _homeCol.height + 40; boundsBehavior: Flickable.DragOverBounds
            Column {
                id: _homeCol; width: parent.width
                Column {
                    width: parent.width; visible: root.continueList.length + root.newList.length > 0
                    SectionTitle { text: qsTr("Up next") }
                    ListView {
                        id: _upNext
                        width: parent.width; height: 332; orientation: ListView.Horizontal; spacing: 14; leftMargin: 20; rightMargin: 20; clip: true
                        model: {
                            var a = root.continueList.slice(), seen = {}
                            for (var i = 0; i < a.length; i++) seen[a[i].guid] = 1
                            for (var j = 0; j < root.newList.length && a.length < 14; j++) if (!seen[root.newList[j].guid]) a.push(root.newList[j])
                            return a
                        }
                        delegate: EpisodeCard { ep: modelData }
                    }
                    Item { width: 1; height: 10 }
                }
                Column {
                    width: parent.width; visible: newModel.count > 0
                    SectionTitle { text: qsTr("Latest episodes"); more: true; onClicked: root.setTab("news") }
                    Grid {
                        id: _latestGrid
                        x: 14; width: parent.width - 28
                        columns: Math.max(2, Math.floor(width / 420))
                        Repeater { model: Math.min(_latestGrid.columns * 2, newModel.count)
                                   EpisodeTile { width: _latestGrid.width / _latestGrid.columns; ep: root.epOf(newModel.get(index)) } }
                    }
                    Item { width: 1; height: 10 }
                }
                Item { width: 1; height: 14; visible: root.subsList.length === 0 }
                Shelf { title: qsTr("Most listened"); items: root.topShows; ranked: true }
                Repeater { model: root.genreShelves; delegate: Shelf { title: modelData.name; items: modelData.items } }
            }
        }

        // ── ESPLORA ──
        PullRefresh { target: _browseFlick; onRefresh: root.loadHome() }
        Flickable {
            id: _browseFlick
            anchors.fill: parent; visible: root.tab === "browse"; clip: true
            contentWidth: width; contentHeight: _browseCol.height + 40; boundsBehavior: Flickable.DragOverBounds
            Column {
                id: _browseCol; width: parent.width
                Item { width: 1; height: 16 }
                // featured: three big ones, with label and title above
                Row {
                    id: _heroRow
                    x: 20; width: parent.width - 40; spacing: 14
                    visible: root.browseData.hero.length > 0
                    Repeater {
                        model: root.browseData.hero
                        Item {
                            width: (_heroRow.width - 28) / 3; height: 60 + width * 0.56
                            Column {
                                id: _hc; width: parent.width; spacing: 2
                                Text { width: parent.width; elide: Text.ElideRight; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 0.6; color: Theme.textSecondary
                                       text: (qsTr("Featured · ") + (modelData.label || "")).toUpperCase() }
                                Text { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; font.pixelSize: 16; font.weight: Font.Bold; color: Theme.textPrimary
                                       text: modelData.show.title || "" }
                                Text { width: parent.width; elide: Text.ElideRight; maximumLineCount: 1; font.pixelSize: 13; color: root.accent
                                       text: modelData.show.author || "" }
                            }
                            Cover { y: 60; width: parent.width; height: parent.width * 0.56; radius: 10; source: modelData.show.cover || "" }
                            Rectangle { y: 60; width: parent.width; height: parent.width * 0.56; radius: 10; color: "#22000000"; visible: _hMA.pressed }
                            MouseArea { id: _hMA; anchors.fill: parent; onClicked: root.openShow(modelData.show) }
                        }
                    }
                }
                Item { width: 1; height: 16; visible: root.browseData.hero.length > 0 }
                Repeater { model: root.browseData.shelves; delegate: BrowseShelf { sh: modelData } }
                Column {
                    width: parent.width; visible: browseEpModel.count > 0
                    SectionTitle { text: qsTr("Featured episodes") }
                    Grid {
                        id: _brGrid
                        x: 14; width: parent.width - 28
                        columns: Math.max(2, Math.floor(width / 420))
                        Repeater { model: browseEpModel.count
                                   EpisodeTile { width: _brGrid.width / _brGrid.columns; ep: root.epOf(browseEpModel.get(index)) } }
                    }
                    Item { width: 1; height: 12 }
                }
                Column {
                    width: parent.width; visible: root.browseGenres.length > 0
                    SectionTitle { text: qsTr("More categories to explore") }
                    ListView {
                        width: parent.width; height: 92; orientation: ListView.Horizontal; spacing: 12; leftMargin: 20; rightMargin: 20; clip: true
                        model: root.browseGenres
                        delegate: Rectangle {
                            width: 190; height: 84; radius: 10
                            color: modelData.color || "#6D28D9"
                            Text { anchors.fill: parent; anchors.margins: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; wrapMode: Text.WordWrap
                                   text: modelData.name; color: "white"; font.pixelSize: 18; font.weight: Font.DemiBold }
                            Rectangle { anchors.fill: parent; radius: 10; color: "#22000000"; visible: _catMA.pressed }
                            MouseArea { id: _catMA; anchors.fill: parent; onClicked: root.openCategory(modelData.id) }
                        }
                    }
                }
                Item { width: 1; height: 20 }
            }
        }

        // ── NEW ──
        ListView {
            anchors.fill: parent; visible: root.tab === "news"; clip: true; model: newModel; boundsBehavior: Flickable.StopAtBounds
            header: Item { width: 1; height: 56
                Text { x: 20; anchors.verticalCenter: parent.verticalCenter; text: qsTr("News from your podcasts"); color: Theme.textPrimary; font.pixelSize: 20; font.weight: Font.Bold } }
            delegate: EpisodeRow { ep: root.epOf(model) }
            footer: Item { width: 1; height: 40 }
            Text { visible: newModel.count === 0 && root.backendOk; anchors.centerIn: parent; width: parent.width - 80; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                   color: Theme.textSecondary; font.pixelSize: 16
                   text: root.subsList.length === 0 ? qsTr("You're not subscribed to any podcast.\nFind one and tap ✓ to subscribe.") : qsTr("No new episodes to listen to.") }
        }

        // ── CLASSIFICHE ──
        PullRefresh { target: _chartFlick; onRefresh: root.loadHome() }
        Flickable {
            id: _chartFlick
            anchors.fill: parent; visible: root.tab === "charts"; clip: true
            contentWidth: width; contentHeight: _chartCol.height + 40; boundsBehavior: Flickable.DragOverBounds
            Column {
                id: _chartCol; width: parent.width
                Flickable {
                    width: parent.width; height: 62; contentWidth: _pillRow.width + 40; contentHeight: height; clip: true; boundsBehavior: Flickable.StopAtBounds
                    Row {
                        id: _pillRow; x: 20; y: 11; spacing: 10
                        Pill { label: qsTr("All categories"); active: root.chartGenre === ""; onClicked: { root.chartGenre = ""; root.loadCharts() } }
                        Repeater { model: root.genres
                                   Pill { label: modelData.name; active: root.chartGenre === modelData.id; onClicked: { root.chartGenre = modelData.id; root.loadCharts() } } }
                    }
                }
                SectionTitle { text: qsTr("Top podcasts") }
                Item { width: parent.width; height: root.chartsBusy ? 60 : 0; visible: root.chartsBusy
                       Text { anchors.centerIn: parent; text: qsTr("Loading the chart…"); color: Theme.textSecondary; font.pixelSize: 15 } }
                Flow {
                    id: _chartFlow
                    visible: !root.chartsBusy && root.chartShows.length > 0
                    x: 20; width: parent.width - 40; spacing: 14
                    readonly property int cols: Math.max(3, Math.floor((width + 14) / 154))
                    Repeater { model: root.chartShows
                               ShowCard { cw: (_chartFlow.width - 14 * (_chartFlow.cols - 1)) / _chartFlow.cols; show: modelData; rank: index + 1 } }
                }
                Text { visible: !root.chartsBusy && root.chartShows.length === 0; x: 20; text: qsTr("Chart unavailable at the moment."); color: Theme.textSecondary; font.pixelSize: 15; height: 40 }
                Item { width: 1; height: 8 }
                SectionTitle { text: qsTr("Top episodes") }
                Item { width: parent.width; height: root.chartEpsBusy ? 60 : 0; visible: root.chartEpsBusy
                       Text { anchors.centerIn: parent; text: qsTr("Loading episodes…"); color: Theme.textSecondary; font.pixelSize: 15 } }
                Grid {
                    id: _epGrid
                    columns: width > 1100 ? 2 : 1; width: parent.width
                    Repeater { model: chartEpModel; delegate: EpisodeRow { width: _epGrid.width / _epGrid.columns; ep: root.epOf(model); rank: index + 1 } }
                }
            }
        }

        // ── LIBRERIA ──
        Item {
            id: _lib
            anchors.fill: parent; visible: root.tab === "library"
            Row {
                id: _libTabs; x: 40; y: 10; spacing: 14; height: 40
                Repeater {
                    model: [{ id: "shows", t: "Podcast" }, { id: "saved", t: qsTr("Saved") }, { id: "history", t: qsTr("History") }]
                    Pill { width: (_lib.width - 80 - 28) / 3; label: modelData.t; active: root.libTab === modelData.id; onClicked: { root.libTab = modelData.id; root.loadLibrary() } }
                }
            }
            Flickable {
                visible: root.libTab === "shows"
                anchors.top: _libTabs.bottom; anchors.topMargin: 12; anchors.bottom: parent.bottom; width: parent.width; clip: true
                contentWidth: width; contentHeight: _libFlow.height + 40; boundsBehavior: Flickable.StopAtBounds
                Flow {
                    id: _libFlow; x: 20; width: parent.width - 40; spacing: 14
                    readonly property int cols: Math.max(3, Math.floor((width + 14) / 190))
                    Repeater { model: root.subsList
                               ShowCard { cw: (_libFlow.width - 14 * (_libFlow.cols - 1)) / _libFlow.cols; show: ({ id: modelData.id, title: modelData.title, author: modelData.author, cover: modelData.cover, feed: modelData.feed }) } }
                }
                Text { visible: root.subsList.length === 0; anchors.horizontalCenter: parent.horizontalCenter; y: 80; width: parent.width - 80; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                       color: Theme.textSecondary; font.pixelSize: 16; text: qsTr("The podcasts you subscribe to will appear here.") }
            }
            ListView {
                visible: root.libTab === "saved"
                anchors.top: _libTabs.bottom; anchors.topMargin: 8; anchors.bottom: parent.bottom; width: parent.width; clip: true; model: savedModel; boundsBehavior: Flickable.StopAtBounds
                delegate: EpisodeRow { ep: root.epOf(model) }
                Text { visible: savedModel.count === 0; anchors.horizontalCenter: parent.horizontalCenter; y: 80; width: parent.width - 80; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                       color: Theme.textSecondary; font.pixelSize: 16; text: qsTr("Episodes you bookmark appear here.") }
            }
            ListView {
                visible: root.libTab === "history"
                anchors.top: _libTabs.bottom; anchors.topMargin: 8; anchors.bottom: parent.bottom; width: parent.width; clip: true; model: historyModel; boundsBehavior: Flickable.StopAtBounds
                delegate: EpisodeRow { ep: root.epOf(model) }
                Text { visible: historyModel.count === 0; anchors.horizontalCenter: parent.horizontalCenter; y: 80; width: parent.width - 80; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                       color: Theme.textSecondary; font.pixelSize: 16; text: qsTr("Episodes you listen to appear here.") }
            }
        }
    }

    // ═════════ PAGINA CATEGORIA (z=50) ═════════
    Rectangle {
        id: _catPage
        visible: root.categoryOpen; z: 50; color: Theme.bg
        anchors.top: _hdr.bottom; anchors.bottom: parent.bottom; width: parent.width
        MouseArea { anchors.fill: parent }
        Flickable {
            anchors.fill: parent; clip: true; contentWidth: width; contentHeight: _catCol.height + 40; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: _catCol; width: parent.width
                Column {
                    x: 20; width: parent.width - 40; topPadding: 14; bottomPadding: 10; spacing: 0
                    Text { text: qsTr("CATEGORY"); color: Theme.textSecondary; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                    Text { text: root.category.name; color: Theme.textPrimary; font.pixelSize: 30; font.weight: Font.Bold }
                }
                Item { width: parent.width; height: root.catBusy && root.catData.all.length === 0 ? 80 : 0; visible: height > 0
                       Text { anchors.centerIn: parent; text: qsTr("Loading the category…"); color: Theme.textSecondary; font.pixelSize: 15 } }
                Shelf { title: qsTr("Most listened"); items: root.catData.top; ranked: true }
                Column {
                    width: parent.width; visible: catEpModel.count > 0
                    SectionTitle { text: qsTr("Latest episodes") }
                    Grid {
                        id: _catGrid
                        x: 14; width: parent.width - 28
                        columns: Math.max(2, Math.floor(width / 420))
                        Repeater { model: catEpModel.count
                                   EpisodeTile { width: _catGrid.width / _catGrid.columns; ep: root.epOf(catEpModel.get(index)) } }
                    }
                    Item { width: 1; height: 12 }
                }
                Shelf { title: qsTr("To discover"); items: root.catData.discover }
                Column {
                    width: parent.width; visible: root.catData.all.length > 12
                    SectionTitle { text: qsTr("Full chart") }
                    Flow {
                        id: _catAll
                        x: 20; width: parent.width - 40; spacing: 14
                        readonly property int cols: Math.max(3, Math.floor((width + 14) / 154))
                        Repeater { model: root.catData.all
                                   ShowCard { cw: (_catAll.width - 14 * (_catAll.cols - 1)) / _catAll.cols; show: modelData; rank: index + 1 } }
                    }
                }
                Item { width: 1; height: 20 }
            }
        }
    }

    // ═════════ PAGINA PODCAST (z=55) ═════════
    Rectangle {
        id: _detail
        visible: root.detailOpen; z: 55; color: Theme.bg
        anchors.top: _hdr.bottom; anchors.bottom: parent.bottom; width: parent.width
        MouseArea { anchors.fill: parent }        // do not let touches through to the card below

        ListView {
            id: _dList
            objectName: "dList"
            anchors.fill: parent; clip: true; model: detailModel; boundsBehavior: Flickable.StopAtBounds
            header: Column {
                width: _dList.width
                Item {
                    width: parent.width; height: 214
                    Cover { id: _dCover; x: parent.width - 20 - 170; y: 16; width: 170; height: 170; radius: 10; source: root.detail.cover }
                    Column {
                        x: 20; y: 14; width: parent.width - 20 - 170 - 40; spacing: 4
                        Text { width: parent.width; text: root.detail.title; color: Theme.textPrimary; font.pixelSize: 28; font.weight: Font.Bold; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                        Text { width: parent.width; text: root.detail.author; color: root.accent; font.pixelSize: 19; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Text { width: parent.width; color: Theme.textSecondary; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight
                               text: { var a = []; if (root.detail.genre) a.push(root.detail.genre.toUpperCase()); if (root.detail.total > 0) a.push(root.detail.total + qsTr(" EPISODES")); return a.join("  ·  ") } }
                        Text { width: parent.width; text: root.detail.desc; color: Theme.textSecondary; font.pixelSize: 14; wrapMode: Text.WordWrap
                               maximumLineCount: root.descExpanded ? 20 : 3; elide: Text.ElideRight
                               MouseArea { anchors.fill: parent; onClicked: root.descExpanded = !root.descExpanded } }
                    }
                }
                Row {
                    x: 20; spacing: 12; height: 64
                    Rectangle {
                        width: _pl.implicitWidth + 56; height: 48; radius: 8; color: _plA.pressed ? Qt.darker(root.accent, 1.2) : root.accent
                        Row { anchors.centerIn: parent; spacing: 10
                            Glyph { width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter; kind: "play"; col: "white" }
                            Text { id: _pl; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Listen"); color: "white"; font.pixelSize: 17; font.weight: Font.DemiBold } }
                        MouseArea { id: _plA; anchors.fill: parent; preventStealing: true; onClicked: root.playLatest() }
                    }
                    Rectangle {
                        id: _subBtn
                        readonly property bool on: !!root.detail.subscribed
                        width: _sl.implicitWidth + 56; height: 48; radius: 8
                        color: on ? root.accent : (root.lightTheme ? "#EAEAEA" : "#333333")
                        Behavior on color { ColorAnimation { duration: 180 } }
                        onOnChanged: _subPop.restart()
                        SequentialAnimation {
                            id: _subPop
                            NumberAnimation { target: _subBtn; property: "scale"; to: 1.12; duration: 110; easing.type: Easing.OutCubic }
                            NumberAnimation { target: _subBtn; property: "scale"; to: 1.0; duration: 220; easing.type: Easing.OutBack }
                        }
                        Row { anchors.centerIn: parent; spacing: 10
                            Glyph { width: 20; height: 20; anchors.verticalCenter: parent.verticalCenter; kind: _subBtn.on ? "check" : "plus"; col: _subBtn.on ? "white" : Theme.textPrimary }
                            Text { id: _sl; anchors.verticalCenter: parent.verticalCenter; text: _subBtn.on ? qsTr("Subscribed") : qsTr("Subscribe"); color: _subBtn.on ? "white" : Theme.textPrimary; font.pixelSize: 17; font.weight: Font.DemiBold } }
                        MouseArea { anchors.fill: parent; preventStealing: true; onClicked: root.toggleSub(root.detail) }
                    }
                }
                Item {
                    width: parent.width; height: 52
                    Text { x: 20; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Episodes"); color: Theme.textPrimary; font.pixelSize: 21; font.weight: Font.Bold }
                    Text { x: 110; anchors.verticalCenter: parent.verticalCenter; visible: root.detailLoading; text: qsTr("loading…"); color: Theme.textSecondary; font.pixelSize: 14 }
                }
            }
            delegate: EpisodeRow { ep: root.epOf(model); showPodcast: false }
            footer: Column {
                width: _dList.width
                Item {
                    width: parent.width; height: 90
                    Row {
                        visible: root.detailAll.length > 1; x: 20; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                        Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Show all (") + root.detailAll.length + ")"; color: root.accent; font.pixelSize: 19; font.weight: Font.DemiBold }
                        Glyph { anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; rotation: -90; kind: "chevron"; col: root.accent }
                    }
                    MouseArea { anchors.fill: parent; enabled: root.detailAll.length > 1; onClicked: root.episodesOpen = true }
                }
                Column {
                    id: _trSec
                    visible: !!root.detail.trailer; width: parent.width
                    SectionTitle { text: qsTr("Trailer") }
                    EpisodeRow { ep: root.detail.trailer || ({}); showPodcast: false }
                    Item { width: 1; height: 16 }
                }
                Column {
                    id: _hgSec
                    objectName: "hostGuests"
                    visible: (root.detail.persons || []).length > 0; width: parent.width
                    SectionTitle { text: qsTr("Hosts and guests") }
                    ListView {
                        id: _hgList
                        width: parent.width; height: 168; orientation: ListView.Horizontal; clip: true; spacing: 6
                        leftMargin: 20; rightMargin: 20; boundsBehavior: Flickable.StopAtBounds
                        model: root.detail.persons || []
                        delegate: Item {
                            width: 112; height: _hgList.height
                            readonly property string nm: modelData.name || ""
                            Item {
                                id: _av; anchors.horizontalCenter: parent.horizontalCenter; y: 4; width: 88; height: 88
                                Rectangle {
                                    anchors.fill: parent; radius: 44; color: root.lightTheme ? "#E3E3E6" : "#3C3C40"
                                    Text { anchors.centerIn: parent; visible: !_hgImg.visible; color: Theme.textSecondary; font.pixelSize: 30; font.weight: Font.Bold
                                           text: { var w = nm.split(/\s+/).filter(function(x) { return x.length > 0 }); return ((w[0] || "?")[0] + (w.length > 1 ? w[w.length - 1][0] : "")).toUpperCase() } }
                                }
                                Cover { id: _hgImg; anchors.fill: parent; radius: 44; source: modelData.img || ""; visible: (modelData.img || "") !== "" }
                            }
                            Text { y: 98; width: parent.width - 8; x: 4; horizontalAlignment: Text.AlignHCenter; text: nm; color: Theme.textPrimary
                                   font.pixelSize: 15; font.weight: Font.DemiBold; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                            Text { y: 140; width: parent.width - 8; x: 4; horizontalAlignment: Text.AlignHCenter; color: Theme.textSecondary; font.pixelSize: 13
                                   text: (modelData.role || "host") === "host" ? qsTr("Host") : ((modelData.role === "guest") ? qsTr("Guest") : (modelData.role.charAt(0).toUpperCase() + modelData.role.slice(1))) }
                        }
                    }
                    Item { width: 1; height: 30 }
                }
            }
        }
    }

    // ═════════ FULL EPISODE LIST (z=56) ═════════
    Rectangle {
        id: _epsPage
        visible: root.detailOpen && root.episodesOpen; z: 56; color: Theme.bg
        anchors.top: _hdr.bottom; anchors.bottom: parent.bottom; width: parent.width
        MouseArea { anchors.fill: parent }
        ListView {
            id: _eList
            anchors.fill: parent; clip: true; model: listModel; boundsBehavior: Flickable.StopAtBounds
            header: Item {
                width: _eList.width; height: 76
                Column { x: 20; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 40 - 200; spacing: 2
                    Text { width: parent.width; text: root.detail.title; color: Theme.textPrimary; font.pixelSize: 24; font.weight: Font.Bold; elide: Text.ElideRight }
                    Text { width: parent.width; text: qsTr("All episodes (") + root.detailAll.length + ")"; color: Theme.textSecondary; font.pixelSize: 14 }
                }
                Pill { anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter; height: 36
                       label: root.detailAsc ? qsTr("Oldest first") : qsTr("Newest first"); onClicked: { root.detailAsc = !root.detailAsc; root.rebuildDetail() } }
            }
            delegate: EpisodeBig { ep: root.epOf(model) }
            footer: Item {
                width: _eList.width; height: (root.detailAll.length > root.detailShown ? 90 : 20) + 20
                Pill { visible: root.detailAll.length > root.detailShown; anchors.centerIn: parent
                       label: qsTr("Show more (") + (root.detailAll.length - root.detailShown) + ")"; onClicked: { root.detailShown += 50; root.rebuildDetail() } }
            }
        }
    }

    // ═════════ IN RIPRODUZIONE + IN CODA (z=80) ═════════
    // Same structure as the YT Music / Spotify queue (MediaQueuePanel): title, controls, bar, cover on the right
    // and below the "Up next" list. In addition to the usual buttons there are the podcast ones: −15 s, +30 s, speed, timer.
    Rectangle {
        id: _player
        visible: root.playerOpen; z: 80; color: Theme.bg
        anchors.fill: parent
        MouseArea { anchors.fill: parent }
        readonly property var ep: root.pState.ep
        property bool dragging: false
        property real dragPct: 0
        readonly property real pct: dragging ? dragPct : (root.pState.dur > 0 ? Math.min(1, root.pState.pos / root.pState.dur) : 0)
        readonly property real u: root.u

        component QBtn: Rectangle {
            id: _qb
            property string kind: "play"
            property string label: ""
            property bool lit: false
            property bool dim: false
            signal clicked()
            width: 48 * _player.u; height: 49 * _player.u; radius: 6 * _player.u
            opacity: dim ? 0.35 : 1
            color: _qbMA.pressed ? Theme.bg : Theme.surfaceElevated
            Glyph { visible: _qb.label === ""; anchors.centerIn: parent; width: ((_qb.kind === "back15" || _qb.kind === "fwd30") ? 32 : 21) * _player.u; height: width; kind: _qb.kind; col: _qb.lit ? root.accent : Theme.textPrimary }
            Text { visible: _qb.label !== ""; anchors.centerIn: parent; text: _qb.label; color: _qb.lit ? root.accent : Theme.textPrimary; font.pixelSize: 15 * _player.u; font.weight: Font.Bold }
            MouseArea { id: _qbMA; anchors.fill: parent; preventStealing: true; enabled: !_qb.dim; onClicked: _qb.clicked() }
        }

        Column {
            anchors.top: parent.top; anchors.topMargin: root.headerH; anchors.bottom: parent.bottom; width: parent.width
            Text { visible: !_player.ep; width: parent.width; height: 120; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                   text: qsTr("Nothing playing\nStart an episode from Home or search"); color: Theme.textSecondary; font.pixelSize: 18; lineHeight: 1.3 }

            Item {
                id: _now
                visible: !!_player.ep; width: parent.width; height: 200 * _player.u
                Text { x: 15 * _player.u; y: 25 * _player.u; width: parent.width - 215 * _player.u; height: 22 * _player.u; verticalAlignment: Text.AlignVCenter
                       text: _player.ep ? _player.ep.title : ""; color: Theme.textPrimary; font.pixelSize: 23.7 * _player.u; elide: Text.ElideRight; maximumLineCount: 1 }
                Image { x: 15 * _player.u; y: 56 * _player.u; width: 15 * _player.u; height: 15 * _player.u; sourceSize: Qt.size(width * 2, height * 2); fillMode: Image.PreserveAspectFit; source: "qrc:/VoltaApp/icons/podcast.svg" }
                Text { x: 36 * _player.u; y: 56 * _player.u; width: parent.width - 236 * _player.u; height: 15 * _player.u; verticalAlignment: Text.AlignVCenter
                       text: _player.ep ? _player.ep.podcast : ""; color: Theme.textSecondary; font.pixelSize: 16 * _player.u; font.weight: Font.Medium; elide: Text.ElideRight; maximumLineCount: 1
                       MouseArea { anchors.fill: parent; onClicked: if (_player.ep && _player.ep.feed) root.openShow({ feed: _player.ep.feed, title: _player.ep.podcast, cover: _player.ep.cover }) } }

                Row {
                    x: 15 * _player.u; y: 88 * _player.u; spacing: 8 * _player.u
                    QBtn { kind: "prev"; dim: !root.pState.canPrev; onClicked: root.prevEp() }
                    QBtn { kind: "back15"; onClicked: root.seekRel(-15) }
                    QBtn { kind: root.pState.playing ? "pause" : "play"; onClicked: root.togglePlay() }
                    QBtn { kind: "fwd30"; onClicked: root.seekRel(30) }
                    QBtn { kind: "next"; dim: !root.pState.canNext; onClicked: root.nextEp() }
                    QBtn { label: root.speedText(root.pState.speed); lit: Math.abs((root.pState.speed || 1) - 1) > 0.01; onClicked: root.cycleSpeed() }
                }
                Text { visible: (root.pState.sleepLeft || 0) > 0; x: 15 * _player.u; y: 140 * _player.u; color: root.accent; font.pixelSize: 12 * _player.u
                       text: qsTr("Stops in ") + Math.ceil((root.pState.sleepLeft || 0) / 60) + " min" }

                // progress bar
                Item {
                    id: _bar
                    x: 15 * _player.u; y: 158 * _player.u; width: _now.width - 181 * _player.u - 30 * _player.u; height: 30 * _player.u
                    Rectangle { id: _track; y: 4; width: parent.width; height: 4; radius: 2; color: Theme.surfaceElevated
                        Rectangle { width: parent.width * _player.pct; height: parent.height; radius: 2; color: Theme.textPrimary }
                        Rectangle { width: _barMA.pressed ? 18 : 12; height: width; radius: width / 2; color: Theme.textPrimary; anchors.verticalCenter: parent.verticalCenter
                                    x: Math.max(0, Math.min(parent.width - width, parent.width * _player.pct - width / 2)) }
                    }
                    MouseArea {
                        id: _barMA; anchors.fill: parent; anchors.topMargin: -10; anchors.bottomMargin: -4; preventStealing: true
                        function pctAt(x) { return Math.max(0, Math.min(1, x / width)) }
                        onPressed: function(m) { _player.dragging = true; _player.dragPct = pctAt(m.x) }
                        onPositionChanged: function(m) { if (pressed) _player.dragPct = pctAt(m.x) }
                        onReleased: function(m) { root.seekPct(pctAt(m.x)); _player.dragging = false }
                    }
                    Text { text: root.fmt(_player.dragging ? _player.dragPct * root.pState.dur : root.pState.pos); color: Theme.textSecondary; font.pixelSize: 12 * _player.u; anchors.left: parent.left; anchors.top: _track.bottom; anchors.topMargin: 4 }
                    Text { text: "-" + root.fmt(Math.max(0, root.pState.dur - (_player.dragging ? _player.dragPct * root.pState.dur : root.pState.pos))); color: Theme.textSecondary; font.pixelSize: 12 * _player.u; anchors.right: parent.right; anchors.top: _track.bottom; anchors.topMargin: 4 }
                }
                Cover { width: 156 * _player.u; height: 163 * _player.u; x: parent.width - 25 * _player.u - width; y: 20 * _player.u; radius: 6; source: _player.ep ? _player.ep.cover : "" }
            }

            // ── In coda ──
            Item {
                visible: !!_player.ep; width: parent.width; height: parent.height - 200 * _player.u
                Text { id: _qHdr; x: 15 * _player.u; text: qsTr("Queue"); color: Theme.textPrimary; font.pixelSize: 22; font.weight: Font.Medium }
                Text { visible: queueModel.count === 0; anchors.top: _qHdr.bottom; anchors.topMargin: 18; x: 15 * _player.u; width: parent.width - 40 * _player.u; wrapMode: Text.WordWrap
                       text: qsTr("No other episodes in queue"); color: Theme.textSecondary; font.pixelSize: 14 }
                ListView {
                    id: _qList
                    anchors.top: _qHdr.bottom; anchors.topMargin: 10; anchors.bottom: parent.bottom; width: parent.width; clip: true
                    model: queueModel; boundsBehavior: Flickable.StopAtBounds
                    footer: Item { width: 1; height: 40 }
                    delegate: Item {
                        id: _row
                        width: _qList.width
                        readonly property bool first: index === 0
                        height: 64 + (first ? 30 : 0)
                        Text { visible: _row.first; x: 15 * _player.u; y: 6; text: qsTr("Next from ") + (_player.ep ? _player.ep.podcast : ""); color: Theme.textSecondary; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Item {
                            y: _row.first ? 30 : 0; width: parent.width; height: 64
                            Rectangle { anchors.fill: parent; color: _rowMA.pressed ? Theme.surface : "transparent" }
                            Cover { id: _rc; x: 15 * _player.u; width: 48; height: 48; radius: 4; anchors.verticalCenter: parent.verticalCenter; source: model.cover }
                            Column {
                                anchors.left: _rc.right; anchors.leftMargin: 16; anchors.right: _rdur.left; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                Text { text: model.title; color: Theme.textPrimary; font.pixelSize: 16; font.weight: Font.Medium; width: parent.width; elide: Text.ElideRight }
                                Text { text: model.dateLabel; color: Theme.textSecondary; font.pixelSize: 13; width: parent.width; elide: Text.ElideRight }
                            }
                            Text { id: _rdur; anchors.right: parent.right; anchors.rightMargin: 25 * _player.u; anchors.verticalCenter: parent.verticalCenter
                                   text: (model.pos > 15 && model.dur > 0) ? root.fmtLeft(model.dur - model.pos) : root.fmtMin(model.dur); color: Theme.textSecondary; font.pixelSize: 13 }
                            MouseArea { id: _rowMA; anchors.fill: parent; onClicked: root.jumpTo(model.qi) }
                        }
                    }
                }
            }
        }
    }

    // ═════════ SEARCH (z=110) ═════════
    Rectangle {
        id: _search
        anchors.fill: parent; z: 110; color: Theme.bg
        visible: root.searchOpen
        MouseArea { anchors.fill: parent }
        Item {
            id: _sTop; width: parent.width; height: root.headerH + 20
            Row {
                anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 40; spacing: 20
                Item { width: 32; height: 44; anchors.verticalCenter: parent.verticalCenter
                    Glyph { anchors.centerIn: parent; width: 22; height: 22; kind: "close"; col: root.iconColor }
                    MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: root.closeSearch() } }
                Rectangle {
                    width: parent.width - 52; height: 44; anchors.verticalCenter: parent.verticalCenter; radius: 4; color: "transparent"
                    border.color: Theme.surfaceElevated; border.width: 1
                    TextInput {
                        id: _si
                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 40; verticalAlignment: TextInput.AlignVCenter
                        color: Theme.textPrimary; font.pixelSize: 16; font.weight: Font.Medium; clip: true
                        inputMethodHints: Qt.ImhNoPredictiveText
                        onTextChanged: { root.searchTerm = text; _sd.restart() }
                        onAccepted: { _sd.stop(); root.doSearch() }
                        Text { visible: parent.text === ""; text: qsTr("Search podcasts, episodes, topics…"); color: Theme.textHint; font.pixelSize: 16; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Rectangle {
                        visible: _si.text !== ""; width: 24; height: 24; radius: 12; color: root.lightTheme ? "#E0E0E0" : "#262626"
                        anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                        Text { text: "✕"; color: root.lightTheme ? "#333" : "#CCC"; font.pixelSize: 12; anchors.centerIn: parent }
                        MouseArea { anchors.fill: parent; onClicked: { _si.text = ""; root.searchTerm = "" } }
                    }
                }
            }
        }
        Timer { id: _sd; interval: 700; onTriggered: root.doSearch() }

        Flickable {
            anchors.top: _sTop.bottom; anchors.bottom: parent.bottom; width: parent.width; clip: true
            contentWidth: width; contentHeight: _sCol.height + 60; boundsBehavior: Flickable.StopAtBounds
            Column {
                id: _sCol; width: parent.width
                // without text: shortcuts to the categories
                Column {
                    width: parent.width; visible: root.searchTerm.trim().length < 2
                    SectionTitle { text: qsTr("Categories") }
                    Flow {
                        x: 20; width: parent.width - 40; spacing: 10
                        Repeater { model: root.genres
                                   Pill { label: modelData.name; onClicked: root.openCategory(modelData.id) } }
                    }
                }
                Text { visible: root.searchBusy; x: 20; height: 50; verticalAlignment: Text.AlignVCenter; text: qsTr("Searching…"); color: Theme.textSecondary; font.pixelSize: 16 }
                Text { visible: root.searchMsg !== "" && !root.searchBusy; x: 20; width: parent.width - 40; height: 60; verticalAlignment: Text.AlignVCenter; wrapMode: Text.WordWrap; text: root.searchMsg; color: Theme.textSecondary; font.pixelSize: 16 }
                Shelf { title: "Podcast"; items: root.searchShows }
                Column {
                    width: parent.width; visible: searchEpModel.count > 0
                    SectionTitle { text: qsTr("Episodes") }
                    Repeater { model: searchEpModel; delegate: EpisodeRow { ep: root.epOf(model) } }
                }
            }
        }
    }

    // ═════════ MENU APP MUSICALI (z=400) ═════════
    Item {
        anchors.fill: parent; z: 400; visible: root.appMenuOpen
        MouseArea { anchors.fill: parent; onClicked: root.appMenuOpen = false }
        Rectangle {
            x: 20; y: root.headerH - 6; width: 220; height: _menuCol.height + 12; radius: 10
            color: root.lightTheme ? "#FFFFFF" : "#2A2A2A"; border.color: Theme.border; border.width: 1
            MouseArea { anchors.fill: parent }
            Column {
                id: _menuCol; width: parent.width; y: 6
                Repeater {
                    model: root.musicApps
                    Rectangle {
                        width: _menuCol.width; height: 48; color: "transparent"
                        Row { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 12
                            Image { source: modelData.icon; sourceSize: Qt.size(48, 48); width: 24; height: 24; fillMode: Image.PreserveAspectFit; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.name; color: root.selectedTextColor; font.pixelSize: 16; font.weight: modelData.appId === root.selfAppId ? Font.DemiBold : Font.Medium; anchors.verticalCenter: parent.verticalCenter } }
                        MouseArea { anchors.fill: parent; onClicked: { root.appMenuOpen = false; if (modelData.appId !== root.selfAppId) root.switchToApp(modelData.appId) } }
                    }
                }
            }
        }
    }

    // ═════════ Messaggio ═════════
    Rectangle {
        z: 500; visible: root.toastText !== ""; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 24
        radius: 8; color: "#E6000000"; width: _toastT.implicitWidth + 36; height: 42
        Text { id: _toastT; anchors.centerIn: parent; text: root.toastText; color: "white"; font.pixelSize: 15 }
    }
}
