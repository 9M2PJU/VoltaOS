import QtQuick
import Qt5Compat.GraphicalEffects
import QtQuick.Window
import QtQuick.VirtualKeyboard
import VoltaApp 1.0

// MESSAGES — EV-style proportions with the project's original colors and icon
Rectangle {
    id: msg
    color: lightTheme ? "#FFFFFF" : "#171717"
    property bool lightTheme: false

    // The margin for the dock is already applied by AppPanel (bottomInset)
    property int bottomSafeArea: 0

    // Palette colori originale ripristinata
    readonly property color txt:     lightTheme ? "#171717" : "#FFFFFF"
    readonly property color txtSub:  lightTheme ? "#5A5A5A" : "#A2A3A5"
    readonly property color txtHint: lightTheme ? "#9A9A9A" : "#6E6F71"
    readonly property color surf:    lightTheme ? "#F2F2F2" : "#262626"
    readonly property color divider: lightTheme ? "#E4E4E4" : "#2E2E2E"
    readonly property color accent:  "#3D6FE7"

    // ── Data ──────────────────────────────────────────────
    property string selectedNumber: ""
    property string selectedName: ""
    readonly property var conversations: PhoneManager.conversations || []

    function normNumber(n) {
        var d = String(n || "").replace(/[^0-9]/g, "")
        return d.length > 9 ? d.slice(-9) : d
    }
    function sameNumber(a, b) {
        var na = normNumber(a), nb = normNumber(b)
        return na !== "" && na === nb
    }

    function openChat(number, name) {
        msg.selectedName = name || ""
        msg.selectedNumber = number || ""
    }

    readonly property var currentConvo: {
        if (selectedNumber === "") return null
        for (var i = 0; i < conversations.length; i++)
            if (sameNumber(conversations[i].number, selectedNumber)) return conversations[i]
        return { number: selectedNumber, name: selectedName !== "" ? selectedName : selectedNumber, messages: [] }
    }

    onConversationsChanged: {
        if (selectedNumber === "" && conversations.length > 0) {
            selectedNumber = conversations[0].number
            selectedName = conversations[0].name || ""
        }
    }
    Component.onCompleted: {
        if (selectedNumber === "" && conversations.length > 0) {
            selectedNumber = conversations[0].number
            selectedName = conversations[0].name || ""
        }
    }

    function sendMessage(text) {
        if (!text || text.trim() === "" || !currentConvo) return
        PhoneManager.sendMessage(currentConvo.number, text.trim())
    }

    // ══════════════ TOP HEADER (WITHOUT HORIZONTAL DIVIDER) ══════════════
    Item {
        id: topBar
        x: 0; y: 0
        width: parent.width
        height: 56

        // dl58: shared header (logo + text): same measures as Phone
        Row {
            id: appHdr58
            x: 20; y: 0; spacing: 16
            height: 32 * ((Window.window && Window.window.uPx) ? Window.window.uPx : 1.12)
            z: 5
            Item {
                width: 26; height: 26
                anchors.verticalCenter: parent.verticalCenter
                Image {
                    id: appHdrIco58
                    anchors.fill: parent
                    sourceSize: Qt.size(52, 52)
                    source: "qrc:/VoltaApp/icons/messages.svg"
                    fillMode: Image.PreserveAspectFit
                    smooth: true   // dl59: original colors of the icon
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Messages")
                color: msg.lightTheme ? "#555555" : "#A0A0A0"
                font.pixelSize: 20
                font.weight: Font.DemiBold
            }
        }
    }

    // ══════════════ LEFT COLUMN (42%): CONVERSATION LIST ══════════════
    Item {
        id: leftPane
        x: 0
        y: topBar.height
        width: Math.round(parent.width * 0.42)
        height: parent.height - topBar.height - msg.bottomSafeArea

        ListView {
            id: convoList
            anchors.fill: parent
            anchors.topMargin: 10
            anchors.bottomMargin: 14
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: msg.conversations

            delegate: Rectangle {
                width: convoList.width
                height: 82
                radius: 8
                readonly property bool isSel: msg.sameNumber(modelData.number, msg.selectedNumber)

                color: isSel
                       ? (msg.lightTheme ? "#E4E4E4" : "#333333")
                       : (_convoMA.pressed ? (msg.lightTheme ? "#F0F0F0" : "#2A2A2A") : "transparent")
                Behavior on color { ColorAnimation { duration: 100 } }

                Column {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.topMargin: 13
                    anchors.bottomMargin: 12
                    spacing: 5

                    // Top row: Name/Number in bold on the left + Time on the right
                    Item {
                        width: parent.width
                        height: 20

                        Text {
                            text: modelData.name || modelData.number || qsTr("Unknown")
                            color: msg.txt
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            anchors.left: parent.left
                            anchors.right: _timeT.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            id: _timeT
                            text: {
                                var m = modelData.messages
                                return (m && m.length > 0 && m[m.length - 1].time) ? m[m.length - 1].time : ""
                            }
                            color: msg.txtHint
                            font.pixelSize: 12
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Message preview (up to 2 lines)
                    Text {
                        width: parent.width
                        text: {
                            var m = modelData.messages
                            return (m && m.length > 0) ? m[m.length - 1].text : ""
                        }
                        color: msg.txtSub
                        font.pixelSize: 13
                        lineHeight: 1.15
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: _convoMA
                    anchors.fill: parent
                    onClicked: msg.openChat(modelData.number, modelData.name)
                }
            }
        }
    }

    // ══════════════ LINEA DI DIVISIONE VERTICALE ══════════════
    Rectangle {
        id: vDivider
        x: leftPane.width
        y: topBar.height
        width: 1
        height: parent.height - topBar.height - msg.bottomSafeArea - 18
        color: msg.divider
    }

    // ══════════════ COLONNA DESTRA (58%): AREA CHAT ══════════════
    Item {
        id: rightPane
        x: leftPane.width + 1
        y: topBar.height
        width: parent.width - leftPane.width - 1
        height: parent.height - topBar.height - msg.bottomSafeArea

        // Empty state if no conversations are selected
        Column {
            visible: !msg.currentConvo
            anchors.centerIn: parent
            spacing: 10
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "💬"
                font.pixelSize: 48
                color: msg.txtHint
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Select a conversation")
                color: msg.txtHint
                font.pixelSize: 15
            }
        }

        // Message bubbles list
        ListView {
            id: chatList
            visible: msg.currentConvo !== null
            x: 0
            width: parent.width
            anchors.top: parent.top
            anchors.topMargin: 14
            anchors.bottom: replyBar.top
            anchors.bottomMargin: 16
            clip: true
            spacing: 12
            boundsBehavior: Flickable.StopAtBounds
            model: msg.currentConvo ? msg.currentConvo.messages : []

            onCountChanged: Qt.callLater(function() { chatList.positionViewAtEnd() })

            delegate: Item {
                width: chatList.width
                height: _bubble.height
                property bool isMe: modelData.from === "me"

                Rectangle {
                    id: _bubble
                    x: isMe ? (parent.width - width - 26) : 26
                    width: Math.min(parent.width * 0.58, Math.max(48, _msgText.implicitWidth + 28))
                    height: _msgText.implicitHeight + 20
                    radius: 8
                    color: isMe ? msg.accent : msg.surf

                    Text {
                        id: _msgText
                        x: 14
                        y: 10
                        width: parent.width - 28
                        text: modelData.text || ""
                        color: isMe ? "#FFFFFF" : msg.txt
                        font.pixelSize: 14
                        lineHeight: 1.2
                        wrapMode: Text.Wrap
                    }
                }
            }

            footer: Item { width: 1; height: 8 }
        }

        // ══════════════ "REPLY" BAR AT THE BOTTOM (EV PROPORTIONS) ══════════════
        Rectangle {
            id: replyBar
            visible: msg.currentConvo !== null
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20
            x: 26
            width: parent.width - 52
            height: 40
            radius: 8
            color: msg.surf

            Row {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 12
                spacing: 10

                // Microphone icon on the left
                Canvas {
                    id: micIcon
                    width: 16; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var c = msg.txtHint
                        ctx.fillStyle = c
                        ctx.strokeStyle = c
                        ctx.lineWidth = 1.6
                        ctx.lineCap = "round"

                        ctx.beginPath()
                        ctx.roundedRect(5, 1.5, 6, 9.5, 3, 3)
                        ctx.fill()

                        ctx.beginPath()
                        ctx.arc(8, 8, 5.5, 0, Math.PI, false)
                        ctx.stroke()

                        ctx.beginPath()
                        ctx.moveTo(8, 13.5)
                        ctx.lineTo(8, 16.5)
                        ctx.stroke()
                    }
                    Connections {
                        target: msg
                        function onLightThemeChanged() { micIcon.requestPaint() }
                    }
                }

                TextInput {
                    id: replyInput
                    width: parent.width - (sendBtn.visible ? 64 : 26)
                    anchors.verticalCenter: parent.verticalCenter
                    color: msg.txt
                    font.pixelSize: 14
                    clip: true
                    EnterKeyAction.actionId: EnterKeyAction.Send
                    EnterKeyAction.label: qsTr("Send")

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("Answer")
                        color: msg.txtHint
                        font.pixelSize: 14
                        visible: replyInput.text === "" && !replyInput.activeFocus
                    }

                    onAccepted: {
                        if (text.trim() !== "") {
                            msg.sendMessage(text)
                            text = ""
                        }
                    }
                }

                Rectangle {
                    id: sendBtn
                    visible: replyInput.text.trim() !== ""
                    width: 28; height: 28; radius: 14
                    anchors.verticalCenter: parent.verticalCenter
                    color: msg.accent

                    Text {
                        anchors.centerIn: parent
                        text: "↑"
                        color: "#FFFFFF"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (replyInput.text.trim() !== "") {
                                msg.sendMessage(replyInput.text)
                                replyInput.text = ""
                            }
                        }
                    }
                }
            }
        }
    }
}