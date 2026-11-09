# MapLibre precompilato

Plugin **MapLibre per Qt Location** già compilato, così non serve costruirlo da zero.
Sorgenti: https://github.com/maplibre/maplibre-native-qt (versione `v3.0.0-52-g7da5c15`, 22 luglio 2026).

Compilato per **Qt 6.11.1**, Linux x86_64 (Debian 13). Con un'altra versione di Qt o
un'altra distribuzione può non partire: in quel caso compilalo tu e installa in
`/usr/local` (VoltaOS usa quello se questa cartella non funziona).

Struttura (VoltaOS la carica da solo, non va installato niente):

- `lib/` librerie `libQMapLibre*`
- `qml/MapLibre/` modulo QML
- `plugins/geoservices/` plugin dei servizi mappa

Licenze in `licenses/` (BSD-2-Clause e relative a MapLibre Native).
