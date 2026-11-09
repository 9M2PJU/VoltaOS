#include "SystemHelper.h"
#include <QProcess>
#include <QFile>
#include <QDebug>
#include <QRegularExpression>
#include <QPair>
#include <QTimer>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusReply>
#include <QtDBus/QDBusArgument>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusMetaType>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSaveFile>
#include <QtWebEngineQuick/QQuickWebEngineProfile>
#include <QtWebEngineCore/QWebEngineUrlRequestInterceptor>
#include <QtWebEngineCore/QWebEngineCookieStore>
#include <QDateTime>
#include <QtWebEngineCore/QWebEngineUrlRequestInfo>

// ── Support types to talk to org.gnome.Mutter.DisplayConfig over
// D-Bus (see the DISPLAY section below for why). They must be defined
// BEFORE the constructor because qDBusRegisterMetaType<T>() needs the
// complete type (struct + QDBusArgument operators), a forward
// declaration.
namespace {

// A "connector + mode" entry inside a logical monitor — same
// shape both on reading (GetCurrentState) and on writing
// (ApplyMonitorsConfig): (connector, mode_id, properties).
struct MonitorRef {
    QString connector;
    QString modeId;
    QVariantMap properties;
};

// A logical monitor: position, scale, orientation, whether it is the
// primary one, and the connectors/modes that compose it. It must be reused
// IDENTICAL (except the field we are changing) when we apply a
// new resolution or scale, otherwise we risk moving or rotating
// the screen by mistake.
struct LogicalMonitorConfig {
    int x = 0;
    int y = 0;
    double scale = 1.0;
    uint transform = 0;
    bool primary = false;
    QList<MonitorRef> monitors;
};

// ── Types ONLY for reading GetCurrentState. Deliberately separate from
// MonitorRef/LogicalMonitorConfig above (the output shapes are not
// identical to those required as input by ApplyMonitorsConfig — e.g. here
// the monitor-ref inside a logical monitor is (ssss), not (ssa{sv})). We no longer
// walk them by hand with nested beginStructure/endStructure: a
// single wrong begin/end in a deep chain is enough to misalign
// the cursor and crash libdbus ("type struct not a basic
// type") — it is exactly what happened. With these structs +
// operator>> Qt's generic QList<T>/QDBusArgument mechanism
// takes care of it, it does the bookkeeping by itself and is tested.
struct DBusMonitorSpec {
    QString connector, vendor, product, serial;
};
struct DBusMode {
    QString id;
    int width = 0;
    int height = 0;
    double refreshRate = 0.0;
    double preferredScale = 1.0;
    QList<double> supportedScales;
    QVariantMap properties;
};
struct DBusMonitor {
    DBusMonitorSpec spec;
    QList<DBusMode> modes;
    QVariantMap properties;
};
// "Connector + something else" entry inside a logical monitor in OUTPUT —
// the real signature (gdbus introspect) is a(ssss), different from the one expected
// as INPUT by ApplyMonitorsConfig (ssa{sv}). We do not need to interpret
// s2/s3/s4: s1 (the connector) is enough to know which logical
// monitor it belongs to, the rest we only read to consume it properly.
struct DBusLogicalMonitorRef {
    QString s1, s2, s3, s4;
};
struct DBusLogicalMonitor {
    int x = 0;
    int y = 0;
    double scale = 1.0;
    uint transform = 0;
    bool primary = false;
    QList<DBusLogicalMonitorRef> monitors;
    QVariantMap properties;
};

} // namespace

Q_DECLARE_METATYPE(MonitorRef)
Q_DECLARE_METATYPE(LogicalMonitorConfig)

static QDBusArgument &operator<<(QDBusArgument &arg, const MonitorRef &m)
{
    arg.beginStructure();
    arg << m.connector << m.modeId << m.properties;
    arg.endStructure();
    return arg;
}
static const QDBusArgument &operator>>(const QDBusArgument &arg, MonitorRef &m)
{
    arg.beginStructure();
    arg >> m.connector >> m.modeId >> m.properties;
    arg.endStructure();
    return arg;
}
static QDBusArgument &operator<<(QDBusArgument &arg, const LogicalMonitorConfig &lm)
{
    arg.beginStructure();
    arg << lm.x << lm.y << lm.scale << lm.transform << lm.primary << lm.monitors;
    arg.endStructure();
    return arg;
}
static const QDBusArgument &operator>>(const QDBusArgument &arg, LogicalMonitorConfig &lm)
{
    arg.beginStructure();
    arg >> lm.x >> lm.y >> lm.scale >> lm.transform >> lm.primary >> lm.monitors;
    arg.endStructure();
    return arg;
}

// ── Reading GetCurrentState — one beginStructure/endStructure per
// type, nothing else: the arrays (QList<DBusMode>, QList<DBusMonitor>, ...)
// are iterated by Qt itself through the generic operator>> for QList<T>, which
// trova questi operatori via ADL.
static const QDBusArgument &operator>>(const QDBusArgument &arg, DBusMonitorSpec &s)
{
    arg.beginStructure();
    arg >> s.connector >> s.vendor >> s.product >> s.serial;
    arg.endStructure();
    return arg;
}
static const QDBusArgument &operator>>(const QDBusArgument &arg, DBusMode &m)
{
    arg.beginStructure();
    arg >> m.id >> m.width >> m.height >> m.refreshRate >> m.preferredScale
        >> m.supportedScales >> m.properties;
    arg.endStructure();
    return arg;
}
static const QDBusArgument &operator>>(const QDBusArgument &arg, DBusMonitor &mon)
{
    arg.beginStructure();
    arg >> mon.spec >> mon.modes >> mon.properties;
    arg.endStructure();
    return arg;
}
static const QDBusArgument &operator>>(const QDBusArgument &arg, DBusLogicalMonitorRef &r)
{
    arg.beginStructure();
    arg >> r.s1 >> r.s2 >> r.s3 >> r.s4;
    arg.endStructure();
    return arg;
}
static const QDBusArgument &operator>>(const QDBusArgument &arg, DBusLogicalMonitor &lm)
{
    arg.beginStructure();
    arg >> lm.x >> lm.y >> lm.scale >> lm.transform >> lm.primary >> lm.monitors >> lm.properties;
    arg.endStructure();
    return arg;
}

