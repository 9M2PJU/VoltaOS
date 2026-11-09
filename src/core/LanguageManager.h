#pragma once
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTranslator>
#include <QQmlEngine>

// Interface language. The original text in the QML files is in English (qsTr):
// for the other languages the volta_<code>.qm files are loaded (i18n/ folder), then the QML
// engine re-evaluates all the texts (retranslate). The choice is saved in "ui/language".
class LanguageManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString code READ code NOTIFY codeChanged)
    Q_PROPERTY(bool chosen READ chosen NOTIFY codeChanged)   // false until the user chooses
public:
    explicit LanguageManager(QQmlEngine *engine, QObject *parent = nullptr);
    QString code() const { return m_code; }
    bool chosen() const { return m_chosen; }
    Q_INVOKABLE void setLanguage(const QString &code);
    // language code for the external services (always one of it,en,es,fr,pt)
    Q_INVOKABLE QString name(const QString &code) const;
signals:
    void codeChanged();
private:
    QQmlEngine *m_engine;
    QTranslator m_tr;
    QString m_code = QStringLiteral("en");
    bool m_chosen = false;
    void apply(const QString &code);
};
