#include "MprisManager.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDBusArgument>
#include <QDBusConnectionInterface>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QDebug>
#include <QFile>
#include <QProcess>
#include <QRegularExpression>

namespace {
const QString kPrefix      = QStringLiteral("org.mpris.MediaPlayer2.");
const QString kPath        = QStringLiteral("/org/mpris/MediaPlayer2");
const QString kRootIface   = QStringLiteral("org.mpris.MediaPlayer2");
const QString kPlayerIface = QStringLiteral("org.mpris.MediaPlayer2.Player");
const QString kPropsIface  = QStringLiteral("org.freedesktop.DBus.Properties");
const QString kDBusService = QStringLiteral("org.freedesktop.DBus");
const QString kDBusPath    = QStringLiteral("/org/freedesktop/DBus");

qint64 nowMs() { return QDateTime::currentMSecsSinceEpoch(); }

QString norm(const QString &s)
{
    return s.simplified().toLower();
}
} // namespace

// ═══════════════════════════ Costruzione ═══════════════════════════

MprisManager::MprisManager(QObject *parent)
    : QObject(parent)
    , m_bus(QDBusConnection::sessionBus())
{
    m_tick.setInterval(250);
    connect(&m_tick, &QTimer::timeout, this, &MprisManager::onTick);
    m_poll.setInterval(1000);
    connect(&m_poll, &QTimer::timeout, this, &MprisManager::onPoll);

    if (!m_bus.isConnected()) {
        qWarning() << "[MPRIS] D-Bus session bus not available:" << m_bus.lastError().message();
        return;
    }

    // Players that appear / disappear
    m_bus.connect(kDBusService, kDBusPath, kDBusService, QStringLiteral("NameOwnerChanged"),
                  this, SLOT(onNameOwnerChanged(QString,QString,QString)));
    // State changes of ANY player (the sender says which)
    m_bus.connect(QString(), kPath, kPropsIface, QStringLiteral("PropertiesChanged"),
                  this, SLOT(onPropertiesChanged(QDBusMessage)));
    m_bus.connect(QString(), kPath, kPlayerIface, QStringLiteral("Seeked"),
                  this, SLOT(onSeeked(QDBusMessage)));

    // Players already present at startup
    const QDBusMessage list = QDBusMessage::createMethodCall(kDBusService, kDBusPath, kDBusService,
                                                             QStringLiteral("ListNames"));
    auto *w = new QDBusPendingCallWatcher(m_bus.asyncCall(list), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<QStringList> r = *w;
        w->deleteLater();
        if (r.isError()) return;
        const QStringList names = r.value();
        for (const QString &n : names)
            if (n.startsWith(kPrefix)) addPlayer(n);
    });

    m_tick.start();
    m_poll.start();
}

MprisManager::~MprisManager()
{
    if (m_btProxy && m_btProxy->state() != QProcess::NotRunning) {
        m_btProxy->terminate();
        m_btProxy->waitForFinished(1000);
    }
}

// ═══════════════════════════ Players on the bus ═══════════════════════════

void MprisManager::onNameOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner)
{
    if (!name.startsWith(kPrefix)) return;
    if (!oldOwner.isEmpty()) removePlayer(name);
    if (!newOwner.isEmpty()) addPlayer(name);
}

void MprisManager::addPlayer(const QString &service)
{
    if (m_players.contains(service)) return;
    Player p;
    p.service = service;
    p.posClock.start();
    m_players.insert(service, p);

    // 1) owner (unique name): needed to know who the signals come from
    const QDBusMessage m = QDBusMessage::createMethodCall(kDBusService, kDBusPath, kDBusService,
                                                          QStringLiteral("GetNameOwner"));
    auto *w = new QDBusPendingCallWatcher(m_bus.asyncCall(QDBusMessage(m) << service), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, service](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<QString> r = *w;
        w->deleteLater();
        auto it = m_players.find(service);
        if (it == m_players.end() || r.isError()) return;
        it->owner = r.value();
        m_ownerServices[it->owner].append(service);
        classify(service);
    });
}

void MprisManager::removePlayer(const QString &service)
{
    auto it = m_players.find(service);
    if (it == m_players.end()) return;
    const bool wasReady = it->ready;
    if (!it->owner.isEmpty()) {
        QStringList &l = m_ownerServices[it->owner];
        l.removeAll(service);
        if (l.isEmpty()) m_ownerServices.remove(it->owner);
    }
    m_players.erase(it);
    if (m_active == service) {
        m_active.clear();
        chooseActive();
        emit stateChanged();
        emit positionChanged();
    }
    if (wasReady) emit playersChanged();
}

