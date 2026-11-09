# Interface

The screen is split in two: the **car panel** on the left, **map and apps** on the right, and the
**dock** at the bottom. With right-hand drive (*Settings › Display › Driving position*) everything is mirrored.

## Car panel

- **3D car** (Qt Quick 3D) with floor reflection, shadows and lights. Rotate it with your finger.
- **Instrument cluster**: gear (P R N D) and speed. *In this version the cluster always shows "P" and "0 km/h":
  it is not connected to the vehicle's ECU.* GPS speed is used by the map and the alerts.
- **Lock**: locks and unlocks the doors. **Trunk** and **Hood**: tap to open or close.
- **Dragging**: the strip on the left edge of the map drags the panel.
- **Car adjust** and **Load 3D car**: position, size, shadow and proportions; you can load your own
  model (see [System](settings/system.md#3d-car)).

## Music widget

Below the car. It shows cover, title and artist of the track playing from **any** source
(YT Music, Spotify, Music, Podcasts, Radio, phone) and a progress bar.

| Button | Function |
|---|---|
| ⏮ ⏯ ⏭ | previous, play/pause, next (with radio: stop, and the arrows are dimmed) |
| ♡ | Like the track (or favorite the radio station) |
| equalizer | opens Settings › Audio › Equalizer |
| magnifier | opens the search of the music app in use |
| shuffle, repeat | shuffle and repeat (one track / whole queue) |
| podcast: `1×`, ±skip | speed and skip forward/back |

**Tap the cover or the title** to open *Now playing + Queue*. When you change the volume, a banner
appears above the widget.

## Unified search and queue

The music apps (YT Music, Spotify, Music, Bluetooth) share a single search and a single queue.

- **Unified search** (magnifier in the header): searches YT Music, Spotify and Music in parallel; chips
  filter by source. Results for tracks, videos, artists, albums, playlists; tap a track to play it,
  albums and artists open in the app of their source. *Recent searches* are shared.
- **Unified queue** (queue icon): at the top the current track with its controls (previous, play, next,
  shuffle, repeat), progress bar and cover; below **Up next**: first the tracks **you added**
  (even from another app: they start when the current track ends), then the **following** tracks of the
  active source. **Clear** removes the ones you added; ✕ removes one; tap a row to jump to that track.

## Dock

The bottom bar, from left to right:

- **Car button**: opens and closes the **Settings**.
- **MY APPS**: the icons you choose. **Drawer** (grid icon): all the apps. **RECENT APPS**:
  the last ones opened.
- **Volume**: the ‹ › arrows change the volume in 5% steps; tapping the speaker **mutes** or unmutes.

To rearrange: in the drawer tap **Edit**, then drag an icon over another to swap them or
drop it in the dock to pin it.
- Web apps added from the Browser appear at the top of the drawer.
- Apps hidden in [Settings › Apps](settings/apps-arcade.md) disappear from the drawer but stay installed.

## Status bar

At the top above the map: **lock**, **time**, **weather** with icon and degrees, position, and the
**passenger airbag** indicator. Tap the **degrees** for the **weather popup**: current location,
outside temperature, hourly and daily forecast, chance of rain, humidity, wind, UV index and
**air quality** (Open-Meteo data, no key; offline it shows the last data received).

## Notifications

- **Incoming / outgoing / ongoing call** and **new message** appear as banners above the
  music widget, with the relevant buttons.
- **"No connection — check the network"** when there is no internet.

## On-screen keyboard

It opens when you tap a text field (it can be turned off in *System*) and is Qt's virtual
keyboard: QWERTY layout with number keys, **globe icon 🌐** to switch language (active languages are
chosen in Settings › System), microphone, enter key with a contextual action (Search, Go…). Tapping
outside the keyboard closes it.

## Screen cleaning mode

*Settings › Display › Screen cleaning mode* locks the touch for a few seconds while you
clean the glass; to exit, **press and hold**.

## Languages

Italian, English, Spanish, French and Portuguese (selector at first launch and in Settings › System › Language).
