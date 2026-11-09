#include "VoltaPresentation.h"

#include <QDebug>
#include <time.h>

void VoltaPresentationFeedback::sendPresentedNow()
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    const quint64 sec = static_cast<quint64>(ts.tv_sec);

    // refresh: nominal duration of a frame in nanoseconds. From here we have no
    // reliable way to read the display's real refresh rate
    // — 60Hz is the same assumption already used elsewhere in the project for
    // time-based polling. Approximate: gamescope uses it for its own internal
    // pacing, not to synchronize exactly to this number.
    const quint32 refreshNs = 16666667; // ~1/60s

    send_presented(static_cast<uint32_t>(sec >> 32),
                   static_cast<uint32_t>(sec & 0xffffffffu),
                   static_cast<uint32_t>(ts.tv_nsec),
                   refreshNs,
                   0, 0,   // seq_hi/seq_lo: no real frame counter to expose — 0 is a valid "unknown" MSC
                   0);     // flags: none of the known bits declared, see comment in VoltaPresentation.h

    wl_resource_destroy(resource()->handle);
}

void VoltaPresentation::attachAndInitialize(QWaylandCompositor *compositor)
{
    if (!extensionContainer())
        setExtensionContainer(compositor);
    if (!isInitialized())
        initialize();
}

void VoltaPresentation::initialize()
{
    QWaylandCompositor *comp = qobject_cast<QWaylandCompositor *>(extensionContainer());
    if (!comp) {
        qWarning() << "VoltaPresentation: QWaylandCompositor not found, wp_presentation not activated";
        return;
    }
    QWaylandCompositorExtensionTemplate::initialize();
    init(comp->display(), 1);
    qDebug() << "[Compositor] wp_presentation inizializzato (versione 1)";
}

void VoltaPresentation::wp_presentation_bind_resource(Resource *resource)
{
    // Required by the protocol: it must be sent before any other event,
    // once per client. CLOCK_MONOTONIC (value 1 on Linux, from
    // <time.h>) — the same clock used in
    // VoltaPresentationFeedback::sendPresentedNow().
    send_clock_id(resource->handle, CLOCK_MONOTONIC);
}

void VoltaPresentation::wp_presentation_destroy(Resource *resource)
{
    wl_resource_destroy(resource->handle);
}

void VoltaPresentation::wp_presentation_feedback(Resource *resource, struct ::wl_resource *surface,
                                                  uint32_t callback)
{
    Q_UNUSED(surface);
    auto *feedback = new VoltaPresentationFeedback(resource->client(), callback, resource->version());
    m_pending.append(feedback);
}

void VoltaPresentation::notifyFramePresented()
{
    if (m_pending.isEmpty())
        return;
    const auto pending = m_pending;
    m_pending.clear();
    for (VoltaPresentationFeedback *feedback : pending) {
        feedback->sendPresentedNow();
        delete feedback;
    }
}
