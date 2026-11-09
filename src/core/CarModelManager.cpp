#include "CarModelManager.h"
#include <QDateTime>
#include <QStandardPaths>
#include <QTimer>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QtEndian>
#include <QMatrix4x4>
#include <QQuaternion>
#include <QVector3D>
#include <functional>
#include <algorithm>

static bool stripAnimations(const QString &path);

CarModelManager::CarModelManager(const QString &projectDir, QObject *parent)
    : QObject(parent), m_project(projectDir)
{
    QFile cur(userDir() + QStringLiteral("/current"));
    if (cur.open(QIODevice::ReadOnly)) m_currentId = QString::fromUtf8(cur.readAll()).trimmed();
    for (const QString &id : carIds()) stripAnimations(fileOf(id));       // cars loaded with a previous version
}

QString CarModelManager::userDir() const { return QDir::homePath() + QStringLiteral("/.config/volta/car"); }
QString CarModelManager::sidecarFor(const QString &glb)
{
    return glb.left(glb.length() - (glb.endsWith(QLatin1String(".glb"), Qt::CaseInsensitive) ? 4 : 0)) + QStringLiteral(".json");
}
// Each car has its own file name (auto_<instant>.glb): so the scene sees a new path and really reloads the model.
QStringList CarModelManager::carIds() const
{
    QStringList out;
    const QFileInfoList l = QDir(userDir()).entryInfoList({QStringLiteral("auto*.glb")}, QDir::Files);
    for (const QFileInfo &fi : l) out << fi.completeBaseName();
    // stable order: from the oldest to the newest according to the instant written in the name (not the file's date, which changes if the file is rewritten)
    std::sort(out.begin(), out.end(), [](const QString &a, const QString &b) { return a.size() != b.size() ? a.size() < b.size() : a < b; });
    return out;
}
QString CarModelManager::fileOf(const QString &id) const { return userDir() + QLatin1Char('/') + id + QStringLiteral(".glb"); }
QString CarModelManager::metaPath(const QString &id) const { return userDir() + QLatin1Char('/') + id + QStringLiteral(".meta.json"); }
QString CarModelManager::currentId() const
{
    const QStringList ids = carIds();
    if (ids.isEmpty()) return QString();
    return ids.contains(m_currentId) ? m_currentId : ids.last();       // no choice: the most recent
}
QString CarModelManager::carFile() const { const QString id = currentId(); return id.isEmpty() ? QString() : fileOf(id); }
bool CarModelManager::userCar() const { return !carFile().isEmpty(); }
bool CarModelManager::configured() const { const QString f = carFile(); return !f.isEmpty() && QFileInfo::exists(sidecarFor(f)); }
QVariantMap CarModelManager::metaOf(const QString &id) const
{
    QFile f(metaPath(id));
    if (!f.open(QIODevice::ReadOnly)) return {};
    return QJsonDocument::fromJson(f.readAll()).object().toVariantMap();
}
QVariantList CarModelManager::cars() const
{
    QVariantList out;
    const QString cur = currentId();
    for (const QString &id : carIds()) {
        QVariantMap m;
        m["id"] = id; m["file"] = fileOf(id); m["current"] = (id == cur);
        const QString nm = metaOf(id).value(QStringLiteral("name")).toString();
        m["name"] = nm.isEmpty() ? id : nm;
        out << m;
    }
    return out;
}
QVariantMap CarModelManager::currentMeta() const { const QString id = currentId(); return id.isEmpty() ? QVariantMap() : metaOf(id); }
void CarModelManager::saveCurrentMeta(const QVariantMap &patch)
{
    const QString id = currentId();
    if (id.isEmpty()) return;
    QVariantMap m = metaOf(id);
    for (auto it = patch.begin(); it != patch.end(); ++it) m[it.key()] = it.value();
    QFile f(metaPath(id));
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) f.write(QJsonDocument(QJsonObject::fromVariantMap(m)).toJson(QJsonDocument::Compact));
    // no emit: these are adjustments, the scene already knows them
}
// Some models have animations inside the file (e.g. "Front left door", "Open all doors"): Qt starts them by itself and they keep moving
// doors and trunk, against the UI's commands. They are removed from our copy of the file (the original is not touched).
static bool stripAnimations(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return false;
    const QByteArray data = f.readAll();
    f.close();
    if (data.size() < 28 || data.left(4) != "glTF") return false;
    const quint32 len = qFromLittleEndian<quint32>(reinterpret_cast<const uchar *>(data.constData()) + 12);
    if (len == 0 || 20 + qint64(len) > data.size() || data.mid(16, 4) != "JSON") return false;
    QJsonObject obj = QJsonDocument::fromJson(data.mid(20, len)).object();
    if (!obj.contains(QStringLiteral("animations"))) return false;
    obj.remove(QStringLiteral("animations"));
    QByteArray js = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    while (js.size() % 4) js.append(' ');
    const QByteArray rest = data.mid(20 + int(len));            // the binary block (and what follows) stays as it is
    QByteArray out;
    out.reserve(20 + js.size() + rest.size());
    auto le32 = [](quint32 v) { QByteArray b(4, 0); qToLittleEndian(v, reinterpret_cast<uchar *>(b.data())); return b; };
    out += "glTF"; out += le32(2); out += le32(quint32(12 + 8 + js.size() + rest.size()));
    out += le32(quint32(js.size())); out += "JSON"; out += js; out += rest;
    QSaveFile w(path);
    if (!w.open(QIODevice::WriteOnly)) return false;
    w.write(out);
    return w.commit();
}


