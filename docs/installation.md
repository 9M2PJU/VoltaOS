# Installation

Volta OS only runs on **Linux with a Wayland session** (Debian 13, recent Ubuntu with GNOME).
It does not run on Windows or macOS.

## AppImage (no compiling)

The AppImage already contains Qt, the maps plugin, the 3D car model and the Volta OS services. It does **not**
contain the system libraries and programs below, because they come from your distribution. You install them
once, with the commands in step 2.

### 1. Download

Download `VoltaOS-<version>-x86_64.AppImage` from the repository's
[**Releases**](https://github.com/Omardigio/VoltaOS/releases) page.

### 2. Install what it needs (Debian / Ubuntu)

**a) Libraries to start the app.** On a normal desktop with Wayland most of them are already there; the command
installs only what is missing:

```bash
sudo apt install libgl1 libegl1 libopengl0 libgbm1 libdrm2 libx11-6 libx11-xcb1 libxcb1 libxcb-dri3-0 \
    libxcb-cursor0 libfontconfig1 libfreetype6 libexpat1 libwayland-client0 libwayland-server0 \
    libasound2t64 libusb-1.0-0 libcom-err2 libfuse2t64
```

On Ubuntu older than 24.04 and on Debian 12 the names are `libasound2` and `libfuse2`.

**b) Programs the features rely on.** Without them the interface starts but that part does not work:

```bash
sudo apt install python3 python3-pip python3-dbus python3-gi mpv network-manager \
    bluez bluez-obexd pipewire-pulse pulseaudio-utils
```

**c) Python libraries of the services:**

```bash
pip install --user --break-system-packages -r https://raw.githubusercontent.com/Omardigio/VoltaOS/main/requirements.txt
```

(`--break-system-packages` is needed on Debian 13 and recent Ubuntu; on older systems remove it.)

### 3. Run

```bash
chmod +x VoltaOS-*-x86_64.AppImage
./VoltaOS-*-x86_64.AppImage
```

To try it in a window: `./VoltaOS-*-x86_64.AppImage --window=1280x800`.
If it does not start, run it with `--appimage-extract-and-run` (this also works without FUSE).

> **Other distributions.** The libraries and programs are the same, but the package names change: look for
> the equivalents of the table below. Debian 13 is the only tested system.

### What is needed for what

| Package | What it is for | Required |
|---|---|---|
| `libgl1`, `libegl1`, `libopengl0`, `libgbm1`, `libdrm2` | graphics (OpenGL) | yes, to start |
| `libx11-6`, `libx11-xcb1`, `libxcb1`, `libxcb-dri3-0`, `libxcb-cursor0` | window system (X11 / XWayland) | yes, to start |
| `libwayland-client0`, `libwayland-server0` | Wayland (the UI is also a Wayland compositor) | yes, to start |
| `libfontconfig1`, `libfreetype6`, `libexpat1` | fonts | yes, to start |
| `libasound2t64` | audio | yes, to start |
| `libusb-1.0-0` | CarPlay / Android Auto dongle | yes, to start |
| `libcom-err2` | needed by the bundled libraries | yes, to start |
| `libfuse2t64` | running AppImages (not needed with `--appimage-extract-and-run`) | optional |
| `mpv` | audio playback (YT Music, Podcasts, Music, radio) | yes, for music |
| `python3`, `python3-dbus`, `python3-gi` + the Python libraries | background services | yes |
| `network-manager` | Wi-Fi in the settings | yes, for Wi-Fi |
| `bluez`, `bluez-obexd` | Bluetooth, contacts, SMS, music from the phone | yes, for the phone |
| `pipewire-pulse` (or PulseAudio) + `pulseaudio-utils` (`pactl`) | volume, audio devices, calls | yes, for audio |
| `spotifyd` | Spotify Connect (play Spotify from the UI) | optional |
| `easyeffects` | equalizer and audio presets | optional |
| `gamescope` + Bottles | Windows games (Arcade) | optional |

The start-up libraries list was checked on a clean Debian 13: with those packages installed the AppImage starts.

Your data (keys, favorites, cache) lives in `~/.local/share/volta_os/`.

On first launch the **guided setup** starts by itself. Its second page is a **System check**: it lists the
programs and Python libraries Volta OS needs and, for each one that is missing, the command to install it.
The same warning is printed in the terminal at every start. Without the required ones the interface starts
but will **not** work at 100% (for example no music playback without `mpv`, no services without the Python
libraries). You can reopen the check any time from *Settings › System › Connected services › Guided setup*.

## Building from source

```bash
git clone https://github.com/Omardigio/VoltaOS.git ~/volta_os
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

See the table [What is needed for what](#what-is-needed-for-what) above.

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