// 2) processo proprietario → sorgente dell'interfaccia
void MprisManager::classify(const QString &service)
{
    auto it = m_players.find(service);
    if (it == m_players.end()) return;
    const QDBusMessage m = QDBusMessage::createMethodCall(kDBusService, kDBusPath, kDBusService,
                                                          QStringLiteral("GetConnectionUnixProcessID"));
    auto *w = new QDBusPendingCallWatcher(m_bus.asyncCall(QDBusMessage(m) << it->owner), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, service](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<uint> r = *w;
        w->deleteLater();
        auto it = m_players.find(service);
        if (it == m_players.end()) return;

        QString comm;
        if (!r.isError()) {
            const qint64 pid = r.value();
            if (pid == QCoreApplication::applicationPid() || m_effectPids.contains(pid)) {   // interfaccia o effetto sonoro
                removePlayer(service);
                return;
            }
            QFile f(QStringLiteral("/proc/%1/comm").arg(pid));
            if (f.open(QIODevice::ReadOnly)) comm = QString::fromUtf8(f.readAll()).trimmed();
        }
        const QString src = classifyName(service, comm);
        if (src.isEmpty()) { removePlayer(service); return; }   // to ignore (playerctld…)
        it->source = src;
        fetchAll(service);
    });
}

QString MprisManager::classifyName(const QString &service, const QString &comm)
{
    const QString n = service.mid(kPrefix.size()).toLower();
    const QString c = comm.toLower();
    if (n.startsWith(QLatin1String("playerctld"))) return QString();    // mirror of another player
    if (c == QLatin1String("mpris-proxy"))           return QStringLiteral("bluetooth");
    if (n.startsWith(QLatin1String("mpv")))           return QStringLiteral("ytmusic");
    if (n.startsWith(QLatin1String("spotifyd")) || n.startsWith(QLatin1String("spotify"))
        || c == QLatin1String("spotifyd") || c == QLatin1String("spotify"))
        return QStringLiteral("spotify");
    static const char *browsers[] = { "firefox", "chromium", "chrome", "brave", "vivaldi", "opera", "epiphany" };
    for (const char *b : browsers)
        if (n.startsWith(QLatin1String(b)) || c.startsWith(QLatin1String(b))) return QStringLiteral("browser");
    return QStringLiteral("other");
}

// 3) full reading of the properties
void MprisManager::fetchAll(const QString &service)
{
    for (const QString &iface : { kRootIface, kPlayerIface }) {
        QDBusMessage m = QDBusMessage::createMethodCall(service, kPath, kPropsIface, QStringLiteral("GetAll"));
        m << iface;
        auto *w = new QDBusPendingCallWatcher(m_bus.asyncCall(m, 3000), this);
        connect(w, &QDBusPendingCallWatcher::finished, this, [this, service, iface](QDBusPendingCallWatcher *w) {
            QDBusPendingReply<QVariantMap> r = *w;
            w->deleteLater();
            auto it = m_players.find(service);
            if (it == m_players.end()) return;
            if (r.isError()) {
                if (iface == kPlayerIface) qWarning() << "[MPRIS]" << service << "GetAll fallito:" << r.error().message();
                return;
            }
            applyProps(*it, iface, r.value(), true);
            if (iface == kPlayerIface && !it->ready) {
                it->ready = true;
                qInfo() << "[MPRIS] lettore" << it->source << "→" << service;
                if (m_active.isEmpty() || it->status == QLatin1String("Playing")) chooseActive();
                emit playersChanged();
                emit stateChanged();
            }
        });
    }
}

// ═══════════════════════════ Player signals ═══════════════════════════

void MprisManager::onPropertiesChanged(const QDBusMessage &msg)
{
    const QStringList services = m_ownerServices.value(msg.service());
    if (services.isEmpty()) return;
    const QList<QVariant> args = msg.arguments();
    if (args.size() < 2) return;
    const QString iface = args.at(0).toString();
    if (iface != kPlayerIface && iface != kRootIface) return;
    const QVariantMap changed = demarshalMap(args.at(1));
    const QStringList invalidated = args.size() > 2 ? args.at(2).toStringList() : QStringList();

    for (const QString &svc : services) {
        auto it = m_players.find(svc);
        if (it == m_players.end()) continue;
        applyProps(*it, iface, changed, false);
        if (!invalidated.isEmpty()) fetchAll(svc);
    }
}