// ── reading the .glb file ─────────────────────────────────────────────────────
static bool readGlbJson(const QString &path, QJsonObject &out, QString &err)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) { err = QObject::tr("File not readable."); return false; }
    const QByteArray head = f.read(20);
    if (head.size() < 20 || head.left(4) != "glTF") { err = QObject::tr("Not a valid .glb file."); return false; }
    const quint32 len = qFromLittleEndian<quint32>(reinterpret_cast<const uchar *>(head.constData()) + 12);
    if (len == 0 || len > 64u * 1024 * 1024 || head.mid(16, 4) != "JSON") { err = QObject::tr("Invalid .glb file."); return false; }
    const QByteArray js = f.read(len);
    QJsonParseError pe;
    const QJsonDocument d = QJsonDocument::fromJson(js, &pe);
    if (!d.isObject()) { err = QObject::tr("Damaged .glb file."); return false; }
    out = d.object();
    return true;
}

// ── nomi: "BodyDoorLColor1", "door_fl", "Door.L.001", "LeftDoor" -> parole minuscole ──
static QStringList tokens(const QString &name)
{
    QString s;
    for (int i = 0; i < name.size(); ++i) {
        const QChar c = name[i];
        if (!c.isLetterOrNumber()) { s += ' '; continue; }
        if (i > 0 && name[i - 1].isLower() && c.isUpper()) s += ' ';                       // doorFL -> door FL
        if (i > 0 && name[i - 1].isUpper() && c.isUpper() && i + 1 < name.size() && name[i + 1].isLower()) s += ' ';
        if (i > 0 && name[i - 1].isLetter() && c.isDigit()) s += ' ';
        s += c;
    }
    return s.toLower().split(' ', Qt::SkipEmptyParts);
}
static bool has(const QStringList &t, std::initializer_list<const char *> words)
{
    for (const char *w : words) if (t.contains(QLatin1String(w))) return true;
    return false;
}
// 'L' left, 'R' right, 0 unclear
static QChar sideOf(const QStringList &t)
{
    if (has(t, {"l", "left", "sx", "izq", "links", "gauche", "fl", "rl", "lf", "lr", "lh"})) return 'L';
    if (has(t, {"r", "right", "dx", "der", "rechts", "droite", "fr", "rr", "rf", "rh"})) return 'R';
    return QChar();
}
// 'F' front, 'B' back, 0 unclear
static QChar rowOf(const QStringList &t)
{
    if (has(t, {"front", "fwd", "ant", "anteriore", "avant", "vorne", "fl", "fr", "lf", "rf"})) return 'F';
    if (has(t, {"rear", "back", "post", "posteriore", "arriere", "hinten", "rl", "rr", "lr", "rh2"})) return 'B';
    return QChar();
}
static bool isDoorName(const QStringList &t)    { return has(t, {"door", "doors", "portiera", "porta", "puerta", "porte", "tur", "tuer"}); }
static bool isWheelName(const QStringList &t)   { return has(t, {"wheel", "wheels", "ruota", "rueda", "roue", "rad"}); }
static bool isHoodName(const QStringList &t)    { return has(t, {"hood", "bonnet", "cofano", "capot", "motorhaube", "frunk"}); }
static bool isTrunkName(const QStringList &t)   { return has(t, {"trunk", "boot", "tailgate", "liftgate", "hatch", "baule", "portellone", "coffre"}); }
static bool isMinorPart(const QStringList &t)   { return has(t, {"handle", "mirror", "window", "glass", "gasket", "seal", "sealing", "lock", "trim", "light", "lamp", "disc", "pad", "brake", "tire", "tyre", "rim", "limiter", "hinge", "hyd", "hydraulic", "shadowcap", "cap", "strut", "damper", "caliper", "airbag", "speaker"}); }

