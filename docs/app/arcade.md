# Arcade

A car-style game launcher. **Windows** games run with **Bottles** (Wine) inside
**gamescope** (Valve's tool), which shows up in the UI as a regular window.

**Requirements (optional):** [Bottles](https://usebottles.com) (Flatpak) and `gamescope`.

## How games show up

Every program you add in **Bottles** shows up **by itself** in the Arcade: the UI reads the list of
programs of each bottle. Nothing needs to be configured.

## Screen

- Header with the selected game and the **Play** button; below, a row of cards.
- With no games: "No games — show them from Settings › Arcade".
- If a game closes by itself, "did not start. Try again." appears.
- Menu at the top to switch to **Theater** and **Toybox**.

## Covers

The project contains no copyrighted images: you choose the **cover** (vertical, e.g. 600×900) and **hero**
(wide image) yourself from [Settings › Arcade](../settings/apps-arcade.md). They are saved in
`~/.config/volta/arcade_art/`. Without an image the card shows the game's name.

## Show or hide

Again in Settings › Arcade you can choose which games to show.

## How a game starts

The script `scripts/native_game_gamescope_launch.sh <bottle> <-p|-e> <program>` starts
`bottles-cli` inside gamescope, connected to the UI's compositor (`wayland-volta`).
