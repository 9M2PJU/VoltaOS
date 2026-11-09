# Map and navigation

The map is the base of the UI: it is always behind the car panel and the apps, and with the
"full screen" mode (Settings › Navigation) it fills the whole screen when no apps are open.

**Keys:** `MAPBOX_TOKEN` (routes and traffic), `MAPTILER_KEY` (style and satellite), `TOMTOM_KEY`
(place search) and optional `OWM_KEY`. See [API keys](../api-keys.md).
**Hardware:** a [GPS receiver](../hardware.md#gps) (USB u-blox or Bluetooth).

## Map view

- **Position and heading**: the car arrow glides along the road; while navigating the map
  rotates in the direction of travel. You can choose **Heading** (the map turns with you) or **North
  up** (Settings › Navigation › Map view).
- **Manual rotation**: rotate the map with two fingers; a **carousel compass** (N, NE, E…) shows the
  orientation. **Recenter** brings the map back to the car.
- **Styles**: light and dark (they follow the interface theme) and **satellite** (MapTiler).
  With *Night effect* the satellite darkens in the evening hours (Off / On / Auto, same window as the
  automatic theme).
- **Weather**: you can turn on the **rain radar** on the map. Tapping the degrees in the top bar
  opens the [weather popup](../interface.md#status-bar).
- **Mars**: from the Toybox the map becomes the surface of Mars ([Toybox](toybox.md)).

## Searching for a destination

Tap the **Search** bar at the top left.

- Type an address, a place or a business: results come from TomTom, near your position.
- Quick tabs: **Recent**, **Favorites**, **Gas stations**, **Restaurants**; for each nearby
  category there is also a *near you* list (stations, parking, restaurants).
- **Home** and **Work**: two shortcuts. They are set from a place's card with *Set as
  Home* / *Set as Work*; until you set them, tapping them opens the search.
- Recent searches and favorites are saved automatically.

Tapping any point on the map shows a **pin** with the place's card.

## A place's card

Name and address, distance, and the buttons:

- **Go**: calculates the route and starts navigation.
- **Add stop** (maximum two).
- **Set as Home / Work**, and add to favorites.
- **Fuel prices** for gas stations (MIMIT data, **Italy only**: prices for
  gasoline, diesel, LPG and methane at the nearest station).

## Navigation

After *Go* you see the route preview: the main route in **blue**, the alternatives in
**gray** with a bubble (time and distance). Tap an alternative to choose it.

- **Routes with real-time traffic** (Mapbox `driving-traffic`), with automatic recalculation
  if you leave the road.
- **Maneuver banner** at the top: the next turn with distance, the street name, the
  **lanes** (the arrows to use are highlighted) and the illustration of the junction (*junction view*,
  the lane to take in blue). Below, the list of following maneuvers: keep it open or collapse it to one line.
- **Bottom panel (ETA)**: arrival time, remaining time and kilometers, **End trip**,
  **Add stop** during the trip (max 2).
- **Edit route**: reorder or remove stops; the leg to the first stop is blue, the
  following ones gray.
- **Avoid tolls / ferries**: Settings › Navigation.
- The part already traveled is colored and the arrow follows the line smoothly.

## Road alerts

- **Speed cameras, Tutor and traffic-light cameras** (OpenStreetMap): an alert appears at the top
  center with the distance and the limit when you have one ahead. They only work above 8 km/h
  and only in your direction of travel.
- **Traffic lights and stop signs** are drawn on the map at close zoom.
- **POIs** (gas stations, parking, restaurants) with the app's icons.
- **Traffic**: the route's segments are colored according to the traffic supplied by Mapbox.

> **Note.** Voice alerts (speed cameras, directions) in this version have no bundled speech
> synthesis engine: alerts are on screen. The *Voice guidance volume* slider in
> Settings is already prepared.

## Map widget

In the left panel, next to the music widget, a mini map with the **Navigate** button and the
latest destinations.

## Data used

Mapbox (routes, traffic), MapTiler (styles, satellite), TomTom (search), OpenStreetMap/Overpass
(speed cameras, traffic lights, POIs), MIMIT (fuel, Italy), Open-Meteo and OpenWeatherMap (weather). The map goes through a local proxy (`map_proxy.py`, port 9098) that **caches
tiles on disk** once seen: usual areas load even with a poor connection.
