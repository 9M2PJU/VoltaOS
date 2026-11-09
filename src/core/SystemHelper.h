#pragma once

#include <QObject>
#include <QProcess>
#include <QDebug>
#include <QRegularExpression>
#include <QVariant>
#include <QMap>
#include <QHash>
#include <QPointer>
#include <QNetworkCookie>
#include <QtQml/qqml.h>

class SystemHelper : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit SystemHelper(QObject *parent = nullptr);

    Q_INVOKABLE void setVolume(int percent);
    Q_INVOKABLE int getVolume();
    Q_INVOKABLE void runDetached(const QString &program, const QStringList &args);
    Q_INVOKABLE bool networkOnline();
    // NON-blocking version: answers with the networkChecked(bool) signal
    Q_INVOKABLE void checkNetworkAsync();
    // Reads a small text file (e.g. FastCarPlay's state); "" if missing
    Q_INVOKABLE QString readTextFile(const QString &path);
    // true if Chrome is playing audio OR it cannot be known (better not to
    // freeze a Chrome that is playing). Reads the audio streams with "pactl list sink-inputs".
    Q_INVOKABLE bool browserAudioMaybePlaying();
    // Installs on a WebEngineProfile an interceptor that adds "Google Chrome" to Sec-CH-UA
    Q_INVOKABLE void installGoogleFix(QObject *profile);
    // FULL cookies (also HttpOnly) of a WebEngineProfile: document.cookie does not see them.
    // watchCookies: to be called BEFORE the login; cookieHeader("music.youtube.com") -> "a=b; c=d"
    Q_INVOKABLE void watchCookies(QObject *profile);
    // persistCookies: keeps the logins (Google, YouTube...) even if Chromium does not write the cookies
    // to disk: it saves them in ~/.local/share/VoltaOS/cookies_<name>.json and restores them at startup
    Q_INVOKABLE void persistCookies(QObject *profile, const QString &name);
    Q_INVOKABLE QString cookieHeader(const QString &host) const;
    // Deletes from the watched profile the google.* and youtube.com cookies (logout from the internal browser).
    Q_INVOKABLE void clearGoogleCookies();
    // "key = value" configuration file (e.g. FastCarPlay's settings.txt).
    // confValue: value of the active (not commented) line, "" if absent.
    // setConfValue: replaces the line (active or commented) or adds it at the end.
    Q_INVOKABLE QString confValue(const QString &path, const QString &key);
    Q_INVOKABLE bool setConfValue(const QString &path, const QString &key, const QString &value);

    // ── Audio: output/input devices, balance (pactl) ──
    // Same synchronous approach as getVolume(): waitForFinished with a
    // short timeout, so the data is immediately usable in QML
    // (direct binding or immediate result of a button), without having to
    // go through asynchronous signals/callbacks for such a small value.
    // Actions that change the state (setDefaultAudioSink/Source,
    // setAudioBalance) instead stay non-blocking (startDetached),
    // as runDetached() already does.
    Q_INVOKABLE QVariantList listAudioSinks();
    Q_INVOKABLE QVariantList listAudioSources();
    Q_INVOKABLE QString defaultAudioSink();
    Q_INVOKABLE QString defaultAudioSource();
    Q_INVOKABLE void setDefaultAudioSink(const QString &name);
    Q_INVOKABLE void setDefaultAudioSource(const QString &name);
    Q_INVOKABLE double getAudioBalance(); // -1 (all left) .. 0 (center) .. +1 (all right)
    Q_INVOKABLE void setAudioBalance(double value);
    Q_INVOKABLE void testAudioOutput();

    // ── Display: risoluzione/refresh/scala reali, via D-Bus a Mutter ──
    // (org.gnome.Mutter.DisplayConfig — the same interface used by
    // gnome-control-center → Displays). It NO longer goes through wlr-randr: that Wayland
    // protocol is only understood by OUR nested compositor
    // (VoltaCompositor.qml), which does not implement it. Mutter instead is the
    // compositor that really owns the physical display in this
    // session, so it is the right place to ask/impose a
    // real configuration. If Mutter is not reachable over D-Bus,
    // displayState() returns available:false with a reason, instead of
    // pretending it works.
    Q_INVOKABLE QVariantMap displayState();
    Q_INVOKABLE bool setDisplayResolution(const QString &modeWxH);
    Q_INVOKABLE bool setDisplayScale(double scale);

    // ── REAL system equalizer, via EasyEffects (PipeWire) ──
    // It is no longer fake graphics: it really reads/writes the presets that the user
    // saved from EasyEffects (~/.config/easyeffects/output/*.json —
    // schema verified on the installed EasyEffects 7.2.3: equalizer#0.
    // left/right.band0..band5, each with "frequency" and "gain") and makes the
    // already running EasyEffects daemon reload the change
    // (it holds the D-Bus bus name com.github.wwmm.easyeffects) with
    // `easyeffects --load-preset <name>`. If no preset exists yet
    // (the user has not created/saved one from EasyEffects' UI),
    // eqAvailable() returns false instead of pretending it works.
    Q_INVOKABLE bool eqAvailable();
    Q_INVOKABLE QVariantList eqBands(); // [{frequency, gain}, ...] 6 bands, read from the preset in use
    Q_INVOKABLE void setEqBandGain(int band, double gainDb); // -12..+12 dB, on the preset in use
    // The equalizer ALWAYS stays on (no switch in the UI):
    // these remain for internal use, to force/verify that the system
    // output really goes through easyeffects_sink.
    Q_INVOKABLE bool eqEnabled();
    Q_INVOKABLE void setEqEnabled(bool on);
    // Presets: list, which one is "in use" now, load an
    // existing one, or save the current equalization with a new name.
    Q_INVOKABLE QStringList eqPresetList();
    Q_INVOKABLE QString eqCurrentPreset();
    Q_INVOKABLE bool eqLoadPreset(const QString &name);
    Q_INVOKABLE bool eqSaveAsPreset(const QString &name);
    // Deletes the preset file. If it was the one in use it switches to the first remaining.
    // Refuses to delete the LAST preset (without presets the EQ does not work).
    Q_INVOKABLE bool eqDeletePreset(const QString &name);

