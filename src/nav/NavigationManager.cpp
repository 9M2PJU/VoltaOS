#include <QCoreApplication>
#include "NavigationManager.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>
#include <QtMath>
#include <utility>

// Thresholds taken from MapView.tsx's behavior
static constexpr double OFFROUTE_M      = 35.0;  // off route beyond this distance
static constexpr double MANEUVER_NEAR_M = 40.0;  // advance to the next step
static constexpr int    REROUTE_COOLDOWN_MS = 5000;
// On a two-way road the "wrong" side is often a few meters
// from the right one — well below OFFROUTE_M — so someone who starts going in the
// opposite direction to the one the route expects was NEVER off
// route by distance: the recalculation only fired much later, when
// one had moved far enough away. Below, the minimum speed to
// trust the GPS heading (below this it is too noisy) and the
// angle difference beyond which we consider "going the
// wrong way" even if the distance from the route is still small.
static constexpr double WRONG_WAY_MIN_SPEED_KMH = 8.0;
static constexpr double WRONG_WAY_ANGLE_DEG     = 120.0;
static constexpr qint64 WRONG_WAY_MIN_MS        = 2000;   // wrong way for at least 2 s in a row
// First calculation: if we are already moving, the heading is also passed to Mapbox
// (as in recalculations), so the route does not start "behind us" and a
// recalculation is not needed right after starting.
static constexpr double BEARING_HINT_MIN_KMH    = 8.0;

NavigationManager::NavigationManager(QObject *parent)
    : QObject(parent), m_net(new QNetworkAccessManager(this))
{
    // Token from keys.env (loaded in main.cpp) or from the environment variable
    // MAPBOX_TOKEN; overridable by assigning Nav.token from QML.
    m_token = qEnvironmentVariable("MAPBOX_TOKEN");
    if (m_token.isEmpty())
        qWarning() << "[nav] MAPBOX_TOKEN missing: add it to keys.env";

    // NIENTE connessione globale a QNetworkAccessManager::finished:
    // would route every response (routes AND searches) into the same slot,
    // which consumes the body and destroys the object. Each request is connected
    // to its own handler, right after get().
}

NavigationManager::~NavigationManager() = default;

void NavigationManager::setToken(const QString &t)
{
    if (m_token == t) return;
    m_token = t;
    emit tokenChanged();
}

// ── Geometric utilities ─────────────────────────────────────────────

double NavigationManager::haversine(const QGeoCoordinate &a, const QGeoCoordinate &b)
{
    // QGeoCoordinate already has distanceTo(), which uses the same formula
    if (!a.isValid() || !b.isValid()) return std::numeric_limits<double>::max();
    return a.distanceTo(b);
}

double NavigationManager::distanceToPolyline(const QGeoCoordinate &pos,
                                             const QVariantList &coords, int fromIdx, int toIdx)
{
    double minD = std::numeric_limits<double>::max();
    const int last = qMin(int(coords.size()) - 1, toIdx < 0 ? int(coords.size()) : toIdx);
    for (int i = qMax(0, fromIdx); i < last; ++i) {
        const QGeoCoordinate a = coords.at(i).value<QGeoCoordinate>();
        const QGeoCoordinate b = coords.at(i + 1).value<QGeoCoordinate>();
        if (!a.isValid() || !b.isValid()) continue;

        // Projection onto the segment in lon/lat space (approximation valid
        // over short distances), then real distance with the geodetic method.
        const double ax = a.longitude(), ay = a.latitude();
        const double bx = b.longitude(), by = b.latitude();
        const double dx = bx - ax, dy = by - ay;
        const double len2 = dx * dx + dy * dy;
        double t = 0.0;
        if (len2 > 0.0) {
            t = ((pos.longitude() - ax) * dx + (pos.latitude() - ay) * dy) / len2;
            t = qBound(0.0, t, 1.0);
        }
        const QGeoCoordinate nearest(ay + t * dy, ax + t * dx);
        const double d = pos.distanceTo(nearest);
        if (d < minD) minD = d;
    }
    return minD;
}

// ── Traffico ────────────────────────────────────────────────────────

int NavigationManager::congestionWeight(const QVariant &c)
{
    if (!c.isValid() || c.isNull()) return 0;                 // unknown
    if (c.typeId() == QMetaType::Double || c.typeId() == QMetaType::Int) {
        // Mapbox scale: low 0-39, moderate 40-59, heavy 60-79, severe 80-100
        const double v = c.toDouble();
        if (v < 40) return 1;
        if (v < 60) return 2;
        if (v < 80) return 3;
        return 4;
    }
    const QString s = c.toString().toLower();
    if (s.contains("low")) return 1;
    if (s.contains("mod")) return 2;
    if (s.contains("hea")) return 3;
    if (s.contains("sev")) return 4;
    return 0;
}

QString NavigationManager::congestionColor(const QVariant &c)
{
    switch (congestionWeight(c)) {
    case 2:  return QStringLiteral("#FF9F0A");
    case 3:  return QStringLiteral("#FF3B30");
    case 4:  return QStringLiteral("#CC0000");
    default: return QStringLiteral("#0A84FF");
    }
}

