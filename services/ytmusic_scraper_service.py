#!/usr/bin/env python3
# ytmusic_scraper_service.py — YTMusic scraper + MPV (Riproduzione Nativa Studio Audio CarPC)
import os, sys, time, threading, json, random
import os as _os_lang
VOLTA_LANG = _os_lang.environ.get("VOLTA_LANG", "en")   # language chosen in the UI (it en es fr pt)
_LANG_REGION = {"it": "IT", "en": "US", "es": "ES", "fr": "FR", "pt": "PT"}
VOLTA_REGION = _LANG_REGION.get(VOLTA_LANG, "US")

from flask import Flask, jsonify, request as freq
from concurrent.futures import ThreadPoolExecutor

OAUTH_PATH  = os.path.expanduser("~/.config/volta/oauth.json")
OAUTH_CLIENT_PATH = os.path.expanduser("~/.config/volta/yt_oauth_client.json")
PORT = 8099
app = Flask(__name__)
from local_security import protect
protect(app)
_lock  = threading.Lock()
_yt    = None
_cache = {}
CACHE_TTL = 1800

# Set of IDs discarded because they contain 0 tracks
_empty_playlists = set()

player = None
try:
    import mpv
    player = mpv.MPV(
        ytdl=True,
        ytdl_format='bestaudio[ext=m4a]/bestaudio/best',
        video=False
    )
    # Uniform level across sources (YT Music, Spotify, podcasts): -16 LUFS
    try: player['af'] = 'loudnorm=I=-16:TP=-1.5:LRA=11'
    except Exception as _e: print("[ytmusic] volume normalization not active:", repr(_e), file=sys.stderr, flush=True)
except Exception as e:
    print("[ytmusic] mpv not available (%r) — content OK, local playback disabled." % e, file=sys.stderr, flush=True)

# mpv announces itself to the system via MPRIS (mpv-mpris plugin): it is from there that
# the interface (MprisManager, C++) reads state, position and commands.
# libmpv does not load the scripts in /etc/mpv/scripts by itself.
if player:
    import glob as _glob
    _mpris_paths = ["/etc/mpv/scripts/mpris.so",
                    os.path.expanduser("~/.config/mpv/scripts/mpris.so")] + \
                   _glob.glob("/usr/lib/*/mpv-mpris/mpris.so") + _glob.glob("/usr/lib/mpv-mpris/mpris.so")
    _mpris_so = next((x for x in _mpris_paths if os.path.exists(x)), None)
    if _mpris_so:
        try:
            player.command("load-script", _mpris_so)
            print("[ytmusic] MPRIS attivo (%s)" % _mpris_so, file=sys.stderr, flush=True)
        except Exception as e:
            print("[ytmusic] MPRIS not loaded: %r" % e, file=sys.stderr, flush=True)
    else:
        print("[ytmusic] mpv-mpris not installed: sudo apt install mpv-mpris", file=sys.stderr, flush=True)

def log(*a): print("[ytmusic]", *a, file=sys.stderr, flush=True)

def _load_oauth_client():
    """Reads the client_id/client_secret saved locally (created once
    on Google Cloud Console). Returns None if the file is not there yet."""
    try:
        if os.path.exists(OAUTH_CLIENT_PATH):
            with open(OAUTH_CLIENT_PATH) as f:
                d = json.load(f)
                if d.get('client_id') and d.get('client_secret'):
                    return d
    except Exception as e:
        log("oauth client config err:", repr(e))
    return None

def get_yt():
    global _yt
    with _lock:
        if _yt: return _yt
        try:
            from ytmusicapi import YTMusic
            if os.path.exists(OAUTH_PATH):
                # Detects the file type: the OAuth ones (device-flow) have the
                # chiave 'access_token'; quelli 'browser' (cookie reali) no —
                # only 'cookie'/'authorization'. Needed to know whether to pass
                # oauth_credentials (required only for the OAuth type).
                is_oauth_token = False
                try:
                    with open(OAUTH_PATH) as f:
                        is_oauth_token = 'access_token' in json.load(f)
                except Exception:
                    pass
                if is_oauth_token:
                    from ytmusicapi import OAuthCredentials
                    client = _load_oauth_client()
                    if client:
                        oauth_creds = OAuthCredentials(client_id=client['client_id'], client_secret=client['client_secret'])
                        _yt = YTMusic(OAUTH_PATH, language=VOLTA_LANG, location=VOLTA_REGION, oauth_credentials=oauth_creds)
                    else:
                        _yt = YTMusic(OAUTH_PATH, language=VOLTA_LANG, location=VOLTA_REGION)
                else:
                    # 'browser auth' file (real cookies): no client credentials
                    # needed, it authenticates with the captured cookies.
                    _yt = YTMusic(OAUTH_PATH, language=VOLTA_LANG, location=VOLTA_REGION)
            else:
                _yt = YTMusic(language=VOLTA_LANG, location=VOLTA_REGION)
        except Exception as e: log("YTMusic err:", repr(e))
        return _yt

def _reset_yt():
    """Forgets the YTMusic session: if it was born without a network it must be recreated."""
    global _yt
    with _lock:
        _yt = None

def cached(key, fn, ttl=CACHE_TTL):
    now = time.time()
    if key in _cache and now - _cache[key][0] < ttl: return _cache[key][1]
    try:
        v = fn()
        if v is not None: _cache[key] = (now, v)
        return v
    except Exception: return _cache.get(key, (0, None))[1]

def thumb(thumbnails):
    if not thumbnails: return ""
    t = max(thumbnails, key=lambda x: (x.get('width',0) or 0))
    return t.get('url','') or ''

def _video_type(item):
    vt = item.get('videoType', '') or ''
    return vt.replace('MUSIC_VIDEO_TYPE_', '')

def is_playable_media(item):
    if not item: return False
    title = item.get('title', '').lower()
    bad_words = [
        'karaoke', 'tutorial', 'vlog', 'reaction', 'gameplay', 'chiacchierata'
    ]
    if any(b in title for b in bad_words):
        return False
    return True

# ── "STUDIO MUSIC ONLY" MODE ──
# Same rule as BitChord (InnertubeParser.kt): a track is a VIDEO if the row
# says "video", if YouTube marks it as a music video (OMV) or user upload
# (UGC), or if the cover is NOT square — catalog tracks have the
# album cover (1:1), music videos have the widescreen preview
# (16:9). With the mode on, home, search and radio only show studio
# audio tracks; the "…video…" shelves (e.g. "Video chart") disappear.
# It is changed from /ui/studio?on=0|1 and stays saved in ~/.config/volta/yt_prefs.json.
import re as _re
PREFS_PATH = os.path.expanduser("~/.config/volta/yt_prefs.json")
_prefs = {"studioOnly": True}
try:
    with open(PREFS_PATH) as _f: _prefs.update(json.load(_f))
except Exception: pass
def studio_only(): return bool(_prefs.get("studioOnly", True))
_VIDEO_WORD = _re.compile(r"\bvideos?\b", _re.I)

def _thumb_not_square(thumbs):
    if not thumbs or not isinstance(thumbs, list): return False
    last = thumbs[-1] or {}
    try: w, h = float(last.get("width")), float(last.get("height"))
    except (TypeError, ValueError): return False     # without measures: when in doubt do not discard
    if w <= 0 or h <= 0: return False
    return not (0.85 <= w / h <= 1.15)

def is_video_item(item):
    if not item: return False
    if item.get("resultType") == "video": return True
    vt = _video_type(item)
    if vt in ("OMV", "UGC"): return True
    if vt: return False        # explicit marker (ATV, official track...): wins over the cover's shape
    return _thumb_not_square(item.get("thumbnails") or item.get("thumbnail") or [])

def song_to_dict(item, idx=0, bypass_filter=False):
    if not item: return None
    if not bypass_filter and not is_playable_media(item): return None
        
    title = item.get('title','')
    if not title: return None
    arts = item.get('artists') or []
    sub = ", ".join(a.get('name','') for a in arts if a.get('name')) if isinstance(arts, list) else str(arts)
    thumbs = item.get('thumbnails') or item.get('thumbnail') or []
    
    album_obj = item.get('album')
    album_name = ""
    if isinstance(album_obj, dict):
        album_name = album_obj.get('name', '')
    elif isinstance(album_obj, str):
        album_name = album_obj
        
    duration = item.get('duration', '')
    is_liked = (item.get('likeStatus') == 'LIKE')
    
    return {
        "title": title, "subtitle": sub, "album": album_name,
        "cover": thumb(thumbs),
        "videoId": item.get('videoId',''),
        "uri": item.get('videoId',''), 
        "type": "Track", "isContext": False, "num": idx+1,
        "isVideo": is_video_item(item),
        "duration": duration,
        "isLiked": is_liked
    }

def playlist_to_dict(item):
    if not item: return None
    pid = item.get('audioPlaylistId','') or item.get('playlistId','')
    bid = item.get('browseId','')
    title = item.get('title','') or item.get('name','')
    if not title: return None
    
    if (pid and pid in _empty_playlists) or (bid and bid in _empty_playlists):
        return None
    
    t_low = title.lower()
    bad_words = ['vlog', 'reaction', 'tutorial']
    if any(w in t_low for w in bad_words):
        return None
        
    count = item.get('count','') or ''
    if str(count).strip() == '0':
        return None

    return {
        "title": title, "subtitle": str(count)+" tracks" if count else "",
        "cover": thumb(item.get('thumbnails',[])),
        "playlistId": pid, "browseId": bid, "type": "Playlist", "isContext": True,
        "isVideo": False
    }

def artist_to_dict(item):
    if not item: return None
    name = item.get('name','') or item.get('artist','') or item.get('title','')
    if not name: return None
    
    bid = item.get('browseId','') or item.get('channelId','')
    if bid and bid in _empty_playlists: return None
    
    return {
        "title": name, "name": name,
        "subtitle": item.get('subscribers','') or "Artista",
        "cover": thumb(item.get('thumbnails',[])),
        "browseId": bid,
        "type": "Artist", "isContext": True,
        "isVideo": False
    }

# ── CONTROLLO MPV E CODA ──
_queue  = []
_q_pos  = -1
_last_play_error = ""
_cur_started = False      # the current track really started (audio advanced)
_cur_vid = ""
_play_retries = {}        # videoId -> fallback attempts already made
_stream_cache = {}
STREAM_TTL = 3600

_ytdlp = None
try:
    import yt_dlp as _ytdlp
    log("yt-dlp versione:", getattr(_ytdlp.version, "__version__", "?"))
except Exception as e:
    log("yt_dlp modulo mancante:", repr(e))

def _yt_url(vid): return f"https://music.youtube.com/watch?v={vid}"

# Some tracks fail with the default yt-dlp client (age/region
# restrictions, "sign in", streams without audio): other clients are tried
# before giving up. The first one that works is remembered for the next tracks.
_YT_CLIENT_CHAIN = [["bitchord"], ["mweb"], ["android_vr"], ["mweb"], ["web_embedded"], None, ["tv"], ["ios"], ["web_safari"]]
_yt_client_ok = None
_yt_skip = {}          # videoId -> clients that gave an error on playback
_stream_client = {}    # videoId -> client with which the stream was resolved

