#include <QCoreApplication>
#include "SetupManager.h"
#include "NavigationManager.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrlQuery>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QProcess>
#include <QSaveFile>
#include <QGuiApplication>
#include <QClipboard>
#include <QTimer>
#include <QDebug>
#include <QStandardPaths>
#include <QLibrary>

// Which Python service uses which key (it must be restarted if the key changes)
static const QHash<QString, QStringList> &keyServices()
{
    static const QHash<QString, QStringList> m = {
        {QStringLiteral("MAPBOX_TOKEN"),          {QStringLiteral("map_proxy")}},
        {QStringLiteral("MAPTILER_KEY"),          {QStringLiteral("map_proxy")}},
        {QStringLiteral("TOMTOM_KEY"),            {QStringLiteral("map_proxy")}},
        {QStringLiteral("OWM_KEY"),               {QStringLiteral("map_proxy")}},
        {QStringLiteral("SPOTIFY_CLIENT_ID"),     {QStringLiteral("spotify_scraper_service")}},
        {QStringLiteral("SPOTIFY_CLIENT_SECRET"), {QStringLiteral("spotify_scraper_service")}},
    };
    return m;
}

SetupManager::SetupManager(const QString &projectDir, NavigationManager *nav, QObject *parent)
    : QObject(parent), m_dir(projectDir), m_nav(nav), m_net(new QNetworkAccessManager(this))
{
}

QString SetupManager::keysPath() const
{
    const QString p = m_dir + QStringLiteral("/keys.env");
    const QString legacy = m_dir + QStringLiteral("/chiavi.env");   // old name, still honored
    return (!QFileInfo::exists(p) && QFileInfo::exists(legacy)) ? legacy : p;
}
QString SetupManager::doneFlagPath() const
{
    // Inside the app's data folder (no longer in ~/.config): so every new installation,
    // even the AppImage with its ~/.local/share/volta_os folder, starts with the guided setup.
    return m_dir + QStringLiteral("/data/setup_done");
}

bool SetupManager::needed() const
{
    if (qEnvironmentVariableIsSet("VOLTA_SETUP")) return true;
    return !QFileInfo::exists(doneFlagPath());   // only the first launch (even if some keys already exist)
}

void SetupManager::markDone()
{
    QDir().mkpath(QFileInfo(doneFlagPath()).absolutePath());
    QFile f(doneFlagPath());
    if (f.open(QIODevice::WriteOnly)) f.write("1\n");
    emit neededChanged();
}

QString SetupManager::value(const QString &name) const
{
    return qEnvironmentVariable(name.toLatin1().constData());
}

QVariantMap SetupManager::gamesStatus() const
{
    const QString home = QDir::homePath();
    const bool bottlesFlatpak = QFileInfo::exists(home + QStringLiteral("/.var/app/com.usebottles.bottles"));
    const bool bottlesNative = !QStandardPaths::findExecutable(QStringLiteral("bottles")).isEmpty();
    return {
        {QStringLiteral("bottles"), bottlesFlatpak || bottlesNative},
        {QStringLiteral("gamescope"), !QStandardPaths::findExecutable(QStringLiteral("gamescope")).isEmpty()},
    };
}

static QVariantMap depEntry(const QString &title, const QString &what, bool ok, bool required,
                            const QString &how, const QString &cmd)
{
    return {{QStringLiteral("title"), title}, {QStringLiteral("what"), what}, {QStringLiteral("ok"), ok},
            {QStringLiteral("required"), required}, {QStringLiteral("how"), how}, {QStringLiteral("cmd"), cmd}};
}

