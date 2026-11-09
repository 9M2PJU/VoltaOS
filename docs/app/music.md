# Music (local files)

The **Music** app plays the audio files on the PC and on USB sticks. No account, no internet.

**Formats:** MP3, FLAC, OGG, Opus, M4A, WAV and others. **Engine:** mpv. **Service:** `local_music_service.py` (port 8097).

## Where it looks for music

- Your **Music folder** (whether it is called `Musica`, `Music`, `Musique`… depending on the system
  language: it reads it from `~/.config/user-dirs.dirs`).
- Every **USB stick or disk** mounted in `/media`, `/run/media` or `/mnt`: it is detected
  automatically, and when you plug it in a "Stick connected" notice appears. Sticks already seen but
  unplugged stay in the index and reappear the next time they are connected.
- Titles, artists, albums, years and covers are read from the files' **tags**; if the cover is missing
  it tries the image in the folder (`cover.jpg`, `folder.jpg`…). If there is nothing, the UI shows
  the gray tile with the ♫ note, the same as the music widget.

## Screens

**Tracks** — the list of all tracks in alphabetical order, with three filters:
**All tracks**, **Local** (only the Music folder), **USB** (only the sticks). Tap a track
to play it: the queue becomes the filtered list.

**Albums** and **Artists** — grids of cards (albums with a square cover, artists with a
round cover). Tap a card to open the page with the track list, the round **Play** button and the
**shuffle** button.

**Playlists** — the **Liked** card (tracks with a heart) and your playlists; **＋ New playlist**
to create one, the ✕ on the card to delete it.

On every track: **heart** (Like) and **⋯** with *Add to queue*, *Add to a playlist* and, inside
a playlist, *Remove from this playlist*.

## Unified queue and search

In the header, next to the logo, there are the **magnifier** and the **queue**: they are the
[unified search](../interface.md#unified-search-and-queue) and the **unified queue** shared with YT Music,
Spotify and Bluetooth.

- In the unified search a **Music** chip limits the results to your files; albums and artists found
  open in here.
- *Add to queue* also works while another app is playing: the track starts afterwards.
- In the queue the following tracks appear as "Up next from Music" and can be jumped to by tapping them.

## Playback control

The player has no bar of its own: it is controlled from the **music widget**, from the *Now playing
+ Queue* screen (tap the widget) or from the media keys. Available: play/pause,
previous/next, seeking within the track, **shuffle** and **repeat** (one track / whole queue /
off). With "repeat one", next and previous restart the same song.

The service announces itself to the system as the **"Music"** player (MPRIS): title, cover and controls
also work with the steering-wheel or system keys.

## Where the data stays

Index, Likes and playlists in `~/.config/volta/localmusic/`. If you delete that folder the
library rebuilds itself; you lose Likes and playlists.