# Since yt-dlp 2025.11 YouTube requires an external JavaScript runtime (Deno, or
# Node enabled by hand) + the "EJS" component: without it, many tracks have no
# audio formats available and "do not start". The one found on the PC is enabled.
def _js_runtime_opts():
    import shutil
    o = {}
    import glob as _glob
    _home = os.path.expanduser("~")
    _extra = ":".join([_home + "/.deno/bin", _home + "/.local/bin", _home + "/.bun/bin", "/usr/local/bin", "/usr/bin", "/snap/bin"]
                      + sorted(_glob.glob(_home + "/.nvm/versions/node/*/bin"), reverse=True))
    for name in ("deno", "node", "bun"):
        path = shutil.which(name) or shutil.which(name, path=_extra)
        if path:
            o["js_runtimes"] = {name: {"path": path}}
            break
    o["remote_components"] = ["ejs:github"]
    return o
_JS_OPTS = _js_runtime_opts()
log("runtime JS:", (list(_JS_OPTS['js_runtimes'].items())[0] if _JS_OPTS.get('js_runtimes') else 'NONE - the link signatures do not resolve'))

# ── BITCHORD-STREAM v1 ── stream resolution "BitChord style" ──────────────────
# 1) yt-dlp finds the address with the first client that works (web_embedded first).
# 2) TEST: before giving it to the player, 16 KB are really downloaded with a LIMITED request
#    (never an open "bytes=0-"), with the client's headers, starting beyond 1 MiB if the file
#    is long; it must answer audio/*. If not, we move to the next client (max 5).
# 3) LOCAL BRIDGE: mpv reads from 127.0.0.1 and the bridge downloads from googlevideo in blocks of
#    1 MiB (512 KiB for ANDROID_VR/TVHTML5_SIMPLY). Googlevideo throttles continuous reads
#    (~15 kB/s) e a certi client rifiuta quelle aperte (403): a blocchi no.
# 4) A SINGLE computation per track (prefetch and click do not duplicate) and tracks that really
#    cannot be played are remembered for 10 minutes.
import http.client as _hc, http.server as _hs, urllib.parse as _up, re as _re
from concurrent.futures import Future as _Future

_MB = 1024 * 1024
_PROBE_BYTES = 16 * 1024
_MAX_CLIENT_TRIES = 5
_UNPLAYABLE_TTL = 600
_PERMANENT = ("video unavailable", "private video", "not available in your country",
              "no longer available", "has been removed", "members-only", "join this channel",
              "copyright", "violating")
_unplayable = {}
_inflight = {}
_inflight_lock = threading.Lock()
_entries = {}            # token -> stream data (address, headers, length...)
_entries_lock = threading.RLock()
_entry_seq = [0]
_proxy_srv = [None]
_play_gen = [0]          # number of the last click: older clicks are discarded
_play_busy = [0]         # how many clicks are being prepared (the prefetch waits)

def _ckey(client): return tuple(client) if client else None

_yt_msgs = threading.local()

class _YtLog:
    """Logger for yt-dlp: it does not print, it collects warnings and errors of the attempt in progress."""
    def debug(self, m): pass
    def info(self, m): pass
    def warning(self, m): self._note(m)
    def error(self, m): self._note(m)
    def _note(self, m):
        lst = getattr(_yt_msgs, "l", None)
        if lst is None: lst = _yt_msgs.l = []
        s = str(m).replace("\n", " ")[:240]
        if s not in lst: lst.append(s)

def _extract_sub(video_id, client):
    """Extracts the link with a NEW yt-dlp process (like the terminal command): the ones extracted
    inside the service were almost always rejected by googlevideo (403)."""
    import subprocess
    cmd = [sys.executable, "-m", "yt_dlp", "-q", "--no-warnings", "--no-playlist", "--simulate",
           "-f", "bestaudio[ext=m4a]/bestaudio/best", "--socket-timeout", "15"]
    _js = _JS_OPTS.get("js_runtimes")
    if _js:
        _n, _v = list(_js.items())[0]
        cmd += ["--js-runtimes", "%s:%s" % (_n, (_v or {}).get("path", ""))]
    cmd += ["--remote-components", "ejs:github"]
    if client: cmd += ["--extractor-args", "youtube:player_client=" + ",".join(client)]
    cmd += ["--print", "%(url)s", "--print", "%(http_headers)j", "--print", "%(filesize,filesize_approx)s",
            "--print", "itag %(format_id)s %(ext)s a=%(acodec)s v=%(vcodec)s", _yt_url(video_id)]
    env = dict(os.environ)
    _h = os.path.expanduser("~")
    env["PATH"] = os.pathsep.join([env.get("PATH", ""), _h + "/.deno/bin", _h + "/.local/bin", "/usr/local/bin", "/usr/bin"])
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=90, env=env)
    out = [l for l in (p.stdout or "").splitlines() if l.strip()]
    if p.returncode != 0 or len(out) < 2 or not out[0].startswith("http"):
        err = [l for l in (p.stderr or "").splitlines() if l.strip()]
        raise RuntimeError((err[-1] if err else "yt-dlp without result (code %s)" % p.returncode)[:300])
    try: hdr = json.loads(out[1])
    except Exception: hdr = {}
    try: fs = int(out[2]) if len(out) > 2 else 0
    except Exception: fs = 0
    return {"url": out[0], "headers": dict(hdr or {}), "filesize": fs, "fmt": out[3] if len(out) > 3 else ""}

# ── BITCHORD-RESOLVER v1 ── BitChord's engine (StreamResolver + InnerTubeX) as the first resolver ──
# Un programma Java/Kotlin (cartella ~/BitChord-src, comando runResolver) tiene sempre pronti token e
# ciphering and answers on 127.0.0.1:8097. The service starts it in the background; until it is ready
# (about 30 s after startup) or if it does not answer, yt-dlp is used as before.
import atexit as _atexit, signal as _signal, subprocess as _sp
_BC_PORT = 18097
_BC_SRC = os.path.expanduser("~/BitChord-src")
_BC_LOG = "/tmp/ytmusic_resolver.log"
_bc_proc = [None]
_bc_lock = threading.Lock()
_bc_t = [0.0]
_bc_up = [False]
_bc_refusals = {}

def _bc_get(path, timeout=5):
    c = _hc.HTTPConnection("127.0.0.1", _BC_PORT, timeout=timeout)
    try:
        c.request("GET", path)
        r = c.getresponse()
        return r.status, r.read()
    finally:
        c.close()

def _bc_alive():
    try:
        st, body = _bc_get("/health", 1.5)
        return st == 200 and b'"ok"' in body
    except Exception: return False

_BC_CP = os.path.join(_BC_SRC, "resolver.classpath")
_BC_JAVA = "/usr/lib/jvm/java-21-openjdk-amd64/bin/java"
_bc_use_direct = [True]
_bc_direct_now = [False]
import contextlib as _cl
_bc_pause = [0.0]                        # until when (epoch) BitChord is skipped and yt-dlp is used
_bc_pf = threading.Semaphore(1)          # the prefetch talks to the resolver one request at a time
def _bc_systemd():
    return os.path.isfile(os.path.expanduser("~/.config/systemd/user/bitchord-resolver.service"))

def _bc_kill_all():
    """Kills every resolver left around (stuck or orphan)."""
    try: _sp.run(["pkill", "-f", "ResolverMainKt"], timeout=5)
    except Exception: pass

def _bc_restart():
    """If the resolver does not even answer /health it kills and restarts it."""
    if _bc_alive(): return
    log("BitChord resolver stuck: restarting it")
    if _bc_systemd():
        try:
            _sp.run(["systemctl", "--user", "restart", "bitchord-resolver"], timeout=15); return
        except Exception: pass
    _bc_stop(); _bc_kill_all()
    with _bc_lock:
        _bc_proc[0] = None; _bc_t[0] = 0.0
    _bc_start()

def _bc_start():
    """Starts the BitChord resolver in the background (at most once a minute).
    First it tries direct Java (a few seconds); if that is not possible or fails, gradle (~30 s)."""
    with _bc_lock:
        p = _bc_proc[0]
        if p is not None and p.poll() is None: return
        if p is not None and _bc_direct_now[0]:          # the direct start is dead: next time gradle
            _bc_use_direct[0] = False
            log("BitChord resolver: direct start failed, using gradle")
        if time.time() - _bc_t[0] < 60: return
        _bc_t[0] = time.time()
        if _bc_alive():
            _bc_up[0] = True; return
        if _bc_systemd():
            try:
                _sp.run(["systemctl", "--user", "start", "bitchord-resolver"], timeout=10)
                log("BitChord resolver: started by the user service (systemd)"); return
            except Exception as e:
                log("BitChord resolver: systemd not available:", repr(e)[:80])
        _bc_kill_all()
        if not os.path.isfile(os.path.join(_BC_SRC, "gradlew")):
            log("BitChord resolver: source not found in", _BC_SRC, "- uso yt-dlp"); return
        env = dict(os.environ)
        if os.path.isdir("/usr/lib/jvm/java-21-openjdk-amd64"): env["JAVA_HOME"] = "/usr/lib/jvm/java-21-openjdk-amd64"
        cp = ""
        try:
            if _bc_use_direct[0] and os.path.isfile(_BC_CP) and os.path.isfile(_BC_JAVA):
                cp = open(_BC_CP, encoding="utf-8").read().strip()
        except Exception: cp = ""
        if cp:
            cmd = [_BC_JAVA, "-Xmx512m", "-XX:+UseG1GC", "-cp", cp, "com.music.bitchord.desktop.ResolverMainKt", str(_BC_PORT)]
            _bc_direct_now[0] = True
        else:
            cmd = ["./gradlew", "--no-daemon", "--offline", "-Dorg.gradle.jvmargs=-Xmx1g",
                   "-Pkotlin.daemon.jvmargs=-Xmx512m", ":desktopApp:runResolver", "--args=%d" % _BC_PORT]
            _bc_direct_now[0] = False
        try:
            _bc_proc[0] = _sp.Popen(cmd, cwd=_BC_SRC, env=env, stdout=open(_BC_LOG, "w"),
                                    stderr=_sp.STDOUT, start_new_session=True)
            log("resolver BitChord: avviato %s (log %s)" % ("(Java diretto)" if cp else "(gradle)", _BC_LOG))
        except Exception as e:
            log("BitChord resolver: start failed:", repr(e)[:120])

def _bc_start_async():
    threading.Thread(target=_bc_start, daemon=True).start()

def _bc_stop():
    p = _bc_proc[0]
    if p is not None and p.poll() is None:
        try: os.killpg(p.pid, _signal.SIGTERM)
        except Exception: pass
_atexit.register(_bc_stop)

def _extract_bc(video_id):
    """Link already verified by BitChord's engine. Raises right away if the resolver is not ready."""
    if time.time() < _bc_pause[0]:
        raise RuntimeError("resolver BitChord in pausa")
    if not _bc_up[0]:
        if _bc_alive(): _bc_up[0] = True
        else:
            _bc_start_async()
            _p = _bc_proc[0]
            if _p is not None and _p.poll() is None and time.time() - _bc_t[0] < 60:
                _w = time.time()                       # at startup: wait a few seconds instead of switching to yt-dlp
                while time.time() - _w < 9 and _p.poll() is None and not _bc_alive(): time.sleep(0.3)
                if _bc_alive(): _bc_up[0] = True
            if not _bc_up[0]:
                raise RuntimeError("BitChord resolver not ready")
    try:
        with (_bc_pf if getattr(_bg, "on", False) else _cl.nullcontext()):
            st, body = _bc_get("/resolve?id=" + video_id, 10)
    except Exception as e:
        _bc_up[0] = False
        _bc_pause[0] = time.time() + 45
        threading.Thread(target=_bc_restart, daemon=True).start()
        raise RuntimeError("BitChord resolver not answering: " + type(e).__name__)
    try: d = json.loads(body.decode("utf-8", "replace"))
    except Exception: d = {}
    if st != 200 or not d.get("url"):
        msg = str(d.get("error") or ("HTTP %d" % st))
        raise RuntimeError(("video unavailable (BitChord): " if st == 410 else "BitChord: ") + msg[:200])
    return {"url": d["url"], "headers": dict(d.get("headers") or {}), "filesize": d.get("clen") or 0, "fmt": "BitChord"}