void MprisManager::onSeeked(const QDBusMessage &msg)
{
    const QStringList services = m_ownerServices.value(msg.service());
    if (services.isEmpty() || msg.arguments().isEmpty()) return;
    const qint64 us = msg.arguments().at(0).toLongLong();
    for (const QString &svc : services) {
        auto it = m_players.find(svc);
        if (it == m_players.end()) continue;
        it->posUs = us;
        it->posClock.restart();
        if (svc == m_active) emit positionChanged();
    }
}

void MprisManager::applyProps(Player &p, const QString &iface, const QVariantMap &props, bool initial)
{
    if (iface == kRootIface) {
        if (props.contains(QStringLiteral("Identity"))) {
            p.identity = props.value(QStringLiteral("Identity")).toString();
            if (p.service == m_active) emit stateChanged();
        }
        return;
    }

    bool changed = false, newTrack = false, becamePlaying = false;

    if (props.contains(QStringLiteral("Metadata"))) {
        const QVariantMap meta = demarshalMap(props.value(QStringLiteral("Metadata")));
        const QVariant oldId = p.meta.value(QStringLiteral("mpris:trackid"));
        const QString oldTitle = metaTitle(p);
        p.meta = meta;
        if (meta.value(QStringLiteral("mpris:trackid")) != oldId || metaTitle(p) != oldTitle) {
            newTrack = true;
            if (!props.contains(QStringLiteral("Position"))) { p.posUs = 0; p.posClock.restart(); }
        }
        changed = true;
    }
    if (props.contains(QStringLiteral("Position"))) {
        p.posUs = props.value(QStringLiteral("Position")).toLongLong();
        p.posClock.restart();
    }
    if (props.contains(QStringLiteral("Rate"))) {
        const double r = props.value(QStringLiteral("Rate")).toDouble();
        p.posUs = currentPosUs(p); p.posClock.restart();
        p.rate = r > 0 ? r : 1.0;
    }
    if (props.contains(QStringLiteral("PlaybackStatus"))) {
        const QString st = props.value(QStringLiteral("PlaybackStatus")).toString();
        if (st != p.status) {
            p.posUs = currentPosUs(p);       // freezes / restarts from where it was
            p.posClock.restart();
            becamePlaying = (st == QLatin1String("Playing"));
            p.status = st;
            changed = true;
        }
    }
    if (props.contains(QStringLiteral("Shuffle"))) {
        p.shuffle = props.value(QStringLiteral("Shuffle")).toBool(); p.hasShuffle = true; changed = true;
    }
    if (props.contains(QStringLiteral("LoopStatus"))) {
        p.loop = props.value(QStringLiteral("LoopStatus")).toString(); p.hasLoop = true; changed = true;
    }
    if (props.contains(QStringLiteral("Volume"))) {
        p.volume = props.value(QStringLiteral("Volume")).toDouble(); p.hasVolume = true;
    }
    if (props.contains(QStringLiteral("CanSeek")))       { p.canSeek = props.value(QStringLiteral("CanSeek")).toBool(); changed = true; }
    if (props.contains(QStringLiteral("CanGoNext")))     { p.canNext = props.value(QStringLiteral("CanGoNext")).toBool(); changed = true; }
    if (props.contains(QStringLiteral("CanGoPrevious"))) { p.canPrev = props.value(QStringLiteral("CanGoPrevious")).toBool(); changed = true; }
    if (props.contains(QStringLiteral("CanControl")))    { p.canControl = props.value(QStringLiteral("CanControl")).toBool(); changed = true; }

    if (!p.ready && initial) {
        // First reading: a player that is already playing counts as "started now"
        if (p.status == QLatin1String("Playing")) p.startedAt = nowMs();
        return;
    }
    if (becamePlaying) startedPlaying(p);
    if (!changed) return;

    if (p.service == m_active) {
        emit stateChanged();
        emit positionChanged();
        if (newTrack) emit trackChanged();
    }
    emit playersChanged();
}

