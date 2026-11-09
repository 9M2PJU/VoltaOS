# Toybox

The UI's "extra" features, with the same interface as the Arcade: a large tile at the top and a row
of cards below. Menu at the top to switch to **Theater** and **Arcade**.

## Emissions

*Emissions test mode*: choose a sound from the list; on the right is the cabin diagram
(the same as Audio › Balance). Drag the **cushion** along the left–right bar, then tap it: the
sound plays **balanced** between the left and right speakers according to
the position.

## Colorizer

Changes the color of the 3D car's body; every change applies immediately.

- Donut-shaped **hue wheel** + **square** for saturation (→) and brightness (↑).
- **Paint type**: *Pastel*, *Glossy*, *Matte*.
- **＋** saves the current color among the **custom** ones; below there are also the **presets**.

The car's reflection on the floor always stays dark gray, whatever color you choose.

## Romance

*Set the right mood with a crackling fireplace, full screen.* **Light the fireplace** opens an online
video, looping and without controls; close it with the back button at the top left. Internet required.

## Album

*Draw*: freehand drawing, full screen. Top bar: **marker** / **eraser**, **color**,
**size** (‹ 12 ›), **Publish** (saves the drawing), **Undo**, **Fill**, **Exit**. Published
drawings end up in `data/album/`.

## Mars

*Multi-planetary species*: the map becomes the surface of **Mars** (OpenPlanetaryMap texture,
NASA/USGS data). 
Card images can be customized in `assets/toybox/<key>.png`
(`emissioni`, `colorizer`, `romance`, `album`, `marte`).
