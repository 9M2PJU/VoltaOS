import QtQuick
import VoltaApp 1.0

// Pull the content down past the top edge to refresh (as on Android):
// a loading bar appears at the top. Put it next to the Flickable
// (same parent), with target: <id of the Flickable>, and onRefresh: { ...reload... }.
Item {
    id: pr
    property Flickable target: null
    property real threshold: 90          // px of dragging to trigger the refresh
    property int minShowMs: 1400         // the bar stays visible at least this long
    property bool refreshing: false
    property color barColor: Theme.accent
    signal refresh()

    readonly property real pull: target ? Math.max(0, -(target.contentY - target.originY)) : 0
    property bool _armed: false

    x: target ? target.x : 0
    y: target ? target.y : 0
    width: target ? target.width : 0
    height: 4
    z: 1000
    visible: refreshing || pull > 2
    clip: true

    onPullChanged: if (target && target.dragging && !refreshing && pull >= threshold) _armed = true
    Connections {
        target: pr.target
        function onDraggingChanged() {
            if (pr.target && !pr.target.dragging) {
                if (pr._armed && !pr.refreshing) pr.start()
                pr._armed = false
            }
        }
    }
    function start() {
        refreshing = true
        pr.refresh()
        _doneTimer.restart()
    }
    Timer { id: _doneTimer; interval: pr.minShowMs; onTriggered: pr.refreshing = false }

    // traccia
    Rectangle { anchors.fill: parent; color: pr.barColor; opacity: 0.18 }
    // dragging: the bar fills up to the threshold
    Rectangle {
        visible: !pr.refreshing
        height: parent.height; width: parent.width * Math.min(1, pr.pull / pr.threshold)
        color: pr.barColor
    }
    // loading: sliding bar
    Rectangle {
        id: runner
        visible: pr.refreshing
        height: parent.height; width: parent.width * 0.35; radius: height / 2
        color: pr.barColor
        SequentialAnimation on x {
            running: pr.refreshing; loops: Animation.Infinite
            NumberAnimation { from: -runner.width; to: pr.width; duration: 900; easing.type: Easing.InOutQuad }
        }
    }
}