// A player has just started: it becomes active, the others are paused
void MprisManager::startedPlaying(Player &p)
{
    p.startedAt = nowMs();
    if (!p.ready) return;
    const QString svc = p.service, src = p.source;
    if (m_exclusive) {
        for (auto it = m_players.begin(); it != m_players.end(); ++it) {
            if (it.key() == svc || !it->ready) continue;
            // NEVER pause another player of the SAME source
            // (e.g. two "bluetooth" MPRIS registrations for the same
            // phone — it happens with mpris-proxy under certain
            // reconnection/startup race conditions): they are the same
            // physical device behind the scenes, so "pausing it" really
            // sends an AVRCP pause command to the phone that is
            // playing — it looked like playback paused
            // by itself after a couple of seconds.
            if (it->source == src) continue;
            if (it->status == QLatin1String("Playing")) callPlayer(it.key(), QStringLiteral("Pause"));
        }
    }
    setActive(svc);
    emit sourceStartedPlaying(src);
}

void MprisManager::setActive(const QString &service)
{
    if (m_active == service) return;
    m_active = service;
    emit stateChanged();
    emit positionChanged();
    emit trackChanged();
}

// No active one (or the active one is gone): the most recent that is playing, otherwise the most recent
void MprisManager::chooseActive()
{
    QString best;
    qint64 bestT = -1;
    bool bestPlaying = false;
    for (auto it = m_players.cbegin(); it != m_players.cend(); ++it) {
        if (!it->ready) continue;
        const bool pl = it->status == QLatin1String("Playing");
        if ((pl && !bestPlaying) || (pl == bestPlaying && it->startedAt > bestT)) {
            best = it.key(); bestT = it->startedAt; bestPlaying = pl;
        }
    }
    if (!best.isEmpty()) setActive(best);
}

// ═══════════════════════════ Posizione ═══════════════════════════

void MprisManager::onTick()
{
    const Player *p = activePlayer();
    if (p && p->status == QLatin1String("Playing")) emit positionChanged();
}

// Realigns the active player's position (Position is not notified)
void MprisManager::onPoll()
{
    const Player *p = activePlayer();
    if (!p || p->status != QLatin1String("Playing")) return;
    const QString svc = p->service;
    QDBusMessage m = QDBusMessage::createMethodCall(svc, kPath, kPropsIface, QStringLiteral("Get"));
    m << kPlayerIface << QStringLiteral("Position");
    auto *w = new QDBusPendingCallWatcher(m_bus.asyncCall(m, 1500), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, svc](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<QDBusVariant> r = *w;
        w->deleteLater();
        auto it = m_players.find(svc);
        if (it == m_players.end() || r.isError()) return;
        it->posUs = r.value().variant().toLongLong();
        it->posClock.restart();
        if (svc == m_active) emit positionChanged();
    });
}

qint64 MprisManager::currentPosUs(const Player &p) const
{
    qint64 us = p.posUs;
    if (p.status == QLatin1String("Playing") && p.posClock.isValid())
        us += qint64(p.posClock.elapsed() * 1000.0 * p.rate);
    const qint64 len = lengthUs(p);
    if (len > 0 && us > len) us = len;
    return qMax<qint64>(0, us);
}

qint64 MprisManager::lengthUs(const Player &p) const
{
    return p.meta.value(QStringLiteral("mpris:length")).toLongLong();
}

// ═══════════════════════════ Metadati ═══════════════════════════

QString MprisManager::metaTitle(const Player &p) const
{
    QString t = p.meta.value(QStringLiteral("xesam:title")).toString().trimmed();
    // mpv without a title announces the stream address: it is not a title
    if (t.startsWith(QLatin1String("http")) || t == QLatin1String("videoplayback")) t.clear();
    return t;
}

const MprisManager::Hint *MprisManager::hintFor(const Player &p) const
{
    auto it = m_hints.constFind(p.source);
    if (it == m_hints.constEnd()) return nullptr;
    const QString t = metaTitle(p);
    if (t.isEmpty() || norm(t) != norm(it->title)) return nullptr;   // only on the right track
    return &it.value();
}

QString MprisManager::effTitle(const Player &p) const
{
    return metaTitle(p);
}

QString MprisManager::effArtist(const Player &p) const
{
    if (const Hint *h = hintFor(p); h && !h->artist.isEmpty()) return h->artist;
    const QVariant a = p.meta.value(QStringLiteral("xesam:artist"));
    QStringList list = a.toStringList();
    if (list.isEmpty() && a.canConvert<QDBusArgument>()) list = qdbus_cast<QStringList>(a.value<QDBusArgument>());
    if (list.isEmpty() && !a.toString().isEmpty()) list << a.toString();
    return list.join(QStringLiteral(", "));
}

