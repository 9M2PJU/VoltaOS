import QtQuick

// Hand-drawn flag (no image file): code = it | en | es | fr | pt
Item {
    id: flag
    property string code: "it"
    width: 36; height: 24

    Item {
        id: clipBox
        anchors.fill: parent
        // rounded corners without shaders: the flag sits inside a rectangle with a border
        Row {
            visible: flag.code === "it" || flag.code === "fr"
            anchors.fill: parent
            Rectangle { width: parent.width / 3; height: parent.height; color: flag.code === "it" ? "#009246" : "#0055A4" }
            Rectangle { width: parent.width / 3; height: parent.height; color: "#FFFFFF" }
            Rectangle { width: parent.width / 3; height: parent.height; color: flag.code === "it" ? "#CE2B37" : "#EF4135" }
        }
        Column {
            visible: flag.code === "es"
            anchors.fill: parent
            Rectangle { width: parent.width; height: parent.height * 0.25; color: "#AA151B" }
            Rectangle { width: parent.width; height: parent.height * 0.5;  color: "#F1BF00" }
            Rectangle { width: parent.width; height: parent.height * 0.25; color: "#AA151B" }
        }
        Row {
            visible: flag.code === "pt"
            anchors.fill: parent
            Rectangle { width: parent.width * 0.4; height: parent.height; color: "#006600" }
            Rectangle { width: parent.width * 0.6; height: parent.height; color: "#FF0000" }
        }
        Rectangle {
            visible: flag.code === "pt"
            width: parent.height * 0.42; height: width; radius: width / 2
            x: parent.width * 0.4 - width / 2; y: (parent.height - height) / 2
            color: "#FFE000"; border.width: 1; border.color: "#FFFFFF"
        }
        Canvas {   // Regno Unito
            id: uk
            visible: flag.code === "en"
            anchors.fill: parent
            onPaint: {
                var c = getContext("2d"), w = width, h = height
                c.fillStyle = "#012169"; c.fillRect(0, 0, w, h)
                c.strokeStyle = "#FFFFFF"; c.lineWidth = h * 0.22
                c.beginPath(); c.moveTo(0, 0); c.lineTo(w, h); c.moveTo(w, 0); c.lineTo(0, h); c.stroke()
                c.strokeStyle = "#C8102E"; c.lineWidth = h * 0.08
                c.beginPath(); c.moveTo(0, 0); c.lineTo(w, h); c.moveTo(w, 0); c.lineTo(0, h); c.stroke()
                c.fillStyle = "#FFFFFF"; c.fillRect(w / 2 - h * 0.17, 0, h * 0.34, h); c.fillRect(0, h * 0.5 - h * 0.17, w, h * 0.34)
                c.fillStyle = "#C8102E"; c.fillRect(w / 2 - h * 0.1, 0, h * 0.2, h); c.fillRect(0, h * 0.5 - h * 0.1, w, h * 0.2)
            }
        }
    }
    Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: "#40808080"; radius: 2 }
}
