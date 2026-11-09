import time
import os
import json
import threading
import random as _random
from flask import Flask, request, jsonify, redirect
import spotipy
from spotipy.oauth2 import SpotifyOAuth

# Anonymous Scraper import (if present in the project folder)
try:
    from spotify_scraper import SpotifyClient
    sp_scraper = SpotifyClient()
except Exception:
    sp_scraper = None

app = Flask(__name__)

# no CORS "*": the UI (QML) does not need it, and this way websites
# cannot read the responses. /callback stays open: it is the return from the Spotify login.
from local_security import protect
protect(app, allow=("/callback",))

# ── CONFIGURAZIONE SPOTIFY OAUTH ──
from keys import key   # keys.env, see keys.env.example
SPOTIPY_CLIENT_ID = key("SPOTIFY_CLIENT_ID")
SPOTIPY_CLIENT_SECRET = key("SPOTIFY_CLIENT_SECRET")
SPOTIPY_REDIRECT_URI = "http://127.0.0.1:8098/callback"
# user-library-modify: needed for the heart (add/remove from "Liked Songs")
SCOPE = ("user-library-read user-library-modify user-top-read playlist-read-private "
         "playlist-read-collaborative user-read-playback-state "
         "user-modify-playback-state")

sp_oauth = None
sp_official = None

# Spotify login token: outside the project (it is a secret). A single path,
# used both by spotipy and by is_logged_in().
TOKEN_PATH = os.path.expanduser("~/.config/volta/spotify_token.cache")
os.makedirs(os.path.dirname(TOKEN_PATH), exist_ok=True)

if SPOTIPY_CLIENT_ID and "INSERISCI" not in SPOTIPY_CLIENT_ID:
    sp_oauth = SpotifyOAuth(
        client_id=SPOTIPY_CLIENT_ID,
        client_secret=SPOTIPY_CLIENT_SECRET,
        redirect_uri=SPOTIPY_REDIRECT_URI,
        scope=SCOPE,
        open_browser=False,
        cache_path=TOKEN_PATH
    )
    sp_official = spotipy.Spotify(auth_manager=sp_oauth)

def is_logged_in():
    """True if a saved session exists. It does not attempt the token refresh
    (offline it would fail and make it look like we are not logged in)."""
    if not sp_oauth:
        return False
    try:
        import json as _j
        with open(TOKEN_PATH) as f:
            info = _j.load(f)
        return bool(info.get("refresh_token") or info.get("access_token"))
    except Exception:
        return False

# ── RATE LIMIT: really respects the pauses requested by Spotify ──
# Before, the code ignored 429s and retried right away on the next
# polling round (500ms later) — that is what led to the 6-hour block.
# Now: if Spotify says "wait N seconds", we really stop until
# then (no new real calls), and meanwhile we serve a short cache
# to absorb the UI's frequent polling without hitting the API every time.
_rl_until = 0.0
_status_cache = {"t": 0.0, "data": None}
STATUS_CACHE_TTL = 2.0  # seconds: the UI polling (even if more frequent) draws from here

_queue_cache = {"t": 0.0, "data": None}
def _real_queue():
    """Upcoming tracks according to Spotify (GET /me/player/queue), 5 s cache."""
    now = time.time()
    if _queue_cache["data"] is not None and now - _queue_cache["t"] < 5:
        return _queue_cache["data"]
    try:
        q = _spotify_call(sp_official.queue)
        out = []
        for it in (q or {}).get("queue", [])[:20]:
            if not it or it.get("type") != "track": continue
            out.append({
                "id": it.get("id", ""),
                "title": it.get("name", ""),
                "subtitle": ", ".join(a.get("name", "") for a in it.get("artists", [])),
                "cover": get_official_img(it.get("album", {}).get("images")),
            })
        _queue_cache.update(t=now, data=out)
        return out
    except Exception:
        return None

def _spotify_call(fn, *args, **kwargs):
    """Calls a spotipy function respecting any active rate limit
    and remembering the wait duration if Spotify answers 429."""
    global _rl_until
    now = time.time()
    if now < _rl_until:
        raise RuntimeError("rate_limited")
    try:
        return fn(*args, **kwargs)
    except spotipy.SpotifyException as e:
        if getattr(e, "http_status", None) == 429:
            retry_after = 30  # prudent fallback if the header is missing
            try:
                hdrs = getattr(e, "headers", None) or {}
                ra = hdrs.get("Retry-After") or hdrs.get("retry-after")
                if ra: retry_after = int(ra)
            except Exception:
                pass
            _rl_until = time.time() + retry_after
            print(f"[spotify] Rate limit 429 — pausing real calls for {retry_after}s", flush=True)
        raise

# ── SPOTIFY CONNECT / spotifyd ──
SPOTIFYD_NAME = os.environ.get("SPOTIFYD_DEVICE", "")

def _uri(track_id):
    tid = str(track_id or "")
    return tid if tid.startswith("spotify:") else ("spotify:track:" + tid)

def _connect_device_id():
    """Finds the Spotify Connect device (spotifyd) to play on."""
    if not (is_logged_in() and sp_official):
        return None
    try:
        devs = (sp_official.devices() or {}).get("devices", [])
        if not devs:
            return None
        if SPOTIFYD_NAME:
            for d in devs:
                if SPOTIFYD_NAME.lower() in (d.get("name","") or "").lower():
                    return d["id"]
        for d in devs:
            if "spotifyd" in (d.get("name","") or "").lower():
                return d["id"]
        for d in devs:
            if d.get("is_active"):
                return d["id"]
        return devs[0]["id"]
    except Exception as e:
        print("Connect devices err:", e)
        return None

# ── ENDPOINT DI AUTENTICAZIONE ──
@app.route("/auth/status")
def auth_status():
    return jsonify({
        "logged_in": is_logged_in(),
        "login_url": "http://127.0.0.1:8098/login"
    })

# Profile of the connected account (name + photo) for the avatar at the top right.
# Cached: it rarely changes and we do not want a call to Spotify at every opening.
_account_cache = {"t": 0.0, "data": None}

@app.route("/auth/account")
def auth_account():
    if not (is_logged_in() and sp_official):
        return jsonify({"logged_in": False}), 401
    now = time.time()
    if _account_cache["data"] and now - _account_cache["t"] < 3600:
        return jsonify(_account_cache["data"])
    try:
        me = _spotify_call(sp_official.current_user) or {}
    except Exception as e:
        print("[spotify] profile not available:", e, flush=True)
        return jsonify({"name": "", "photo": ""})
    imgs = me.get("images") or []
    # the smallest photo that is at least 64 px (the avatar is tiny)
    imgs = sorted(imgs, key=lambda i: (i.get("width") or 0))
    photo = next((i.get("url") for i in imgs if (i.get("width") or 0) >= 64), imgs[-1].get("url") if imgs else "")
    data = {"name": me.get("display_name") or me.get("id") or "", "photo": photo or ""}
    _account_cache.update(t=now, data=data)
    return jsonify(data)

@app.route("/auth/logout", methods=["POST"])
def auth_logout():
    """Sign out: deletes the saved token. The UI goes back to the sign-in screen."""
    try:
        os.remove(TOKEN_PATH)
    except FileNotFoundError:
        pass
    _account_cache.update(t=0.0, data=None)
    _liked_cache.clear()
    print("[spotify] uscito dall'account", flush=True)
    return jsonify({"ok": True})

@app.route("/login")
def login():
    if sp_oauth:
        auth_url = sp_oauth.get_authorize_url()
        return redirect(auth_url)
    return "Official API not configured. Enter the Client ID and Secret in keys.env."

@app.route("/callback")
def callback():
    if sp_oauth:
        code = request.args.get('code')
        if code:
            sp_oauth.get_access_token(code)
            return """
<html>
                <body style="background:#111; color:#1DB954; font-family:sans-serif; text-align:center; padding-top:100px;">
                    <h1>✅ Spotify login completed!</h1>
                    <p style="color:#FFF;">You can close this tab and go back to your Volta OS.</p>
                </body>
            </html>
            """
    return "Error during authentication with Spotify."

# ── STATO DEL PLAYER LOCALE ──
player_state = {
    "is_playing": False,
    "progress_ms": 0,
    "duration_ms": 30000,
    "queue": [],
    "queue_pos": -1,
    "shuffle": False,
    "repeat": "off",        # "off" | "all" | "one"
    "track": None,
    "last_update": time.time()
}

# ── LOCAL RECENTS (disk cache) ──
RECENTS_PATH = os.path.expanduser("~/.config/volta/spotify_recents.json")
RECENT_SEARCHES_PATH = os.path.expanduser("~/.config/volta/spotify_recent_searches.json")
_recents = []
recent_searches = []

def _load_recents():
    global _recents, recent_searches
    try:
        with open(RECENTS_PATH) as f: _recents = json.load(f)
    except: _recents = []
    try:
        with open(RECENT_SEARCHES_PATH) as f: recent_searches = json.load(f)
    except: recent_searches = []
_load_recents()

