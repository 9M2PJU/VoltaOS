#pragma once
// Diagnostics (only with VOLTA_DIRTY=1): who forces the UI to redraw?
// At every frame it reads Qt Quick's internal list of "dirty" items
// (to be redrawn) and every 5 s prints the ranking, plus the animations and the fast
// timers that are on. Uses private Qt Quick APIs: for diagnosis only.
#include <QObject>
#include <QHash>
#include <QTimer>
#include <QQuickWindow>
#include <QQmlContext>
#include <QQmlEngine>
#include <QMetaProperty>
#include <QDebug>
#include <algorithm>
#include <private/qquickwindow_p.h>
#include <private/qquickitem_p.h>

class DirtyProbe : public QObject {
public:
    DirtyProbe(QQuickWindow *w, QObject *root) : QObject(w), m_win(w), m_root(root) {
        connect(w, &QQuickWindow::afterAnimating, this, &DirtyProbe::sample);
        connect(w, &QQuickWindow::frameSwapped, this, [this]() { ++m_swapped; });
        auto *t = new QTimer(this);
        t->setInterval(5000);
        connect(t, &QTimer::timeout, this, &DirtyProbe::report);
        t->start();
        qInfo() << "[dirty] probe active: report every 5 s";
    }

private:
    static QString describe(QObject *o) {
        if (!o) return QStringLiteral("?");
        // goes up to the first object with a QML id, to give a readable name
        QString cls = QString::fromLatin1(o->metaObject()->className());
        for (QObject *p = o; p; p = p->parent()) {
            if (QQmlContext *c = qmlContext(p)) {
                const QString id = c->nameForObject(p);
                if (!id.isEmpty()) {
                    const QString file = c->baseUrl().fileName();
                    return (p == o) ? QStringLiteral("%1#%2 (%3)").arg(file, id, cls)
                                    : QStringLiteral("%1#%2 > %3").arg(file, id, cls);
                }
            }
        }
        return cls;
    }

    void sample() {
        ++m_frames;
        QQuickWindowPrivate *wp = QQuickWindowPrivate::get(m_win);
        int n = 0;
        for (QQuickItem *it = wp->dirtyItemList; it; it = QQuickItemPrivate::get(it)->nextDirtyItem) {
            ++m_dirty[describe(it)];
            if (++n > 2000) break;
        }
        if (n == 0) ++m_emptyFrames;
    }

    void collectRunning(QObject *o, QStringList &out, int depth = 0) {
        if (!o || depth > 60) return;
        const QMetaObject *mo = o->metaObject();
        bool anim = false;
        for (const QMetaObject *m = mo; m; m = m->superClass()) {
            const char *n = m->className();
            if (!qstrcmp(n, "QQuickAbstractAnimation") || !qstrcmp(n, "QQuickFrameAnimation")) { anim = true; break; }
            if (!qstrcmp(n, "QQmlTimer")) {
                const int iv = o->property("interval").toInt();
                if (o->property("running").toBool() && o->property("repeat").toBool() && iv <= 1000)
                    out << QStringLiteral("Timer %1 ms  %2").arg(iv).arg(describe(o));
                break;
            }
        }
        if (anim && o->property("running").toBool())
            out << QStringLiteral("%1  %2").arg(QString::fromLatin1(mo->className()), describe(o));
        for (QObject *c : o->children()) collectRunning(c, out, depth + 1);
    }

    void report() {
        QList<QPair<int, QString>> v;
        for (auto i = m_dirty.cbegin(); i != m_dirty.cend(); ++i) v.append({i.value(), i.key()});
        std::sort(v.begin(), v.end(), [](const auto &a, const auto &b) { return a.first > b.first; });
        qInfo().noquote() << QStringLiteral("[dirty] last 5 s: %1 frames, %2 drawn, %3 without changed items")
                                 .arg(m_frames).arg(m_swapped).arg(m_emptyFrames);
        for (int i = 0; i < qMin(12, int(v.size())); ++i)
            qInfo().noquote() << QStringLiteral("[dirty]   %1x  %2").arg(v[i].first, 5).arg(v[i].second);
        QStringList running;
        collectRunning(m_root, running);
        running.removeDuplicates();
        for (const QString &r : running.mid(0, 25)) qInfo().noquote() << "[dirty] acceso:" << r;
        m_dirty.clear(); m_frames = m_swapped = m_emptyFrames = 0;
    }

    QQuickWindow *m_win;
    QObject *m_root;
    QHash<QString, int> m_dirty;
    int m_frames = 0, m_swapped = 0, m_emptyFrames = 0;
};
