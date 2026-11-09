# Spotify

Shows your playlists, library and Spotify's recommendations. **Playback** goes through
**spotifyd** (Spotify Connect): the UI becomes a Spotify device on your account.

**Requirements:** Spotify account (a free one is fine for browsing; to play via Connect a
Premium one is generally needed), `spotifyd` installed, `SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET`
([how to get them](../api-keys.md#spotify-step-by-step)). Service `spotify_scraper_service.py` (port 8098).

## Signing in

Tap **Sign in to Spotify** and sign in from the panel inside the UI. **Sign out** in the menu to disconnect.

## Screens

- **Home** — playlists and "Made for you" collections, new releases and recommendations.
- **Explore** — fixed categories (*New releases, Dance / Electronic, Charts, Discover, In the car,
  Trending, Workout music, Wellness, Kids and family…*); the content of each
  category is fetched on the fly, with automatic retries if the service is slow. Card covers
  update by themselves.
- **Library** — saved **Playlists, Tracks, Albums, Artists, Podcasts**.
- **Detail** — album, playlist and artist: tracks, *See all*, top tracks, singles.

> Spotify removed the category list from its official API (February 2026): that is why the list
> in *Explore* is fixed in the app.

## Playback, queue and search

As in YT Music: **heart** for favorite tracks, **synced lyrics**, **unified queue**,
**unified search**, shuffle and repeat (even without login they go through MPRIS). The logo menu at the top switches
to the other music apps. See [YT Music](ytmusic.md) and [Interface](../interface.md#unified-search-and-queue).

## If it does not play

- Check that `spotifyd` is installed: the UI starts it by itself.
- If the library does not load, sign in again and check the Spotify app's Redirect URIs.
