#pragma once
#include <QObject>
#include <QHash>
#include <QSet>
#include <QString>
#include <functional>

class QTimer;

// "On demand" start of the heavy Python services (YT Music, Spotify, podcasts): they start only when
// needed (app opened, search, track to resume) instead of all at UI startup.
class ServiceManager : public QObject
{
    Q_OBJECT
public:
    using Starter = std::function<void(const QString &script)>;
    explicit ServiceManager(Starter starter, QObject *parent = nullptr);
    // nome breve: "ytmusic" | "spotify" | "podcast"
    Q_INVOKABLE void ensure(const QString &name);
    void markStarted(const QString &name);
signals:
    void ready(const QString &name);      // the service's port is open
private:
    struct Info { QString script; int port; };
    QHash<QString, Info> m_info;
    QSet<QString> m_started;
    Starter m_starter;
    void waitForPort(const QString &name);
};