QString MprisManager::effArtUrl(const Player &p) const
{
    if (const Hint *h = hintFor(p); h && !h->artUrl.isEmpty()) return h->artUrl;
    return p.meta.value(QStringLiteral("mpris:artUrl")).toString();
}

void MprisManager::setTrackHint(const QString &source, const QString &title,
                                const QString &artist, const QString &artUrl)
{
    Hint h{ title.trimmed(), artist.trimmed(), artUrl.trimmed() };
    auto it = m_hints.constFind(source);
    if (it != m_hints.constEnd() && it->title == h.title && it->artist == h.artist && it->artUrl == h.artUrl)
        return;
    m_hints.insert(source, h);
    if (const Player *p = activePlayer(); p && p->source == source) emit stateChanged();
    emit playersChanged();
}

void MprisManager::clearTrackHint(const QString &source)
{
    if (m_hints.remove(source)) { emit stateChanged(); emit playersChanged(); }
}

QVariantMap MprisManager::demarshalMap(const QVariant &v)
{
    if (v.canConvert<QDBusArgument>()) return qdbus_cast<QVariantMap>(v.value<QDBusArgument>());
    if (v.canConvert<QDBusVariant>())  return demarshalMap(v.value<QDBusVariant>().variant());
    return v.toMap();
}

// ═══════════════════════════ Properties for QML ═══════════════════════════

const MprisManager::Player *MprisManager::activePlayer() const
{
    auto it = m_players.constFind(m_active);
    return (it != m_players.constEnd() && it->ready) ? &it.value() : nullptr;
}

MprisManager::Player *MprisManager::activePlayer()
{
    auto it = m_players.find(m_active);
    return (it != m_players.end() && it->ready) ? &it.value() : nullptr;
}

QString MprisManager::serviceFor(const QString &source) const
{
    // Several players of the same source: the active one counts, then the most recent
    if (const Player *a = activePlayer(); a && a->source == source) return a->service;
    QString best; qint64 t = -1;
    for (auto it = m_players.cbegin(); it != m_players.cend(); ++it)
        if (it->ready && it->source == source && it->startedAt > t) { best = it.key(); t = it->startedAt; }
    return best;
}

const MprisManager::Player *MprisManager::playerFor(const QString &source) const
{
    const QString svc = serviceFor(source);
    auto it = m_players.constFind(svc);
    return it != m_players.constEnd() ? &it.value() : nullptr;
}

#define ACTIVE_OR(def) const Player *p = activePlayer(); if (!p) return def;
QString MprisManager::activeSource() const   { ACTIVE_OR(QString()) return p->source; }
QString MprisManager::activeIdentity() const { ACTIVE_OR(QString()) return p->identity; }
QString MprisManager::title() const          { ACTIVE_OR(QString()) return effTitle(*p); }
QString MprisManager::artist() const         { ACTIVE_OR(QString()) return effArtist(*p); }
QString MprisManager::album() const          { ACTIVE_OR(QString()) return p->meta.value(QStringLiteral("xesam:album")).toString(); }
QString MprisManager::artUrl() const         { ACTIVE_OR(QString()) return effArtUrl(*p); }
qint64  MprisManager::lengthMs() const       { ACTIVE_OR(0) return lengthUs(*p) / 1000; }
bool    MprisManager::playing() const        { ACTIVE_OR(false) return p->status == QLatin1String("Playing"); }
QString MprisManager::playbackStatus() const { ACTIVE_OR(QStringLiteral("Stopped")) return p->status; }
bool    MprisManager::shuffle() const        { ACTIVE_OR(false) return p->shuffle; }
QString MprisManager::loopStatus() const     { ACTIVE_OR(QStringLiteral("None")) return p->loop; }
bool    MprisManager::hasShuffle() const     { ACTIVE_OR(false) return p->hasShuffle; }
bool    MprisManager::hasLoop() const        { ACTIVE_OR(false) return p->hasLoop; }
bool    MprisManager::canSeek() const        { ACTIVE_OR(false) return p->canSeek && lengthUs(*p) > 0; }
bool    MprisManager::canGoNext() const      { ACTIVE_OR(false) return p->canNext; }
bool    MprisManager::canGoPrevious() const  { ACTIVE_OR(false) return p->canPrev; }
qint64  MprisManager::positionMs() const     { ACTIVE_OR(0) return currentPosUs(*p) / 1000; }
double  MprisManager::progress() const
{
    ACTIVE_OR(0.0)
    const qint64 len = lengthUs(*p);
    return len > 0 ? qBound(0.0, double(currentPosUs(*p)) / double(len), 1.0) : 0.0;
}
#undef ACTIVE_OR