signals:
    void networkChecked(bool online);

private:
    QHash<QString, QNetworkCookie> m_cookies;
    QPointer<QObject> m_cookieProfile;
    static QString friendlyDeviceName(const QString &pactlName);
    bool applyDisplayConfig(const QString &modeId, double scale);

    // ── Stato dell'ultima displayState() riuscita, riusato dai setter
    // (setDisplayResolution/setDisplayScale) to rebuild the
    // ApplyMonitorsConfig call without asking everything again from QML: it needs the
    // connector, the current configuration serial (Mutter
    // requires it to avoid overwriting a config changed
    // by someone else in the meantime) and the position/orientation of the
    // logical monitor, to be proposed again UNCHANGED when only resolution or
    // only scale changes.
    uint    m_lastDisplaySerial = 0;
    QString m_lastDisplayConnector;
    int     m_lastDisplayX = 0;
    int     m_lastDisplayY = 0;
    uint    m_lastDisplayTransform = 0;
    bool    m_lastDisplayPrimary = true;
    double  m_lastDisplayScale = 1.0;
    QString m_lastDisplayCurrentModeId;
    // "1920x1080" -> Mutter mode_id with the highest refresh for that
    // resolution (so setDisplayResolution only receives "WxH" from QML,
    // as it already did before, without having to expose the refresh too).
    QMap<QString, QString> m_lastDisplayModeByRes;

    // Name (without ".json") of the EasyEffects preset currently in use for
    // the equalizer — by default "volta", the first one the user
    // created; it changes with eqLoadPreset()/eqSaveAsPreset().
    QString m_currentEqPreset = QStringLiteral("volta");
};