_bc_start_async()

def _extract_with(video_id, client):
    if client and list(client) == ["bitchord"]:
        return _extract_bc(video_id)
    return _extract_sub(video_id, client)

def _extract_with_inproc(video_id, client):
    opts = {"quiet": True, "no_warnings": True, "noplaylist": True,
            "format": "bestaudio[ext=m4a]/bestaudio/best", "socket_timeout": 15}
    opts.update(_JS_OPTS)
    opts["logger"] = _YtLog()
    if client: opts["extractor_args"] = {"youtube": {"player_client": client}}
    with _ytdlp.YoutubeDL(opts) as y:
        info = y.extract_info(_yt_url(video_id), download=False)
        return {"url": info.get("url"), "headers": dict(info.get("http_headers") or {}),
                "filesize": info.get("filesize") or info.get("filesize_approx"),
                "fmt": "itag %s %s a=%s v=%s" % (info.get("format_id"), info.get("ext"), info.get("acodec"), info.get("vcodec"))}

def _chunk_for(url):
    c = ((_up.parse_qs(_up.urlparse(url).query).get("c") or [""])[0]).upper()
    return 512 * 1024 if (c == "ANDROID_VR" or c.startswith("TVHTML5_SIMPLY")) else _MB

def _make_entry(video_id, client, found):
    url = found["url"]
    q = _up.parse_qs(_up.urlparse(url).query)
    try: clen = int((q.get("clen") or [0])[0] or 0)
    except Exception: clen = 0
    if not clen:
        try: clen = int(found.get("filesize") or 0)
        except Exception: clen = 0
    return {"url": url, "headers": dict(found.get("headers") or {}), "clen": clen,
            "mime": (q.get("mime") or ["audio/webm"])[0], "vid": video_id,
            "ckey": _ckey(client), "chunk": _chunk_for(url), "fmt": found.get("fmt", ""), "why": ""}

def _up_open(entry, start, end, timeout=15):
    """LIMITED request to googlevideo with the headers of the client that created the stream.
    Follows the redirects to *.googlevideo.com and remembers the final address."""
    conn = r = None
    for _hop in range(4):
        u = _up.urlparse(entry["url"])
        Conn = _hc.HTTPSConnection if u.scheme == "https" else _hc.HTTPConnection
        conn = Conn(u.netloc, timeout=timeout)
        h = dict(entry["headers"])
        h["Range"] = "bytes=%d-%d" % (start, end)
        h["Accept-Encoding"] = "identity"
        try:
            conn.request("GET", u.path + ("?" + u.query if u.query else ""), headers=h)
            r = conn.getresponse()
        except Exception:
            conn.close(); raise
        loc = r.getheader("Location") if r.status in (301, 302, 303, 307, 308) else None
        if not loc:
            return conn, r
        nxt = _up.urljoin(entry["url"], loc)
        host = (_up.urlparse(nxt).hostname or "").lower()
        if not (host.endswith(".googlevideo.com") or host.endswith(".youtube.com")):
            return conn, r
        try: r.read()
        except Exception: pass
        conn.close()
        entry["url"] = nxt
    return conn, r

def _probe_entry(entry):
    """'ok' | 'refused' | 'unreachable' — like BitChord's probe."""
    clen = entry["clen"]
    start = _MB if clen > _MB + _PROBE_BYTES else 0
    end = start + _PROBE_BYTES - 1
    if clen: end = min(end, clen - 1)
    conn = None
    try:
        conn, r = _up_open(entry, start, end, timeout=6)
        if r.status in (401, 403, 404, 410):
            entry["why"] = "HTTP %d" % r.status; return "refused"
        if r.status not in (200, 206):
            entry["why"] = "HTTP %d" % r.status; return "unreachable"
        _ct = r.getheader("Content-Type") or ""
        if not (_ct.startswith("audio/") or _ct.startswith("video/")):
            entry["why"] = "tipo %s" % (_ct or "?"); return "refused"
        if not clen:
            m = _re.match(r"bytes \d+-\d+/(\d+)", r.getheader("Content-Range") or "")
            if m: entry["clen"] = int(m.group(1))
        data = r.read(end - start + 1)
        if len(data) < min(_PROBE_BYTES, end - start + 1):
            entry["why"] = "only %d bytes" % len(data); return "unreachable"
        return "ok"
    except Exception as e:
        entry["why"] = type(e).__name__
        log("probe flusso:", type(e).__name__)
        return "unreachable"
    finally:
        try:
            if conn: conn.close()
        except Exception: pass

def _stream_refused(entry, status):
    """The server rejected the stream while playing: that client is forgotten and discarded."""
    vid = entry["vid"]
    log("stream rejected (HTTP %s) with client %s for %s" % (status, entry["ckey"], vid))
    _stream_cache.pop(vid, None)
    if entry["ckey"] == ("bitchord",):
        try: _bc_get("/refused?url=" + _up.quote(entry["url"], safe="") + "&code=%s" % status, 3)
        except Exception: pass
        _bc_refusals[vid] = _bc_refusals.get(vid, 0) + 1
        if _bc_refusals[vid] < 2: return          # BitChord picks another client at the next attempt
    _yt_skip.setdefault(vid, set()).add(entry["ckey"])

class _ProxyHandler(_hs.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass

    def _span(self, total):
        a, b, partial = 0, total - 1, False
        m = _re.match(r"bytes=(\d*)-(\d*)$", (self.headers.get("Range") or "").strip())
        if m and (m.group(1) or m.group(2)):
            partial = True
            if not m.group(1):
                a = max(0, total - int(m.group(2)))
            else:
                a = int(m.group(1))
                if m.group(2): b = min(total - 1, int(m.group(2)))
        return a, b, partial

    def _head(self, e, a, b, partial):
        self.send_response(206 if partial else 200)
        self.send_header("Content-Type", e["mime"])
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(b - a + 1))
        if partial: self.send_header("Content-Range", "bytes %d-%d/%d" % (a, b, e["clen"]))
        self.send_header("Connection", "close")
        self.end_headers()

    def do_HEAD(self): self._serve(False)
    def do_GET(self): self._serve(True)

    def _serve(self, body):
        tok = self.path.split("?")[0].rsplit("/", 1)[-1]
        with _entries_lock: e = _entries.get(tok)
        if not e or e["clen"] <= 0:
            self.send_error(404); return
        a, b, partial = self._span(e["clen"])
        if a > b or a >= e["clen"]:
            self.send_response(416); self.send_header("Content-Range", "bytes */%d" % e["clen"])
            self.send_header("Content-Length", "0"); self.send_header("Connection", "close"); self.end_headers(); return
        if not body:
            self._head(e, a, b, partial); return
        pos, first = a, True
        try:
            while pos <= b:
                end = min(pos + e["chunk"] - 1, b)
                try: conn, r = _up_open(e, pos, end)
                except Exception:
                    time.sleep(0.3); conn, r = _up_open(e, pos, end)
                got = 0
                try:
                    if r.status not in (200, 206):
                        if first:
                            _stream_refused(e, r.status); self.send_error(502)
                        return                      # halfway: it closes, mpv and the service retry
                    if first:
                        self._head(e, a, b, partial); first = False
                    while True:
                        buf = r.read(65536)
                        if not buf: break
                        self.wfile.write(buf)
                        got += len(buf)
                finally:
                    try: conn.close()
                    except Exception: pass
                if got <= 0: return
                pos += got
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            return
        except Exception as ex:
            log("ponte flusso:", type(ex).__name__, str(ex)[:80])

def _proxy_port():
    with _entries_lock:
        if _proxy_srv[0] is None:
            srv = _hs.ThreadingHTTPServer(("127.0.0.1", 0), _ProxyHandler)
            srv.daemon_threads = True
            threading.Thread(target=srv.serve_forever, daemon=True).start()
            _proxy_srv[0] = srv
        return _proxy_srv[0].server_address[1]

def _register(entry):
    port = _proxy_port()
    with _entries_lock:
        _entry_seq[0] += 1
        tok = "%s_%d" % (entry["vid"], _entry_seq[0])
        _entries[tok] = entry
        if len(_entries) > 300:
            for k in list(_entries)[:100]: _entries.pop(k, None)
    return "http://127.0.0.1:%d/s/%s" % (port, tok)

_RACE = 1                 # clients tried together for the clicked track
_bg = threading.local()   # on=True in the prefetch threads (one client at a time)

def _attempt(video_id, client):
    """A complete attempt (extraction + test). It never raises exceptions."""
    t0 = time.time()
    try:
        found = _extract_with(video_id, client)
    except Exception as e:
        return {"client": client, "err": e, "t0": t0}
    try:
        if not found or not found.get("url"): return {"client": client, "err": None, "t0": t0}
        entry = _make_entry(video_id, client, found)
        return {"client": client, "entry": entry, "verdict": _probe_entry(entry), "t0": t0}
    except Exception as e:
        return {"client": client, "err": e, "t0": t0}

_HEDGE_S = 3.0           # if BitChord does not answer within 3 s the next client (yt-dlp) also starts right away

def _resolve_walk(video_id):
    global _last_play_error, _yt_client_ok
    from concurrent.futures import wait as _cf_wait, FIRST_COMPLETED as _FIRST
    chain = list(_YT_CLIENT_CHAIN)
    sk = _yt_skip.get(video_id, set())
    chain = ([c for c in chain if _ckey(c) not in sk] or list(_YT_CLIENT_CHAIN))[:_MAX_CLIENT_TRIES]
    n_race = 1 if getattr(_bg, "on", False) else _RACE
    last_err, first_ok, errs, perm = None, None, 0, 0
    i = 0
    while i < len(chain):
        group = chain[i:i + n_race]; i += len(group)
        ex = ThreadPoolExecutor(max_workers=3)
        try:
            pend = {ex.submit(_attempt, video_id, c) for c in group}
            hedged = False
            can_hedge = bool(group[0]) and list(group[0]) == ["bitchord"]
            while pend:
                wait_s = _HEDGE_S if (can_hedge and not hedged and i < len(chain)) else None
                done, pend = _cf_wait(pend, timeout=wait_s, return_when=_FIRST)
                if not done:                      # BitChord is slow: we also start with the next client
                    nxt = chain[i]; i += 1; hedged = True
                    log("BitChord resolver slow for", video_id, "- provo in parallelo", nxt)
                    pend.add(ex.submit(_attempt, video_id, nxt))
                    continue
                for f in done:
                    r = f.result(); client = r["client"]
                    if r.get("err") is not None:
                        e = r["err"]; last_err = e; errs += 1
                        if any(p in str(e).lower() for p in _PERMANENT): perm += 1
                        log("resolve_stream", video_id, "client", client, "->", repr(e)[:160])
                        continue
                    entry = r.get("entry")
                    if not entry: continue
                    if r["verdict"] != "ok":
                        log("stream not usable (%s: %s) with client %s for %s [%s] - trying another" % (r["verdict"], entry.get("why"), client, video_id, entry.get("fmt")))
                        if first_ok is None: first_ok = (entry, client)
                        continue
                    _stream_client[video_id] = _ckey(client)
                    if client != _yt_client_ok:
                        _yt_client_ok = client
                        if client: log("yt-dlp: using the client", client)
                    play = _register(entry) if entry["clen"] > 0 else entry["url"]
                    log("flusso %s: client %s, %.1f s [%s]" % (video_id, client, time.time() - r["t0"], entry.get("fmt")))
                    return play
        finally:
            ex.shutdown(wait=False)
    if first_ok:                      # all discarded by the test: as before, the first one is used
        entry, client = first_ok
        _stream_client[video_id] = _ckey(client)
        log("no client passed the test for", video_id, "- using the first one anyway")
        return entry["url"]
    if errs and perm == errs:
        _unplayable[video_id] = time.time() + _UNPLAYABLE_TTL
        log(video_id, "is not playable:", repr(last_err)[:120], "- not requesting it for 10 minutes")
    _last_play_error = repr(last_err) if last_err else "stream not found"
    log("resolve_stream FAILED for", video_id, "with all the clients")
    return None

