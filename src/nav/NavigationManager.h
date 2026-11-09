#pragma once
#include <QObject>
#include <QGeoCoordinate>
#include <QVariantList>
#include <QDateTime>
#include <QJsonObject>
#include <QVector>

class QNetworkAccessManager;
class QNetworkReply;

/**
 * NavigationManager — turn-by-turn navigation logic.
 *
 * Ports to C++ the same logic that ran in MapView.tsx with Mapbox GL JS:
 *  - richiesta percorso a Mapbox Directions (profilo driving-traffic)
 *  - parsing of geometry, maneuvers (steps) and congestion
 *  - advancing to the next step when approaching the maneuver
 *  - computing the progress along the route
 *  - off-route detection and automatic recalculation
 *
 * The drawing stays in QML: here only data is exposed.
 */
class NavigationManager : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString token READ token WRITE setToken NOTIFY tokenChanged)
    // Route preferences (Settings → Navigation). Applied to every
    // Mapbox request with the "exclude" parameter.
    Q_PROPERTY(bool avoidTolls   READ avoidTolls   WRITE setAvoidTolls   NOTIFY routeOptionsChanged)
    Q_PROPERTY(bool avoidFerries READ avoidFerries WRITE setAvoidFerries NOTIFY routeOptionsChanged)

    // Percorso
    Q_PROPERTY(QVariantList routeCoordinates READ routeCoordinates NOTIFY routeChanged)
    Q_PROPERTY(QVariantList trafficSegments  READ trafficSegments  NOTIFY routeChanged)
    Q_PROPERTY(QVariantList trafficFractions READ trafficFractions NOTIFY routeChanged)
    // Route to draw: today equal to routeCoordinates. It used to be simplified, but the traffic
    // segments no longer matched the blue line and the route jittered when zooming.
    Q_PROPERTY(QVariantList routeDisplayCoordinates    READ routeDisplayCoordinates    NOTIFY routeChanged)
    Q_PROPERTY(QVariantList altRouteDisplayCoordinates READ altRouteDisplayCoordinates NOTIFY routeChanged)
    Q_PROPERTY(bool    hasRoute      READ hasRoute      NOTIFY routeChanged)
    Q_PROPERTY(QGeoCoordinate destination READ destination NOTIFY routeChanged)
    Q_PROPERTY(QString destinationName    READ destinationName NOTIFY destinationNameChanged)

    // Alternative route (preview with two options, like Google/EVs)
    Q_PROPERTY(bool         hasAltRoute       READ hasAltRoute       NOTIFY routeChanged)
    Q_PROPERTY(QVariantList altRouteCoordinates READ altRouteCoordinates NOTIFY routeChanged)
    Q_PROPERTY(int          altRouteDuration  READ altRouteDuration  NOTIFY routeChanged)
    Q_PROPERTY(QGeoCoordinate altRouteMidpoint READ altRouteMidpoint NOTIFY routeChanged)
    Q_PROPERTY(QGeoCoordinate routeMidpoint    READ routeMidpoint    NOTIFY routeChanged)

    // Stato navigazione
    Q_PROPERTY(bool navigating  READ navigating  NOTIFY navigatingChanged)
    Q_PROPERTY(int waypointCount READ waypointCount NOTIFY waypointCountChanged)
    Q_PROPERTY(QVariantList waypoints READ waypoints NOTIFY waypointCountChanged)
    // dl92: all the stops in order, destination last: [{name, lat, lon, kind}]
    Q_PROPERTY(QVariantList stops READ stops NOTIFY stopsChanged)
    Q_PROPERTY(int maxStops READ maxStops CONSTANT)
    // dl92: route split by segments (a list of coordinates for each segment)
    Q_PROPERTY(QVariantList legPaths READ legPaths NOTIFY routeChanged)
    Q_PROPERTY(bool rerouting   READ rerouting   NOTIFY reroutingChanged)
    Q_PROPERTY(bool loading     READ loading     NOTIFY loadingChanged)

    // Istruzione corrente
    Q_PROPERTY(QString instruction      READ instruction      NOTIFY stepChanged)
    Q_PROPERTY(QString maneuverType     READ maneuverType     NOTIFY stepChanged)
    Q_PROPERTY(QString maneuverModifier READ maneuverModifier NOTIFY stepChanged)
    Q_PROPERTY(QString nextStreet       READ nextStreet       NOTIFY stepChanged)
    Q_PROPERTY(double  distanceToManeuver READ distanceToManeuver NOTIFY progressChanged)
    // Maneuvers after the current one, for the expandable banner
    Q_PROPERTY(QVariantList upcomingManeuvers READ upcomingManeuvers NOTIFY maneuverChanged)
    // Lanes to show now (empty if not needed / maneuver still far away)
    Q_PROPERTY(QVariantList laneGuidance READ laneGuidance NOTIFY progressChanged)

    // Position snapped to the road (snap onto the route) and heading
    // of the road at that point: much more stable than the raw GPS data.
    Q_PROPERTY(QGeoCoordinate snappedPosition READ snappedPosition NOTIFY snapChanged)
    Q_PROPERTY(double         routeBearing    READ routeBearing    NOTIFY snapChanged)
    Q_PROPERTY(bool           snapped         READ snapped         NOTIFY snapChanged)

    // Riepilogo viaggio
    Q_PROPERTY(double  remainingDistance READ remainingDistance NOTIFY progressChanged)
    Q_PROPERTY(int     remainingDuration READ remainingDuration NOTIFY progressChanged)
    Q_PROPERTY(QString arrivalTime       READ arrivalTime       NOTIFY progressChanged)
    Q_PROPERTY(double  progress          READ progress          NOTIFY progressChanged)
    Q_PROPERTY(int     speedLimit        READ speedLimit        NOTIFY progressChanged)


