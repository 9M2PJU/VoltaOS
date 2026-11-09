#pragma once

// FROM-SCRATCH implementation of the Wayland protocol
// "pointer-constraints-unstable-v1" (zwp_pointer_constraints_v1) — round72c,
// same technique as VoltaPresentation.h/VoltaRelativePointer.h: generated
// from the official system XML spec via
// qt_generate_wayland_protocol_server_sources() in CMakeLists.txt. Vedi
// VoltaRelativePointer.h for the general reason (gamescope's strict check
// in CWaylandBackend::Init(), read in its real source code) —
// this is the last of the three missing protocols identified in
// quel controllo (insieme a zwp_relative_pointer_manager_v1 e
// zwp_linux_dmabuf_v1, the latter already provided by Qt internally, see
// the QT_XCB_GL_INTEGRATION fix in main.cpp).
//
// Deliberate simplification (v1): when a client requests lock_pointer
// or confine_pointer, we create the object and IMMEDIATELY send the
// activation event ("locked"/"confined") — the protocol explicitly
// allows it ("this request may not take effect immediately", it does not
// guarantee WHEN it activates, "right away" is fine too). What we do NOT
// do yet in this v1: really prevent the pointer from moving/
// leaving the region at the QWaylandSeat/QML level — it would need
// a separate integration with the real dispatch of mouse events.
// Practical result: gamescope passes the check in Init() and games
// that only request the lock without depending on real
// cursor confinement work; a game that DOES expect
// cursore resti davvero intrappolato (tipicamente qualunque sparatutto in
// first person with mouse-look) will not yet get that behavior with
// this change alone. To be refined in a later round if needed.

#include <QWaylandCompositorExtensionTemplate>
#include <QWaylandCompositor>
#include <QtQml/qqml.h>

#include "qwayland-server-pointer-constraints-unstable-v1.h"

// "zwp_locked_pointer_v1": born from a lock_pointer() request, lives until
// the client destroys it (or disconnects) — it destroys itself,
// same pattern as VoltaRelativePointerObject.
class VoltaLockedPointerObject : public QtWaylandServer::zwp_locked_pointer_v1
{
public:
    VoltaLockedPointerObject(struct ::wl_client *client, uint32_t id, int version)
        : QtWaylandServer::zwp_locked_pointer_v1(client, id, version) {}

    // Sends the "locked" event — see the "Deliberate simplification" above:
    // we send it right after creation, we do not wait for any
    // real condition on the cursor position.
    void activateLocked() { send_locked(); }

protected:
    void zwp_locked_pointer_v1_destroy(Resource *resource) override;
    void zwp_locked_pointer_v1_destroy_resource(Resource *resource) override;
};

// "zwp_confined_pointer_v1": same treatment, for confine_pointer().
class VoltaConfinedPointerObject : public QtWaylandServer::zwp_confined_pointer_v1
{
public:
    VoltaConfinedPointerObject(struct ::wl_client *client, uint32_t id, int version)
        : QtWaylandServer::zwp_confined_pointer_v1(client, id, version) {}

    void activateConfined() { send_confined(); }

protected:
    void zwp_confined_pointer_v1_destroy(Resource *resource) override;
    void zwp_confined_pointer_v1_destroy_resource(Resource *resource) override;
};

class VoltaPointerConstraints : public QWaylandCompositorExtensionTemplate<VoltaPointerConstraints>
                               , public QtWaylandServer::zwp_pointer_constraints_v1
{
    Q_OBJECT
    QML_NAMED_ELEMENT(PointerConstraints)

public:
    using QWaylandCompositorExtensionTemplate::QWaylandCompositorExtensionTemplate;

    // Exactly the same logic as VoltaPresentation::attachAndInitialize().
    Q_INVOKABLE void attachAndInitialize(QWaylandCompositor *compositor);

    void initialize() override;

protected:
    void zwp_pointer_constraints_v1_destroy(Resource *resource) override;
    void zwp_pointer_constraints_v1_lock_pointer(Resource *resource, uint32_t id,
                                                  struct ::wl_resource *surface,
                                                  struct ::wl_resource *pointer,
                                                  struct ::wl_resource *region,
                                                  uint32_t lifetime) override;
    void zwp_pointer_constraints_v1_confine_pointer(Resource *resource, uint32_t id,
                                                     struct ::wl_resource *surface,
                                                     struct ::wl_resource *pointer,
                                                     struct ::wl_resource *region,
                                                     uint32_t lifetime) override;
};
