#pragma once
#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QVariantList>
#include <QStringList>
#include <QProcess>

// The user's 3D car (.glb). At runtime Qt does not carry the glTF node NAMES to QML, so we
// read them ourselves from the file: the order of the nodes (depth-first visit) matches that of the tree that
// carica RuntimeLoader, e cosi' QML sa quale nodo e' "portiera sinistra", "ruota anteriore destra"...
//
// One model at a time, in ~/.config/volta/car/: auto_<id>.glb + auto_<id>.json (parts chosen in the setup)
// + auto_<id>.meta.json (position/shadow/button adjustments and color). Loading a new one replaces the old one.
// With no car the UI shows the "Load 3D car" button.
class CarModelManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString carFile READ carFile NOTIFY changed)       // .glb file in use (empty = none)
    Q_PROPERTY(bool userCar READ userCar NOTIFY changed)          // true = a user-loaded car exists
    Q_PROPERTY(bool configured READ configured NOTIFY changed)    // true = the guided setup has been done (auto.json exists)
    Q_PROPERTY(int revision READ revision NOTIFY changed)         // goes up at every change (to reload)
    Q_PROPERTY(QVariantList cars READ cars NOTIFY changed)        // auto salvate: [{id, name, file, current}]
    Q_PROPERTY(QString currentId READ currentId NOTIFY changed)
    Q_PROPERTY(bool converting READ converting NOTIFY convertingChanged)   // true while Blender converts the file
public:
    explicit CarModelManager(const QString &projectDir, QObject *parent = nullptr);
    QString carFile() const;
    bool userCar() const;
    bool configured() const;
    int revision() const { return m_rev; }
    QVariantList cars() const;
    QString currentId() const;
    bool converting() const { return m_converting; }

    // Reads the .glb: node names, parents, materials, and the automatic detection of the parts.
    // {ok, error, names[], parents[], mats[][], parts{...}}
    Q_INVOKABLE QVariantMap inspect(const QString &glbPath) const;
    // Parts to use for the current car: auto.json if it exists (user edits), otherwise the detection.
    Q_INVOKABLE QVariantMap currentParts() const;
    // Bounding box of all the meshes inside node `nodeName`, in the node's own system: [minx,miny,minz,maxx,maxy,maxz].
    // Used to work out which side of the hinge the part is on and where to put the hinge if the node has no pivot of its own.
    Q_INVOKABLE QVariantList partBounds(const QString &glbPath, const QString &nodeName) const;
    Q_INVOKABLE bool saveParts(const QVariantMap &parts);
    Q_INVOKABLE void resetParts();
    // Uses the file chosen by the user (copies it to ~/.config/volta/car/). Returns "" if ok, otherwise the reason.
    // If it is not a .glb (.fbx, .obj, .dae, .blend, .gltf...) it first converts it with Blender, in the background:
    // at the end carInstalled() or convertFailed(reason) arrives.
    Q_INVOKABLE QString installCar(const QString &srcPath, bool lighten = false);
    // File weight: {sizeMB, triangles, heavy}. "heavy" = too heavy to run well (warning to the user; with lighten=true it is lightened with Blender).
    Q_INVOKABLE QVariantMap analyze(const QString &srcPath) const;
    Q_INVOKABLE QVariantMap currentMeta() const;             // {name, layout{...}, color, finish}
    Q_INVOKABLE QVariantMap partsFor(const QString &id) const;                          // inspect + parti scelte dell'auto `id`
    Q_INVOKABLE void saveCurrentMeta(const QVariantMap &patch);   // updates only the given keys
    // requested by the Settings (handled by the car scene)
    Q_INVOKABLE void requestAdjust() { emit adjustRequested(); }    // adjust position, size, shadow, buttons
    Q_INVOKABLE void requestSetup() { resetParts(); emit setupRequested(); }   // redo the guided setup
    Q_INVOKABLE void requestReload() { emit reloadRequested(); }    // choose a new .glb file
signals:
    void changed();
    void convertingChanged();
    void convertFailed(const QString &reason);
    void carInstalled();                 // a new model has been loaded (the adjustment restarts from the standard values)
    void partsChanged();                 // the parts chosen in the setup have changed (of some car)
    void currentChanged();               // e' cambiata l'auto in uso (nuovo modello caricato)
    void adjustRequested();
    void setupRequested();
    void reloadRequested();
private:
    QString m_project;
    int m_rev = 0;
    bool m_converting = false;
    QProcess *m_proc = nullptr;
    QString m_convOut;
    QString finishInstall(const QString &glb, const QString &displayName);
    QString m_pendingName;
    QString m_currentId;
    QStringList carIds() const;                               // from the oldest to the newest
    QString fileOf(const QString &id) const;
    QString metaPath(const QString &id) const;
    QVariantMap metaOf(const QString &id) const;
    QString userDir() const;
    static QString sidecarFor(const QString &glb);
};