void NavigationManager::parseLegData(const QJsonObject &leg, QList<Step> &steps,
                                     QVariantList &congestion, QList<int> &speedLimits,
                                     QList<double> &segDurations)
{
    const QJsonArray stepsArr = leg.value("steps").toArray();
    for (const QJsonValue &sv : stepsArr) {
        const QJsonObject so = sv.toObject();
        const QJsonObject man = so.value("maneuver").toObject();
        const QJsonArray loc = man.value("location").toArray();

        Step st;
        if (loc.size() >= 2)
            st.maneuverLoc = QGeoCoordinate(loc.at(1).toDouble(), loc.at(0).toDouble());
        st.type     = man.value("type").toString();
        st.modifier = man.value("modifier").toString();
        st.name     = so.value("name").toString();
        st.ref      = so.value("ref").toString();
        st.distance = so.value("distance").toDouble();
        st.duration = so.value("duration").toDouble();

        // The banner text is more readable than the raw instruction
        const QJsonArray banners = so.value("bannerInstructions").toArray();
        if (!banners.isEmpty()) {
            st.instruction = banners.first().toObject()
                               .value("primary").toObject()
                               .value("text").toString();
        }
        if (st.instruction.isEmpty())
            st.instruction = man.value("instruction").toString();

        // Lanes: "lane" components of the sub-banner (first banner that contains them)
        for (const QJsonValue &bv : banners) {
            const QJsonObject bo = bv.toObject();
            const QJsonArray comps = bo.value("sub").toObject().value("components").toArray();
            QVariantList lanes;
            for (const QJsonValue &cv : comps) {
                const QJsonObject co = cv.toObject();
                if (co.value("type").toString() != QLatin1String("lane")) continue;
                QVariantMap lane;
                QStringList dirs;
                for (const QJsonValue &dv : co.value("directions").toArray())
                    dirs << dv.toString();
                lane["directions"]      = dirs;
                lane["active"]          = co.value("active").toBool(false);
                lane["activeDirection"] = co.value("active_direction").toString();
                lanes.append(lane);
            }
            if (!lanes.isEmpty()) {
                st.lanes = lanes;
                st.laneShowDist = bo.value("distanceAlongGeometry").toDouble(400.0);
                break;
            }
        }

        steps.append(st);
    }

    const QJsonObject ann = leg.value("annotation").toObject();
    // First Mapbox's classification (low/moderate/heavy/severe): the numeric
    // thresholds used before (25/50/75) were not Mapbox's and colored randomly.
    QJsonArray congArr = ann.value("congestion").toArray();
    if (congArr.isEmpty()) congArr = ann.value("congestion_numeric").toArray();
    for (const QJsonValue &v : congArr) {
        if (v.isDouble()) congestion.append(v.toDouble());
        else              congestion.append(v.toString());
    }

    for (const QJsonValue &v : ann.value("duration").toArray())
        segDurations.append(v.toDouble());

    for (const QJsonValue &v : ann.value("maxspeed").toArray()) {
        const QJsonObject ms = v.toObject();
        const double sp = ms.value("speed").toDouble();
        if (sp <= 0) { speedLimits.append(0); continue; }
        speedLimits.append(ms.value("unit").toString() == "km/h"
                           ? qRound(sp) : qRound(sp * 1.609));
    }
}

void NavigationManager::buildTrafficSegments(const QVariantList &congestion)
{
    m_trafficSegments.clear();
    m_trafficFrac.clear();
    if (congestion.isEmpty() || m_routeCoords.size() < 2)
        return;

    // cumulative distance along the route, to give the segments a 0..1 position
    QList<double> cum;
    cum.reserve(m_routeCoords.size());
    cum.append(0.0);
    for (int k = 1; k < m_routeCoords.size(); ++k)
        cum.append(cum.last() + haversine(m_routeCoords.at(k - 1).value<QGeoCoordinate>(),
                                          m_routeCoords.at(k).value<QGeoCoordinate>()));
    const double totalLen = qMax(1.0, cum.last());

    // Congestion has one value for each pair of coordinates.
    // We group consecutive segments with the same level, so QML
    // draws a few polylines instead of one for every segment.
    int segStart = 0;
    int curWeight = congestionWeight(congestion.value(0));

    auto flush = [&](int endIdx) {
        QVariantList coords;
        for (int k = segStart; k <= qMin(endIdx + 1, m_routeCoords.size() - 1); ++k)
            coords.append(m_routeCoords.at(k));
        if (coords.size() < 2) return;
        // Free-flowing/unknown segments are already the blue line: we do not pass them to
        // the map (they were hidden lines that MapLibre tried to remove anyway:
        // "Layer not found: QtLocation-..." in the log)
        const QString color = congestionColor(congestion.value(segStart));
        if (color == QLatin1String("#0A84FF")) return;
        QVariantMap seg;
        seg[QStringLiteral("color")] = color;
        seg[QStringLiteral("coordinates")] = coords;   // same points as the blue line: they match exactly
        m_trafficSegments.append(seg);
        QVariantMap fr;
        fr[QStringLiteral("from")]  = cum.value(segStart) / totalLen;
        fr[QStringLiteral("to")]    = cum.value(qMin(endIdx + 1, int(cum.size()) - 1)) / totalLen;
        fr[QStringLiteral("color")] = color;
        m_trafficFrac.append(fr);
    };

    for (int i = 1; i < congestion.size(); ++i) {
        const int w = congestionWeight(congestion.at(i));
        if (w != curWeight) {
            flush(i - 1);
            segStart = i;
            curWeight = w;
        }
    }
    flush(congestion.size() - 1);
}

// ── Richiesta percorso ──────────────────────────────────────────────

void NavigationManager::setAvoidTolls(bool on)
{
    if (m_avoidTolls == on) return;
    m_avoidTolls = on;
    emit routeOptionsChanged();
    recalcForOptionsChange();
}

void NavigationManager::setAvoidFerries(bool on)
{
    if (m_avoidFerries == on) return;
    m_avoidFerries = on;
    emit routeOptionsChanged();
    recalcForOptionsChange();
}

void NavigationManager::recalcForOptionsChange()
{
    // Route already calculated: we recalculate it right away with the new preferences,
    // so the change is visible without having to set the destination again.
    // While navigating we use the recalculation (no alternatives, current heading).
    if (!hasRoute() || !m_destination.isValid()) return;
    doRequest(m_destination.longitude(), m_destination.latitude(),
              m_destName, m_navigating);
}