SystemHelper::SystemHelper(QObject *parent) : QObject(parent)
{
    // Needed to be able to pass LogicalMonitorConfig/MonitorRef (with their
    // QLists inside) as a D-Bus argument to ApplyMonitorsConfig.
    //
    // CORRECTION compared to a previous attempt: here I had removed the
    // registration of the QList<>s thinking it was the cause of the "type
    // struct not a basic type" crash — but the real backtrace showed that the
    // crash was actually in the manual walk of displayState() (fixed
    // separately, see above), not here. Removing these two registerMetaType
    // however silently broke ApplyMonitorsConfig: passing a
    // QVariant that contains QList<LogicalMonitorConfig> to iface.call()
    // requires that ALSO the type QList<...> (not just LogicalMonitorConfig
    // alone) have a registered D-Bus marshaller, otherwise Qt does not know how to
    // convert it to bytes on the wire — probably the cause of why
    // resolution/scale seemed to "do nothing" after the click.
    qDBusRegisterMetaType<MonitorRef>();
    qDBusRegisterMetaType<QList<MonitorRef>>();
    qDBusRegisterMetaType<LogicalMonitorConfig>();
    qDBusRegisterMetaType<QList<LogicalMonitorConfig>>();
}

void SystemHelper::setVolume(int percent)
{
    percent = qBound(0, percent, 100);

    // 1. pactl (PulseAudio o pipewire-pulse compat layer)
    QProcess *p1 = new QProcess(this);
    p1->setProgram("pactl");
    p1->setArguments({"set-sink-volume", "@DEFAULT_SINK@", QString::number(percent) + "%"});
    connect(p1, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [p1, percent](int code, QProcess::ExitStatus) {
                if (code != 0) {
                    qWarning() << "[SystemHelper] pactl fallito (" << code << "):"
                               << p1->readAllStandardError();
                } else {
                    qDebug() << "[SystemHelper] pactl OK, volume =" << percent;
                }
                p1->deleteLater();
            });
    connect(p1, &QProcess::errorOccurred, this, [](QProcess::ProcessError) {
        qWarning() << "[SystemHelper] pactl not found or start error";
    });
    p1->start();

    // 2. wpctl — PipeWire's native command, often the only one that works on
    // Debian with pure PipeWire (without pipewire-pulse compat installed)
    QProcess *p2 = new QProcess(this);
    p2->setProgram("wpctl");
    p2->setArguments({"set-volume", "@DEFAULT_AUDIO_SINK@", QString::number(percent) + "%"});
    connect(p2, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [p2, percent](int code, QProcess::ExitStatus) {
                if (code != 0) {
                    qWarning() << "[SystemHelper] wpctl fallito (" << code << "):"
                               << p2->readAllStandardError();
                } else {
                    qDebug() << "[SystemHelper] wpctl OK, volume =" << percent;
                }
                p2->deleteLater();
            });
    connect(p2, &QProcess::errorOccurred, this, [](QProcess::ProcessError) {
        qWarning() << "[SystemHelper] wpctl not found or start error";
    });
    p2->start();

    // 3. Fallback ALSA amixer (ultima risorsa)
    QProcess *p3 = new QProcess(this);
    p3->setProgram("amixer");
    p3->setArguments({"-D", "pulse", "sset", "Master", QString::number(percent) + "%"});
    connect(p3, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            p3, &QProcess::deleteLater);
    p3->start();
}

int SystemHelper::getVolume()
{
    // Prova pactl
    QProcess p;
    p.start("pactl", {"get-sink-volume", "@DEFAULT_SINK@"});
    if (p.waitForFinished(1000) && p.exitCode() == 0) {
        QString output = p.readAllStandardOutput();
        QRegularExpression re(R"((\d+)%)");
        auto m = re.match(output);
        if (m.hasMatch()) return m.captured(1).toInt();
    }

    // Fallback wpctl
    QProcess p2;
    p2.start("wpctl", {"get-volume", "@DEFAULT_AUDIO_SINK@"});
    if (p2.waitForFinished(1000) && p2.exitCode() == 0) {
        QString output = p2.readAllStandardOutput();
        // Output tipico: "Volume: 0.65"
        QRegularExpression re(R"((\d+\.\d+))");
        auto m = re.match(output);
        if (m.hasMatch()) return qRound(m.captured(1).toDouble() * 100);
    }

    return 50;
}

void SystemHelper::runDetached(const QString &program, const QStringList &args)
{
    bool ok = QProcess::startDetached(program, args);
    if (!ok) {
        qWarning() << "[SystemHelper] Impossibile avviare:" << program << args;
    }
}

bool SystemHelper::networkOnline()
{
    // 1) Real state of the PC via NetworkManager
    QProcess p;
    p.start("nmcli", {"-t", "networking", "connectivity"});
    if (p.waitForFinished(1500)) {
        const QString out = QString::fromUtf8(p.readAllStandardOutput()).trimmed().toLower();
        if (out == "full")  return true;
        if (out == "none" || out == "limited" || out == "portal") return false;
        // "unknown" -> goes to the fallback
    }
    // 2) Fallback: is there an interface (other than lo) with operstate "up"?
    QProcess p2;
    p2.start("/bin/sh", {"-c",
        "for i in /sys/class/net/*/operstate; do "
        "n=$(basename $(dirname $i)); [ \"$n\" = lo ] && continue; "
        "[ \"$(cat $i)\" = up ] && { echo up; break; }; done"});
    if (p2.waitForFinished(1500)) {
        return QString::fromUtf8(p2.readAllStandardOutput()).trimmed() == "up";
    }
    return true; // when in doubt do not block the UI
}


// ═══════════════════════════ AUDIO (pactl) ═══════════════════════════════

