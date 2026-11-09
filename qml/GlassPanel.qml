import QtQuick
import QtQuick.Effects
import VoltaApp 1.0

// "Glass" background like the music widget: blurs what is behind it and puts a dark/light veil on top.
// `sources` = the scene layers to blur, from the lowest to the highest (background, glow, reflection, 3D car...): each one is blurred on its own
// with its own opacity and then they are stacked, so what you see under the panel is what is really there.
// Put it as the first child of a panel (anchors.fill: parent, z: -1). Without sources (or in low-power mode) it stays a solid background.
Item {
    id: gp
    property var sources: []
    property bool lightTheme: false
    property real radius: 18
    readonly property bool glass: sources.length > 0 && !Theme.lowPower

    Item {
        anchors.fill: parent
        visible: gp.glass
        layer.enabled: gp.glass
        layer.effect: MultiEffect { maskEnabled: true; maskSource: gmask }
        Repeater {
            model: gp.sources
            Item {
                anchors.fill: parent
                visible: modelData.visible
                opacity: modelData.opacity
                ShaderEffectSource {
                    id: grab
                    anchors.fill: parent
                    sourceItem: modelData
                    // the area behind the panel, in source coordinates (updated if the panel moves or changes size)
                    sourceRect: { var _d = gp.x + gp.y + gp.width + gp.height; var p = gp.mapToItem(modelData, 0, 0); return Qt.rect(p.x, p.y, gp.width, gp.height) }
                    live: true
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: grab
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 48
                    autoPaddingEnabled: false
                }
            }
        }
    }
    Rectangle { id: gmask; anchors.fill: parent; radius: gp.radius; visible: false; layer.enabled: true; color: "#FFFFFF" }
    Rectangle {
        anchors.fill: parent
        radius: gp.radius
        color: gp.glass ? (gp.lightTheme ? "#A0F2F2F2" : "#A0262626") : (gp.lightTheme ? "#F2F2F2" : "#262626")
        border.width: 1
        border.color: gp.lightTheme ? "#22000000" : "#22FFFFFF"
    }
}