void NavigationManager::requestRoute(double lon, double lat, const QString &name)
{
    m_waypoints.clear();      // new destination: the previous trip's stops are removed
    m_waypointNames.clear();  // dl92
    doRequest(lon, lat, name, false);
}

void NavigationManager::addWaypoint(double lon, double lat, const QString &name)
{
    if (!m_destination.isValid()) return;
    if (m_waypoints.size() >= maxStops() - 1) return;   // at most 2 stops besides the destination
    // dl93: the new place becomes the NEW destination (last segment, gray in preview);
    // the previous destination becomes a stop (first segment, blue)
    m_waypoints.append(m_destination);
    m_waypointNames.append(m_destName.isEmpty() ? QStringLiteral("Tappa") : m_destName);
    emit waypointCountChanged();
    // after adding a stop we go back to the route preview
    if (m_navigating) stopNavigation();
    doRequest(lon, lat, name.isEmpty() ? QStringLiteral("Destinazione") : name, false);
}

// dl92: replaces all the stops (route edit). The last entry is the destination.
void NavigationManager::setStops(const QVariantList &stops)
{
    QList<QGeoCoordinate> pts;
    QStringList names;
    for (const QVariant &v : stops) {
        const QVariantMap m = v.toMap();
        bool okLat = false, okLon = false;
        const double lat = m.value(QStringLiteral("lat")).toDouble(&okLat);
        const double lon = m.value(QStringLiteral("lon")).toDouble(&okLon);
        if (!okLat || !okLon) continue;
        pts.append(QGeoCoordinate(lat, lon));
        names.append(m.value(QStringLiteral("name")).toString());
    }
    if (pts.isEmpty()) return;
    if (m_token.isEmpty()) { emit routeFailed(QCoreApplication::translate("Msg", "Mapbox token missing")); return; }
    if (!m_lastPos.isValid()) { emit routeFailed(QCoreApplication::translate("Msg", "GPS position not available")); return; }
    // maximum: destination + 2 stops (the first ones and the destination are kept)
    while (pts.size() > maxStops()) { pts.removeAt(pts.size() - 2); names.removeAt(names.size() - 2); }

    const QGeoCoordinate dest = pts.takeLast();
    QString destName = names.takeLast();
    if (destName.isEmpty()) destName = QStringLiteral("Destinazione");
    for (QString &n : names) if (n.isEmpty()) n = QStringLiteral("Tappa");

    m_waypoints = pts;
    m_waypointNames = names;
    emit waypointCountChanged();
    if (m_navigating) stopNavigation();      // after the edit: preview of the new route
    doRequest(dest.longitude(), dest.latitude(), destName, false);
}

QVariantList NavigationManager::stops() const
{
    QVariantList out;
    for (int i = 0; i < m_waypoints.size(); ++i) {
        QVariantMap m;
        m[QStringLiteral("name")] = m_waypointNames.value(i, QStringLiteral("Tappa"));
        m[QStringLiteral("lat")]  = m_waypoints.at(i).latitude();
        m[QStringLiteral("lon")]  = m_waypoints.at(i).longitude();
        m[QStringLiteral("kind")] = QStringLiteral("stop");
        out.append(m);
    }
    if (m_destination.isValid()) {
        QVariantMap m;
        m[QStringLiteral("name")] = m_destName;
        m[QStringLiteral("lat")]  = m_destination.latitude();
        m[QStringLiteral("lon")]  = m_destination.longitude();
        m[QStringLiteral("kind")] = QStringLiteral("dest");
        out.append(m);
    }
    return out;
}

void NavigationManager::abortRouteRequest()
{
    // abort() immediately calls the "finished" handler: we reset the pointer first,
    // so onRouteReply recognizes it as old and does not touch the state.
    if (QNetworkReply *r = m_routeReply) {
        m_routeReply = nullptr;
        r->abort();
    }
    setLoading(false);
    setRerouting(false);
}

void NavigationManager::resetStepTracking()
{
    m_prevManLoc = QGeoCoordinate();
    m_prevManDist = 1e12;
    m_lastStepIdx = -1;
    m_wrongWaySinceMs = 0;
}