QString SystemHelper::friendlyDeviceName(const QString &pactlName)
{
    // Ripulisce nomi tecnici tipo "alsa_output.pci-0000_00_1f.3.analog-stereo"
    QString n = pactlName;
    n.replace("alsa_output.", "");
    n.replace("alsa_input.", "");
    n.replace("bluez_output.", "Bluetooth ");
    n.replace("bluez_input.", "Bluetooth ");
    n.replace('_', ' ');
    n.replace('.', ' ');
    n = n.trimmed();
    if (n.isEmpty()) return pactlName;
    n[0] = n[0].toUpper();
    return n;
}

static QStringList parsePactlListShortNames(const QString &kind)
{
    QStringList out;
    QProcess p;
    p.start("pactl", {"list", "short", kind});
    if (!p.waitForFinished(1500) || p.exitCode() != 0) return out;
    const QString text = QString::fromUtf8(p.readAllStandardOutput());
    for (const QString &line : text.split('\n', Qt::SkipEmptyParts)) {
        const QStringList cols = line.split('\t');
        if (cols.size() >= 2) out.append(cols.at(1));
    }
    return out;
}

QVariantList SystemHelper::listAudioSinks()
{
    QVariantList result;
    for (const QString &name : parsePactlListShortNames("sinks")) {
        // EasyEffects' virtual sink is not a real device to
        // choose: it is an internal step of the equalizer (always
        // active, see setEqEnabled), it must not appear in the list.
        if (name.contains(QLatin1String("easyeffects"))) continue;
        QVariantMap m;
        m["name"] = name;
        m["label"] = friendlyDeviceName(name);
        result.append(m);
    }
    return result;
}

QVariantList SystemHelper::listAudioSources()
{
    QVariantList result;
    for (const QString &name : parsePactlListShortNames("sources")) {
        if (name.endsWith(".monitor")) continue; // it is not a real microphone, it is the "monitor" of an output
        QVariantMap m;
        m["name"] = name;
        m["label"] = friendlyDeviceName(name);
        result.append(m);
    }
    return result;
}

QString SystemHelper::defaultAudioSink()
{
    QProcess p;
    p.start("pactl", {"get-default-sink"});
    if (p.waitForFinished(1000) && p.exitCode() == 0)
        return QString::fromUtf8(p.readAllStandardOutput()).trimmed();
    return QString();
}

QString SystemHelper::defaultAudioSource()
{
    QProcess p;
    p.start("pactl", {"get-default-source"});
    if (p.waitForFinished(1000) && p.exitCode() == 0)
        return QString::fromUtf8(p.readAllStandardOutput()).trimmed();
    return QString();
}

void SystemHelper::setDefaultAudioSink(const QString &name)
{
    if (!QProcess::startDetached("pactl", {"set-default-sink", name}))
        qWarning() << "[SystemHelper] unable to set the default sink:" << name;
}

void SystemHelper::setDefaultAudioSource(const QString &name)
{
    if (!QProcess::startDetached("pactl", {"set-default-source", name}))
        qWarning() << "[SystemHelper] unable to set the default source:" << name;
}

double SystemHelper::getAudioBalance()
{
    const QString sink = defaultAudioSink();
    if (sink.isEmpty()) return 0.0;

    QProcess p;
    p.start("pactl", {"get-sink-volume", sink});
    if (!p.waitForFinished(1000) || p.exitCode() != 0) return 0.0;

    // "Volume: front-left: 45000 /  69% / -10.00 dB,   front-right: ... /  69% / ..."
    const QString out = QString::fromUtf8(p.readAllStandardOutput());
    QRegularExpression re(R"((\d+)%)");
    auto it = re.globalMatch(out);
    QList<int> vals;
    while (it.hasNext()) vals.append(it.next().captured(1).toInt());
    if (vals.size() < 2) return 0.0;

    // ON YOUR HARDWARE pactl's "front-left"/"front-right" label is
    // swapped relative to the physical ear (see note in
    // setAudioBalance): here we invert the reading in the same way, so the
    // returned value stays consistent with what is set
    // setAudioBalance (positivo = favorisce l'orecchio destro reale).
    const int physicalRight = vals.at(0), physicalLeft = vals.at(1);
    const int maxLR = qMax(qMax(physicalLeft, physicalRight), 1);
    return double(physicalRight - physicalLeft) / double(maxLR);
}

void SystemHelper::setAudioBalance(double value)
{
    value = qBound(-1.0, value, 1.0);
    const QString sink = defaultAudioSink();
    if (sink.isEmpty()) return;

    // IMPORTANT: the "base" reference must be read from the HIGHER channel of
    // the two current ones, NEVER from getVolume() (which only reads front-left).
    // Reason: front-left is exactly the channel that this function
    // itself modifies when panning to the right — if we reused it as the
    // base, every drag of the slider would re-read a value already
    // reduced by the previous round and reduce it again, making the overall
    // volume go down at every movement instead of just
    // moving the pan (the bug for which the balance seemed "a
    // volume"). Taking the maximum of the two channels, the "full" side
    // stays always stable no matter how many times it is dragged.
    int base = getVolume(); // fallback if the parse below fails
    QProcess p;
    p.start("pactl", {"get-sink-volume", sink});
    if (p.waitForFinished(1000) && p.exitCode() == 0) {
        const QString out = QString::fromUtf8(p.readAllStandardOutput());
        QRegularExpression re(R"((\d+)%)");
        auto it = re.globalMatch(out);
        QList<int> vals;
        while (it.hasNext()) vals.append(it.next().captured(1).toInt());
        if (vals.size() >= 2) base = qMax(vals.at(0), vals.at(1));
    }

    const int left  = value <= 0 ? base : qRound(base * (1.0 - value));
    const int right = value >= 0 ? base : qRound(base * (1.0 + value));

    // pactl does NOT accept channel prefixes like "front-left:50%": the
    // per-channel volumes are passed in positional order, first argument =
    // "front-left" for pactl, second = "front-right". ON YOUR HARDWARE
    // however that pactl label does not match the physical ear
    // corrispondente (confermato testando a mano `pactl set-sink-volume
    // ... 20% 100%`: the "high" channel was heard on the left, not on the
    // right) — so we invert here the order of the arguments passed to
    // pactl, so "left"/"right" in our code match again
    // the right physical ear instead of pactl's.
    QProcess::startDetached("pactl", {
        "set-sink-volume", sink,
        QString::number(right) + "%",
        QString::number(left) + "%"
    });
}