QStringList MprisManager::sources() const
{
    QStringList out;
    for (auto it = m_players.cbegin(); it != m_players.cend(); ++it)
        if (it->ready && !out.contains(it->source)) out << it->source;
    return out;
}

QVariantMap MprisManager::snapshot(const Player &p) const
{
    return {
        { QStringLiteral("service"),    p.service },
        { QStringLiteral("identity"),   p.identity },
        { QStringLiteral("title"),      effTitle(p) },
        { QStringLiteral("artist"),     effArtist(p) },
        { QStringLiteral("album"),      p.meta.value(QStringLiteral("xesam:album")).toString() },
        { QStringLiteral("artUrl"),     effArtUrl(p) },
        { QStringLiteral("playing"),    p.status == QLatin1String("Playing") },
        { QStringLiteral("status"),     p.status },
        { QStringLiteral("lengthMs"),   lengthUs(p) / 1000 },
        { QStringLiteral("positionMs"), currentPosUs(p) / 1000 },
        { QStringLiteral("shuffle"),    p.shuffle },
        { QStringLiteral("loopStatus"), p.loop },
        { QStringLiteral("hasShuffle"), p.hasShuffle },
        { QStringLiteral("hasLoop"),    p.hasLoop },
        { QStringLiteral("canSeek"),    p.canSeek },
        { QStringLiteral("canGoNext"),  p.canNext },
        { QStringLiteral("canGoPrevious"), p.canPrev },
    };
}

QVariantMap MprisManager::players() const
{
    QVariantMap out;
    for (const QString &src : sources())
        if (const Player *p = playerFor(src)) out.insert(src, snapshot(*p));
    return out;
}

bool MprisManager::hasSource(const QString &source) const { return !serviceFor(source).isEmpty(); }

bool MprisManager::isPlaying(const QString &source) const
{
    for (auto it = m_players.cbegin(); it != m_players.cend(); ++it)
        if (it->ready && it->source == source && it->status == QLatin1String("Playing")) return true;
    return false;
}

void MprisManager::setExclusive(bool on)
{
    if (m_exclusive == on) return;
    m_exclusive = on;
    emit exclusiveChanged();
}

// ═══════════════════════════ Comandi ═══════════════════════════

void MprisManager::callPlayer(const QString &service, const QString &method, const QVariantList &args)
{
    if (service.isEmpty()) return;
    QDBusMessage m = QDBusMessage::createMethodCall(service, kPath, kPlayerIface, method);
    m.setArguments(args);
    auto *w = new QDBusPendingCallWatcher(m_bus.asyncCall(m, 3000), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [service, method](QDBusPendingCallWatcher *w) {
        if (w->isError()) qWarning() << "[MPRIS]" << service << method << "fallito:" << w->error().message();
        w->deleteLater();
    });
}

void MprisManager::setPlayerProperty(const QString &service, const QString &name, const QVariant &value)
{
    if (service.isEmpty()) return;
    QDBusMessage m = QDBusMessage::createMethodCall(service, kPath, kPropsIface, QStringLiteral("Set"));
    m << kPlayerIface << name << QVariant::fromValue(QDBusVariant(value));
    auto *w = new QDBusPendingCallWatcher(m_bus.asyncCall(m, 3000), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [service, name](QDBusPendingCallWatcher *w) {
        if (w->isError()) qWarning() << "[MPRIS]" << service << "Set" << name << "fallito:" << w->error().message();
        w->deleteLater();
    });
}

void MprisManager::seekPlayer(Player &p, qint64 targetUs)
{
    const qint64 len = lengthUs(p);
    if (len > 0) targetUs = qBound<qint64>(0, targetUs, len - 1000);
    const QString tid = p.meta.value(QStringLiteral("mpris:trackid")).value<QDBusObjectPath>().path();
    if (!tid.isEmpty() && tid != QLatin1String("/org/mpris/MediaPlayer2/TrackList/NoTrack"))
        callPlayer(p.service, QStringLiteral("SetPosition"),
                   { QVariant::fromValue(QDBusObjectPath(tid)), QVariant::fromValue(qlonglong(targetUs)) });
    else
        callPlayer(p.service, QStringLiteral("Seek"),
                   { QVariant::fromValue(qlonglong(targetUs - currentPosUs(p))) });
    // Immediate update: the confirmation (Seeked / Position) arrives right after
    p.posUs = targetUs;
    p.posClock.restart();
    if (p.service == m_active) emit positionChanged();
}

