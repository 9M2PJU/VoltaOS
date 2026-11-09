#include "GpsService.h"

#include <QSocketNotifier>
#include <QTimer>
#include <QDir>
#include <QFile>
#include <QDebug>
#include <QProcess>
#include <QRegularExpression>
#include <QSettings>

#include <fcntl.h>
#include <termios.h>
#include <sys/socket.h>
#include <poll.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>

// UBX CFG-RATE: measure every 100 ms (10 Hz). Checksum already computed.
static const unsigned char UBX_10HZ[] = {0xB5, 0x62, 0x06, 0x08, 0x06, 0x00, 0x64, 0x00,
                                         0x01, 0x00, 0x01, 0x00, 0x7A, 0x12};

GpsService::GpsService(QObject *parent) : QObject(parent)
{
    m_retry = new QTimer(this);
    m_retry->setSingleShot(true);
    connect(m_retry, &QTimer::timeout, this, &GpsService::tryOpen);
    m_tick = new QTimer(this);
    m_tick->setInterval(100);                       // 10 updates per second, as before
    connect(m_tick, &QTimer::timeout, this, &GpsService::broadcast);
    m_tick->start();
    m_btSelected = QSettings().value("gps/btMac").toString();
    QTimer::singleShot(0, this, &GpsService::tryOpen);
}

GpsService::~GpsService()
{
    if (m_fd >= 0) ::close(m_fd);
}

QString GpsService::usbVendor(const QString &n)
{
    for (const char *rel : {"/device/../idVendor", "/device/../../idVendor"}) {
        QFile f(QStringLiteral("/sys/class/tty/") + n + QLatin1String(rel));
        if (f.open(QIODevice::ReadOnly)) return QString::fromLatin1(f.readAll().trimmed());
    }
    return {};
}

// Ports to try, in order: GPS_PORT (if set), then u-blox (vendor 1546), then the
// other ttyACM/ttyUSB EXCEPT microcontroller boards. Before, any
// ttyACM was taken: with the GPS unplugged a connected MicroPython/Arduino board
// was opened (and received the UBX command), which finds Ctrl-A (raw REPL) in the command or resets.
QStringList GpsService::candidatePorts()
{
    const QString forced = qEnvironmentVariable("GPS_PORT");
    if (!forced.isEmpty()) return {forced};
    static const QStringList notGps = {
        QStringLiteral("2e8a"),   // Raspberry Pi Pico / MicroPython
        QStringLiteral("2341"), QStringLiteral("2a03"),   // Arduino
        QStringLiteral("239a"),   // Adafruit
        QStringLiteral("303a"),   // Espressif (ESP32)
        QStringLiteral("16c0"),   // Teensy
    };
    const QStringList names = QDir(QStringLiteral("/dev")).entryList(
        {QStringLiteral("ttyACM*"), QStringLiteral("ttyUSB*")}, QDir::System, QDir::Name);
    QStringList ublox, others;
    for (const QString &n : names) {
        const QString v = usbVendor(n);
        if (v == QLatin1String("1546")) ublox << QStringLiteral("/dev/") + n;
        else if (!notGps.contains(v)) others << QStringLiteral("/dev/") + n;
    }
    return ublox + others;
}

void GpsService::setBaud(int fd, int baud)
{
    termios t{};
    if (tcgetattr(fd, &t) != 0) return;
    cfmakeraw(&t);
    speed_t s = B9600;
    switch (baud) { case 4800: s = B4800; break; case 19200: s = B19200; break; case 38400: s = B38400; break;
                    case 57600: s = B57600; break; case 115200: s = B115200; break; default: break; }
    cfsetispeed(&t, s);
    cfsetospeed(&t, s);
    t.c_cflag |= (CLOCAL | CREAD);
    tcsetattr(fd, TCSANOW, &t);
    tcflush(fd, TCIFLUSH);
}