void SystemHelper::testAudioOutput()
{
    // A single sound, not three overlapping (unlike setVolume(), here
    // we want the FIRST one that really works, not "all the ones there are").
    // Same trick already used for the blue light filter: a shell one-liner
    // launched "detached" (never blocking on the QML thread) that chains the
    // candidates with "&&", moving to the next only if the previous one is
    // davvero fallito.
    const QString cmd =
        "paplay /usr/share/sounds/alsa/Front_Center.wav && exit 0; "
        "paplay /usr/share/sounds/freedesktop/stereo/bell.oga && exit 0; "
        "speaker-test -t sine -f 1000 -l 1";
    if (!QProcess::startDetached("/bin/sh", {"-c", cmd}))
        qWarning() << "[SystemHelper] unable to start the audio test";
}


// ═══════════════════════ DISPLAY (Mutter, via D-Bus) ═══════════════════════
//
// WHY D-Bus and not wlr-randr: wlr-randr speaks the Wayland protocol
// wlr-output-management-unstable-v1, which OUR nested compositor
// (VoltaCompositor.qml) does not implement — it always failed, regardless of
// what was installed. But this machine does not run with our
// compositor as the main session: it is a real GNOME Shell/Mutter
// session, with VoltaCompositor.qml nested inside as a simple
// client window (same discovery already made for the blue light filter). Mutter
// really owns the physical output and exposes its configuration over
// D-Bus (org.gnome.Mutter.DisplayConfig) — the same interface used by
// gnome-control-center → Displays. The exact signature below is taken
// from the REAL introspection of this machine (gdbus introspect), not from
// memory. The support types (MonitorRef, LogicalMonitorConfig) and their
// operators are defined at the top of the file, before the constructor.

QVariantMap SystemHelper::displayState()
{
    QVariantMap result;

    QDBusInterface iface(QStringLiteral("org.gnome.Mutter.DisplayConfig"),
                          QStringLiteral("/org/gnome/Mutter/DisplayConfig"),
                          QStringLiteral("org.gnome.Mutter.DisplayConfig"),
                          QDBusConnection::sessionBus());
    if (!iface.isValid()) {
        result["available"] = false;
        result["reason"] = QStringLiteral(
            "Unable to reach org.gnome.Mutter.DisplayConfig over D-Bus "
            "(no GNOME/Mutter session running here)");
        return result;
    }

    QDBusMessage reply = iface.call(QStringLiteral("GetCurrentState"));
    if (reply.type() == QDBusMessage::ErrorMessage || reply.arguments().size() < 3) {
        result["available"] = false;
        result["reason"] = QStringLiteral("GetCurrentState fallita: ") + reply.errorMessage();
        return result;
    }

    m_lastDisplaySerial = reply.arguments().at(0).toUInt();

    // ── monitors: a((ssss) a(siiddada{sv}) a{sv}) — demarshaling
    // delegated to Qt's generic mechanism (QList<T> knows how to descend by
    // itself into DBusMonitor/DBusMode through the operator>> above),
    // no more begin/end written by hand line by line.
    QList<DBusMonitor> monitors;
    reply.arguments().at(1).value<QDBusArgument>() >> monitors;

    QList<DBusLogicalMonitor> logicalMonitors;
    reply.arguments().at(2).value<QDBusArgument>() >> logicalMonitors;

    if (monitors.isEmpty() || monitors.first().modes.isEmpty()) {
        result["available"] = false;
        result["reason"] = QStringLiteral("Mutter reports no active monitor");
        return result;
    }

    // We take the first monitor (this kiosk has only one real output).
    const DBusMonitor &primaryMonitor = monitors.first();
    m_lastDisplayConnector = primaryMonitor.spec.connector;

    // ── logical_monitors: we find the one that contains our
    // connector, to reuse its position/scale/orientation when we
    // reapply a config (otherwise we risk moving or
    // rotating the screen by changing only the resolution).
    for (const DBusLogicalMonitor &lm : logicalMonitors) {
        bool matches = false;
        for (const DBusLogicalMonitorRef &r : lm.monitors)
            if (r.s1 == m_lastDisplayConnector) matches = true;
        if (matches) {
            m_lastDisplayX = lm.x; m_lastDisplayY = lm.y; m_lastDisplayScale = lm.scale;
            m_lastDisplayTransform = lm.transform; m_lastDisplayPrimary = lm.primary;
            break;
        }
    }

    // ── List of modes → unique "WxH" resolutions for the QML picker,
    // keeping for each the mode_id with the highest refresh (used by the
    // setter when the user chooses only the resolution). The active
    // mode is identified from the "is-current" property that Mutter
    // marks per mode.
    m_lastDisplayModeByRes.clear();
    QMap<QString, double> bestRefresh;
    QVariantList resolutions;
    QString currentRes; double currentRefresh = 0.0;

    for (const DBusMode &m : primaryMonitor.modes) {
        const QString res = QString::number(m.width) + "x" + QString::number(m.height);
        if (!m_lastDisplayModeByRes.contains(res)) {
            resolutions.append(res);
            m_lastDisplayModeByRes[res] = m.id;
            bestRefresh[res] = m.refreshRate;
        } else if (m.refreshRate > bestRefresh.value(res)) {
            m_lastDisplayModeByRes[res] = m.id;
            bestRefresh[res] = m.refreshRate;
        }
        if (m.properties.value(QStringLiteral("is-current")).toBool()) {
            currentRes = res;
            currentRefresh = m.refreshRate;
            m_lastDisplayCurrentModeId = m.id;
        }
    }
    if (currentRes.isEmpty()) { // rare: no mode marked "is-current"
        const DBusMode &fallback = primaryMonitor.modes.first();
        currentRes = QString::number(fallback.width) + "x" + QString::number(fallback.height);
        currentRefresh = fallback.refreshRate;
        m_lastDisplayCurrentModeId = fallback.id;
    }

    result["available"] = true;
    result["outputName"] = m_lastDisplayConnector;
    result["resolutions"] = resolutions;
    result["currentResolution"] = currentRes;
    result["currentRefresh"] = currentRefresh;
    result["scale"] = m_lastDisplayScale;
    return result;
}

