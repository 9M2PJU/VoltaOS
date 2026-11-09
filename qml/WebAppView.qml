import QtQuick
import QtWebEngine
import VoltaApp 1.0

// A web app opened from the drawer: the site full screen, like an app, without an address
// bar. At the top only back, icon, name and reload.
Rectangle {
    id: wv
    property var entry: null              // { id, url, name, icon } from WebApps
    property bool lightTheme: false
    signal requestFullscreen(bool on)
    readonly property alias webView: web

    readonly property color txt:    lightTheme ? "#171717" : "#FFFFFF"
    readonly property color iconC:  lightTheme ? "#5A5A5A" : "#A2A3A5"
    readonly property color pressC: lightTheme ? "#E3E3E3" : "#2E2E2E"
    color: lightTheme ? "#FFFFFF" : "#171717"

    // The Browser (BrowserApp): web apps use ITS profile, so they have the same
    // logins and cookies, and the same user agent trick for the Google login.
    property var browser: null

    // ── intestazione ──
    Item {
        id: header
        width: parent.width; height: 56
        visible: !wv._fullscreen

        Image {
            id: hdrIcon
            anchors.left: parent.left; anchors.leftMargin: 18; anchors.verticalCenter: parent.verticalCenter
            width: 26; height: 26
            source: wv.entry ? wv.entry.icon : ""
            sourceSize: Qt.size(52, 52); fillMode: Image.PreserveAspectFit; smooth: true
        }
        Text {
            anchors.left: hdrIcon.right; anchors.leftMargin: 12
            anchors.right: reloadBtn.left; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: wv.entry ? wv.entry.name : ""
            color: wv.txt; font.pixelSize: 17; font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Rectangle {          // ricarica
            id: reloadBtn
            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
            width: 40; height: 40; radius: 20
            color: _relMA.pressed ? wv.pressC : "transparent"
            Text { anchors.centerIn: parent; text: web.loading ? "✕" : "↻"; color: wv.iconC; font.pixelSize: 19 }
            MouseArea { id: _relMA; anchors.fill: parent; onClicked: web.loading ? web.stop() : web.reload() }
        }
        // loading bar
        Rectangle {
            anchors.bottom: parent.bottom
            height: 2; color: "#1667F2"
            width: web.loading ? parent.width * web.loadProgress / 100 : 0
            visible: web.loading
        }
    }

    property bool _fullscreen: false
    WebEngineView {
        settings.showScrollBars: false
        id: web
        anchors.top: wv._fullscreen ? parent.top : header.bottom
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        profile: wv.browser.webProfile
        userScripts.collection: wv.browser.uaScripts
        url: wv.entry ? wv.entry.url : "about:blank"
        backgroundColor: wv.color
        settings.playbackRequiresUserGesture: false
        settings.javascriptCanAccessClipboard: true
        settings.fullScreenSupportEnabled: true
        // links that would open a new window stay inside the app
        // Google login: tablet user agent, as in the Browser (see BrowserApp.qml)
        onNavigationRequested: function(request) {
            if (!request.isMainFrame) return
            var b = wv.browser
            var tablet = b._isGoogleLogin(request.url)
            if (tablet === b._tabletUA) return
            b._tabletUA = tablet
            request.reject()
            var u = request.url
            var ua = tablet ? b.tabletUA : b.desktopUA
            Qt.callLater(function() { b.webProfile.httpUserAgent = ua; web.url = u })
        }
        onNewWindowRequested: function(request) { request.openIn(web) }
        onFullScreenRequested: function(request) {
            request.accept()
            wv._fullscreen = request.toggleOn
            wv.requestFullscreen(request.toggleOn)
        }
    }
}