QVariantList SetupManager::dependencyReport() const
{
    QVariantList out;
    auto has = [](const char *exe) { return !QStandardPaths::findExecutable(QString::fromLatin1(exe)).isEmpty(); };

    // Python libraries of the services (the services run with /usr/bin/python3)
    struct Mod { const char *module; const char *pip; };
    static const Mod mods[] = {
        {"flask", "Flask"}, {"requests", "requests"}, {"PIL", "Pillow"}, {"segno", "segno"},
        {"ytmusicapi", "ytmusicapi"}, {"yt_dlp", "yt-dlp"}, {"mpv", "python-mpv"}, {"spotipy", "spotipy"},
        {"spotify_scraper", "spotifyscraper"}, {"mutagen", "mutagen"}, {"dbus_next", "dbus-next"}, {"vobject", "vobject"},
    };
    QString probe = QStringLiteral("import importlib.util as u\nfor m in [");
    for (const Mod &m : mods) probe += QStringLiteral("'%1',").arg(QLatin1String(m.module));
    probe += QStringLiteral("]:\n    print(m) if u.find_spec(m) is None else None\n");
    QProcess py;
    py.start(QStringLiteral("/usr/bin/python3"), {QStringLiteral("-c"), probe});
    QStringList missingPip;
    bool pyOk = py.waitForFinished(8000) && py.exitStatus() == QProcess::NormalExit;
    if (!pyOk) {
        out << depEntry(QStringLiteral("Python 3"), QStringLiteral("Runs the background services (music, maps, phone)"),
                        false, true, QStringLiteral("Install it from the terminal:"),
                        QStringLiteral("sudo apt install python3 python3-pip"));
    } else {
        const QStringList missingMods = QString::fromUtf8(py.readAllStandardOutput()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const Mod &m : mods)
            if (missingMods.contains(QLatin1String(m.module))) missingPip << QLatin1String(m.pip);
        out << depEntry(QStringLiteral("Python libraries"),
                        missingPip.isEmpty() ? QStringLiteral("All the Python libraries of the services are installed")
                                             : QStringLiteral("Missing: ") + missingPip.join(QStringLiteral(", ")),
                        missingPip.isEmpty(), true,
                        QStringLiteral("Music, maps, podcasts and phone will not fully work without them. Install them from the terminal:"),
                        QStringLiteral("/usr/bin/python3 -m pip install --user --break-system-packages ") + missingPip.join(QLatin1Char(' ')));
    }
    out << depEntry(QStringLiteral("mpv"), QStringLiteral("Plays music, podcasts and radio"), has("mpv"), true,
                    QStringLiteral("Install it from the terminal:"), QStringLiteral("sudo apt install mpv"));
    out << depEntry(QStringLiteral("pactl (PipeWire / PulseAudio)"), QStringLiteral("Volume, audio devices and calls"), has("pactl"), true,
                    QStringLiteral("Install it from the terminal:"), QStringLiteral("sudo apt install pipewire-pulse pulseaudio-utils"));
    out << depEntry(QStringLiteral("NetworkManager (nmcli)"), QStringLiteral("Wi-Fi in the Settings"), has("nmcli"), true,
                    QStringLiteral("Install it from the terminal:"), QStringLiteral("sudo apt install network-manager"));
    const bool obex = QFileInfo::exists(QStringLiteral("/usr/libexec/bluetooth/obexd")) || QFileInfo::exists(QStringLiteral("/usr/lib/bluetooth/obexd"));
    out << depEntry(QStringLiteral("BlueZ + obexd"), QStringLiteral("Bluetooth, phone contacts, SMS and music from the phone"),
                    has("bluetoothctl") && obex, true,
                    QStringLiteral("Install it from the terminal:"), QStringLiteral("sudo apt install bluez bluez-obexd"));
    QLibrary usb(QStringLiteral("usb-1.0"));
    out << depEntry(QStringLiteral("libusb"), QStringLiteral("CarPlay / Android Auto dongle"), usb.load(), false,
                    QStringLiteral("Install it from the terminal:"), QStringLiteral("sudo apt install libusb-1.0-0"));
    out << depEntry(QStringLiteral("spotifyd"), QStringLiteral("Plays Spotify through Spotify Connect"), has("spotifyd"), false,
                    QStringLiteral("Install it from the terminal:"), QStringLiteral("sudo apt install spotifyd"));
    out << depEntry(QStringLiteral("EasyEffects"), QStringLiteral("System equalizer in the Settings"), has("easyeffects"), false,
                    QStringLiteral("Install it from the terminal:"), QStringLiteral("sudo apt install easyeffects"));
    return out;
}

void SetupManager::logMissingDependencies() const
{
    const QVariantList r = dependencyReport();
    QStringList lines;
    for (const QVariant &v : r) {
        const QVariantMap m = v.toMap();
        if (!m.value(QStringLiteral("ok")).toBool() && m.value(QStringLiteral("required")).toBool())
            lines << QStringLiteral("  - %1: %2\n      %3").arg(m.value(QStringLiteral("title")).toString(),
                                                           m.value(QStringLiteral("what")).toString(),
                                                           m.value(QStringLiteral("cmd")).toString());
    }
    if (!lines.isEmpty())
        qWarning().noquote() << "[deps] Some required libraries or programs are missing: the UI will NOT be 100% functional.\n"
                                "[deps] Install them with:\n" + lines.join(QLatin1Char('\n'));
}

void SetupManager::openBottles() const
{
    if (QFileInfo::exists(QDir::homePath() + QStringLiteral("/.var/app/com.usebottles.bottles")))
        QProcess::startDetached(QStringLiteral("flatpak"), {QStringLiteral("run"), QStringLiteral("com.usebottles.bottles")});
    else
        QProcess::startDetached(QStringLiteral("bottles"), {});
}

QString SetupManager::clipboardText() const
{
    QClipboard *c = QGuiApplication::clipboard();
    return c ? c->text().trimmed() : QString();
}