bool SystemHelper::applyDisplayConfig(const QString &modeId, double scale)
{
    MonitorRef mon;
    mon.connector = m_lastDisplayConnector;
    mon.modeId = modeId;

    LogicalMonitorConfig lm;
    lm.x = m_lastDisplayX;
    lm.y = m_lastDisplayY;
    lm.scale = scale;
    lm.transform = m_lastDisplayTransform;
    lm.primary = m_lastDisplayPrimary;
    lm.monitors = QList<MonitorRef>{ mon };

    QDBusInterface iface(QStringLiteral("org.gnome.Mutter.DisplayConfig"),
                          QStringLiteral("/org/gnome/Mutter/DisplayConfig"),
                          QStringLiteral("org.gnome.Mutter.DisplayConfig"),
                          QDBusConnection::sessionBus());
    if (!iface.isValid()) {
        qWarning() << "[SystemHelper] D-Bus Mutter.DisplayConfig unreachable";
        return false;
    }

    // method: 0=verify, 1=temporary (automatic revert if not confirmed
    // within ~20s), 2=persistent — we use persistent because here there is
    // no "keep changes?" dialog to confirm it.
    QDBusMessage reply = iface.call(QStringLiteral("ApplyMonitorsConfig"),
        m_lastDisplaySerial,
        (uint)2,
        QVariant::fromValue(QList<LogicalMonitorConfig>{ lm }),
        QVariantMap());

    if (reply.type() == QDBusMessage::ErrorMessage) {
        qWarning() << "[SystemHelper] ApplyMonitorsConfig fallita:" << reply.errorMessage();
        return false;
    }
    return true;
}

bool SystemHelper::setDisplayResolution(const QString &modeWxH)
{
    if (m_lastDisplayConnector.isEmpty()) displayState();
    if (m_lastDisplayConnector.isEmpty()) return false;
    const QString modeId = m_lastDisplayModeByRes.value(modeWxH);
    if (modeId.isEmpty()) return false;
    if (!applyDisplayConfig(modeId, m_lastDisplayScale)) return false;
    m_lastDisplayCurrentModeId = modeId;
    return true;
}

bool SystemHelper::setDisplayScale(double scale)
{
    if (m_lastDisplayConnector.isEmpty()) displayState();
    if (m_lastDisplayConnector.isEmpty() || m_lastDisplayCurrentModeId.isEmpty()) return false;
    if (!applyDisplayConfig(m_lastDisplayCurrentModeId, scale)) return false;
    m_lastDisplayScale = scale;
    return true;
}

// ═══════════════ EQUALIZZATORE DI SISTEMA (EasyEffects) ═══════════════
// The preset is a simple JSON file that the user saved from
// EasyEffects' UI — we read/write it with QJsonDocument instead of
// regex blows on the text, so all the fields we do not touch
// (frequency, mode, q, slope, type, width, ...) stay exactly
// as they were: we only change "gain".
namespace {
QString eqPresetDir()
{
    return QDir::homePath() + "/.config/easyeffects/output";
}
QString eqPresetFile(const QString &name)
{
    return eqPresetDir() + "/" + name + ".json";
}
constexpr int kEqBandCount = 6;
constexpr double kEqMaxDb = 12.0; // useful range of a "car" EQ slider
constexpr const char *kEqSinkName = "easyeffects_sink";

// Filesystem-safe preset names (only letters, digits, space, - and
// _): eqSaveAsPreset() writes a file called that, so we first clean
// anything that comes from the text box in QML, so as not to
// end up outside the presets folder or with invalid characters.
QString sanitizePresetName(const QString &raw)
{
    QString out;
    for (const QChar &c : raw)
        if (c.isLetterOrNumber() || c == QLatin1Char('-') || c == QLatin1Char('_') || c == QLatin1Char(' '))
            out += c;
    return out.trimmed();
}
}

bool SystemHelper::eqAvailable()
{
    if (QFile::exists(eqPresetFile(m_currentEqPreset))) return true;
    // The "in use" preset does not exist (never created, or renamed/deleted by
    // EasyEffects): if at least one other exists anyway, let us hook onto
    // that instead of declaring everything unavailable.
    const QStringList list = eqPresetList();
    if (!list.isEmpty()) { m_currentEqPreset = list.first(); return true; }
    return false;
}

QStringList SystemHelper::eqPresetList()
{
    QDir dir(eqPresetDir());
    QStringList names;
    const QFileInfoList entries = dir.entryInfoList({"*.json"}, QDir::Files, QDir::Name);
    for (const QFileInfo &fi : entries) names.append(fi.completeBaseName());
    return names;
}

QString SystemHelper::eqCurrentPreset()
{
    return m_currentEqPreset;
}

bool SystemHelper::eqLoadPreset(const QString &name)
{
    const QString safe = sanitizePresetName(name);
    if (safe.isEmpty() || !QFile::exists(eqPresetFile(safe))) return false;
    m_currentEqPreset = safe;
    // Same EasyEffects daemon already running (D-Bus bus
    // com.github.wwmm.easyeffects): we make it load this preset.
    QProcess::startDetached("easyeffects", { "--load-preset", safe });
    return true;
}

bool SystemHelper::eqSaveAsPreset(const QString &name)
{
    const QString safe = sanitizePresetName(name);
    if (safe.isEmpty()) return false;

    // "Save as" of the CURRENT equalization (gains already applied in the
    // preset in use): we copy the existing file, we do not create an empty one,
    // so the button really saves what is being listened to now.
    QFile src(eqPresetFile(m_currentEqPreset));
    if (!src.open(QIODevice::ReadOnly)) {
        qWarning() << "[SystemHelper] no EQ preset in use to copy from — unable to save" << safe;
        return false;
    }
    const QByteArray data = src.readAll();
    src.close();

    QDir().mkpath(eqPresetDir());
    QFile dst(eqPresetFile(safe));
    if (!dst.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "[SystemHelper] unable to write the new EQ preset" << safe;
        return false;
    }
    dst.write(data);
    dst.close();

    m_currentEqPreset = safe;
    QProcess::startDetached("easyeffects", { "--load-preset", safe });
    return true;
}

