#pragma once
#include <QObject>
#include <QHash>
#include <QSet>
#include <QStringList>
#include <QVariantMap>
#include <QElapsedTimer>
#include <QTimer>
#include <QDBusConnection>
#include <QDBusMessage>

class QProcess;

/**
 * MprisManager — the interface's "system player".
 *
 * All Linux players announce themselves on the D-Bus session bus with
 * standard MPRIS (org.mpris.MediaPlayer2.*). This object observes them
 * direttamente (niente servizi intermedi, niente polling HTTP) e offre a QML:
 *
 *   • which player is playing ("activeSource") with the rule
 *     "the last one that starts playing wins": when a player starts, the
 *     altri lettori MPRIS vengono messi in pausa;
 *   • title, artist, cover, duration and position of the active player
 *     (the position is interpolated locally and realigned every second);
 *   • the standard commands: play/pause, next, previous, seek,
 *     casuale e ripeti.
 *
 * Each player is recognized by its name on the bus and by the process that
 * owns it, and mapped to an interface "source":
 *   "ytmusic"   → mpv (with the mpv-mpris plugin) used by the YT Music service
 *   "spotify"   → spotifyd (Spotify Connect) or the Spotify client
 *   "bluetooth" → phone via AVRCP, exposed by mpris-proxy (BlueZ)
 *   "browser"   → Firefox / Chromium
 *   "other"     → qualsiasi altro lettore MPRIS
 * playerctld (which only mirrors another player) and the interface
 * itself are ignored.
 *
 * Track "hints" (setTrackHint): mpv receives a raw audio stream and
 * does not know artist and cover; the YT Music app provides them and they are used
 * ONLY if the title matches the one announced by the player, so an
 * old hint can never end up on the wrong track.
 */
class MprisManager : public QObject
{
    Q_OBJECT

    // ── Lettore attivo ──
    Q_PROPERTY(QString activeSource   READ activeSource   NOTIFY stateChanged)
    Q_PROPERTY(QString activeIdentity READ activeIdentity NOTIFY stateChanged)
    Q_PROPERTY(bool    hasActive      READ hasActive      NOTIFY stateChanged)
    Q_PROPERTY(QString title          READ title          NOTIFY stateChanged)
    Q_PROPERTY(QString artist         READ artist         NOTIFY stateChanged)
    Q_PROPERTY(QString album          READ album          NOTIFY stateChanged)
    Q_PROPERTY(QString artUrl         READ artUrl         NOTIFY stateChanged)
    Q_PROPERTY(qint64  lengthMs       READ lengthMs       NOTIFY stateChanged)
    Q_PROPERTY(bool    playing        READ playing        NOTIFY stateChanged)
    Q_PROPERTY(QString playbackStatus READ playbackStatus NOTIFY stateChanged)
    Q_PROPERTY(bool    shuffle        READ shuffle        NOTIFY stateChanged)
    Q_PROPERTY(QString loopStatus     READ loopStatus     NOTIFY stateChanged)   // "None" | "Track" | "Playlist"
    Q_PROPERTY(bool    hasShuffle     READ hasShuffle     NOTIFY stateChanged)
    Q_PROPERTY(bool    hasLoop        READ hasLoop        NOTIFY stateChanged)
    Q_PROPERTY(bool    canSeek        READ canSeek        NOTIFY stateChanged)
    Q_PROPERTY(bool    canGoNext      READ canGoNext      NOTIFY stateChanged)
    Q_PROPERTY(bool    canGoPrevious  READ canGoPrevious  NOTIFY stateChanged)

    // Position (updated 4 times per second while playing)
    Q_PROPERTY(qint64  positionMs READ positionMs NOTIFY positionChanged)
    Q_PROPERTY(double  progress   READ progress   NOTIFY positionChanged)        // 0..1

    // ── All the players ──
    // sources: sources currently on the bus (e.g. ["ytmusic","bluetooth"])
    Q_PROPERTY(QStringList sources READ sources NOTIFY playersChanged)
    // players: state of each source { title, artist, artUrl, playing, lengthMs,
    // positionMs, shuffle, loopStatus, canSeek, identity, service }
    Q_PROPERTY(QVariantMap players READ players NOTIFY playersChanged)

    // When a player starts, pause the other MPRIS players
    Q_PROPERTY(bool exclusive READ exclusive WRITE setExclusive NOTIFY exclusiveChanged)

public:
    explicit MprisManager(QObject *parent = nullptr);
    ~MprisManager() override;

    QString activeSource() const;
    QString activeIdentity() const;
    bool    hasActive() const { return !m_active.isEmpty(); }
    QString title() const;
    QString artist() const;
    QString album() const;
    QString artUrl() const;
    qint64  lengthMs() const;
    bool    playing() const;
    QString playbackStatus() const;
    bool    shuffle() const;
    QString loopStatus() const;
    bool    hasShuffle() const;
    bool    hasLoop() const;
    bool    canSeek() const;
    bool    canGoNext() const;
    bool    canGoPrevious() const;
    qint64  positionMs() const;
    double  progress() const;
    QStringList sources() const;
    QVariantMap players() const;
    bool exclusive() const { return m_exclusive; }
    void setExclusive(bool on);

