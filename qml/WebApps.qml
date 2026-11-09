pragma Singleton
import QtQuick
import QtCore as Core

// Web apps: sites added from the Browser ("Add to apps" button) that appear
// at the top of the drawer and open full screen like an app (WebAppView.qml).
// Shared list saved to disk.
QtObject {
    id: wa

    property Core.Settings _prefs: Core.Settings {
        category: "webapps"
        property string json: "[]"
    }

    // [{ id, url, name, icon }]
    readonly property var list: {
        try { var l = JSON.parse(_prefs.json); return Array.isArray(l) ? l : [] } catch (e) { return [] }
    }

    // same site = same address without "https://", "www." and trailing "/"
    function key(u) {
        return String(u || "").trim().replace(/^https?:\/\//i, "").replace(/^www\./i, "").replace(/\/+$/, "").toLowerCase()
    }
    function find(u) {
        var k = key(u)
        for (var i = 0; i < list.length; i++) if (key(list[i].url) === k) return list[i]
        return null
    }
    function byId(id) {
        for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
        return null
    }
    function has(u) { return find(u) !== null }

    // Short name for the icon: from the page title ("YouTube - Home" -> "YouTube"),
    // otherwise from the domain ("www.repubblica.it" -> "Repubblica")
    function shortName(title, u) {
        var t = String(title || "").split(/ [-–—|·:] /)[0].trim()
        if (t.length > 0 && t.length <= 18 && !/^https?:/i.test(t)) return t
        var host = key(u).split("/")[0].split(".")
        var base = host.length >= 2 ? host[host.length - 2] : host[0]
        return base.charAt(0).toUpperCase() + base.slice(1)
    }

    function add(u, title) {
        if (!u || has(u)) return
        var l = list.slice()
        var id = "w" + Date.now().toString(36)
        l.push({ id: id, url: String(u), name: shortName(title, u),
                 icon: "http://127.0.0.1:9098/webapp-icon?url=" + encodeURIComponent(String(u)) })
        _prefs.json = JSON.stringify(l)
    }
    function remove(id) {
        _prefs.json = JSON.stringify(list.filter(function(a) { return a.id !== id }))
    }
    function removeUrl(u) {
        var a = find(u)
        if (a) remove(a.id)
    }
}
