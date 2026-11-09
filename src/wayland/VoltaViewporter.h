#pragma once

// Qt does not expose QWaylandViewporter to QML (no QML_ELEMENT in the library
// class — verified on the QtWaylandCompositor sources): it must be
// wrapped in a class of our own to be able to use it as "Viewporter {}"
// inside VoltaCompositor.qml, exactly as we already do with
// SystemHelper/XWindowHelper/ecc.
//
// Why we need it: it implements the Wayland protocol "wp_viewporter",
// required by Wine's native Wayland driver (winewayland.drv) for the
// handling of window mode/scale changes — one of the two
// gaps identified in our compositor (VoltaCompositor.qml) that
// so far prevented clients like Wine and gamescope from attaching
// correctly to our "wayland-volta" instead of always ending up in a
// separate external window. The other gap (wp_presentation) is
// solved with the same technique, see VoltaPresentationTime.h.
//
// ROUND 56→58: declared as a direct QML child of WaylandCompositor,
// the extension is attached (extensionContainer) automatically
// ONLY if its initialize() uses the base implementation of
// QWaylandCompositorExtension, which "adopts" the QML parent as
// container before initializing itself. We have no confirmation that
// QWaylandViewporter::initialize() always does it reliably
// (for QWaylandPresentationTime it does NOT, see VoltaPresentationTime.h
// for details — bug verified on the Qt sources). To be safe
// we use for both the same explicit and guaranteed way: the method
// attachAndInitialize(), called by VoltaCompositor.qml ONLY after
// comp.created is true, which sets extensionContainer before calling
// initialize() — bypassing any ambiguity about the automatic
// "parent adoption". initialize()/setExtensionContainer() are public in
// QWaylandCompositorExtension (verified on the Qt sources/docs), so
// they can be called from here without needing private APIs.
//
// NOT CONFIRMED: adding this protocol does not guarantee that Wine
// attaches successfully — other requirements we have not yet
// identified may be missing. It is the next sensible step to try,
// not an already verified solution.

#include <QWaylandViewporter>
#include <QWaylandCompositor>
#include <QtQml/qqml.h>

class VoltaViewporter : public QWaylandViewporter
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Viewporter)

public:
    using QWaylandViewporter::QWaylandViewporter;

    // To be called from QML ONCE, when the owning WaylandCompositor
    // is already "created". Sets the container explicitly
    // and then initializes the extension — avoids any race with Qt's
    // automatic "parent adoption" logic.
    Q_INVOKABLE void attachAndInitialize(QWaylandCompositor *compositor)
    {
        if (!extensionContainer())
            setExtensionContainer(compositor);
        if (!isInitialized())
            initialize();
    }
};
