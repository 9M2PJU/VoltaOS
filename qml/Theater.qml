import QtQuick
import QtQuick.Window
import QtWebEngine
import Qt5Compat.GraphicalEffects
import VoltaApp 1.0

// SMART THEATER — grid launcher + WebEngineView to play the
// selected service. The tile images can be customized by putting
// i PNG in volta_os/assets/theater/ (youtube, netflix, prime, disney, paramount)
// (or changing the `banner` property of each service) and the labels will disappear.
Rectangle {
    id: theater
    // Gradiente launcher: 262626 in alto → nero puro in basso
    gradient: Gradient {
        GradientStop { position: 0.0; color: lightTheme ? "#F5F5F5" : "#262626" }
        GradientStop { position: 1.0; color: lightTheme ? "#E6E6E6" : "#000000" }
    }
    clip: true

    property bool lightTheme: false
    property bool active: false               // true when it is the foreground app

    // URL currently open ("" = shows the grid launcher)
    property string currentUrl: ""
    // Full-screen container (Main.qml): apps open there, the Theater panel stays still
    property Item overlayHost: null
    property string currentName: ""

    // "Back" navigation — driven by the panel's handle (AppPanel)
    property bool canGoBack: currentUrl !== ""
    // closing the app returns to the Theater launcher, which is NOT full screen
    function goBack() { theater.currentUrl = "" }

    // Exposed to AppPanel for the global pause logic
    property alias webView: theaterWeb

    signal requestFullscreen(bool on)
    signal mediaActivated()
    // Menu Theater/Arcade in alto: preme "Arcade" -> chi instanzia Theater
    // (AppPanel) cambia app.
    signal switchToArcade()
    signal switchToToybox()

    // When the app is no longer active, return to the launcher and unload the webview
    onActiveChanged: if (!active) currentUrl = ""

    // ── Servizi ────────────────────────────────────────────────────────────
    // The banners are images ON DISK in the volta_os/assets/theater/ folder:
    // youtube.png, netflix.png, prime.png, disney.png, paramount.png
    // Replace those files with YOUR images (same name) and they will appear here.
    readonly property string bannerBase: appUrl + "/assets/theater/"
    property var services: [
        { key: "youtube",   name: "YouTube",     url: "https://m.youtube.com/",        accent: "#FF0000" },
        { key: "netflix",   name: "Netflix",     url: "https://www.netflix.com",       accent: "#E50914" },
        { key: "prime",     name: "Prime Video", url: "https://www.primevideo.com",    accent: "#1FA2FF" },
        { key: "disney",    name: "Disney+",     url: "https://www.disneyplus.com",    accent: "#2A6DF4" },
        { key: "paramount", name: "Paramount+",  url: "https://www.paramountplus.com", accent: "#0064FF" }
    ]

    // Emitted instead of opening the webview: AppPanel catches it (leftover
    // from the Waydroid era — today the handler in AppPanel.qml is empty, but the
    // signal must still exist for that QML assignment to be valid).
    signal openAndroidApp(string key)

    // User agent: YouTube in tablet mode (grid layout like on tablets), the other sites as desktop.
    readonly property string desktopUserAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    readonly property string youtubeUserAgent: "Mozilla/5.0 (Linux; Android 13; SM-X906C) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    function openService(url, name, key) {
        // the user agent must be set BEFORE loading the page
        theaterProfile.httpUserAgent = (key === "youtube") ? theater.youtubeUserAgent : theater.desktopUserAgent
        theater.currentUrl = url
        theater.currentName = name
        // The Theater apps open directly in fullscreen (see AppPanel):
        // here we immediately request the fullscreen state, as if the user had
        // pressed the dedicated button.
    }

    // ══════════════════════════════════════════════════════════════════════
    //  HEADER BAR — fixed at the top (does not scroll with the content),
    //  app icon on the left, Theater/Arcade menu centered over the full
    //  width (not just next to the icon). Same text style as the
    //  YT Music tabs (no background/pill).
    // ══════════════════════════════════════════════════════════════════════
    Item {
        id: headerBar
        visible: theater.currentUrl === ""
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 20
        height: 26
        z: 50

        Image {
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            source: "qrc:/VoltaApp/icons/theater.svg"
            sourceSize: Qt.size(26, 26)
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: 18

            Text {
                text: qsTr("Theater")
                color: lightTheme ? "#444444" : "#FFFFFF"
                font.pixelSize: 20; font.weight: Font.DemiBold
                // No MouseArea: we are already on Theater, the solid color
                // (vs. Arcade's muted one) shows the active state.
            }
            Text {
                text: "Arcade"
                color: lightTheme ? "#555555" : "#A2A3A5"
                font.pixelSize: 20; font.weight: Font.DemiBold
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    onClicked: theater.switchToArcade()
                }
            }
            Text {
                text: qsTr("Toybox")
                color: lightTheme ? "#555555" : "#A2A3A5"
                font.pixelSize: 20; font.weight: Font.DemiBold
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    onClicked: theater.switchToToybox()
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    //  LAUNCHER (griglia)
    // ══════════════════════════════════════════════════════════════════════
    Flickable {
        id: launcher
        anchors.fill: parent
        visible: theater.currentUrl === ""
        contentWidth: width
        contentHeight: Math.max(height, contentCol.height + 60)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: contentCol
            width: Math.min(launcher.width - 60, 1100)
            anchors.horizontalCenter: parent.horizontalCenter
            // Vertically centered to fill the page well
            y: Math.max(30, (launcher.height - height) / 2)
            spacing: 40

            // ── Header ───────────────────────────────────────────────────
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "S M A R T"
                    color: "#8A8A8A"
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    font.letterSpacing: 6
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "THEATER"
                    color: lightTheme ? "#171717" : "#FFFFFF"
                    font.pixelSize: 46
                    font.weight: Font.DemiBold
                    font.letterSpacing: 9
                }
            }

            // ── Griglia servizi ──────────────────────────────────────────
            Grid {
                id: grid
                width: parent.width
                columns: 3
                columnSpacing: 22
                rowSpacing: 22
                anchors.horizontalCenter: parent.horizontalCenter

                readonly property real cellW: (width - columnSpacing * (columns - 1)) / columns

                Repeater {
                    model: theater.services

                    Rectangle {
                        id: tile
                        width: grid.cellW
                        height: grid.cellW * 0.55
                        radius: 10
                        color: tileArea.pressed ? (lightTheme ? "#EDEDED" : "#1C1C1C") : (lightTheme ? "#FFFFFF" : "#111111")
                        border.width: 1
                        border.color: lightTheme ? "#DDDDDD" : "#242424"

                        Behavior on color { ColorAnimation { duration: 120 } }

                        // Banner: YOUR image from volta_os/assets/theater/<key>.png
                        Image {
                            id: banner
                            anchors.fill: parent
                            anchors.margins: 1
                            source: theater.bannerBase + modelData.key + ".png"
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                            smooth: true
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle { width: banner.width; height: banner.height; radius: 8 }
                            }
                        }

                        // Placeholder (service name) if the image is missing
                        Column {
                            anchors.centerIn: parent
                            spacing: 10
                            visible: !banner.visible

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 12; height: 12; radius: 6
                                color: modelData.accent
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.name
                                color: lightTheme ? "#171717" : "#F0F0F0"
                                font.pixelSize: 24
                                font.weight: Font.Normal
                                font.letterSpacing: 0.5
                            }
                        }

                        MouseArea {
                            id: tileArea
                            anchors.fill: parent
                            onClicked: theater.openService(modelData.url, modelData.name, modelData.key)
                        }
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    //  WEBVIEW (servizio aperto)
    // ══════════════════════════════════════════════════════════════════════
    // Web profile with data saved to disk (VoltaTheaterData). No "offTheRecord: false":
    // set before storageName it produced the warning "Storage name is empty...".
    // (Qt 6.9's WebEngineProfilePrototype does not work here: instance() is null while
    //  the WebEngineView is created, and setProfile(null) crashes.)
    SystemHelper { id: cookieSys; Component.onCompleted: cookieSys.persistCookies(theaterProfile, "theater") }
    WebEngineProfile {
        id: theaterProfile
        storageName: "VoltaTheaterData"
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
        httpUserAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    }

    Item {
        id: webWrap
        parent: (theater.overlayHost && theater.currentUrl !== "") ? theater.overlayHost : theater
        anchors.fill: parent
        visible: theater.currentUrl !== ""
        clip: true

        Rectangle { anchors.fill: parent; color: "#000000" }
        FullscreenBar { id: wbar; width: parent.width; onBackRequested: theater.goBack() }

        // Opening a service: the screen slides from the bottom to
        // the top (above the dock), like all the apps that start full
        // screen. The handle at the top stays visible here (unlike the
        // Toybox's Romance fireplace).
        transform: Translate { id: webSlideT; y: 0 }
        NumberAnimation {
            id: webSlideAnim
            target: webSlideT; property: "y"
            to: 0
            duration: 360; easing.type: Easing.OutCubic
        }
        onVisibleChanged: if (visible) {
            webSlideT.y = webWrap.height
            webSlideAnim.restart()
        }

        WebEngineView {
            settings.showScrollBars: false
            id: theaterWeb
            anchors.top: wbar.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            profile: theaterProfile
            url: theater.currentUrl
            settings.pluginsEnabled: true
            settings.javascriptEnabled: true
            settings.playbackRequiresUserGesture: false
            settings.allowRunningInsecureContent: false
            settings.javascriptCanAccessClipboard: true
            settings.localContentCanAccessRemoteUrls: true

            lifecycleState: (theater.active && theater.currentUrl !== "")
                            ? WebEngineView.LifecycleState.Active
                            : WebEngineView.LifecycleState.Discarded

            onRecentlyAudibleChanged: if (recentlyAudible) theater.mediaActivated()

            onFullScreenRequested: function(request) {
                request.accept()
            }
        }
    }
}
