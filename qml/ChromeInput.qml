import QtQuick

// INPUT FOR THE BROWSER (Chrome in the compositor) — on-screen keyboard + scrolling.
//
// Chrome is a "separate" Wayland app: Qt's on-screen keyboard cannot type
// into its fields, and wheel/finger do not always arrive. Here we go through the
// DevTools protocol (already used by BrowserApp for back/forward/reload):
//   • a small function in the page signals when a text field is tapped
//     (and when it is left) → the on-screen keyboard appears / disappears;
//   • what you type (on-screen or physical keyboard) reaches the page with
//     Input.insertText / Input.dispatchKeyEvent;
//   • mouse wheel and finger drag (with inertia) scroll the page
//     with Input.dispatchMouseEvent (mouseWheel).
// BrowserApp collega: request() → socket DevTools, fromPage() ← Runtime.bindingCalled.
Item {
    id: ci

    // ── Da collegare ──
    property bool connected: false      // socket DevTools aperto
    property bool active: false         // the browser is the foreground app
    property real pageWidth: 0          // page width in CSS px (for the coordinates)
    signal request(string method, var params)
    signal refocusSurface()             // gives focus back to Chrome

    readonly property bool keyboardOpen: proxy.activeFocus

    // ── Function injected into the page ──
    readonly property string injectScript: [
        "(function(){",
        "if(window.__voltaKb)return;window.__voltaKb=1;",
        "var NON={button:1,checkbox:1,radio:1,submit:1,reset:1,file:1,image:1,range:1,color:1,hidden:1};",
        "function deep(){var a=document.activeElement;while(a&&a.shadowRoot&&a.shadowRoot.activeElement)a=a.shadowRoot.activeElement;return a;}",
        "function kind(e){if(!e)return '';var t=e.tagName;",
        "if(t==='IFRAME'||t==='FRAME')return 'frame';",
        "if(t==='TEXTAREA')return(e.readOnly||e.disabled)?'':'text';",
        "if(t==='INPUT'){var ty=(e.type||'text').toLowerCase();if(NON[ty]||e.readOnly||e.disabled)return '';return ty;}",
        "if(e.isContentEditable)return 'text';return '';}",
        "var last=null;",
        "function send(force){var e=deep(),k=kind(e);if(!force&&k===last)return;last=k;",
        "var r={k:k};",
        "if(k&&k!=='frame'&&e&&e.getBoundingClientRect){var b=e.getBoundingClientRect();r.t=Math.round(b.top);r.b=Math.round(b.bottom);r.h=window.innerHeight;}",
        "try{window.voltaKb(JSON.stringify(r));}catch(_){}",
        "if(r.b!==undefined&&r.b>window.innerHeight*0.5&&document.scrollingElement&&document.scrollingElement.scrollHeight>window.innerHeight+50){",
        "try{window.scrollBy({top:r.t-window.innerHeight*0.25,behavior:'smooth'});}catch(_){}}}",
        "document.addEventListener('focusin',function(){setTimeout(function(){send(false)},0)},true);",
        "document.addEventListener('focusout',function(){setTimeout(function(){send(false)},60)},true);",
        "document.addEventListener('pointerup',function(){setTimeout(function(){var k=kind(deep());if(k&&k!=='frame')send(true)},30)},true);",
        "if(document.readyState!=='loading')send(false);",
        "})();"
    ].join("")

    // To be called as soon as the DevTools socket is open.
    function setup() {
        request("Emulation.setFocusEmulationEnabled", { enabled: true })   // the page stays "active" even if Qt's focus is elsewhere
        request("Runtime.enable", {})
        request("Runtime.addBinding", { name: "voltaKb" })
        request("Page.addScriptToEvaluateOnNewDocument", { source: injectScript })
        request("Runtime.evaluate", { expression: injectScript })
    }

    // ── La pagina dice: campo toccato / uscito ──
    function fromPage(payload) {
        var p
        try { p = JSON.parse(payload) } catch (e) { return }
        if (!p || p.k === "frame") return          // focus inside an iframe: nothing changes
        if (p.k === "") { closeTimer.restart(); return }
        closeTimer.stop()
        showKeyboard(p.k)
    }
    function showKeyboard(kind) {
        if (!ci.active) return
        var h = Qt.ImhNone
        if (kind === "email" || kind === "url" || kind === "search" || kind === "password")
            h = Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
        if (kind === "password") h |= Qt.ImhSensitiveData
        if (kind === "number") h = Qt.ImhFormattedNumbersOnly
        if (kind === "tel")    h = Qt.ImhDialableCharactersOnly
        proxy.inputMethodHints = h
        if (!proxy.activeFocus) proxy.forceActiveFocus()
        Qt.inputMethod.show()
    }
    function hideKeyboard() {
        closeTimer.stop()
        if (proxy.activeFocus) {
            Qt.inputMethod.hide()
            proxy.focus = false
            ci.refocusSurface()
        }
    }
    onActiveChanged: if (!active) hideKeyboard()
    // small delay: clicking from one field to another the page first sends "leaving", then "entering"
    Timer { id: closeTimer; interval: 280; onTriggered: ci.hideKeyboard() }

    // ── What is typed ──
    function insertText(t) { if (t && t.length > 0) request("Input.insertText", { text: t }) }
    function sendKey(key, vk) {
        var down = { type: key === "Enter" ? "keyDown" : "rawKeyDown", key: key, code: key, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk }
        if (key === "Enter") down.text = "\r"
        request("Input.dispatchKeyEvent", down)
        request("Input.dispatchKeyEvent", { type: "keyUp", key: key, code: key, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk })
    }
    function keyPressed(ev) {
        var m = {}
        m[Qt.Key_Backspace] = ["Backspace", 8]; m[Qt.Key_Delete] = ["Delete", 46]
        m[Qt.Key_Return] = ["Enter", 13];       m[Qt.Key_Enter] = ["Enter", 13]
        m[Qt.Key_Tab] = ["Tab", 9];             m[Qt.Key_Escape] = ["Escape", 27]
        m[Qt.Key_Left] = ["ArrowLeft", 37];     m[Qt.Key_Right] = ["ArrowRight", 39]
        m[Qt.Key_Up] = ["ArrowUp", 38];         m[Qt.Key_Down] = ["ArrowDown", 40]
        m[Qt.Key_Home] = ["Home", 36];          m[Qt.Key_End] = ["End", 35]
        var s = m[ev.key]
        if (s) { sendKey(s[0], s[1]); ev.accepted = true; return }
        var mods = Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier
        if (ev.text && ev.text.length > 0 && ev.text.charCodeAt(0) >= 32 && !(ev.modifiers & mods)) {
            insertText(ev.text); ev.accepted = true
        }
    }

    // Invisible text field: it is the one that "receives" Qt's on-screen keyboard.
    TextInput {
        id: proxy
        objectName: "browserPageProxy"
        x: 0; y: 0; width: 1; height: 1
        opacity: 0
        activeFocusOnPress: false
        // text inserted by the keyboard engine (not as a single key): we forward it to the page
        onTextChanged: if (text.length > 0) { var t = text; text = ""; ci.insertText(t) }
        Keys.onPressed: function(ev) { ci.keyPressed(ev) }
    }

    // ── Scorrimento ──
    function scrollBy(x, y, dx, dy) {
        var s = (pageWidth > 0 && width > 0) ? pageWidth / width : 1
        request("Input.dispatchMouseEvent", { type: "mouseWheel", x: x * s, y: y * s, deltaX: dx * s, deltaY: dy * s })
    }
    Item {
        id: scrollLayer
        anchors.fill: parent
        enabled: ci.connected

        // mouse wheel / touchpad
        WheelHandler {
            id: wheel
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(ev) {
                var dx = ev.pixelDelta.x !== 0 ? ev.pixelDelta.x : ev.angleDelta.x * 0.8
                var dy = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : ev.angleDelta.y * 0.8
                ci.scrollBy(ev.x, ev.y, -dx, -dy)
            }
        }

        // finger drag, with inertia
        DragHandler {
            id: drag
            acceptedDevices: PointerDevice.TouchScreen
            target: null
            property real lastX: 0
            property real lastY: 0
            property real vx: 0
            property real vy: 0
            property double lastT: 0
            onActiveChanged: {
                if (active) {
                    lastX = 0; lastY = 0; vx = 0; vy = 0; lastT = Date.now(); coast.stop()
                } else {
                    if (Date.now() - lastT > 90) { vx = 0; vy = 0 }          // finger still before lifting: no inertia
                    if (Math.abs(vx) > 80 || Math.abs(vy) > 80) coast.start()
                }
            }
            onTranslationChanged: {
                if (!active) return
                var dx = translation.x - lastX, dy = translation.y - lastY
                lastX = translation.x; lastY = translation.y
                var now = Date.now(), dt = Math.max(1, now - lastT); lastT = now
                vx = vx * 0.6 + (dx / dt * 1000) * 0.4
                vy = vy * 0.6 + (dy / dt * 1000) * 0.4
                ci.scrollBy(centroid.position.x, centroid.position.y, -dx, -dy)
            }
        }
        Timer {
            id: coast
            interval: 16; repeat: true
            onTriggered: {
                drag.vx *= 0.94; drag.vy *= 0.94
                if (Math.abs(drag.vx) < 40 && Math.abs(drag.vy) < 40) { stop(); return }
                ci.scrollBy(ci.width / 2, ci.height / 2, -drag.vx * 0.016, -drag.vy * 0.016)
            }
        }
    }
}