static QMatrix4x4 localMatrix(const QJsonObject &n)
{
    QMatrix4x4 m;
    if (n.contains("matrix")) {
        const QJsonArray a = n["matrix"].toArray();
        if (a.size() == 16) {
            float v[16]; for (int i = 0; i < 16; ++i) v[i] = float(a[i].toDouble());
            return QMatrix4x4(v).transposed();      // glTF is column-major, QMatrix4x4 row-major
        }
        return m;
    }
    if (n.contains("translation")) { const QJsonArray t = n["translation"].toArray(); m.translate(float(t[0].toDouble()), float(t[1].toDouble()), float(t[2].toDouble())); }
    if (n.contains("rotation")) { const QJsonArray r = n["rotation"].toArray(); m.rotate(QQuaternion(float(r[3].toDouble(1)), float(r[0].toDouble()), float(r[1].toDouble()), float(r[2].toDouble()))); }
    if (n.contains("scale")) { const QJsonArray c = n["scale"].toArray(); m.scale(float(c[0].toDouble(1)), float(c[1].toDouble(1)), float(c[2].toDouble(1))); }
    return m;
}

QVariantMap CarModelManager::inspect(const QString &glbPath) const
{
    QVariantMap res;
    QJsonObject j; QString err;
    if (!readGlbJson(glbPath, j, err)) { res["ok"] = false; res["error"] = err; return res; }

    const QJsonArray nodes = j["nodes"].toArray(), meshes = j["meshes"].toArray(), mats = j["materials"].toArray();
    const QJsonArray scenes = j["scenes"].toArray();
    if (nodes.isEmpty() || scenes.isEmpty()) { res["ok"] = false; res["error"] = tr("The file does not contain a car (no scene)."); return res; }

    // depth-first visit from the scene (same order as the RuntimeLoader tree)
    QStringList names; QList<int> parents; QVariantList hasMesh, matLists; QList<int> order;
    std::function<void(int, int)> walk = [&](int idx, int parentFlat) {
        if (idx < 0 || idx >= nodes.size() || order.size() > 20000) return;
        const QJsonObject n = nodes[idx].toObject();
        const int flat = order.size();
        order << idx;
        names << n["name"].toString();
        parents << parentFlat;
        QStringList ml;
        bool mesh = n.contains("mesh");
        if (mesh) {
            const QJsonArray prims = meshes[n["mesh"].toInt()].toObject()["primitives"].toArray();
            for (const QJsonValue &p : prims) {
                const QJsonObject po = p.toObject();
                ml << (po.contains("material") ? mats[po["material"].toInt()].toObject()["name"].toString() : QString());
            }
        }
        hasMesh << mesh; matLists << QVariant(ml);
        for (const QJsonValue &c : n["children"].toArray()) walk(c.toInt(), flat);
    };
    const int sceneIdx = j["scene"].toInt(0);
    for (const QJsonValue &r : scenes[sceneIdx].toObject()["nodes"].toArray()) walk(r.toInt(), -1);

    const int N = names.size();
    // ── part detection ──
    QList<QStringList> tk; for (const QString &n : names) tk << tokens(n);
    auto ancestorMatches = [&](int i, auto pred) {
        for (int p = parents[i]; p >= 0; p = parents[p]) if (pred(tk[p])) return true;
        return false;
    };
    // a node has a "pivot" if its position is not the origin: that is where the hinge (door, hood) or the axis (wheel) is
    QList<bool> pivot;
    for (int i = 0; i < N; ++i) {
        const QMatrix4x4 m = localMatrix(nodes[order[i]].toObject());
        pivot << (m.map(QVector3D(0, 0, 0)).length() > 1e-3f);
    }
    // all the nodes "of that kind" (door, hood...): the pivot is searched by going up from the node to one with its own position
    // (e.g. "RearHatch" inside the whole tailgate -> the tailgate is taken). If more than one is found (outer door +
    // inner door) they all move together.
    auto pickAll = [&](auto isKind, QChar side, QChar row, bool rowDefaultFront) -> QStringList {
        bool rowsExist = false;
        for (int i = 0; i < N; ++i) if (isKind(tk[i]) && rowOf(tk[i]).unicode()) { rowsExist = true; break; }
        QSet<int> C;
        for (int i = 0; i < N; ++i) {
            if (!isKind(tk[i]) || isMinorPart(tk[i]) || names[i].isEmpty()) continue;
            if (side.unicode() && sideOf(tk[i]) != side) continue;
            if (row.unicode()) {
                const QChar r = rowOf(tk[i]);
                if (r.unicode() ? r != row : !(rowDefaultFront && row == 'F' && !rowsExist)) continue;
            }
            int j = i;
            if (has(tk[i], {"interior", "int", "inner"})) {
                // "interior" piece inside the real one (e.g. InteriorRearHatch inside the tailgate): the piece that contains it is moved
                int a = parents[i];
                while (a >= 0 && !pivot[a]) a = parents[a];
                if (a >= 0 && !has(tk[a], {"interior", "int", "inner"})) j = a;
            }
            while (j >= 0 && !pivot[j]) j = parents[j];
            if (j < 0) continue;
            C.insert(j);
        }
        // if there are pieces containing other meshes (door, tailgate) the single meshes that only share the same name are discarded
        bool anyKids = false;
        for (int i : C) { for (int k = 0; k < N; ++k) if (parents[k] == i) { anyKids = true; break; } if (anyKids) break; }
        if (anyKids) {
            QSet<int> keep;
            for (int i : C) { bool kids = false; for (int k = 0; k < N; ++k) if (parents[k] == i) { kids = true; break; } if (kids) keep.insert(i); }
            C = keep;
        }
        QStringList out;
        for (int i = 0; i < N; ++i) {
            if (!C.contains(i)) continue;
            bool covered = false;
            for (int p = parents[i]; p >= 0; p = parents[p]) if (C.contains(p)) { covered = true; break; }
            if (!covered) out << names[i];
        }
        return out;
    };
    QVariantMap parts;
    parts["doorL"] = pickAll(isDoorName, 'L', 'F', true);
    parts["doorR"] = pickAll(isDoorName, 'R', 'F', true);
    parts["doorRL"] = pickAll(isDoorName, 'L', 'B', false);
    parts["doorRR"] = pickAll(isDoorName, 'R', 'B', false);
    parts["hood"] = pickAll(isHoodName, QChar(), QChar(), false);
    parts["trunk"] = pickAll(isTrunkName, QChar(), QChar(), false);
    // wheels: nodes with side and row (FL, FR, RL, RR) that are in a "wheels" group or are called "wheel", with the pivot on the axis
    QStringList wheelsFound;
    for (int i = 0; i < N; ++i) {
        if (!pivot[i] || isMinorPart(tk[i]) || names[i].isEmpty()) continue;
        if (!(isWheelName(tk[i]) || ancestorMatches(i, isWheelName))) continue;
        if (!sideOf(tk[i]).unicode() || !rowOf(tk[i]).unicode()) continue;
        bool covered = false;
        for (int p = parents[i]; p >= 0; p = parents[p]) if (wheelsFound.contains(names[p])) { covered = true; break; }
        if (!covered) wheelsFound << names[i];
    }
    parts["wheels"] = wheelsFound;
    // paint: materials with "paint" in the name; if there are several kinds (Paint 1 / Paint 2) the "1" one is the body
    QStringList paintAll, paint1;
    QSet<QString> seen;
    for (int i = 0; i < N; ++i)
        for (const QString &m : matLists[i].toStringList()) {
            if (m.isEmpty() || seen.contains(m)) continue;
            seen.insert(m);
            const QStringList t = tokens(m);
            if (has(t, {"paint", "carpaint", "vernice", "lacquer", "bodywork", "pittura"}) || (t.contains("body") && t.contains("color"))) {
                paintAll << m;
                if (t.contains("1") || has(t, {"primary", "main", "body"})) paint1 << m;
            }
        }
    // the part's name can also say "paint" (e.g. "Ext Body#Car Paint"): if so, the paint materials are its own
    QStringList paintByNode;
    for (int i = 0; i < N; ++i)
        if (has(tk[i], {"paint", "carpaint", "vernice", "lacquer", "pittura"}))
            for (const QString &m : matLists[i].toStringList()) if (!m.isEmpty() && !paintByNode.contains(m)) paintByNode << m;
    parts["paint"] = !paintByNode.isEmpty() ? paintByNode : (paint1.isEmpty() ? paintAll : paint1);

    // data for the mesh list in the setup: depth, front/rear row, pivot
    QVariantList depths, rows, pivots;
    for (int i = 0; i < N; ++i) {
        int d = 0; for (int p = parents[i]; p >= 0; p = parents[p]) ++d;
        depths << d; rows << QString(rowOf(tk[i])); pivots << bool(pivot[i]);
    }
    res["depths"] = depths; res["rows"] = rows; res["pivots"] = pivots;
    // materials (names) to choose the paint by hand
    QStringList matNames;
    for (int i = 0; i < N; ++i) for (const QString &m : matLists[i].toStringList()) if (!m.isEmpty() && !matNames.contains(m)) matNames << m;
    res["materialNames"] = matNames;

    res["ok"] = true; res["error"] = QString();
    res["names"] = names; res["parents"] = QVariant::fromValue(QList<int>(parents)).toList();
    res["hasMesh"] = hasMesh; res["mats"] = matLists; res["parts"] = parts;
    res["count"] = N;
    return res;
}