def _push_recent(track):
    """Saves the track at the top of the recents (max 30), on disk."""
    global _recents
    if not track or not track.get("id"): return
    _recents = [t for t in _recents if t.get("id") != track["id"]]
    entry = dict(track); entry["type"] = "Track"; entry["isContext"] = False
    _recents.insert(0, entry)
    _recents = _recents[:30]
    try:
        os.makedirs(os.path.dirname(RECENTS_PATH), exist_ok=True)
        with open(RECENTS_PATH, "w") as f: json.dump(_recents, f)
    except: pass

def _q_current():
    q = player_state["queue"]; i = player_state["queue_pos"]
    return q[i] if 0 <= i < len(q) else None

# ── VOLUME: same level as YT Music ──
# spotifyd starts at 90% on a logarithmic curve (about -6 dB): Spotify came out lower than YT Music.
# At the first playback on a device it is brought to 100%; the volume is then adjusted with the system volume.
_vol_done = set()
def _ensure_full_volume():
    try:
        dev = _connect_device_id()
        if not dev or dev in _vol_done: return
        _vol_done.add(dev)
        sp_official.volume(100, device_id=dev)
    except Exception as e:
        print("[spotify] volume 100% err:", repr(e), flush=True)

def _play_at(idx):
    """Sets the track at position idx of the queue and plays it."""
    global player_state
    q = player_state["queue"]
    if not q or not (0 <= idx < len(q)): return False
    player_state["queue_pos"] = idx
    player_state["track"] = q[idx]
    player_state["is_playing"] = True
    player_state["progress_ms"] = 0
    player_state["last_update"] = time.time()
    _push_recent(q[idx])
    
    if is_logged_in() and sp_official:
        try:
            uris = [_uri(t.get("id")) for t in q[idx:idx+50] if t.get("id")]
            if uris:
                sp_official.start_playback(device_id=_connect_device_id(), uris=uris)
                _ensure_full_volume()
        except Exception as e:
            print("_play_at Connect err:", e)
    return True

def _advance(auto=False):
    """Moves to the next track (or random). auto=True: natural end of track,
    where "Repeat" also counts (one track = the same, all = start over)."""
    q = player_state["queue"]; i = player_state["queue_pos"]
    if not q: return False
    rep = player_state.get("repeat", "off")
    if auto and rep == "one" and 0 <= i < len(q):
        return _play_at(i)
    if rep == "all" and i + 1 >= len(q) and not player_state["shuffle"]:
        return _play_at(0)
    if i + 1 >= len(q) and not player_state["shuffle"]:
        cur = _q_current()
        if cur and cur.get("id"):
            _populate_radio(cur["id"], cur.get("subtitle", ""))
            q = player_state["queue"]
    if player_state["shuffle"]:
        candidates = [j for j in range(len(q)) if j != i]
        if not candidates: return False
        nxt = _random.choice(candidates)
    else:
        nxt = i + 1
    if nxt >= len(q): return False
    return _play_at(nxt)

# ── RADIO / RELATED TRACKS ──
_radio_loading = False

def _populate_radio(seed_track_id, artist_hint=""):
    """Fills the queue with tracks similar to the seed, using the anonymous scraper.
    (The official endpoint /v1/recommendations is deprecated by Spotify for
    apps without Extended Quota Mode and always answers 404 — there is no point in
    trying it: it only wastes an HTTP round that always fails.)"""
    global _radio_loading
    if _radio_loading: return
    _radio_loading = True
    try:
        seen = {t.get("id") for t in player_state["queue"] if t.get("id")}
        related = []

        # Without an artist name (e.g. /play launched without subtitle) it gets it from Spotify
        if not artist_hint and seed_track_id and is_logged_in() and sp_official:
            try:
                info = _spotify_call(sp_official.track, seed_track_id)
                arts = (info or {}).get("artists") or []
                if arts: artist_hint = arts[0].get("name", "")
            except Exception as e:
                print("[spotify] radio: seed artist not found:", repr(e), flush=True)

        if sp_scraper and artist_hint:
            # 1) Tracks by the same artist as the seed (safe base).
            try:
                results = sp_scraper.search(artist_hint, types=("track",), limit=15)
                for t in (getattr(results, "tracks", None) or []):
                    tid = getattr(t, "id", "") or ""
                    if not tid or tid in seen: continue
                    seen.add(tid)
                    arts = getattr(t, "artists", None) or []
                    related.append({
                        "id": tid,
                        "title": getattr(t, "name", "") or "",
                        "subtitle": ", ".join(getattr(a, "name", "") for a in arts),
                        "cover": get_img(t),
                        "duration": format_ms(getattr(t, "duration_ms", 0) or 0),
                        "type": "Track",
                    })
            except Exception as e:
                print("[spotify] radio scraper (search artista) err:", e, flush=True)

            # 2) Tracks by SIMILAR ARTISTS (get_related_artists), for a more
            # varied mix than a simple "only songs by the same artist" —
            # it is the closest equivalent to a real "radio" that the anonymous
            # scraper allows.
            try:
                res_art = sp_scraper.search(artist_hint, types=("artist",), limit=1)
                seed_artists = getattr(res_art, "artists", None) or []
                if seed_artists:
                    seed_artist_id = getattr(seed_artists[0], "id", "") or ""
                    if seed_artist_id:
                        rel_artists = sp_scraper.get_related_artists(seed_artist_id)
                        for ra in (rel_artists or [])[:4]:
                            for t in (getattr(ra, "top_tracks", None) or [])[:4]:
                                tid = getattr(t, "id", "") or ""
                                if not tid or tid in seen: continue
                                seen.add(tid)
                                arts = getattr(t, "artists", None) or []
                                related.append({
                                    "id": tid,
                                    "title": getattr(t, "name", "") or "",
                                    "subtitle": ", ".join(getattr(a, "name", "") for a in arts) or getattr(ra, "name", ""),
                                    "cover": get_img(t),
                                    "duration": format_ms(getattr(t, "duration_ms", 0) or 0),
                                    "type": "Track",
                                })
            except Exception as e:
                print("[spotify] radio scraper (artisti simili) err:", e, flush=True)

        # Last resort: the artist's top tracks via the official API
        if not related and artist_hint and is_logged_in() and sp_official:
            try:
                res = _spotify_call(sp_official.search, q=f'artist:"{artist_hint}"', type="track", limit=20)
                for it in ((res or {}).get("tracks") or {}).get("items", []):
                    tid = it.get("id", "")
                    if not tid or tid in seen: continue
                    seen.add(tid)
                    related.append({
                        "id": tid, "title": it.get("name", ""),
                        "subtitle": ", ".join(a.get("name", "") for a in it.get("artists", [])),
                        "cover": get_official_img((it.get("album") or {}).get("images")),
                        "duration": format_ms(it.get("duration_ms", 0) or 0), "type": "Track",
                    })
            except Exception as e:
                print("[spotify] radio (fallback API) err:", repr(e), flush=True)

        if related:
            player_state["queue"].extend(related)
        print(f"[spotify] radio: +{len(related)} tracks (seed {seed_track_id}, artist '{artist_hint}')", flush=True)
    finally:
        _radio_loading = False

def _radio_enqueue_bg(seed_id, artist_hint=""):
    """Creates the track's radio and puts it in Spotify's REAL QUEUE, so that
    after the chosen track similar tracks keep starting."""
    def run():
        old_len = len(player_state["queue"])
        _populate_radio(seed_id, artist_hint)
        new = player_state["queue"][old_len:]
        dev = None
        if is_logged_in() and sp_official:
            dev = _connect_device_id()
            for nt in new[:25]:
                if not nt.get("id"): continue
                try: _spotify_call(sp_official.add_to_queue, _uri(nt["id"]), device_id=dev)
                except Exception as e:
                    print("[spotify] add_to_queue err:", repr(e), flush=True)
                    break
        _queue_cache["data"] = None
        _status_cache["data"] = None
    threading.Thread(target=run, daemon=True).start()

def _populate_radio_bg(seed_id, artist_hint=""):
    threading.Thread(target=_populate_radio, args=(seed_id, artist_hint), daemon=True).start()