public:
    explicit NavigationManager(QObject *parent = nullptr);
    ~NavigationManager() override;

    QString token() const { return m_token; }
    void setToken(const QString &t);
    bool avoidTolls()   const { return m_avoidTolls; }
    bool avoidFerries() const { return m_avoidFerries; }
    void setAvoidTolls(bool on);
    void setAvoidFerries(bool on);

    QVariantList routeCoordinates() const { return m_routeCoords; }
    QVariantList trafficSegments()  const { return m_trafficSegments; }
    QVariantList trafficFractions() const { return m_trafficFrac; }
    QVariantList routeDisplayCoordinates()    const { return m_routeDisplay; }
    QVariantList altRouteDisplayCoordinates() const { return m_altRouteDisplay; }
    bool hasRoute() const { return !m_routeCoords.isEmpty(); }
    QGeoCoordinate destination() const { return m_destination; }
    int waypointCount() const { return int(m_waypoints.size()); }
    QVariantList waypoints() const { QVariantList l; for (const auto &w : m_waypoints) l.append(QVariant::fromValue(w)); return l; }
    QString destinationName() const { return m_destName; }
    QVariantList stops() const;
    int maxStops() const { return 3; }   // destination + at most 2 stops
    QVariantList legPaths() const { return m_legPaths; }

    bool hasAltRoute() const { return !m_altRouteCoords.isEmpty(); }
    QVariantList altRouteCoordinates() const { return m_altRouteCoords; }
    int altRouteDuration() const { return m_altRouteDuration; }
    QGeoCoordinate altRouteMidpoint() const { return m_altRouteMidpoint; }
    QGeoCoordinate routeMidpoint() const { return m_routeMidpoint; }

    bool navigating() const { return m_navigating; }
    bool rerouting()  const { return m_rerouting; }
    bool loading()    const { return m_loading; }

    QString instruction()      const { return m_instruction; }
    QString maneuverType()     const { return m_maneuverType; }
    QString maneuverModifier() const { return m_maneuverModifier; }
    QString nextStreet()       const { return m_nextStreet; }
    double  distanceToManeuver() const { return m_distToManeuver; }

    double  remainingDistance() const { return m_remainingDistance; }
    int     remainingDuration() const { return m_remainingDuration; }
    QString arrivalTime()       const { return m_arrivalTime; }
    double  progress()          const { return m_progress; }
    int     speedLimit()        const { return m_speedLimit; }

    // ── API for QML ──────────────────────────────────────────────────
    /// Computes a route from the current position to a destination.
    Q_INVOKABLE void requestRoute(double lon, double lat,
                                  const QString &name = QStringLiteral("Destinazione"));
    /// Starts navigation (camera that follows, instructions active).
    /// Adds an intermediate stop to the current route and recomputes it.
    Q_INVOKABLE void addWaypoint(double lon, double lat, const QString &name = QString());
    /// dl92: replaces all the stops: [{lat, lon, name}], the last one is the destination.
    Q_INVOKABLE void setStops(const QVariantList &stops);
    Q_INVOKABLE void startNavigation();
    /// Stops navigation but keeps the route drawn.
    Q_INVOKABLE void stopNavigation();
    /// Cancella percorso e stato.
    Q_INVOKABLE void clearRoute();
    /// Updates the GPS position: all the advancement logic starts from here.
    Q_INVOKABLE void updatePosition(double lat, double lon,
                                    double bearing, double speedKmh);
    /// Recommended zoom based on speed (as speedToZoom did in TS).
    Q_INVOKABLE double zoomForSpeed(double speedKmh) const;
    /// Chooses which of the two routes (0 = main, 1 = alternative)
    /// becomes the active one. It simply swaps the two data sets, so that
    /// the other stays available as an alternative (you can tweak back
    /// and forth until you press "Start navigation").
    Q_INVOKABLE void selectRoute(int index);
    /// Only changes the displayed name of the destination (e.g. street reached after the computation).
    Q_INVOKABLE void setDestinationName(const QString &name);

    QVariantList upcomingManeuvers() const;

    QVariantList laneGuidance() const;
    QGeoCoordinate snappedPosition() const { return m_snapped; }
    double         routeBearing()    const { return m_routeBearing; }
    bool           snapped()         const { return m_isSnapped; }