bool SystemHelper::eqDeletePreset(const QString &name)
{
    const QString safe = sanitizePresetName(name);
    if (safe.isEmpty() || !QFile::exists(eqPresetFile(safe))) return false;

    const QStringList before = eqPresetList();
    if (before.size() <= 1) {
        qWarning() << "[SystemHelper] impossibile eliminare l'unico preset EQ" << safe;
        return false;
    }
    if (!QFile::remove(eqPresetFile(safe))) {
        qWarning() << "[SystemHelper] unable to delete the EQ preset" << safe;
        return false;
    }
    if (m_currentEqPreset == safe) {
        const QStringList after = eqPresetList();
        if (!after.isEmpty()) {
            m_currentEqPreset = after.first();
            QProcess::startDetached("easyeffects", { "--load-preset", m_currentEqPreset });
        }
    }
    return true;
}

QVariantList SystemHelper::eqBands()
{
    QVariantList result;
    QFile f(eqPresetFile(m_currentEqPreset));
    if (!f.open(QIODevice::ReadOnly)) return result;
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    f.close();

    const QJsonObject eq = root["output"].toObject()["equalizer#0"].toObject();
    const QJsonObject left = eq["left"].toObject(); // split-channels is false: left==right
    for (int i = 0; i < kEqBandCount; ++i) {
        const QJsonObject band = left[QStringLiteral("band%1").arg(i)].toObject();
        QVariantMap m;
        m["frequency"] = band["frequency"].toDouble();
        m["gain"] = band["gain"].toDouble();
        result.append(m);
    }
    return result;
}

void SystemHelper::setEqBandGain(int band, double gainDb)
{
    if (band < 0 || band >= kEqBandCount) return;
    gainDb = qBound(-kEqMaxDb, gainDb, kEqMaxDb);

    QFile f(eqPresetFile(m_currentEqPreset));
    if (!f.open(QIODevice::ReadOnly)) {
        qWarning() << "[SystemHelper] preset EQ" << m_currentEqPreset << "not found";
        return;
    }
    QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();

    QJsonObject root = doc.object();
    QJsonObject output = root["output"].toObject();
    QJsonObject eq = output["equalizer#0"].toObject();

    const QString bandKey = QStringLiteral("band%1").arg(band);
    // The preset has "split-channels": false (a single value for both
    // channels), but it still keeps two copies (left/right) in the file: we
    // write both to stay consistent even if in the future
    // split-channels venisse attivato dall'utente in EasyEffects.
    for (const char *side : { "left", "right" }) {
        QJsonObject channel = eq[side].toObject();
        QJsonObject bandObj = channel[bandKey].toObject();
        bandObj["gain"] = gainDb;
        channel[bandKey] = bandObj;
        eq[side] = channel;
    }
    output["equalizer#0"] = eq;
    root["output"] = output;
    doc.setObject(root);

    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "[SystemHelper] unable to write the EQ preset" << m_currentEqPreset;
        return;
    }
    f.write(doc.toJson(QJsonDocument::Indented));
    f.close();

    // The EasyEffects daemon is already running (it holds the D-Bus bus
    // com.github.wwmm.easyeffects): this command makes it reload the
    // preset just written to disk, applying the new gain right away.
    QProcess::startDetached("easyeffects", { "--load-preset", m_currentEqPreset });
}

bool SystemHelper::eqEnabled()
{
    QProcess p;
    p.start("pactl", {"get-default-sink"});
    if (!p.waitForFinished(1000)) return false;
    return QString::fromUtf8(p.readAllStandardOutput()).trimmed() == QLatin1String(kEqSinkName);
}

void SystemHelper::setEqEnabled(bool on)
{
    if (on) {
        // If EasyEffects is not running its sink does not exist: moving the
        // audio there would fail ("Failure: No such entity") and be useless.
        QProcess ls;
        ls.start("pactl", {"list", "sinks", "short"});
        if (!ls.waitForFinished(1000)
            || !QString::fromUtf8(ls.readAllStandardOutput()).contains(QLatin1String(kEqSinkName))) {
            qInfo() << "[EQ] EasyEffects not active: equalizer not applied";
            return;
        }
        // Moves the default output to EasyEffects' virtual sink:
        // from here on all the system audio goes through its
        // equalizer before reaching the real hardware (which
        // EasyEffects drives internally, from its "Output
        // Device" section — we do not touch it, it stays what the user chose
        // there).
        QProcess::startDetached("pactl", {"set-default-sink", QLatin1String(kEqSinkName)});

        // set-default-sink only applies to NEW streams: we also move
        // the ones already playing, otherwise the activation seems to have no
        // effect until the app that is playing is restarted.
        QProcess mv;
        mv.start("pactl", {"list", "sink-inputs", "short"});
        if (mv.waitForFinished(1000)) {
            const QStringList lines = QString::fromUtf8(mv.readAllStandardOutput())
                                           .split('\n', Qt::SkipEmptyParts);
            for (const QString &line : lines) {
                const QString id = line.section('\t', 0, 0);
                if (!id.isEmpty())
                    QProcess::startDetached("pactl", {"move-sink-input", id, QLatin1String(kEqSinkName)});
            }
        }
    } else {
        // Back to the first real hardware sink (the first that is NOT
        // EasyEffects' virtual sink) — same pactl already used elsewhere here,
        // no assumptions about the sound card's exact name.
        QProcess p;
        p.start("pactl", {"list", "sinks", "short"});
        QString fallback;
        if (p.waitForFinished(1000)) {
            const QStringList lines = QString::fromUtf8(p.readAllStandardOutput())
                                           .split('\n', Qt::SkipEmptyParts);
            for (const QString &line : lines) {
                if (!line.contains(QLatin1String(kEqSinkName))) {
                    fallback = line.section('\t', 1, 1);
                    break;
                }
            }
        }
        if (!fallback.isEmpty())
            QProcess::startDetached("pactl", {"set-default-sink", fallback});
    }
}