void MprisManager::playPause()
{
    if (const Player *p = activePlayer()) playPauseSource(p->source);
}
void MprisManager::play()     { if (const Player *p = activePlayer()) callPlayer(p->service, QStringLiteral("Play")); }
void MprisManager::pause()    { if (const Player *p = activePlayer()) callPlayer(p->service, QStringLiteral("Pause")); }
void MprisManager::next()     { if (const Player *p = activePlayer()) callPlayer(p->service, QStringLiteral("Next")); }
void MprisManager::previous() { if (const Player *p = activePlayer()) callPlayer(p->service, QStringLiteral("Previous")); }

void MprisManager::seekTo(qint64 ms)
{
    if (Player *p = activePlayer()) seekPlayer(*p, ms * 1000);
}
void MprisManager::seekToFraction(double f)
{
    if (Player *p = activePlayer()) seekPlayer(*p, qint64(qBound(0.0, f, 1.0) * lengthUs(*p)));
}

void MprisManager::setShuffle(bool on)
{
    if (Player *p = activePlayer()) setSourceShuffle(p->source, on);
}
void MprisManager::setLoopStatus(const QString &status)
{
    if (Player *p = activePlayer()) setSourceLoopStatus(p->source, status);
}
void MprisManager::cycleLoopStatus()
{
    const Player *p = activePlayer();
    if (!p) return;
    const QString next = p->loop == QLatin1String("None") ? QStringLiteral("Playlist")
                       : p->loop == QLatin1String("Playlist") ? QStringLiteral("Track")
                       : QStringLiteral("None");
    setSourceLoopStatus(p->source, next);
}

// Sends "Play" and checks: some Bluetooth bridges (BlueZ's mpris-proxy,
// behind the phone's AVRCP) occasionally lose the first "play" command
// after a pause — it happens in particular with the phone, not with native YT Music or
// Spotify — while "Pause"/"Next"/"Previous" on the same player
// always work. Since we cannot test it on real hardware from here, we
// limit ourselves to a second attempt if the state is not "Playing" shortly
// afterwards: harmless if the first command already went through.
void MprisManager::sendPlayWithRetry(const QString &service)
{
    callPlayer(service, QStringLiteral("Play"));
    QTimer::singleShot(700, this, [this, service]() {
        auto it = m_players.find(service);
        if (it != m_players.end() && it->ready && it->status != QLatin1String("Playing"))
            callPlayer(service, QStringLiteral("Play"));
    });
}

void MprisManager::playPauseSource(const QString &source)
{
    const QString svc = serviceFor(source);
    auto it = m_players.find(svc);
    if (it == m_players.end()) return;
    // Explicit Play/Pause: PlayPause is not implemented the same way by everyone
    const bool isPl = it->status == QLatin1String("Playing");
    if (isPl) callPlayer(svc, QStringLiteral("Pause"));
    else      sendPlayWithRetry(svc);
}
void MprisManager::playSource(const QString &source)     { sendPlayWithRetry(serviceFor(source)); }
void MprisManager::pauseSource(const QString &source)
{
    for (auto it = m_players.cbegin(); it != m_players.cend(); ++it)
        if (it->ready && it->source == source && it->status == QLatin1String("Playing"))
            callPlayer(it.key(), QStringLiteral("Pause"));
}
void MprisManager::nextSource(const QString &source)     { callPlayer(serviceFor(source), QStringLiteral("Next")); }
void MprisManager::previousSource(const QString &source) { callPlayer(serviceFor(source), QStringLiteral("Previous")); }

void MprisManager::seekSourceToFraction(const QString &source, double f)
{
    auto it = m_players.find(serviceFor(source));
    if (it == m_players.end()) return;
    seekPlayer(*it, qint64(qBound(0.0, f, 1.0) * lengthUs(*it)));
}

void MprisManager::setSourceShuffle(const QString &source, bool on)
{
    auto it = m_players.find(serviceFor(source));
    if (it == m_players.end()) return;
    it->shuffle = on;                                  // subito nell'interfaccia
    setPlayerProperty(it->service, QStringLiteral("Shuffle"), on);
    if (it->service == m_active) emit stateChanged();
    emit playersChanged();
}

