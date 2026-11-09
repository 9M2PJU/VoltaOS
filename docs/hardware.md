# Hardware

Volta OS runs on a regular **Linux PC** (a mini-PC works too) with a **touchscreen** and a Wayland session. Everything else is optional: each peripheral only enables its own feature.

## PC and screen

- Linux x86_64 with **Wayland**, GPU with working **OpenGL** drivers (the 3D car and the map use them).
- Touchscreen recommended; it also works with a mouse. Try it in a window with `--window=1280x800`.
- Slow PC? Enable *Settings › System › Performance › Low performance mode*: it removes reflections
  and blurs.

## GPS

Needed for position, navigation and alerts.

- **USB receiver** (e.g. u-blox): plug it in and it is detected automatically (serial port).
- **Bluetooth GPS**: pair it in [Settings › Bluetooth](settings/bluetooth-network.md), then in
  *Settings › Navigation › GPS receiver* choose *Automatic* or tap the device in the list
  (*Find Bluetooth GPS*).

## Phone (Bluetooth)

The PC's Bluetooth adapter + a paired phone. On the phone, enable **sharing of contacts and
messages**. It gives you: calls, contacts, SMS and music from the phone. See [Phone](app/phone.md) and
[Bluetooth](app/bluetooth.md).

## CarPlay / Android Auto dongle

A **Carlinkit** dongle in a USB port: the phone connects to the dongle over Bluetooth and the video
reaches the UI. See [CarPlay / Android Auto](app/carplay-androidauto.md).

## Audio

Output and input are chosen in [Settings › Audio](settings/audio.md) (PipeWire/PulseAudio).
Equalizer with EasyEffects; left/right and front/rear balance.

## USB sticks

A stick with music is detected automatically by the [Music](app/music.md) app (mounted in
`/media`, `/run/media` or `/mnt`).

## Games

The Arcade needs Bottles and gamescope (see [Arcade](app/arcade.md)).
