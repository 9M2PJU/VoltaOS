import QtQuick
import QtQuick.VirtualKeyboard

// REAL Wi-Fi panel: drives NetworkManager through network_settings_service.py
// (porta 9097). Riusa i design token e i componenti (txt/txtSub/TToggle/ecc.)
// passed by the parent (Settings.qml), to stay visually consistent.
Item {
    id: root
    // Without an explicit height an Item stays at height:0 by default: the
    // parent Column (in Settings.qml) allocated zero vertical space to it,
    // which is why the panel was invisible even though it was loaded.
    implicitHeight: _wifiCol.implicitHeight
    height: implicitHeight
    property color txt
    property color txtSub
    property color txtHint
    property color ctrlBg
    property color ctrlBrd
    property color blue
    property color divider
    property color popupBg
    property bool lightTheme

    readonly property string backendUrl: "http://127.0.0.1:9097"

    property bool radioOn: false
    property string connectedSsid: ""
    property int connectedSignal: 0
    property var networks: []
    property bool scanning: false
    property bool adapterAvailable: true

    property string pendingSsid: ""   // network waiting for a password
    property string statusMsg: ""

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
        xhrCall("GET", "/wifi/status", null, function(status, d) {
            if (!d) return
            root.radioOn = !!d.radioOn
            root.connectedSsid = d.connected || ""
            root.connectedSignal = d.signal || 0
            root.adapterAvailable = d.available !== false
        })
    }

    function scan() {
        root.scanning = true
        xhrCall("GET", "/wifi/scan", null, function(status, d) {
            root.scanning = false
            if (d && d.networks) root.networks = d.networks
        })
    }

    function toggleRadio(on) {
        xhrCall("POST", "/wifi/toggle", {on: on}, function() {
            refreshStatus()
            if (on) scan()
        })
    }

    function connectTo(ssid, password) {
        root.statusMsg = qsTr("Connecting to ") + ssid + "…"
        xhrCall("POST", "/wifi/connect", {ssid: ssid, password: password || ""}, function(status, d) {
            if (d && d.ok) {
                root.statusMsg = ""
                refreshStatus(); scan()
            } else {
                root.statusMsg = qsTr("Can't connect: ") + (d ? d.message : qsTr("error"))
            }
        })
    }

    function forget(ssid) {
        xhrCall("POST", "/wifi/forget", {ssid: ssid}, function() { refreshStatus(); scan() })
    }

    // (implicitHeight/height declared right after id, above)

    Component.onCompleted: { refreshStatus(); scan() }
    Timer { interval: 8000; running: root.radioOn; repeat: true; onTriggered: root.refreshStatus() }

    Column {
        id: _wifiCol
        width: parent.width; spacing: 18

        Row {
            width: parent.width
            Text { text: qsTr("Wi-Fi"); color: root.txt; font.pixelSize: 15; width: parent.width - 60 }
            TWifiToggle {
                checked: root.radioOn
                onToggled: on => root.toggleRadio(on)
            }
        }

        TWifiDivider { visible: root.radioOn }

        Text {
            visible: !root.adapterAvailable && root.radioOn
            text: qsTr("No Wi-Fi adapter found on the system.")
            color: root.txtHint; font.pixelSize: 13; width: parent.width; wrapMode: Text.WordWrap
        }

        Text {
            visible: root.statusMsg.length > 0
            text: root.statusMsg; color: root.txtHint; font.pixelSize: 13
        }

        // Rete attualmente connessa
        Rectangle {
            visible: root.radioOn && root.connectedSsid.length > 0
            width: parent.width; height: 64; radius: 10
            color: root.ctrlBg; border.width: 1; border.color: root.ctrlBrd
            Row {
                anchors.fill: parent; anchors.margins: 14; spacing: 12
                Text { text: "📶"; font.pixelSize: 20; anchors.verticalCenter: parent.verticalCenter }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 2
                    Text { text: root.connectedSsid; color: root.txt; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text { text: qsTr("Connected · signal ") + root.connectedSignal + "%"; color: root.txtSub; font.pixelSize: 12 }
                }
            }
            Text {
                text: qsTr("Disconnect"); color: root.blue; font.pixelSize: 13
                anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.xhrCall("POST","/wifi/disconnect",{}, function(){ root.refreshStatus(); root.scan() }) }
            }
        }

        Row {
            visible: root.radioOn
            width: parent.width
            Text { text: qsTr("Available networks"); color: root.txtHint; font.pixelSize: 12; font.weight: Font.DemiBold; width: parent.width - 80 }
            Text {
                text: root.scanning ? "…" : qsTr("Refresh")
                color: root.blue; font.pixelSize: 12
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: root.scan() }
            }
        }

        Column {
            visible: root.radioOn
            width: parent.width; spacing: 2

            Repeater {
                model: root.networks.filter(function(n) { return !n.connected })
                Rectangle {
                    width: parent.width; height: 54; radius: 8
                    color: _wifiRowMA.pressed ? root.ctrlBg : "transparent"
                    Row {
                        anchors.fill: parent; anchors.margins: 12; spacing: 12
                        Text {
                            text: modelData.signal > 66 ? "▂▄▆" : (modelData.signal > 33 ? "▂▄" : "▂")
                            color: root.txtSub; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: modelData.ssid; color: root.txt; font.pixelSize: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            visible: modelData.secured
                            text: "🔒"; font.pixelSize: 11; color: root.txtHint
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        id: _wifiRowMA
                        anchors.fill: parent
                        onClicked: {
                            if (modelData.secured) {
                                root.pendingSsid = modelData.ssid
                                wifiPasswordPopup.open()
                            } else {
                                root.connectTo(modelData.ssid, "")
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.radioOn && root.networks.length === 0 && !root.scanning
                text: qsTr("No networks found nearby.")
                color: root.txtHint; font.pixelSize: 13; topPadding: 8
            }
        }
    }

    // ── Popup password ──
    Item {
        id: wifiPasswordPopup
        anchors.fill: parent
        visible: false
        z: 500
        function open() { visible = true; _pwField.text = ""; _pwField.forceActiveFocus() }
        function close() { visible = false }

        Rectangle { anchors.fill: parent; color: "#99000000"; MouseArea { anchors.fill: parent; onClicked: wifiPasswordPopup.close() } }

        Rectangle {
            anchors.centerIn: parent
            width: 380; height: 190; radius: 8
            color: root.popupBg

            Column {
                anchors.fill: parent; anchors.margins: 24; spacing: 16

                Text { text: qsTr("Password for ") + root.pendingSsid; color: root.txt; font.pixelSize: 16; font.weight: Font.DemiBold; width: parent.width; wrapMode: Text.WordWrap }

                Rectangle {
                    width: parent.width; height: 44; radius: 8
                    color: root.ctrlBg; border.width: 1; border.color: root.ctrlBrd
                    TextInput {
                        id: _pwField
                        anchors.fill: parent; anchors.margins: 12
                        color: root.txt; font.pixelSize: 14
                        echoMode: TextInput.Password
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter
                        EnterKeyAction.actionId: EnterKeyAction.Done
                        EnterKeyAction.label: qsTr("Connect")
                        Keys.onReturnPressed: connectBtn.clicked()
                    }
                }

                Row {
                    anchors.right: parent.right; spacing: 10
                    TWifiSecondary { label: qsTr("Cancel"); onClicked: wifiPasswordPopup.close() }
                    TWifiPrimary {
                        id: connectBtn
                        label: qsTr("Connect")
                        onClicked: {
                            root.connectTo(root.pendingSsid, _pwField.text)
                            wifiPasswordPopup.close()
                        }
                    }
                }
            }
        }
    }

    // Small local aliases of the components defined in Settings.qml are not
    // reachable from here (they are private "component"s of the parent file), so
    // we define equivalent, lightweight ones here.
    component TWifiToggle: Rectangle {
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
    component TWifiPrimary: Rectangle {
        property string label
        signal clicked()
        id: pbtn
        width: Math.max(110, pTxt.implicitWidth + 40); height: 40; radius: 8
        color: _pbMA.pressed ? Qt.darker(root.blue, 1.2) : root.blue
        Text { id: pTxt; anchors.centerIn: parent; text: pbtn.label; color: "#FFFFFF"; font.pixelSize: 13; font.weight: Font.DemiBold }
        MouseArea { id: _pbMA; anchors.fill: parent; onClicked: pbtn.clicked() }
    }
    component TWifiSecondary: Rectangle {
        property string label
        signal clicked()
        id: sbtn
        width: Math.max(110, sTxt.implicitWidth + 40); height: 40; radius: 8
        color: _sbMA.pressed ? (root.lightTheme ? "#C8C8C8" : "#5A5A5A") : (root.lightTheme ? "#D5D5D5" : "#6B6B6B")
        Text { id: sTxt; anchors.centerIn: parent; text: sbtn.label; color: root.txt; font.pixelSize: 13; font.weight: Font.DemiBold }
        MouseArea { id: _sbMA; anchors.fill: parent; onClicked: sbtn.clicked() }
    }
    component TWifiDivider: Rectangle { width: parent.width; height: 1; color: root.divider }
}