# ── AUDIO IN LOCALE v1 ── file audio salvati in ~/.cache/volta_ytmusic/audio ──
# We save: the next track in the queue (so it starts right away and does not depend on the network) and the tracks with a heart
# that you listen to. An already saved track is played from file: 0 s, and without network. 2 GB cap (oldest removed).
_CACHE_DIR = os.path.expanduser("~/.cache/volta_ytmusic/audio")
_CACHE_MAX = 2 * 1024 * 1024 * 1024
_CACHE_MIN_FREE = 1024 * 1024 * 1024
_cache_pool = ThreadPoolExecutor(max_workers=1)
_cache_busy = set()
_cache_lock = threading.Lock()
_cache_fail = {}                                   # videoId -> do not retry before

def _cache_path(vid):
    """Path of the complete file, or None."""
    try:
        for ext in (".m4a", ".webm"):
            p = os.path.join(_CACHE_DIR, vid + ext)
            if os.path.isfile(p) and os.path.getsize(p) > 4096:
                try: os.utime(p, None)
                except Exception: pass
                return p
    except Exception: pass
    return None

def _cache_drop(vid):
    for ext in (".m4a", ".webm", ".m4a.part", ".webm.part"):
        try: os.remove(os.path.join(_CACHE_DIR, vid + ext))
        except Exception: pass

def _cache_trim():
    try:
        files = []
        for n in os.listdir(_CACHE_DIR):
            p = os.path.join(_CACHE_DIR, n)
            try: st = os.stat(p)
            except Exception: continue
            if n.endswith(".part"):
                if time.time() - st.st_mtime > 3600:
                    try: os.remove(p)
                    except Exception: pass
                continue
            files.append((st.st_mtime, st.st_size, p))
        tot = sum(f[1] for f in files)
        if tot <= _CACHE_MAX: return
        for _m, sz, p in sorted(files):
            try: os.remove(p); tot -= sz
            except Exception: pass
            if tot <= _CACHE_MAX * 0.85: break
    except Exception: pass

def _cache_fetch(vid):
    part = None
    try:
        if _cache_path(vid): return
        url = (_stream_cache.get(vid) or (None, 0))[0]
        if not url or not str(url).startswith("http://127.0.0.1:"): return
        tok = url.split("?")[0].rsplit("/", 1)[-1]
        with _entries_lock: e = _entries.get(tok)
        if not e or e["clen"] <= 0: return
        os.makedirs(_CACHE_DIR, exist_ok=True)
        try:
            sv = os.statvfs(_CACHE_DIR)
            if sv.f_bavail * sv.f_frsize < _CACHE_MIN_FREE + e["clen"]: return
        except Exception: pass
        ext = ".webm" if "webm" in (e.get("mime") or "") else ".m4a"
        final = os.path.join(_CACHE_DIR, vid + ext); part = final + ".part"
        u = _up.urlparse(url)
        conn = _hc.HTTPConnection(u.hostname, u.port, timeout=30)
        got = 0
        try:
            conn.request("GET", u.path)
            r = conn.getresponse()
            if r.status != 200: raise RuntimeError("HTTP %d" % r.status)
            with open(part, "wb") as f:
                while True:
                    buf = r.read(262144)
                    if not buf: break
                    f.write(buf); got += len(buf)
        finally:
            conn.close()
        if got != e["clen"]: raise RuntimeError("incompleto %d/%d" % (got, e["clen"]))
        os.replace(part, final); part = None
        log("audio salvato in locale:", vid, "%.1f MB" % (got / 1048576.0))
        _cache_trim()
    except Exception as ex:
        log("audio in locale:", vid, "not saved -", repr(ex)[:100])
        _cache_fail[vid] = time.time() + 300
        if part:
            try: os.remove(part)
            except Exception: pass
    finally:
        with _cache_lock: _cache_busy.discard(vid)

def _cache_want(vid):
    """Asks (queued, one file at a time) to save the track locally."""
    if not vid or _cache_path(vid): return
    if time.time() < _cache_fail.get(vid, 0): return
    with _cache_lock:
        if vid in _cache_busy: return
        _cache_busy.add(vid)
    _cache_pool.submit(_cache_fetch, vid)

def _resolve_and_cache(vid):
    u = resolve_stream(vid)
    if u and not str(u).startswith("/"): _cache_want(vid)