bool SetupManager::save(const QVariantMap &values)
{
    // Start from the existing file; if missing, from the template (with comments and links)
    QStringList lines;
    for (const QString &src : {keysPath(), m_dir + QStringLiteral("/keys.env.example")}) {
        QFile f(src);
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            lines = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
            break;
        }
    }
    if (!lines.isEmpty() && lines.last().isEmpty()) lines.removeLast();

    QStringList changed;
    for (auto it = values.cbegin(); it != values.cend(); ++it) {
        const QString key = it.key();
        const QString val = it.value().toString().trimmed();
        if (val == value(key)) continue;
        changed << key;
        bool found = false;
        for (QString &l : lines) {
            if (l.startsWith(key + QLatin1Char('='))) { l = key + QLatin1Char('=') + val; found = true; break; }
        }
        if (!found) lines << key + QLatin1Char('=') + val;
        qputenv(key.toLatin1().constData(), val.toUtf8());     // for the services that restart
    }
    if (changed.isEmpty()) { emit saved(changed); return true; }

    QSaveFile out(keysPath());                                 // scrittura atomica
    if (!out.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "[setup] impossibile scrivere" << keysPath();
        return false;
    }
    out.write(lines.join(QLatin1Char('\n')).toUtf8() + "\n");
    if (!out.commit()) return false;
    QFile::setPermissions(keysPath(), QFileDevice::ReadOwner | QFileDevice::WriteOwner);

    if (changed.contains(QStringLiteral("MAPBOX_TOKEN")) && m_nav)
        m_nav->setToken(value(QStringLiteral("MAPBOX_TOKEN")));

    // Restarts the affected services: they stop and the supervisor restarts them
    // (with the environment updated above)
    QStringList svcs;
    for (const QString &k : changed)
        for (const QString &s : keyServices().value(k))
            if (!svcs.contains(s)) svcs << s;
    for (const QString &s : svcs)
        QProcess::startDetached(QStringLiteral("pkill"),
            {QStringLiteral("-f"), QStringLiteral("^/usr/bin/python3 [^ ]*/%1\\.py$").arg(s)});
    qInfo().noquote() << "[setup] salvate" << changed.join(", ") << "— riavvio:" << svcs.join(", ");
    emit saved(changed);
    return true;
}

void SetupManager::finishTest(const QString &name, bool ok, const QString &msg)
{
    emit testResult(name, ok, msg);
}

void SetupManager::test(const QString &name, const QString &rawValue, const QString &extra)
{
    const QString v = rawValue.trimmed();
    if (v.isEmpty()) { finishTest(name, false, QCoreApplication::translate("Msg", "Paste the key first")); return; }

    QUrl url;
    QNetworkRequest req;
    QByteArray post;
    bool isPost = false;
    // For each service the simplest call that says "valid key or not"
    if (name == QLatin1String("MAPBOX_TOKEN")) {
        url = QUrl(QStringLiteral("https://api.mapbox.com/tokens/v2"));
        QUrlQuery q; q.addQueryItem(QStringLiteral("access_token"), v); url.setQuery(q);
    } else if (name == QLatin1String("MAPTILER_KEY")) {
        url = QUrl(QStringLiteral("https://api.maptiler.com/maps/streets-v2/style.json"));
        QUrlQuery q; q.addQueryItem(QStringLiteral("key"), v); url.setQuery(q);
    } else if (name == QLatin1String("TOMTOM_KEY")) {
        url = QUrl(QStringLiteral("https://api.tomtom.com/search/2/search/roma.json"));
        QUrlQuery q; q.addQueryItem(QStringLiteral("key"), v); q.addQueryItem(QStringLiteral("limit"), QStringLiteral("1")); url.setQuery(q);
    } else if (name == QLatin1String("OWM_KEY")) {
        url = QUrl(QStringLiteral("https://api.openweathermap.org/data/2.5/weather"));
        QUrlQuery q; q.addQueryItem(QStringLiteral("q"), QStringLiteral("Roma")); q.addQueryItem(QStringLiteral("appid"), v); url.setQuery(q);
    } else if (name == QLatin1String("SPOTIFY_CLIENT_SECRET")) {
        // checks the id + secret PAIR (extra = Client ID)
        url = QUrl(QStringLiteral("https://accounts.spotify.com/api/token"));
        req.setRawHeader("Authorization", "Basic " + (extra.trimmed() + QLatin1Char(':') + v).toUtf8().toBase64());
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/x-www-form-urlencoded"));
        post = "grant_type=client_credentials";
        isPost = true;
    } else {
        finishTest(name, true, QString());     // no check available
        return;
    }
    req.setUrl(url);
    req.setTransferTimeout(10000);
    QNetworkReply *r = isPost ? m_net->post(req, post) : m_net->get(req);
    connect(r, &QNetworkReply::finished, this, [this, r, name]() {
        r->deleteLater();
        const int http = r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray body = r->readAll();
        if (http == 0) {
            finishTest(name, false, QCoreApplication::translate("Msg", "No internet connection"));
            return;
        }
        bool ok = http == 200;
        if (name == QLatin1String("MAPBOX_TOKEN"))
            ok = QJsonDocument::fromJson(body).object().value(QStringLiteral("code")).toString()
                 == QLatin1String("TokenValid");
        if (ok) finishTest(name, true, QCoreApplication::translate("Msg", "Valid key"));
        else if (http == 401 || http == 403 || http == 400 || name == QLatin1String("MAPBOX_TOKEN"))
            finishTest(name, false, QCoreApplication::translate("Msg", "Invalid key: check that you copied all of it"));
        else if (http == 429)
            finishTest(name, false, QCoreApplication::translate("Msg", "Too many attempts in a short time: try again in a minute"));
        else
            finishTest(name, false, QStringLiteral("The service is not responding (error %1): try again later").arg(http));
    });
}
