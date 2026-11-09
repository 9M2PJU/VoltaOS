#!/bin/bash
# Builds VoltaOS-x86_64.AppImage (needs Qt from the official installer in ~/Qt and the build in build/Release).
# Tools: linuxdeploy, linuxdeploy-plugin-qt and appimagetool (download them from GitHub into ~/appimage-tools).
set -e
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
T="${APPIMAGE_TOOLS:-$HOME/appimage-tools}"
QT="$(ls -d "$HOME"/Qt/6.*/gcc_64 | sort -V | tail -1)"
W="$ROOT/build/appimage-work"; A="$W/AppDir"   # on disk, not in /tmp (often small, in RAM)
rm -rf "$W"; mkdir -p "$W"
export APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 QMAKE="$QT/bin/qmake" QML_SOURCES_PATHS="$ROOT/qml"
export PATH="$T:$PATH"

mkdir -p "$A/usr/bin" "$A/usr/share/volta_os"
cp "$ROOT/build/Release/VoltaOS" "$A/usr/bin/"
cp -a "$ROOT/build/Release/VoltaApp" "$A/usr/bin/"          # the app's QML module, next to the executable
for d in services assets third_party scripts i18n; do cp -a "$ROOT/$d" "$A/usr/share/volta_os/"; done
cp "$ROOT/keys.env.example" "$A/usr/share/volta_os/"
cp "$ROOT/packaging/volta-os.png" "$ROOT/packaging/volta-os.desktop" "$ROOT/packaging/AppRun" "$W/"

# fake libraries just to pass linuxdeploy's checks (removed right after)
mkdir "$W/stub"; ln -s /usr/lib/x86_64-linux-gnu/libtiff.so.6 "$W/stub/libtiff.so.5"
echo | gcc -shared -fPIC -x c - -o "$W/stub/libQt6SerialPort.so.6" -Wl,-soname,libQt6SerialPort.so.6
export LD_LIBRARY_PATH="$W/stub:$QT/lib:$ROOT/third_party/maplibre/lib"

cd "$W"
"$T/linuxdeploy-x86_64.AppImage" --appdir AppDir -e AppDir/usr/bin/VoltaOS -d volta-os.desktop \
    -i volta-os.png --plugin qt --custom-apprun AppRun
rm -f "$A/usr/lib/libQt6SerialPort.so.6" "$A/usr/lib/libtiff.so.5" \
      "$A/usr/plugins/imageformats/libqtiff.so" "$A/usr/plugins/position/libqtposition_nmea.so" \
      "$A/usr/libexec/QtWebEngineProcess.debug"
rm -rf "$A/usr/share/doc"
cp "$QT/plugins/platforms/"{libqoffscreen.so,libqwayland.so} "$A/usr/plugins/platforms/"
mkdir -p "$A/usr/plugins/sqldrivers" && cp "$QT/plugins/sqldrivers/libqsqlite.so" "$A/usr/plugins/sqldrivers/"
# compositor-side plugins (wayland-egl + linux-dmabuf): without them the UI does not offer zwp_linux_dmabuf_v1 and gamescope (Arcade) does not start
mkdir -p "$A/usr/plugins/wayland-graphics-integration-server" && cp "$QT/plugins/wayland-graphics-integration-server/"*.so "$A/usr/plugins/wayland-graphics-integration-server/"
mkdir -p "$A/usr/plugins/assetimporters" && cp "$QT/plugins/assetimporters/"*.so "$A/usr/plugins/assetimporters/"   # reads the 3D car's .glb files
for l in icuuc icui18n icudata; do cp -L /usr/lib/x86_64-linux-gnu/lib$l.so.76 "$A/usr/share/volta_os/third_party/maplibre/lib/"; done  # required by the maps plugin
(cd "$A/usr/translations" && ls | grep -vE '_(it|en|es|fr|pt)\.qm$|^qtwebengine_locales$' | xargs -r rm -rf)
chmod -R a+rX "$A"
"$T/appimagetool-x86_64.AppImage" AppDir "$ROOT/VoltaOS-x86_64.AppImage"
rm -rf "$W"
echo "Creato: $ROOT/VoltaOS-x86_64.AppImage"
