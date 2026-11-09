import QtQuick
import QtQuick.Window

// CALENDAR — EV-style agenda: at the top the icon + "Calendar", below
// the days with events (starting from today) and for each day the rows
// "time | title" separated by a thin line.
//
// Events are passed with setEvents([...]) or by assigning `events`:
//   { title: "On call", start: <ms or Date>, end: <ms or Date>, allDay: true|false }
// For "all day" events start/end are the first and the last day
// (end inclusive or exclusive: see endExclusive).
Rectangle {
    id: cal
    color: lightTheme ? "#FFFFFF" : "#171717"
    property bool lightTheme: false

    readonly property color txt:    lightTheme ? "#2B2B2B" : "#F2F2F2"
    readonly property color txtSub: lightTheme ? "#8E8E93" : "#8A8B8D"
    readonly property color txtHdr: lightTheme ? "#5A5A5A" : "#A2A3A5"
    readonly property color sepCol: lightTheme ? "#E3E3E3" : "#2E2E2E"

    // ── Data ──────────────────────────────────────────────
    property var  events: []
    // If true, the end of an "all day" event is the day AFTER the last one
    // (as iCal/Google do). If false, end is the last day inclusive.
    property bool endExclusive: true
    property int  horizonDays: 60
    property date today: new Date()

    function setEvents(list) { cal.events = list || [] }

    readonly property var monthNames: [qsTr("January"),qsTr("February"),qsTr("March"),qsTr("April"),qsTr("May"),qsTr("June"),
                                       qsTr("July"),qsTr("August"),qsTr("September"),qsTr("October"),qsTr("November"),qsTr("December")]
    readonly property var weekNames: [qsTr("Sunday"),qsTr("Monday"),qsTr("Tuesday"),qsTr("Wednesday"),qsTr("Thursday"),qsTr("Friday"),qsTr("Saturday")]

    function _d(v) { return (v instanceof Date) ? v : new Date(v) }
    function _p2(n) { return (n < 10 ? "0" : "") + n }
    function _hm(d) { return _p2(d.getHours()) + ":" + _p2(d.getMinutes()) }
    function _day0(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }

    // Flat list for the ListView: day headers + event rows.
    function buildRows(evs, from, days) {
        var out = []
        var start0 = _day0(from)
        for (var k = 0; k < days; k++) {
            var day0 = new Date(start0.getFullYear(), start0.getMonth(), start0.getDate() + k)
            var day1 = new Date(day0.getFullYear(), day0.getMonth(), day0.getDate() + 1)
            var items = []
            for (var i = 0; i < evs.length; i++) {
                var e = evs[i]
                if (!e) continue
                var s = _d(e.start), en = _d(e.end !== undefined ? e.end : e.start)
                var overlap
                if (e.allDay) {
                    var last = _day0(en)
                    if (cal.endExclusive && last > _day0(s)) last = new Date(last.getFullYear(), last.getMonth(), last.getDate() - 1)
                    overlap = _day0(s) <= day0 && last >= day0
                } else {
                    overlap = (s < day1 && en > day0) || (s >= day0 && s < day1)
                }
                if (!overlap) continue
                var label
                if (e.allDay) label = qsTr("All day")
                else {
                    var a = s < day0 ? "00:00" : _hm(s)
                    var b = en >= day1 ? "24:00" : _hm(en)
                    label = a + " - " + b
                }
                items.push({ allDay: !!e.allDay, sort: e.allDay ? -1 : Math.max(s.getTime(), day0.getTime()),
                             time: label, title: e.title || "" })
            }
            if (items.length === 0) continue
            items.sort(function(x, y) { return x.sort - y.sort })
            out.push({ head: true, first: out.length === 0,
                       text: weekNames[day0.getDay()] + ", " + day0.getDate() + " " + monthNames[day0.getMonth()] })
            for (var j = 0; j < items.length; j++)
                out.push({ head: false, time: items[j].time, title: items[j].title })
        }
        return out
    }

    property var rows: buildRows(cal.events, cal.today, cal.horizonDays)

    Timer { interval: 60000; running: true; repeat: true
            onTriggered: { var n = new Date(); if (n.getDate() !== cal.today.getDate()) cal.today = n } }

    // ── Icon with the current day (same look as the app drawer) ────
    function _iconSvg(n) {
        return '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 128 128">' + '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7C83FF"/><stop offset="1" stop-color="#4B4FD1"/></linearGradient></defs>' + '<rect x="4" y="4" width="120" height="120" rx="32" fill="url(#g)"/>' + '<rect x="30" y="22" width="10" height="18" rx="5" fill="#fff"/><rect x="88" y="22" width="10" height="18" rx="5" fill="#fff"/>' + '<rect x="22" y="34" width="84" height="8" rx="4" fill="#fff" opacity=".35"/>' + '<text x="64" y="98" font-family="Arial, Helvetica, sans-serif" font-size="58" font-weight="700" fill="#fff" text-anchor="middle">' + n + '</text></svg>'
    }

    readonly property real padX:   Math.round(width * 0.06)
    readonly property real titleX: Math.max(Math.round(width * 0.26), padX + 150)
    readonly property real padR:   Math.round(width * 0.04)

    // ── Header: icon + name ───────────────────────────────────────
    Row {
        id: hdr
        x: 20; y: 0; spacing: 16   // dl59: same measures as the Phone and Messages header
        height: 32 * ((Window.window && Window.window.uPx) ? Window.window.uPx : 1.12)
        Image {
            width: 26; height: 26; anchors.verticalCenter: parent.verticalCenter
            fillMode: Image.PreserveAspectFit; smooth: true
            source: "data:image/svg+xml;utf8," + encodeURIComponent(cal._iconSvg(cal.today.getDate()))
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Calendar"); color: cal.txtHdr
            font.pixelSize: 20; font.weight: Font.DemiBold
        }
    }

    // ── Agenda ───────────────────────────────────────────────────────────
    ListView {
        id: agenda
        anchors { left: parent.left; right: parent.right; top: hdr.bottom; topMargin: 30; bottom: parent.bottom }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: cal.rows

        delegate: Item {
            width: agenda.width
            height: modelData.head ? (modelData.first ? 64 : 80) : 58

            // Day header
            Text {
                visible: modelData.head
                x: cal.padX
                y: modelData.first ? 18 : 34
                text: modelData.text || ""
                color: cal.txt; font.pixelSize: 24; font.weight: Font.DemiBold
            }

            // Event row
            Text {
                visible: !modelData.head
                x: cal.padX; width: cal.titleX - cal.padX - 12
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.time || ""
                color: cal.txtSub; font.pixelSize: 14
                elide: Text.ElideRight
            }
            Text {
                visible: !modelData.head
                x: cal.titleX; width: parent.width - cal.titleX - cal.padR
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.title || ""
                color: cal.txt; font.pixelSize: 17
                elide: Text.ElideRight
            }
            Rectangle {
                visible: !modelData.head
                x: cal.titleX; width: parent.width - cal.titleX - cal.padR
                y: parent.height - 1; height: 1
                color: cal.sepCol
            }
        }

        // No events
        Text {
            visible: cal.rows.length === 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: 60
            text: qsTr("No events scheduled")
            color: cal.txtSub; font.pixelSize: 17
        }
    }
}