bool SystemHelper::browserAudioMaybePlaying()
{
    QProcess p;
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));   // output pactl sempre in inglese
    p.setProcessEnvironment(env);
    p.start(QStringLiteral("pactl"), QStringList{QStringLiteral("list"), QStringLiteral("sink-inputs")});
    if (!p.waitForStarted(500)) return true;
    if (!p.waitForFinished(1000)) { p.kill(); p.waitForFinished(300); return true; }
    if (p.exitStatus() != QProcess::NormalExit || p.exitCode() != 0) return true;
    const QString out = QString::fromUtf8(p.readAllStandardOutput());
    const QStringList blocks = out.split(QRegularExpression(QStringLiteral("\\n(?=Sink Input #)")));
    for (const QString &raw : blocks) {
        const QString b = raw.toLower();
        const bool isChrome = b.contains(QLatin1String("application.name = \"google chrome"))
                           || b.contains(QLatin1String("application.name = \"chromium"))
                           || b.contains(QLatin1String("application.process.binary = \"chrome"))
                           || b.contains(QLatin1String("application.process.binary = \"google-chrome"));
        if (isChrome && b.contains(QLatin1String("corked: no"))) return true;
    }
    return false;
}

QString SystemHelper::readTextFile(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return QString();
    return QString::fromUtf8(f.read(64 * 1024));
}

QString SystemHelper::confValue(const QString &path, const QString &key)
{
    const QStringList lines = readTextFile(path).split('\n');
    const QRegularExpression re(QStringLiteral("^\\s*") + QRegularExpression::escape(key)
                                + QStringLiteral("\\s*=\\s*([^#]*)"));
    for (const QString &l : lines) {
        const auto m = re.match(l);
        if (m.hasMatch()) return m.captured(1).trimmed();
    }
    return QString();
}

bool SystemHelper::setConfValue(const QString &path, const QString &key, const QString &value)
{
    QFile f(path);
    QStringList lines;
    if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        lines = QString::fromUtf8(f.readAll()).split('\n');
        f.close();
    }
    const QString k = QRegularExpression::escape(key);
    const QRegularExpression active(QStringLiteral("^\\s*") + k + QStringLiteral("\\s*="));
    const QRegularExpression commented(QStringLiteral("^\\s*#\\s*") + k + QStringLiteral("\\s*="));
    const QString newLine = key + QStringLiteral(" = ") + value;

    int idx = -1;
    for (int i = 0; i < lines.size(); ++i)
        if (active.match(lines[i]).hasMatch()) { idx = i; break; }
    if (idx < 0)
        for (int i = 0; i < lines.size(); ++i)
            if (commented.match(lines[i]).hasMatch()) { idx = i; break; }

    if (idx >= 0) {
        lines[idx] = newLine;
        // any other active lines with the same key: commented out
        for (int i = idx + 1; i < lines.size(); ++i)
            if (active.match(lines[i]).hasMatch()) lines[i] = QStringLiteral("#") + lines[i];
    } else {
        if (!lines.isEmpty() && lines.last().isEmpty()) lines.insert(lines.size() - 1, newLine);
        else lines << newLine;
    }

    if (!f.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
        qWarning() << "[SystemHelper] impossibile scrivere" << path;
        return false;
    }
    f.write(lines.join('\n').toUtf8());
    return true;
}


// ── Fix login Google in QtWebEngine ─────────────────────────────────
namespace {
class GoogleHintsInterceptor : public QWebEngineUrlRequestInterceptor {
public:
    using QWebEngineUrlRequestInterceptor::QWebEngineUrlRequestInterceptor;
    void interceptRequest(QWebEngineUrlRequestInfo &info) override {
        const QString host = info.requestUrl().host();
        // On the login pages the Browser presents itself as an Android tablet (see
        // BrowserApp.qml): there no "Google Chrome desktop" header.
        if (host == QLatin1String("accounts.google.com")) return;
        if (host.endsWith("google.com") || host.endsWith("youtube.com")
            || host.endsWith("gstatic.com") || host.endsWith("googleusercontent.com")
            || host.endsWith("googleapis.com")) {
            info.setHttpHeader("Sec-CH-UA",
                "\"Google Chrome\";v=\"140\", \"Chromium\";v=\"140\", \"Not=A?Brand\";v=\"24\"");
        }
    }
};
}

void SystemHelper::installGoogleFix(QObject *profile)
{
    auto *p = qobject_cast<QQuickWebEngineProfile *>(profile);
    if (!p) { qWarning() << "[gfix] invalid profile"; return; }
    p->setUrlRequestInterceptor(new GoogleHintsInterceptor(p));
    qInfo() << "[gfix] intercettore Sec-CH-UA installato";
}

// ── Full cookies (also HttpOnly) read from the browser's profile ──
void SystemHelper::watchCookies(QObject *profile)
{
    auto *p = qobject_cast<QQuickWebEngineProfile *>(profile);
    if (!p) { qWarning() << "[cookie] invalid profile"; return; }
    QWebEngineCookieStore *store = p->cookieStore();
    if (!store) { qWarning() << "[cookie] cookie store assente"; return; }
    if (m_cookieProfile.data() != p) {
        m_cookieProfile = p;
        m_cookies.clear();
        auto key = [](const QNetworkCookie &ck) {
            return ck.domain() + QLatin1Char('|') + ck.path() + QLatin1Char('|') + QString::fromUtf8(ck.name());
        };
        connect(store, &QWebEngineCookieStore::cookieAdded, this,
                [this, key](const QNetworkCookie &ck) { m_cookies.insert(key(ck), ck); });
        connect(store, &QWebEngineCookieStore::cookieRemoved, this,
                [this, key](const QNetworkCookie &ck) { m_cookies.remove(key(ck)); });
    }
    store->loadAllCookies();   // re-emits cookieAdded for those already present
}

