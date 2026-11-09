import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import QtCore
import QtCore as Core
import VoltaApp 1.0

Rectangle {
    property bool lightTheme: Window.window.lightTheme
    id: phoneView

    color: lightTheme ? "#FFFFFF" : "#171717"
    // Without this, content taller than the available space (like the
    // tastierino, ~570px fissi) sborda visivamente oltre i propri confini
    // instead of stopping there — the margin reserved for the dock in
    // AppPanel.qml became useless, because the content ignored it and
    // kept drawing underneath anyway.
    clip: true

    // ── Call state: comes from the phone over Bluetooth (PhoneManager) ──
    readonly property string callState:   PhoneManager.callState   || "idle"
    readonly property string callContact: PhoneManager.callContact || ""
    readonly property string callNumber:  PhoneManager.callNumber  || ""

    property int    callDuration: 0
    property string activeTab:   "calls"  // calls, contacts, favorites
    readonly property var contacts:    PhoneManager.contacts    || []
    readonly property var recentCalls: PhoneManager.recentCalls || []

    // Favorite contacts: persisted locally (same pattern already used
    // for radio favorites) — PhoneManager/isFavorite was never connected
    // to anything that really sets them, so we keep the list here.
    Core.Settings {   // dl75
        id: contactFavSettings
        property string favNumbersJson: "[]"
    }
    property var favNumbers: {
        try { return JSON.parse(contactFavSettings.favNumbersJson) } catch(e) { return [] }
    }
    function isNumberFavorite(phone) {
        return phoneView.favNumbers.indexOf(phone) !== -1
    }
    function toggleFavoriteContact(phone) {
        var list = phoneView.favNumbers.slice()
        var idx = list.indexOf(phone)
        if (idx === -1) list.push(phone)
        else list.splice(idx, 1)
        phoneView.favNumbers = list
        contactFavSettings.favNumbersJson = JSON.stringify(list)
    }
    readonly property var favorites: phoneView.contacts.filter(function(c) {
        return phoneView.isNumberFavorite(c.phone)
    })
    property string digits:      ""
    property string searchText:  ""

    // The "Message" button on each contact emits this — whoever
    // instantiates PhoneView decides what to do (switch to the Messages app and open
    // the right conversation). Before, the button had no
    // MouseArea.onClicked, it was an empty placeholder.
    signal messageContact(string number, string name)

    function fmt(s) {
        return String(Math.floor(s/60)).padStart(2,'0') + ":" + String(s % 60).padStart(2,'0')
    }

    Timer {
        running: phoneView.callState === "active"
        interval: 1000
        repeat: true
        onTriggered: phoneView.callDuration++
    }

    onCallStateChanged: {
        if (callState === "idle" || callState === "dialing")
            phoneView.callDuration = 0
    }

    function dial(number, name) {
        PhoneManager.dial(number)
    }

    // ── CONTACT CARD COMPONENT (Reusable for Contacts and Favorites) ──
    Component {
        id: contactCardDelegate
        Item {
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: 10
                color: phoneView.color // SAME COLOR AS THE BACKGROUND
                border.color: lightTheme ? "#D1D1D6" : "#222222"
                border.width: 1
                radius: 8

                // Star icon (Favorites) at the top right
                Text {
                    id: favStar
                    z: 2
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 12
                    text: "★"
                    color: phoneView.isNumberFavorite(modelData.phone) ? "#FFFFFF" : (lightTheme ? "#D1D1D6" : "#444444")
                    font.pixelSize: 18

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8   // touch area a bit wider than the glyph alone
                        onClicked: phoneView.toggleFavoriteContact(modelData.phone)
                    }
                }

                // ── Avatar + name, centered in the space ABOVE the row of the
                // buttons. Before, avatar and name had fixed positions (24px
                // from the top + 76px avatar + 16px) that did not take into account
                // the card's real height: on screens where the cards are
                // smaller the name ended up above the Call/Message buttons.
                // Now the avatar resizes to always leave room for the name.
                Item {
                    id: infoArea
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: actionsRow.top
                    anchors.topMargin: 14
                    anchors.bottomMargin: 10

                    readonly property real nameH: 24
                    readonly property real gap: 10
                    readonly property real avatarSize: Math.max(36, Math.min(76, height - nameH - gap))

                    Column {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: infoArea.gap

                        Rectangle {
                            id: avatarRect
                            width: infoArea.avatarSize; height: width
                            radius: width / 2
                            color: lightTheme ? "#F9F9F9" : "#2C2C2E"
                            clip: true
                            anchors.horizontalCenter: parent.horizontalCenter

                            Image {
                                anchors.fill: parent
                                source: modelData.avatar || ""
                                fillMode: Image.PreserveAspectCrop
                                visible: modelData.avatar !== ""
                            }

                            // New user.svg icon
                            Image { sourceSize: Qt.size(width * 2, height * 2);
                                id: fallbackUserIcon
                                anchors.centerIn: parent
                                source: "qrc:/VoltaApp/icons/user.svg"
                                width: parent.width * 0.47; height: width
                                visible: false
                            }
                            ColorOverlay {
                                anchors.fill: fallbackUserIcon
                                source: fallbackUserIcon
                                color: lightTheme ? "#A0A0A0" : "#555555"
                                visible: modelData.avatar === ""
                            }
                        }

                        // Nome Contatto
                        Text {
                            height: infoArea.nameH
                            width: parent.width - 32
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.name || qsTr("Unknown")
                            color: lightTheme ? "#0D0D0D" : "#FFFFFF"
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                // Thin dividing line
                Rectangle {
                    width: parent.width
                    height: 1
                    color: lightTheme ? "#D1D1D6" : "#2A2A2A"
                    anchors.bottom: actionsRow.top
                }

                // Buttons row (Call on the LEFT / Message on the RIGHT)
                Row {
                    id: actionsRow
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 44

                    // Call button (LEFT)
                    Item {
                        width: parent.width / 2; height: parent.height
                        Image { sourceSize: Qt.size(width * 2, height * 2);
                            id: callBtnImg
                            anchors.centerIn: parent
                            source: "qrc:/VoltaApp/icons/phone.svg"
                            width: 24; height: 24
                            fillMode: Image.PreserveAspectFit
                            visible: false
                        }
                        ColorOverlay {
                            anchors.fill: callBtnImg
                            source: callBtnImg
                            color: lightTheme ? "#555555" : "#A0A0A0"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: phoneView.dial(modelData.phone, modelData.name)
                        }
                    }

                    // Divisore verticale
                    Rectangle {
                        width: 1; height: parent.height
                        color: lightTheme ? "#D1D1D6" : "#2A2A2A"
                    }

                    // Message button (right) — before, the icon pointed to a
                    // nonexistent file (msg.svg instead of messages.svg,
                    // probably invisible) and the MouseArea had
                    // no onClicked, an empty placeholder.
                    Item {
                        width: parent.width / 2; height: parent.height
                        Image { sourceSize: Qt.size(width * 2, height * 2);
                            id: msgBtnImg
                            anchors.centerIn: parent
                            source: "qrc:/VoltaApp/icons/messages.svg"
                            width: 24; height: 24
                            fillMode: Image.PreserveAspectFit
                            visible: false
                        }
                        ColorOverlay {
                            anchors.fill: msgBtnImg
                            source: msgBtnImg
                            color: lightTheme ? "#555555" : "#A0A0A0"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: phoneView.messageContact(modelData.phone, modelData.name || "")
                        }
                    }
                }
            }
        }
    }


    // ── MAIN UI (idle) ────────────────────────────────────────────────────────
    Column {
        anchors.fill: parent
        
        // ── NAVBAR ────────────────────────────────────────────────────────────
        Rectangle {
            id: header
            width: parent.width; height: 32 * ((Window.window && Window.window.uPx) ? Window.window.uPx : 1.12); color: "transparent"; z: 2
            property string iconColor: lightTheme ? "#555555" : "#A0A0A0"
            Row {
                anchors.left: parent.left; anchors.leftMargin: 20; anchors.verticalCenter: parent.verticalCenter; spacing: 16

                // The Item guarantees that the layout (Row) computes the space correctly, avoiding overlaps
                Item {
                    width: 26; height: 26
                    anchors.verticalCenter: parent.verticalCenter

                    Image { sourceSize: Qt.size(width * 2, height * 2);
                        id: headerPhoneIcon
                        anchors.fill: parent
                        source: "qrc:/VoltaApp/icons/phone.svg"
                        fillMode: Image.PreserveAspectFit
                        visible: false
                    }
                    // Colored green like the app!
                    ColorOverlay {
                        anchors.fill: headerPhoneIcon
                        source: headerPhoneIcon
                        color: "#00E676"
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: PhoneManager.deviceName || qsTr("Nothing Phone 2A") // Nome Bluetooth forzato
                    color: header.iconColor
                    font.pixelSize: 18
                    font.weight: Font.Medium
                }
            }

            Row {
                anchors.centerIn: parent; spacing: 32
                Repeater {
                    model: [
                        { id: "calls", text: qsTr("Calls") },
                        { id: "contacts", text: qsTr("Contacts") },
                        { id: "favorites", text: qsTr("Favorites") }
                    ]
                    Text {
                        text: modelData.text
                        color: phoneView.activeTab === modelData.id ? (lightTheme ? "#000000" : "#FFFFFF") : (lightTheme ? "#888888" : "#999999")
                        font.pixelSize: 20; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter

                        TapHandler {
                            onTapped: {
                                phoneView.activeTab = modelData.id;
                                if (modelData.id === "contacts" && (!phoneView.contacts || phoneView.contacts.length === 0)) {
                                    PhoneManager.fetchContacts()
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── AREA CONTENUTI ────────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: parent.height - 64
            color: "transparent"

            // ── CALLS TAB ─────────────────────────────────────────────────────
            Row {
                visible: phoneView.activeTab === "calls"
                anchors.fill: parent
                anchors.topMargin: 40; anchors.bottomMargin: 0
                spacing: 0

                Column {
                    width: (parent.width / 2) - 1
                    height: parent.height
                    spacing: 15
                    leftPadding: 40; rightPadding: 40
                    Text {
                        text: qsTr("RECENT CALLS")
                        color: lightTheme ? "#555560" : "#888888"
                        font.pixelSize: 12; font.weight: Font.ExtraBold; font.letterSpacing: 2.5
                    }
                    ListView {
                        width: parent.width - 80
                        height: parent.height - 25
                        clip: true
                        spacing: 10
                        model: phoneView.recentCalls

                        // Modified delegate: text list without a white background with radius
                        delegate: Item {
                            width: parent ? parent.width : 0
                            height: 64
                            Row {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 15
                                Rectangle {
                                    width: 40; height: 40; radius: 20; color: lightTheme ? "#F9F9F9" : "#2C2C2E"
                                    anchors.verticalCenter: parent.verticalCenter

                                    Image { sourceSize: Qt.size(width * 2, height * 2);
                                        id: recentUserIcon
                                        anchors.centerIn: parent
                                        source: "qrc:/VoltaApp/icons/user.svg"
                                        width: 20; height: 20
                                        visible: false
                                    }
                                    ColorOverlay {
                                        anchors.fill: recentUserIcon
                                        source: recentUserIcon
                                        color: lightTheme ? "#A0A0A0" : "#555555"
                                    }
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter; spacing: 2; width: parent.width - 55 - 30
                                    Text { text: modelData.name; color: modelData.missed ? "#e53935" : lightTheme ? "#0D0D0D" : "#FFFFFF"; font.pixelSize: 15; font.weight: Font.Normal }
                                    Text { text: modelData.time; color: lightTheme ? "#888888" : "#A0A0A0"; font.pixelSize: 12 }
                                }
                                // Dark icons for incoming/outgoing/missed
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.missed ? "↙" : (modelData.type === "outgoing" ? "↗" : "↙")
                                    font.pixelSize: 22
                                    font.weight: Font.Normal
                                    color: modelData.missed ? "#e53935" : (lightTheme ? "#555555" : "#A0A0A0")
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: phoneView.dial(modelData.phone, modelData.name) }
                        }
                        Text {
                            visible: phoneView.recentCalls.length === 0
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: PhoneManager.connected ? qsTr("No recent calls\nConnect your phone via Bluetooth") : qsTr("Phone service not active")
                            color: lightTheme ? "#9090A0" : "#A0A0A0"; font.pixelSize: 14; font.weight: Font.Medium
                        }
                    }
                }

                Rectangle {
                    width: 1; height: parent.height
                    color: lightTheme ? "#D1D1D6" : "#333333"
                }

                Column {
                    width: parent.width / 2; height: parent.height; spacing: 25; anchors.top: parent.top
                    Item {
                        width: parent.width; height: 80
                        Text {
                            anchors.centerIn: parent
                            text: phoneView.digits
                            color: lightTheme ? "#000000" : "#FFFFFF"
                            font.pixelSize: 42; font.weight: Font.Light; font.letterSpacing: 4
                            visible: phoneView.digits.length > 0
                        }
                    }
                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 360; columns: 3; columnSpacing: 0; rowSpacing: 30
                        Repeater {
                            model: [
                                { n: "1", s: "" },     { n: "2", s: "ABC" },  { n: "3", s: "DEF" },
                                { n: "4", s: "GHI" },  { n: "5", s: "JKL" },  { n: "6", s: "MNO" },
                                { n: "7", s: "PQRS" }, { n: "8", s: "TUV" },  { n: "9", s: "WXYZ" },
                                { n: "*", s: "" },     { n: "0", s: "+" },    { n: "#", s: "" }
                            ]
                            Item {
                                width: 360 / 3; height: 70
                                Column {
                                    anchors.centerIn: parent; spacing: 2
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.n; color: lightTheme ? "#000000" : "#FFFFFF"
                                        font.pixelSize: 34; font.weight: Font.DemiBold
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.s; color: lightTheme ? "#000000" : "#FFFFFF"
                                        font.pixelSize: 11; font.weight: Font.Normal; font.letterSpacing: 1
                                        visible: text !== ""
                                    }
                                }
                                Rectangle {
                                    id: clickBg
                                    anchors.centerIn: parent; width: 80; height: 80; radius: 40
                                    color: lightTheme ? "#E5E5EA" : "#333333"; opacity: 0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: clickBg.opacity = 0.5
                                    onReleased: { clickBg.opacity = 0; phoneView.digits += modelData.n }
                                    onCanceled: clickBg.opacity = 0
                                }
                            }
                        }
                    }
                    Item {
                        width: 360; height: 70
                        anchors.horizontalCenter: parent.horizontalCenter
                        Row {
                            anchors.fill: parent
                            Item { width: 360 / 3; height: parent.height }
                            Item {
                                width: 360 / 3; height: parent.height
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 140; height: 56; radius: 16
                                    color: "#00E676"

                                    Image { sourceSize: Qt.size(width * 2, height * 2);
                                        id: greenCallIcon
                                        anchors.centerIn: parent
                                        source: "qrc:/VoltaApp/icons/phone.svg"
                                        width: 26; height: 26
                                        fillMode: Image.PreserveAspectFit
                                        visible: false
                                    }

                                    // Icon color based on the view's background
                                    ColorOverlay {
                                        anchors.fill: greenCallIcon
                                        source: greenCallIcon
                                        color: phoneView.color
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: { if(phoneView.digits !== "") phoneView.dial(phoneView.digits) }
                                    }
                                }
                            }
                            Item {
                                width: 360 / 3; height: parent.height
                                Text {
                                    anchors.centerIn: parent; text: "←"
                                    color: lightTheme ? "#888888" : "#A0A0A0"
                                    font.pixelSize: 28; font.weight: Font.Light
                                    visible: phoneView.digits.length > 0
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: phoneView.digits = phoneView.digits.slice(0,-1)
                                }
                            }
                        }
                    }
                }
            }

            // ── CONTACTS TAB ─────────────────────────────────────────────────
            Item {
                id: contactsTab
                visible: phoneView.activeTab === "contacts"
                anchors.fill: parent

                // list filtered and sorted by name
                readonly property var filtered: {
                    var q = phoneView.searchText.toLowerCase()
                    var l = (phoneView.contacts || []).filter(function(c) {
                        return (c.name && c.name.toLowerCase().indexOf(q) !== -1) || (c.phone && c.phone.indexOf(phoneView.searchText) !== -1)
                    })
                    return l.slice().sort(function(a, b) { return String(a.name || "").localeCompare(String(b.name || "")) })
                }
                property string selKey: ""
                function keyOf(c) { return (c.phone || "") + "|" + (c.name || "") }
                readonly property var selected: {
                    var l = filtered
                    for (var i = 0; i < l.length; ++i) if (keyOf(l[i]) === selKey) return l[i]
                    return l.length > 0 ? l[0] : null
                }
                readonly property color txt:   lightTheme ? "#0D0D0D" : "#FFFFFF"
                readonly property color muted: lightTheme ? "#888888" : "#A0A0A0"
                readonly property color line:  lightTheme ? "#D1D1D6" : "#333333"

                // ── left panel: search + list ──
                Item {
                    id: contactsLeft
                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    width: Math.max(300, parent.width * 0.38)

                    Rectangle {
                        id: csBar
                        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                        anchors.topMargin: 24; anchors.leftMargin: 28; anchors.rightMargin: 24
                        height: 44; radius: 8
                        color: lightTheme ? "#E5E5EA" : "#2C2C2E"

                        Image {
                            id: csIco
                            source: "qrc:/VoltaApp/icons/Icons_search_black.svg"
                            width: 20; height: 20; fillMode: Image.PreserveAspectFit
                            anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
                            visible: false
                        }
                        ColorOverlay {
                            anchors.fill: csIco; source: csIco
                            color: contactsTab.muted
                        }
                        TextInput {
                            id: csInput
                            anchors.left: csIco.right; anchors.leftMargin: 10
                            anchors.right: csClear.left; anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            clip: true
                            color: contactsTab.txt
                            font.pixelSize: 17
                            text: phoneView.searchText
                            onTextChanged: if (phoneView.searchText !== text) phoneView.searchText = text
                            Text {
                                visible: parent.text === ""
                                text: qsTr("Search contact")
                                color: contactsTab.muted
                                font.pixelSize: 17
                            }
                        }
                        Item {
                            id: csClear
                            width: 36; height: parent.height
                            anchors.right: parent.right
                            visible: csInput.text !== ""
                            Text {
                                anchors.centerIn: parent; text: "✕"
                                color: contactsTab.muted; font.pixelSize: 16
                            }
                            MouseArea { anchors.fill: parent; onClicked: { csInput.text = ""; phoneView.searchText = "" } }
                        }
                    }

                    ListView {
                        id: contactsList
                        anchors.top: csBar.bottom; anchors.topMargin: 14
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        anchors.leftMargin: 16; anchors.rightMargin: 12
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: contactsTab.filtered

                        delegate: Item {
                            width: ListView.view.width
                            height: 60
                            readonly property bool isSel: contactsTab.selected !== null && contactsTab.keyOf(modelData) === contactsTab.keyOf(contactsTab.selected)
                            Rectangle {
                                anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 2
                                radius: 8
                                color: isSel ? (lightTheme ? "#E3E3E8" : "#262628") : "transparent"
                            }
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: 16
                                anchors.right: parent.right; anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name || modelData.phone || qsTr("Unknown")
                                color: contactsTab.txt
                                font.pixelSize: 15
                                font.weight: Font.Normal
                                elide: Text.ElideRight
                            }
                            MouseArea { anchors.fill: parent; onClicked: contactsTab.selKey = contactsTab.keyOf(modelData) }
                        }
                    }
                }

                Rectangle {
                    id: contactsDivider
                    anchors.left: contactsLeft.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                    anchors.topMargin: 24
                    width: 1; color: contactsTab.line
                }

                // ── right panel: contact detail ──
                Item {
                    id: contactsRight
                    anchors.left: contactsDivider.right; anchors.right: parent.right
                    anchors.top: parent.top; anchors.bottom: parent.bottom
                    visible: contactsTab.selected !== null

                    readonly property var c: contactsTab.selected || ({ name: "", phone: "", avatar: "" })

                    Column {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.top: parent.top; anchors.topMargin: 56
                        anchors.leftMargin: 56; anchors.rightMargin: 56
                        spacing: 22

                        // circle with photo or initial
                        Rectangle {
                            width: 96; height: 96; radius: 48
                            color: lightTheme ? "#DADADF" : "#2C2C2E"
                            clip: true
                            Text {
                                anchors.centerIn: parent
                                visible: !contactsRight.c.avatar
                                text: String(contactsRight.c.name || "?").charAt(0).toUpperCase()
                                color: lightTheme ? "#555560" : "#D0D0D0"
                                font.pixelSize: 44; font.weight: Font.Medium
                            }
                            Image {
                                anchors.fill: parent
                                source: contactsRight.c.avatar || ""
                                fillMode: Image.PreserveAspectCrop
                                visible: !!contactsRight.c.avatar
                            }
                        }

                        Text {
                            width: parent.width
                            text: contactsRight.c.name || qsTr("Unknown")
                            color: contactsTab.txt
                            font.pixelSize: 40; font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Rectangle { width: parent.width; height: 1; color: contactsTab.line }

                        Item {
                            width: parent.width; height: 72

                            Column {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Text { text: qsTr("Mobile"); color: contactsTab.muted; font.pixelSize: 15 }
                                Text {
                                    text: contactsRight.c.phone || ""
                                    color: contactsTab.txt; font.pixelSize: 26
                                }
                            }

                            Row {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                spacing: 14

                                // preferito
                                Rectangle {
                                    width: 48; height: 48; radius: 24
                                    color: lightTheme ? "#E5E5EA" : "#2C2C2E"
                                    Text {
                                        anchors.centerIn: parent; text: "★"
                                        font.pixelSize: 22
                                        color: phoneView.isNumberFavorite(contactsRight.c.phone) ? (lightTheme ? "#000000" : "#FFFFFF") : (lightTheme ? "#B0B0B6" : "#555555")
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: phoneView.toggleFavoriteContact(contactsRight.c.phone) }
                                }

                                // messaggio
                                Rectangle {
                                    width: 48; height: 48; radius: 24
                                    color: lightTheme ? "#E5E5EA" : "#2C2C2E"
                                    Image {
                                        id: csMsgImg
                                        anchors.centerIn: parent
                                        source: "qrc:/VoltaApp/icons/messages.svg"
                                        width: 24; height: 24; fillMode: Image.PreserveAspectFit
                                        visible: false
                                    }
                                    ColorOverlay {
                                        anchors.fill: csMsgImg; source: csMsgImg
                                        color: lightTheme ? "#555555" : "#D0D0D0"
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: phoneView.messageContact(contactsRight.c.phone, contactsRight.c.name || "") }
                                }

                                // chiama
                                Rectangle {
                                    width: 52; height: 52; radius: 26
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "#00E676"
                                    Image {
                                        id: csCallImg
                                        anchors.centerIn: parent
                                        source: "qrc:/VoltaApp/icons/phone.svg"
                                        width: 26; height: 26; fillMode: Image.PreserveAspectFit
                                        visible: false
                                    }
                                    ColorOverlay {
                                        anchors.fill: csCallImg; source: csCallImg
                                        color: phoneView.color
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: phoneView.dial(contactsRight.c.phone, contactsRight.c.name) }
                                }
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: contactsTab.line }
                    }
                }

                // ── stati vuoti ──
                Text {
                    visible: phoneView.contacts.length === 0 && phoneView.searchText === ""
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: PhoneManager.connected ? qsTr("No contacts\nEnable contact sharing on your phone") : qsTr("Phone service not active")
                    color: lightTheme ? "#9090A0" : "#555555"
                    font.pixelSize: 14; font.weight: Font.Medium
                }
                Text {
                    visible: phoneView.contacts.length > 0 && contactsTab.filtered.length === 0
                    anchors.horizontalCenter: contactsLeft.horizontalCenter
                    anchors.top: parent.top; anchors.topMargin: 120
                    text: qsTr("No results found")
                    color: lightTheme ? "#9090A0" : "#555555"
                    font.pixelSize: 14; font.weight: Font.Medium
                }
            }

            // ── FAVORITES TAB ─────────────────────────────────────────────────
            Column {
                visible: phoneView.activeTab === "favorites"
                anchors.fill: parent
                anchors.margins: 40
                spacing: 20

                GridView {
                    width: parent.width
                    height: parent.height
                    clip: true

                    cellWidth: width / 4
                    // Slightly taller than wide: avatar, name and buttons
                    // each have their own space without overlapping
                    cellHeight: Math.max(cellWidth * 1.08, 210)

                    model: phoneView.favorites

                    delegate: contactCardDelegate

                    Text {
                        visible: phoneView.favorites.length === 0
                        anchors.centerIn: parent
                        text: qsTr("No favorite contacts saved")
                        color: lightTheme ? "#9090A0" : "#555555"
                        font.pixelSize: 14; font.weight: Font.Medium
                    }
                }
            }
        }
    }
}