void GpsService::tryOpen()
{
    if (m_fd >= 0 || m_btFd >= 0) return;
    // 1) Bluetooth scelto a mano dall'utente
    if (!m_btSelected.isEmpty() && !m_btMode && m_btQueue.isEmpty() && !m_btListed) {
        m_btListed = true;
        QString nm = m_btSelected;
        for (const QVariant &v : m_btDevices)
            if (v.toMap().value("mac") == m_btSelected) nm = v.toMap().value("name").toString();
        startBt(m_btSelected, nm);
        return;
    }
    // 2) ricevitori seriali (USB)
    if (m_candidates.isEmpty()) m_candidates = candidatePorts();
    if (!m_candidates.isEmpty()) {
        const QString p = m_candidates.takeFirst();
        const int fd = ::open(p.toLocal8Bit().constData(), O_RDWR | O_NOCTTY | O_NONBLOCK);
        if (fd < 0) {
            qWarning().noquote() << "[GPS] impossibile aprire" << p << ":" << strerror(errno);
            m_retry->start(m_candidates.isEmpty() ? 5000 : 200);
            return;
        }
        const bool known = qEnvironmentVariableIsSet("GPS_PORT")
                           || usbVendor(p.mid(5)) == QLatin1String("1546");
        m_bauds = known ? QList<int>{38400} : QList<int>{9600, 38400, 4800, 115200, 57600};
        m_baudIdx = 0;
        setBaud(fd, m_bauds.first());
        m_fd = fd;
        m_port = p;
        m_btMode = false;
        m_buf.clear();
        m_notifier = new QSocketNotifier(m_fd, QSocketNotifier::Read, this);
        connect(m_notifier, &QSocketNotifier::activated, this, &GpsService::onReadable);
        if (known) {
            ::write(m_fd, UBX_10HZ, sizeof(UBX_10HZ));
            m_candidates.clear();
            m_source = QStringLiteral("USB ") + p;
            qInfo().noquote() << "[GPS]" << p << "open (u-blox), 38400 baud, 10 Hz";
            emit connectedChanged();
        } else {
            // unknown port: listen without writing anything, trying the most common speeds
            m_probing = true;
            if (!m_probe) {
                m_probe = new QTimer(this);
                m_probe->setSingleShot(true);
                connect(m_probe, &QTimer::timeout, this, &GpsService::probeTimeout);
            }
            m_probe->start(1800);
        }
        return;
    }
    // 3) no USB: already paired Bluetooth GPS (first the names that look like a GPS)
    if (m_btQueue.isEmpty()) {
        if (!m_btListed) { listBtDevices(true); return; }
        m_btListed = false;                      // round finished: starts over shortly
        m_retry->start(8000);
        return;
    }
    const auto dev = m_btQueue.takeFirst();
    startBt(dev.first, dev.second);
}

// ── Bluetooth ───────────────────────────────────────────────────────────────
void GpsService::listBtDevices(bool thenOpen)
{
    auto *p = new QProcess(this);
    auto done = [this, p, thenOpen](int, QProcess::ExitStatus) {
        QVariantList all;
        QList<QPair<QString, QString>> gps;
        static const QRegularExpression looksGps(
            QStringLiteral("gps|gnss|glonass|xgps|bad ?elf|holux|qstarz|globalsat|bu-?353|sirf|u-?blox|btgps|garmin glo|navilock|dualav|bt-?09"),
            QRegularExpression::CaseInsensitiveOption);
        const QString out = QString::fromUtf8(p->readAllStandardOutput());
        for (const QString &ln : out.split('\n')) {
            const QStringList w = ln.trimmed().split(' ');
            if (w.size() < 3 || w.at(0) != QLatin1String("Device")) continue;
            const QString mac = w.at(1), name = w.mid(2).join(' ');
            const bool g = looksGps.match(name).hasMatch();
            all << QVariantMap{{"mac", mac}, {"name", name}, {"gps", g}};
            if (g) gps << qMakePair(mac, name);
        }
        m_btDevices = all;
        emit btDevicesChanged();
        if (thenOpen) {
            m_btQueue = gps;
            m_btListed = true;
            if (m_btQueue.isEmpty()) m_retry->start(8000);
            else QTimer::singleShot(0, this, &GpsService::tryOpen);
        }
        p->deleteLater();
    };
    connect(p, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, done);
    connect(p, &QProcess::errorOccurred, this, [this, p, thenOpen](QProcess::ProcessError) {
        if (thenOpen) { m_btListed = true; m_retry->start(8000); }
        p->deleteLater();
    });
    p->start(QStringLiteral("bluetoothctl"), {QStringLiteral("devices"), QStringLiteral("Paired")});
}

void GpsService::refreshBtDevices() { listBtDevices(false); }

void GpsService::selectBluetooth(const QString &mac)
{
    m_btSelected = mac;
    QSettings().setValue("gps/btMac", mac);
    emit btSelectedChanged();
    if (m_fd >= 0) closePort(QStringLiteral("cambio ricevitore"));
    m_btListed = false; m_btQueue.clear();
    m_retry->start(200);
}

void GpsService::selectAuto()
{
    m_btSelected.clear();
    QSettings().remove("gps/btMac");
    emit btSelectedChanged();
    if (m_fd >= 0) closePort(QStringLiteral("ritorno all'automatico"));
    m_btListed = false; m_btQueue.clear(); m_candidates.clear();
    m_retry->start(200);
}

