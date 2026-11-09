// Singleton shared between Settings.qml (where the user configures the
// virtual keyboard) and VoltaInputPanel.qml (which reads these settings
// in real time). Persisted to disk with Qt.labs.settings (same
// mechanism already used by Settings.qml for "prefs"), so the choices
// survive an app restart.
pragma Singleton
import QtQuick
import QtCore as Core

// "Item" and not "QtObject": a "default property" is needed to be able to
// contain the "Core.Settings" child below (QtObject has none —
// qmllint reported "Cannot assign to non-existent default
// property"). It is still a purely logical singleton: it is never
// shown, has no visual parent, draws nothing.
Item {
    id: root

    // ── List of ALL the languages selectable in the Settings ────────
    // The physical keyboard layout always stays QWERTY: changing language
    // only changes the set of accents/variants offered when holding down a
    // letter key (see "accentTable" below), not the key layout.
    readonly property var languages: [
        { code: "it", name: "Italiano" },
        { code: "en", name: "English" },
        { code: "fr", name: "Français" },
        { code: "es", name: "Español" },
        { code: "de", name: "Deutsch" },
        { code: "pt", name: "Português" },
        { code: "nl", name: "Nederlands" },
        { code: "tr", name: "Türkçe" }
    ]

    // Accents/variants per lowercase letter, for each language — used by the
    // long-press on letter keys. Deliberately essential list (the
    // most common variants of each language), not exhaustive.
    readonly property var accentTable: ({
        it: { a: ["à"], e: ["è", "é"], i: ["ì"], o: ["ò"], u: ["ù"] },
        en: {},
        fr: { a: ["à", "â", "ä"], e: ["é", "è", "ê", "ë"], i: ["î", "ï"],
              o: ["ô", "ö"], u: ["ù", "û", "ü"], c: ["ç"] },
        es: { a: ["á"], e: ["é"], i: ["í"], o: ["ó"], u: ["ú", "ü"], n: ["ñ"] },
        de: { a: ["ä"], o: ["ö"], u: ["ü"], s: ["ß"] },
        pt: { a: ["á", "â", "ã", "à"], e: ["é", "ê"], i: ["í"],
              o: ["ó", "ô", "õ"], u: ["ú"], c: ["ç"] },
        nl: { e: ["ë", "é"], i: ["ï"], o: ["ö"] },
        tr: { c: ["ç"], g: ["ğ"], i: ["ı", "î"], o: ["ö"], s: ["ş"], u: ["ü"] }
    })

    // Returns the extra variants (without the base letter) for the
    // currently active language. Empty array if that letter has no variants.
    function variantsFor(letter) {
        var table = root.accentTable[root.activeLanguage]
        if (!table) return []
        return table[letter] || []
    }

    // ── Stato persistito ───────────────────────────────────────────────────
    property alias keyboardEnabled:   prefs.keyboardEnabled
    property alias enabledLanguagesCsv: prefs.enabledLanguages
    property alias activeLanguage:   prefs.activeLanguage

    readonly property var enabledLanguageCodes:
        root.enabledLanguagesCsv.length ? root.enabledLanguagesCsv.split(",") : ["en"]

    function isLanguageEnabled(code) {
        return root.enabledLanguageCodes.indexOf(code) >= 0
    }

    // Enables/disables a language in the "globe" button's menu. If you were about to
    // disable the last remaining language, the operation is ignored:
    // at least one must always remain enabled.
    function setLanguageEnabled(code, on) {
        var list = root.enabledLanguageCodes.slice()
        var idx = list.indexOf(code)
        if (on && idx < 0) list.push(code)
        if (!on && idx >= 0) list.splice(idx, 1)
        if (list.length === 0) list = [code]
        root.enabledLanguagesCsv = list.join(",")
        if (!root.isLanguageEnabled(root.activeLanguage))
            root.activeLanguage = list[0]
    }

    Core.Settings {
        id: prefs
        category: "virtualKeyboard"
        property bool   keyboardEnabled:   true
        property string enabledLanguages:  "it,en"
        property string activeLanguage:    "en"
    }
}
