pragma Singleton
import QtQuick

// Final palette + semantic tokens. In dark theme the surfaces use
// semi-transparent white overlays over the background (#171717) so as to get
// the "levels" (background < card < elevated < border) while having few grays.
QtObject {
    id: theme
    property bool light: false
    property bool lowPower: false      // low-performance mode: no blur or blurred shadows in the UI

    // PALETTE GREZZA
    readonly property color white:    "#FFFFFF"
    readonly property color grey50:   "#F0F0F0"
    readonly property color grey100:  "#E0E0E0"
    readonly property color grey200:  "#D0D1D2"
    readonly property color grey400:  "#A2A3A5"
    readonly property color grey600:  "#757575"
    readonly property color grey800:  "#414141"
    readonly property color grey900:  "#171717"
    readonly property color blueSoft: "#A8C3F4"
    readonly property color blue:     "#2E78FF"
    readonly property color blueDeep: "#005AFF"
    readonly property color green:    "#25CB55"
    readonly property color yellow:   "#FFC107"
    readonly property color red:      "#ED4E3B"
    readonly property color redDeep:  "#B74134"

    // BACKGROUNDS / SURFACES (with levels)
    property color bg:              light ? "#FFFFFF" : "#171717"
    property color surface:         light ? "#F0F0F0" : "#14FFFFFF"
    property color surfaceElevated: light ? "#E0E0E0" : "#24FFFFFF"
    property color surfaceInput:    light ? "#F0F0F0" : "#1AFFFFFF"
    // alias vecchi nomi
    property color bgCard:  surface
    property color bgCard2: surfaceElevated
    property color bgInput: surfaceInput

    // TEXT
    property color textPrimary:   light ? "#171717" : "#FFFFFF"
    property color textSecondary: light ? "#757575" : "#A2A3A5"
    property color textHint:      light ? "#A2A3A5" : "#757575"

    // BORDI / DIVISORI
    property color border:  light ? "#D0D1D2" : "#26FFFFFF"
    property color divider: light ? "#E0E0E0" : "#14FFFFFF"

    // ICONS
    property color icon:      light ? "#414141" : "#E0E0E0"
    property color iconMuted: light ? "#A2A3A5" : "#757575"

    // ACCENTI
    property color accent:     "#2E78FF"
    property color accentDeep: "#005AFF"
    property color accentSoft: "#A8C3F4"
    property color success:    "#25CB55"
    property color warning:    "#FFC107"
    property color danger:     "#ED4E3B"
    property color dangerDeep: "#B74134"
    property color accentRed:  "#ED4E3B"

    // OVERLAY
    property color overlay: light ? "#33171717" : "#99171717"
}
