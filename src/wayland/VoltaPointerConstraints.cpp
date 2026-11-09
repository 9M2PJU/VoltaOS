#include "VoltaPointerConstraints.h"

#include <QDebug>

void VoltaLockedPointerObject::zwp_locked_pointer_v1_destroy(Resource *resource)
{
    wl_resource_destroy(resource->handle);
}

void VoltaLockedPointerObject::zwp_locked_pointer_v1_destroy_resource(Resource *resource)
{
    Q_UNUSED(resource);
    delete this;
}

void VoltaConfinedPointerObject::zwp_confined_pointer_v1_destroy(Resource *resource)
{
    wl_resource_destroy(resource->handle);
}

void VoltaConfinedPointerObject::zwp_confined_pointer_v1_destroy_resource(Resource *resource)
{
    Q_UNUSED(resource);
    delete this;
}

void VoltaPointerConstraints::attachAndInitialize(QWaylandCompositor *compositor)
{
    if (!extensionContainer())
        setExtensionContainer(compositor);
    if (!isInitialized())
        initialize();
}

void VoltaPointerConstraints::initialize()
{
    QWaylandCompositor *comp = qobject_cast<QWaylandCompositor *>(extensionContainer());
    if (!comp) {
        qWarning() << "VoltaPointerConstraints: QWaylandCompositor not found, "
                      "zwp_pointer_constraints_v1 not activated";
        return;
    }
    QWaylandCompositorExtensionTemplate::initialize();
    init(comp->display(), 1);
    qDebug() << "[Compositor] zwp_pointer_constraints_v1 inizializzato (versione 1)";
}

void VoltaPointerConstraints::zwp_pointer_constraints_v1_destroy(Resource *resource)
{
    wl_resource_destroy(resource->handle);
}

void VoltaPointerConstraints::zwp_pointer_constraints_v1_lock_pointer(
        Resource *resource, uint32_t id,
        struct ::wl_resource *surface, struct ::wl_resource *pointer,
        struct ::wl_resource *region, uint32_t lifetime)
{
    Q_UNUSED(surface);
    Q_UNUSED(pointer);
    Q_UNUSED(region);
    Q_UNUSED(lifetime);
    // simplified v1 — see the comment at the top of VoltaPointerConstraints.h:
    // we activate the lock immediately, without really checking the
    // cursor position against the region/surface.
    auto *locked = new VoltaLockedPointerObject(resource->client(), id, resource->version());
    locked->activateLocked();
}

void VoltaPointerConstraints::zwp_pointer_constraints_v1_confine_pointer(
        Resource *resource, uint32_t id,
        struct ::wl_resource *surface, struct ::wl_resource *pointer,
        struct ::wl_resource *region, uint32_t lifetime)
{
    Q_UNUSED(surface);
    Q_UNUSED(pointer);
    Q_UNUSED(region);
    Q_UNUSED(lifetime);
    auto *confined = new VoltaConfinedPointerObject(resource->client(), id, resource->version());
    confined->activateConfined();
}