void GpsService::startBt(const QString &mac, const QString &name)
{
    // BlueZ's struct sockaddr_rc written by hand (Linux: AF_BLUETOOTH = 31, BTPROTO_RFCOMM = 3)
    struct SockAddrRc { sa_family_t family; unsigned char bdaddr[6]; unsigned char channel; };
    const QStringList b = mac.split(':');
    if (b.size() != 6) { m_retry->start(5000); return; }
    const int fd = ::socket(31, SOCK_STREAM | SOCK_NONBLOCK, 3);
    if (fd < 0) { qWarning().noquote() << "[GPS] Bluetooth not available:" << strerror(errno); m_retry->start(15000); return; }
    SockAddrRc a{};
    a.family = 31;
    for (int i = 0; i < 6; ++i) a.bdaddr[5 - i] = static_cast<unsigned char>(b.at(i).toInt(nullptr, 16));
    a.channel = static_cast<unsigned char>(m_btChannel);
    m_btMac = mac; m_btName = name;
    const int r = ::connect(fd, reinterpret_cast<sockaddr *>(&a), sizeof(a));
    if (r < 0 && errno != EINPROGRESS) {
        ::close(fd);
        btFinished(false);
        return;
    }
    m_btFd = fd;
    m_btWrite = new QSocketNotifier(fd, QSocketNotifier::Write, this);
    connect(m_btWrite, &QSocketNotifier::activated, this, [this]() {
        int err = 0; socklen_t l = sizeof(err);
        getsockopt(m_btFd, SOL_SOCKET, SO_ERROR, &err, &l);
        btFinished(err == 0);
    });
    if (!m_btTimer) {
        m_btTimer = new QTimer(this);
        m_btTimer->setSingleShot(true);
        connect(m_btTimer, &QTimer::timeout, this, [this]() { btFinished(false); });
    }
    m_btTimer->start(7000);
}

void GpsService::btFinished(bool ok)
{
    if (m_btTimer) m_btTimer->stop();
    if (m_btWrite) { m_btWrite->setEnabled(false); m_btWrite->deleteLater(); m_btWrite = nullptr; }
    const int fd = m_btFd;
    m_btFd = -1;
    if (!ok) {
        if (fd >= 0) ::close(fd);
        // next RFCOMM channel (most GPS use 1), then the next device
        if (m_btChannel < 3) { m_btChannel++; QTimer::singleShot(0, this, [this]() { startBt(m_btMac, m_btName); }); return; }
        m_btChannel = 1;
        qWarning().noquote() << "[GPS] Bluetooth" << m_btName << "unreachable";
        m_retry->start(m_btQueue.isEmpty() ? 8000 : 200);
        return;
    }
    m_fd = fd;                                   // from here on it is like a serial port
    m_port = QStringLiteral("bt:") + m_btMac;
    m_btMode = true;
    m_buf.clear();
    m_bauds.clear();
    m_notifier = new QSocketNotifier(m_fd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &GpsService::onReadable);
    m_probing = true;                            // if no NMEA sentences arrive within 10 s we move on
    if (!m_probe) {
        m_probe = new QTimer(this);
        m_probe->setSingleShot(true);
        connect(m_probe, &QTimer::timeout, this, &GpsService::probeTimeout);
    }
    m_probe->start(10000);
}

void GpsService::probeTimeout()
{
    if (!m_probing) return;
    if (!m_btMode && m_baudIdx + 1 < m_bauds.size()) {
        setBaud(m_fd, m_bauds.at(++m_baudIdx));     // same port, next speed
        m_buf.clear();
        m_probe->start(1800);
        return;
    }
    m_probing = false;
    if (m_notifier) { m_notifier->setEnabled(false); m_notifier->deleteLater(); m_notifier = nullptr; }
    if (m_fd >= 0) ::close(m_fd);
    m_fd = -1;
    m_btMode = false;
    m_btChannel = 1;
    m_retry->start(m_candidates.isEmpty() && m_btQueue.isEmpty() ? 5000 : 200);
}

void GpsService::closePort(const QString &why)
{
    qWarning().noquote() << "[GPS]" << why << "— riprovo tra 3 s";
    if (m_notifier) { m_notifier->setEnabled(false); m_notifier->deleteLater(); m_notifier = nullptr; }
    if (m_fd >= 0) ::close(m_fd);                     // frees the port (receiver unplugged)
    m_fd = -1;
    m_fix = false;
    m_probing = false;
    m_btMode = false;
    m_btChannel = 1;
    m_btListed = false;
    m_btQueue.clear();
    m_source.clear();
    m_candidates.clear();
    emit connectedChanged();
    m_retry->start(3000);
}

void GpsService::onReadable()
{
    char tmp[512];
    for (;;) {
        const ssize_t n = ::read(m_fd, tmp, sizeof(tmp));
        if (n > 0) { m_buf.append(tmp, int(n)); continue; }
        if (n == 0) { closePort(QStringLiteral("ricevitore scollegato")); return; }
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) break;
        closePort(QStringLiteral("read error: ") + QString::fromLocal8Bit(strerror(errno)));
        return;
    }
    int nl;
    while ((nl = m_buf.indexOf('\n')) >= 0) {
        parseLine(m_buf.left(nl).trimmed());
        m_buf.remove(0, nl + 1);
    }
    if (m_buf.size() > 4096) m_buf.clear();           // garbage without a newline
}

