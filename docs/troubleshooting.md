# Troubleshooting

## The UI does not start

- **Wayland session**: `echo $XDG_SESSION_TYPE` must say `wayland`.
- **AppImage**: install `libfuse2t64`, or `./VoltaOS-*.AppImage --appimage-extract-and-run`.
- Start from the terminal to see the errors; with `VOLTA_DEBUG=1` you get more detail.
- **The map does not appear**: the bundled plugin is for Qt 6.11.1; with a different Qt version you need to build
  [maplibre-native-qt](https://github.com/maplibre/maplibre-native-qt).

## Map

- **Blank or gray map**: check `MAPBOX_TOKEN` and `MAPTILER_KEY` in the
  [guided setup](settings/system.md#connected-services). You need internet and a valid key.
- **Blurry satellite**: tiles not yet downloaded keep the previous resolution; they complete
  as soon as the network is back.
- **Search finds nothing**: it needs `TOMTOM_KEY`. Fuel prices only work in Italy.
- **No position**: connect a [GPS](hardware.md#gps) or choose it in Settings › Navigation.
- **No voice in the alerts**: speech synthesis is not included in this version.

## Music

- **YT Music does not load**: sign in again; check `mpv` and `yt-dlp` (`pip install -U yt-dlp`).
- **Spotify does not play**: it needs `spotifyd` and, to play, a Premium account. Check the
  *Redirect URIs* of the Spotify app.
- **Podcasts "python-mpv missing"**: `pip install --user --break-system-packages -r https://raw.githubusercontent.com/Omardigio/VoltaOS/main/requirements.txt`.
- **Music does not see the USB stick**: it must be **mounted** in `/media`, `/run/media` or `/mnt`; open the
  *USB* tab. If your desktop does not mount it automatically, mount it from the file manager.
- **Radio without stations**: check the network; choose a country at the top of the page.

## Phone

- **Empty contacts or SMS**: on the phone enable sharing of contacts and messages for the Bluetooth
  device; check that `bluez-obexd` is installed.
- **No audio during calls**: check PipeWire (`pipewire-pulse`) and the output chosen in Settings › Audio.
- **The phone does not connect**: *Forget* the device in Settings › Bluetooth and pair it again.

## CarPlay / Android Auto

- "Dongle not available": reinsert the Carlinkit dongle and check `libusb-1.0-0`.
- Cropped or squashed image: change **Fit** in Settings › CarPlay / Android Auto.
- Too slow: drop to 720p or 480p.

## Arcade

It needs Bottles and `gamescope`. If no games show up, add them in Bottles and reopen the app; if a
game closes immediately, try it from Bottles first.

## Performance

On less powerful PCs enable *Settings › System › Performance › Low performance mode*.
To see what is heavy: `VOLTA_PERF=1 ./start.sh`.

## Starting from scratch

Close the UI and rename `~/.local/share/volta_os/` and the `~/.config/volta*` folders (save `keys.env` first). On
restart the guided setup starts again.