signals:
    void tokenChanged();
    void routeOptionsChanged();
    void routeChanged();
    void destinationNameChanged();
    void waypointCountChanged();
    void stopsChanged();
    void navigatingChanged();
    void reroutingChanged();
    void loadingChanged();
    void stepChanged();
    void maneuverChanged();
    void progressChanged();
    void routeFailed(const QString &reason);
    void snapChanged();
    void arrived();

private slots:
    void onRouteReply(QNetworkReply *reply);

private:
    struct Step {
        QGeoCoordinate maneuverLoc;
        QString type;        // turn, merge, arrive, ...
        QString modifier;    // left, right, slight left, ...
        QString instruction; // ready text (banner or fallback)
        QString name;        // nome strada
        QString ref;         // road number (e.g. A4, SS36) for the badge on the map
        double  distance = 0;
        double  duration = 0;
        // Lanes (from the Mapbox banner): they concern the maneuver at the END of this step
        QVariantList lanes;       // [{directions:[...], active:bool, activeDirection:""}]
        double  laneShowDist = 0; // from how many meters before the maneuver to show them
    };

    bool doRequest(double lon, double lat, const QString &name, bool isReroute);
    void abortRouteRequest();
    void resetStepTracking();
    void recomputeStep(const QGeoCoordinate &pos);
    void recomputeProgress(const QGeoCoordinate &pos);
    void checkOffRoute(const QGeoCoordinate &pos);
    void buildTrafficSegments(const QVariantList &congestion);
    void setLoading(bool v);
    void setRerouting(bool v);

    static void parseLegData(const QJsonObject &leg, QList<Step> &steps,
                             QVariantList &congestion, QList<int> &speedLimits,
                             QList<double> &segDurations);
    void rebuildRouteIndex();
    static double haversine(const QGeoCoordinate &a, const QGeoCoordinate &b);
    static double distanceToPolyline(const QGeoCoordinate &pos,
                                     const QVariantList &coords, int fromIdx, int toIdx = -1);
    static QString congestionColor(const QVariant &c);
    static int     congestionWeight(const QVariant &c);

    void updateSnap(const QGeoCoordinate &pos);

    QGeoCoordinate m_snapped;
    double m_routeBearing     = 0;
    bool   m_isSnapped        = false;
    int    m_currentCoordIdx  = 0;   // nearest route vertex
    // Route index, computed once per route: distance and duration
    // cumulated up to each vertex (the duration comes from Mapbox's traffic, segment
    // by segment). So progress and arrival do not need to scan the whole
    // route at every GPS fix (10 per second).
    QList<double>  m_segDurations;       // seconds per segment (annotation "duration")
    QList<double>  m_altSegDurations;
    QVector<double> m_cumDist;           // meters from the start to each vertex
    QVector<double> m_cumDur;            // seconds from the start to each vertex (empty if missing)
    // How many consecutive samples are beyond the snapping threshold:
    // a single noisy GPS fix (typical in tight curves, where the
    // receiver lags a moment) must not make the arrow "leave"
    // the road only to come back by itself a few seconds later.
    int    m_offRouteStreak   = 0;

    QNetworkAccessManager *m_net = nullptr;
    // In-flight route request (only one at a time): old responses
    // (destinazione cambiata, navigazione annullata) vengono scartate.
    QNetworkReply *m_routeReply = nullptr;
    // Maneuver progress (before they were static variables inside recomputeStep and
    // survived from one route to another)
    QGeoCoordinate m_prevManLoc;
    double         m_prevManDist = 1e12;
    int            m_lastStepIdx = -1;
    // "Wrong way": it must last a while, a single noisy GPS sample is not enough
    qint64         m_wrongWaySinceMs = 0;
    QString m_token;

    QVariantList   m_routeCoords;       // QGeoCoordinate
    QVariantList   m_trafficFrac;       // { from, to, color }: colored segments as a 0..1 fraction of the route (widget bar)
    QVariantList   m_trafficSegments;   // { color, coordinates } (only the colored segments, simplified)
    QVariantList   m_routeDisplay;      // simplified routeCoords, for drawing
    QVariantList   m_altRouteDisplay;
    QVariantList   m_congestion;
    QList<int>     m_speedLimits;
    QList<Step>    m_steps;
    QGeoCoordinate m_destination;
    QList<QGeoCoordinate> m_waypoints;     // tappe intermedie, in ordine
    QStringList    m_waypointNames;        // dl92: name of each stop (same order)
    QVariantList   m_legPaths;             // dl92: coordinates per segment
    void rebuildLegPaths();
    QString        m_destName;
    QGeoCoordinate m_routeMidpoint;

    // Alternative route (only for the preview, before starting nav) —
    // complete data (not just geometry) so that selectRoute() can swap it
    // with the active route without having to redo the request.
    QVariantList   m_altRouteCoords;
    int            m_altRouteDuration = 0;
    QGeoCoordinate m_altRouteMidpoint;
    QList<Step>    m_altSteps;
    QVariantList   m_altCongestion;
    QList<int>     m_altSpeedLimits;
    double         m_altTotalDistance = 0;
    double         m_altTotalDuration = 0;

    QGeoCoordinate m_lastPos;
    bool m_avoidTolls   = false;
    bool m_avoidFerries = false;
    // Recomputes the preview route when the preferences change
    void recalcForOptionsChange();

    double m_lastBearing = 0;
    double m_lastSpeed   = 0;

    bool m_navigating = false;
    bool m_rerouting  = false;
    bool m_loading    = false;

    int     m_stepIdx = 0;
    QString m_instruction;
    QString m_maneuverType;
    QString m_maneuverModifier;
    QString m_nextStreet;
    double  m_distToManeuver = 0;

    double  m_totalDistance   = 0;
    double  m_totalDuration   = 0;
    double  m_remainingDistance = 0;
    int     m_remainingDuration = 0;
    QString m_arrivalTime;
    double  m_progress = 0;
    int     m_speedLimit = 0;

    QDateTime m_lastRerouteAt;
};