static double nmeaDeg(const QByteArray &raw, const QByteArray &hemi)
{
    const int dot = raw.indexOf('.');
    if (raw.isEmpty() || dot < 2) return 0.0;
    const double deg = raw.left(dot - 2).toDouble();
    const double min = raw.mid(dot - 2).toDouble();
    const double v = deg + min / 60.0;
    return (hemi == "S" || hemi == "W") ? -v : v;
}

static bool checksumOk(const QByteArray &s)
{
    const int star = s.indexOf('*');
    if (star < 0) return true;
    unsigned char x = 0;
    for (int i = 1; i < star; ++i) x ^= static_cast<unsigned char>(s.at(i));
    bool ok = false;
    const int want = s.mid(star + 1, 2).toInt(&ok, 16);
    return ok && want == x;
}

void GpsService::parseLine(const QByteArray &line)
{
    if (!line.startsWith('$') || !checksumOk(line)) return;
    if (m_probing && line.startsWith("$G") && line.contains('*')) {
        // the unknown port sends valid GPS sentences: it is the receiver
        m_probing = false;
        if (m_probe) m_probe->stop();
        m_candidates.clear();
        m_btQueue.clear();
        const int baud = (!m_btMode && m_baudIdx < m_bauds.size()) ? m_bauds.at(m_baudIdx) : 0;
        m_source = m_btMode ? QStringLiteral("Bluetooth ") + m_btName
                            : QStringLiteral("USB ") + m_port + QStringLiteral(" (%1 baud)").arg(baud);
        qInfo().noquote() << "[GPS]" << m_source << "riconosciuto dalle frasi NMEA";
        emit connectedChanged();
    }
    if (m_probing) return;
    const int star = line.indexOf('*');
    const QList<QByteArray> p = (star > 0 ? line.mid(1, star - 1) : line.mid(1)).split(',');
    if (p.isEmpty() || p.at(0).size() < 5) return;
    const QByteArray msg = p.at(0).mid(2);            // GPGGA, GNRMC... -> GGA, RMC

    if (msg == "GGA" && p.size() >= 10) {
        if (p.at(6).toInt() == 0) { m_fix = false; return; }   // GGA is the authoritative source of the fix
        m_fix = true;
        m_lat = nmeaDeg(p.at(2), p.at(3));
        m_lon = nmeaDeg(p.at(4), p.at(5));
        m_sats = p.at(7).toInt();
        m_accuracy = (p.at(8).isEmpty() ? 99.0 : p.at(8).toDouble()) * 5.0;   // HDOP -> metri, stima
        m_altitude = p.at(9).toDouble();
    } else if (msg == "RMC" && p.size() >= 9 && p.at(2) == "A") {
        m_fix = true;
        m_lat = nmeaDeg(p.at(3), p.at(4));
        m_lon = nmeaDeg(p.at(5), p.at(6));
        if (!p.at(7).isEmpty()) m_speed = p.at(7).toDouble() * 0.514444;      // nodi -> m/s
        // when stopped the heading is empty: the last good one is kept (not 0 = north)
        if (!p.at(8).isEmpty()) m_bearing = p.at(8).toDouble();
    } else if (msg == "VTG" && p.size() >= 8) {
        if (!p.at(7).isEmpty()) m_speed = p.at(7).toDouble() / 3.6;          // km/h -> m/s
        if (!p.at(1).isEmpty()) m_bearing = p.at(1).toDouble();
    }
    // (GSA deliberately ignored: one per constellation, it skewed the fix — see the history
    //  of map_service.py)
}

void GpsService::broadcast()
{
    if (!m_fix) return;
    static bool first = true;
    if (first) {
        first = false;
        qInfo().noquote() << QStringLiteral("[GPS] primo fix: %1, %2 (%3 satelliti)")
                                 .arg(m_lat, 0, 'f', 5).arg(m_lon, 0, 'f', 5).arg(m_sats);
    }
    QVariantMap d;
    d.insert(QStringLiteral("lat"), m_lat);
    d.insert(QStringLiteral("lon"), m_lon);
    d.insert(QStringLiteral("speed"), m_speed);
    d.insert(QStringLiteral("bearing"), m_bearing);
    d.insert(QStringLiteral("accuracy"), m_accuracy);
    d.insert(QStringLiteral("altitude"), m_altitude);
    d.insert(QStringLiteral("sats"), m_sats);
    d.insert(QStringLiteral("fix"), true);
    emit updated(d);
}
