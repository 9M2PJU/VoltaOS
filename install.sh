#!/bin/bash
# Guided installation of Volta OS (Debian / Ubuntu).
# Usage:  ./install.sh
set -e
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$DIR"

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
die() { printf '\n\033[1;31mError: %s\033[0m\n' "$1" >&2; exit 1; }

command -v apt >/dev/null || die "Debian or Ubuntu required (apt not found)."
[ "$(id -u)" -eq 0 ] && die "do not run it as root: it asks for the password only when needed."

# Qt: if installed with the official installer in ~/Qt it uses that, otherwise it uses the system packages
QTPREFIX=""
if [ -d "$HOME/Qt" ]; then
    QTPREFIX=$(ls -d "$HOME"/Qt/6.*/gcc_64 2>/dev/null | sort -V | tail -1 || true)
fi

say "1/4  System packages (asks for the password)"
PKGS="build-essential cmake pkg-config git mpv libwayland-dev wayland-protocols libx11-dev \
libusb-1.0-0-dev libavcodec-dev libavutil-dev python3 python3-pip python3-dbus python3-gi network-manager bluez pipewire-pulse"
if [ -z "$QTPREFIX" ]; then
    PKGS="$PKGS qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-declarative-private-dev qt6-quick3d-dev \
qt6-webengine-dev qt6-multimedia-dev qt6-websockets-dev qt6-positioning-dev qt6-location-dev \
qt6-virtualkeyboard-dev qt6-wayland-dev qt6-tools-dev qt6-l10n-tools libqt6opengl6-dev \
qml6-module-qtquick-controls qml6-module-qtquick3d qml6-module-qtwebengine"
fi
sudo apt update
sudo apt install -y $PKGS

say "2/4  Python libraries"
pip install --user --break-system-packages -r requirements.txt \
    || pip install --user -r requirements.txt

say "3/4  Building (it can take several minutes)"
CMAKE_ARGS="-DCMAKE_BUILD_TYPE=Release"
[ -n "$QTPREFIX" ] && CMAKE_ARGS="$CMAKE_ARGS -DCMAKE_PREFIX_PATH=$QTPREFIX"
cmake -B build/Release $CMAKE_ARGS
cmake --build build/Release -j"$(nproc)"

say "4/4  Icon in the applications menu"
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/volta-os.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Volta OS
Comment=In-car interface
Exec=$DIR/start.sh
Terminal=false
Categories=Utility;
DESK

say "Done!"
echo "Start it from the applications menu (Volta OS) or with:  ./start.sh"
echo "On first launch the guided setup helps you create the free keys."
