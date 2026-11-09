import QtQuick
import Qt5Compat.GraphicalEffects
import VoltaApp 1.0

// ═══════════════════════════════════════════════════════════════════════════
//  CONFIGURAZIONE GUIDATA
//  Connect the free services (maps, search, weather, music)
//  in a few steps: for each one you create an account, copy a key and
//  paste it here. The key is checked right away and saved in keys.env
//  (SetupManager, C++), then only the service that uses it is restarted.
//  It opens by itself on first launch; then from Settings › System.
// ═══════════════════════════════════════════════════════════════════════════
Rectangle {
    id: wiz
    property bool lightTheme: false
    signal finished()

    // ── colors: the same as the Settings ──
    readonly property color bg:      lightTheme ? "#FFFFFF" : "#171717"
    readonly property color txt:     lightTheme ? "#171717" : "#FFFFFF"
    readonly property color txtSub:  lightTheme ? "#8A8A8A" : "#A2A3A5"
    readonly property color txtHint: lightTheme ? "#ABABAB" : "#6E6F71"
    readonly property color ctrlBg:  lightTheme ? "#E3E3E3" : "#2E2E2E"
    readonly property color selBg:   lightTheme ? "#D5D5D5" : "#3A3A3A"
    readonly property color divider: lightTheme ? "#DDDDDD" : "#333333"
    // no colors: only white / grays
    readonly property color accent:  "#1667F2"   // only the main buttons
    color: bg

    // Blocks touches to the UI underneath
    MouseArea { anchors.fill: parent }

    // ── I PASSI ──
    // fields: the keys to enter; testWith: key to check (with extra = another field)
    readonly property var steps: [
        { id: "welcome", nav: qsTr("Welcome"), icon: "car.svg" },
        { id: "system", nav: qsTr("System"), icon: "ms_check.svg", required: true, title: qsTr("System check"),
          desc: qsTr("Volta OS needs a few programs and Python libraries. Without the ones marked as required the interface will not work at 100%: some features (music, maps, phone, Wi-Fi…) will be missing or limited. Install what is missing with the commands below, then tap Check again.") },
        { id: "mapbox", nav: qsTr("Maps"), icon: "nav.svg", required: true,
          title: qsTr("Maps and navigation"),
          desc: qsTr("Mapbox calculates routes, live traffic and turn-by-turn directions."),
          url: "https://account.mapbox.com/access-tokens/", site: "account.mapbox.com",
          howto: [qsTr("Open account.mapbox.com and create a free account."),
                  qsTr("On the «Tokens» page copy the «Default public token» (starts with «pk.»)."),
                  qsTr("Paste it below.")],
          fields: [{ key: "MAPBOX_TOKEN", label: qsTr("Mapbox token"), hint: "pk.eyJ1Ijoi…" }],
          testWith: "MAPBOX_TOKEN" },
        { id: "maptiler", nav: qsTr("Map style"), icon: "globo.svg", required: true,
          title: qsTr("Map appearance"),
          desc: qsTr("MapTiler draws the map: roads, street names and the light and dark theme colors."),
          url: "https://cloud.maptiler.com/account/keys/", site: "cloud.maptiler.com",
          howto: [qsTr("Open cloud.maptiler.com and sign up for free."),
                  qsTr("In «Account › Keys» copy the «Default key»."),
                  qsTr("Paste it below.")],
          fields: [{ key: "MAPTILER_KEY", label: qsTr("MapTiler key"), hint: qsTr("AbCdEf123…") }],
          testWith: "MAPTILER_KEY" },
        { id: "tomtom", nav: qsTr("Search"), icon: "search.svg",
          title: qsTr("Place search"),
          desc: qsTr("TomTom finds cities, addresses and businesses when you search for a destination, plus nearby fuel stations."),
          url: "https://developer.tomtom.com/user/register", site: "developer.tomtom.com",
          howto: [qsTr("Sign up at developer.tomtom.com."),
                  qsTr("In the dashboard open «Keys»: copy the ready-made key."),
                  qsTr("Paste it below.")],
          fields: [{ key: "TOMTOM_KEY", label: qsTr("TomTom key"), hint: qsTr("32-character key") }],
          testWith: "TOMTOM_KEY" },
        { id: "owm", nav: qsTr("Weather"), icon: "wx_partly_day.svg",
          title: qsTr("Weather"),
          desc: qsTr("OpenWeatherMap completes the rain radar on the map. It's optional: the radar already works without it."),
          url: "https://home.openweathermap.org/users/sign_up", site: "openweathermap.org",
          howto: [qsTr("Create an account on openweathermap.org and confirm your email."),
                  qsTr("Open «API keys» and copy the key."),
                  qsTr("Paste it below. New keys can take up to 2 hours to activate.")],
          fields: [{ key: "OWM_KEY", label: qsTr("OpenWeatherMap key"), hint: qsTr("32-character key") }],
          testWith: "OWM_KEY" },
        { id: "spotify", nav: qsTr("Spotify"), icon: "spotify.svg",
          title: qsTr("Spotify"),
          desc: qsTr("Shows your playlists, library and recommended tracks in the Spotify app. A free account works too."),
          url: "https://developer.spotify.com/dashboard", site: "developer.spotify.com",
          howto: [qsTr("Open developer.spotify.com/dashboard and sign in with your Spotify account."),
                  qsTr("Press «Create app». Name and description are up to you; in «Redirect URIs» add the address below and tick «Web API»."),
                  qsTr("In the app you created open «Settings» and copy the Client ID and Client secret.")],
          copyLabel: qsTr("Redirect URI"), copyText: "http://127.0.0.1:8098/callback",
          fields: [{ key: "SPOTIFY_CLIENT_ID", label: qsTr("Client ID"), hint: qsTr("32 characters") },
                   { key: "SPOTIFY_CLIENT_SECRET", label: qsTr("Client secret"), hint: qsTr("32 characters"), secret: true }],
          testWith: "SPOTIFY_CLIENT_SECRET", testExtra: "SPOTIFY_CLIENT_ID" },
        { id: "games", nav: qsTr("Games"), icon: "arcade.svg", title: qsTr("Games"),
          title: qsTr("Games"),
          desc: qsTr("Windows games are installed with Bottles, which is free. Every game you add in Bottles appears by itself in the Arcade, with its cover.") },
        { id: "done", nav: qsTr("Done"), icon: "ms_check.svg", title: qsTr("All set") }
    ]

    property int cur: 0
    readonly property real k: 1.15     // scaling of the icon | line | content block
    readonly property var step: steps[cur]
    readonly property bool isInfo: step.id === "welcome" || step.id === "done" || step.id === "games" || step.id === "system"
    // Games step: what is on the system and how many games were found
    property var gamesSt: ({ bottles: false, gamescope: false })
    property int gamesFound: -1
    function refreshGames() {
        gamesSt = Setup.gamesStatus()
        var x = new XMLHttpRequest()
        x.open("GET", "http://127.0.0.1:9098/games")
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return
            try { wiz.gamesFound = x.status === 200 ? (JSON.parse(x.responseText).games || []).length : -1 } catch (e) { wiz.gamesFound = -1 }
            if (wiz.gamesFound > 0) wiz.setStatus("games", "ok")
        }
        x.send()
    }


    // System check step: [{title, what, ok, required, how, cmd}]
    property var deps: []
    readonly property bool depsMissingRequired: {
        for (var i = 0; i < deps.length; i++) if (deps[i].required && !deps[i].ok) return true
        return false
    }
    function refreshDeps() {
        deps = Setup.dependencyReport()
        setStatus("system", depsMissingRequired ? "" : "ok")
    }

    // state per step: "" | "ok" | "skip"
    property var status: ({})
    function setStatus(id, s) { var o = Object.assign({}, status); o[id] = s; status = o }

    // values being edited (per key)
    property var vals: ({})
    function setVal(k, v) { var o = Object.assign({}, vals); o[k] = v; vals = o }
    function valOf(k) { return vals[k] !== undefined ? vals[k] : Setup.value(k) }

    // verifica
    property string testState: ""       // "" | "busy" | "ok" | "fail"
    property string testMsg: ""
    property bool offlineFail: false

    function go(i) {
        cur = Math.max(0, Math.min(steps.length - 1, i))
        testState = ""; testMsg = ""; offlineFail = false
        if (steps[cur].id === "games") refreshGames()
        if (steps[cur].id === "system") refreshDeps()
    }
    Component.onCompleted: {
        // steps already configured (e.g. whoever reopens the procedure): marked as done
        var o = {}
        for (var i = 0; i < steps.length; i++) {
            var s = steps[i]
            if (s.fields && Setup.value(s.fields[s.fields.length - 1].key) !== "") o[s.id] = "ok"
        }
        status = o
        if (Setup.debugStep >= 0) go(Setup.debugStep)
        refreshGames()                 // for the "Games" check mark in the left menu
        deps = Setup.dependencyReport()
        setStatus("system", depsMissingRequired ? "" : "ok")
    }

    function saveStep() {
        var m = {}
        for (var i = 0; i < step.fields.length; i++) m[step.fields[i].key] = valOf(step.fields[i].key).trim()
        Setup.save(m)
        setStatus(step.id, "ok")
        go(cur + 1)
    }
    function continueStep() {
        if (step.id === "games" && status["games"] !== "ok") setStatus("games", "skip")
        if (isInfo) { if (step.id === "done") close(); else go(cur + 1); return }
        var k = step.testWith
        var v = valOf(k).trim()
        if (v === "") { skipStep(); return }
        if (testState === "ok") { saveStep(); return }
        testState = "busy"; testMsg = ""; offlineFail = false
        Setup.test(k, v, step.testExtra ? valOf(step.testExtra) : "")
    }
    function skipStep() { if (status[step.id] !== "ok") setStatus(step.id, "skip"); go(cur + 1) }
    function close() { Setup.markDone(); wiz.finished() }

    Connections {
        target: Setup
        function onTestResult(name, ok, message) {
            if (wiz.isInfo || name !== wiz.step.testWith) return
            wiz.testState = ok ? "ok" : "fail"
            wiz.testMsg = message
            wiz.offlineFail = !ok && message.indexOf("connessione") >= 0
            if (ok) okHold.restart()          // the green check mark shows, then we move on
        }
    }
    Timer { id: okHold; interval: 700; onTriggered: if (wiz.testState === "ok") wiz.saveStep() }

    // To copy to the clipboard (Spotify's Redirect URI)
    TextEdit { id: clip; visible: false }
    function copyText(t) { clip.text = t; clip.selectAll(); clip.copy(); copiedTip.restart() }
    Timer { id: copiedTip; interval: 1600 }

    // ── componenti ──
    component WIcon: Item {
        property string src
        property color tint: wiz.txt
        width: 22; height: 22
        Image { id: _ic; anchors.fill: parent; source: "qrc:/VoltaApp/icons/" + parent.src
                sourceSize: Qt.size(Math.max(44, parent.width * 2), Math.max(44, parent.height * 2)); fillMode: Image.PreserveAspectFit; visible: false }
        ColorOverlay { anchors.fill: _ic; source: _ic; color: parent.tint }
    }
    // "real" icon (the one in the app menu): its own colors, no tint
    component AppIcon: Image {
        property string src
        source: src === "" ? "" : "qrc:/VoltaApp/icons/" + src
        sourceSize: Qt.size(width * 2, height * 2)
        fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
    }
    component WPrimary: Rectangle {
        id: _p
        property string label
        property bool enabledBtn: true
        signal clicked()
        width: Math.max(170, _pt.implicitWidth + 56); height: 48; radius: 8
        color: !enabledBtn ? (wiz.lightTheme ? "#A9C3F5" : "#2B3E66")
               : (_pm.pressed ? Qt.darker(wiz.accent, 1.2) : wiz.accent)
        Text { id: _pt; anchors.centerIn: parent; text: _p.label; color: "#FFFFFF"; font.pixelSize: 16; font.weight: Font.DemiBold }
        MouseArea { id: _pm; anchors.fill: parent; enabled: _p.enabledBtn; onClicked: _p.clicked() }
    }
    component WSecondary: Rectangle {
        id: _s
        property string label
        signal clicked()
        width: Math.max(150, _st.implicitWidth + 48); height: 48; radius: 8
        color: _sm.pressed ? (wiz.lightTheme ? "#C8C8C8" : "#4A4A4A") : wiz.ctrlBg
        Text { id: _st; anchors.centerIn: parent; text: _s.label; color: wiz.txt; font.pixelSize: 16; font.weight: Font.DemiBold }
        MouseArea { id: _sm; anchors.fill: parent; onClicked: _s.clicked() }
    }
    // tab name, step and dots (small): they sit above the big icon
    component StepHeader: Column {
        property bool centered: false
        spacing: 12
        Text {
            visible: wiz.step.id !== "welcome"
            text: wiz.step.title || ""
            color: wiz.txt; font.pixelSize: 32; font.weight: Font.DemiBold
        }
        Text {
            visible: wiz.step.id !== "welcome" && wiz.step.id !== "done"
            text: qsTr("Step ") + wiz.cur + qsTr(" of ") + (wiz.steps.length - 2) + (wiz.step.required ? "" : qsTr("  ·  optional"))
            color: wiz.txtSub; font.pixelSize: 17
        }
        Row {
            anchors.horizontalCenter: parent.centered ? parent.horizontalCenter : undefined
            spacing: 9
            Repeater {
                model: wiz.steps
                Item {
                    width: index === wiz.cur ? 40 : 12; height: 22
                    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width; height: 12; radius: 6
                        color: index === wiz.cur ? wiz.txt : (wiz.lightTheme ? "#CFCFCF" : "#6F7072")
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: wiz.go(index) }
                }
            }
        }
    }
    component WLink: Text {
        signal clicked()
        color: wiz.txtSub; font.pixelSize: 15; font.weight: Font.DemiBold
        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: parent.clicked() }
    }

    Item { id: topBar; width: parent.width; height: 96 }   // like the footer: the content stays centered

    // ══════════ CONTENUTO ══════════
    Item {
        id: content
        x: 0; y: topBar.height
        width: parent.width; height: parent.height - topBar.height
        // side margin: the column and the buttons sit in a central column of 720
        readonly property real sideX: Math.max(48, (width - 1180) / 2)

        Flickable {
            id: flick
            anchors.fill: parent; anchors.bottomMargin: footer.height
            contentHeight: Math.max(flick.height, body.height + 48)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: body
                x: content.sideX; y: Math.max(24, (flick.height - height) / 2)
                width: content.width - 2 * content.sideX
                spacing: 26
                // fade at every step change
                opacity: 1
                Connections { target: wiz; function onCurChanged() { fadeIn.restart() } }
                NumberAnimation on opacity { id: fadeIn; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic; running: false }

                // ─── WELCOME: just a greeting ───
                Column {
                    visible: wiz.step.id === "welcome"
                    width: parent.width; spacing: 36
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 104; height: 104; radius: 30
                        color: wiz.ctrlBg
                        AppIcon { anchors.centerIn: parent; src: "car.svg"; width: 56; height: 56 }
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Welcome")
                        color: wiz.txt; font.pixelSize: Math.round(44 * wiz.k); font.weight: Font.DemiBold
                    }
                    // Interface language: dropdown with flag, changes immediately (this screen too)
                    LanguagePicker {
                        id: langPick
                        anchors.horizontalCenter: parent.horizontalCenter
                        ctrlBg: wiz.ctrlBg; selBg: wiz.selBg; txt: wiz.txt; txtSub: wiz.txtSub; divider: wiz.divider
                    }
                    StepHeader { anchors.horizontalCenter: parent.horizontalCenter; centered: true; opacity: langPick.open ? 0 : 1 }
                }

                // ─── big icon on the left, line, content ───
                Row {
                    id: split
                    visible: wiz.step.id !== "welcome"
                    width: parent.width; spacing: 64
                    readonly property real iconW: 280
                    Item {
                        width: split.iconW; height: Math.max(leftCol.height, rightCol.height)
                        Column {
                            id: leftCol
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 26
                            StepHeader {}
                            Item {
                                width: split.iconW; height: 240
                                AppIcon {
                                    visible: (wiz.step.icon || "").indexOf("ms_") !== 0
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    src: wiz.step.icon || ""; width: 240; height: 240
                                }
                                WIcon {
                                    visible: (wiz.step.icon || "").indexOf("ms_") === 0
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    src: wiz.step.icon || "ms_check.svg"; width: 210; height: 210
                                }
                            }
                        }
                    }
                    Rectangle { width: 1; height: Math.max(leftCol.height, rightCol.height); color: wiz.divider }
                    Column {
                        id: rightCol
                        anchors.verticalCenter: parent.verticalCenter
                        width: split.width - split.iconW - 129
                        spacing: 26

                // ─── PASSO DI UN SERVIZIO ───
                Column {
                    visible: !wiz.isInfo
                    width: parent.width; spacing: 30

                    Text {
                        width: parent.width; wrapMode: Text.WordWrap; lineHeight: 1.25
                        text: wiz.step.desc || ""
                        color: wiz.txtSub; font.pixelSize: Math.round(17 * wiz.k)
                    }

                    // numbered instructions: dot and line on the left, text on the right
                    Column {
                        width: parent.width; spacing: 0
                        Repeater {
                            id: howtoRep
                            model: wiz.step.howto || []
                            Item {
                                width: parent.width; height: Math.max(_hw.height + 24, 56)
                                readonly property bool last: index === howtoRep.count - 1
                                // line leading to the next dot
                                Rectangle {
                                    visible: !parent.last
                                    x: 18.25; y: 46; width: 1.5; height: parent.height - 50
                                    color: wiz.divider
                                }
                                Rectangle {
                                    width: 38; height: 38; radius: 19
                                    color: "transparent"; border.width: 1.5; border.color: wiz.txtSub
                                    Text { anchors.centerIn: parent; text: index + 1; color: wiz.txt; font.pixelSize: Math.round(14 * wiz.k); font.weight: Font.DemiBold }
                                }
                                Text {
                                    id: _hw
                                    x: 62; y: 6; width: parent.width - 62; wrapMode: Text.WordWrap
                                    text: modelData; color: wiz.txt; font.pixelSize: Math.round(17 * wiz.k); lineHeight: 1.2
                                }
                            }
                        }
                        Item { visible: !!wiz.step.copyText; width: 1; height: 16 }
                        // address to copy (e.g. Spotify's Redirect URI)
                        Rectangle {
                            visible: !!wiz.step.copyText
                            width: parent.width; height: Math.round(56 * wiz.k); color: "transparent"
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: wiz.divider }
                            Text {
                                x: 0; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - copyBtn.width - 52; elide: Text.ElideRight
                                text: (wiz.step.copyLabel || "") + "   " + (wiz.step.copyText || "")
                                color: wiz.txt; font.pixelSize: Math.round(15 * wiz.k); font.family: "monospace"
                            }
                            WLink {
                                id: copyBtn
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: copiedTip.running ? qsTr("Copied ✓") : qsTr("Copy")
                                color: wiz.txt
                                onClicked: wiz.copyText(wiz.step.copyText)
                            }
                        }
                    }

                    // campi chiave
                    Repeater {
                        model: wiz.isInfo ? [] : wiz.step.fields
                        Column {
                            width: parent.width; spacing: 10
                            Text { text: modelData.label; color: wiz.txtSub; font.pixelSize: Math.round(14 * wiz.k); font.weight: Font.Medium }
                            Rectangle {
                                width: parent.width; height: Math.round(60 * wiz.k); radius: 14; color: wiz.ctrlBg
                                border.width: input.activeFocus ? 2 : 0; border.color: wiz.txtSub
                                TextInput {
                                    id: input
                                    x: 18; width: parent.width - pasteBtn.width - 52
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: wiz.valOf(modelData.key)
                                    color: wiz.txt; font.pixelSize: Math.round(17 * wiz.k); font.family: "monospace"
                                    clip: true; selectByMouse: true
                                    echoMode: modelData.secret && !input.activeFocus && text !== "" ? TextInput.Password : TextInput.Normal
                                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
                                    onTextEdited: { wiz.setVal(modelData.key, text); wiz.testState = ""; wiz.testMsg = "" }
                                    // an already saved key is seen from the beginning, not from the end
                                    Component.onCompleted: cursorPosition = 0
                                    onActiveFocusChanged: if (!activeFocus) cursorPosition = 0
                                    Text {
                                        visible: input.text === ""
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.hint; color: wiz.txtHint; font: input.font
                                    }
                                }
                                WLink {
                                    id: pasteBtn
                                    anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                                    text: input.text === "" ? qsTr("Paste") : qsTr("Delete")
                                    color: wiz.txt
                                    onClicked: {
                                        var t = input.text === "" ? Setup.clipboardText() : ""
                                        input.text = t
                                        wiz.setVal(modelData.key, t); wiz.testState = ""; wiz.testMsg = ""
                                    }
                                }
                            }
                        }
                    }

                    // outcome of the check
                    Row {
                        visible: wiz.testState !== ""
                        spacing: 10; height: 26
                        Spinner { visible: wiz.testState === "busy"; running: visible; size: 20; anchors.verticalCenter: parent.verticalCenter }
                        WIcon {
                            visible: wiz.testState === "ok"
                            src: "ms_check.svg"; anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            visible: wiz.testState === "fail"
                            anchors.verticalCenter: parent.verticalCenter
                            text: "!"; color: wiz.txt; font.pixelSize: Math.round(18 * wiz.k); font.weight: Font.Bold
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: wiz.testState === "busy" ? qsTr("Verifying the key…") : wiz.testMsg
                            color: wiz.testState === "busy" ? wiz.txtSub : wiz.txt
                            font.pixelSize: Math.round(15 * wiz.k)
                        }
                        WLink {
                            visible: wiz.offlineFail
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("   Save without verifying"); color: wiz.txt
                            onClicked: wiz.saveStep()
                        }
                    }
                    Text {
                        visible: !!wiz.step.required && wiz.valOf(wiz.step.testWith) === "" && wiz.status[wiz.step.id] !== "ok"
                        width: parent.width; wrapMode: Text.WordWrap
                        text: qsTr("Without this key the map can't work. You can still add it later.")
                        color: wiz.txtHint; font.pixelSize: Math.round(14 * wiz.k)
                    }
                }

                // ─── SYSTEM CHECK ───
                Column {
                    visible: wiz.step.id === "system"
                    width: parent.width; spacing: 26
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap; lineHeight: 1.25
                        text: wiz.step.desc || ""
                        color: wiz.txtSub; font.pixelSize: Math.round(17 * wiz.k)
                    }
                    Text {
                        visible: !wiz.depsMissingRequired && wiz.deps.length > 0
                        width: parent.width; wrapMode: Text.WordWrap
                        text: qsTr("Everything required is installed.")
                        color: wiz.txt; font.pixelSize: Math.round(17 * wiz.k); font.weight: Font.DemiBold
                    }
                    Column {
                        width: Math.min(parent.width, 720); spacing: 8
                        Repeater {
                            model: wiz.deps
                            Rectangle {
                                width: parent.width; height: _dc.height + 32; color: "transparent"
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: wiz.divider }
                                Column {
                                    id: _dc
                                    x: 0; y: 16; width: parent.width - 170; spacing: 4
                                    Text { text: modelData.title + (modelData.required ? "" : qsTr("  ·  optional")); color: wiz.txt
                                           font.pixelSize: Math.round(16 * wiz.k); font.weight: Font.DemiBold }
                                    Text { width: parent.width; wrapMode: Text.WordWrap; text: modelData.ok ? modelData.what : modelData.how
                                           color: wiz.txtSub; font.pixelSize: Math.round(14 * wiz.k) }
                                    Text { visible: !modelData.ok; width: parent.width; wrapMode: Text.WrapAnywhere; text: modelData.what
                                           color: wiz.txtHint; font.pixelSize: Math.round(13 * wiz.k) }
                                    Text { visible: !modelData.ok; width: parent.width; wrapMode: Text.WrapAnywhere; text: modelData.cmd
                                           color: wiz.txt; font.pixelSize: Math.round(14 * wiz.k); font.family: "monospace" }
                                }
                                Text {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.ok ? qsTr("Installed") : (modelData.required ? qsTr("Missing") : qsTr("Not installed"))
                                    color: modelData.ok ? wiz.txt : wiz.txtHint
                                    font.pixelSize: Math.round(15 * wiz.k); font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                    WLink { text: qsTr("Check again"); color: wiz.txt; onClicked: wiz.refreshDeps() }
                }

                // ─── GAMES ───
                Column {
                    visible: wiz.step.id === "games"
                    width: parent.width; spacing: 30
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap; lineHeight: 1.25
                        text: wiz.step.desc || ""
                        color: wiz.txtSub; font.pixelSize: Math.round(17 * wiz.k)
                    }
                    // what is needed, with its status
                    Column {
                        width: Math.min(parent.width, 720); spacing: 8
                        Repeater {
                            model: [
                                { t: qsTr("Bottles"), d: qsTr("Installs and runs Windows games"), ok: wiz.gamesSt.bottles,
                                  how: qsTr("Install it from the Software app (search «Bottles») or from the terminal:"),
                                  cmd: "flatpak install flathub com.usebottles.bottles" },
                                { t: "gamescope", d: qsTr("Shows the game fullscreen inside the UI"), ok: wiz.gamesSt.gamescope,
                                  how: qsTr("Install it from the terminal:"), cmd: "sudo apt install gamescope" }
                            ]
                            Rectangle {
                                width: parent.width; height: _gc.height + 32; color: "transparent"
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: wiz.divider }
                                Column {
                                    id: _gc
                                    x: 0; y: 16; width: parent.width - 150; spacing: 4
                                    Text { text: modelData.t; color: wiz.txt; font.pixelSize: Math.round(16 * wiz.k); font.weight: Font.DemiBold }
                                    Text { width: parent.width; wrapMode: Text.WordWrap; text: modelData.ok ? modelData.d : modelData.how
                                           color: wiz.txtSub; font.pixelSize: Math.round(14 * wiz.k) }
                                    Text { visible: !modelData.ok; width: parent.width; wrapMode: Text.WrapAnywhere; text: modelData.cmd
                                           color: wiz.txt; font.pixelSize: Math.round(14 * wiz.k); font.family: "monospace" }
                                }
                                Text {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.ok ? qsTr("Installed") : qsTr("To install")
                                    color: modelData.ok ? wiz.txt : wiz.txtHint
                                    font.pixelSize: Math.round(15 * wiz.k); font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                    // games found + add some
                    Row {
                        spacing: 30
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: wiz.gamesFound > 0 ? (wiz.gamesFound === 1 ? qsTr("1 game found in Bottles") : wiz.gamesFound + qsTr(" games found in Bottles"))
                                : wiz.gamesFound === 0 ? qsTr("No games yet: add one in Bottles")
                                : qsTr("Looking for games…")
                            color: wiz.gamesFound > 0 ? wiz.txt : wiz.txtSub; font.pixelSize: Math.round(16 * wiz.k)
                        }
                        WPrimary {
                            visible: wiz.gamesSt.bottles
                            label: qsTr("Open Bottles")
                            onClicked: Setup.openBottles()
                        }
                        WLink { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Refresh"); color: wiz.txt; onClicked: wiz.refreshGames() }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: qsTr("In Bottles: create a «Gaming» bottle, install the game and add it with «Add shortcut». Then tap Refresh.")
                        color: wiz.txtHint; font.pixelSize: Math.round(14 * wiz.k)
                    }
                }

                // ─── FINE ───
                Column {
                    visible: wiz.step.id === "done"
                    width: parent.width; spacing: 30
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: qsTr("Here's what you've connected. Tap a service to change it; you can also find it in Settings › System.")
                        color: wiz.txtSub; font.pixelSize: Math.round(17 * wiz.k)
                    }
                    Column {
                        width: Math.min(parent.width, 620); spacing: 8
                        Repeater {
                            model: wiz.steps.filter(function(x) { return !!x.fields || x.id === "games" })
                            Rectangle {
                                width: parent.width; height: Math.round(60 * wiz.k); color: "transparent"
                                readonly property string st: wiz.status[modelData.id] || ""
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: wiz.divider }
                                AppIcon { x: 0; anchors.verticalCenter: parent.verticalCenter; src: modelData.icon; width: 42; height: 42 }
                                Text { x: 66; anchors.verticalCenter: parent.verticalCenter; text: modelData.title; color: wiz.txt; font.pixelSize: Math.round(16 * wiz.k) }
                                Text {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    text: parent.st === "ok" ? qsTr("Connected") : (parent.st === "skip" ? qsTr("Skipped") : qsTr("To do"))
                                    color: parent.st === "ok" ? wiz.txt : wiz.txtHint
                                    font.pixelSize: Math.round(15 * wiz.k); font.weight: Font.DemiBold
                                }
                                MouseArea { anchors.fill: parent; onClicked: wiz.go(wiz.steps.indexOf(modelData)) }
                            }
                        }
                    }
                }
                    }   // rightCol
                }       // split
            }
        }

        // ══════════ BUTTONS AT THE BOTTOM ══════════
        Item {
            id: footer
            anchors.bottom: parent.bottom; width: parent.width; height: 96
            Row {
                // in the welcome the button is in the center, in the other steps on the right
                x: wiz.step.id === "welcome" ? (parent.width - width) / 2 : parent.width - width - content.sideX
                anchors.verticalCenter: parent.verticalCenter
                spacing: 24
                WSecondary {
                    visible: wiz.cur > 0
                    anchors.verticalCenter: parent.verticalCenter
                    label: qsTr("Back")
                    onClicked: wiz.go(wiz.cur - 1)
                }
                WPrimary {
                    label: wiz.step.id === "welcome" ? qsTr("Start")
                         : wiz.step.id === "done" ? qsTr("Done")
                         : (wiz.step.id === "games" || wiz.step.id === "system") ? qsTr("Continue")
                         : wiz.testState === "busy" ? qsTr("Verifying…")
                         : (wiz.valOf(wiz.step.testWith || "").trim() === "" ? qsTr("Continue without") : qsTr("Continue"))
                    enabledBtn: wiz.testState !== "busy"
                    onClicked: wiz.continueStep()
                }
            }
        }
    }
}
