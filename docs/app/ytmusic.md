# YT Music

A YouTube Music client for the car. Playback with **mpv** + **yt-dlp**; library and search with
**ytmusicapi**. Service `ytmusic_scraper_service.py` (port 8099).

**Requirements:** internet, `mpv`, a Google account (for your library). No API key.

## Signing in

On first open tap **Sign in to YouTube Music**: a panel with the Google login appears.
Sign in with your account; the UI **detects the login by itself**, saves the sign-in data on the PC and the
connection is automatic. **Sign out** in the account menu to disconnect.

## Screens

The tabs at the top change the view:

- **Home** — recommended, **Quick picks** (quick selection of tracks and playlists) and *Recently played*.
- **Library** — your collections, filterable by **Playlists, Tracks, Albums, Artists, Podcasts**.
- **Detail pages** — album, playlist and artist with tracks, **See all**, top
  tracks, singles. Columns show song, artist, album and duration.
- **Screen history** — the header's back/forward buttons retrace the screens you visited.

## Playback

- Tap a track to play it; the **heart** saves it to YouTube Music's Likes.
- With video versions the widget shows the cover in video format.
- **Synced lyrics**: from the widget (or the app) open the lyrics panel, see [below](#synced-lyrics).
- If a track cannot be played "playback not available" appears and it moves on to the next.

## Queue and search

- **Unified queue** (queue icon): *Now playing* + *Up next* with tracks added from any app.
  See [Interface › unified search and queue](../interface.md#unified-search-and-queue).
- **Unified search** (magnifier): searches YT Music, Spotify and Music together; *Recent searches*
  shared between apps; top result, tracks, videos, artists, albums, playlists.
- **Shuffle** and **repeat** (one track / queue) are handled by the service, which owns the queue.

## Synced lyrics

The panel on the right shows the line being sung large and the others faded, scrolling by itself. The
text is searched in parallel on LRCLIB, lrc.red, BiniLyrics, BetterLyrics, LyricsPlus, Unison and
KuGou (no key); the first one with a credible **timed** text wins (check on title,
artist and duration). If none has timed lyrics but one has plain text, it is shown static.

## Switching music app

Tap the logo at the top left: the dropdown menu switches to Spotify, Music, Podcasts or Bluetooth.
