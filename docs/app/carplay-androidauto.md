# CarPlay / Android Auto

The phone is shown inside the UI (video, audio and touch) through a **Carlinkit dongle** plugged into
a USB port. No keys, no Python service: the main program does the work.

**Requirements:** Carlinkit dongle, `libusb-1.0-0`. More details
in [Hardware](../hardware.md#carplay--android-auto-dongle).

## How to connect

1. Plug the dongle into a USB port of the PC.
2. Turn on **Bluetooth** on the phone and connect it to the dongle (it appears as a Bluetooth device on the
   phone). CarPlay or Android Auto start by themselves.
3. Open the **CarPlay / Android Auto** app from the drawer.

The states you see: *Starting the dongle…* → *Connect your phone* → *Connecting to …* → the phone's video.
If the dongle is not connected, *Dongle not available · Plug in the USB dongle* appears.

## Small panel and full screen

The app opens in the right-hand panel and can go **full screen**. The phone's video is always
16:9: in the small panel and in full screen you can choose how to fit it (see below).

## Settings

In [Settings › CarPlay / Android Auto](../settings/carplay-android-auto.md): theme, fit
(*Automatic* or *Fill*), resolution (480p / 720p / 1080p), density (DPI) and **Reconnect the phone**.
Resolution and DPI apply on reconnection, which starts by itself when you change them.