@app.route("/cache/status")
def cache_status():
    n, tot = 0, 0
    try:
        for fn in os.listdir(_CACHE_DIR):
            if not fn.endswith(".part"):
                n += 1; tot += os.path.getsize(os.path.join(_CACHE_DIR, fn))
    except Exception: pass
    return jsonify({"files": n, "mb": round(tot / 1048576.0, 1), "max_mb": _CACHE_MAX // 1048576, "in_corso": sorted(_cache_busy)})

@app.route("/cache/clear")
def cache_clear():
    n = 0
    try:
        for fn in os.listdir(_CACHE_DIR):
            try: os.remove(os.path.join(_CACHE_DIR, fn)); n += 1
            except Exception: pass
    except Exception: pass
    return jsonify({"ok": True, "rimossi": n})

def resolve_stream(video_id, force=False):
    if force: _cache_drop(video_id)           # retry after an error: the local file is not trusted
    _cp = _cache_path(video_id)
    if _cp: return _cp                        # already saved: it is played from file
    if not _ytdlp: return None
    if force: _stream_cache.pop(video_id, None)
    hit = _stream_cache.get(video_id)
    if hit and time.time() - hit[1] < STREAM_TTL: return hit[0]
    if not force and time.time() < _unplayable.get(video_id, 0): return None
    with _inflight_lock:
        fut = _inflight.get(video_id)
        owner = fut is None
        if owner:
            fut = _Future(); _inflight[video_id] = fut
    if not owner:                      # a single computation per track: the others wait
        try: return fut.result(timeout=45)
        except Exception: return None
    url = None
    try:
        url = _resolve_walk(video_id)
        if url: _stream_cache[video_id] = (url, time.time())
        return url
    finally:
        fut.set_result(url)
        with _inflight_lock: _inflight.pop(video_id, None)


# ── PRE-CARICAMENTO DEI FLUSSI ──
# The delay when starting a track is almost all yt-dlp resolving the address
# of the stream (~1 s). When the interface shows a list of tracks (search,
# album, playlist, artist) it asks to resolve the first ones in advance: on tap
# the stream is already ready and mpv starts right away, like Spotify.
_prefetch_pool = ThreadPoolExecutor(max_workers=3)
_prefetch_pending = set()

def _prefetch_one(vid):
    try:
        _w = time.time()
        while _play_busy[0] > 0 and time.time() - _w < 20: time.sleep(0.25)
        _bg.on = True
        resolve_stream(vid)
    finally: _prefetch_pending.discard(vid)

@app.route("/prefetch")
def prefetch_streams():
    ids = [x for x in (freq.args.get("ids", "") or "").split(",") if x][:8]
    queued = 0
    for vid in ids:
        hit = _stream_cache.get(vid)
        if (hit and time.time() - hit[1] < STREAM_TTL - 300) or vid in _prefetch_pending: continue
        _prefetch_pending.add(vid)
        _prefetch_pool.submit(_prefetch_one, vid)
        queued += 1
    return jsonify({"ok": True, "queued": queued})

# ── MI PIACE (account YouTube Music + copia locale) ──
# The local copy makes the heart stay lit even without login or if
# YouTube answers slowly; with login the track also ends up in the "Likes".
LIKES_PATH = os.path.expanduser("~/.config/volta/yt_likes.json")
_likes = {}
try:
    with open(LIKES_PATH) as f: _likes = json.load(f)
except Exception: _likes = {}

def _save_likes():
    try:
        os.makedirs(os.path.dirname(LIKES_PATH), exist_ok=True)
        with open(LIKES_PATH, "w") as f: json.dump(_likes, f)
    except Exception: pass

# ── RECENTI LOCALI ──
RECENTS_PATH = os.path.expanduser("~/.config/volta/recents.json")
RECENT_SEARCHES_PATH = os.path.expanduser("~/.config/volta/recent_searches.json")
_recents, _recent_searches = [], []

def _load_recents():
    global _recents, _recent_searches
    try:
        with open(RECENTS_PATH) as f: _recents = json.load(f)
    except: _recents = []
    try:
        with open(RECENT_SEARCHES_PATH) as f: _recent_searches = json.load(f)
    except: _recent_searches = []
_load_recents()

def _push_recent(track):
    global _recents
    if not track or not track.get("videoId"): return
    _recents = [t for t in _recents if t.get("videoId") != track["videoId"]]
    entry = dict(track); entry["type"] = "Track"; entry["isContext"] = False
    _recents.insert(0, entry)
    _recents = _recents[:30]
    try:
        os.makedirs(os.path.dirname(RECENTS_PATH), exist_ok=True)
        with open(RECENTS_PATH, "w") as f: json.dump(_recents, f)
    except: pass

@app.route("/ui/recents")
def ui_recents(): return jsonify({"items": _recents})

@app.route("/ui/recent_searches")
def ui_recent_searches(): return jsonify({"items": _recent_searches})

@app.route("/ui/recent_searches/add")
def ui_recent_searches_add():
    global _recent_searches
    q = (freq.args.get("q", "") or "").strip()
    if len(q) < 2: return jsonify({"items": _recent_searches})
    low = q.lower()
    _recent_searches = [q] + [x for x in _recent_searches if x.lower() != low]
    _recent_searches = _recent_searches[:8]
    try:
        os.makedirs(os.path.dirname(RECENT_SEARCHES_PATH), exist_ok=True)
        with open(RECENT_SEARCHES_PATH, "w") as f: json.dump(_recent_searches, f)
    except: pass
    return jsonify({"items": _recent_searches})

_resume_start_sec = 0.0   # position from which to start the next track (resume at startup)

def _play_at(idx):
    global _q_pos, _last_play_error, _queue, _cur_started, _cur_vid, _last_advance_at, _resume_start_sec
    if not player or not (0 <= idx < len(_queue)): return False
    _q_pos = idx
    vid = _queue[idx]["videoId"]
    _cur_started = False; _cur_vid = vid
    _last_advance_at = time.time()      # the loading of a track must not be mistaken for "end of track"
    try: player.pause = True            # the old track stops right away: the new one starts as soon as it is ready
    except Exception: pass
    _t_click = time.time()
    _play_gen[0] += 1; _my_gen = _play_gen[0]
    _play_busy[0] += 1
    try:
        url = resolve_stream(vid)
    finally:
        _play_busy[0] -= 1
    log("stream ready for", vid, "in %.1f s" % (time.time() - _t_click))
    if not url:
        alt = _alt_video_id(_queue[idx])
        if alt:
            log("track not playable", vid, "-> trying the version", alt)
            url = resolve_stream(alt)
            if url:
                _queue[idx]["videoId"] = alt
                _cur_vid = alt
    if _my_gen != _play_gen[0]:
        log("brano", vid, "scartato: nel frattempo ne e' stato scelto un altro")
        return False
    url = url or _yt_url(vid)
    try:
        # Title announced via MPRIS (otherwise it would be the stream address)
        try: player.force_media_title = _queue[idx].get("title") or ""
        except Exception: pass
        player.pause = False
        _st = _resume_start_sec if idx == 0 else 0.0
        _resume_start_sec = 0.0
        if _st > 3:
            try: player.loadfile(url, start=str(_st))
            except Exception: player.play(url)
        else:
            player.play(url)
        _push_recent(_queue[idx])
        if _likes.get(_cur_vid): _cache_want(_cur_vid)      # track with a heart: it is saved
        if idx + 1 < len(_queue):
            nxt = _queue[idx + 1]["videoId"]
            threading.Thread(target=_resolve_and_cache, args=(nxt,), daemon=True).start()
        return True
    except Exception as e:
        _last_play_error = repr(e)
        return False

def _alt_video_id(track):
    """If a videoId is not playable (blocked music video, version without
    audio...) looks for the "track" version of the same title/artist."""
    try:
        yt = get_yt()
        if not yt: return None
        title = track.get("title") or ""
        # "subtitle" = "Artist • Album • 3:45": only the first piece is kept
        artist = (track.get("subtitle") or track.get("artist") or "").split("•")[0].strip()
        if not title: return None
        res = yt.search((title + " " + artist).strip(), filter="songs", limit=5) or []
        for r in res:
            vid = r.get("videoId")
            if vid and vid != track.get("videoId"):
                return vid
    except Exception as e:
        log("alternative not found:", repr(e)[:120])
    return None

def _q_current():
    if 0 <= _q_pos < len(_queue): return _queue[_q_pos]
    return None

@app.route("/player/like/<video_id>")
def player_like(video_id):
    yt = get_yt()
    action = freq.args.get("action", "LIKE")
    _likes[video_id] = (action == "LIKE")
    _save_likes()
    if yt:
        def _rate():
            try: yt.rate_song(video_id, action)
            except Exception as e: log("like not sent to YouTube Music:", repr(e))
        threading.Thread(target=_rate, daemon=True).start()
    return jsonify({"ok": True, "liked": _likes[video_id]})

@app.route("/player/liked/<video_id>")
def player_liked(video_id):
    """Is the track among the "Likes"? First the local copy, then the account."""
    if video_id in _likes: return jsonify({"liked": bool(_likes[video_id])})
    liked = False
    yt = get_yt()
    if yt:
        try:
            wp = yt.get_watch_playlist(videoId=video_id, limit=1)
            tr = (wp.get("tracks") or [{}])[0]
            liked = tr.get("likeStatus") == "LIKE"
            if liked: _likes[video_id] = True; _save_likes()
        except Exception: pass
    return jsonify({"liked": liked})


# ── CASUALE / RIPETI ──
_shuffle_on = False
_shuffle_orig = []        # original order of the following tracks (videoId), to go back
_repeat_mode = "off"      # "off" | "all" | "one"

def _shuffle_upcoming():
    """With Shuffle on it reshuffles ALL the tracks after the current one
    (also the ones just added by the radio/autoplay or by a new playlist).
    To be called with _lock taken."""
    global _queue, _shuffle_orig
    rest = _queue[_q_pos + 1:]
    if len(rest) < 2: return
    known = set(_shuffle_orig)
    _shuffle_orig = _shuffle_orig + [t.get("videoId") for t in rest if t.get("videoId") not in known]
    random.shuffle(rest)
    _queue = _queue[:_q_pos + 1] + rest
    nxt = _queue[_q_pos + 1].get("videoId")
    if nxt: threading.Thread(target=resolve_stream, args=(nxt,), daemon=True).start()

# ── AUTOPLAY v2 ── rules taken from BitChord (QueueBuilder.kt) ──
_RADIO_BATCH = 12            # tracks added per refill
_RADIO_PER_ARTIST = 2        # maximum per artist in a refill
_RADIO_SEED_ARTIST = 4       # for the artist of the track the radio starts from
_RADIO_RETRY_SEC = 4         # second attempt if the radio comes back empty
_related_pending = None      # (seed, play_next) arrived while another radio was in progress
_RNOISE = _re.compile(r"\((?:official|lyric|lyrics|lyrical|audio|video|visuali[sz]er|full song|hd|4k)[^)]*\)"
                      r"|\(from[^)]*\)|\[[^\]]*\]"
                      r"|\b(?:official (?:video|audio|music video)|lyrical video|full video|4k video)\b", _re.I)
_RPUNCT = _re.compile(r"[\W_]+", _re.U)

def _r_title(s):
    s = (s or "").lower().split(" | ")[0]
    return _RPUNCT.sub(" ", _RNOISE.sub(" ", s)).strip()

def _r_artists(s):
    s = _re.sub(r"\s*-\s*topic\b", " ", (s or "").lower())
    parts = _re.split(r",|&|·|•|;| feat| ft\.| ft | x | with ", s)
    return {p for p in (_RPUNCT.sub(" ", x).strip() for x in parts) if p}

def _r_same(a, b):
    if a.get("videoId") and a.get("videoId") == b.get("videoId"): return True
    ta = _r_title(a.get("title"))
    if not ta or ta != _r_title(b.get("title")): return False
    la, lb = _r_artists(a.get("subtitle")), _r_artists(b.get("subtitle"))
    return (not la) or (not lb) or bool(la & lb)

def _radio_pick(existing, cands, limit):
    """The candidates to add after 'existing': nothing already in the queue, no duplicates, per-artist limits."""
    taken = list(existing)
    seed_artists = _r_artists(existing[-1].get("subtitle")) if existing else set()
    per = {}
    out = []
    for c in cands:
        if len(out) >= limit: break
        if any(_r_same(t, c) for t in taken): continue
        arts = _r_artists(c.get("subtitle"))
        key = min(arts) if arts else None
        if key is not None:
            cap = _RADIO_SEED_ARTIST if (arts & seed_artists) else _RADIO_PER_ARTIST
            if per.get(key, 0) >= cap: continue
            per[key] = per.get(key, 0) + 1
        taken.append(c); out.append(c)
    return out

# ── LOGICA AUTOPLAY E CODA ──
_related_loading = False

def _radio_fetch(seed_video_id):
    """A radio request: the new (filtered) tracks or None if there is no way to get any."""
    yt = get_yt()
    if not yt: return None
    wp = None
    try: wp = yt.get_watch_playlist(videoId=seed_video_id, radio=True, limit=25)
    except Exception as e: log("radio not available for", seed_video_id, "->", repr(e))
    if not wp or not wp.get("tracks"):
        # Some tracks (e.g. videos) have no "radio": it uses the "up next" queue
        try: wp = yt.get_watch_playlist(videoId=seed_video_id, limit=25)
        except Exception: return None

    cands = []
    for t in (wp.get("tracks") or []):
        vid = t.get("videoId")
        if not vid or not is_playable_media(t): continue
        if studio_only() and is_video_item(t): continue
        arts = t.get("artists") or []
        sub = ", ".join(a.get("name","") for a in arts if a.get("name"))
        cands.append({
            "videoId": vid, "title": t.get("title",""), "subtitle": sub,
            "cover": thumb(t.get("thumbnail",[]) or t.get("thumbnails",[])),
            "isVideo": is_video_item(t)
        })
    with _lock:
        existing = list(_queue)
    return _radio_pick(existing, cands, _RADIO_BATCH)

def _populate_radio(seed_video_id, play_next=False):
    global _queue, _related_loading, _related_pending
    if not seed_video_id: return
    if _related_loading:
        _related_pending = (seed_video_id, play_next)      # it is not lost: it restarts as soon as the current one ends
        return
    _related_loading = True
    try:
        related = None
        for attempt in (1, 2):
            related = _radio_fetch(seed_video_id)
            if related: break
            if attempt == 1:
                log("radio empty for", seed_video_id, "-> retrying in", _RADIO_RETRY_SEC, "s")
                time.sleep(_RADIO_RETRY_SEC)

        if related:
            with _lock:
                _queue.extend(related)
                if _shuffle_on: _shuffle_upcoming()
            if play_next and _q_pos < len(_queue) - 1:
                _play_at(_q_pos + 1)
    finally:
        _related_loading = False
        _p, _related_pending = _related_pending, None
        if _p: threading.Thread(target=_populate_radio, args=_p, daemon=True).start()

@app.route("/player/enqueue_next")
def enqueue_next():
    global _queue, _q_pos
    video_id = freq.args.get("videoId")
    if not video_id: return jsonify({"ok": False})
    
    track = {
        "videoId": video_id, 
        "title": freq.args.get("title", ""),
        "subtitle": freq.args.get("subtitle", ""),
        "cover": freq.args.get("cover", ""),
        "isVideo": freq.args.get("isVideo") == "true",
        "type": "Track", "isContext": False
    }
    
    with _lock:
        if _q_pos < 0 or not _queue:
            _queue.append(track)
            threading.Thread(target=_play_at, args=(0,), daemon=True).start()
        else:
            _queue.insert(_q_pos + 1, track)
            
    return jsonify({"ok": True})


@app.route("/player/shuffle")
def player_shuffle():
    """?state=1 turns on, ?state=0 turns off (restores the order), without a parameter it toggles."""
    global _queue, _shuffle_on, _shuffle_orig
    if not player: return jsonify({"ok": False}), 503
    st = freq.args.get("state")
    want = (not _shuffle_on) if st is None else (st == "1")
    log("casuale ->", want, "(coda:", len(_queue), "pos:", _q_pos, ")")
    with _lock:
        rest = _queue[_q_pos + 1:] if _q_pos + 1 < len(_queue) else []
        if want:
            if rest:
                _shuffle_orig = [t.get("videoId") for t in rest]
                random.shuffle(rest)
                _queue = _queue[:_q_pos + 1] + rest
                nxt = _queue[_q_pos + 1]["videoId"]
                threading.Thread(target=resolve_stream, args=(nxt,), daemon=True).start()
            elif 0 <= _q_pos < len(_queue):
                seed = _queue[_q_pos].get("videoId")
                if seed: threading.Thread(target=_populate_radio, args=(seed, False), daemon=True).start()
        elif _shuffle_on and rest:
            # Goes back to the original order; tracks added later stay at the end
            order = {vid: i for i, vid in enumerate(_shuffle_orig)}
            known = sorted([t for t in rest if t.get("videoId") in order], key=lambda t: order[t.get("videoId")])
            extra = [t for t in rest if t.get("videoId") not in order]
            _queue = _queue[:_q_pos + 1] + known + extra
            if _q_pos + 1 < len(_queue):
                threading.Thread(target=resolve_stream, args=(_queue[_q_pos + 1]["videoId"],), daemon=True).start()
        _shuffle_on = want
    return jsonify({"ok": True, "shuffle": _shuffle_on, "repeat": _repeat_mode, "queue_len": len(_queue), "pos": _q_pos})

@app.route("/player/repeat")
def player_repeat():
    """?mode=off|all|one; without a parameter it moves to the next (off → all → one → off)."""
    global _repeat_mode
    m = freq.args.get("mode")
    if m not in ("off", "all", "one"):
        m = {"off": "all", "all": "one"}.get(_repeat_mode, "off")
    _repeat_mode = m
    log("ripeti ->", m)
    if player:
        try: player.loop_file = "inf" if m == "one" else "no"   # one track: mpv repeats it by itself
        except Exception: pass
    return jsonify({"ok": True, "shuffle": _shuffle_on, "repeat": _repeat_mode})

if player:
    @player.event_callback("end_file")
    def _on_end(ev):
        try:
            reason = getattr(ev, "data", None)
            reason = getattr(reason, "reason", None) or (reason or {}).get("reason") if reason else None
        except: reason = None
        if (reason in ("eof", 0)) or (getattr(reason, "value", None) == 0) or ("eof" in str(reason).lower()):
            _advance_or_related()
        elif "error" in str(reason).lower():
            # mpv could not play (usually yt-dlp extraction failed)
            global _last_play_error
            _last_play_error = "mpv end_file: %s" % str(reason)
            log("PLAYBACK FAILED (end_file reason=%s) — often yt-dlp needs updating" % str(reason))
            threading.Thread(target=_recover_failed, args=(_cur_vid,), daemon=True).start()

def _recover_failed(vid):
    """The track does not start: first it retries (new stream, other yt-dlp clients),
    only if it is really unplayable do we move to the next one."""
    if not vid or vid != _cur_vid: return
    n = _play_retries.get(vid, 0)
    if n < 2:
        _play_retries[vid] = n + 1
        log("retrying the track", vid, "(tentativo", n + 1, ")")
        _stream_cache.pop(vid, None)
        _bad = _stream_client.get(vid)
        _yt_skip.setdefault(vid, set()).add(_bad)
        log("client", _bad, "not playable for", vid, "- trying another")
        if resolve_stream(vid, force=True) and 0 <= _q_pos < len(_queue) and _queue[_q_pos].get("videoId") == vid:
            _play_at(_q_pos)
            return
    log("unplayable track, moving to the next:", vid)
    _play_retries.pop(vid, None)
    _advance_or_related(force=True)

_last_advance_at = 0.0
def _advance_or_related(force=False):
    global _last_advance_at
    now = time.time()
    if not force and now - _last_advance_at < 3: return
    _last_advance_at = now

    if _repeat_mode == "one" and 0 <= _q_pos < len(_queue):
        threading.Thread(target=_play_at, args=(_q_pos,), daemon=True).start()
        return
    if _repeat_mode == "all" and _queue and _q_pos >= len(_queue) - 1:
        # Repeat all: at the end of the queue it starts again from the first track
        threading.Thread(target=_play_at, args=(0,), daemon=True).start()
        return
    if _q_pos < len(_queue) - 1:
        threading.Thread(target=_play_at, args=(_q_pos + 1,), daemon=True).start()
        if _q_pos + 1 >= len(_queue) - 2:
            last_vid = _queue[_q_pos + 1].get("videoId")
            if last_vid: threading.Thread(target=_populate_radio, args=(last_vid, False), daemon=True).start()
    else:
        last = _queue[_q_pos] if 0 <= _q_pos < len(_queue) else None
        if last and last.get("videoId"):
            threading.Thread(target=_populate_radio, args=(last["videoId"], True), daemon=True).start()

_manual_stop = False
def _watchdog():
    was_playing = False
    while True:
        time.sleep(1.5)
        if not player: continue
        try:
            idle = bool(player.core_idle)
            paused = bool(player.pause)
        except: continue
        playing = (not idle) and (not paused)
        global _cur_started
        try:
            if playing and (player.time_pos or 0) > 0.5: _cur_started = True
        except Exception: pass
        # It advances only if this track had really started and then stopped by itself:
        # before, slow loading (or a track that does not start) was mistaken for
        # "end of track" and the chosen track was skipped.
        if was_playing and idle and not paused and _queue and _cur_started:
            _cur_started = False
            _advance_or_related()
        was_playing = playing

if player:
    threading.Thread(target=_watchdog, daemon=True).start()

@app.route("/play_context", methods=["POST"])
def play_context():
    global _queue, _q_pos
    if not player: return jsonify({"status": "error", "error": "mpv not available"}), 503
    data = freq.get_json(silent=True) or {}
    tracks = [t for t in (data.get("tracks") or []) if t.get("videoId")]
    idx = max(0, min(int(data.get("index", 0)), max(len(tracks)-1, 0)))
    if not tracks: return jsonify({"status": "error", "error": "coda vuota"}), 400
    
    global _shuffle_orig
    if _shuffle_on and len(tracks) > 1:
        # Shuffle: the chosen track starts, all the others in the list in random order
        chosen = tracks[idx]
        others = tracks[:idx] + tracks[idx + 1:]
        _shuffle_orig = [t.get("videoId") for t in others]
        random.shuffle(others)
        tracks = [chosen] + others
        idx = 0
    else:
        _shuffle_orig = []
    with _lock:
        _queue = tracks
        _q_pos = idx      # right away: so the displayed queue is already the right one
    threading.Thread(target=_play_at, args=(idx,), daemon=True).start()
    
    if idx >= len(tracks) - 2:
        threading.Thread(target=_populate_radio, args=(tracks[idx]["videoId"], False), daemon=True).start()
        
    return jsonify({"status": "starting", "count": len(_queue), "index": idx, "track": tracks[idx]})

@app.route("/play/<video_id>")
def play_media(video_id):
    global _queue, _q_pos, _resume_start_sec
    if not player: return jsonify({"status": "error", "error": "mpv not available"}), 503
    _queue = [{"videoId": video_id, "title": freq.args.get("title",""),
               "subtitle": freq.args.get("subtitle",""), "cover": freq.args.get("cover",""),
               "isVideo": False}]
    _q_pos = 0
    try: _resume_start_sec = max(0.0, float(freq.args.get("start_ms", 0) or 0) / 1000.0)
    except Exception: _resume_start_sec = 0.0
    threading.Thread(target=_play_at, args=(0,), daemon=True).start()
    threading.Thread(target=_populate_radio, args=(video_id, False), daemon=True).start()
    return jsonify({"status": "starting", "videoId": video_id})

@app.route("/player/next")
def player_next():
    global _last_advance_at
    if not player: return jsonify({"ok": False}), 503
    _last_advance_at = time.time()
    if _q_pos < len(_queue) - 1:
        _play_at(_q_pos + 1)
    else:
        # End of queue (e.g. a single track started from search
        # whose radio had not arrived): before, "next" no longer did anything.
        # Now it loads the recommended tracks and moves to the first right away.
        cur = _q_current()
        if cur and cur.get("videoId"):
            threading.Thread(target=_populate_radio, args=(cur["videoId"], True), daemon=True).start()
    return jsonify({"ok": True, "index": _q_pos, "track": _q_current()})

@app.route("/player/prev")
def player_prev():
    global _last_advance_at
    if not player: return jsonify({"ok": False}), 503
    _last_advance_at = time.time()
    try:
        if (player.time_pos or 0) > 3 or _q_pos <= 0: player.seek(0, reference="absolute")
        else: _play_at(_q_pos - 1)
    except: pass
    return jsonify({"ok": True, "index": _q_pos, "track": _q_current()})

@app.route("/player/stop")
def player_stop():
    global _queue, _q_pos, _manual_stop
    _manual_stop = True
    if player:
        try:
            player.pause = True
            player.stop()
        except: pass
    _queue = []; _q_pos = -1
    return jsonify({"ok": True})

@app.route("/player/pause")
def toggle_pause():
    if not player: return jsonify({"paused": True}), 503
    global _manual_stop
    st = freq.args.get("state")
    if st is not None: player.pause = (st == "1")
    else: player.pause = not player.pause
    return jsonify({"paused": player.pause})

@app.route("/player/seek")
def player_seek():
    if not player: return jsonify({"ok": False}), 503
    try:
        pct = max(0.0, min(float(freq.args.get("pct", 0)), 1.0))
        dur = player.duration or 0
        if dur > 0: player.seek(pct * dur, reference="absolute")
    except: pass
    return jsonify({"ok": True})

@app.route("/player/status")
def player_status():
    if not player:
        return jsonify({"is_playing": False, "progress_ms": 0, "duration_ms": 1, "index": -1, "track": None, "queue": []})
    
    upcoming = []
    with _lock:
        if 0 <= _q_pos < len(_queue):
            upcoming = _queue[_q_pos+1 : _q_pos+21]

    return jsonify({
        "is_playing": not player.core_idle and not player.pause,
        "progress_ms": (player.time_pos or 0) * 1000,
        "duration_ms": (player.duration or 1) * 1000,
        "index": _q_pos,
        "track": _q_current(),
        "queue": upcoming,
        "shuffle": _shuffle_on,
        "repeat": _repeat_mode,
        # ── Diagnostics: if the audio does not start, here you see why ──
        "idle": bool(player.core_idle),
        "last_error": _last_play_error
    })

def _home_classify(c):
    if not c: return None
    vid = c.get('videoId')
    bid = c.get('browseId', '') or ''
    pid = c.get('playlistId', '') or c.get('audioPlaylistId', '') or ''

    # Podcast episode: it has a videoId BUT comes from parse_episode, which carries
    # 'description'/'date' with it — a normal song (parse_song) does not have them.
    # Before, it was taken by the "vid" branch below and ended up labeled "Track".
    if vid and (c.get('description') is not None or c.get('date') is not None):
        d = song_to_dict(c, bypass_filter=True)
        if d:
            d['type'] = 'Episode'
            if c.get('date'): d['subtitle'] = c.get('date')
        return d

    if vid:
        if studio_only() and is_video_item(c): return None
        d = song_to_dict(c)
        # Real music video (not just audio): distinguish from the normal Track.
        if d and _video_type(c) == 'OMV':
            d['type'] = 'Video'
        return d

    if bid.startswith('MPRE'):
        d = playlist_to_dict(c)
        if d:
            d['type'] = 'Album'
            d['browseId'] = bid
            # Artist name under the album title (before it stayed empty)
            try:
                names = [a.get('name', '') for a in (c.get('artists') or []) if isinstance(a, dict) and a.get('name')]
                if names:
                    d['subtitle'] = ', '.join(names)
                elif c.get('year'):
                    d['subtitle'] = str(c.get('year'))
            except Exception:
                pass
        return d

    if bid.startswith('UC') or c.get('subscribers'):
        return artist_to_dict(c)

    # Auto-generated Mix/Radio (playlistId with "RD" prefix): same
    # mechanism as normal playlists, but labeled Mix for the UI.
    if pid.startswith('RD'):
        d = playlist_to_dict(c)
        if d: d['type'] = 'Mix'
        return d

    if pid or bid.startswith('VL') or bid.startswith('PL'):
        return playlist_to_dict(c)

    # Podcast (show): niente videoId/playlistId. parse_podcast restituisce
    # 'channel' (channel name) and/or 'podcastId'. Before it fell through here below and
    # spariva silenziosamente (return None).
    if c.get('channel') or c.get('podcastId'):
        title = c.get('title', '')
        if not title: return None
        channel = c.get('channel')
        subtitle = channel.get('name', '') if isinstance(channel, dict) else (channel or '')
        return {
            "title": title,
            "subtitle": subtitle or "Podcast",
            "cover": thumb(c.get('thumbnails', [])),
            "browseId": bid,
            "type": "Podcast",
            "isContext": True,
            "isVideo": False,
        }

    return None

# ── LOGIN/LOGOUT ("device" OAuth flow, for the button in the UI) ──
_auth_flow = {}  # state of the login in progress: credentials, device_code, started_at

@app.route("/auth/browser_save", methods=["POST"])
def auth_browser_save():
    """Receives the headers captured automatically by the WebEngineView (real
    login on music.youtube.com) and saves them in ytmusicapi's 'browser auth'
    format — the same one that 'ytmusicapi browser' produces from the terminal.
    We use the library's official function for parsing/validation, so
    the produced file is guaranteed to have the same format as the official one."""
    data = freq.get_json(silent=True) or {}
    headers = data.get('headers') or {}
    if not headers.get('cookie'):
        return jsonify({"error": "no_cookie", "message": "Cookie not captured, try again"}), 400
    if not headers.get('authorization'):
        return jsonify({"error": "no_authorization", "message": "Authorization header not captured, try again"}), 400
    try:
        from ytmusicapi.auth.browser import setup_browser
        # "Name: value" format per line, as if pasted from DevTools.
        raw = "\n".join(f"{k}: {v}" for k, v in headers.items() if v)
        os.makedirs(os.path.dirname(OAUTH_PATH), exist_ok=True)
        setup_browser(filepath=OAUTH_PATH, headers_raw=raw)
        os.chmod(OAUTH_PATH, 0o600)
    except Exception as e:
        log("auth/browser_save err:", repr(e))
        return jsonify({"error": "save_failed", "message": str(e)}), 500
    global _yt
    with _lock:
        _yt = None  # forces reinitialization with the new account at next use
    _cache.clear()
    _account_cache.update({"t": 0.0, "v": None})
    log("Login (browser auth) completato, nuovo file salvato")
    ok, why = _verify_session(force=True)
    return jsonify({"status": "done", "verified": ok, "why": why})

_verify_cache = {"t": 0.0, "ok": None, "why": ""}
_account_cache = {"t": 0.0, "v": None}

@app.route("/auth/account")
def auth_account():
    """Name and photo of the connected account (for the avatar in the header)."""
    now = time.time()
    if _account_cache["v"] is not None and now - _account_cache["t"] < 3600:
        return jsonify(_account_cache["v"])
    res = {"name": "", "photo": ""}
    yt = get_yt() if os.path.exists(OAUTH_PATH) else None
    if yt:
        try:
            info = yt.get_account_info() or {}
            res = {"name": info.get("accountName") or "", "photo": info.get("accountPhotoUrl") or ""}
            _account_cache.update({"t": now, "v": res})
        except Exception as e:
            log("account info err:", repr(e)[:160])
    return jsonify(res)

def _verify_session(force=False):
    """Tries a real call that requires login. Returns (ok, reason):
    True = valid; False = rejected/expired; None = unknown (e.g. no network)."""
    now = time.time()
    if not force and _verify_cache["ok"] is not None and now - _verify_cache["t"] < 120:
        return _verify_cache["ok"], _verify_cache["why"]
    yt = get_yt()
    if not yt:
        return None, "servizio"
    try:
        yt.get_account_info()   # fails if YouTube does not recognize an account
        ok, why = True, ""
    except Exception as e:
        low = str(e).lower()
        if "unable to find" in low:
            ok, why = False, "anonima"
        elif any(k in low for k in ("401", "403", "unauthor", "sign in", "logged", "authentic", "provide auth")):
            ok, why = False, "scaduta"
        elif "400" in low:
            ok, why = False, "rifiutata"
        else:
            ok, why = None, "rete"
        log("verifica sessione:", ok, why, repr(e)[:160])
    _verify_cache.update({"t": now, "ok": ok, "why": why})
    return ok, why

def _qr_svg(text):
    """QR as SVG (text). Uses 'segno' (or 'qrcode' if present); None if neither is installed."""
    try:
        import io, segno
        buf = io.BytesIO()
        segno.make(text, error="m").save(buf, kind="svg", scale=8, border=4, xmldecl=False)
        return buf.getvalue().decode("utf-8")
    except ImportError:
        pass
    except Exception as e:
        log("qr (segno) err:", repr(e)); return None
    try:
        import io, qrcode, qrcode.image.svg
        img = qrcode.make(text, image_factory=qrcode.image.svg.SvgPathImage, box_size=8, border=4)
        buf = io.BytesIO(); img.save(buf)
        return buf.getvalue().decode("utf-8")
    except Exception:
        return None

@app.route("/auth/qr.svg")
def auth_qr():
    text = (freq.args.get("text") or "")[:400]
    if not text.startswith("https://"):
        return ("invalid text", 400)
    svg = _qr_svg(text)
    if not svg:
        return ("QR not available: install python3-segno", 501)
    from flask import Response
    return Response(svg, mimetype="image/svg+xml", headers={"Cache-Control": "no-store"})

@app.route("/auth/status")
def auth_status():
    has_file = os.path.exists(OAUTH_PATH)
    out = {
        "loggedIn": has_file,
        "clientConfigured": _load_oauth_client() is not None,
        "qrAvailable": _qr_svg("https://example.com") is not None,
    }
    if has_file and freq.args.get("verify") == "1":
        ok, why = _verify_session()
        if ok is False:
            out["loggedIn"] = False
            out["reason"] = why
    return jsonify(out)

@app.route("/auth/start", methods=["POST"])
def auth_start():
    client = _load_oauth_client()
    if not client:
        return jsonify({"error": "no_client_config",
                         "message": "Create ~/.config/volta/yt_oauth_client.json first"}), 400
    try:
        from ytmusicapi import OAuthCredentials
        creds = OAuthCredentials(client_id=client['client_id'], client_secret=client['client_secret'])
        code = creds.get_code()
        _auth_flow.clear()
        _auth_flow['credentials'] = creds
        _auth_flow['device_code'] = code['device_code']
        _auth_flow['started'] = time.time()
        url = f"{code['verification_url']}?user_code={code['user_code']}"
        import urllib.parse
        qr = None
        if _qr_svg(url):
            qr = f"http://127.0.0.1:{PORT}/auth/qr.svg?text=" + urllib.parse.quote(url, safe="")
        return jsonify({
            "url": url,
            "qr": qr,
            "userCode": code['user_code'],
            "expiresIn": code.get('expires_in', 1800),
            "interval": code.get('interval', 5),
        })
    except Exception as e:
        log("auth/start err:", repr(e))
        return jsonify({"error": "start_failed", "message": str(e)}), 500

@app.route("/auth/poll")
def auth_poll():
    if 'device_code' not in _auth_flow:
        return jsonify({"status": "no_flow"}), 400
    # Expired on our side after 10 minutes, so as not to hang forever.
    if time.time() - _auth_flow.get('started', 0) > 600:
        _auth_flow.clear()
        return jsonify({"status": "expired"})
    try:
        creds = _auth_flow['credentials']
        raw = creds.token_from_code(_auth_flow['device_code'])
    except Exception as e:
        log("auth/poll err:", repr(e))
        return jsonify({"status": "error", "message": str(e)})

    if raw.get('access_token'):
        try:
            from ytmusicapi.auth.oauth import RefreshingToken
            from pathlib import Path
            creds = _auth_flow['credentials']
            expires_in = raw.get('expires_in', 3600)
            ref_token = RefreshingToken(
                credentials=creds,
                access_token=raw['access_token'],
                refresh_token=raw['refresh_token'],
                scope=raw['scope'],
                token_type=raw['token_type'],
                expires_in=raw.get('refresh_token_expires_in', expires_in),
            )
            ref_token.update(raw)  # calcola expires_at coerente col metodo ufficiale
            os.makedirs(os.path.dirname(OAUTH_PATH), exist_ok=True)
            ref_token.local_cache = Path(OAUTH_PATH)  # triggera store_token() ufficiale
            os.chmod(OAUTH_PATH, 0o600)
        except Exception as e:
            log("auth/poll: error saving token with RefreshingToken:", repr(e))
            _auth_flow.clear()
            return jsonify({"status": "error", "message": "salvataggio token fallito: " + str(e)})
        _auth_flow.clear()
        global _yt
        with _lock:
            _yt = None  # forces reinitialization with the new account at next use
        _cache.clear()  # remove the old home (wrong account) from the cache
        log("Login completato, nuovo oauth.json salvato (RefreshingToken)")
        ok, why = _verify_session(force=True)
        if ok is False:
            log("WARNING: login succeeded but YouTube Music rejects the requests (%s)" % why)
            return jsonify({"status": "done", "verified": False, "reason": why})
        return jsonify({"status": "done", "verified": True if ok else None})

    err = (raw.get('error') or '').lower()
    if err in ('authorization_pending', 'slow_down'):
        return jsonify({"status": "pending"})
    _auth_flow.clear()
    return jsonify({"status": "error", "message": err or "unknown error"})

@app.route("/auth/logout", methods=["POST"])
def auth_logout():
    global _yt
    try:
        if os.path.exists(OAUTH_PATH):
            os.remove(OAUTH_PATH)
        with _lock:
            _yt = None
        _cache.clear()
        _account_cache.update({"t": 0.0, "v": None})
        _verify_cache.update({"t": 0.0, "ok": None, "why": ""})
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "message": str(e)}), 500

