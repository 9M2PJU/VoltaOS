#pragma once
#include <QObject>
#include <QVariantList>
#include <QQmlEngine>

class QDBusInterface;

/**
 * Ponte QML ↔ phone_service.py (bus name com.volta.Phone).
 * Espone:
 *  - contatti e cronologia chiamate scaricati via Bluetooth PBAP
 *  - stato chiamata corrente (idle / incoming / dialing / active)
 *  - dial / answer / hangup
 * Receives the IncomingCall / CallAnswered / CallEnded signals from the service
 * Python e li ripropaga a QML.
 */
class PhoneManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList contacts     READ contacts     NOTIFY contactsChanged)
    Q_PROPERTY(QVariantList recentCalls  READ recentCalls  NOTIFY recentCallsChanged)
    Q_PROPERTY(QVariantList conversations READ conversations NOTIFY conversationsChanged)
    Q_PROPERTY(QString      callState    READ callState    NOTIFY callStateChanged)
    Q_PROPERTY(QString      callContact  READ callContact  NOTIFY callStateChanged)
    Q_PROPERTY(QString      callNumber   READ callNumber   NOTIFY callStateChanged)
    Q_PROPERTY(bool         connected    READ connected    NOTIFY connectedChanged)

public:
    explicit PhoneManager(QObject *parent = nullptr);

    QVariantList contacts()      const { return m_contacts; }
    QVariantList recentCalls()   const { return m_recentCalls; }
    QVariantList conversations() const { return m_conversations; }
    QString      callState()    const { return m_callState; }
    QString      callContact()  const { return m_callContact; }
    QString      callNumber()   const { return m_callNumber; }
    bool         connected()    const { return m_connected; }

    Q_INVOKABLE void fetchContacts();     // refresh request (optional, the service updates by itself)
    Q_INVOKABLE void dial(const QString &number);
    Q_INVOKABLE void hangup();
    Q_INVOKABLE void answer();
    // Messaggi (SMS via Bluetooth MAP)
    Q_INVOKABLE void sendMessage(const QString &number, const QString &text);
    // Synchronous: GetFullMessage downloads the full body of a message (the
    // initial ListMessages only gives a preview) — called when the UI
    // opens/scrolls a conversation.
    Q_INVOKABLE QString fetchFullMessage(const QString &number, int index);

signals:
    void contactsChanged();
    void recentCallsChanged();
    void conversationsChanged();
    void callStateChanged();
    void connectedChanged();

private slots:
    void onIncomingCall(const QString &name, const QString &number);
    void onCallDialing(const QString &name, const QString &number);
    void onCallAnswered();
    void onCallEnded();
    void onContactsUpdated();
    void onConversationsUpdated();
    void reconnectService();

private:
    QDBusInterface *m_iface = nullptr;
    QVariantList m_contacts;
    QVariantList m_recentCalls;
    QVariantList m_conversations;
    QString      m_callState   = "idle";
    QString      m_callContact;
    QString      m_callNumber;
    bool         m_connected   = false;

    void connectSignals();
    void refreshContacts();
    void refreshRecentCalls();
    void refreshConversations();
    void refreshCallState();
};
