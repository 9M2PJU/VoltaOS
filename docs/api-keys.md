# API keys

Volta OS uses external services for maps, search and weather. The keys are **free** (with usage
limits that are more than enough for a car) and live **only on your PC**, in `keys.env`.

Without a key, only the feature that uses it is disabled: the rest of the UI keeps working.

## The easy way: guided setup

It opens by itself on first launch. For each service it explains how to create the account (with a QR
code to open the page on your phone), **checks the key as soon as you paste it** and saves it. You can
reopen it any time from **Settings › System › Connected services › Guided setup**.

## By hand

```bash
cp keys.env.example keys.env     # source checkout
# or, with the AppImage: ~/.local/share/volta_os/keys.env
```

Write the key after the `=`, without quotes or spaces, then restart the UI. An environment variable
with the same name takes precedence over the file. `keys.env` never goes to GitHub (it is in `.gitignore`).

## Which ones you need

| Key | What it unlocks | Where to get it | Cost |
|---|---|---|---|
| `MAPBOX_TOKEN` | **routes with real-time traffic**, turn-by-turn directions, lanes, vector map data | account.mapbox.com › Tokens › *Default public token* (starts with `pk.`) | free within the monthly quota |
| `MAPTILER_KEY` | **map look** (light and dark styles, street names) and **satellite view** | cloud.maptiler.com › Account › Keys | free plan |
| `TOMTOM_KEY` | **place search** (cities, addresses, businesses), nearby gas stations and restaurants | developer.tomtom.com › Keys | free plan |
| `OWM_KEY` | rain radar on the map (optional: works without it) | home.openweathermap.org › API keys; new keys can take up to 2 hours to activate | free |
| `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET` | library, playlists and explore in the Spotify app | developer.spotify.com/dashboard › *Create app* | free (a free account is enough) |

**Minimum for useful navigation:** `MAPBOX_TOKEN` + `MAPTILER_KEY` + `TOMTOM_KEY`.

### Spotify, step by step

1. On developer.spotify.com/dashboard sign in and press **Create app** (any name and description).
2. In **Redirect URIs** add exactly `http://127.0.0.1:8098/callback` and tick **Web API**.
3. Open the app's **Settings** and copy **Client ID** and **Client secret** into `keys.env`.
4. In the UI's Spotify app tap **Sign in to Spotify**.

## Services that do NOT need keys

- **Weather** (temperature, forecast popup, air quality): [Open-Meteo](https://open-meteo.com)
- **Radio**: [Radio Browser](https://www.radio-browser.info)
- **Podcasts**: iTunes catalog and RSS feeds
- **Synced lyrics**: LRCLIB and other public sources
- **YT Music**: sign in with your Google account inside the UI
- **Speed cameras, traffic lights, POIs**: OpenStreetMap (Overpass)
- **Fuel prices**: MIMIT open data (Italy only)
- **Local music**: no account and no network

## Where your data stays

Keys are in `keys.env`. Your sign-ins (YT Music, Spotify) and favorites stay on the PC in
`~/.local/share/volta_os/` and in `~/.config/volta*`. Nothing is sent to the project's servers.
