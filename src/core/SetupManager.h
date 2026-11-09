#pragma once
// SetupManager — behind the guided setup (qml/SetupWizard.qml).
//  - reads the current keys and writes them to keys.env (creates the file from the template
//    keys.env.example if missing, keeps comments and order)
//  - tests a key with a real call to the service (testResult)
//  - after saving it updates the environment and restarts ONLY the Python services that
//    use the changed keys (main.cpp's supervisor restarts them by itself)
#include <QObject>
#include <QVariantMap>
#include <QStringList>

class QNetworkAccessManager;
class NavigationManager;

class SetupManager : public QObject
{
    Q_OBJECT
    // true on first launch: setup never completed and the Mapbox key is missing
    Q_PROPERTY(bool needed READ needed NOTIFY neededChanged)
    // tests: VOLTA_SETUP=1 always opens it, VOLTA_SETUP_STEP=n starts from step n
    Q_PROPERTY(int debugStep READ debugStep CONSTANT)
public:
    SetupManager(const QString &projectDir, NavigationManager *nav, QObject *parent = nullptr);

    bool needed() const;
    int debugStep() const { bool ok; const int n = qEnvironmentVariableIntValue("VOLTA_SETUP_STEP", &ok); return ok ? n : -1; }

    Q_INVOKABLE QString value(const QString &name) const;
    /// Tests the key: answers with testResult(name, ok, message)
    Q_INVOKABLE void test(const QString &name, const QString &value, const QString &extra = QString());
    /// Saves {NAME: value} in keys.env and restarts the affected services
    Q_INVOKABLE bool save(const QVariantMap &values);
    /// Setup completed (or postponed): do not show it again at startup
    Q_INVOKABLE void markDone();
    /// "Games" step: are Bottles and gamescope installed?
    Q_INVOKABLE QVariantMap gamesStatus() const;
    /// "System check" step: [{title, what, ok, required, how, cmd}] for the libraries and programs
    /// Volta OS needs. Without the required ones the UI does not work at 100%.
    Q_INVOKABLE QVariantList dependencyReport() const;
    /// Writes the missing required dependencies (with the command to install them) to the terminal log
    void logMissingDependencies() const;
    /// Opens Bottles (to add games)
    Q_INVOKABLE void openBottles() const;
    /// Text from the system clipboard ("Paste" button)
    Q_INVOKABLE QString clipboardText() const;

    /// Opens the guided setup (from Settings › System)
    Q_INVOKABLE void open() { emit openRequested(); }

signals:
    void openRequested();
    void testResult(const QString &name, bool ok, const QString &message);
    void saved(const QStringList &changed);
    void neededChanged();

private:
    QString keysPath() const;
    QString doneFlagPath() const;
    void finishTest(const QString &name, bool ok, const QString &msg);

    QString m_dir;
    NavigationManager *m_nav;
    QNetworkAccessManager *m_net;
};