@app.route("/ui/home")
def ui_home():
    yt = get_yt()
    res = {"shelves": []}
    if not yt: return jsonify(res)

    def fetch():
        try:
            home_data = yt.get_home(limit=20)
            shelves = []
            quick_picks_shelf = None

            for r in home_data:
                title = (r.get('title') or '').strip()
                t_low = title.lower()
                if not title: continue

                bad_words = [
                    'shorts', 'short', 'reel', 'vlog', 'reaction'
                ]
                if any(w in t_low for w in bad_words):
                    continue
                # Video-only shelves ("Music video chart"...): out
                if studio_only() and _VIDEO_WORD.search(title):
                    continue

                items = []
                for c in r.get('contents', []):
                    d = _home_classify(c)
                    if d: items.append(d)

                if len(items) >= 3:
                    all_artist = all(x.get('type') == 'Artist' for x in items)
                    shelf_obj = {
                        "title": title,
                        "items": items[:24],
                        "isCircle": all_artist,
                    }
                    
                    if 'scelte rapide' in t_low or 'quick picks' in t_low:
                        if not quick_picks_shelf:
                            shelf_obj["title"] = "Scelte rapide"
                            quick_picks_shelf = shelf_obj
                    else:
                        shelves.append(shelf_obj)

            if quick_picks_shelf:
                res["shelves"].append(quick_picks_shelf)

            res["shelves"].extend(shelves)

        except Exception as e:
            log("Home err:", repr(e))
            _reset_yt()          # session created offline: it is rebuilt at the next request
            return None          # do not cache an empty/failed result
        return res if res["shelves"] else None

    if freq.args.get("fresh") == "1":
        _cache.pop("ui_home", None)
    return jsonify(cached("ui_home", fetch, ttl=60) or res)

