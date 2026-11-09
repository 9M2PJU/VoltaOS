# For developers

## Structure

```
volta_os/
├── CMakeLists.txt  requirements.txt  keys.env.example  install.sh  start.sh
├── src/                 C++
│   ├── main.cpp         startup, services, QML engine
│   ├── core/            SystemHelper (audio, screen, network), ServiceManager, SetupManager, LanguageManager
│   ├── media/           MprisManager (system players over D-Bus)
│   ├── phone/           PhoneManager (bridge to phone_service.py)
│   ├── nav/             NavigationManager (Mapbox routes, maneuvers), GpsService (serial/Bluetooth GPS)
│   ├── carlink/         CarlinkDongle (CarPlay / Android Auto over USB), video and audio decoding
│   └── wayland/         extra Wayland protocols of the compositor
├── qml/                 interface (one screen per file)
├── services/            Python services started by the UI
├── scripts/             game launch (gamescope / XWayland), translations, AppImage build
├── assets/              icons, images, fonts, 3D car, radio logos
├── i18n/                translations (volta_it/es/fr/pt.ts + dict.txt)
├── third_party/         MapLibre maps plugin
├── packaging/           AppRun, .desktop, AppImage icon
└── data/                data generated at runtime (map cache, albums): not in git
```

The files in `assets/` end up in the Qt resources with the path `qrc:/VoltaApp/...` thanks to the aliases
in `CMakeLists.txt`.

## Services

The program starts the Python services by itself and restarts them if they stop. They all listen only on
`127.0.0.1`.

| Service | Port | When it starts |
|---|---|---|
| `map_proxy.py` — styles and tiles with cache, search, POIs, speed cameras, fuel, radio logos | 9098 | at startup |
| `network_settings_service.py` — real Wi-Fi and Bluetooth | 9097 | at startup |
| `phone_service.py` — calls, contacts, SMS (D-Bus `com.volta.Phone`) | — | at startup |
| `ytmusic_scraper_service.py` — YT Music | 8099 | when needed |
| `spotify_scraper_service.py` — Spotify | 8098 | when needed |
| `podcast_service.py` — podcasts | 8094 | when needed |
| `local_music_service.py` — Music (local files) | 8097 | when needed |

"When needed" = the first time the app is opened, or if it was the last source in use (with *Resume
on startup*). Keys are read with `services/keys.py` (`keys.env` > environment variables).

## Media playback

The players (`mpv` for YT Music/Podcasts/Music, `spotifyd`, the phone via `mpris-proxy`) announce themselves
on the bus as **MPRIS** players: `MprisManager` collects them and the music widget shows the last one started.
`MediaHub.qml` is the "big picture": it treats YT Music, Spotify, Music and Bluetooth as *providers* of
a single **queue** and a single **search**. To add a source you need: a service with
`/search`, `/play`, `/player/*`, an MPRIS player, and the entries in the `provider*` of `MediaHub.qml`.

## Useful environment variables

| Variable | Effect |
|---|---|
| `VOLTA_DEBUG=1` | diagnostic log: FPS, map styles, 3D materials, keyboard, web console |
| `VOLTA_PERF=1` | timing of every frame of the graphics engine |
| `VOLTA_STALL=1` | stack when the UI blocks for more than 60 ms |
| `VOLTA_DIR=…` | project folder (by default that of the executable) |
| `VOLTA_OPEN=app[:page]` | opens an app after startup (e.g. `settings:Display`, `localmusic`) |
| `VOLTA_SHOT=file.png[:ms]` | saves a screenshot after *ms* milliseconds |
| `VOLTA_CARLINK_AUTO=1` | enables the CarPlay / Android Auto dongle at startup |

Quick test after QML changes, without a screen: `QT_QPA_PLATFORM=offscreen ./build/Release/VoltaOS` and
look in the log for `TypeError`, `ReferenceError`, `Non-existent`, `failed to load` and the `FIRST FRAME` line.
Graphic effects (masks, `MultiEffect`) are not visible offscreen: for screenshots use a real
session.

## Translations

The source language is **English** inside `qsTr("…")`; Italian, Spanish, French and Portuguese are translations. To add strings:

```bash
for l in it es fr pt; do ~/Qt/6.11.1/gcc_64/bin/lupdate qml src -ts i18n/volta_$l.ts -source-language en -target-language $l; done
# add lines  english§italian§spanish§french§portuguese  to i18n/dict.txt
python3 scripts/apply_translations.py
```

Do not put in `qsTr` strings that are used in comparisons (`===`) or as keys.

## Building the AppImage

```bash
cmake --build build/Release -j$(nproc)
bash scripts/build_appimage.sh      # creates VoltaOS-x86_64.AppImage
```

You need Qt from the official installer in `~/Qt` and the tools `linuxdeploy`, `linuxdeploy-plugin-qt` and
`appimagetool` in `~/appimage-tools`. It works in `build/appimage-work` (not in `/tmp`, often small).
Do not set `LD_LIBRARY_PATH` in `AppRun`: gamescope, Wine and Python would inherit it.

## 3D models and licenses

Do not put 3D models or images in the repository unless you have the right to redistribute them. Your own
car is loaded at runtime from *Settings › System › 3D car*.