bool NavigationManager::doRequest(double lon, double lat,
                                  const QString &name, bool isReroute)
{
    if (m_token.isEmpty()) {
        emit routeFailed(QCoreApplication::translate("Msg", "Mapbox token missing"));
        return false;
    }
    if (!m_lastPos.isValid()) {
        emit routeFailed(QCoreApplication::translate("Msg", "GPS position not available"));
        return false;
    }
    abortRouteRequest();      // one request at a time: the last one wins

    m_destination = QGeoCoordinate(lat, lon);
    if (m_destName != name) { m_destName = name; emit destinationNameChanged(); }
    emit stopsChanged();   // dl92

    // start; intermediate stops (if any); destination
    QString coordList = QStringLiteral("%1,%2")
        .arg(m_lastPos.longitude(), 0, 'f', 6)
        .arg(m_lastPos.latitude(),  0, 'f', 6);
    for (const QGeoCoordinate &w : std::as_const(m_waypoints))
        coordList += QStringLiteral(";%1,%2").arg(w.longitude(), 0, 'f', 6).arg(w.latitude(), 0, 'f', 6);
    coordList += QStringLiteral(";%1,%2").arg(lon, 0, 'f', 6).arg(lat, 0, 'f', 6);
    const QString path = QStringLiteral(
        "https://api.mapbox.com/directions/v5/mapbox/driving-traffic/") + coordList;

    QUrl url(path);
    QUrlQuery q;
    q.addQueryItem("steps", "true");
    q.addQueryItem("geometries", "geojson");
    q.addQueryItem("overview", "full");
    q.addQueryItem("annotations", "congestion,congestion_numeric,maxspeed,duration");
    q.addQueryItem("banner_instructions", "true");
    q.addQueryItem("language", "it");
    // Evita pedaggi / traghetti (Impostazioni → Navigazione)
    QStringList excl;
    if (m_avoidTolls)   excl << QStringLiteral("toll");
    if (m_avoidFerries) excl << QStringLiteral("ferry");
    if (!excl.isEmpty())
        q.addQueryItem("exclude", excl.join(QLatin1Char(',')));
    // Alternatives only in preview (before starting navigation): once
    // started we only follow the chosen route, nothing to recalculate.
    if (!isReroute && m_waypoints.isEmpty()) {   // dl92: with stops no alternative (the gray segments are the stops)
        q.addQueryItem("alternatives", "true");
    }
    if (isReroute || m_lastSpeed >= BEARING_HINT_MIN_KMH) {
        // We give the current heading, so Mapbox does not immediately suggest
        // a U-turn (it also applies to the first calculation if we are moving).
        q.addQueryItem("bearings",
                       QStringLiteral("%1,45").arg(qRound(m_lastBearing))
                       + QString(int(m_waypoints.size()) + 1, QLatin1Char(';')));
    }
    q.addQueryItem("access_token", m_token);
    url.setQuery(q);

    QNetworkRequest req(url);
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setRawHeader("User-Agent", "VoltaOS/1.0");
    // We mark the reply to know, on response, whether it was a recalculation
    QNetworkReply *reply = m_net->get(req);
    m_routeReply = reply;
    reply->setProperty("isReroute", isReroute);
    reply->setProperty("destName", name);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onRouteReply(reply);
    });

    setLoading(true);
    return true;
}

