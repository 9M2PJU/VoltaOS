#pragma once

// FROM-SCRATCH implementation of the Wayland protocol "relative-pointer-unstable-v1"
// (zwp_relative_pointer_manager_v1) — round72c, same technique already used for
// wp_presentation (VoltaPresentation.h) e wp_viewporter (VoltaViewporter.h):
// generated from the official system XML spec ("wayland-protocols" package),
// via qt_generate_wayland_protocol_server_sources() in CMakeLists.txt — not
// a private Qt API (which does not exist here anyway: no header, public
// or private, for this protocol in QtWaylandCompositor).
//
// WHY IT IS NEEDED: round72 discovered (reading the REAL source code of
// gamescope, not by guessing — see src/Backends/WaylandBackend.cpp,
// CWaylandBackend::Init()) that the check that makes
// "xdg_backend: Couldn't create Wayland objects." requires ALL together:
// wl_compositor, wl_subcompositor, xdg_wm_base, zwp_linux_dmabuf_v1,
// wp_viewporter, wp_presentation, zwp_relative_pointer_manager_v1,
// zwp_pointer_constraints_v1, wl_shm. Implementing only wp_presentation
// (round70) was not enough: THESE two pointer protocols were ALSO missing
// (this file) and zwp_pointer_constraints_v1 (VoltaPointerConstraints.h).
// zwp_linux_dmabuf_v1 instead we do NOT implement ourselves: Qt already provides it
// internamente (plugin "qt-wayland-compositor-linux-dmabuf-unstable-v1",
// confirmed installed on the system), but only when the compositor's EGL hardware
// integration initializes successfully — see the fix of
// QT_XCB_GL_INTEGRATION in main.cpp, same round.
//
// Deliberate simplification (v1): we implement the protocol hookup
// (manager bind, creation/destruction of the zwp_relative_pointer_v1 object
// for every get_relative_pointer request) WITHOUT yet sending real
// relative_motion events — that would require hooking the real mouse movement
// on the QWaylandSeat/QML side, a separate job. This is enough to make
// gamescope pass the strict check in Init() (which only verifies that the global
// exists, not that it is used), but a game that needs REAL mouse-look
// (e.g. a first-person shooter) will not yet get a free view
// with this change alone. To be refined in a later round if needed.

#include <QWaylandCompositorExtensionTemplate>
#include <QWaylandCompositor>
#include <QtQml/qqml.h>

#include "qwayland-server-relative-pointer-unstable-v1.h"

// A single "zwp_relative_pointer_v1" object: born from a
// get_relative_pointer() request of the client, lives until the client destroys it
// (or disconnects) — it destroys itself (see .cpp), no list to
// manage by hand as for VoltaPresentation's feedback (here there is no
// "final" event that we have to send: the object stays alive for the whole
// duration of the client's session).
class VoltaRelativePointerObject : public QtWaylandServer::zwp_relative_pointer_v1
{
public:
    VoltaRelativePointerObject(struct ::wl_client *client, uint32_t id, int version)
        : QtWaylandServer::zwp_relative_pointer_v1(client, id, version) {}

protected:
    void zwp_relative_pointer_v1_destroy(Resource *resource) override;
    void zwp_relative_pointer_v1_destroy_resource(Resource *resource) override;
};

class VoltaRelativePointerManager : public QWaylandCompositorExtensionTemplate<VoltaRelativePointerManager>
                                   , public QtWaylandServer::zwp_relative_pointer_manager_v1
{
    Q_OBJECT
    QML_NAMED_ELEMENT(RelativePointerManager)

public:
    using QWaylandCompositorExtensionTemplate::QWaylandCompositorExtensionTemplate;

    // Exactly the same logic as VoltaPresentation::attachAndInitialize() /
    // VoltaViewporter::attachAndInitialize() — see those files for the reason
    // (ordering bug on the automatic adoption of the QML parent).
    Q_INVOKABLE void attachAndInitialize(QWaylandCompositor *compositor);

    void initialize() override;

protected:
    void zwp_relative_pointer_manager_v1_destroy(Resource *resource) override;
    void zwp_relative_pointer_manager_v1_get_relative_pointer(Resource *resource, uint32_t id,
                                                                struct ::wl_resource *pointer) override;
};