    // ── Commands on the active player ──
    Q_INVOKABLE void playPause();
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void seekTo(qint64 ms);
    Q_INVOKABLE void seekToFraction(double f);
    Q_INVOKABLE void setShuffle(bool on);
    Q_INVOKABLE void setLoopStatus(const QString &status);
    Q_INVOKABLE void cycleLoopStatus();              // None → Playlist → Track → None

    // ── Commands per source ──
    Q_INVOKABLE bool hasSource(const QString &source) const;
    Q_INVOKABLE bool isPlaying(const QString &source) const;
    Q_INVOKABLE void playPauseSource(const QString &source);
    Q_INVOKABLE void playSource(const QString &source);
    Q_INVOKABLE void pauseSource(const QString &source);
    Q_INVOKABLE void nextSource(const QString &source);
    Q_INVOKABLE void previousSource(const QString &source);
    Q_INVOKABLE void seekSourceToFraction(const QString &source, double f);
    Q_INVOKABLE void setSourceShuffle(const QString &source, bool on);
    Q_INVOKABLE void setSourceLoopStatus(const QString &source, const QString &status);
    Q_INVOKABLE void pauseAll();
    Q_INVOKABLE void pauseAllExcept(const QString &source);
    // Makes a source active (e.g. just chosen by the user in the interface)
    Q_INVOKABLE void activate(const QString &source);

    // Artist/cover provided by the app for the track "title" of that source
    Q_INVOKABLE void setTrackHint(const QString &source, const QString &title,
                                  const QString &artist, const QString &artUrl);
    Q_INVOKABLE void clearTrackHint(const QString &source);

    // Plays a sound effect (program + arguments, e.g. mpv) lowering
    // the music of the players that are playing to "duckLevel" (0..1) and raising it again
    // when the effect ends. Several effects together: it rises after the last one.
    Q_INVOKABLE void playEffect(const QString &program, const QStringList &args, double duckLevel = 0.25);

    // Starts mpris-proxy (BlueZ) if it is not already running: makes the phone
    // connected over Bluetooth an MPRIS player like the others
    Q_INVOKABLE void ensureBluetoothProxy();

signals:
    void stateChanged();
    void positionChanged();
    void playersChanged();
    void exclusiveChanged();
    // A player has switched to "Playing" (the last one to start wins)
    void sourceStartedPlaying(const QString &source);
    // The active player has changed track
    void trackChanged();

private slots:
    void onNameOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);
    void onPropertiesChanged(const QDBusMessage &msg);
    void onSeeked(const QDBusMessage &msg);
    void onTick();
    void onPoll();

private:
    struct Player {
        QString service;            // bus name (org.mpris.MediaPlayer2.xxx)
        QString owner;              // nome unico (:1.42)
        QString source;             // ytmusic / spotify / bluetooth / browser / other
        QString identity;
        QString status = QStringLiteral("Stopped");
        QVariantMap meta;
        qint64  posUs = 0;
        QElapsedTimer posClock;
        double  rate = 1.0;
        bool    shuffle = false,  hasShuffle = false;
        QString loop = QStringLiteral("None");
        bool    hasLoop = false;
        bool    canSeek = false, canNext = false, canPrev = false;
        bool    canControl = true;
        double  volume = 1.0;
        bool    hasVolume = false;
        qint64  startedAt = 0;      // when it switched to Playing (ms)
        bool    ready = false;      // riconosciuto e letto
    };
    struct Hint { QString title, artist, artUrl; };

    void addPlayer(const QString &service);
    void removePlayer(const QString &service);
    void classify(const QString &service);
    void fetchAll(const QString &service);
    void applyProps(Player &p, const QString &iface, const QVariantMap &props, bool initial);
    void setActive(const QString &service);
    void chooseActive();
    void startedPlaying(Player &p);

    const Player *activePlayer() const;
    Player *activePlayer();
    const Player *playerFor(const QString &source) const;
    QString serviceFor(const QString &source) const;

    qint64 currentPosUs(const Player &p) const;
    qint64 lengthUs(const Player &p) const;
    QString metaTitle(const Player &p) const;
    QString effTitle(const Player &p) const;
    QString effArtist(const Player &p) const;
    QString effArtUrl(const Player &p) const;
    const Hint *hintFor(const Player &p) const;
    QVariantMap snapshot(const Player &p) const;

    void callPlayer(const QString &service, const QString &method, const QVariantList &args = {});
    void sendPlayWithRetry(const QString &service);
    void setPlayerProperty(const QString &service, const QString &name, const QVariant &value);
    void seekPlayer(Player &p, qint64 targetUs);

    static QVariantMap demarshalMap(const QVariant &v);
    static QString classifyName(const QString &service, const QString &comm);

    QDBusConnection m_bus;
    QHash<QString, Player> m_players;              // service → lettore
    QHash<QString, QStringList> m_ownerServices;   // owner → services
    QHash<QString, Hint> m_hints;                  // source → suggerimento
    QString m_active;                              // service attivo
    bool m_exclusive = true;
    QTimer m_tick;                                 // 250 ms: posizione interpolata
    QTimer m_poll;                                 // 1 s: realigns the position
    QProcess *m_btProxy = nullptr;
    // Lowering the music during sound effects
    int m_effectsRunning = 0;
    QSet<qint64> m_effectPids;                     // effect processes: they are not "players"
    QHash<QString, double> m_duckedVolumes;        // service → volume originale
    void duck(double level);
    void unduck();
};