void NavigationManager::onRouteReply(QNetworkReply *reply)
{
    reply->deleteLater();
    // Outdated response (new destination, navigation canceled): ignored.
    // Before, a late response put the route back and made
    // navigation restart by itself even after closing it.
    if (reply != m_routeReply) return;
    m_routeReply = nullptr;
    setLoading(false);

    const bool wasReroute = reply->property("isReroute").toBool();
    if (wasReroute) setRerouting(false);

    if (reply->error() != QNetworkReply::NoError) {
        // BUG fixed: the toast showed reply->errorString() in full —
        // on a network error it can be a very long, technical text
        // (full request URL, protocol/SSL details...),
        // unreadable in a toast while driving. The technical detail
        // stays in the log (line below), in the toast only the essentials.
        qWarning() << "[Nav] network error:" << reply->errorString();
        emit routeFailed(QCoreApplication::translate("Msg", "Network error: route not calculated, retrying shortly"));
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
    const QJsonArray routes = doc.object().value("routes").toArray();
    if (routes.isEmpty()) {
        emit routeFailed(QCoreApplication::translate("Msg", "No route found"));
        return;
    }

    m_currentCoordIdx = 0;   // the old index is not valid on the new route
    resetStepTracking();
    const QJsonObject route = routes.first().toObject();
    const QJsonArray coords = route.value("geometry").toObject()
                                   .value("coordinates").toArray();

    m_routeCoords.clear();
    m_routeCoords.reserve(coords.size());
    for (const QJsonValue &v : coords) {
        const QJsonArray c = v.toArray();
        if (c.size() >= 2)
            m_routeCoords.append(QVariant::fromValue(
                QGeoCoordinate(c.at(1).toDouble(), c.at(0).toDouble())));
    }
    m_routeMidpoint = m_routeCoords.isEmpty()
        ? QGeoCoordinate()
        : m_routeCoords.at(m_routeCoords.size() / 2).value<QGeoCoordinate>();
    m_routeDisplay = m_routeCoords;   // not simplified: it must match the traffic segments

    m_totalDistance = route.value("distance").toDouble();
    m_totalDuration = route.value("duration").toDouble();

    m_steps.clear();
    m_congestion.clear();
    m_speedLimits.clear();
    m_segDurations.clear();
    // one leg for each intermediate stop + the final one: they are queued in order
    for (const QJsonValue &lv : route.value("legs").toArray())
        parseLegData(lv.toObject(), m_steps, m_congestion, m_speedLimits, m_segDurations);
    buildTrafficSegments(m_congestion);
    rebuildRouteIndex();
    rebuildLegPaths();   // dl92

    // Alternative route (if Mapbox proposed one with alternatives=true).
    // Parsed in full (not just the geometry) so selectRoute() can
    // swap it with the active one without redoing the request. Shown
    // only during the preview: QML hides it as soon as navigation starts.
    m_altRouteCoords.clear();
    m_altRouteDisplay.clear();
    m_altRouteDuration = 0;
    m_altRouteMidpoint = QGeoCoordinate();
    m_altSteps.clear();
    m_altCongestion.clear();
    m_altSpeedLimits.clear();
    m_altSegDurations.clear();
    m_altTotalDistance = 0;
    m_altTotalDuration = 0;
    if (routes.size() > 1) {
        const QJsonObject altRoute = routes.at(1).toObject();
        const QJsonArray altCoords = altRoute.value("geometry").toObject()
                                       .value("coordinates").toArray();
        m_altRouteCoords.reserve(altCoords.size());
        for (const QJsonValue &v : altCoords) {
            const QJsonArray c = v.toArray();
            if (c.size() >= 2)
                m_altRouteCoords.append(QVariant::fromValue(
                    QGeoCoordinate(c.at(1).toDouble(), c.at(0).toDouble())));
        }
        if (!m_altRouteCoords.isEmpty())
            m_altRouteMidpoint = m_altRouteCoords.at(m_altRouteCoords.size() / 2)
                                      .value<QGeoCoordinate>();
        m_altRouteDisplay = m_altRouteCoords;
        m_altTotalDistance = altRoute.value("distance").toDouble();
        m_altTotalDuration = altRoute.value("duration").toDouble();
        m_altRouteDuration = qRound(m_altTotalDuration / 60.0);

        for (const QJsonValue &lv : altRoute.value("legs").toArray())
            parseLegData(lv.toObject(), m_altSteps, m_altCongestion, m_altSpeedLimits, m_altSegDurations);
    }

    m_stepIdx = 0;
    m_progress = 0;
    m_remainingDistance = m_totalDistance;
    m_remainingDuration = qRound(m_totalDuration / 60.0);
    m_arrivalTime = QDateTime::currentDateTime()
                        .addSecs(qRound(m_totalDuration))
                        .toString(QStringLiteral("HH:mm"));

    if (!m_steps.isEmpty()) {
        m_instruction      = m_steps.first().instruction;
        m_maneuverType     = m_steps.first().type;
        m_maneuverModifier = m_steps.first().modifier;
        m_nextStreet       = m_steps.size() > 1 ? m_steps.at(1).name
                                                : m_steps.first().name;
    }

    qDebug() << "[Nav] percorso:" << m_routeCoords.size() << "punti,"
             << m_steps.size() << "manovre,"
             << qRound(m_totalDistance / 1000.0) << "km,"
             << m_remainingDuration << "min";

    emit routeChanged();
    emit stepChanged();
    emit maneuverChanged();
    emit progressChanged();
    // (no more startNavigation() here: a recalculation arriving after
    //  navigation was closed must not restart it)
    Q_UNUSED(wasReroute);
}

// ── Stato ───────────────────────────────────────────────────────────

void NavigationManager::setDestinationName(const QString &name)
{
    // Place chosen by tapping the map: the route starts with the provisional name
    // (coordinates) and the street arrives later from reverse geocoding.
    if (name.isEmpty() || name == m_destName) return;
    m_destName = name;
    emit destinationNameChanged();
    emit stopsChanged();   // dl92
}

void NavigationManager::startNavigation()
{
    if (m_navigating || m_routeCoords.isEmpty()) return;
    m_navigating = true;
    emit navigatingChanged();
}

void NavigationManager::stopNavigation()
{
    if (m_rerouting) abortRouteRequest();   // recalculation in progress: no longer needed
    if (!m_navigating) return;
    m_navigating = false;
    emit navigatingChanged();
}

void NavigationManager::selectRoute(int index)
{
    // index 0 = main (already active, nothing to do), 1 = alternative:
    // we swap the two data sets so the chosen one becomes the active one
    // and the other stays available as an alternative (it can be pressed again to
    // go back until navigation starts).
    if (index != 1 || m_altRouteCoords.isEmpty())
        return;

    std::swap(m_routeCoords, m_altRouteCoords);
    std::swap(m_routeDisplay, m_altRouteDisplay);
    std::swap(m_routeMidpoint, m_altRouteMidpoint);
    std::swap(m_steps, m_altSteps);
    std::swap(m_congestion, m_altCongestion);
    std::swap(m_speedLimits, m_altSpeedLimits);
    std::swap(m_segDurations, m_altSegDurations);
    std::swap(m_totalDistance, m_altTotalDistance);
    std::swap(m_totalDuration, m_altTotalDuration);
    m_altRouteDuration = qRound(m_altTotalDuration / 60.0);

    m_currentCoordIdx = 0;
    resetStepTracking();
    m_stepIdx = 0;
    m_progress = 0;
    m_remainingDistance = m_totalDistance;
    m_remainingDuration = qRound(m_totalDuration / 60.0);
    m_arrivalTime = QDateTime::currentDateTime()
                        .addSecs(qRound(m_totalDuration))
                        .toString(QStringLiteral("HH:mm"));
    if (!m_steps.isEmpty()) {
        m_instruction      = m_steps.first().instruction;
        m_maneuverType     = m_steps.first().type;
        m_maneuverModifier = m_steps.first().modifier;
        m_nextStreet       = m_steps.size() > 1 ? m_steps.at(1).name
                                                : m_steps.first().name;
    }
    buildTrafficSegments(m_congestion);
    rebuildRouteIndex();
    rebuildLegPaths();   // dl92

    emit routeChanged();
    emit stepChanged();
    emit maneuverChanged();
    emit progressChanged();
}

void NavigationManager::rebuildRouteIndex()
{
    const int n = int(m_routeCoords.size());
    m_cumDist.resize(n);
    m_cumDur.clear();
    if (n == 0) return;
    m_cumDist[0] = 0;
    for (int i = 1; i < n; ++i)
        m_cumDist[i] = m_cumDist[i - 1] + m_routeCoords.at(i - 1).value<QGeoCoordinate>()
                                              .distanceTo(m_routeCoords.at(i).value<QGeoCoordinate>());
    // Durations per segment (traffic): one per segment, therefore n-1
    if (m_segDurations.size() == n - 1) {
        m_cumDur.resize(n);
        m_cumDur[0] = 0;
        for (int i = 1; i < n; ++i) m_cumDur[i] = m_cumDur[i - 1] + m_segDurations.at(i - 1);
    }
}

// dl92: splits the route into one leg for each stop (+ the final one), looking for the
// route vertex closest to each stop, in order.
void NavigationManager::rebuildLegPaths()
{
    m_legPaths.clear();
    const int n = int(m_routeCoords.size());
    if (n < 2) return;
    QList<int> br;
    int from = 0;
    for (const QGeoCoordinate &w : std::as_const(m_waypoints)) {
        int best = from;
        double bd = std::numeric_limits<double>::max();
        for (int i = from; i < n; ++i) {
            const double d = m_routeCoords.at(i).value<QGeoCoordinate>().distanceTo(w);
            if (d < bd) { bd = d; best = i; }
        }
        br.append(best);
        from = best;
    }
    br.append(n - 1);
    int start = 0;
    for (int b : std::as_const(br)) {
        const int end = qMax(b, qMin(start + 1, n - 1));
        QVariantList path;
        path.reserve(end - start + 1);
        for (int i = start; i <= end; ++i) path.append(m_routeCoords.at(i));
        m_legPaths.append(QVariant::fromValue(path));
        start = b;
    }
}

void NavigationManager::clearRoute()
{
    abortRouteRequest();      // an in-flight calculation must not put the route back
    resetStepTracking();
    m_currentCoordIdx = 0;
    m_isSnapped = false;
    emit snapChanged();
    m_routeCoords.clear();
    m_routeDisplay.clear();
    m_altRouteDisplay.clear();
    m_routeMidpoint = QGeoCoordinate();
    m_altRouteCoords.clear();
    m_altRouteDuration = 0;
    m_altRouteMidpoint = QGeoCoordinate();
    m_altSteps.clear();
    m_altCongestion.clear();
    m_altSpeedLimits.clear();
    m_altTotalDistance = 0;
    m_altTotalDuration = 0;
    m_trafficSegments.clear();
    m_trafficFrac.clear();
    m_congestion.clear();
    m_speedLimits.clear();
    m_segDurations.clear();
    m_altSegDurations.clear();
    m_cumDist.clear();
    m_cumDur.clear();
    m_steps.clear();
    m_destination = QGeoCoordinate();
    if (!m_waypoints.isEmpty()) { m_waypoints.clear(); emit waypointCountChanged(); }
    m_waypointNames.clear();   // dl92
    m_legPaths.clear();        // dl92
    if (!m_destName.isEmpty()) { m_destName.clear(); emit destinationNameChanged(); }
    emit stopsChanged();       // dl92
    m_stepIdx = 0;
    m_progress = 0;
    m_remainingDistance = 0;
    m_remainingDuration = 0;
    m_arrivalTime.clear();
    m_instruction.clear();
    m_maneuverType.clear();
    m_maneuverModifier.clear();
    m_nextStreet.clear();
    m_speedLimit = 0;
    stopNavigation();
    emit routeChanged();
    emit stepChanged();
    emit maneuverChanged();
    emit progressChanged();
}

void NavigationManager::setLoading(bool v)
{
    if (m_loading == v) return;
    m_loading = v;
    emit loadingChanged();
}

void NavigationManager::setRerouting(bool v)
{
    if (m_rerouting == v) return;
    m_rerouting = v;
    emit reroutingChanged();
}

double NavigationManager::zoomForSpeed(double speedKmh) const
{
    if (speedKmh < 10)  return 18.0;
    if (speedKmh < 30)  return 17.5;
    if (speedKmh < 60)  return 17.0;
    if (speedKmh < 100) return 16.5;
    return 16.0;
}

// ── Position update: the heart of navigation ─────────────

void NavigationManager::updatePosition(double lat, double lon,
                                       double bearing, double speedKmh)
{
    m_lastPos     = QGeoCoordinate(lat, lon);
    m_lastBearing = bearing;
    m_lastSpeed   = speedKmh;

    if (m_routeCoords.isEmpty()) {
        // Without a route there is nothing to snap to: we use the raw data
        if (m_isSnapped) { m_isSnapped = false; emit snapChanged(); }
        return;
    }

    updateSnap(m_lastPos);
    recomputeStep(m_lastPos);
    recomputeProgress(m_lastPos);
    if (m_navigating) checkOffRoute(m_lastPos);

    emit progressChanged();
}

void NavigationManager::recomputeStep(const QGeoCoordinate &pos)
{
    if (m_steps.isEmpty()) return;

    // m_stepIdx = road segment we are in (its banner describes the
    // maneuver at the END of the segment, i.e. that of m_steps[m_stepIdx + 1]).
    // We move to the next segment when the maneuver has been reached
    // (within 15 m) or just passed (we are moving away again).
    {
        const int total     = int(m_steps.size());
        const int lookahead = qMin(m_stepIdx + 4, total);
        for (int i = m_stepIdx + 1; i < lookahead; ++i) {
            const QGeoCoordinate loc = m_steps.at(i).maneuverLoc;
            const double d = haversine(pos, loc);
            bool take;
            if (i == m_stepIdx + 1) {
                const bool sameTarget = (m_prevManLoc == loc);
                const bool passed = sameTarget && m_prevManDist < MANEUVER_NEAR_M && d > m_prevManDist + 2.0;
                take = (d < 15.0) || passed;
            } else {
                take = d < MANEUVER_NEAR_M;     // punto saltato: recupera
            }
            if (take) { m_stepIdx = i; break; }
        }
        const int nx = qMin(m_stepIdx + 1, total - 1);
        m_prevManLoc  = m_steps.at(nx).maneuverLoc;
        m_prevManDist = haversine(pos, m_prevManLoc);
    }

    // Maneuver to show: the NEXT one (icon, direction, meters left).
    const int total = int(m_steps.size());
    const int up    = qMin(m_stepIdx + 1, total - 1);
    const Step &cur = m_steps.at(m_stepIdx);
    const Step &nxt = m_steps.at(up);
    const QString nextStreet = (m_stepIdx + 1 < total) ? m_steps.at(m_stepIdx + 1).name
                                                      : cur.name;
    const bool idxChanged = (m_lastStepIdx != m_stepIdx);
    m_lastStepIdx = m_stepIdx;
    if (idxChanged || m_instruction != cur.instruction || m_maneuverType != nxt.type
        || m_maneuverModifier != nxt.modifier || m_nextStreet != nextStreet) {
        m_instruction      = cur.instruction;
        m_maneuverType     = nxt.type;
        m_maneuverModifier = nxt.modifier;
        m_nextStreet       = nextStreet;
        emit stepChanged();
        emit maneuverChanged();
    }

    // Distance from the next maneuver (the one the UI shows large)
    m_distToManeuver = haversine(pos, nxt.maneuverLoc);

    // Stop reached (within 40 m): it no longer goes into the route, not even in recalculations
    if (m_navigating && !m_waypoints.isEmpty() && haversine(pos, m_waypoints.first()) < 40.0) {
        m_waypoints.removeFirst();
        if (!m_waypointNames.isEmpty()) m_waypointNames.removeFirst();   // dl92
        emit waypointCountChanged();
        emit stopsChanged();
    }

    // Arrival: last step and destination within 30 m
    if (m_navigating && m_destination.isValid()
        && haversine(pos, m_destination) < 30.0) {
        stopNavigation();
        emit arrived();
    }
}

void NavigationManager::recomputeProgress(const QGeoCoordinate &pos)
{
    const int n = int(m_routeCoords.size());
    if (n < 2 || m_cumDist.size() != n) return;

    // Segment we are on: the one found by updateSnap (it only searches in a
    // window around the previous position). Only if we are not snapped
    // to the road do we scan the whole route (it rarely happens: then we recalculate).
    int seg = qBound(0, m_currentCoordIdx, n - 2);
    QGeoCoordinate here = m_isSnapped && m_snapped.isValid() ? m_snapped : pos;
    if (!m_isSnapped) {
        double best = std::numeric_limits<double>::max();
        const double k = qCos(qDegreesToRadians(pos.latitude()));
        for (int i = 0; i < n; ++i) {
            const QGeoCoordinate c = m_routeCoords.at(i).value<QGeoCoordinate>();
            const double dx = (c.longitude() - pos.longitude()) * k;
            const double dy = c.latitude() - pos.latitude();
            const double d = dx * dx + dy * dy;
            if (d < best) { best = d; seg = qMin(i, n - 2); }
        }
        here = m_routeCoords.at(seg).value<QGeoCoordinate>();
    }

    const QGeoCoordinate a = m_routeCoords.at(seg).value<QGeoCoordinate>();
    const double segLen = m_cumDist[seg + 1] - m_cumDist[seg];
    const double along  = qMin(segLen, a.distanceTo(here));
    const double t      = segLen > 0 ? along / segLen : 0.0;
    const double total  = m_cumDist[n - 1];
    const double done   = m_cumDist[seg] + along;

    m_progress = total > 0 ? qBound(0.0, done / total, 1.0) : 0.0;
    m_remainingDistance = qMax(0.0, total - done);

    // Remaining time: from Mapbox's per-segment durations (they account for traffic);
    // if missing, proportional to the km left as before.
    double remSec;
    if (m_cumDur.size() == n) {
        const double segDur = m_cumDur[seg + 1] - m_cumDur[seg];
        remSec = qMax(0.0, m_cumDur[n - 1] - m_cumDur[seg] - segDur * t);
    } else {
        remSec = m_totalDistance > 0 ? m_totalDuration * (m_remainingDistance / m_totalDistance) : 0.0;
    }
    m_remainingDuration = qRound(remSec / 60.0);
    m_arrivalTime = QDateTime::currentDateTime().addSecs(qRound(remSec))
                        .toString(QStringLiteral("HH:mm"));

    // Speed limit of the current segment
    m_speedLimit = (seg < m_speedLimits.size()) ? m_speedLimits.at(seg) : 0;
}

void NavigationManager::checkOffRoute(const QGeoCoordinate &pos)
{
    if (m_rerouting || m_routeCoords.size() < 2) return;

    // Look only at the part of the route ahead of us, otherwise going
    // back along an already traveled road we would never be off route.
    const int fromIdx = qMax(0, m_currentCoordIdx - 2);
    const double d = distanceToPolyline(pos, m_routeCoords, fromIdx, fromIdx + 300);

    // "Wrong way" relative to the route: it happens right after starting, on a
    // two-way road, if we are (or start) on the opposite side
    // to the right one — the wrong side is often a few meters from the
    // right one, so distance alone (above) does not notice. Here
    // we also look at the heading: if we move at normal speed but
    // clearly in the opposite direction to the one the route expects at the nearest
    // point (m_routeBearing, just updated by updateSnap), we are
    // off route anyway even if still "close" by distance.
    bool wrongWay = false;
    if (m_isSnapped && m_lastSpeed > WRONG_WAY_MIN_SPEED_KMH) {
        // m_lastBearing (GPS) and m_routeBearing (azimuthTo) are both
        // already in the range [0, 360): no modulo needed.
        double diff = qAbs(m_lastBearing - m_routeBearing);
        if (diff > 180.0) diff = 360.0 - diff;
        wrongWay = diff > WRONG_WAY_ANGLE_DEG;
    }
    // A single "wrong way" sample is not enough (noisy GPS, tight curve):
    // deve durare almeno WRONG_WAY_MIN_MS.
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    if (!wrongWay) m_wrongWaySinceMs = 0;
    else if (m_wrongWaySinceMs == 0) m_wrongWaySinceMs = nowMs;
    const bool wrongWayLong = wrongWay && nowMs - m_wrongWaySinceMs >= WRONG_WAY_MIN_MS;

    if (d <= OFFROUTE_M && !wrongWayLong) return;

    // Avoids bursts of recalculations
    if (m_lastRerouteAt.isValid()
        && m_lastRerouteAt.msecsTo(QDateTime::currentDateTime()) < REROUTE_COOLDOWN_MS)
        return;

    m_lastRerouteAt = QDateTime::currentDateTime();
    qDebug() << "[Nav] off route" << qRound(d) << "m"
             << (wrongWayLong ? "(contromano)" : "") << "— ricalcolo";
    // "rerouting" only if the request really started: before, if it failed immediately
    // (e.g. missing token), it stayed true forever and the check switched off.
    if (doRequest(m_destination.longitude(), m_destination.latitude(), m_destName, true))
        setRerouting(true);
}

// ═════════════════════════════════════════════════════════════════════
// SNAP SU STRADA
// ═════════════════════════════════════════════════════════════════════
//
// The GPS puts the car "next to" the road (error of a few meters) and its
// bearing, at low speed, jumps even by 90°. If we have a route,
// we project the position onto the nearest segment: the marker stays glued
// to the carriageway and we take the orientation from the road's direction,
// which is stable by construction.

void NavigationManager::updateSnap(const QGeoCoordinate &pos)
{
    if (m_routeCoords.size() < 2) {
        if (m_isSnapped) { m_isSnapped = false; emit snapChanged(); }
        return;
    }

    double bestDist = 1e12;
    QGeoCoordinate bestPoint;
    double bestBearing = m_routeBearing;

    // We limit ourselves to a window around the point already reached: it avoids that
    // a route that passes close to itself again makes us jump back.
    const int from = qMax(0, m_currentCoordIdx - 30);
    const int to   = qMin(m_routeCoords.size() - 1, m_currentCoordIdx + 200);

    for (int i = from; i < to; ++i) {
        const QGeoCoordinate a = m_routeCoords.at(i).value<QGeoCoordinate>();
        const QGeoCoordinate b = m_routeCoords.at(i + 1).value<QGeoCoordinate>();

        // Projection onto the segment in local coordinates (meters), sufficient
        // a queste distanze.
        const double latRad = qDegreesToRadians(pos.latitude());
        const double mPerDegLat = 111132.0;
        const double mPerDegLon = 111320.0 * qCos(latRad);

        const double ax = 0.0, ay = 0.0;
        const double bx = (b.longitude() - a.longitude()) * mPerDegLon;
        const double by = (b.latitude()  - a.latitude())  * mPerDegLat;
        const double px = (pos.longitude() - a.longitude()) * mPerDegLon;
        const double py = (pos.latitude()  - a.latitude())  * mPerDegLat;

        const double segLen2 = bx * bx + by * by;
        double t = (segLen2 > 0.0) ? ((px - ax) * bx + (py - ay) * by) / segLen2 : 0.0;
        t = qBound(0.0, t, 1.0);

        const double cx = bx * t, cy = by * t;
        const double dx = px - cx, dy = py - cy;
        const double d  = qSqrt(dx * dx + dy * dy);

        if (d < bestDist) {
            bestDist = d;
            bestPoint = QGeoCoordinate(
                a.latitude()  + (b.latitude()  - a.latitude())  * t,
                a.longitude() + (b.longitude() - a.longitude()) * t);
            bestBearing = a.azimuthTo(b);
            m_currentCoordIdx = i;
        }
    }

    // Beyond 40 m from the road it makes no sense to snap: we are really
    // off route (parking lot, unmapped road, big GPS error).
    //
    // BUG fixed: in a tight curve the GPS receiver often lags a moment
    // (it is a known characteristic of these modules, not something
    // that can be eliminated in software) and a single sample may fall
    // momentarily beyond this threshold — the arrow "left" the
    // road only to re-enter it by itself at the next sample. Now
    // a couple of samples IN A ROW must be far away before really
    // releasing the snap: re-snapping instead stays immediate.
    const bool farSample = (bestDist > 40.0);
    m_offRouteStreak = farSample ? (m_offRouteStreak + 1) : 0;
    const bool ok = !farSample || m_offRouteStreak < 2;

    const bool changed = (ok != m_isSnapped)
                      || (ok && !farSample && (bestPoint != m_snapped
                                 || !qFuzzyCompare(bestBearing + 1.0, m_routeBearing + 1.0)));

    m_isSnapped = ok;
    if (ok && !farSample) {
        m_snapped      = bestPoint;
        m_routeBearing = bestBearing;
    }
    if (changed) emit snapChanged();
}

// Maneuvers after the current one (for the banner's expandable list)
QVariantList NavigationManager::upcomingManeuvers() const
{
    QVariantList out;
    for (int i = m_stepIdx + 1; i < m_steps.size() && out.size() < 60; ++i) {   // the 1st is the banner's maneuver
        const Step &s = m_steps.at(i);
        QVariantMap m;
        m["type"]     = s.type;
        m["modifier"] = s.modifier;
        m["street"]   = s.name.isEmpty() ? s.instruction : s.name;
        m["distance"] = m_steps.at(i > 0 ? i - 1 : 0).distance;   // distance from the previous maneuver
        m["name"]     = s.name;                       // road entered after the maneuver
        m["ref"]      = s.ref;
        m["lat"]      = s.maneuverLoc.latitude();     // for the dot and the sign on the map
        m["lon"]      = s.maneuverLoc.longitude();
        out.append(m);
    }
    return out;
}

// Lanes of the next maneuver: the data is in the current step (Mapbox banner) and
// applies to the maneuver at the end of the step, i.e. the start of the next step.
QVariantList NavigationManager::laneGuidance() const
{
    if (!m_navigating || m_stepIdx < 0 || m_stepIdx >= m_steps.size()) return {};
    const Step &s = m_steps.at(m_stepIdx);
    if (s.lanes.isEmpty() || m_stepIdx + 1 >= m_steps.size()) return {};
    const double d = haversine(m_lastPos, m_steps.at(m_stepIdx + 1).maneuverLoc);
    if (d > qMax(s.laneShowDist, 150.0)) return {};
    return s.lanes;
}