@app.route("/ui/library")
def ui_library():
    yt = get_yt()
    filter_type = freq.args.get("filter", "playlists")
    if not yt: return jsonify({"items": []})
    def fetch():
        items = []
        try:
            if filter_type == "playlists":
                items.append({"title": "Musica che ti piace", "subtitle": "Auto Playlist", "cover": "", "playlistId": "LM", "type": "Playlist", "isContext": True})
                items.extend([pd for p in yt.get_library_playlists(limit=100) if (pd := playlist_to_dict(p))])
            elif filter_type == "songs":
                items.extend([sd for i, s in enumerate(yt.get_library_songs(limit=100)) if (sd := song_to_dict(s, i, bypass_filter=True))])
            elif filter_type == "albums":
                items.extend([pd for a in yt.get_library_albums(limit=100) if (pd := playlist_to_dict(a))])
            elif filter_type == "artists":
                items.extend([ad for a in yt.get_library_subscriptions(limit=100) if (ad := artist_to_dict(a))])
            elif filter_type == "podcasts":
                items.extend([pd for p in yt.get_library_podcasts(limit=100) if (pd := playlist_to_dict(p))])
        except Exception as e: log("Library err:", e)
        return {"items": items}
    return jsonify(cached(f"ui_lib_{filter_type}", fetch, ttl=120) or {"items": []})

