# Messages, Calendar, Camera

## Messages

Your phone's SMS, over Bluetooth: see [Phone and Messages](phone.md#messages).

## Calendar

An **agenda** with the day icon: "Calendar" at the top, then the days with events starting from today and,
for each day, rows of *time | title* ("All day" for events without a time). If there is
nothing: "No upcoming events". The drawer icon shows the day of the month.

> In this version the agenda is filled from code (`setEvents([...])`): it is not yet connected to an
> online calendar.

## Camera

A main view (rear) and two side views below, edge to edge and without a header, as on
electric cars. **The tiles are placeholders**: the camera streams still need to be connected
(just put an image or video inside the relevant `CamTile` in `CameraApp.qml`).

## Native and web apps

Besides the apps described here, the UI is a **Wayland compositor**: a Linux program started with
`WAYLAND_DISPLAY=wayland-volta` opens inside the UI as an app, with popups and menus. Sites added from the
Browser show up as [web apps](theater-browser.md#web-apps).
