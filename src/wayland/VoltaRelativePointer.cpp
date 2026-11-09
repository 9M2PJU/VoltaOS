#include "VoltaRelativePointer.h"

#include <QDebug>

void VoltaRelativePointerObject::zwp_relative_pointer_v1_destroy(Resource *resource)
{
    wl_resource_destroy(resource->handle);
}

void VoltaRelativePointerObject::zwp_relative_pointer_v1_destroy_resource(Resource *resource)
{
    Q_UNUSED(resource);
    // The wayland resource has already been destroyed (called by libwayland
    // when the client sends "destroy" or disconnects) — here it is up to us to
    // free the C++ wrapper object, same self-cleanup pattern used
    // by Qt itself in its internal classes.
    delete this;
}

void VoltaRelativePointerManager::attachAndInitialize(QWaylandCompositor *compositor)
{
    if (!extensionContainer())
        setExtensionContainer(compositor);
    if (!isInitialized())
        initialize();
}

void VoltaRelativePointerManager::initialize()
{
    QWaylandCompositor *comp = qobject_cast<QWaylandCompositor *>(extensionContainer());
    if (!comp) {
        qWarning() << "VoltaRelativePointerManager: QWaylandCompositor not found, "
                      "zwp_relative_pointer_manager_v1 not activated";
        return;
    }
    QWaylandCompositorExtensionTemplate::initialize();
    init(comp->display(), 1);
    qDebug() << "[Compositor] zwp_relative_pointer_manager_v1 inizializzato (versione 1)";
}

void VoltaRelativePointerManager::zwp_relative_pointer_manager_v1_destroy(Resource *resource)
{
    wl_resource_destroy(resource->handle);
}

void VoltaRelativePointerManager::zwp_relative_pointer_manager_v1_get_relative_pointer(
        Resource *resource, uint32_t id, struct ::wl_resource *pointer)
{
    Q_UNUSED(pointer);
    // simplified v1 — see the comment at the top of VoltaRelativePointer.h:
    // we create the object so gamescope passes the strict check in
    // Init(), but we do not send real relative_motion events yet.
    // The object destroys itself when its wayland resource dies (see
    // VoltaRelativePointerObject::zwp_relative_pointer_v1_destroy_resource).
    new VoltaRelativePointerObject(resource->client(), id, resource->version());
}