QVariantList CarModelManager::partBounds(const QString &glbPath, const QString &nodeName) const
{
    QJsonObject j; QString err;
    if (!readGlbJson(glbPath, j, err)) return {};
    const QJsonArray nodes = j["nodes"].toArray(), meshes = j["meshes"].toArray(), acc = j["accessors"].toArray();
    const QJsonArray scenes = j["scenes"].toArray();
    if (scenes.isEmpty()) return {};
    int found = -1; int guard = 0;
    std::function<void(int)> find = [&](int idx) {
        if (found >= 0 || idx < 0 || idx >= nodes.size() || ++guard > 20000) return;
        const QJsonObject n = nodes[idx].toObject();
        if (n["name"].toString() == nodeName) { found = idx; return; }
        for (const QJsonValue &c : n["children"].toArray()) find(c.toInt());
    };
    for (const QJsonValue &r : scenes[j["scene"].toInt(0)].toObject()["nodes"].toArray()) find(r.toInt());
    if (found < 0) return {};

    QVector3D uLo(1e30f, 1e30f, 1e30f), uHi(-1e30f, -1e30f, -1e30f); bool any = false;
    guard = 0;
    std::function<void(int, QMatrix4x4)> visit = [&](int idx, QMatrix4x4 M) {
        if (idx < 0 || idx >= nodes.size() || ++guard > 20000) return;
        const QJsonObject n = nodes[idx].toObject();
        if (n.contains("mesh")) {
            for (const QJsonValue &p : meshes[n["mesh"].toInt()].toObject()["primitives"].toArray()) {
                const int ai = p.toObject()["attributes"].toObject()["POSITION"].toInt(-1);
                if (ai < 0 || ai >= acc.size()) continue;
                const QJsonArray mn = acc[ai].toObject()["min"].toArray(), mx = acc[ai].toObject()["max"].toArray();
                if (mn.size() < 3 || mx.size() < 3) continue;
                QVector3D lo(1e30f, 1e30f, 1e30f), hi(-1e30f, -1e30f, -1e30f);
                for (int c = 0; c < 8; ++c) {
                    const QVector3D q = M.map(QVector3D(float((c & 1 ? mx : mn)[0].toDouble()), float((c & 2 ? mx : mn)[1].toDouble()), float((c & 4 ? mx : mn)[2].toDouble())));
                    lo = QVector3D(qMin(lo.x(), q.x()), qMin(lo.y(), q.y()), qMin(lo.z(), q.z()));
                    hi = QVector3D(qMax(hi.x(), q.x()), qMax(hi.y(), q.y()), qMax(hi.z(), q.z()));
                }
                uLo = QVector3D(qMin(uLo.x(), lo.x()), qMin(uLo.y(), lo.y()), qMin(uLo.z(), lo.z()));
                uHi = QVector3D(qMax(uHi.x(), hi.x()), qMax(uHi.y(), hi.y()), qMax(uHi.z(), hi.z()));
                any = true;
            }
        }
        for (const QJsonValue &c : n["children"].toArray()) {
            const int ci = c.toInt();
            if (ci >= 0 && ci < nodes.size()) visit(ci, M * localMatrix(nodes[ci].toObject()));
        }
    };
    visit(found, QMatrix4x4());       // the node itself: local system = identity
    if (!any) return {};
    return { uLo.x(), uLo.y(), uLo.z(), uHi.x(), uHi.y(), uHi.z() };
}