void MprisManager::setSourceLoopStatus(const QString &source, const QString &status)
{
    auto it = m_players.find(serviceFor(source));
    if (it == m_players.end()) return;
    it->loop = status;
    setPlayerProperty(it->service, QStringLiteral("LoopStatus"), status);
    if (it->service == m_active) emit stateChanged();
    emit playersChanged();
}

void MprisManager::pauseAll() { pauseAllExcept(QString()); }

void MprisManager::pauseAllExcept(const QString &source)
{
    for (auto it = m_players.cbegin(); it != m_players.cend(); ++it)
        if (it->ready && it->source != source && it->status == QLatin1String("Playing"))
            callPlayer(it.key(), QStringLiteral("Pause"));
}

void MprisManager::activate(const QString &source)
{
    const QString svc = serviceFor(source);
    if (!svc.isEmpty()) setActive(svc);
}

// ═══════════════════════════ Effetti sonori ═══════════════════════════

void MprisManager::playEffect(const QString &program, const QStringList &args, double duckLevel)
{
    auto *proc = new QProcess(this);
    proc->setProcessChannelMode(QProcess::ForwardedErrorChannel);
    proc->setStandardOutputFile(QProcess::nullDevice());
    if (m_effectsRunning++ == 0) duck(qBound(0.0, duckLevel, 1.0));
    auto done = [this, proc]() {
        if (proc->property("mpris_done").toBool()) return;   // finished + errorOccurred
        proc->setProperty("mpris_done", true);
        m_effectPids.remove(proc->property("mpris_pid").toLongLong());
        if (--m_effectsRunning <= 0) { m_effectsRunning = 0; unduck(); }
        proc->deleteLater();
    };
    connect(proc, &QProcess::finished, this, done);
    connect(proc, &QProcess::errorOccurred, this, [proc, done](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart || proc->state() == QProcess::NotRunning) done();
    });
    connect(proc, &QProcess::started, this, [this, proc]() {
        proc->setProperty("mpris_pid", proc->processId());
        m_effectPids.insert(proc->processId());
    });
    proc->start(program, args);
}

void MprisManager::duck(double level)
{
    m_duckedVolumes.clear();
    for (auto it = m_players.begin(); it != m_players.end(); ++it) {
        if (!it->ready || !it->hasVolume || it->status != QLatin1String("Playing")) continue;
        m_duckedVolumes.insert(it.key(), it->volume);
        setPlayerProperty(it.key(), QStringLiteral("Volume"), it->volume * level);
    }
}

void MprisManager::unduck()
{
    // Raised in two steps, so as not to "slam" the music suddenly
    const QHash<QString, double> vols = m_duckedVolumes;
    m_duckedVolumes.clear();
    for (auto it = vols.cbegin(); it != vols.cend(); ++it) {
        const QString svc = it.key();
        const double v = it.value();
        if (!m_players.contains(svc)) continue;
        setPlayerProperty(svc, QStringLiteral("Volume"), v * 0.6);
        QTimer::singleShot(250, this, [this, svc, v]() {
            if (m_players.contains(svc)) setPlayerProperty(svc, QStringLiteral("Volume"), v);
        });
    }
}

// ═══════════════════════════ Bluetooth ═══════════════════════════

void MprisManager::ensureBluetoothProxy()
{
    if (m_btProxy && m_btProxy->state() != QProcess::NotRunning) return;
    // Already started by others (e.g. BlueZ user service)? Then do not duplicate
    // (QProcess::execute printed the PID found on the terminal, e.g. "1341")
    {
        QProcess check;
        check.start(QStringLiteral("pidof"), { QStringLiteral("mpris-proxy") });
        if (check.waitForFinished(1000) && check.exitStatus() == QProcess::NormalExit && check.exitCode() == 0) return;
    }
    if (!m_btProxy) {
        m_btProxy = new QProcess(this);
        m_btProxy->setProcessChannelMode(QProcess::ForwardedErrorChannel);
        m_btProxy->setStandardOutputFile(QProcess::nullDevice());
    }
    m_btProxy->start(QStringLiteral("mpris-proxy"), {});
    if (!m_btProxy->waitForStarted(2000))
        qWarning() << "[MPRIS] mpris-proxy not found: install the bluez package (music from the phone)";
    else
        qInfo() << "[MPRIS] mpris-proxy started (music from the phone over Bluetooth)";
}
