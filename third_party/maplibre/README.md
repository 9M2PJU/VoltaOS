# Prebuilt MapLibre

The **MapLibre plugin for Qt Location**, already built, so you do not have to build it from scratch.
Source: https://github.com/maplibre/maplibre-native-qt (version `v3.0.0-52-g7da5c15`, 22 July 2026).

Built for **Qt 6.11.1**, Linux x86_64 (Debian 13). With a different Qt version or
another distribution it may not start: in that case build it yourself and install it in
`/usr/local` (VoltaOS uses that one if this folder does not work).

Structure (VoltaOS loads it by itself, nothing has to be installed):

- `lib/` the `libQMapLibre*` libraries
- `qml/MapLibre/` the QML module
- `plugins/geoservices/` the map services plugin

Licenses are in `licenses/` (BSD-2-Clause and the MapLibre Native ones).
