#pragma once

// FROM-SCRATCH implementation of the Wayland protocol "wp_presentation"
// (presentation-time) — needed by gamescope to attach to our
// compositor instead of falling back to its invisible headless backend.
//
// WHY FROM SCRATCH: in rounds 56-58 we tried to use Qt's
// internal class (QWaylandPresentationTime, exposed to QML as
// "PresentationTime") — abandoned because in that Qt build
// (6.11.1) that class has NO public header (only
// qwaylandpresentationtime_p.h/_p_p.h, private, confirmed with
// `find / -iname "*presentationtime*.h"` on the build machine), so
// it cannot be subclassed by external code. Here we do NOT depend at all on
// that internal class: we generate our own support code
// directly from the protocol's official XML spec (system package
// "wayland-protocols"), with the exact same public and documented
// mechanism by which Qt itself generates xdg-shell and the others
// protocolli "ufficiali" — qt_generate_wayland_protocol_server_sources()
// in CMakeLists.txt, not a private API.
//
// VERIFIED IN THIS SESSION (not just written on paper): I
// installed qt6-wayland-dev + wayland-protocols in a Qt 6.4.2 environment
// e rigenerato davvero "qwayland-server-presentation-time.h/.cpp" dallo
// same exact system XML file, then compiled AND linked this class
// (VoltaPresentation.h/.cpp) in full against those real APIs
// of QWaylandCompositorExtensionTemplate — zero compile or
// link errors. It is not the same environment/Qt version as the real
// build machine (6.11.1), so it is not an absolute guarantee, but it is much more
// solid than an attempt written without ever compiling it.
//
// Why it is really needed: gamescope, connecting as a "nested"
// Wayland client to our compositor, requires this protocol — otherwise it
// refuses to create its Wayland objects and falls back to an invisible headless
// backend (confirmed in the log, round67: "Your Wayland
// compositor does NOT support wp_presentation/presentation-time..." then
// "xdg_backend: Couldn't create Wayland objects."). With this protocol
// present, gamescope is again the path with the fewest complications
// compared to "bare" Xwayland (round66-68c): gamescope itself acts as
// window manager for its internal Xwayland, we do not have to implement
// that part ourselves.
//
// NOT CONFIRMED: it only solves the missing protocol on OUR
// compositor. It does not guarantee that gamescope then completes the
// rest of its negotiation successfully (other requirements not yet identified
// may emerge) — next concrete experiment, to be verified
// empirically with the log/screenshot after the real rebuild.
//
// Deliberate simplification (v1): we send "presented" to ALL the
// pending feedbacks at every real frame of the output window (see
// notifyFramePresented(), hooked to QQuickWindow::frameSwapped by
// VoltaCompositor.qml), without distinguishing whether the requesting surface
// was really the one visible in that specific frame — gamescope
// mostly uses it for its own internal frame pacing, not for
// pixel-perfect guarantees, so this approximation should be enough.
// "flags" is always sent as 0 (none of the vsync/hw_clock/
// hw_completion/zero_copy bits declared, because we cannot guarantee them
// with certainty from our Qt Quick renderer) and "refresh" is fixed at ~1/60s
// (same 60fps assumption already used elsewhere in the project) — if
// more precise pacing were needed it can be refined in a later round.

#include <QWaylandCompositorExtensionTemplate>
#include <QWaylandCompositor>
#include <QtQml/qqml.h>
#include <QList>

#include "qwayland-server-presentation-time.h"

// A single "wp_presentation_feedback" object: born from a
// feedback() request of the client (see VoltaPresentation::wp_presentation_feedback
// below), lives until we send "presented"/"discarded" ("destructor"
// events by protocol), then it must be deleted by the caller.
class VoltaPresentationFeedback : public QtWaylandServer::wp_presentation_feedback
{
public:
    VoltaPresentationFeedback(struct ::wl_client *client, uint32_t id, int version)
        : QtWaylandServer::wp_presentation_feedback(client, id, version) {}

    // Sends "presented" with the timestamp of NOW and destroys the resource
    // wayland. Il chiamante (VoltaPresentation::notifyFramePresented)
    // then also deletes the C++ object.
    void sendPresentedNow();
};

class VoltaPresentation : public QWaylandCompositorExtensionTemplate<VoltaPresentation>
                         , public QtWaylandServer::wp_presentation
{
    Q_OBJECT
    QML_NAMED_ELEMENT(PresentationTime)

public:
    using QWaylandCompositorExtensionTemplate::QWaylandCompositorExtensionTemplate;

    // To be called from QML only once, when the owning WaylandCompositor
    // is already "created" — exactly the same logic as
    // VoltaViewporter::attachAndInitialize() (see that file for the
    // reason: ordering bug on the automatic adoption of the QML parent,
    // solved by setting extensionContainer BEFORE initialize()).
    Q_INVOKABLE void attachAndInitialize(QWaylandCompositor *compositor);

    // Da agganciare, in VoltaCompositor.qml, a QQuickWindow::frameSwapped
    // of the real output window — see the "Deliberate
    // simplification" in the comment at the top of the file.
    Q_INVOKABLE void notifyFramePresented();

    // Required override: unlike QWaylandViewporter (public
    // Qt class, with its own already correct initialize()), here the
    // protocol is implemented from scratch (see comment at the top), so
    // WE have to hook init(display, version) to the compositor —
    // exactly what QWaylandPresentationTime::initialize() did
    // (privately, not callable by us) according to the code cited in the
    // commit round58.
    void initialize() override;

protected:
    void wp_presentation_bind_resource(Resource *resource) override;
    void wp_presentation_destroy(Resource *resource) override;
    void wp_presentation_feedback(Resource *resource, struct ::wl_resource *surface,
                                   uint32_t callback) override;

private:
    QList<VoltaPresentationFeedback *> m_pending;
};
