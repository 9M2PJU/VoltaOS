#pragma once

// Wrapper nostro attorno a QWaylandPresentationTime (protocollo
// "wp_presentation"), exposed to QML with the same mechanism already used
// for Viewporter (see VoltaViewporter.h) — needed because Qt exposes it to
// QML through a "foreign" module (import QtWayland.Compositor.
// PresentationTime) that does NOT inherit the "quick extension" logic used
// by XdgShell/XdgDecorationManagerV1, and its initialize() has a bug in
// ordine confermato leggendo i sorgenti Qt (qtwayland/src/compositor/
// extensions/qwaylandpresentationtime.cpp):
//
//     void QWaylandPresentationTime::initialize()
//     {
//         ...
//         QWaylandCompositor *compositor = this->compositor(); // = extensionContainer()
//         if (compositor == nullptr) {
//             qWarning() << "Failed to find QWaylandCompositor when initializing QWaylandPresentationTime";
//             return;                                   // <-- esce QUI
//         }
//         QWaylandCompositorExtensionTemplate::initialize(); // <-- "adopts" the parent ONLY here, too late
//         d->init(compositor->display(), 1);
//     }
//
// The "compositor == nullptr" check is done BEFORE the base class's
// initialize() has the chance to automatically adopt the QML
// parent as extensionContainer — that is why, declared as a
// simple QML child of WaylandCompositor (round 56), it always failed with
// that exact error, even though the parent was correct. It cannot be solved
// from pure QML: extensionContainer must be set by hand BEFORE
// calling initialize(), through public methods of
// QWaylandCompositorExtension (setExtensionContainer/initialize, entrambi
// public — verified on doc.qt.io).
//
// NOT CONFIRMED: it only solves the error of attaching the extension to
// OUR compositor. It does not guarantee that gamescope/Wine then use it
// successfully to attach to "wayland-volta" instead of falling back to an
// external window — it is the next concrete experiment, not a
// verified solution.

// Unlike QWaylandViewporter, this class has no installed CamelCase
// "convenience" header in this Qt version (6.11.1) —
// build failed with "QWaylandPresentationTime: No such file or
// directory" using <QWaylandPresentationTime>. The full path of the
// lowercase module/header is needed.
#include <QtWaylandCompositor/qwaylandpresentationtime.h>
#include <QWaylandCompositor>
#include <QtQml/qqml.h>

class VoltaPresentationTime : public QWaylandPresentationTime
{
    Q_OBJECT
    QML_NAMED_ELEMENT(PresentationTime)

public:
    using QWaylandPresentationTime::QWaylandPresentationTime;

    // Same logic as VoltaViewporter::attachAndInitialize(): sets the
    // container explicitly BEFORE initializing, to avoid the
    // premature check inside QWaylandPresentationTime::initialize().
    Q_INVOKABLE void attachAndInitialize(QWaylandCompositor *compositor)
    {
        if (!extensionContainer())
            setExtensionContainer(compositor);
        if (!isInitialized())
            initialize();
    }
};
