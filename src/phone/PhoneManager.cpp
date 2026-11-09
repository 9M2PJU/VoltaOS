#include "PhoneManager.h"
#include <QDebug>
#include <QtDBus/QtDBus>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QTimer>

// Servizio Python
static const char *SVC_BUS  = "com.volta.Phone";
static const char *SVC_PATH = "/com/volta/Phone";
static const char *SVC_IFACE = "com.volta.Phone";

PhoneManager::PhoneManager(QObject *parent) : QObject(parent) {
    // Retries connecting until the Python service is ready
    reconnectService();
}

void PhoneManager::reconnectService() {
    delete m_iface;
    m_iface = new QDBusInterface(SVC_BUS, SVC_PATH, SVC_IFACE,
                                 QDBusConnection::sessionBus(), this);
    if (m_iface->isValid()) {
        qDebug() << "[PhoneManager] Connected to the phone_service.py service";
        m_connected = true;
        emit connectedChanged();
        connectSignals();
        refreshContacts();
        refreshRecentCalls();
        refreshConversations();
        refreshCallState();
    } else {
        m_connected = false;
        emit connectedChanged();
        // Retry in 2s
        QTimer::singleShot(2000, this, &PhoneManager::reconnectService);
    }
}

void PhoneManager::connectSignals() {
    auto bus = QDBusConnection::sessionBus();
    bus.connect(SVC_BUS, SVC_PATH, SVC_IFACE, "IncomingCall",
                this, SLOT(onIncomingCall(QString,QString)));
    bus.connect(SVC_BUS, SVC_PATH, SVC_IFACE, "CallDialing",
                this, SLOT(onCallDialing(QString,QString)));
    bus.connect(SVC_BUS, SVC_PATH, SVC_IFACE, "CallAnswered",
                this, SLOT(onCallAnswered()));
    bus.connect(SVC_BUS, SVC_PATH, SVC_IFACE, "CallEnded",
                this, SLOT(onCallEnded()));
    bus.connect(SVC_BUS, SVC_PATH, SVC_IFACE, "ContactsUpdated",
                this, SLOT(onContactsUpdated()));
    bus.connect(SVC_BUS, SVC_PATH, SVC_IFACE, "ConversationsUpdated",
                this, SLOT(onConversationsUpdated()));
}

void PhoneManager::refreshContacts() {
    if (!m_iface || !m_iface->isValid()) return;
    QDBusReply<QString> reply = m_iface->call("GetContacts");
    if (reply.isValid()) {
        QJsonDocument doc = QJsonDocument::fromJson(reply.value().toUtf8());
        m_contacts = doc.array().toVariantList();
        emit contactsChanged();
        qDebug() << "[PhoneManager]" << m_contacts.size() << "contatti caricati.";
    }
}

void PhoneManager::refreshRecentCalls() {
    if (!m_iface || !m_iface->isValid()) return;
    QDBusReply<QString> reply = m_iface->call("GetRecentCalls");
    if (reply.isValid()) {
        QJsonDocument doc = QJsonDocument::fromJson(reply.value().toUtf8());
        m_recentCalls = doc.array().toVariantList();
        emit recentCallsChanged();
        qDebug() << "[PhoneManager]" << m_recentCalls.size() << "chiamate recenti.";
    }
}

void PhoneManager::refreshConversations() {
    if (!m_iface || !m_iface->isValid()) return;
    QDBusReply<QString> reply = m_iface->call("GetConversations");
    if (reply.isValid()) {
        QJsonDocument doc = QJsonDocument::fromJson(reply.value().toUtf8());
        m_conversations = doc.array().toVariantList();
        emit conversationsChanged();
        qDebug() << "[PhoneManager]" << m_conversations.size() << "conversazioni caricate.";
    }
}

void PhoneManager::refreshCallState() {
    if (!m_iface || !m_iface->isValid()) return;
    QDBusReply<QString> reply = m_iface->call("GetCallState");
    if (reply.isValid()) {
        QJsonDocument doc = QJsonDocument::fromJson(reply.value().toUtf8());
        QJsonObject o = doc.object();
        m_callState   = o.value("state").toString("idle");
        m_callContact = o.value("name").toString();
        m_callNumber  = o.value("number").toString();
        emit callStateChanged();
    }
}

void PhoneManager::fetchContacts() {
    refreshContacts();
    refreshRecentCalls();
}

void PhoneManager::dial(const QString &number) {
    qDebug() << "[PhoneManager] Dial:" << number;
    if (m_iface && m_iface->isValid()) m_iface->asyncCall("Dial", number);
    // Optimistic: updates the state right away (the service will confirm with CallDialing)
    m_callState = "dialing"; m_callContact = number; m_callNumber = number;
    emit callStateChanged();
}

void PhoneManager::hangup() {
    qDebug() << "[PhoneManager] Hangup";
    if (m_iface && m_iface->isValid()) m_iface->asyncCall("Hangup");
}

void PhoneManager::answer() {
    qDebug() << "[PhoneManager] Answer";
    if (m_iface && m_iface->isValid()) m_iface->asyncCall("Answer");
}

void PhoneManager::sendMessage(const QString &number, const QString &text) {
    qDebug() << "[PhoneManager] SendMessage a" << number;
    if (m_iface && m_iface->isValid()) m_iface->asyncCall("SendMessage", number, text);
    // ConversationsUpdated will arrive from the service once sending succeeds and will do the
    // refresh by itself — no optimistic update here: unlike a
    // call (where we know right away that it is "ringing"), an SMS sent
    // over Bluetooth can fail silently on the phone side, so
    // better to wait for the real confirmation.
}

QString PhoneManager::fetchFullMessage(const QString &number, int index) {
    if (!m_iface || !m_iface->isValid()) return QString();
    QDBusReply<QString> reply = m_iface->call("GetFullMessage", number, index);
    return reply.isValid() ? reply.value() : QString();
}

// ── Slot dai segnali DBus ─────────────────────────────────────────────

void PhoneManager::onIncomingCall(const QString &name, const QString &number) {
    m_callState = "incoming"; m_callContact = name; m_callNumber = number;
    qDebug() << "[PhoneManager] IncomingCall:" << name << "<" << number << ">";
    emit callStateChanged();
}

void PhoneManager::onCallDialing(const QString &name, const QString &number) {
    m_callState = "dialing"; m_callContact = name; m_callNumber = number;
    emit callStateChanged();
}

void PhoneManager::onCallAnswered() {
    m_callState = "active";
    emit callStateChanged();
}

void PhoneManager::onCallEnded() {
    m_callState = "idle"; m_callContact = ""; m_callNumber = "";
    emit callStateChanged();
}

void PhoneManager::onContactsUpdated() {
    refreshContacts();
    refreshRecentCalls();
}

void PhoneManager::onConversationsUpdated() {
    refreshConversations();
}
