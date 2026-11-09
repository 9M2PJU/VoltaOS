# Installation

Volta OS only runs on **Linux with a Wayland session** (Debian 13, recent Ubuntu with GNOME).
It does not run on Windows or macOS.

## AppImage (no compiling)

Download `VoltaOS-<version>-x86_64.AppImage` from the repository's **Releases** page.

```bash
sudo apt install python3 python3-pip python3-dbus python3-gi mpv libusb-1.0-0 \
    libxcb-cursor0 network-manager bluez bluez-obexd pipewire-pulse
pip install --user --break-system-packages -r requirements.txt   # Python services
chmod +x VoltaOS-*-x86_64.AppImage
./VoltaOS-*-x86_64.AppImage
```

Qt, the maps plugin and the car model are already inside the file. If it does not start, install
`libfuse2t64` or run it with `--appimage-extract-and-run`. To try it in a window:
`./VoltaOS-*.AppImage --window=1280x800`.

Your data (keys, favorites, cache) lives in `~/.local/share/volta_os/`.

On first launch the **guided setup** starts by itself. Its second page is a **System check**: it lists the
programs and Python libraries Volta OS needs and, for each one that is missing, the command to install it.
The same warning is printed in the terminal at every start. Without the required ones the interface starts
but will **not** work at 100% (for example no music playback without `mpv`, no services without the Python
libraries). You can reopen the check any time from *Settings › System › Connected services › Guided setup*.

## Building from source

```bash
git clone https://github.com/omardigiovanni3-beep/VoltaOS.git ~/volta_os
cd ~/volta_os
./install.sh
```

`install.sh` does four things: installs the system packages (it asks for your password), the Python
libraries, builds in `build/Release` (a few minutes) and creates the **Volta OS** icon in the
application menu. Then start it from the menu or with `./start.sh` (windowed: `./start.sh --window=1280x800`).

If you have Qt from the official installer in `~/Qt`, the script uses that; otherwise it uses the Debian packages.

### Manual installation

Qt 6 (6.9 or newer recommended) with the modules: Quick, Quick3D, WebEngine, WebSockets, Positioning,
Location, VirtualKeyboard, WaylandCompositor, DBus, OpenGL, Multimedia, Svg. Then:

```bash
sudo apt install build-essential cmake pkg-config mpv libwayland-dev wayland-protocols libx11-dev \
    libusb-1.0-0-dev libavcodec-dev libavutil-dev python3 python3-pip python3-dbus python3-gi \
    network-manager bluez bluez-obexd pipewire-pulse
pip install -r requirements.txt
cmake -B build/Release -DCMAKE_BUILD_TYPE=Release
cmake --build build/Release -j$(nproc)
```

> **Maps plugin.** The MapLibre plugin included in `third_party/maplibre/` is built for
> **Qt 6.11.1 on Linux x86_64**. With a different Qt version the map may not start:
> build [maplibre-native-qt](https://github.com/maplibre/maplibre-native-qt) and install it in `/usr/local/qml`.

## Dependencies

### System

| Package | What it is for | Required |
|---|---|---|
| `mpv` | audio playback (YT Music, Podcasts, Music, radio) | yes |
| `python3`, `python3-dbus`, `python3-gi` | background services | yes |
| `network-manager` | Wi-Fi in the settings | yes |
| `bluez`, `bluez-obexd` | Bluetooth, contacts, SMS, music from the phone | yes (for the phone) |
| `pipewire-pulse` (or PulseAudio) + `pactl` | volume, audio devices, calls | yes |
| `libusb-1.0-0` | CarPlay / Android Auto dongle | yes |
| `libxcb-cursor0` | starting the AppImage | yes |
| `spotifyd` | Spotify Connect (play Spotify from the UI) | optional |
| `easyeffects` | equalizer and audio presets | optional |
| `gamescope` + Bottles | Windows games (Arcade) | optional |

### Python (`requirements.txt`)

`Flask`, `requests`, `Pillow` (all services); `segno` (map QR codes); `ytmusicapi`, `yt-dlp`,
`python-mpv`, `spotipy`, `spotifyscraper` (music and podcasts); `mutagen` (tags and covers for the
Music app); `dbus-next`, `vobject` (phone, Wi-Fi, Bluetooth).

## Updating

- **AppImage**: download the new file and replace the old one. Your data stays in `~/.local/share/volta_os/`.
- **Source**: `git pull`, then `cmake --build build/Release -j$(nproc)`.

## Uninstalling

Delete the AppImage (or the project folder), `~/.local/share/volta_os/` and, if it exists,
`~/.local/share/applications/volta-os.desktop`.
