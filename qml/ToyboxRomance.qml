import QtQuick
import QtWebEngine
import VoltaApp 1.0

// TOYBOX › ROMANCE MODE — online fireplace video, looping, no controls.
// Full screen as before; closes with the back button at the top left,
// like the Theater apps and the games (no X on the video).
Rectangle {
    id: rm
    color: "#000000"
    visible: false
    clip: true

    readonly property string videoId: "L_LUpnjgPso"
    signal closed()

    transform: Translate { id: slideT; y: 0 }
    NumberAnimation { id: slideInAnim; target: slideT; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
    NumberAnimation {
        id: slideOutAnim; target: slideT; property: "y"; to: rm.height
        duration: 280; easing.type: Easing.InCubic
        onFinished: { rm.visible = false; web.loadHtml("<html></html>"); rm.closed() }
    }

    // Player with the YouTube APIs: until the video starts a black cover stays,
    // so the controls and the title that YouTube shows while loading are never seen.
    readonly property string pageHtml:
        "<html><head><style>html,body{margin:0;height:100%;background:#000;overflow:hidden}"
        + "iframe{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%) scale(1.35);border:0;"
        + "width:max(100vw,177.78vh);height:max(100vh,56.25vw);pointer-events:none}"
        + "#c{position:fixed;inset:0;background:#000;z-index:9;transition:opacity .8s}</style></head><body>"
        + "<div id='p'></div><div id='c'></div><script>"
        + "var c=document.getElementById('c');function hide(){c.style.opacity=0;setTimeout(function(){c.style.display='none'},900)}"
        + "setTimeout(hide,15000);"
        + "var t=document.createElement('script');t.src='https://www.youtube.com/iframe_api';document.head.appendChild(t);"
        + "function onYouTubeIframeAPIReady(){new YT.Player('p',{videoId:'" + videoId + "',"
        + "playerVars:{autoplay:1,controls:0,loop:1,playlist:'" + videoId + "',modestbranding:1,rel:0,iv_load_policy:3,disablekb:1,fs:0,playsinline:1,showinfo:0},"
        + "events:{onReady:function(e){e.target.playVideo()},"
        + "onStateChange:function(e){if(e.data===1)setTimeout(hide,1200);if(e.data===0)e.target.playVideo()}}})}"
        + "</script></body></html>"

    function open() {
        web.loadHtml(rm.pageHtml, "https://volta-romance.local/")
        rm.visible = true
        slideT.y = rm.height
        slideInAnim.restart()
    }
    function close() { slideOutAnim.restart() }

    WebEngineProfile {
        id: romanceProfile
        storageName: "VoltaRomanceData"
        httpUserAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    }

    FullscreenBar { id: bar; width: parent.width; onBackRequested: rm.close() }

    WebEngineView {
        settings.showScrollBars: false
        id: web
        anchors.top: bar.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        profile: romanceProfile
        settings.playbackRequiresUserGesture: false
        settings.javascriptEnabled: true
        lifecycleState: rm.visible ? WebEngineView.LifecycleState.Active : WebEngineView.LifecycleState.Discarded
    }

    // No controls on the video: touches do not reach the player
    MouseArea { anchors.fill: parent; anchors.topMargin: 30; hoverEnabled: true; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = true }
}
