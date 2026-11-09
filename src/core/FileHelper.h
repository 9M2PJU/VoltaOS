#pragma once
// Small QML helper: know whether a file exists before loading it
// (avoids the "QML Image: Cannot open" messages for optional images).
#include <QObject>
#include <QFileInfo>
#include <QUrl>

class FileHelper : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;
    // Accepts both a path ("/home/...") and a URL ("file:///home/...")
    Q_INVOKABLE bool exists(const QString &pathOrUrl) const {
        const QUrl u(pathOrUrl);
        const QString p = u.isLocalFile() ? u.toLocalFile() : pathOrUrl;
        return !p.isEmpty() && QFileInfo::exists(p);
    }
};