def format_ms(ms):
    if not ms:
        return "0:00"
    m = int(ms) // 60000
    s = int((ms // 1000) % 60)
    return f"{m}:{s:02d}"

def get_img(obj):
    if isinstance(obj, dict):
        imgs = obj.get("images", [])
        return imgs[0]["url"] if imgs else ""
    if hasattr(obj, "images") and obj.images:
        return obj.images[0].url if hasattr(obj.images[0], "url") else (obj.images[0].get("url", "") if isinstance(obj.images[0], dict) else "")
    return ""

def get_official_img(images):
    return images[0]['url'] if images and len(images) > 0 else ""

def update_player():
    global player_state
    if player_state["is_playing"]:
        now = time.time()
        player_state["progress_ms"] += (now - player_state["last_update"]) * 1000
        if player_state["progress_ms"] >= player_state["duration_ms"]:
            if not _advance(auto=True):
                player_state["progress_ms"] = player_state["duration_ms"]
                player_state["is_playing"] = False
    player_state["last_update"] = time.time()

# ── ENDPOINT CONTROLLI E CODA ──
@app.route("/player/status")
def player_status():
    global player_state
    if is_logged_in() and sp_official:
        now = time.time()
        # Serves from the short cache if recent: absorbs the UI's frequent
        # polling without hitting Spotify's API on every single request.
        if _status_cache["data"] is not None and (now - _status_cache["t"]) < STATUS_CACHE_TTL:
            return jsonify(_status_cache["data"])
        try:
            cur = _spotify_call(sp_official.current_playback)
            if cur and cur.get("item"):
                it = cur["item"]
                tid = it.get("id", "")
                
                if player_state["track"] and player_state["track"].get("id") != tid:
                    new_idx = player_state["queue_pos"]
                    for j, qt in enumerate(player_state["queue"]):
                        if qt.get("id") == tid:
                            new_idx = j
                            break
                    
                    player_state["queue_pos"] = new_idx
                    player_state["track"] = {
                        "id": tid,
                        "title": it.get("name",""),
                        "subtitle": it["artists"][0]["name"] if it.get("artists") else "",
                        "cover": get_official_img(it.get("album",{}).get("images"))
                    }
                    _push_recent(player_state["track"])
                    
                    if player_state["queue_pos"] >= len(player_state["queue"]) - 3:
                        def bg_add():
                            old_len = len(player_state["queue"])
                            _populate_radio(tid, player_state["track"]["subtitle"])
                            for nt in player_state["queue"][old_len:]:
                                try: _spotify_call(sp_official.add_to_queue, _uri(nt["id"]), device_id=_connect_device_id())
                                except: pass
                        threading.Thread(target=bg_add, daemon=True).start()

                player_state["is_playing"]  = bool(cur.get("is_playing"))
                # Shuffle / Repeat as Spotify really sees them
                # (not right after changing them from here: Spotify takes a moment)
                _fresh = time.time() - player_state.get("modes_set_at", 0) < 6
                if "shuffle_state" in cur and not _fresh:
                    player_state["shuffle"] = bool(cur.get("shuffle_state"))
                if "repeat_state" in cur and not _fresh:
                    _sp_rep = {"track": "one", "context": "all"}.get(cur.get("repeat_state"), "off")
                    # "repeat track" is also handled by us (see _repeat_one_watch): if Spotify has not
                    # accepted it and says "off", the button must not turn off by itself
                    if not (player_state.get("repeat") == "one" and _sp_rep == "off"):
                        player_state["repeat"] = _sp_rep
                player_state["progress_ms"] = cur.get("progress_ms",0) or 0
                player_state["duration_ms"] = it.get("duration_ms",0) or 0
                player_state["last_update"] = time.time()
                
                resp = dict(player_state)
                pos = resp.get("queue_pos", -1)
                resp["queue"] = resp["queue"][pos + 1:] if pos >= 0 else []
                # REAL Spotify queue (with Shuffle on the order is decided by
                # Spotify: our local list would stay linear)
                real = _real_queue()
                if real is not None: resp["queue"] = real
                _status_cache["data"] = resp
                _status_cache["t"] = now
                return jsonify(resp)
        except RuntimeError:
            pass  # rate_limited: no real call, we drop to the fallback below
        except Exception as e:
            print(f"[spotify] player_status err: {e!r}", flush=True)
            
    update_player()
    resp = dict(player_state)
    pos = resp.get("queue_pos", -1)
    resp["queue"] = resp["queue"][pos + 1:] if pos >= 0 else []
    return jsonify(resp)

@app.route("/play/<track_id>")
def play_track(track_id):
    global player_state
    t = {
        "id": track_id,
        "title": request.args.get("title", ""),
        "subtitle": request.args.get("subtitle", ""),
        "cover": request.args.get("cover", "")
    }
    player_state["track"] = t
    player_state["queue"] = [t]
    player_state["queue_pos"] = 0
    _push_recent(t)

    try: start_ms = max(0, int(float(request.args.get("start_ms", 0) or 0)))
    except Exception: start_ms = 0
    if start_ms < 3000: start_ms = 0

    if is_logged_in() and sp_official:
        try:
            if start_ms: sp_official.start_playback(device_id=_connect_device_id(), uris=[_uri(track_id)], position_ms=start_ms)
            else: sp_official.start_playback(device_id=_connect_device_id(), uris=[_uri(track_id)])
            _ensure_full_volume()
        except Exception as e:
            print("start_playback err:", e)

    # Radio: similar tracks are queued on Spotify as soon as they are ready
    _radio_enqueue_bg(track_id, t.get("subtitle", ""))

    player_state["is_playing"] = True
    player_state["progress_ms"] = start_ms
    player_state["last_update"] = time.time()
    return jsonify({"status": "playing"})

@app.route("/play_context", methods=["POST"])
def play_context():
    data = request.get_json(force=True, silent=True) or {}
    global player_state
    tracks = data.get("tracks", [])
    index = data.get("index", 0)
    if tracks and len(tracks) > index:
        player_state["queue"] = tracks
        player_state["queue_pos"] = index
        player_state["track"] = tracks[index]
        
        _push_recent(tracks[index])
        
        if is_logged_in() and sp_official:
            try:
                uris = [_uri(t.get("id")) for t in player_state["queue"][index:index+50] if t.get("id")]
                if uris:
                    sp_official.start_playback(device_id=_connect_device_id(), uris=uris)
                    _ensure_full_volume()
            except Exception as e:
                print("play_context Connect err:", e)

        # Single track (or last of the list): creates the radio and queues it
        if index >= len(tracks) - 1:
            _radio_enqueue_bg(tracks[index].get("id"), tracks[index].get("subtitle", ""))

        player_state["is_playing"] = True
        player_state["progress_ms"] = 0
        player_state["last_update"] = time.time()
        return jsonify({"status": "playing"})
    return jsonify({"status": "error", "error": "No track"})

@app.route("/player/pause")
def pause_player():
    global player_state
    update_player()
    play = (request.args.get("state", "1") == "0")
    player_state["is_playing"] = play
    player_state["last_update"] = time.time()
    if is_logged_in() and sp_official:
        try:
            if play: sp_official.start_playback(device_id=_connect_device_id())
            else:    sp_official.pause_playback(device_id=_connect_device_id())
        except Exception: pass
    return jsonify({"paused": not player_state["is_playing"]})

@app.route("/player/next")
def player_next():
    _advance()
    return jsonify({"track": player_state.get("track")})

@app.route("/player/prev")
def player_prev():
    i = player_state["queue_pos"]
    if player_state["progress_ms"] > 3000:
        player_state["progress_ms"] = 0
        player_state["last_update"] = time.time()
        if is_logged_in() and sp_official:
            try: sp_official.seek_track(0, device_id=_connect_device_id())
            except Exception: pass
    elif i > 0:
        _play_at(i - 1)
    else:
        _play_at(0)
    return jsonify({"track": player_state.get("track")})

@app.route("/player/seek")
def seek_player():
    pct = float(request.args.get("pct", 0))
    global player_state
    player_state["progress_ms"] = player_state["duration_ms"] * pct
    player_state["last_update"] = time.time()
    if is_logged_in() and sp_official:
        try: sp_official.seek_track(int(player_state["duration_ms"] * pct), device_id=_connect_device_id())
        except Exception: pass
    return jsonify({"status": "ok"})

@app.route("/player/shuffle")
def player_shuffle():
    """?state=1 turns on, ?state=0 turns off, without a parameter it toggles."""
    global player_state
    st = request.args.get("state")
    player_state["shuffle"] = (not player_state["shuffle"]) if st is None else (st == "1")
    player_state["modes_set_at"] = time.time()
    _status_cache["data"] = None
    _queue_cache["data"] = None
    if is_logged_in() and sp_official:
        try: _spotify_call(sp_official.shuffle, player_state["shuffle"], device_id=_connect_device_id())
        except Exception as e: print("[spotify] shuffle err:", repr(e), flush=True)
    return jsonify({"shuffle": player_state["shuffle"], "repeat": player_state["repeat"]})

@app.route("/player/repeat")
def player_repeat():
    """?mode=off|all|one; without a parameter it moves to the next (off → all → one → off)."""
    global player_state
    m = request.args.get("mode")
    if m not in ("off", "all", "one"):
        m = {"off": "all", "all": "one"}.get(player_state.get("repeat", "off"), "off")
    player_state["repeat"] = m
    player_state["modes_set_at"] = time.time()
    _status_cache["data"] = None
    if is_logged_in() and sp_official:
        try: _spotify_call(sp_official.repeat, {"one": "track", "all": "context"}.get(m, "off"), device_id=_connect_device_id())
        except Exception as e: print("[spotify] repeat err:", repr(e), flush=True)
    return jsonify({"shuffle": player_state["shuffle"], "repeat": m})

@app.route("/player/enqueue_next")
def enqueue_next():
    global player_state
    new_track = {
        "id": request.args.get("id", ""),
        "title": request.args.get("title", ""),
        "subtitle": request.args.get("subtitle", ""),
        "cover": request.args.get("cover", "")
    }
    player_state["queue"].append(new_track)
    
    if is_logged_in() and sp_official:
        try: sp_official.add_to_queue(_uri(new_track["id"]), device_id=_connect_device_id())
        except Exception: pass
        
    return jsonify({"status": "ok"})

_liked_cache = {}   # track id → in "Liked Songs"?

@app.route("/player/like/<track_id>")
def like_track(track_id):
    action = request.args.get("action", "LIKE")
    ok = False
    if is_logged_in() and sp_official:
        try:
            if action == "LIKE": sp_official.current_user_saved_tracks_add(tracks=[track_id])
            else: sp_official.current_user_saved_tracks_delete(tracks=[track_id])
            ok = True
        except Exception as e:
            print(f"[spotify] like failed: {e!r}", flush=True)
    if ok: _liked_cache[track_id] = (action == "LIKE")
    return jsonify({"status": "ok" if ok else "error", "liked": _liked_cache.get(track_id, False)})

@app.route("/player/liked/<track_id>")
def liked_track(track_id):
    if track_id in _liked_cache: return jsonify({"liked": _liked_cache[track_id]})
    liked = False
    if is_logged_in() and sp_official:
        try:
            liked = bool(sp_official.current_user_saved_tracks_contains(tracks=[track_id])[0])
            _liked_cache[track_id] = liked
        except Exception: pass
    return jsonify({"liked": liked})

# ── SEARCH ENDPOINT ──
@app.route("/search")
def search():
    q = request.args.get("q", "")
    if not q:
        return jsonify({"tracks":[], "albums":[], "artists":[], "playlists":[], "videos":[]})
    
    tr, al, ar, pl = [], [], [], []

    if is_logged_in() and sp_official:
        try:
            raw = sp_official.search(q=q, type="track,album,artist,playlist", limit=6)
            for t in raw.get("tracks", {}).get("items", []):
                tr.append({
                    "id": t["id"], "title": t["name"],
                    "subtitle": t["artists"][0]["name"] if t.get("artists") else "",
                    "album": t.get("album", {}).get("name", ""),
                    "cover": get_official_img(t.get("album", {}).get("images")),
                    "duration": format_ms(t.get("duration_ms", 0)),
                    "type": "Track"
                })
            for a in raw.get("albums", {}).get("items", []):
                al.append({
                    "id": a["id"], "title": a["name"],
                    "subtitle": a["artists"][0]["name"] if a.get("artists") else "",
                    "cover": get_official_img(a.get("images")),
                    "type": "Album"
                })
            for a in raw.get("artists", {}).get("items", []):
                ar.append({
                    "id": a["id"], "title": a["name"],
                    "subtitle": "Artista",
                    "cover": get_official_img(a.get("images")),
                    "type": "Artist"
                })
            for p in raw.get("playlists", {}).get("items", []):
                if not p: continue
                pl.append({
                    "id": p["id"], "title": p["name"],
                    "subtitle": p.get("owner", {}).get("display_name", ""),
                    "cover": get_official_img(p.get("images")),
                    "type": "Playlist"
                })
            return jsonify({"tracks": tr, "albums": al, "artists": ar, "playlists": pl, "videos": []})
        except Exception:
            pass

    if sp_scraper:
        try:
            res = sp_scraper.search(q)
            for t in getattr(res, "tracks", []):
                tr.append({
                    "id": getattr(t, "id", ""), "title": getattr(t, "name", ""),
                    "subtitle": t.artists[0].name if hasattr(t, "artists") and t.artists else "",
                    "album": t.album.name if hasattr(t, "album") and t.album else "",
                    "cover": get_img(t.album) if hasattr(t, "album") else "",
                    "duration": format_ms(getattr(t, "duration_ms", 0)),
                    "type": "Track"
                })
            for a in getattr(res, "albums", []):
                al.append({
                    "id": getattr(a, "id", ""), "title": getattr(a, "name", ""),
                    "subtitle": a.artists[0].name if hasattr(a, "artists") and a.artists else "",
                    "cover": get_img(a), "type": "Album"
                })
            for a in getattr(res, "artists", []):
                ar.append({
                    "id": getattr(a, "id", ""), "title": getattr(a, "name", ""),
                    "subtitle": "Artista", "cover": get_img(a), "type": "Artist"
                })
            for p in getattr(res, "playlists", []):
                pl.append({
                    "id": getattr(p, "id", ""), "title": getattr(p, "name", ""),
                    "subtitle": p.owner.name if hasattr(p, "owner") and p.owner else "",
                    "cover": get_img(p), "type": "Playlist"
                })
        except Exception:
            pass

    return jsonify({"tracks": tr, "albums": al, "artists": ar, "playlists": pl, "videos": []})

# ── ENDPOINT UI HOME ──
@app.route("/ui/home")
def home():
    shelves = []
    quick_picks = []
    global _recents

    # 1. SCELTE RAPIDE (Combina recenti locali e top tracks)
    try:
        for t in _recents[:8]:
            if t and t.get("id") and not any(x['id'] == t['id'] for x in quick_picks):
                quick_picks.append({
                    "id": t['id'],
                    "title": t.get('title', ''),
                    "subtitle": t.get('subtitle', ''),
                    "cover": t.get('cover', ''),
                    "type": "Track"
                })
        
        if is_logged_in() and sp_official:
            top_tr = sp_official.current_user_top_tracks(limit=10, time_range="short_term").get('items', [])
            for t in top_tr:
                if t and t.get("id") and not any(x['id'] == t['id'] for x in quick_picks):
                    quick_picks.append({
                        "id": t['id'],
                        "title": t['name'],
                        "subtitle": t['artists'][0]['name'] if t.get('artists') else "",
                        "cover": get_official_img(t.get('album', {}).get('images')),
                        "type": "Track"
                    })
        
        if quick_picks:
            _random.shuffle(quick_picks)
            shelves.append({"title": "Scelte rapide", "items": quick_picks[:8], "isCircle": False})
    except Exception as e:
        print("Quick Picks error:", e)

    # 2. RECENTLY PLAYED (Draws DIRECTLY from the local _recents cache)
    if _recents:
        shelves.append({"title": "Recently played", "items": _recents[:15], "isCircle": False})

    # 3. I TUOI ARTISTI PREFERITI (Spotipy)
    if is_logged_in() and sp_official:
        try:
            top_ar = sp_official.current_user_top_artists(limit=15, time_range="medium_term").get('items', [])
            if top_ar:
                ar_items = [{
                    "id": ar['id'],
                    "title": ar['name'],
                    "subtitle": "Artista",
                    "cover": get_official_img(ar.get('images')),
                    "type": "Artist"
                } for ar in top_ar if ar and ar.get('id')]
                if ar_items:
                    shelves.append({"title": "I tuoi artisti preferiti", "items": ar_items, "isCircle": True})
        except Exception as e:
            print("Artists error:", e)

        # 4. "Simili a..." rimosso: /v1/recommendations risponde sempre 404
        #    (deprecated by Spotify for apps without Extended Quota Mode).

    # 5. CLASSIFICHE E TENDENZE ITALIANE (Scraper)
    if sp_scraper:
        try:
            res_trend = sp_scraper.search("Top 50 Italia")
            pl_items = [{
                "id": getattr(p, "id", ""),
                "title": getattr(p, "name", ""),
                "subtitle": p.owner.name if hasattr(p, "owner") and p.owner else "Spotify",
                "cover": get_img(p),
                "type": "Playlist"
            } for p in getattr(res_trend, "playlists", [])[:15] if getattr(p, "id", None)]
            if pl_items:
                shelves.append({"title": "Classifiche e Tendenze", "items": pl_items, "isCircle": False})
        except Exception as e:
            print("Trends error:", e)

        # 6. ESPLORA MOOD/GENERI (Scraper)
        try:
            moods = ["Pop Italiano", "Indie Italia", "Viaggio in auto", "Energia", "Chill", "Rap Italiano"]
            mood = _random.choice(moods)
            res_mood = sp_scraper.search(f"Playlist {mood}")
            mood_items = [{
                "id": getattr(p, "id", ""),
                "title": getattr(p, "name", ""),
                "subtitle": p.owner.name if hasattr(p, "owner") and p.owner else "Spotify",
                "cover": get_img(p),
                "type": "Playlist"
            } for p in getattr(res_mood, "playlists", [])[:15] if getattr(p, "id", None)]
            if mood_items:
                shelves.append({"title": f"Esplora: {mood}", "items": mood_items, "isCircle": False})
        except Exception as e:
            print("Mood error:", e)

        # 7. ALBUM DEL MOMENTO (Scraper)
        try:
            res_al = sp_scraper.search("Nuove Uscite")
            al_items = [{
                "id": getattr(a, "id", ""),
                "title": getattr(a, "name", ""),
                "subtitle": a.artists[0].name if hasattr(a, "artists") and a.artists else "",
                "cover": get_img(a),
                "type": "Album"
            } for a in getattr(res_al, "albums", [])[:15] if getattr(a, "id", None)]
            if al_items:
                shelves.append({"title": "Albums of the moment", "items": al_items, "isCircle": False})
        except Exception as e:
            print("Albums error:", e)

    return jsonify({"shelves": shelves})

@app.route("/ui/library")
def library():
    filter_type = request.args.get("filter", "playlists").lower()
    items = []
    
    if is_logged_in() and sp_official:
        try:
            if filter_type == "songs":
                my_tr = sp_official.current_user_saved_tracks(limit=20)
                for item in my_tr.get('items', []):
                    t = item['track']
                    items.append({
                        "id": t['id'], "title": t['name'], "subtitle": t['artists'][0]['name'],
                        "album": t['album']['name'], "cover": get_official_img(t['album'].get('images')),
                        "duration": format_ms(t.get("duration_ms", 0)), "type": "Track"
                    })
            elif filter_type == "albums":
                my_al = sp_official.current_user_saved_albums(limit=20)
                for item in my_al.get('items', []):
                    a = item['album']
                    items.append({
                        "id": a['id'], "title": a['name'], "subtitle": a['artists'][0]['name'],
                        "cover": get_official_img(a.get('images')), "type": "Album"
                    })
        except Exception:
            pass
            
    if sp_scraper and len(items) == 0:
        try:
            search_query = "Hits" if filter_type == "playlists" else ("Pop" if filter_type == "artists" else "Best of")
            res = sp_scraper.search(search_query)
            if filter_type == "playlists":
                items = [{
                    "id": getattr(p, "id", ""), "title": getattr(p, "name", ""),
                    "subtitle": p.owner.name if hasattr(p, "owner") and p.owner else "",
                    "cover": get_img(p), "type": "Playlist"
                } for p in getattr(res, "playlists", [])[:15]]
            elif filter_type == "albums":
                items = [{
                    "id": getattr(a, "id", ""), "title": getattr(a, "name", ""),
                    "subtitle": a.artists[0].name if hasattr(a, "artists") and a.artists else "",
                    "cover": get_img(a), "type": "Album"
                } for a in getattr(res, "albums", [])[:15]]
            elif filter_type == "artists":
                items = [{
                    "id": getattr(ar, "id", ""), "title": getattr(ar, "name", ""),
                    "subtitle": "Artista", "cover": get_img(ar), "type": "Artist"
                } for ar in getattr(res, "artists", [])[:15]]
        except Exception:
            pass

    return jsonify({"items": items})

@app.route("/ui/recent_searches")
def recent_searches_get():
    return jsonify({"items": recent_searches})

@app.route("/ui/recent_searches/add")
def recent_searches_add():
    global recent_searches
    q = (request.args.get("q", "") or "").strip()
    if len(q) < 2: return jsonify({"items": recent_searches})
    low = q.lower()
    recent_searches = [q] + [x for x in recent_searches if x.lower() != low]
    recent_searches = recent_searches[:8]
    try:
        os.makedirs(os.path.dirname(RECENT_SEARCHES_PATH), exist_ok=True)
        with open(RECENT_SEARCHES_PATH, "w") as f: json.dump(recent_searches, f)
    except: pass
    return jsonify({"items": recent_searches})

@app.route("/ui/recents")
def recents():
    return jsonify({"items": _recents})

# ── PLAYLIST / ALBUM DETAIL (WITH SAFE FALLBACK) ──
@app.route("/playlist/<item_id>")
def get_playlist(item_id):
    q_type = request.args.get("type", "playlist")

    if is_logged_in() and sp_official:
        try:
            is_album = (q_type == "album")
            raw = sp_official.album(item_id) if is_album else sp_official.playlist(item_id)
            tr = []
            tracks_raw = raw.get("tracks", {}).get("items", []) if raw else []
            
            # If the official playlist response contains no items, use playlist_items
            if not is_album and not tracks_raw:
                items_res = sp_official.playlist_items(item_id)
                tracks_raw = items_res.get("items", []) if items_res else []

            for idx, item in enumerate(tracks_raw):
                if not item: continue
                t = item.get("track", item) if not is_album else item
                if not t or not isinstance(t, dict) or not t.get("id"): continue
                
                album_obj = t.get("album", {}) if isinstance(t.get("album"), dict) else {}
                cover = get_official_img(raw.get("images")) if is_album else (get_official_img(album_obj.get("images")) or get_official_img(raw.get("images")))
                
                tr.append({
                    "id": t["id"],
                    "num": idx + 1,
                    "title": t.get("name", ""),
                    "subtitle": t["artists"][0]["name"] if t.get("artists") and isinstance(t["artists"], list) and len(t["artists"]) > 0 else "",
                    "album": raw.get("name", "") if is_album else album_obj.get("name", ""),
                    "cover": cover,
                    "duration": format_ms(t.get("duration_ms", 0)),
                    "type": "Track"
                })
            
            if tr:
                return jsonify({
                    "type": "Album" if is_album else "Playlist",
                    "title": raw.get("name", ""),
                    "cover": get_official_img(raw.get("images")),
                    "tracks": tr
                })
        except Exception as e:
            print("get_playlist official err:", e)

    if sp_scraper:
        try:
            obj = sp_scraper.get_album(item_id) if q_type == "album" else sp_scraper.get_playlist(item_id)
            tr = []
            raw_tracks = getattr(obj, "tracks", [])
            if hasattr(raw_tracks, "items"): raw_tracks = raw_tracks.items
            for idx, t_wrap in enumerate(raw_tracks):
                t = getattr(t_wrap, "track", t_wrap) if q_type == "playlist" else t_wrap
                if not t: continue
                cover = get_img(obj) if q_type == "album" else (get_img(t.album) if hasattr(t, "album") else "")
                album_name = getattr(obj, "name", "") if q_type == "album" else (t.album.name if hasattr(t, "album") and t.album else "")
                tr.append({
                    "id": getattr(t, "id", "") or "",
                    "num": idx + 1,
                    "title": getattr(t, "name", "") or "",
                    "subtitle": t.artists[0].name if hasattr(t, "artists") and t.artists else "",
                    "album": album_name,
                    "cover": cover,
                    "duration": format_ms(getattr(t, "duration_ms", 0) or 0),
                    "type": "Track"
                })
            return jsonify({
                "type": "Album" if q_type == "album" else "Playlist",
                "title": getattr(obj, "name", "") or "",
                "cover": get_img(obj),
                "tracks": tr
            })
        except Exception as e:
            print("get_playlist scraper err:", e)

    return jsonify({"tracks": []})

@app.route("/artist/<artist_id>")
def get_artist(artist_id):
    if is_logged_in() and sp_official:
        try:
            artist = sp_official.artist(artist_id)
            top_tracks = sp_official.artist_top_tracks(artist_id)
            albums = sp_official.artist_albums(artist_id, album_type="album", limit=6)
            singles = sp_official.artist_albums(artist_id, album_type="single", limit=6)

            tr = [{
                "id": t["id"], "title": t["name"],
                "subtitle": t["artists"][0]["name"] if t.get("artists") else "",
                "album": t.get("album", {}).get("name", ""),
                "cover": get_official_img(t.get("album", {}).get("images")),
                "duration": format_ms(t.get("duration_ms", 0)), "type": "Track"
            } for t in top_tracks.get("tracks", [])]

            al = [{
                "id": a["id"], "title": a["name"], "subtitle": "Album",
                "cover": get_official_img(a.get("images")), "type": "Album"
            } for a in albums.get("items", [])]

            sg = [{
                "id": s["id"], "title": s["name"], "subtitle": "Singolo",
                "cover": get_official_img(s.get("images")), "type": "Album"
            } for s in singles.get("items", [])]

            return jsonify({
                "name": artist.get("name", ""),
                "cover": get_official_img(artist.get("images")),
                "tracks": tr, "albums": al, "singles": sg
            })
        except Exception:
            pass

    if sp_scraper:
        try:
            artist = sp_scraper.get_artist(artist_id)

            def _sc_track(t, i):
                arts = getattr(t, "artists", None) or []
                sub = ", ".join(getattr(a, "name", "") for a in arts if getattr(a, "name", ""))
                alb = getattr(t, "album", None)
                return {
                    "id": getattr(t, "id", "") or "",
                    "title": getattr(t, "name", "") or "",
                    "subtitle": sub,
                    "album": getattr(alb, "name", "") if alb is not None else "",
                    "cover": get_img(t) or (get_img(alb) if alb is not None else ""),
                    "duration": format_ms(getattr(t, "duration_ms", 0) or 0),
                    "type": "Track", "isContext": False, "num": i + 1, "isLiked": False,
                }

            def _sc_alb(a, subtitle):
                return {
                    "id": getattr(a, "id", "") or "",
                    "title": getattr(a, "name", "") or "",
                    "subtitle": subtitle,
                    "cover": get_img(a),
                    "type": "Album",
                }

            tops  = getattr(artist, "top_tracks", None) or []
            albs  = getattr(artist, "albums", None) or []
            sings = getattr(artist, "singles", None) or []
            return jsonify({
                "name":   getattr(artist, "name", "") or "",
                "cover":  get_img(artist),
                "tracks":  [_sc_track(t, i) for i, t in enumerate(tops)],
                "albums":  [_sc_alb(a, "Album")   for a in albs],
                "singles": [_sc_alb(s, "Singolo") for s in sings],
            })
        except Exception as e:
            print("artist scraper err:", e)

    return jsonify({"tracks": [], "albums": [], "singles": []})

# ── EXPLORE: playlists/albums of a category + card covers ──
# The Explore tab's cards have a fixed color; the cover inside the card is that of the first
# editorial playlist (by "Spotify") found for that category: it changes by itself when Spotify changes its playlists.
_cat_cache = {}                      # "type|query" -> [time, items]  (saved to disk: it is ready right away on opening)
_cat_cover = {}                      # nome categoria -> {"url": ..., "t": ...}
_cat_queue = []                      # [(name, query, type)] to update, one every ~1 s (no bursts)
_cat_lock = threading.Lock()
_cat_worker_on = False
_cat_inflight = {}                   # key -> Lock (only one search at a time per category)
_cat_refreshing = set()
_CAT_COVER_PATH = os.path.expanduser("~/.config/volta/spotify_category_covers.json")
_CAT_ITEMS_PATH = os.path.expanduser("~/.config/volta/spotify_category_items.json")
_CAT_COVER_TTL = 12 * 3600
_CAT_ITEMS_TTL = 1800
try:
    with open(_CAT_COVER_PATH) as _f: _cat_cover = json.load(_f)
except Exception:
    _cat_cover = {}
try:
    with open(_CAT_ITEMS_PATH) as _f: _cat_cache = json.load(_f)
except Exception:
    _cat_cache = {}

def _cat_save_items():
    try:
        os.makedirs(os.path.dirname(_CAT_ITEMS_PATH), exist_ok=True)
        tmp = _CAT_ITEMS_PATH + ".tmp"
        with open(tmp, "w") as f: json.dump(_cat_cache, f)
        os.replace(tmp, _CAT_ITEMS_PATH)
    except Exception:
        pass

def _cat_search(q, kind):
    """A real (slow) search: playlists and albums, falling back to the official API."""
    pls, als = [], []
    if sp_scraper:
        try:
            res = sp_scraper.search(q)
            for p in list(getattr(res, "playlists", []) or [])[:40]:
                if getattr(p, "id", None):
                    pls.append({"id": getattr(p, "id", ""), "title": getattr(p, "name", ""),
                                "subtitle": p.owner.name if hasattr(p, "owner") and p.owner else "Spotify",
                                "cover": get_img(p), "type": "Playlist"})
            for a in list(getattr(res, "albums", []) or [])[:30]:
                if getattr(a, "id", None):
                    als.append({"id": getattr(a, "id", ""), "title": getattr(a, "name", ""),
                                "subtitle": a.artists[0].name if hasattr(a, "artists") and a.artists else "",
                                "cover": get_img(a), "type": "Album"})
        except Exception as e:
            print("Category error:", e)
    if not pls and not als and is_logged_in() and sp_official:
        try:
            raw = sp_official.search(q=q, type="playlist,album", limit=10)
            for p in (raw.get("playlists", {}) or {}).get("items", []) or []:
                if p and p.get("id"):
                    pls.append({"id": p["id"], "title": p.get("name", ""),
                                "subtitle": (p.get("owner") or {}).get("display_name", ""),
                                "cover": get_official_img(p.get("images")), "type": "Playlist"})
            for a in (raw.get("albums", {}) or {}).get("items", []) or []:
                if a and a.get("id"):
                    als.append({"id": a["id"], "title": a.get("name", ""),
                                "subtitle": a["artists"][0]["name"] if a.get("artists") else "",
                                "cover": get_official_img(a.get("images")), "type": "Album"})
        except Exception as e:
            print("Category error (official):", e)
    return pls, als

def _cat_fetch(q, kind):
    base = (q or "").strip()
    if not base: return []
    # as "Explore: Italian Rap" already does in the Home: the search "Playlist <category>" finds the Spotify playlists
    tries = [base]
    if kind != "albums" and not base.lower().startswith(("top", "playlist")):
        tries = ["Playlist " + base, base]
    pls, als = [], []
    for qq in tries:
        pls, als = _cat_search(qq, kind)
        if pls or als: break
    # editorial playlists (by "Spotify") first; the others only to fill in if there are few
    ed = [p for p in pls if (p.get("subtitle") or "").strip().lower() == "spotify"]
    rest = [p for p in pls if p not in ed]
    pls = ed + (rest if len(ed) < 8 else [])
    return (als + pls) if kind == "albums" else (pls + als)

def _cat_refresh(key, q, kind):
    try:
        items = _cat_fetch(q, kind)
        if items:
            _cat_cache[key] = [time.time(), items]
            _cat_save_items()
    finally:
        _cat_refreshing.discard(key)

def _cat_items(q, kind, fresh=False):
    """Right away from memory/disk if present (even if old: meanwhile it updates in the background);
    otherwise it does the search. Several requests for the same category wait for the same search."""
    q = (q or "").strip()
    if not q: return []
    key = "%s|%s" % (kind, q.lower())
    hit = _cat_cache.get(key)
    if hit and hit[1] and not fresh:
        if time.time() - hit[0] > _CAT_ITEMS_TTL and key not in _cat_refreshing:
            _cat_refreshing.add(key)
            threading.Thread(target=_cat_refresh, args=(key, q, kind), daemon=True).start()
        return hit[1]
    with _cat_lock:
        lk = _cat_inflight.setdefault(key, threading.Lock())
    with lk:
        hit = _cat_cache.get(key)
        if hit and hit[1] and time.time() - hit[0] < 60:   # another request has just filled it
            return hit[1]
        items = _cat_fetch(q, kind)
        if items:
            _cat_cache[key] = [time.time(), items]
            _cat_save_items()
        return items

@app.route("/ui/category")
def ui_category():
    return jsonify({"items": _cat_items(request.args.get("q"), request.args.get("kind", "playlists"))})

def _cat_cover_worker():
    global _cat_worker_on
    try:
        while True:
            with _cat_lock:
                job = _cat_queue.pop(0) if _cat_queue else None
            if job is None: break
            name, q, kind = job
            try:
                items = _cat_items(q, kind, fresh=True)
                url = next((i["cover"] for i in items if i.get("cover")), "")
                if not url:   # nothing found: retry in 10 minutes, not in bursts
                    _cat_cover[name] = {"url": "", "t": time.time() - _CAT_COVER_TTL + 600}
                if url:
                    _cat_cover[name] = {"url": url, "t": time.time()}
                    try:
                        os.makedirs(os.path.dirname(_CAT_COVER_PATH), exist_ok=True)
                        with open(_CAT_COVER_PATH, "w") as f: json.dump(_cat_cover, f)
                    except Exception: pass
            except Exception as e:
                print("Category cover error:", e)
            time.sleep(1.0)
    finally:
        _cat_worker_on = False

@app.route("/ui/category_covers")
def ui_category_covers():
    """?c=Name~query[~albums] (repeatable). Answers right away with what is in cache; updates in the background."""
    global _cat_worker_on
    now = time.time(); out = {}
    for spec in request.args.getlist("c")[:60]:
        parts = spec.split("~")
        name = parts[0].strip()
        if not name: continue
        q = parts[1].strip() if len(parts) > 1 and parts[1].strip() else name
        kind = "albums" if len(parts) > 2 and parts[2] == "albums" else "playlists"
        e = _cat_cover.get(name)
        if e and e.get("url"): out[name] = e["url"]
        if not e or now - e.get("t", 0) > _CAT_COVER_TTL:
            with _cat_lock:
                if not any(j[0] == name for j in _cat_queue): _cat_queue.append((name, q, kind))
    with _cat_lock:
        if _cat_queue and not _cat_worker_on:
            _cat_worker_on = True
            threading.Thread(target=_cat_cover_worker, daemon=True).start()
    return jsonify({"covers": out})


# ── KARAOKE (inizio) ──
# Karaoke catalog: "instrumental" tracks by Karaoke Academy (Spotify playlist), with real
# title/artist and studio cover (iTunes) and synced lyrics (LRCLIB). All cached on disk.
#   GET  /karaoke/catalog        ready tracks (title+artist+cover found)
#   GET  /karaoke/status         avanzamento
#   GET  /karaoke/lyrics/<id>    timed lyrics + saved tweak
#   POST /karaoke/offset         {"id":..., "offset": seconds}  (timing tweak, saved)
#   POST /karaoke/fix            {"id":..., "title":..., "artist":...}  (correzione manuale, salvata)
# Playlists used: ~/.config/volta/karaoke_playlists.json (list of ids) — by default "Karaoke Academy International".
import re as _kre
import unicodedata as _kud
import urllib.request as _kur
import urllib.parse as _kup

KAR_DIR = os.path.expanduser("~/.config/volta")
KAR_PLAYLISTS_DEFAULT = ["544Gb5Vdn4GpuCZucrLWZo"]
KAR_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36"
KAR_PAUSE = 3.0            # seconds between two requests to iTunes (it has a low limit)
KAR_REFRESH_S = 12 * 3600  # how often to re-read the playlists
KAR_RETRY_S = 6 * 3600     # how often to retry tracks without a result
KAR_MIN_RESTART = 60       # minimum seconds between two starts of the background job
_kar_lock = threading.RLock()
_kar = {"tracks": None, "meta": None, "fix": None, "offs": None, "tracks_ts": 0.0,
        "worker": None, "err": "", "prio": [], "plist_err": "", "skip": {}}
_KAR_BAD = _kre.compile(r"karaoke|instrumental|tribute|cover|made famous|in the style|originally performed", _kre.I)


def _kar_path(n):
    return os.path.join(KAR_DIR, n)


def _kar_load(n, default):
    try:
        with open(_kar_path(n), encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def _kar_save(n, data):
    try:
        os.makedirs(KAR_DIR, exist_ok=True)
        tmp = _kar_path(n) + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        os.replace(tmp, _kar_path(n))
    except Exception as e:
        print("[karaoke] salvataggio", n, "fallito:", e, flush=True)


def _kar_init():
    with _kar_lock:
        if _kar["tracks"] is None:
            _kar["tracks"] = _kar_load("karaoke_catalog.json", {"tracks": [], "ts": 0}).get("tracks", [])
            _kar["tracks_ts"] = _kar_load("karaoke_catalog.json", {"ts": 0}).get("ts", 0)
            _kar["meta"] = _kar_load("karaoke_meta.json", {})
            _kar["fix"] = _kar_load("karaoke_fix.json", {})
            _kar["offs"] = _kar_load("karaoke_offsets.json", {})


def _kar_http(url, timeout=20):
    req = _kur.Request(url, headers={"User-Agent": KAR_UA, "Accept-Language": "it-IT,it;q=0.9,en;q=0.8"})
    with _kur.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def _kar_norm(s):
    s = _kud.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    s = _kre.sub(r"[^a-z0-9 ]+", " ", s)
    return _kre.sub(r"\s+", " ", s).strip()


def _kar_clean(t):
    t = _kre.sub(r"\s*[\(\[]\s*(instrumental|karaoke)[^\)\]]*[\)\]]\s*$", "", t or "", flags=_kre.I)
    t = _kre.sub(r"\s*[-–—]\s*(instrumental|karaoke)\b.*$", "", t, flags=_kre.I)
    return t.strip()


def _kar_playlists():
    v = _kar_load("karaoke_playlists.json", None)
    if isinstance(v, list) and v:
        return [str(x.get("id") if isinstance(x, dict) else x) for x in v if x]
    return KAR_PLAYLISTS_DEFAULT


def _kar_fetch_playlist(pid):
    """All the tracks of a playlist: official API in pages of 100, otherwise the scraper."""
    out = []
    if sp_official and is_logged_in():
        off = 0
        try:
            while off < 5000:
                page = _spotify_call(sp_official.playlist_items, pid, limit=100, offset=off) or {}
                items = page.get("items") or []
                for it in items:
                    t = (it or {}).get("track") or {}
                    if isinstance(t, dict) and t.get("id"):
                        out.append({"id": t["id"], "title": t.get("name", ""), "pl": pid,
                                    "dur": int((t.get("duration_ms") or 0) / 1000)})
                if not page.get("next") or not items:
                    break
                off += len(items)
        except Exception as e:
            _kar["plist_err"] = "API ufficiale: %s" % e
            print("[karaoke] playlist", pid, "API ufficiale:", e, flush=True)
    if not out and sp_scraper:
        try:
            obj = sp_scraper.get_playlist(pid)
            raw = getattr(obj, "tracks", []) or []
            if hasattr(raw, "items"):
                raw = raw.items
            for w in raw:
                t = getattr(w, "track", w)
                tid = getattr(t, "id", "") if t else ""
                if tid:
                    out.append({"id": tid, "title": getattr(t, "name", "") or "", "pl": pid,
                                "dur": int((getattr(t, "duration_ms", 0) or 0) / 1000)})
        except Exception as e:
            _kar["plist_err"] = "scraper: %s" % e
            print("[karaoke] playlist", pid, "scraper:", e, flush=True)
    return out


def _kar_refresh_tracks():
    new = []
    for pid in _kar_playlists():
        new += _kar_fetch_playlist(pid)
    if not new:
        return False
    with _kar_lock:
        seen = {t["id"] for t in _kar["tracks"]}
        for t in new:
            if t["id"] not in seen:
                _kar["tracks"].append(t)
                seen.add(t["id"])
        _kar["tracks_ts"] = time.time()
        _kar_save("karaoke_catalog.json", {"tracks": _kar["tracks"], "ts": _kar["tracks_ts"]})
    return True


def _kar_itunes(titolo, dur, artista=None):
    """Original of a track: same name, the artist that appears most often among the results (covers just
    once) and high position; duration counts little (the karaoke base lasts as long as a cover).
    If the artist is specified (manual correction) it must match. Returns (dict|None, error|None)."""
    best = None
    for country in ("IT", "US"):
        q = _kup.urlencode({"term": (titolo + " " + artista) if artista else titolo, "media": "music",
                            "entity": "song", "country": country, "limit": 25})
        try:
            res = json.loads(_kar_http("https://itunes.apple.com/search?" + q)).get("results", [])
        except Exception as e:
            return None, "iTunes: %s" % e
        nt = _kar_norm(titolo)
        na = _kar_norm(artista) if artista else ""
        ok = []
        for pos, r in enumerate(res):
            blob = r.get("trackName", "") + " " + r.get("artistName", "") + " " + r.get("collectionName", "")
            if not artista and _KAR_BAD.search(blob):
                continue
            nn = _kar_norm(r.get("trackName", ""))
            if na and not (na in _kar_norm(r.get("artistName", "")) or _kar_norm(r.get("artistName", "")) in na):
                continue
            if nn == nt:
                ok.append((pos, r, 4))
            elif nn.startswith(nt + " ") or nt.startswith(nn + " "):
                ok.append((pos, r, 1))
        freq = {}
        for pos, r, base in ok:
            freq[r.get("artistName")] = freq.get(r.get("artistName"), 0) + 1
        for pos, r, base in ok:
            d = abs((r.get("trackTimeMillis") or 0) / 1000.0 - dur) if dur else 99
            if d > 45 and not artista:
                continue
            sc = base + min(freq[r.get("artistName")], 4) + (2 if d <= 8 else 1 if d <= 25 else 0) \
                + (2 if pos < 3 else 1 if pos < 6 else 0)
            if best is None or sc > best[0]:
                best = (sc, r)
        if best and best[0] >= 8:
            break
        time.sleep(KAR_PAUSE)
    if not best:
        return None, "no results"
    r = best[1]
    return {"title": r.get("trackName", ""), "artist": r.get("artistName", ""),
            "album": r.get("collectionName", ""),
            "cover": _kre.sub(r"/\d+x\d+bb", "/600x600bb", r.get("artworkUrl100", ""))}, None


def _kar_resolve_one(t):
    fx = _kar["fix"].get(t["id"]) or {}
    base = fx.get("title") or _kar_clean(t.get("title", ""))
    m, err = _kar_itunes(base, t.get("dur", 0), fx.get("artist"))
    if err and err.startswith("iTunes"):
        return None                       # network error: I do not mark it, I retry later
    if m:
        m["ok"] = True
        m["ts"] = time.time()
        if fx.get("title"):
            m["title"] = fx["title"]
        if fx.get("artist"):
            m["artist"] = fx["artist"]
        return m
    return {"ok": False, "ts": time.time(), "title": base, "artist": "", "album": "", "cover": ""}


def _kar_todo():
    now = time.time()
    with _kar_lock:
        meta = _kar["meta"]
        pend = []
        for t in _kar["tracks"]:
            if _kar["skip"].get(t["id"], 0) > now:
                continue
            m = meta.get(t["id"])
            if m is None or (not m.get("ok") and now - m.get("ts", 0) > KAR_RETRY_S):
                pend.append(t)
        prio = [p for p in _kar["prio"] if any(t["id"] == p for t in pend)]
        pend.sort(key=lambda t: 0 if t["id"] in prio else 1)
        return pend


def _kar_worker():
    fails = 0
    try:
        while True:
            if time.time() - _kar["tracks_ts"] > KAR_REFRESH_S:
                _kar_refresh_tracks()
                with _kar_lock:
                    _kar["tracks_ts"] = max(_kar["tracks_ts"], time.time() - KAR_REFRESH_S + 1800)
            todo = _kar_todo()
            if not todo:
                break
            t = todo[0]
            m = _kar_resolve_one(t)
            if m is None:
                # network error: this track is skipped for a while, the others go on
                with _kar_lock:
                    _kar["skip"][t["id"]] = time.time() + 900
                fails += 1
                if fails >= 5:
                    break
                time.sleep(max(KAR_PAUSE, 2))
                continue
            fails = 0
            with _kar_lock:
                _kar["meta"][t["id"]] = m
                if len(_kar["meta"]) % 5 == 0:
                    _kar_save("karaoke_meta.json", _kar["meta"])
            time.sleep(KAR_PAUSE)
    except Exception as e:
        _kar["err"] = str(e)
        print("[karaoke] worker:", e, flush=True)
    finally:
        with _kar_lock:
            _kar_save("karaoke_meta.json", _kar["meta"])
            _kar["worker"] = None


def _kar_ensure_worker(force=False):
    with _kar_lock:
        w = _kar["worker"]
        if w is not None and w.is_alive():
            return
        if not _kar_todo() and _kar["tracks"] and time.time() - _kar["tracks_ts"] <= KAR_REFRESH_S:
            return
        if not force and time.time() - _kar.get("last_start", 0) < KAR_MIN_RESTART:
            return                        # no bursts of attempts if Spotify/network do not answer
        _kar["last_start"] = time.time()
        w = threading.Thread(target=_kar_worker, daemon=True)
        _kar["worker"] = w
        w.start()


def _kar_item(t):
    m = _kar["meta"].get(t["id"])
    if not m or not m.get("ok"):
        return None
    return {"id": t["id"], "uri": _uri(t["id"]), "title": m["title"], "artist": m["artist"],
            "album": m.get("album", ""), "cover": m["cover"], "dur": t.get("dur", 0),
            "src_title": t.get("title", "")}


@app.route("/karaoke/catalog")
def karaoke_catalog():
    _kar_init()
    _kar_ensure_worker()
    with _kar_lock:
        items = [i for i in (_kar_item(t) for t in _kar["tracks"]) if i]
        total = len(_kar["tracks"])
    return jsonify({"items": items, "total": total, "ready": len(items), "loading": _kar["worker"] is not None})


@app.route("/karaoke/status")
def karaoke_status():
    _kar_init()
    with _kar_lock:
        total = len(_kar["tracks"])
        ready = sum(1 for t in _kar["tracks"] if (_kar["meta"].get(t["id"]) or {}).get("ok"))
        failed = sum(1 for t in _kar["tracks"] if t["id"] in _kar["meta"] and not _kar["meta"][t["id"]].get("ok"))
    return jsonify({"total": total, "ready": ready, "failed": failed, "worker": _kar["worker"] is not None,
                    "err": _kar["err"], "playlist_err": _kar["plist_err"]})


def _kar_parse_lrc(txt):
    lines = []
    for ln in (txt or "").split("\n"):
        stamps = _kre.findall(r"\[(\d+):(\d+(?:\.\d+)?)\]", ln)
        if not stamps:
            continue
        text = _kre.sub(r"\[[^\]]*\]", "", ln).strip()
        for mm, ss in stamps:
            lines.append({"t": round(int(mm) * 60 + float(ss), 2), "text": text})
    lines.sort(key=lambda x: x["t"])
    return lines


def _kar_lrclib(title, artist, dur):
    """(lines, lrc_duration, busy). busy=True if LRCLIB did not answer (it must not be cached)."""
    for attempt, wait in enumerate((0, 1.5, 4)):
        if wait:
            time.sleep(wait)
        try:
            p = {"track_name": title}
            if artist:
                p["artist_name"] = artist
            res = json.loads(_kar_http("https://lrclib.net/api/search?" + _kup.urlencode(p), timeout=15))
        except Exception:
            continue
        cand = [r for r in res if r.get("syncedLyrics")]
        if not cand and artist:
            try:
                res = json.loads(_kar_http("https://lrclib.net/api/search?" + _kup.urlencode({"track_name": title}), timeout=15))
                cand = [r for r in res if r.get("syncedLyrics")]
            except Exception:
                continue
        if not cand:
            return [], 0, False
        cand.sort(key=lambda r: abs((r.get("duration") or 0) - dur))
        return _kar_parse_lrc(cand[0]["syncedLyrics"]), cand[0].get("duration") or 0, False
    return [], 0, True


@app.route("/karaoke/lyrics/<tid>")
def karaoke_lyrics(tid):
    _kar_init()
    with _kar_lock:
        tr = next((t for t in _kar["tracks"] if t["id"] == tid), None)
        meta = _kar["meta"].get(tid) or {}
        off = _kar["offs"].get(tid, 0)
    if tr is None:
        return jsonify({"found": False, "lines": [], "offset": 0, "error": "unknown track"}), 404
    cache_dir = _kar_path("karaoke_lrc")
    cf = os.path.join(cache_dir, tid + ".json")
    try:
        with open(cf, encoding="utf-8") as f:
            c = json.load(f)
        if c.get("lines") or time.time() - c.get("ts", 0) < 3 * 86400:
            c["offset"] = off
            c["busy"] = False
            return jsonify(c)
    except Exception:
        pass
    title = meta.get("title") or _kar_clean(tr.get("title", ""))
    lines, lrc_dur, busy = _kar_lrclib(title, meta.get("artist", ""), tr.get("dur", 0))
    out = {"found": bool(lines), "lines": lines, "dur": tr.get("dur", 0), "lrc_dur": lrc_dur, "ts": time.time()}
    if not busy:
        try:
            os.makedirs(cache_dir, exist_ok=True)
            with open(cf, "w", encoding="utf-8") as f:
                json.dump(out, f, ensure_ascii=False)
        except Exception as e:
            print("[karaoke] cache testo:", e, flush=True)
    out["offset"] = off
    out["busy"] = busy
    return jsonify(out)


@app.route("/karaoke/offset", methods=["POST"])
def karaoke_offset():
    _kar_init()
    d = request.get_json(silent=True) or {}
    tid = str(d.get("id") or "")
    try:
        off = max(-15.0, min(15.0, round(float(d.get("offset", 0)), 2)))
    except Exception:
        return jsonify({"ok": False}), 400
    if not tid:
        return jsonify({"ok": False}), 400
    with _kar_lock:
        _kar["offs"][tid] = off
        _kar_save("karaoke_offsets.json", _kar["offs"])
    return jsonify({"ok": True, "offset": off})


@app.route("/karaoke/fix", methods=["POST"])
def karaoke_fix():
    _kar_init()
    d = request.get_json(silent=True) or {}
    tid = str(d.get("id") or "")
    title = (d.get("title") or "").strip()
    artist = (d.get("artist") or "").strip()
    if not tid or not (title or artist):
        return jsonify({"ok": False}), 400
    with _kar_lock:
        fx = _kar["fix"].setdefault(tid, {})
        if title:
            fx["title"] = title
        if artist:
            fx["artist"] = artist
        _kar_save("karaoke_fix.json", _kar["fix"])
        _kar["meta"].pop(tid, None)
        _kar["prio"].append(tid)
    try:
        os.remove(os.path.join(_kar_path("karaoke_lrc"), tid + ".json"))
    except Exception:
        pass
    _kar_ensure_worker(force=True)
    return jsonify({"ok": True})
# ── KARAOKE (fine) ──

# ── REPEAT ONE TRACK (with account connected) ──
# With the account connected the end of the track is handled by Spotify (spotifyd), and Spotify's "repeat track"
# does not always make the same song start again. If Repeat = "one track" Spotify is asked for
# the real position (every 2.5 s, every 0.6 s when less than 5 s are left) and at the end of the track it is brought back to 0.
# The cached state is not used: if the interface does not query the service it would be stale.
_rep_guard = {"key": None}
def _repeat_one_watch():
    nxt = 0.0
    while True:
        time.sleep(0.3)
        try:
            if player_state.get("repeat") != "one" or not (is_logged_in() and sp_official):
                _rep_guard["key"] = None; continue
            if time.time() < nxt: continue
            cur = _spotify_call(sp_official.current_playback)
            nxt = time.time() + 2.5
            if not cur or not cur.get("item") or not cur.get("is_playing"): continue
            dur = cur["item"].get("duration_ms") or 0
            prog = cur.get("progress_ms") or 0
            tid = cur["item"].get("id")
            if dur < 5000 or not tid: continue
            key = (tid, dur)
            left = dur - prog
            if prog < dur / 2 and _rep_guard["key"] == key: _rep_guard["key"] = None   # restarted: armed again
            if left <= 5000: nxt = time.time() + 0.6
            if left <= 1200 and _rep_guard["key"] != key:
                _rep_guard["key"] = key
                _spotify_call(sp_official.seek_track, 0, device_id=_connect_device_id())
                player_state["progress_ms"] = 0; player_state["last_update"] = time.time()
                _status_cache["data"] = None
        except Exception as e:
            nxt = time.time() + 5
            print("[spotify] repeat-track err:", repr(e), flush=True)
threading.Thread(target=_repeat_one_watch, daemon=True).start()

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8098, debug=False)