@app.route("/playlist/<pl_id>")
def playlist_tracks(pl_id):
    yt = get_yt()
    if not yt: return jsonify({"tracks":[]}), 503
    def fetch():
        kind = "playlist"
        try:
            if pl_id == "LM":
                p = yt.get_liked_songs(limit=100)
            elif pl_id.startswith("MPREb"):
                p = yt.get_album(pl_id); kind = "album"
            elif pl_id.startswith("RD"):
                p = yt.get_watch_playlist(playlistId=pl_id, limit=100)
                kind = "playlist"
                if not p.get('title'): p['title'] = "Mix Playlist"
            elif pl_id.startswith("OLAK5uy_"):
                bid = None
                try: bid = yt.get_album_browse_id(pl_id)
                except: pass
                if bid: p = yt.get_album(bid); kind = "album"
                else: p = yt.get_playlist(pl_id, limit=100)
            else:
                p = yt.get_playlist(pl_id, limit=100)
        except Exception as e:
            log("Error loading playlist", pl_id, ":", repr(e))
            return None

        playlist_cover = thumb(p.get('thumbnails',[]))
        tracks = []
        for i, t in enumerate(p.get('tracks',[]) or []):
            if kind == "album":
                if t.get("isAvailable") is False: continue
            
            d = song_to_dict(t, i, bypass_filter=True)
            if d:
                track_thumbs = t.get('thumbnails') or t.get('thumbnail') or []
                track_cover = thumb(track_thumbs)
                
                d['cover'] = track_cover if track_cover else playlist_cover
                d['duration'] = t.get('duration', '')
                tracks.append(d)
                
        if not playlist_cover and tracks: playlist_cover = tracks[0]['cover']
        
        if len(tracks) == 0:
            _empty_playlists.add(pl_id)
            return {"title": p.get('title',''), "cover": playlist_cover, "type": kind, "total": 0, "tracks": []}
            
        return {"title": p.get('title',''), "cover": playlist_cover, "type": kind, "total": len(tracks), "tracks": tracks}

    return jsonify(cached("pl_"+pl_id, fetch, ttl=900) or {"tracks":[]})

@app.route("/artist/<browse_id>")
def artist_data(browse_id):
    yt = get_yt()
    if not yt: return jsonify({"tracks":[],"albums":[],"singles":[]}), 503
    def fetch():
        a = yt.get_artist(browse_id)
        name, cover = a.get('name',''), thumb(a.get('thumbnails',[]))
        tracks = [d for i, t in enumerate(a.get('songs',{}).get('results',[])[:10]) if (d := song_to_dict(t, i, bypass_filter=True))]
        
        if len(tracks) == 0:
            _empty_playlists.add(browse_id)
            
        for t in tracks: t['subtitle'], t['cover'] = name, t['cover'] or cover
        albums = [playlist_to_dict(al) for al in a.get('albums',{}).get('results',[])[:20]]
        singles = [playlist_to_dict(s) for s in a.get('singles',{}).get('results',[])[:20]]
        return {"name": name, "cover": cover, "tracks": tracks, "albums": [x for x in albums if x], "singles": [x for x in singles if x]}
    return jsonify(cached("art_"+browse_id, fetch) or {"tracks":[],"albums":[],"singles":[]})

@app.route("/ui/diag")
def ui_diag():
    """Quick diagnostics: open http://127.0.0.1:8099/ui/diag in the browser."""
    out = {"version": "studio-v4", "studioOnly": studio_only(), "recentsInMemory": len(_recents), "recentsFile": RECENTS_PATH,
           "recentsFileExists": os.path.exists(RECENTS_PATH), "oauthFile": OAUTH_PATH,
           "oauthFileExists": os.path.exists(OAUTH_PATH)}
    try:
        import ytmusicapi; out["ytmusicapi"] = getattr(ytmusicapi, "__version__", "?")
    except Exception as e: out["ytmusicapi"] = "NOT INSTALLED: %r" % e
    yt = get_yt()
    out["ytClient"] = bool(yt)
    if not yt: return jsonify(out)
    try:
        res = yt.search("daft punk", filter="songs", limit=10)
        out["searchSongsRaw"] = len(res)
        out["searchSongsStudio"] = sum(1 for r in res if not is_video_item(r))
        out["searchSample"] = [{"title": r.get("title"), "videoType": r.get("videoType"),
                                "thumb": (r.get("thumbnails") or [{}])[-1], "video": is_video_item(r)} for r in res[:4]]
    except Exception as e: out["searchError"] = repr(e)
    try: out["librarySongs"] = len(yt.get_library_songs(limit=5))
    except Exception as e: out["libraryError"] = repr(e)
    try: out["homeShelves"] = len(yt.get_home(limit=3))
    except Exception as e: out["homeError"] = repr(e)
    return jsonify(out)

@app.route("/ui/studio")
def ui_studio():
    """GET: state. ?on=1|0: turns "studio music only" on/off (saved). Version: studio-v4."""
    v = freq.args.get("on")
    if v is not None:
        _prefs["studioOnly"] = v in ("1", "true", "yes", "on")
        try:
            os.makedirs(os.path.dirname(PREFS_PATH), exist_ok=True)
            with open(PREFS_PATH, "w") as f: json.dump(_prefs, f)
        except Exception as e: log("prefs not saved:", repr(e))
        _cache.pop("ui_home", None)           # the home must be recomputed
    return jsonify({"studioOnly": studio_only(), "version": "studio-v4"})

@app.route("/search")
def search():
    q = freq.args.get("q","").strip()
    yt = get_yt()
    if not q or not yt: return jsonify({"tracks":[],"videos":[],"albums":[],"artists":[],"playlists":[]})
    
    tracks, videos, albums, artists, playlists = [], [], [], [], []
    top_result = None
    _search_dbg = {"version": "studio-v4", "studioOnly": studio_only()}

    with ThreadPoolExecutor(max_workers=6) as ex:
        def get_top():
            # Search WITHOUT filter: the real "top result" can be
            # of any type (song, video, artist, album, playlist),
            # not just a song — unlike get_tracks() below.
            res = yt.search(q, limit=5)
            for r in res:
                d = _home_classify(r)
                if d: return d
            return None
        def get_tracks():
            # 1) YouTube Music 'songs' filter; 2) if it fails/gives <2 tracks, we
            # fall back to the search without filter (rows of type song). The errors
            # stay in _search_dbg and appear in /search?debug=1.
            def conv(res, allow_video=False):
                out = []
                for i, r in enumerate(res or []):
                    try:
                        rt = r.get('resultType')
                        if rt == 'video' and (studio_only() or not allow_video): continue
                        if rt not in ('song', 'video'): continue
                        if not is_playable_media(r): continue
                        d = song_to_dict(r, i)
                        if d and d.get('videoId'): out.append(d)
                    except Exception as e:
                        log("track discarded due to error (%r): %r" % (e, (r or {}).get('title')))
                return out
            out = []
            try:
                res = yt.search(q, filter='songs', limit=20)
                _search_dbg['songs_raw'] = len(res or [])
                _search_dbg['songs_types'] = sorted({str(r.get('resultType')) for r in (res or [])})
                out = conv(res)
            except Exception as e:
                import traceback
                _search_dbg['songs_error'] = traceback.format_exc()[-600:]
                log("ricerca '%s': filtro songs fallito: %r" % (q, e))
            if len(out) < 2:
                try:
                    res2 = yt.search(q, limit=20)
                    _search_dbg['plain_raw'] = len(res2 or [])
                    _search_dbg['plain_types'] = sorted({str(r.get('resultType')) for r in (res2 or [])})
                    seen = {t['videoId'] for t in out}
                    for d in conv(res2, allow_video=False):
                        if d['videoId'] not in seen: out.append(d); seen.add(d['videoId'])
                except Exception as e:
                    import traceback
                    _search_dbg['plain_error'] = traceback.format_exc()[-600:]
                    log("ricerca '%s': ricerca semplice fallita: %r" % (q, e))
            return out
        def get_videos():
            if studio_only(): return []        # studio music only: no video tab
            res = yt.search(q, filter='videos', limit=6)
            return [d for i, r in enumerate(res) if is_playable_media(r) and (d := song_to_dict(r, i))]
        def get_albums():
            res = yt.search(q, filter='albums', limit=6)
            return [p for r in res if (p := playlist_to_dict(r))]
        def get_artists():
            res = yt.search(q, filter='artists', limit=6)
            return [a for r in res if (a := artist_to_dict(r))]
        def get_playlists():
            res = yt.search(q, filter='featured_playlists', limit=6)
            return [p for r in res if (p := playlist_to_dict(r))]

        fut_top = ex.submit(get_top)
        fut_t = ex.submit(get_tracks)
        fut_v = ex.submit(get_videos)
        fut_al = ex.submit(get_albums)
        fut_ar = ex.submit(get_artists)
        fut_pl = ex.submit(get_playlists)

        def _res(fut, name, default):
            try: return fut.result(timeout=10)
            except Exception as e:
                log("ricerca '%s': %s fallita -> %r" % (q, name, e))
                return default
        top_result = _res(fut_top, "top", None)
        tracks = _res(fut_t, "brani", [])
        if top_result is None and tracks: top_result = tracks[0]
        videos = _res(fut_v, "video", [])
        albums = _res(fut_al, "album", [])
        artists = _res(fut_ar, "artisti", [])
        playlists = _res(fut_pl, "playlist", [])

    log("search '%s': tracks=%d video=%d album=%d artists=%d playlist=%d" % (q, len(tracks), len(videos), len(albums), len(artists), len(playlists)))
    if freq.args.get("debug"):
        _search_dbg.update({"n_tracks": len(tracks), "n_albums": len(albums), "n_artists": len(artists)})
        return jsonify({"debug": _search_dbg, "tracks": tracks[:3]})
    return jsonify({
        "top_result": top_result,
        "tracks": tracks[:8],
        "videos": videos[:6],
        "albums": albums[:6],
        "artists": artists[:6],
        "playlists": playlists[:6]
    })

if __name__ == "__main__":
    os.makedirs(os.path.dirname(OAUTH_PATH), exist_ok=True)
    get_yt()

    def _auto_refresh():
        import urllib.request
        base = f"http://127.0.0.1:{PORT}"
        time.sleep(20)
        while True:
            try:
                body = urllib.request.urlopen(base + "/ui/home?fresh=1", timeout=40).read()
                try:
                    d = json.loads(body)
                    ids, seen = [], set()
                            
                    for shelf in (d.get("shelves") or []):
                        for it in shelf.get("items", []):
                            pid = it.get("playlistId") or it.get("browseId") or ""
                            if pid and pid not in seen and not it.get("videoId"):
                                seen.add(pid); ids.append(pid)
                                        
                    for pid in ids[:10]:
                        try: urllib.request.urlopen(base + "/playlist/" + pid, timeout=40).read()
                        except: pass
                except: pass
            except: pass
            time.sleep(300)
            
    threading.Thread(target=_auto_refresh, daemon=True).start()
    app.run(host="127.0.0.1", port=PORT, threaded=True)
