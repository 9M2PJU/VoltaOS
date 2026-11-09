import QtQuick
import QtQuick.Shapes

// Loading wheel (faded ring from the drawing "loading_circles_set.eps"):
// same graphics as the drawing, rotates clockwise. Usage: Spinner { size: 32 }
Item {
    id: sp
    property real size: 32
    property bool running: true
    width: size; height: size

    Item {
        id: holder
        anchors.fill: parent
        antialiasing: true

        // the original drawing is 404 x 404: I draw it once at that size and scale it down
        Item {
            id: art
            width: 404; height: 404
            scale: sp.width / 404
            transformOrigin: Item.TopLeft
            layer.enabled: true
            layer.smooth: true
            layer.samples: 4

            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeColor: "transparent"
                    fillRule: ShapePath.OddEvenFill
                    fillGradient: ConicalGradient {
                        centerX: 202; centerY: 202
                        angle: 90
                        GradientStop { position: 0.0; color: "#000000" }
                        GradientStop { position: 1.0; color: "#FFFFFF" }
                    }
                    startX: 404; startY: 202
                    PathAngleArc { centerX: 202; centerY: 202; radiusX: 202; radiusY: 202; startAngle: 0; sweepAngle: 360 }
                    PathMove { x: 356; y: 202 }
                    PathAngleArc { centerX: 202; centerY: 202; radiusX: 154; radiusY: 154; startAngle: 0; sweepAngle: 360 }
                }
            }
            // estremita' arrotondata (nera) a ore 12
            Rectangle { x: 178; y: 0; width: 48; height: 48; radius: 24; color: "#000000"; antialiasing: true }
        }

        RotationAnimator on rotation {
            from: 0; to: 360
            duration: 900
            loops: Animation.Infinite
            running: sp.running && sp.visible && sp.width > 0
        }
    }
}
