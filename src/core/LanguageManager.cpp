#include "LanguageManager.h"
#include <QCoreApplication>
#include <QSettings>
#include <QLocale>
#include <QDebug>
#include <QProcess>
#include <QTimer>

static const QStringList kLangs = { "en", "it", "es", "fr", "pt" };

LanguageManager::LanguageManager(QQmlEngine *engine, QObject *parent)
    : QObject(parent), m_engine(engine)
{
    QSettings s;
    const QString saved = s.value("ui/language").toString();
    if (kLangs.contains(saved)) { m_chosen = true; apply(saved); }
    else apply(QStringLiteral("en"));
}

void LanguageManager::apply(const QString &code)
{
    QCoreApplication::removeTranslator(&m_tr);
    m_code = code;
    if (code != QLatin1String("en")) {   // English is the source language: no translation file
        if (m_tr.load(QStringLiteral(":/i18n/volta_%1.qm").arg(code)))
            QCoreApplication::installTranslator(&m_tr);
        else
            qWarning() << "[language] translation not found for" << code;
    }
}

void LanguageManager::setLanguage(const QString &code)
{
    if (!kLangs.contains(code)) return;
    QSettings s;
    s.setValue("ui/language", code);
    m_chosen = true;
    if (code == m_code) { emit codeChanged(); return; }
    apply(code);
    if (m_engine) m_engine->retranslate();
    // The services that produce content in the language (YT Music, Spotify, podcasts)
    // read it at startup: I restart them, main relaunches them by itself with the new language.
    qputenv("VOLTA_LANG", code.toUtf8());
    QTimer::singleShot(600, this, []() {
        QProcess::execute("pkill", {"-f", "^/usr/bin/python3 [^ ]*/(ytmusic_scraper_service|spotify_scraper_service|"
                                          "podcast_service)\\.py$"});
    });
    emit codeChanged();
}

QString LanguageManager::name(const QString &code) const
{
    if (code == "it") return QStringLiteral("English");
    if (code == "es") return QStringLiteral("Español");
    if (code == "fr") return QStringLiteral("Français");
    if (code == "pt") return QStringLiteral("Português");
    return QStringLiteral("English");
}
