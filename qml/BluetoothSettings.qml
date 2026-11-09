import QtQuick
import QtQuick.Shapes

// REAL Bluetooth panel: drives BlueZ (D-Bus) through
// network_settings_service.py (porta 9097).
Item {
    id: root
    implicitHeight: _btCol.implicitHeight
    height: implicitHeight
    property color txt
    property color txtSub
    property color txtHint
    property color ctrlBg
    property color ctrlBrd
    property color blue
    property color divider
    property bool lightTheme

    readonly property string backendUrl: "http://127.0.0.1:9097"

    property bool poweredOn: false
    property bool discovering: false
    property bool adapterAvailable: true
    property var devices: []
    property string statusMsg: ""
    property string busyAddress: ""   // device on which an action is in progress

    function xhrCall(method, path, body, cb) {
        var xhr = new XMLHttpRequest()
        xhr.open(method, root.backendUrl + path)
        if (body) xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                var d = null
                try { d = JSON.parse(xhr.responseText) } catch (e) {}
                if (cb) cb(xhr.status, d)
            }
        }
        xhr.send(body ? JSON.stringify(body) : undefined)
    }

    function refreshStatus() {
        xhrCall("GET", "/bt/status", null, function(status, d) {
            if (!d) return
            root.poweredOn = !!d.poweredOn
            root.discovering = !!d.discovering
            root.adapterAvailable = d.available !== false
        })
    }

    function refreshDevices() {
        xhrCall("GET", "/bt/devices", null, function(status, d) {
            if (d && d.devices) root.devices = d.devices
        })
    }

    function togglePower(on) {
        xhrCall("POST", "/bt/toggle", {on: on}, function() {
            root.refreshStatus()
            if (on) root.startScan()
        })
    }

    property bool scanned: false          // true after at least one finished scan
    function startScan() {
        root.scanned = false
        xhrCall("POST", "/bt/scan", {on: true}, function(status, d) {
            if (!d || !d.ok) root.statusMsg = qsTr("Search failed: ") + (d && d.message ? d.message : qsTr("the Bluetooth service isn't responding"))
            else root.statusMsg = ""
            root.refreshStatus()
        })
        _scanStopTimer.restart()
    }

    function deviceAction(address, action) {
        root.busyAddress = address
        xhrCall("POST", "/bt/" + action, {address: address}, function(status, d) {
            root.busyAddress = ""
            if (!d || !d.ok) root.statusMsg = qsTr("Operation failed: ") + (d ? d.message : "")
            else root.statusMsg = ""
            root.refreshDevices()
        })
    }

    // Same reason as the Wi-Fi panel: without a computed height the root
    // Item stays at 0 and the parent Column does not reserve space for it (see
    // implicitHeight/height declared right after id, above).

    // ── pairing request (PIN) shown by the service ──
    property var pairReq: null
    function pairName() {
        if (!root.pairReq) return ""
        var p = String(root.pairReq.device || "")
        for (var i = 0; i < root.devices.length; i++)
            if (root.devices[i].path === p) return root.devices[i].name || qsTr("Device")
        return qsTr("Device")
    }
    function pollPair() {
        xhrCall("GET", "/bt/pair/request", null, function(status, d) {
            var r = (d && d.request) ? d.request : null
            if (!r && root.pairReq === null) return
            if (r && root.pairReq && r.id === root.pairReq.id && r.passkey === root.pairReq.passkey && r.kind === root.pairReq.kind) return
            root.pairReq = r
        })
    }
    function answerPair(ok) {
        root.pairReq = null
        xhrCall("POST", "/bt/pair/answer", {accept: ok}, function() {})
    }
    Timer { interval: 1000; running: root.poweredOn && root.visible; repeat: true; onTriggered: root.pollPair() }

    // Automatic scan when the page opens (as on EVs)
    onVisibleChanged: if (visible) { refreshStatus(); refreshDevices(); _autoScan.restart() }
    Timer {
        id: _autoScan
        interval: 700
        onTriggered: {
            if (root.visible && root.poweredOn && !root.discovering && root.pairReq === null) root.startScan()
        }
    }

    Component.onCompleted: { refreshStatus(); refreshDevices() }
    Timer { interval: 3000; running: root.poweredOn; repeat: true; onTriggered: root.refreshDevices() }
    Timer { id: _scanStopTimer; interval: 20000; onTriggered: root.xhrCall("POST", "/bt/scan", {on:false}, function(){ root.scanned = true; root.refreshStatus(); root.refreshDevices() }) }

    // ── Device icons (same logic as the Bluetooth page) ──
    component PhoneGlyph: Item {
        id: _pg
        property color tint: root.txt
        width: 26; height: 26
        Rectangle {
            anchors.centerIn: parent
            width: 13; height: 22; radius: 3
            color: "transparent"
            border.width: 2; border.color: _pg.tint
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                width: 3.5; height: 2; radius: 1
                color: _pg.tint
            }
        }
    }
    component MdiIcon: Item {
        id: _mi
        property string path: ""
        property color tint: root.txt
        property real size: 24
        width: size; height: size
        Shape {
            width: 24; height: 24
            scale: _mi.size / 24
            transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: _mi.tint; strokeColor: "transparent"
                fillRule: ShapePath.WindingFill
                PathSvg { path: _mi.path }
            }
        }
    }
    readonly property var mdiPaths: ({
        "bluetooth": "M14.88 16.29 13 18.17v-3.76m0-8.58 1.88 1.88L13 9.58m4.71-1.87L12 2h-1v7.58L6.41 5 5 6.41 10.59 12 5 17.58 6.41 19 11 14.41V22h1l5.71-5.71-4.3-4.29z",
        "headphones": "M12 1c-5 0-9 4-9 9v7a3 3 0 0 0 3 3h3v-8H5v-2a7 7 0 0 1 7-7 7 7 0 0 1 7 7v2h-4v8h3a3 3 0 0 0 3-3v-7c0-5-4.03-9-9-9",
        "headset": "M12 1c-5 0-9 4-9 9v7a3 3 0 0 0 3 3h3v-8H5v-2a7 7 0 0 1 7-7 7 7 0 0 1 7 7v2h-4v8h4v1h-7v2h6a3 3 0 0 0 3-3V10c0-5-4.03-9-9-9",
        "gamepad": qsTr("M7 6h10a6 6 0 0 1 6 6 6 6 0 0 1-6 6c-1.78 0-3.37-.77-4.47-2h-1.06c-1.1 1.23-2.69 2-4.47 2a6 6 0 0 1-6-6 6 6 0 0 1 6-6M6 9v2H4v2h2v2h2v-2h2v-2H8V9zm9.5 3a1.5 1.5 0 0 0-1.5 1.5 1.5 1.5 0 0 0 1.5 1.5 1.5 1.5 0 0 0 1.5-1.5 1.5 1.5 0 0 0-1.5-1.5m3-3a1.5 1.5 0 0 0-1.5 1.5 1.5 1.5 0 0 0 1.5 1.5 1.5 1.5 0 0 0 1.5-1.5A1.5 1.5 0 0 0 18.5 9"),
        "keyboard": "M19 10h-2V8h2m0 5h-2v-2h2m-3-1h-2V8h2m0 5h-2v-2h2m0 6H8v-2h8m-9-5H5V8h2m0 5H5v-2h2m1 0h2v2H8m0-5h2v2H8m3 1h2v2h-2m0-5h2v2h-2m9-5H4c-1.11 0-2 .89-2 2v10a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2",
        "mouse": "M11 1.07C7.05 1.56 4 4.92 4 9h7m-7 6a8 8 0 0 0 8 8 8 8 0 0 0 8-8v-4H4m9-9.93V9h7c0-4.08-3.06-7.44-7-7.93",
        "speaker": "M12 12a3 3 0 0 0-3 3 3 3 0 0 0 3 3 3 3 0 0 0 3-3 3 3 0 0 0-3-3m0 8a5 5 0 0 1-5-5 5 5 0 0 1 5-5 5 5 0 0 1 5 5 5 5 0 0 1-5 5m0-16a2 2 0 0 1 2 2 2 2 0 0 1-2 2 2 2 0 0 1-2-2c0-1.11.89-2 2-2m5-2H7c-1.11 0-2 .89-2 2v16a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2",
        "laptop": "M4 6h16v10H4m16 2a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2H4c-1.11 0-2 .89-2 2v10a2 2 0 0 0 2 2H0v2h24v-2z",
        "monitor": "M21 16H3V4h18m0-2H3c-1.11 0-2 .89-2 2v12a2 2 0 0 0 2 2h7v2H8v2h8v-2h-2v-2h7a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2",
        "tablet": "M19 18H5V6h14m2-2H3c-1.11 0-2 .89-2 2v12a2 2 0 0 0 2 2h18a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2",
        "watch": "M6 12a6 6 0 0 1 6-6 6 6 0 0 1 6 6 6 6 0 0 1-6 6 6 6 0 0 1-6-6m14 0a7.94 7.94 0 0 0-3.05-6.27L16 0H8l-.95 5.73A7.94 7.94 0 0 0 4 12c0 2.54 1.19 4.81 3.05 6.27L8 24h8l.95-5.73A7.96 7.96 0 0 0 20 12",
        "earbuds": qsTr("M5 3C3 3 2 5 2 6v5c0 1 1 3 3 3 .61 0 1.32-.28 2-.73V20c0 .55.45 1 1 1h1c.55 0 1-.45 1-1V8c0-2-3-5-5-5m3 7.23L5.91 11.6c-.51.33-.83.4-.91.4-.7 0-1-.92-1-1V6.03C4 5.92 4.3 5 5 5c.9 0 3 2.1 3 3zM16.5 15c.7 0 1.37-.11 2-.32V20c0 .55-.45 1-1 1h-2c-.55 0-1-.45-1-1v-5.32c.63.21 1.3.32 2 .32m0-12C13.46 3 11 5.46 11 8.5s2.46 5.5 5.5 5.5S22 11.54 22 8.5 19.54 3 16.5 3m0 9c-1.93 0-3.5-1.57-3.5-3.5S14.57 5 16.5 5 20 6.57 20 8.5 18.43 12 16.5 12"),
        "car": qsTr("M5 14h14l-1.5-4.5h-11zm12.5 5a1.5 1.5 0 0 0 1.5-1.5 1.5 1.5 0 0 0-1.5-1.5 1.5 1.5 0 0 0-1.5 1.5 1.5 1.5 0 0 0 1.5 1.5m-11 0A1.5 1.5 0 0 0 8 17.5 1.5 1.5 0 0 0 6.5 16 1.5 1.5 0 0 0 5 17.5 1.5 1.5 0 0 0 6.5 19M18.92 9 21 15v8a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1v-1H6v1a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-8l2.08-6c.2-.58.77-1 1.42-1h11c.65 0 1.22.42 1.42 1M12 0c2.12 0 4.15.86 5.65 2.35l-1.42 1.42A6.02 6.02 0 0 0 12 2c-1.58 0-3.11.65-4.23 1.77L6.36 2.35A8 8 0 0 1 12 0m0 4c1.06 0 2.07.44 2.82 1.18L13.4 6.6c-.37-.37-.87-.6-1.4-.6-.5 0-1.03.23-1.4.6L9.18 5.18C9.93 4.44 10.94 4 12 4"),
        "printer": "M18 3H6v4h12m1 5a1 1 0 0 1-1-1 1 1 0 0 1 1-1 1 1 0 0 1 1 1 1 1 0 0 1-1 1m-3 7H8v-5h8m3-6H5a3 3 0 0 0-3 3v6h4v4h12v-4h4v-6a3 3 0 0 0-3-3",
        "microphone": "M12 2a3 3 0 0 1 3 3v6a3 3 0 0 1-3 3 3 3 0 0 1-3-3V5a3 3 0 0 1 3-3m7 9c0 3.53-2.61 6.44-6 6.93V21h-2v-3.07c-3.39-.49-6-3.4-6-6.93h2a5 5 0 0 0 5 5 5 5 0 0 0 5-5z"
    })
    function mdiPath(kind) { return mdiPaths[kind] || mdiPaths["bluetooth"] }
    function devKind(d) {
        var ic = String((d && d.icon) || "").toLowerCase()
        var nm = String((d && d.name) || "").toLowerCase()
        if (ic === "phone") return "phone"
        if (ic.indexOf("gaming") >= 0 || /controller|gamepad|joypad|xbox|dualsense|dualshock|playstation|joy-con/.test(nm)) return "gamepad"
        if (ic.indexOf("keyboard") >= 0 || /keyboard|tastiera/.test(nm)) return "keyboard"
        if (ic.indexOf("mouse") >= 0 || /mouse/.test(nm)) return "mouse"
        if (/buds|airpods|earbuds|auricolari/.test(nm)) return "earbuds"
        if (ic.indexOf("headphones") >= 0 || /headphone|cuffie/.test(nm)) return "headphones"
        if (ic.indexOf("headset") >= 0) return "headset"
        if (ic.indexOf("speaker") >= 0 || ic === "audio-card" || /speaker|soundbar|boombox|altoparlante/.test(nm)) return "speaker"
        if (/watch|smartband/.test(nm)) return "watch"
        if (ic === "computer" || /laptop|notebook|macbook/.test(nm)) return "laptop"
        if (ic.indexOf("tablet") >= 0 || /ipad|tablet/.test(nm)) return "tablet"
        if (ic === "video-display" || /\btv\b/.test(nm)) return "monitor"
        if (ic === "printer") return "printer"
        if (ic.indexOf("microphone") >= 0 || /\bmic\b/.test(nm)) return "microphone"
        if (/\bcar\b|\bauto\b/.test(nm)) return "car"
        if (ic === "") return "phone"
        return "bluetooth"
    }

    // Row of a device: icon, name, status; on the right "Connect"/"Pair" and arrow
    component DevRow: Rectangle {
        id: _dr
        property var dev: ({})
        property bool nearby: false          // true = device found, not yet paired
        property bool expanded: false
        readonly property bool isConnected: !!dev.connected
        readonly property bool isBusy: root.busyAddress === dev.address
        readonly property string kind: root.devKind(dev)
        width: parent ? parent.width : 400
        height: 74 + (expanded ? 56 : 0)
        radius: 8
        color: root.ctrlBg
        clip: true
        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // top part (always visible)
        Item {
            id: _top
            width: parent.width; height: 74
            PhoneGlyph { x: 22; anchors.verticalCenter: parent.verticalCenter; visible: _dr.kind === "phone" }
            MdiIcon {
                x: 22; anchors.verticalCenter: parent.verticalCenter
                visible: _dr.kind !== "phone"
                path: root.mdiPath(_dr.kind)
            }
            Column {
                x: 66; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 66 - 170; spacing: 4
                Text {
                    text: _dr.dev.name || qsTr("Unknown device")
                    color: root.txt; font.pixelSize: 17; font.weight: Font.DemiBold
                    width: parent.width; elide: Text.ElideRight
                }
                Row {
                    spacing: 7
                    Text {
                        text: _dr.isBusy ? "…" : (_dr.nearby ? qsTr("Available") : (_dr.isConnected ? qsTr("Connected") : qsTr("Not connected")))
                        color: root.txtSub; font.pixelSize: 13
                    }
                    Rectangle {
                        visible: _dr.isConnected && !_dr.isBusy
                        width: 7; height: 7; radius: 3.5; color: "#3DCB5A"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        visible: _dr.isConnected && !_dr.nearby && _dr.kind === "phone"
                        text: "★"; color: "#F5A623"; font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
            // azione veloce a destra
            Text {
                id: _quick
                visible: _dr.nearby || !_dr.isConnected
                anchors.right: _chev.left; anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: _dr.nearby ? qsTr("Pair") : qsTr("Connect")
                color: root.txt; font.pixelSize: 16; font.weight: Font.Medium
                MouseArea {
                    anchors.fill: parent; anchors.margins: -14
                    onClicked: root.deviceAction(_dr.dev.address, _dr.nearby ? "pair" : "connect")
                }
            }
            Canvas {
                id: _chev
                visible: !_dr.nearby
                width: 14; height: 9
                anchors.right: parent.right; anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                rotation: _dr.expanded ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                property color col: root.txtSub
                onColChanged: requestPaint()
                onPaint: {
                    var c = getContext("2d"); c.clearRect(0, 0, width, height)
                    c.strokeStyle = col; c.lineWidth = 2; c.lineCap = "round"; c.lineJoin = "round"
                    c.beginPath(); c.moveTo(1.5, 1.5); c.lineTo(width / 2, height - 1.5); c.lineTo(width - 1.5, 1.5); c.stroke()
                }
                MouseArea { anchors.fill: parent; anchors.margins: -18; onClicked: _dr.expanded = !_dr.expanded }
            }
            // tapping the row (not the button) opens/closes the details
            MouseArea {
                z: -1
                anchors.fill: parent
                enabled: !_dr.nearby
                onClicked: _dr.expanded = !_dr.expanded
            }
        }

        // details: actions on the device
        Row {
            visible: _dr.expanded && !_dr.nearby
            x: 66; y: 74; height: 56
            spacing: 36
            Text {
                visible: _dr.isConnected
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Disconnect"); color: root.txt; font.pixelSize: 15; font.weight: Font.Medium
                MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: { _dr.expanded = false; root.deviceAction(_dr.dev.address, "disconnect") } }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Forget"); color: "#E05252"; font.pixelSize: 15; font.weight: Font.Medium
                MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: { _dr.expanded = false; root.deviceAction(_dr.dev.address, "forget") } }
            }
        }
    }

    Column {
        id: _btCol
        width: parent.width; spacing: 14

        // ── pairing request (PIN) ──
        Rectangle {
            id: _pairCard
            visible: root.pairReq !== null
            width: parent.width
            height: _pairCol.implicitHeight + 36
            radius: 8
            color: root.ctrlBg
            border.width: 2; border.color: root.blue
            Column {
                id: _pairCol
                x: 22; y: 18; width: parent.width - 44; spacing: 10
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: root.pairReq ? qsTr("Pair «") + root.pairName() + "»" : ""
                    color: root.txt; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    visible: root.pairReq !== null
                    text: !root.pairReq ? "" : (root.pairReq.kind === "confirm" ? qsTr("Check that this code matches the one shown on the device.")
                        : (root.pairReq.kind === "display" ? qsTr("Type this code on the device.") : qsTr("The device wants to pair. Allow?")))
                    color: root.txtSub; font.pixelSize: 14
                }
                Text {
                    visible: !!(root.pairReq && root.pairReq.passkey)
                    text: root.pairReq && root.pairReq.passkey ? String(root.pairReq.passkey).replace(/(\d{3})(?=\d)/g, "$1 ") : ""
                    color: root.txt; font.pixelSize: 40; font.weight: Font.DemiBold; font.letterSpacing: 3
                }
                Row {
                    visible: !!(root.pairReq && root.pairReq.kind !== "display")
                    spacing: 12; topPadding: 4
                    Rectangle {
                        width: 150; height: 44; radius: 8
                        color: root.lightTheme ? "#E2E2E2" : "#3A3A3A"
                        Text { anchors.centerIn: parent; text: qsTr("Cancel"); color: root.txt; font.pixelSize: 16; font.weight: Font.Medium }
                        MouseArea { anchors.fill: parent; onClicked: root.answerPair(false) }
                    }
                    Rectangle {
                        width: 150; height: 44; radius: 8
                        color: root.blue
                        Text { anchors.centerIn: parent; text: qsTr("Confirm"); color: "#FFFFFF"; font.pixelSize: 16; font.weight: Font.Medium }
                        MouseArea { anchors.fill: parent; onClicked: root.answerPair(true) }
                    }
                }
            }
        }

        Text {
            visible: root.poweredOn
            text: qsTr("Paired devices")
            color: root.txt; font.pixelSize: 17; font.weight: Font.DemiBold
        }

        Text {
            visible: !root.adapterAvailable && root.poweredOn
            text: qsTr("No Bluetooth adapter found on the system.")
            color: root.txtHint; font.pixelSize: 13; width: parent.width; wrapMode: Text.WordWrap
        }
        Text {
            visible: root.statusMsg.length > 0
            text: root.statusMsg; color: root.txtHint; font.pixelSize: 13
        }

        // ── dispositivi abbinati ──
        Column {
            visible: root.poweredOn
            width: parent.width; spacing: 8
            Repeater {
                model: root.devices.filter(function(d) { return d.paired })
                DevRow { dev: modelData }
            }
            Text {
                visible: root.devices.filter(function(d) { return d.paired }).length === 0
                text: qsTr("No paired devices.")
                color: root.txtHint; font.pixelSize: 14; topPadding: 2
            }
        }

        // ── Bluetooth switch (same look as the EV switch: blue pill on the left, text on the right) ──
        Row {
            width: parent.width; spacing: 16; topPadding: 6
            TBtToggle {
                checked: root.poweredOn
                onToggled: on => root.togglePower(on)
            }
            Column {
                width: parent.width - 52 - 16; spacing: 4
                Text { text: qsTr("Bluetooth"); color: root.txt; font.pixelSize: 16; font.weight: Font.DemiBold }
                Text {
                    text: root.poweredOn ? qsTr("Turn it off to disconnect all devices.") : qsTr("Turn it on to connect your phone and other devices.")
                    color: root.txtSub; font.pixelSize: 14; width: parent.width; wrapMode: Text.WordWrap
                }
            }
        }

        // ── dispositivi nelle vicinanze ──
        Row {
            visible: root.poweredOn
            width: parent.width; spacing: 10; topPadding: 18
            Text { text: qsTr("Nearby devices"); color: root.txt; font.pixelSize: 17; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
            // (i)
            Rectangle {
                width: 20; height: 20; radius: 10
                color: "transparent"; border.width: 1.5; border.color: root.txtSub
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: "i"; color: root.txtSub; font.pixelSize: 12; font.weight: Font.Bold }
            }
            // spinner during the scan
            Spinner {
                id: _scanSpin
                visible: root.discovering
                size: 20; running: visible
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: !root.discovering
                text: qsTr("Search")
                color: root.blue; font.pixelSize: 15; font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.startScan() }
            }
        }

        Column {
            visible: root.poweredOn
            width: parent.width; spacing: 8
            Repeater {
                model: root.devices.filter(function(d) { return !d.paired })
                DevRow { dev: modelData; nearby: true }
            }
        }

        Text {
            visible: root.poweredOn && root.scanned && !root.discovering && root.devices.filter(function(d) { return !d.paired }).length === 0
            text: qsTr("No devices found. Check that it's on and discoverable, then tap «Search».")
            color: root.txtHint; font.pixelSize: 14; width: parent.width; wrapMode: Text.WordWrap
        }

        // ── help texts ──
        Text {
            visible: root.poweredOn
            width: parent.width; wrapMode: Text.WordWrap; topPadding: 6
            text: qsTr("Before the device can be added, make sure it's on and discoverable.")
            color: root.txt; font.pixelSize: 15
        }
        Text {
            visible: root.poweredOn
            width: parent.width; wrapMode: Text.WordWrap
            text: qsTr("Wireless controllers can be paired if they support Bluetooth Classic. See the user manual for more information on controller compatibility.")
            color: root.txt; font.pixelSize: 15
        }
    }

    component TBtToggle: Rectangle {
        id: tgl
        property bool checked: false
        signal toggled(bool on)
        width: 52; height: 30; radius: 15
        color: checked ? root.blue : (root.lightTheme ? "#D0D0D0" : "#5A5A5A")
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            width: 24; height: 24; radius: 12; color: "#FFFFFF"
            anchors.verticalCenter: parent.verticalCenter
            x: tgl.checked ? tgl.width - width - 3 : 3
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; onClicked: { tgl.checked = !tgl.checked; tgl.toggled(tgl.checked) } }
    }
    component TBtDivider: Rectangle { width: parent.width; height: 1; color: root.divider }
}
