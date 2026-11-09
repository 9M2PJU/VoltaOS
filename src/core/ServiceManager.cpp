#include "ServiceManager.h"
#include <QTcpSocket>
#include <QTimer>
#include <QDebug>

ServiceManager::ServiceManager(Starter starter, QObject *parent)
    : QObject(parent), m_starter(std::move(starter))
{
    m_info = {
        {QStringLiteral("ytmusic"), {QStringLiteral("ytmusic_scraper_service.py"), 8099}},
        {QStringLiteral("spotify"), {QStringLiteral("spotify_scraper_service.py"), 8098}},
        {QStringLiteral("podcast"), {QStringLiteral("podcast_service.py"), 8094}},
        {QStringLiteral("localmusic"), {QStringLiteral("local_music_service.py"), 8097}},
    };
}

void ServiceManager::markStarted(const QString &name) { m_started.insert(name); }

void ServiceManager::ensure(const QString &name)
{
    if (!m_info.contains(name) || m_started.contains(name)) return;
    m_started.insert(name);
    qInfo().noquote() << "[services] on-demand start:" << m_info.value(name).script;
    if (m_starter) m_starter(m_info.value(name).script);
    waitForPort(name);
}

// Checks every 400 ms (at most 40 s) whether the service's port answers, then notifies the UI
void ServiceManager::waitForPort(const QString &name)
{
    auto *t = new QTimer(this);
    auto *tries = new int(0);
    t->setInterval(400);
    connect(t, &QTimer::timeout, this, [this, t, tries, name]() {
        auto *s = new QTcpSocket(this);
        connect(s, &QTcpSocket::connected, this, [this, s, t, tries, name]() {
            s->deleteLater();
            if (t->isActive()) { t->stop(); t->deleteLater(); delete tries; emit ready(name); }
        });
        connect(s, &QTcpSocket::errorOccurred, s, &QObject::deleteLater);
        s->connectToHost(QStringLiteral("127.0.0.1"), quint16(m_info.value(name).port));
        if (++*tries > 100 && t->isActive()) { t->stop(); t->deleteLater(); delete tries; }
    });
    t->start();
}
