#pragma once
// GpsService — serial GPS receiver (u-blox M9N) read directly by the UI.
// It used to be done by services/map_service.py, which sent the data to QML via WebSocket:
// one Python process and one network hop less, more immediate position.
//
// To QML (context property "Gps") it emits updated(d) 10 times per second with
// a valid fix. d has the same fields as before:
//   lat, lon [gradi] · speed [m/s] · bearing [gradi, 0 = nord] · accuracy [m stimati]
//   altitude [m] · sats · fix
#include <QObject>
#include <QVariantMap>
#include <QVariantList>
#include <QByteArray>

class QSocketNotifier;
class QTimer;

class GpsService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(QString port READ port NOTIFY connectedChanged)
    Q_PROPERTY(QString source READ source NOTIFY connectedChanged)           // es. "USB /dev/ttyACM0" o "Bluetooth BT-GPS"
    Q_PROPERTY(QVariantList btDevices READ btDevices NOTIFY btDevicesChanged)  // dispositivi Bluetooth associati [{mac,name,gps}]
    Q_PROPERTY(QString btSelected READ btSelected NOTIFY btSelectedChanged)    // MAC scelto a mano ("" = automatico)
public:
    explicit GpsService(QObject *parent = nullptr);
    ~GpsService() override;

    bool connected() const { return m_fd >= 0; }
    QString port() const { return m_port; }
    QString source() const { return m_source; }
    QVariantList btDevices() const { return m_btDevices; }
    QString btSelected() const { return m_btSelected; }
    // Bluetooth GPS: list of paired devices, manual choice and return to automatic
    Q_INVOKABLE void refreshBtDevices();
    Q_INVOKABLE void selectBluetooth(const QString &mac);
    Q_INVOKABLE void selectAuto();

signals:
    void updated(const QVariantMap &d);
    void connectedChanged();
    void btDevicesChanged();
    void btSelectedChanged();

private:
    void tryOpen();
    void closePort(const QString &why);
    void onReadable();
    void parseLine(const QByteArray &line);
    void broadcast();
    void probeTimeout();
    static QStringList candidatePorts();
    static QString usbVendor(const QString &ttyName);

    void startBt(const QString &mac, const QString &name);
    void btFinished(bool ok);
    void setBaud(int fd, int baud);
    void listBtDevices(bool thenOpen);

    // Bluetooth GPS (RFCOMM, serial over radio): socket opened by hand, without Bluetooth libraries
    QString m_source;
    QString m_btSelected;
    QVariantList m_btDevices;
    QList<QPair<QString, QString>> m_btQueue;     // automatic devices still to be tried
    bool m_btListed = false;
    bool m_btMode = false;
    int m_btFd = -1;
    int m_btChannel = 1;
    QString m_btMac, m_btName;
    QSocketNotifier *m_btWrite = nullptr;
    QTimer *m_btTimer = nullptr;
    QList<int> m_bauds;
    int m_baudIdx = 0;

    int m_fd = -1;
    QString m_port;
    QSocketNotifier *m_notifier = nullptr;
    QTimer *m_retry = nullptr;
    QTimer *m_tick = nullptr;
    QByteArray m_buf;
    // On a port not recognized as u-blox we first LISTEN: only if valid NMEA
    // sentences arrive is it considered a GPS (and only then is the UBX command sent).
    bool m_probing = false;
    QTimer *m_probe = nullptr;
    QStringList m_candidates;

    double m_lat = 45.4642, m_lon = 9.19, m_speed = 0, m_bearing = 0;
    double m_accuracy = 0, m_altitude = 0;
    int m_sats = 0;
    bool m_fix = false;
};