QString SystemHelper::cookieHeader(const QString &host) const
{
    const QString h = host.toLower();
    const QDateTime now = QDateTime::currentDateTimeUtc();
    QMap<QString, QString> out;
    for (const QNetworkCookie &ck : m_cookies) {
        QString d = ck.domain().toLower();
        if (d.startsWith(QLatin1Char('.'))) d.remove(0, 1);
        if (d.isEmpty()) continue;
        if (!(h == d || h.endsWith(QLatin1Char('.') + d))) continue;
        if (!ck.isSessionCookie() && ck.expirationDate() < now) continue;
        const QString path = ck.path();
        if (!path.isEmpty() && path != QLatin1String("/")) continue;
        out.insert(QString::fromUtf8(ck.name()), QString::fromUtf8(ck.value()));
    }
    QStringList parts;
    for (auto it = out.cbegin(); it != out.cend(); ++it)
        parts << it.key() + QLatin1Char('=') + it.value();
    return parts.join(QStringLiteral("; "));
}

void SystemHelper::clearGoogleCookies()
{
    auto *p = qobject_cast<QQuickWebEngineProfile *>(m_cookieProfile.data());
    if (!p || !p->cookieStore()) return;
    const QList<QNetworkCookie> all = m_cookies.values();
    for (const QNetworkCookie &ck : all) {
        QString d = ck.domain().toLower();
        if (d.startsWith(QLatin1Char('.'))) d.remove(0, 1);
        const bool google  = d.startsWith(QLatin1String("google.")) || d.contains(QLatin1String(".google."));
        const bool youtube = d == QLatin1String("youtube.com") || d.endsWith(QLatin1String(".youtube.com"));
        if (google || youtube) p->cookieStore()->deleteCookie(ck);
    }
}


// ── NON-blocking network check ──
// networkOnline() launches nmcli and waits on the UI thread: the UI stops until nmcli answers.
static bool volta_anyIfaceUp()
{
    QDir d(QStringLiteral("/sys/class/net"));
    const QStringList names = d.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &n : names) {
        if (n == QLatin1String("lo")) continue;
        QFile f(d.filePath(n) + QStringLiteral("/operstate"));
        if (f.open(QIODevice::ReadOnly) && f.readAll().trimmed() == "up") return true;
    }
    return false;
}

void SystemHelper::checkNetworkAsync()
{
    auto *p = new QProcess(this);
    auto finish = [this, p](bool online) {
        if (p->property("done").toBool()) return;
        p->setProperty("done", true);
        p->deleteLater();
        emit networkChecked(online);
    };
    connect(p, &QProcess::finished, this, [p, finish](int, QProcess::ExitStatus) {
        const QString out = QString::fromUtf8(p->readAllStandardOutput()).trimmed().toLower();
        if (out == QLatin1String("full")) finish(true);
        else if (out == QLatin1String("none") || out == QLatin1String("limited") || out == QLatin1String("portal")) finish(false);
        else finish(volta_anyIfaceUp());
    });
    connect(p, &QProcess::errorOccurred, this, [finish](QProcess::ProcessError) { finish(volta_anyIfaceUp()); });
    QTimer::singleShot(4000, p, [p, finish]() {
        if (p->state() != QProcess::NotRunning) p->kill();
        finish(true);   // when in doubt do not report offline
    });
    p->start(QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("networking"), QStringLiteral("connectivity")});
}


// ── Logins that stay: cookie copy to file, restored at startup ──
void SystemHelper::persistCookies(QObject *profile, const QString &name)
{
    auto *p = qobject_cast<QQuickWebEngineProfile *>(profile);
    if (!p) { qWarning() << "[cookie] invalid profile"; return; }
    QWebEngineCookieStore *store = p->cookieStore();
    if (!store) { qWarning() << "[cookie] cookie store assente"; return; }

    const QString dir = QDir::homePath() + QStringLiteral("/.local/share/VoltaOS");
    QDir().mkpath(dir);
    const QString path = dir + QStringLiteral("/cookies_") + name + QStringLiteral(".json");

    auto *jar = new QHash<QString, QNetworkCookie>;          // lives as long as the profile
    auto key = [](const QNetworkCookie &ck) {
        return ck.domain() + QLatin1Char('|') + ck.path() + QLatin1Char('|') + QString::fromUtf8(ck.name());
    };

    // 1) ripristino
    QFile f(path);
    if (f.open(QIODevice::ReadOnly)) {
        const QJsonArray arr = QJsonDocument::fromJson(f.readAll()).array();
        const QDateTime now = QDateTime::currentDateTime();
        for (const QJsonValue &v : arr) {
            const auto list = QNetworkCookie::parseCookies(v.toString().toUtf8());
            for (QNetworkCookie ck : list) {
                if (ck.expirationDate().isValid() && ck.expirationDate() < now) continue;
                jar->insert(key(ck), ck);
                store->setCookie(ck);
            }
        }
        f.close();
    }

    // 2) saving (postponed by 2 s: cookies arrive in bursts)
    auto *timer = new QTimer(p);
    timer->setSingleShot(true);
    timer->setInterval(2000);
    connect(timer, &QTimer::timeout, p, [jar, path]() {
        QJsonArray arr;
        for (const QNetworkCookie &ck : std::as_const(*jar))
            arr.append(QString::fromUtf8(ck.toRawForm(QNetworkCookie::Full)));
        QSaveFile out(path);
        if (out.open(QIODevice::WriteOnly)) {
            out.write(QJsonDocument(arr).toJson(QJsonDocument::Compact));
            out.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
            out.commit();
        }
    });
    connect(store, &QWebEngineCookieStore::cookieAdded, p, [jar, key, timer](const QNetworkCookie &c) {
        QNetworkCookie ck = c;
        // session cookies (without expiry) last 60 days, so the login stays
        if (!ck.expirationDate().isValid())
            ck.setExpirationDate(QDateTime::currentDateTime().addDays(60));
        jar->insert(key(ck), ck);
        timer->start();
    });
    connect(store, &QWebEngineCookieStore::cookieRemoved, p, [jar, key, timer](const QNetworkCookie &c) {
        jar->remove(key(c));
        timer->start();
    });
    qInfo() << "[cookie] accessi salvati in" << path << "- ripristinati:" << jar->size();
}
