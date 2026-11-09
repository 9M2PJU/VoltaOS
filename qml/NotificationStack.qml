import QtQuick

// STACK NOTIFICHE stile iOS — versione OVERLAY.
// It does not wrap the MusicWidget: it is placed beside it as a sibling.
// Cards are positioned absolutely above the target thanks to targetItem.
// When there are notifications, the target shrinks slightly
// (scale 0.92) to create the visual stack effect.
Item {
    id: stack

    property Item targetItem: null
    property Item blurSource: null                    // for the cards' glass effect
    property bool lightTheme: false
    // position/size relative to the target (shared with the player)
    property real overlayDx: 0
    property real overlayDy: 0
    property real overlayDw: 0
    property real overlayDh: 0
    readonly property int  count: notifModel.count
    readonly property bool hasNotifications: count > 0
    // call microphone muted (true) / unmuted (false)
    signal micToggled(bool isMuted)
    signal keypadRequested()

    ListModel { id: notifModel }
    property var _actions:   ({})
    property var _secondary: ({})

    // API pubbliche
    function notify(n) {
        var idx = _findById(n.id)
        var entry = {
            entryId:      n.id || ("n_" + Date.now() + "_" + Math.random()),
            iconType:     n.iconType || "info",
            iconColor:    n.iconColor || "#ED4E3B",
            title:        n.title || "",
            subtitle:     n.subtitle || "",
            actionLabel:     n.actionLabel     || "",
            actionColor:     n.actionColor     || "#3D6FE7",
            secondaryLabel:  n.secondaryLabel  || "",
            secondaryColor:  n.secondaryColor  || "#ED4E3B",
            dismissible:  n.dismissible !== undefined ? n.dismissible : true,
            autoDismissMs: n.autoDismissMs || 0,
            layoutType:   n.id === "call" ? "call" : "",
            incoming:     !!n.secondaryLabel
        }
        if (n.onAction)    _actions[entry.entryId] = n.onAction
        if (n.onSecondary) _secondary[entry.entryId] = n.onSecondary
        if (idx >= 0) notifModel.set(idx, entry)
        else          notifModel.insert(0, entry)
    }
    function dismiss(id) {
        var idx = _findById(id)
        if (id === "call") micToggled(false)   // at the end of the call the microphone becomes active again
        if (idx >= 0) notifModel.remove(idx)
        delete _actions[id]
        delete _secondary[id]
    }
    function _findById(id) {
        for (var i = 0; i < notifModel.count; i++)
            if (notifModel.get(i).entryId === id) return i
        return -1
    }

    // (no more shrinking of the music player: it stays visible underneath)

    Repeater {
        id: rep
        model: notifModel
        delegate: NotificationCard {
            targetItem: stack.targetItem
            blurSource: stack.blurSource
            lightTheme: stack.lightTheme
            overlayDx: stack.overlayDx; overlayDy: stack.overlayDy
            overlayDw: stack.overlayDw; overlayDh: stack.overlayDh
            entryId:     model.entryId
            iconType:    model.iconType
            iconColor:   model.iconColor
            title:       model.title
            subtitle:    model.subtitle
            actionLabel:    model.actionLabel
            actionColor:    model.actionColor
            secondaryLabel: model.secondaryLabel
            secondaryColor: model.secondaryColor
            dismissible: model.dismissible
            autoDismissMs: model.autoDismissMs
            layoutType:  model.layoutType
            incomingCall: model.incoming
            onMicToggled: function(m) { stack.micToggled(m) }
            onKeypadRequested: stack.keypadRequested()
            stackDepth:  index
            totalCount:  notifModel.count
            z: 500 - index
            onDismissed: stack.dismiss(entryId)
            onActionTriggered: {
                var cb = stack._actions[entryId]
                if (cb) cb()
            }
            onSecondaryTriggered: {
                var cb = stack._secondary[entryId]
                if (cb) cb()
            }
        }
    }
}
