#!/bin/bash
# Volta OS remote installer (1-liner).
#
#   curl -fsSL https://raw.githubusercontent.com/Omardigio/VoltaOS/main/scripts/install-remote.sh | bash
#
# What it does:
#   1. detects the distro (apt / dnf / pacman / zypper),
#   2. installs the runtime deps (same list as docs/installation.md),
#   3. downloads the latest GitHub release asset (.deb / .rpm / AppImage),
#   4. installs it + the Python service deps from requirements.txt.
#
# Options (env or args):
#   --tag v1.0        install a specific release tag instead of latest
#   --method deb|rpm|appimage   force asset type (default: auto by distro)
#   --uninstall       remove an AppImage install from ~/.local/bin
#   VOLTA_REPO=Owner/Repo  use a fork instead of Omardigio/VoltaOS
set -euo pipefail

REPO="${VOLTA_REPO:-Omardigio/VoltaOS}"
TAG=""
METHOD="auto"

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
die() { printf '\n\033[1;31mError: %s\033[0m\n' "$1" >&2; exit 1; }

usage() {
    grep '^#' "$0" | cut -c3-
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --tag) TAG="${2:-}"; shift 2 ;;
        --method) METHOD="${2:-}"; shift 2 ;;
        --uninstall)
            rm -f "$HOME/.local/bin/VoltaOS-"*.AppImage "$HOME/.local/bin/VoltaOS.AppImage" \
                "$HOME/.local/share/applications/volta-os.desktop"
            echo "Volta OS AppImage install removed."
            exit 0 ;;
        -h|--help) usage ;;
        *) die "unknown argument: $1 (see --help)" ;;
    esac
done

[ -f /etc/os-release ] && . /etc/os-release
DIST_ID="${ID:-unknown} ${ID_LIKE:-}"
PKG_MGR=""
case "$DIST_ID" in
    *apt*|*debian*|*ubuntu*|*linuxmint*|*pop*) PKG_MGR="apt" ;;
    *fedora*|*rhel*|*centos*|*rocky*|*alma*|*opensuse*|*suse*)
        command -v dnf >/dev/null 2>&1 && PKG_MGR="dnf" || PKG_MGR="zypper" ;;
    *arch*|*manjaro*|*endeavour*|*cachy*) PKG_MGR="pacman" ;;
esac
[ -n "$PKG_MGR" ] || die "unsupported distro ($DIST_ID): install the AppImage manually, see docs/installation.md"

if [ "$METHOD" = "auto" ]; then
    case "$PKG_MGR" in
        apt) METHOD="deb" ;;
        dnf|zypper) METHOD="rpm" ;;
        *) METHOD="appimage" ;;  # Arch users: prefer the AUR package volta-os-bin
    esac
fi

say "1/4  System packages ($PKG_MGR)"
case "$PKG_MGR" in
    apt)
        sudo apt update
        sudo apt install -y libgl1 libegl1 libopengl0 libgbm1 libdrm2 libx11-6 libx11-xcb1 \
            libxcb1 libxcb-dri3-0 libxcb-cursor0 libfontconfig1 libfreetype6 libexpat1 \
            libwayland-client0 libwayland-server0 libasound2t64 libusb-1.0-0 libcom-err2 libfuse2t64 \
            python3 python3-pip python3-dbus python3-gi mpv network-manager \
            bluez bluez-obexd pipewire-pulse pulseaudio-utils curl ;;
    dnf)
        sudo dnf install -y mesa-libGL mesa-libEGL libX11 libxcb fontconfig freetype \
            wayland alsa-lib libusb1 mpv python3 python3-pip python3-dbus python3-gobject \
            NetworkManager bluez bluez-obexd pipewire-pulseaudio curl fuse ;;
    zypper)
        sudo zypper install -y Mesa-libGL1 Mesa-libEGL1 libX11-6 fontconfig freetype2 \
            wayland alsa libusb-1_0-0 mpv python3 python3-pip NetworkManager bluez \
            pipewire-pulseaudio curl ;;
    pacman)
        sudo pacman -Sy --needed --noconfirm mesa libgl libx11 libxcb fontconfig freetype2 \
            wayland alsa-lib libusb mpv python python-pip networkmanager bluez bluez-utils \
            pipewire-pulse curl fuse2 ;;
esac

say "2/4  Python service libraries"
if command -v pip3 >/dev/null 2>&1; then PIP=pip3; else PIP=pip; fi
"$PIP" install --user --break-system-packages -r "https://raw.githubusercontent.com/$REPO/main/requirements.txt" \
    || "$PIP" install --user -r "https://raw.githubusercontent.com/$REPO/main/requirements.txt" \
    || die "pip install failed"

say "3/4  Downloading Volta OS ($METHOD, ${TAG:-latest})"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if [ -n "$TAG" ]; then
    API_URL="https://api.github.com/repos/$REPO/releases/tags/$TAG"
else
    API_URL="https://api.github.com/repos/$REPO/releases/latest"
fi
ASSETS_JSON="$TMP/assets.json"
curl -fsSL "$API_URL" -o "$TMP/release.json" \
    || die "no GitHub release found for $REPO (${TAG:-latest}) yet - use the AppImage guide in docs/installation.md"
pick_asset() {  # $1 = grep pattern, prints first matching browser_download_url
    grep -o '"browser_download_url": *"[^"]*'"$1"'"' "$TMP/release.json" | head -1 | cut -d'"' -f4
}
case "$METHOD" in
    deb) URL="$(pick_asset '.*\.deb\"')" ;;
    rpm) URL="$(pick_asset '.*\.rpm\"')" ;;
    appimage) URL="$(pick_asset '.*\.AppImage\"')" ;;
    *) die "--method must be deb|rpm|appimage" ;;
esac
[ -n "${URL:-}" ] || die "release has no .$METHOD asset - see https://github.com/$REPO/releases"
curl -fSL "$URL" -o "$TMP/pkg" || die "download failed: $URL"
FILE="$(basename "$URL")"

say "4/4  Installing $FILE"
case "$METHOD" in
    deb)
        sudo apt install -y "$TMP/pkg" || { sudo dpkg -i "$TMP/pkg"; sudo apt install -f -y; } ;;
    rpm)
        if [ "$PKG_MGR" = "dnf" ]; then sudo dnf install -y "$TMP/pkg";
        else sudo zypper install -y --allow-unsigned-rpm "$TMP/pkg"; fi ;;
    appimage)
        mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
        cp "$TMP/pkg" "$HOME/.local/bin/$FILE"
        chmod +x "$HOME/.local/bin/$FILE"
        cat > "$HOME/.local/share/applications/volta-os.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Volta OS
Comment=In-car interface
Exec=$HOME/.local/bin/$FILE
Terminal=false
Categories=Utility;
DESK
        ;;
esac

say "Done!"
echo "Start Volta OS from the applications menu, or run:"
case "$METHOD" in
    appimage) echo "  $HOME/.local/bin/$FILE" ;;
    *) echo "  VoltaOS" ;;
esac
echo "On first launch the guided setup helps you create the free API keys."