QVariantMap CarModelManager::partsFor(const QString &id) const
{
    if (id.isEmpty()) return {};
    const QString f = fileOf(id);
    if (!QFileInfo::exists(f)) return {};
    QFile sc(sidecarFor(f));
    QVariantMap detected = inspect(f);
    if (sc.open(QIODevice::ReadOnly)) {
        const QJsonDocument d = QJsonDocument::fromJson(sc.readAll());
        if (d.isObject()) {
            QVariantMap saved = d.object().toVariantMap();
            for (auto it = saved.begin(); it != saved.end(); ++it) {     // the user's file wins over the detection
                QVariantMap p = detected["parts"].toMap();
                p[it.key()] = it.value();
                detected["parts"] = p;
            }
        }
    }
    return detected;
}

QVariantMap CarModelManager::currentParts() const { return partsFor(currentId()); }

bool CarModelManager::saveParts(const QVariantMap &parts)
{
    const QString f = carFile();
    if (f.isEmpty()) return false;
    QFile sc(sidecarFor(f));
    if (!sc.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    sc.write(QJsonDocument(QJsonObject::fromVariantMap(parts)).toJson());
    ++m_rev; emit changed(); emit partsChanged();
    return true;
}

void CarModelManager::resetParts()
{
    if (userCar()) QFile::remove(sidecarFor(carFile()));
    ++m_rev; emit changed(); emit partsChanged();
}

// How heavy a model is: file size and number of triangles (sum of all the meshes used by the nodes).
QVariantMap CarModelManager::analyze(const QString &srcPath) const
{
    QString p = srcPath;
    if (p.startsWith(QLatin1String("file://"))) p = p.mid(7);
    QVariantMap r;
    const double mb = QFileInfo(p).size() / 1048576.0;
    r["sizeMB"] = mb; r["triangles"] = 0; r["heavy"] = false;
    qint64 tris = 0;
    QJsonObject j; QString err;
    if (p.endsWith(QLatin1String(".glb"), Qt::CaseInsensitive) && readGlbJson(p, j, err)) {
        const QJsonArray nodes = j["nodes"].toArray(), meshes = j["meshes"].toArray(), acc = j["accessors"].toArray();
        QHash<int, qint64> meshTris;
        for (int m = 0; m < meshes.size(); ++m) {
            qint64 t = 0;
            for (const QJsonValue &pv : meshes[m].toObject()["primitives"].toArray()) {
                const QJsonObject po = pv.toObject();
                int ai = po.contains("indices") ? po["indices"].toInt(-1) : po["attributes"].toObject()["POSITION"].toInt(-1);
                if (ai >= 0 && ai < acc.size()) t += acc[ai].toObject()["count"].toInt() / 3;
            }
            meshTris[m] = t;
        }
        for (const QJsonValue &nv : nodes) { const QJsonObject n = nv.toObject(); if (n.contains("mesh")) tris += meshTris.value(n["mesh"].toInt()); }
    }
    r["triangles"] = double(tris);
    r["heavy"] = (mb > 40.0) || (tris > 700000);        // thresholds: the Mercedes tried was far above
    return r;
}

QString CarModelManager::finishInstall(const QString &p, const QString &displayName)
{
    QJsonObject j; QString err;
    if (!readGlbJson(p, j, err)) return err;
    if (QFileInfo(p).size() > 200LL * 1024 * 1024) return tr("The file is too large (maximum 200 MB).");
    QDir().mkpath(userDir());
    // one model at a time: the new one takes the place of the old one
    for (const QString &old : carIds()) { QFile::remove(fileOf(old)); QFile::remove(sidecarFor(fileOf(old))); QFile::remove(metaPath(old)); }
    const QString id = QStringLiteral("auto_") + QString::number(QDateTime::currentMSecsSinceEpoch());
    const QString dst = fileOf(id);
    if (!QFile::copy(p, dst)) return tr("Unable to copy the file.");
    stripAnimations(dst);
    QFile mf(metaPath(id));
    if (mf.open(QIODevice::WriteOnly)) mf.write(QJsonDocument(QJsonObject{{QStringLiteral("name"), displayName}}).toJson(QJsonDocument::Compact));
    m_currentId = id;
    QFile cf(userDir() + QStringLiteral("/current"));
    if (cf.open(QIODevice::WriteOnly | QIODevice::Truncate)) cf.write(id.toUtf8());
    ++m_rev; emit changed(); emit partsChanged(); emit carInstalled(); emit currentChanged();
    return QString();
}

QString CarModelManager::installCar(const QString &srcPath, bool lighten)
{
    QString p = srcPath;
    if (p.startsWith(QLatin1String("file://"))) p = p.mid(7);
    if (m_converting) return tr("A conversion is already in progress.");
    if (!QFileInfo::exists(p)) return tr("File not found.");
    const QString shownName = QFileInfo(p).completeBaseName();
    if (!lighten && p.endsWith(QLatin1String(".glb"), Qt::CaseInsensitive)) return finishInstall(p, shownName);
    m_pendingName = shownName;

    // other formats: converted with Blender (free, blender.org)
    const QString blender = QStandardPaths::findExecutable(QStringLiteral("blender"));
    if (blender.isEmpty())
        return tr("This format requires Blender (free, blender.org): install it and try again. Or load a .glb file.");
    const QString script = m_project + QStringLiteral("/scripts/convert_to_glb.py");
    if (!QFileInfo::exists(script)) return tr("The converter is missing (scripts/convert_to_glb.py).");
    const QString tmp = QDir::tempPath() + QStringLiteral("/volta_conv_") + QString::number(QDateTime::currentMSecsSinceEpoch()) + QStringLiteral(".glb");
    m_convOut = tmp;
    m_proc = new QProcess(this);
    m_proc->setProcessChannelMode(QProcess::MergedChannels);
    // lightening can take a while: 10 minutes at most
    connect(m_proc, &QProcess::finished, this, [this](int code, QProcess::ExitStatus st) {
        const QString out = QString::fromUtf8(m_proc->readAll());
        m_proc->deleteLater(); m_proc = nullptr;
        m_converting = false; emit convertingChanged();
        QString err;
        if (st != QProcess::NormalExit || code != 0 || !QFileInfo::exists(m_convOut)) {
            QString why = tr("Conversion failed.");
            if (out.contains(QLatin1String("no 3D shape"))) why = tr("The file does not contain any 3D shape.");
            else if (out.contains(QLatin1String("error opening"))) why = tr("Blender cannot open this file.");
            emit convertFailed(why);
        } else {
            err = finishInstall(m_convOut, m_pendingName);
            if (!err.isEmpty()) emit convertFailed(err);
        }
        QFile::remove(m_convOut);
    });
    connect(m_proc, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) { m_converting = false; emit convertingChanged(); emit convertFailed(tr("I cannot start Blender.")); }
    });
    m_converting = true; emit convertingChanged();
    QStringList args{QStringLiteral("-b"), QStringLiteral("-noaudio"), QStringLiteral("--python"), script, QStringLiteral("--"), p, tmp};
    if (lighten) args << QStringLiteral("--lighten");
    m_proc->start(blender, args);
    QTimer::singleShot((lighten ? 10 : 5) * 60 * 1000, m_proc, [this]() { if (m_proc) m_proc->kill(); });
    return QString();
}

