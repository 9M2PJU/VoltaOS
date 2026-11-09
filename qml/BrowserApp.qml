import QtQuick
import QtWebEngine
import Qt5Compat.GraphicalEffects
import VoltaApp 1.0
import QtWebSockets
import QtCore as Core

// BROWSER — EV-OS style: address bar with back/forward, URL, reload,
// bookmarks. Replaces both the old bare webview and Chrome wayland.
Rectangle {
    id: browser
    color: lightTheme ? "#F5F5F5" : "#171717"
    clip: true

    property bool lightTheme: false
    property bool active: false

    // ── Native Chrome in the compositor (Google login, DRM) ──────────────
    // false = WebEngine inside the UI (VoltaBrowserData profile, with the fix for the Google
    // logins below); true = real Google Chrome as a separate app, controlled via
    // DevTools (port 9222, profile ~/.config/volta-chrome). WebEngine put back on
    // 2026-11-05: Google logins now work here too, as in Theater.
    property bool chromeMode: false
    property var nativeShells: ({})
    property var nativeToplevels: ({})
    property var nativeSurfaces: ({})
    property bool chromeLaunchAttempted: false
    readonly property string chromeStartUrl: "https://www.google.com"
    SystemHelper { id: chromeLauncher }
    function launchChrome() {
        chromeLaunchAttempted = true
        chromeLauncher.runDetached("/bin/sh", ["-c",
            "env WAYLAND_DISPLAY=wayland-volta google-chrome " +
            "--app=" + chromeStartUrl + " " +
            "--user-data-dir=$HOME/.config/volta-chrome " +
            "--ozone-platform=wayland --password-store=basic --lang=it " +
            "--class=volta-browser --disable-features=TranslateUI " +
            "--no-first-run --no-default-browser-check --remote-debugging-port=9222"])
        chromeRetry.restart()
    }
    Timer {
        id: chromeRetry; interval: 8000; repeat: false
        onTriggered: if (!browser.nativeSurfaces["chrome"]) browser.chromeLaunchAttempted = false
    }
    onActiveChanged: {
        if (active && chromeMode && !nativeSurfaces["chrome"] && !chromeLaunchAttempted)
            launchChrome()
        if (active && nativeSurfaces["chrome"]) chromeLaunchAttempted = false
        lifecycleSync()
    }

    readonly property color barBg:     lightTheme ? "#FFFFFF" : "#262626"
    readonly property color barBorder: lightTheme ? "#D0D1D2" : "#3A3A3A"
    readonly property color txt:       lightTheme ? "#171717" : "#FFFFFF"
    readonly property color txtHint:   lightTheme ? "#9A9A9A" : "#6E6F71"
    readonly property color iconCol:   lightTheme ? "#5A5A5A" : "#A2A3A5"

    // Esposto ad AppPanel
    property alias webView: webContent

    // Desktop for all sites; Android tablet ONLY on the Google login pages
    // (accounts.google.com): from desktop Google recognizes the embedded browser and blocks
    // the login ("insecure browser"), from tablet it does not — it is how YouTube does it in Theater.
    readonly property string desktopUA: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    readonly property string tabletUA:  "Mozilla/5.0 (Linux; Android 13; SM-X906C) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    property bool _tabletUA: false
    function _isGoogleLogin(u) { return /^https?:\/\/([^\/]*\.)?accounts\.google\.com(\/|$|\?)/.test(String(u)) }
    // shared with the web apps (same logins as the Browser), see WebAppView.qml
    readonly property alias webProfile: browserProfile
    readonly property var uaScripts: webContent.userScripts.collection
    SystemHelper { id: uaFix; Component.onCompleted: { uaFix.installGoogleFix(browserProfile); uaFix.persistCookies(browserProfile, "browser") } }

    // Web profile with data saved to disk (VoltaBrowserData). No "offTheRecord: false":
    // set before storageName it produced the warning "Storage name is empty...".
    // (Qt 6.9's WebEngineProfilePrototype does not work here: instance() is null while
    //  the WebEngineView is created, and setProfile(null) crashes.)
    WebEngineProfile {
        id: browserProfile
        storageName: "VoltaBrowserData"
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
        httpUserAgent: browser.desktopUA
    }

    // ── ADDRESS BAR (EV style) ────────────────────────────────────
    Rectangle {
        id: toolbar
        anchors.top: parent.top
        width: parent.width; height: 52
        color: browser.barBg
        z: 10

        // Bordo sottile in basso
        Rectangle {
            anchors.bottom: parent.bottom; width: parent.width; height: 1
            color: browser.barBorder
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 12; anchors.rightMargin: 12
            spacing: 6

            // ← Indietro
            Rectangle {
                width: 36; height: 36; radius: 8
                anchors.verticalCenter: parent.verticalCenter
                color: _backMA.pressed ? browser.barBorder : "transparent"
                opacity: browser.canBack ? 1.0 : 0.35
                Text { anchors.centerIn: parent; text: "←"; color: browser.iconCol; font.pixelSize: 20 }
                MouseArea { id: _backMA; anchors.fill: parent; enabled: browser.canBack; onClicked: browser.doBack() }
            }

            // → Avanti
            Rectangle {
                width: 36; height: 36; radius: 8
                anchors.verticalCenter: parent.verticalCenter
                color: _fwdMA.pressed ? browser.barBorder : "transparent"
                opacity: browser.canFwd ? 1.0 : 0.35
                Text { anchors.centerIn: parent; text: "→"; color: browser.iconCol; font.pixelSize: 20 }
                MouseArea { id: _fwdMA; anchors.fill: parent; enabled: browser.canFwd; onClicked: browser.doForward() }
            }

            // URL bar
            Rectangle {
                id: urlBar
                width: parent.width - 5*36 - 5*6  // space for the 5 buttons
                height: 36; radius: 18
                anchors.verticalCenter: parent.verticalCenter
                color: lightTheme ? "#F0F0F0" : "#1E1E1E"
                border.width: urlInput.activeFocus ? 1 : 0
                border.color: "#3D6FE7"

                Row {
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 8

                    // Search icon (icons/search.svg)
                    Image { sourceSize: Qt.size(width * 2, height * 2);
                        source: "qrc:/VoltaApp/icons/search.svg"
                        width: 14; height: 14
                        fillMode: Image.PreserveAspectFit
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: 0.7
                    }

                    TextInput {
                        id: urlInput
                        objectName: "browserUrlBar"
                        width: parent.width - 30
                        anchors.verticalCenter: parent.verticalCenter
                        color: browser.txt; font.pixelSize: 14
                        selectByMouse: true; clip: true
                        text: browser.curUrl

                        Text {
                            anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                            text: qsTr("Search Google or type a URL")
                            color: browser.txtHint; font.pixelSize: 14
                            visible: urlInput.text === "" && !urlInput.activeFocus
                        }

                        onTextEdited: {
                            browser.suggestions = browser.buildSuggestions(text)
                            browser.suggestOpen = text.trim().length > 0
                        }

                        onAccepted: {
                            browser.suggestOpen = false
                            var t = text.trim()
                            if (t === "") return
                            // If it has no protocol and looks like a URL, add https://
                            if (t.indexOf("://") < 0) {
                                if (t.indexOf(".") >= 0 && t.indexOf(" ") < 0)
                                    t = "https://" + t
                                else
                                    t = "https://www.google.com/search?q=" + encodeURIComponent(t)
                            }
                            browser.doNavigate(t)
                            urlInput.focus = false
                        }

                        onActiveFocusChanged: {
                            if (activeFocus) selectAll()
                            else suggestCloseTimer.restart()
                        }
                    }
                }

                // ── Suggestions list under the address bar ──
                Rectangle {
                    id: suggestBox
                    visible: browser.suggestOpen
                    z: 50
                    x: 0; y: parent.height + 6
                    width: parent.width
                    height: sugCol.height
                    radius: 8
                    color: browser.barBg
                    border.width: 1; border.color: browser.barBorder

                    Column {
                        id: sugCol
                        width: parent.width
                        Repeater {
                            model: browser.suggestions
                            Rectangle {
                                width: sugCol.width; height: 42
                                radius: 8
                                color: _sugMA.pressed ? browser.barBorder : "transparent"
                                Text {
                                    id: _sugStar
                                    x: 14; anchors.verticalCenter: parent.verticalCenter
                                    width: 18
                                    text: modelData.bm ? "★" : "›"
                                    color: modelData.bm ? "#F5B301" : browser.txtHint
                                    font.pixelSize: 15
                                }
                                Text {
                                    anchors.left: _sugStar.right; anchors.leftMargin: 8
                                    anchors.right: _sugFill.left; anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: browser.txt; font.pixelSize: 15
                                    elide: Text.ElideRight
                                }
                                MouseArea { id: _sugMA; anchors.fill: parent; onClicked: browser.pickSuggestion(modelData.url) }
                                Item {
                                    id: _sugFill
                                    anchors.right: parent.right
                                    width: 44; height: parent.height
                                    Text { anchors.centerIn: parent; text: "↖"; color: browser.iconCol; font.pixelSize: 17 }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            urlInput.text = modelData.label
                                            urlInput.cursorPosition = urlInput.text.length
                                            browser.suggestions = browser.buildSuggestions(urlInput.text)
                                        }
                                    }
                                }
                            }
                        }
                        // Last row: search on Google
                        Rectangle {
                            width: sugCol.width; height: 42; radius: 8
                            color: _sugGMA.pressed ? browser.barBorder : "transparent"
                            Image {
                                id: _sugG
                                sourceSize: Qt.size(width * 2, height * 2)
                                source: "qrc:/VoltaApp/icons/search.svg"
                                x: 14; width: 14; height: 14
                                anchors.verticalCenter: parent.verticalCenter
                                fillMode: Image.PreserveAspectFit; opacity: 0.7
                            }
                            Text {
                                anchors.left: _sugG.right; anchors.leftMargin: 12
                                anchors.right: parent.right; anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Search «") + urlInput.text.trim() + qsTr("» on Google")
                                color: browser.txt; font.pixelSize: 15
                                elide: Text.ElideRight
                            }
                            MouseArea {
                                id: _sugGMA; anchors.fill: parent
                                onClicked: browser.pickSuggestion("https://www.google.com/search?q=" + encodeURIComponent(urlInput.text.trim()))
                            }
                        }
                    }
                }
            }

            // ↻ Reload
            Rectangle {
                width: 36; height: 36; radius: 18
                anchors.verticalCenter: parent.verticalCenter
                color: _reloadMA.pressed ? browser.barBorder : "transparent"
                Text { anchors.centerIn: parent; text: (browser.chromeMode ? browser.cdpLoading : webContent.loading) ? "✕" : "↻"; color: browser.iconCol; font.pixelSize: 18 }
                MouseArea { id: _reloadMA; anchors.fill: parent; onClicked: browser.doReload() }
            }

            // ★ Favorites: adds/removes the current page
            Rectangle {
                width: 36; height: 36; radius: 18
                anchors.verticalCenter: parent.verticalCenter
                color: _starMA.pressed ? browser.barBorder : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: browser.curBookmarked ? "★" : "☆"
                    color: browser.curBookmarked ? "#F5B301" : browser.iconCol
                    font.pixelSize: 20
                }
                MouseArea { id: _starMA; anchors.fill: parent; onClicked: browser.toggleBookmark() }
            }

            // ⊞ Add to apps: the site becomes an icon in the drawer (web app)
            Rectangle {
                width: 36; height: 36; radius: 18
                anchors.verticalCenter: parent.verticalCenter
                color: _waMA.pressed ? browser.barBorder : "transparent"
                readonly property bool added: browser.curUrl !== "" && WebApps.has(browser.curUrl)
                Rectangle {
                    anchors.centerIn: parent
                    width: 19; height: 19; radius: 5
                    color: parent.added ? "#1667F2" : "transparent"
                    border.width: 2; border.color: parent.added ? "#1667F2" : browser.iconCol
                    Text {
                        anchors.centerIn: parent; anchors.verticalCenterOffset: parent.parent.added ? 0 : -1
                        text: parent.parent.added ? "✓" : "+"
                        color: parent.parent.added ? "#FFFFFF" : browser.iconCol
                        font.pixelSize: parent.parent.added ? 12 : 16; font.weight: Font.Bold
                    }
                }
                MouseArea { id: _waMA; anchors.fill: parent; onClicked: browser.toggleWebApp() }
            }

            // ☰ Menu (placeholder)
            Rectangle {
                width: 36; height: 36; radius: 18; color: "transparent"
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: "☰"; color: browser.iconCol; font.pixelSize: 18 }
            }
        }

        // Loading bar
        Rectangle {
            anchors.bottom: parent.bottom; x: 0
            width: webContent.loading ? parent.width * webContent.loadProgress / 100 : 0
            height: 2; color: "#3D6FE7"; radius: 1
            visible: webContent.loading
            Behavior on width { NumberAnimation { duration: 200 } }
        }
    }

    // ═════ PREFERITI + AUTOCOMPLETAMENTO + CONGELAMENTO ═════════════════════
    Core.Settings {
        id: browserPrefs
        category: "browser"
        property string bookmarks: "[]"
        property string visited: "{}"
    }
    property var bookmarkList: []        // [{url, title}]
    property var visitedMap: ({})        // host -> quante volte
    property bool editBookmarks: false
    property var suggestions: []         // [{url, label, bm}]
    property bool suggestOpen: false
    property string cdpTitle: ""
    readonly property string curTitle: chromeMode ? cdpTitle : webContent.title
    readonly property bool curBookmarked: isBookmarked(curUrl)
    onBookmarkListChanged: if (bookmarkList.length === 0) editBookmarks = false
    onCurUrlChanged: recordVisit(curUrl)
    Component.onCompleted: _loadPrefs()

    Timer { id: suggestCloseTimer; interval: 220; onTriggered: browser.suggestOpen = false }
    Timer { id: saveVisitedTimer; interval: 4000; onTriggered: browser._saveVisited() }

    readonly property var knownSites: [
        "google.com", "youtube.com", "wikipedia.org", "facebook.com", "instagram.com",
        "amazon.it", "netflix.com", "twitch.tv", "reddit.com", "whatsapp.com",
        "repubblica.it", "corriere.it", "ansa.it", "gazzetta.it", "ilmeteo.it",
        "spotify.com", "github.com", "linkedin.com", "primevideo.com", "raiplay.it",
        "subito.it", "ebay.it", "openstreetmap.org", "maps.google.com",
        "mail.google.com", "x.com", "tiktok.com", "disneyplus.com", "dazn.com"
    ]

    function _loadPrefs() {
        try { var b = JSON.parse(browserPrefs.bookmarks); bookmarkList = Array.isArray(b) ? b : [] }
        catch (e) { bookmarkList = [] }
        try { var v = JSON.parse(browserPrefs.visited); visitedMap = (v && typeof v === "object" && !Array.isArray(v)) ? v : ({}) }
        catch (e) { visitedMap = ({}) }
    }
    function _saveVisited() {
        var keys = Object.keys(visitedMap)
        if (keys.length > 300) {
            keys.sort(function(a, b) { return visitedMap[b] - visitedMap[a] })
            var m = {}
            for (var i = 0; i < 300; i++) m[keys[i]] = visitedMap[keys[i]]
            visitedMap = m
        }
        browserPrefs.visited = JSON.stringify(visitedMap)
    }
    function hostOf(u) {
        var m = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#:]+)/i.exec(u || "")
        return m ? m[1].toLowerCase().replace(/^www\./, "") : ""
    }
    function plainOf(u) { return (u || "").replace(/^[a-z][a-z0-9+.-]*:\/\//i, "").replace(/^www\./i, "").replace(/#.*$/, "").replace(/\/+$/, "").toLowerCase() }
    function isBookmarked(u) {
        var k = plainOf(u)
        if (!k) return false
        for (var i = 0; i < bookmarkList.length; i++)
            if (plainOf(bookmarkList[i].url) === k) return true
        return false
    }
    // Adds/removes the current page as a web app in the drawer
    function toggleWebApp() {
        var u = String(browser.curUrl || "")
        if (!/^https?:\/\//i.test(u)) return
        if (WebApps.has(u)) { WebApps.removeUrl(u); browser.showToast(qsTr("Removed from apps")) }
        else { WebApps.add(u, browser.curTitle); browser.showToast(qsTr("Added to apps: you'll find it at the top of the app menu")) }
    }
    property string _toastText: ""
    function showToast(t) { _toastText = t; waToast.opacity = 1; waToastTimer.restart() }

    function toggleBookmark() {
        var u = curUrl
        if (!u || u.indexOf("http") !== 0) return
        var k = plainOf(u), list = [], found = false
        for (var i = 0; i < bookmarkList.length; i++) {
            if (plainOf(bookmarkList[i].url) === k) found = true
            else list.push(bookmarkList[i])
        }
        if (!found) list.push({ url: u, title: (curTitle && curTitle.length) ? curTitle : (hostOf(u) || u) })
        bookmarkList = list
        browserPrefs.bookmarks = JSON.stringify(list)
    }
    function removeBookmarkAt(i) {
        var list = bookmarkList.slice()
        list.splice(i, 1)
        bookmarkList = list
        browserPrefs.bookmarks = JSON.stringify(list)
    }
    function recordVisit(u) {
        var h = hostOf(u)
        if (!h || u.indexOf("http") !== 0) return
        var m = visitedMap
        m[h] = (m[h] || 0) + 1
        visitedMap = m
        saveVisitedTimer.restart()
    }
    function buildSuggestions(text) {
        var q = (text || "").trim().toLowerCase().replace(/^https?:\/\//, "").replace(/^www\./, "")
        if (q.length === 0 || q.indexOf(" ") >= 0) return []
        var cand = {}
        function put(key, url, score, bm) {
            var c = cand[key]
            if (!c) cand[key] = { key: key, url: url, score: score, bm: bm }
            else {
                if (score > c.score) c.score = score
                if (bm) { c.bm = true; c.url = url }
            }
        }
        var i
        for (i = 0; i < bookmarkList.length; i++) {
            var bu = bookmarkList[i].url, bk = plainOf(bu), s = 0
            if (bk.indexOf(q) === 0) s = 3
            else if (bk.indexOf(q) >= 0) s = 1
            else if (((bookmarkList[i].title || "").toLowerCase()).indexOf(q) >= 0) s = 1
            if (s > 0) put(bk, bu, s + 2, true)
        }
        for (var h in visitedMap) {
            var sv = h.indexOf(q) === 0 ? 3 : (h.indexOf(q) >= 0 ? 1 : 0)
            if (sv > 0) put(h, "https://" + h, sv + Math.min(1.5, Math.log(visitedMap[h] + 1) / Math.LN10), false)
        }
        for (i = 0; i < knownSites.length; i++) {
            var kh = knownSites[i], sk = kh.indexOf(q) === 0 ? 3 : (kh.indexOf(q) >= 0 ? 1 : 0)
            if (sk > 0) put(kh, "https://" + kh, sk, false)
        }
        var arr = []
        for (var k in cand) if (cand[k].key !== q) arr.push(cand[k])
        arr.sort(function(a, b) { return (b.score - a.score) || (a.key.length - b.key.length) })
        return arr.slice(0, 6).map(function(c) { return { url: c.url, label: c.key, bm: c.bm } })
    }
    function pickSuggestion(u) {
        suggestOpen = false
        urlInput.focus = false
        doNavigate(u)
    }

    // ── Freeze on close: only if Chrome is silent ──
    property bool cdpFrozen: false
    function lifecycleSync() {
        if (!chromeMode) return
        if (active) {
            freezeTimer.stop()
            if (cdpFrozen && cdpSock.status === WebSocket.Open)
                cdpSend(9, "Page.setWebLifecycleState", { state: "active" })
            cdpFrozen = false
        } else {
            freezeTimer.restart()
        }
    }
    Timer {
        id: freezeTimer
        interval: 4000; repeat: true
        onTriggered: {
            if (browser.active || browser.cdpFrozen || cdpSock.status !== WebSocket.Open) return
            if (chromeLauncher.browserAudioMaybePlaying()) return   // sta suonando: lascialo stare
            browser.cdpFrozen = true
            browser.cdpSend(8, "Page.setWebLifecycleState", { state: "frozen" })
        }
    }

    // ── FAVORITES BAR ───────────────────────────────────────────
    Rectangle {
        id: bookmarksBar
        anchors.top: toolbar.bottom
        width: parent.width
        height: toolbar.visible ? 36 : 0
        visible: toolbar.visible
        color: browser.barBg
        z: 9

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: browser.barBorder }

        Text {
            visible: browser.bookmarkList.length === 0
            anchors.left: parent.left; anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Tap ☆ to add this page to your favorites")
            color: browser.txtHint; font.pixelSize: 13
        }

        ListView {
            id: bmList
            anchors.left: parent.left; anchors.leftMargin: 10
            anchors.right: _bmDone.visible ? _bmDone.left : parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 28
            orientation: ListView.Horizontal
            spacing: 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: browser.bookmarkList
            delegate: Rectangle {
                height: 28; radius: 14
                width: Math.min(210, _bmRow.width + 20)
                color: _bmMA.pressed ? browser.barBorder : (browser.lightTheme ? "#F0F0F0" : "#1E1E1E")
                Row {
                    id: _bmRow
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle {
                        id: _fav
                        width: 18; height: 18; radius: 9
                        color: _favImg.status === Image.Ready ? "transparent" : "#3D6FE7"
                        anchors.verticalCenter: parent.verticalCenter
                        Image {
                            id: _favImg
                            anchors.fill: parent
                            // site favicon (Google's service); if missing the letter stays
                            source: {
                                var m = /^[a-z]+:\/\/([^\/?#]+)/i.exec(modelData.url || "")
                                return m ? "https://www.google.com/s2/favicons?sz=64&domain=" + m[1] : ""
                            }
                            sourceSize: Qt.size(36, 36)
                            fillMode: Image.PreserveAspectFit
                            smooth: true; mipmap: true; asynchronous: true
                        }
                        Text {
                            visible: _favImg.status !== Image.Ready
                            anchors.centerIn: parent
                            text: (modelData.title || "?").charAt(0).toUpperCase()
                            color: "#FFFFFF"; font.pixelSize: 11; font.bold: true
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.title
                        color: browser.txt; font.pixelSize: 13
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 140)
                    }
                    Text {
                        visible: browser.editBookmarks
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✕"; color: "#EB5A50"; font.pixelSize: 13
                    }
                }
                MouseArea {
                    id: _bmMA
                    anchors.fill: parent
                    onClicked: {
                        if (browser.editBookmarks) browser.removeBookmarkAt(index)
                        else browser.doNavigate(modelData.url)
                    }
                    onPressAndHold: browser.editBookmarks = true
                }
            }
        }

        Rectangle {
            id: _bmDone
            visible: browser.editBookmarks
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 60; height: 26; radius: 13
            color: "#3D6FE7"
            Text { anchors.centerIn: parent; text: qsTr("Done"); color: "#FFFFFF"; font.pixelSize: 13; font.weight: Font.DemiBold }
            MouseArea { anchors.fill: parent; onClicked: browser.editBookmarks = false }
        }
    }

    // ── Chrome control via DevTools protocol (localhost:9222 only) ──
    property string cdpUrl: ""
    property bool cdpCanBack: false
    property bool cdpCanFwd: false
    property bool cdpLoading: false
    property var cdpEntries: []
    property int cdpIndex: -1
    readonly property string curUrl: chromeMode ? cdpUrl : webContent.url
    readonly property bool canBack: chromeMode ? cdpCanBack : webContent.canGoBack
    readonly property bool canFwd:  chromeMode ? cdpCanFwd  : webContent.canGoForward
    function cdpSend(id, method, params) {
        if (cdpSock.status !== WebSocket.Open) return false
        cdpSock.sendTextMessage(JSON.stringify({ id: id, method: method, params: params || {} }))
        return true
    }
    readonly property string av1Script: "(function(){try{var bad=function(t){return String(t).toLowerCase().indexOf('av01')>=0||String(t).toLowerCase().indexOf('av1')>=0};if(window.MediaSource&&MediaSource.isTypeSupported){var m=MediaSource.isTypeSupported.bind(MediaSource);MediaSource.isTypeSupported=function(t){return bad(t)?false:m(t)}}var c=HTMLMediaElement.prototype.canPlayType;HTMLMediaElement.prototype.canPlayType=function(t){return bad(t)?'':c.apply(this,arguments)};var mc=navigator.mediaCapabilities;if(mc&&mc.decodingInfo){var d=mc.decodingInfo.bind(mc);mc.decodingInfo=function(x){var ct=(x&&x.video&&x.video.contentType)||'';if(bad(ct))return Promise.resolve({supported:false,smooth:false,powerEfficient:false});return d(x)}}}catch(e){}})();"
    readonly property string linkScript: "(function(){try{if(window.__voltaLinks)return;window.__voltaLinks=true;function go(u){try{(window.top||window).location.href=u}catch(e){location.href=u}}function http(u){return String(u||'').toLowerCase().indexOf('http')===0}document.addEventListener('click',function(e){if(e.defaultPrevented)return;var a=e.target&&e.target.closest?e.target.closest('a[href]'):null;if(!a)return;var t=(a.getAttribute('target')||'').toLowerCase();if(t===''||t==='_self'||t==='_top'||t==='_parent')return;if(!http(a.href))return;e.preventDefault();e.stopPropagation();go(a.href)},true);document.addEventListener('submit',function(e){var f=e.target;if(!f||!f.getAttribute)return;var t=(f.getAttribute('target')||'').toLowerCase();if(t!==''&&t!=='_self'&&t!=='_top'&&t!=='_parent')f.setAttribute('target','_self')},true);var wo=window.open;window.open=function(u,n,f){if(u&&!f){var s=String(u);if(http(s)||s.charAt(0)==='/'||s.charAt(0)==='.'){go(new URL(s,location.href).href);return null}}return wo.apply(this,arguments)};}catch(e){}})();"
    // DevTools calls without numbering them by hand + page width (for the scroll coordinates)
    property int cdpSeq: 100
    property real cdpPageW: 0
    property int cdpWidthId: -1
    function cdpCall(method, params) { return cdpSend(++cdpSeq, method, params) }
    function cdpQueryWidth() {
        cdpWidthId = ++cdpSeq
        cdpSend(cdpWidthId, "Runtime.evaluate", { expression: "window.innerWidth", returnByValue: true })
    }
    function cdpRefresh() { cdpSend(2, "Page.getNavigationHistory") }
    function doBack() {
        if (!chromeMode) { webContent.goBack(); return }
        if (cdpIndex > 0) cdpSend(3, "Page.navigateToHistoryEntry", { entryId: cdpEntries[cdpIndex - 1].id })
    }
    function doForward() {
        if (!chromeMode) { webContent.goForward(); return }
        if (cdpIndex >= 0 && cdpIndex < cdpEntries.length - 1)
            cdpSend(3, "Page.navigateToHistoryEntry", { entryId: cdpEntries[cdpIndex + 1].id })
    }
    function doReload() {
        if (!chromeMode) { webContent.loading ? webContent.stop() : webContent.reload(); return }
        cdpLoading ? cdpSend(6, "Page.stopLoading") : cdpSend(4, "Page.reload")
    }
    function doNavigate(t) {
        if (!chromeMode) { webContent.url = t; return }
        cdpSend(5, "Page.navigate", { url: t })
    }
    function cdpConnect() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return
            try {
                var list = JSON.parse(xhr.responseText)
                for (var i = 0; i < list.length; i++) {
                    if (list[i].type === "page" && list[i].webSocketDebuggerUrl) {
                        cdpSock.url = list[i].webSocketDebuggerUrl
                        cdpSock.active = true
                        return
                    }
                }
            } catch (e) {}
        }
        xhr.open("GET", "http://127.0.0.1:9222/json")
        xhr.send()
    }
    WebSocket {
        id: cdpSock
        active: false
        onStatusChanged: {
            if (status === WebSocket.Open) {
                browser.cdpSend(1, "Page.enable")
                // connection (re)opened: if we are in the foreground make sure the page is awake
                browser.cdpFrozen = false
                if (browser.active) browser.cdpSend(9, "Page.setWebLifecycleState", { state: "active" })
                browser.cdpSend(7, "Page.addScriptToEvaluateOnNewDocument", { source: browser.av1Script })
                chromeInput.setup()
                browser.cdpQueryWidth()
                // "new tab" links open in the same page (in the app the extra windows are not visible)
                browser.cdpSend(10, "Page.addScriptToEvaluateOnNewDocument", { source: browser.linkScript })
                browser.cdpSend(11, "Runtime.evaluate", { expression: browser.linkScript })
                browser.cdpRefresh()
            }
            else if (status === WebSocket.Error) active = false
        }
        onTextMessageReceived: function(message) {
            var m = JSON.parse(message)
            if (m.id === 2 && m.result) {
                browser.cdpEntries = m.result.entries
                browser.cdpIndex = m.result.currentIndex
                var e = m.result.entries[m.result.currentIndex]
                if (e) {
                    browser.cdpUrl = e.url
                    browser.cdpTitle = e.title || ""
                    if (!urlInput.activeFocus) urlInput.text = e.url
                }
                browser.cdpCanBack = m.result.currentIndex > 0
                browser.cdpCanFwd = m.result.currentIndex < m.result.entries.length - 1
            } else if (m.method === "Page.frameNavigated" || m.method === "Page.navigatedWithinDocument") {
                cdpRefreshTimer.restart()
            } else if (m.method === "Runtime.bindingCalled") {
                if (m.params && m.params.name === "voltaKb") chromeInput.fromPage(m.params.payload)
            } else if (m.id !== undefined && m.id === browser.cdpWidthId) {
                if (m.result && m.result.result) browser.cdpPageW = Number(m.result.result.value) || 0
            } else if (m.method === "Page.frameStartedLoading") {
                browser.cdpLoading = true
            } else if (m.method === "Page.frameStoppedLoading") {
                browser.cdpLoading = false
                cdpRefreshTimer.restart()
                browser.cdpQueryWidth()
            }
        }
    }
    Timer { id: cdpRefreshTimer; interval: 150; onTriggered: browser.cdpRefresh() }
    Timer {
        id: cdpTimer; interval: 1500; repeat: true
        running: browser.chromeMode && !!browser.nativeSurfaces["chrome"]
                 && cdpSock.status !== WebSocket.Open && cdpSock.status !== WebSocket.Connecting
        onTriggered: browser.cdpConnect()
    }

    NativeAppView {
        id: chromeView
        useDefaultSubsurfaces: true
        coverColor: browser.color
        visible: browser.chromeMode
        anchors.top: bookmarksBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        appLabel: qsTr("Browser")
        shellSurface:    browser.nativeShells["chrome"]
        waylandToplevel: browser.nativeToplevels["chrome"]
    }

    // On-screen keyboard + scroll for Chrome pages (see ChromeInput.qml)
    ChromeInput {
        id: chromeInput
        anchors.fill: chromeView
        z: 5
        visible: browser.chromeMode
        connected: browser.chromeMode && cdpSock.status === WebSocket.Open
        active: browser.active
        pageWidth: browser.cdpPageW
        onRequest: function(method, params) { browser.cdpCall(method, params) }
        onRefocusSurface: chromeView.refocus()
        onWidthChanged: cdpWidthTimer.restart()
    }
    Timer { id: cdpWidthTimer; interval: 500; onTriggered: browser.cdpQueryWidth() }

    // ── WEBVIEW ──────────────────────────────────────────────────────────
    WebEngineView {
        settings.showScrollBars: false
        id: webContent
        anchors.top: bookmarksBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        profile: browserProfile
        userScripts.collection: [
            {
                name: "uaFix",
                injectionPoint: WebEngineScript.DocumentCreation,
                worldId: WebEngineScript.MainWorld,
                runsOnSubFrames: true,
                sourceCode: "(function(){try{if(/(^|\\.)accounts\\.google\\.com$/.test(location.hostname))return;var b=[{brand:'Google Chrome',version:'140'},{brand:'Chromium',version:'140'},{brand:'Not=A?Brand',version:'24'}];var fl=b.map(function(x){return{brand:x.brand,version:x.version+'.0.0.0'}});var u={brands:b,mobile:false,platform:'Linux',toJSON:function(){return{brands:b,mobile:false,platform:'Linux'}},getHighEntropyValues:function(){return Promise.resolve({brands:b,mobile:false,platform:'Linux',platformVersion:'6.12.0',architecture:'x86',bitness:'64',model:'',wow64:false,uaFullVersion:'140.0.0.0',fullVersionList:fl})}};Object.defineProperty(Navigator.prototype,'userAgentData',{get:function(){return u},configurable:true});if(!window.chrome){window.chrome={runtime:{}}}}catch(e){}})();"
            }
        ]
        visible: !browser.chromeMode
        url: browser.chromeMode ? "about:blank" : "https://www.google.com"

        settings.pluginsEnabled: true
        settings.javascriptEnabled: true
        settings.playbackRequiresUserGesture: false
        settings.javascriptCanAccessClipboard: true

        // When the browser is closed the page really closes (audio, video and scripts stopped, memory freed):
        // like Theater and Arcade. When reopened the page reloads from the same address.
        lifecycleState: browser.active
                        ? WebEngineView.LifecycleState.Active
                        : WebEngineView.LifecycleState.Discarded

        onUrlChanged: {
            if (!urlInput.activeFocus)
                urlInput.text = url
        }

        onNewWindowRequested: function(request) { request.openIn(webContent) }

        // Desktop <-> tablet switch when entering/leaving the Google login: the user agent must be
        // changed BEFORE the request, so navigation is stopped, the agent changed and the request
        // redone (redirects included).
        onNavigationRequested: function(request) {
            if (!request.isMainFrame) return
            var tablet = browser._isGoogleLogin(request.url)
            if (tablet === browser._tabletUA) return
            browser._tabletUA = tablet
            request.reject()
            // The user agent can NOT be changed in here: Chromium crashes (tested:
            // changing it during onNavigationRequested crashes the UI when clicking "Sign in").
            // The navigation is rejected and on the next turn of the event loop the user
            // agent is changed and the page reopened.
            var u = request.url
            var ua = tablet ? browser.tabletUA : browser.desktopUA
            Qt.callLater(function() { browserProfile.httpUserAgent = ua; webContent.url = u })
        }

        onFullScreenRequested: function(request) {
            request.accept()
            toolbar.visible = !request.toggleOn
        }
    }

    // conferma "Aggiunta alle app"
    Rectangle {
        id: waToast
        z: 500; opacity: 0; visible: opacity > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 40
        width: _waTxt.implicitWidth + 40; height: 44; radius: 22
        color: "#E6222222"
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text { id: _waTxt; anchors.centerIn: parent; text: browser._toastText; color: "#FFFFFF"; font.pixelSize: 15 }
    }
    Timer { id: waToastTimer; interval: 2600; onTriggered: waToast.opacity = 0 }
}
