#!/usr/bin/env python3
# local_music_service.py — Music app: audio files of the PC and of USB sticks.
#
# Port 8097 (127.0.0.1 only). No account and no internet: it reads the files, the tags (mutagen) and the covers,
# plays them with mpv and announces itself to the system as the "Music" player (MPRIS), so the mini player shows title,
# cover and controls as for YT Music and Spotify.
#
# Folders read: ONLY the user's Music folder (whether it is called Musica, Music, Musique... depending on the Debian
# language: XDG says it) and, automatically, every USB stick or disk mounted in /media, /run/media or /mnt.
# Covers: only those of the files (tags) or of the folder; if missing the interface shows the music widget's placeholder.
# Indice e preferenze in ~/.config/volta/localmusic/.
import os, sys, re, json, time, hashlib, threading, random, io, base64
from flask import Flask, jsonify, request as freq, Response

PORT = int(os.environ.get("LOCALMUSIC_PORT", "8097"))
DIR = os.environ.get("LOCALMUSIC_DIR", os.path.expanduser("~/.config/volta/localmusic"))
COVER_DIR = os.path.join(DIR, "covers_file")      # (the old "covers" could contain covers downloaded from the internet: no longer used)
os.makedirs(COVER_DIR, exist_ok=True)
EXTS = (".mp3", ".flac", ".ogg", ".oga", ".opus", ".m4a", ".mp4", ".aac", ".wav", ".wma", ".ape", ".wv", ".aif", ".aiff")
FONT = os.environ.get("LOCALMUSIC_FONT", os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "fonts", "VoltaFont-Bold.ttf"))
MPRIS_NAME = os.environ.get("LOCALMUSIC_MPRIS_NAME", "org.mpris.MediaPlayer2.volta_musica")

app = Flask(__name__)
from local_security import protect
protect(app)

def log(*a): print("[musica]", *a, file=sys.stderr, flush=True)
def _md5(s): return hashlib.md5(s.encode("utf-8", "replace")).hexdigest()
_lk = threading.RLock()

# ═════════════════════════ Preferenze (config.json) ═════════════════════════
CFG_PATH = os.path.join(DIR, "config.json")
CFG = {"likes": [], "playlists": [], "shuffle": False, "repeat": "off"}
def load_cfg():
    try:
        with open(CFG_PATH, encoding="utf-8") as f: CFG.update(json.load(f))
    except (OSError, ValueError): pass
def save_cfg():
    try:
        tmp = CFG_PATH + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f: json.dump(CFG, f, ensure_ascii=False)
        os.replace(tmp, CFG_PATH)
    except OSError as e: log("config not saved:", repr(e)[:80])

# ═════════════════════════ Sorgenti: PC e chiavette ═════════════════════════
def _music_dir():
    """User's Music folder, with the name in the system language (XDG: Musica, Music, Musique, Música...)."""
    if os.environ.get("LOCALMUSIC_MUSIC_DIR"): return os.environ["LOCALMUSIC_MUSIC_DIR"]
    home = os.path.expanduser("~")
    try:
        for line in open(os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config"), "user-dirs.dirs"), encoding="utf-8"):
            if line.startswith("XDG_MUSIC_DIR"):
                p = line.split("=", 1)[1].strip().strip('"').replace("$HOME", home)
                if os.path.isdir(p) and os.path.abspath(p) != os.path.abspath(home): return p
    except OSError: pass
    try:
        import subprocess
        p = subprocess.run(["xdg-user-dir", "MUSIC"], capture_output=True, text=True, timeout=3).stdout.strip()
        if p and os.path.isdir(p) and os.path.abspath(p) != os.path.abspath(home): return p
    except Exception: pass
    for n in ("Musica", "Music", "Musique", "Música", "Musik", "Muziek", "Müzik", "Музыка"):
        p = os.path.join(home, n)
        if os.path.isdir(p): return p
    return os.path.join(home, "Music")

def _removable_mounts():
    """Mount points of USB/SD sticks and disks."""
    out = []
    try:
        for line in open("/proc/mounts", encoding="utf-8", errors="replace"):
            p = line.split()
            if len(p) < 3: continue
            dev, mp = p[0], p[1].replace("\\040", " ")
            if not dev.startswith("/dev/"): continue
            if mp.startswith("/media/") or mp.startswith("/run/media/") or (mp.startswith("/mnt/") and re.match(r"/dev/(sd|mmcblk|nvme)", dev)):
                out.append(mp)
    except OSError: pass
    return out

def sources():
    """[{id, label, path, kind, present}] — the Music folder and the USB sticks/disks."""
    out, seen = [], set()
    md = _music_dir()
    cand = [(md, "pc", os.path.basename(md.rstrip("/")) or "Musica")]
    for mp in _removable_mounts(): cand.append((mp, "usb", os.path.basename(mp.rstrip("/")) or "USB"))
    for path, kind, label in cand:
        if path in seen: continue
        seen.add(path)
        out.append({"id": _md5(path)[:8], "label": label, "path": path, "kind": kind, "present": os.path.isdir(path)})
    # known sticks that are not connected right now: they stay in the index, hidden
    for sid, info in KNOWN.items():
        if not any(x["id"] == sid for x in out) and info.get("kind") == "usb":
            out.append({"id": sid, "label": info.get("label", "USB"), "path": info.get("path", ""), "kind": "usb", "present": False})
    return out

# ═════════════════════════ Track index ═════════════════════════
INDEX = {}      # path -> track
KNOWN = {}      # id sorgente -> {label, path, kind}
IDX_PATH = os.path.join(DIR, "index.json")
def load_index():
    try:
        with open(IDX_PATH, encoding="utf-8") as f: d = json.load(f)
        INDEX.update(d.get("tracks", {})); KNOWN.update(d.get("known", {}))
    except (OSError, ValueError): pass
def save_index():
    try:
        tmp = IDX_PATH + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f: json.dump({"tracks": INDEX, "known": KNOWN}, f, ensure_ascii=False)
        os.replace(tmp, IDX_PATH)
    except OSError as e: log("index not saved:", repr(e)[:80])

def _int(v):
    m = re.match(r"\s*(\d+)", str(v or ""))
    return int(m.group(1)) if m else 0

def read_tags(path):
    t = {"title": "", "artist": "", "album": "", "albumartist": "", "track": 0, "disc": 0, "year": "", "genre": "", "dur": 0.0}
    try:
        import mutagen
        f = mutagen.File(path, easy=True)
        if f is not None:
            tg = f.tags or {}
            def g(k):
                try:
                    v = tg.get(k)
                    if isinstance(v, (list, tuple)): v = v[0] if v else ""
                    return str(v or "").strip()
                except Exception: return ""
            t.update(title=g("title"), artist=g("artist"), album=g("album"), albumartist=g("albumartist"),
                     track=_int(g("tracknumber")), disc=_int(g("discnumber")), year=g("date")[:4], genre=g("genre"))
            if f.info is not None and getattr(f.info, "length", None): t["dur"] = float(f.info.length)
    except Exception as e:
        log("tag illeggibili:", os.path.basename(path), repr(e)[:60])
    return t

def make_track(path, src_id, st):
    t = read_tags(path)
    base = os.path.splitext(os.path.basename(path))[0]
    if not t["title"]:
        t["title"] = re.sub(r"^\d+\s*[-_. ]+\s*", "", base).strip() or base
        if not t["track"]: t["track"] = _int(base)
    if not t["album"]: t["album"] = os.path.basename(os.path.dirname(path)) or ""
    if not t["artist"]: t["artist"] = t["albumartist"] or ""
    aa = t["albumartist"] or t["artist"]
    t.update(id=_md5(path)[:12], path=path, src=src_id, size=st.st_size, mtime=int(st.st_mtime),
             akey=_md5((aa.lower() + "|" + t["album"].lower()))[:12])
    return t

SCAN = {"running": False, "done": 0, "total": 0, "label": "", "added": 0, "last": 0}
_scan_lock = threading.Lock()

def scan_source(src):
    path = src["path"]
    if not os.path.isdir(path): return 0
    KNOWN[src["id"]] = {"label": src["label"], "path": path, "kind": src["kind"]}
    files = []
    for root, dirs, names in os.walk(path):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d.lower() not in ("$recycle.bin", "system volume information", "lost+found")]
        for n in names:
            if n.lower().endswith(EXTS) and not n.startswith("."): files.append(os.path.join(root, n))
    SCAN["total"] += len(files)
    added, alive = 0, set()
    for p in files:
        SCAN["done"] += 1
        alive.add(p)
        try: st = os.stat(p)
        except OSError: continue
        old = INDEX.get(p)
        if old and old.get("size") == st.st_size and old.get("mtime") == int(st.st_mtime):
            continue
        with _lk: INDEX[p] = make_track(p, src["id"], st)
        added += 1
    # tracks gone from this source (deleted files)
    with _lk:
        for p in [p for p, t in INDEX.items() if t.get("src") == src["id"] and p not in alive]:
            INDEX.pop(p, None)
    return added

def scan_all(only=None):
    if not _scan_lock.acquire(blocking=False): return
    def run():
        try:
            SCAN.update(running=True, done=0, total=0, added=0)
            for s in sources():
                if not s["present"] or (only and s["id"] != only): continue
                SCAN["label"] = s["label"]
                SCAN["added"] += scan_source(s)
            save_index(); SCAN["last"] = int(time.time())
            log("scan finished: %d tracks" % len(INDEX))
        except Exception as e: log("scansione:", repr(e)[:100])
        finally:
            SCAN["running"] = False; _scan_lock.release()
    threading.Thread(target=run, daemon=True).start()

_mounts_seen = set()
def _watch_usb():
    """Every 4 s: a new stick is scanned by itself."""
    global _mounts_seen
    _mounts_seen = set(_removable_mounts())
    while True:
        time.sleep(4)
        try:
            cur = set(_removable_mounts())
            for mp in cur - _mounts_seen:
                log("chiavetta collegata:", mp)
                SCAN["usb_new"] = {"label": os.path.basename(mp.rstrip("/")) or "USB", "ts": time.time()}
                scan_all(only=_md5(mp)[:8])
            for mp in _mounts_seen - cur: log("chiavetta rimossa:", mp)
            _mounts_seen = cur
        except Exception as e: log("usb:", repr(e)[:80])

def present_ids():
    return {s["id"] for s in sources() if s["present"]}

def _kind_ids(kind):
    """Ids of the present sources of a kind: pc (Music folder) or usb."""
    return {s["id"] for s in sources() if s["present"] and s["kind"] == kind}

def all_tracks():
    ok = present_ids()
    with _lk: return [t for t in INDEX.values() if t.get("src") in ok]

def pub(t):
    return {"id": t["id"], "title": t["title"], "artist": t["artist"], "album": t["album"], "albumartist": t.get("albumartist", ""),
            "track": t.get("track", 0), "disc": t.get("disc", 0), "year": t.get("year", ""), "genre": t.get("genre", ""),
            "dur": round(t.get("dur", 0)), "akey": t["akey"], "src": t["src"], "like": t["id"] in CFG["likes"]}

def _by_id():
    with _lk: return {t["id"]: t for t in INDEX.values()}

def _album_sort(t): return ((t.get("albumartist") or t["artist"]).lower(), t["album"].lower(), t.get("disc", 0), t.get("track", 0), t["title"].lower())

# ═════════════════════════ Covers ═════════════════════════
def _embedded_cover(path):
    try:
        import mutagen
        f = mutagen.File(path)
        if f is None: return None
        tg = f.tags
        if hasattr(f, "pictures") and f.pictures: return f.pictures[0].data                      # FLAC
        if tg is not None:
            for k in tg.keys():
                if str(k).startswith("APIC"): return tg[k].data                                   # MP3
            if "covr" in tg and tg["covr"]: return bytes(tg["covr"][0])                           # M4A
            if "metadata_block_picture" in tg:                                                     # OGG/Opus
                from mutagen.flac import Picture
                return Picture(base64.b64decode(tg["metadata_block_picture"][0])).data
    except Exception: pass
    return None

def _folder_cover(path):
    d = os.path.dirname(path)
    try:
        names = {n.lower(): n for n in os.listdir(d)}
    except OSError: return None
    for base in ("cover", "folder", "front", "album", "albumart", "artwork"):
        for ext in (".jpg", ".jpeg", ".png"):
            if base + ext in names:
                try: return open(os.path.join(d, names[base + ext]), "rb").read()
                except OSError: pass
    return None

_NOCOVER = set()                      # albums without a cover in the files: not checked again every time

def cover_bytes(akey):
    """Cover from the files (tag or image in the folder), None if there is none: the placeholder is drawn by the interface."""
    path = os.path.join(COVER_DIR, akey + ".jpg")
    try: return open(path, "rb").read()
    except OSError: pass
    if akey in _NOCOVER: return None
    tr = sorted([t for t in all_tracks() if t["akey"] == akey], key=_album_sort)
    data = None
    for t in tr[:6]:
        data = _embedded_cover(t["path"]) or _folder_cover(t["path"])
        if data: break
    try:
        from PIL import Image
        if data:
            im = Image.open(io.BytesIO(data)).convert("RGB")
            im.thumbnail((480, 480))
            buf = io.BytesIO(); im.save(buf, "JPEG", quality=88); out = buf.getvalue()
            try:
                with open(path, "wb") as f: f.write(out)
            except OSError: pass
            return out
    except Exception: pass
    _NOCOVER.add(akey)
    return None

# ═════════════════════════ Riproduzione (mpv) ═════════════════════════
player = None
def init_mpv():
    global player
    try:
        import mpv
        player = mpv.MPV(video=False, ytdl=False)
        try: player["af"] = "loudnorm=I=-16:TP=-1.5:LRA=11"      # same level as YT Music, Spotify and podcasts
        except Exception: pass
        for k, v in (("keep-open", "yes"), ("audio-display", "no"), ("gapless-audio", "yes")):
            try: player[k] = v
            except Exception: pass
    except Exception as e:
        player = None
        log("mpv not available (%r): the list works, playback does not." % e)

PS = {"queue": [], "orig": [], "qpos": -1, "status": "Stopped", "pos": 0.0, "dur": 0.0, "loaded": False, "ended": False}
_mp = {"loop": None, "player": None, "ok": False, "hold": False, "claimed": False, "bus": None}

def cur_track():
    q, i = PS["queue"], PS["qpos"]
    if 0 <= i < len(q): return _by_id().get(q[i])
    return None

def _ctx_tracks(ctx):
    """Track list of a context: all | album:<akey> | artist:<name> | playlist:<id> | likes | search:<text>"""
    tr = all_tracks()
    kind, _, arg = (ctx or "all").partition(":")
    if kind == "album": return sorted([t for t in tr if t["akey"] == arg], key=_album_sort)
    if kind == "artist": return sorted([t for t in tr if (t.get("albumartist") or t["artist"]).lower() == arg.lower() or t["artist"].lower() == arg.lower()], key=_album_sort)
    if kind == "src":                                            # src:pc (cartella Musica) | src:usb (chiavette)
        ids = _kind_ids(arg)
        return sorted([t for t in tr if t["src"] in ids], key=lambda t: t["title"].lower())
    if kind == "likes":
        idx = {t["id"]: t for t in tr}
        return [idx[i] for i in CFG["likes"] if i in idx]
    if kind == "playlist":
        idx = {t["id"]: t for t in tr}
        for p in CFG["playlists"]:
            if p["id"] == arg: return [idx[i] for i in p["tracks"] if i in idx]
        return []
    if kind == "search":
        q = arg.lower()
        return sorted([t for t in tr if q in t["title"].lower() or q in t["artist"].lower() or q in t["album"].lower()], key=lambda t: t["title"].lower())
    return sorted(tr, key=lambda t: t["title"].lower())

def _shuffle_rest(keep_first=True):
    q = PS["queue"]
    if not q: return
    i = PS["qpos"]
    head = q[:i + 1] if keep_first and i >= 0 else []
    rest = q[i + 1:] if keep_first and i >= 0 else q[:]
    random.shuffle(rest)
    PS["queue"] = head + rest

def play_track(tid, queue=None):
    if not player: return False
    t = _by_id().get(tid)
    if not t or not os.path.exists(t["path"]): return False
    with _lk:
        if queue is not None:
            PS["orig"] = list(queue)
            PS["queue"] = list(queue)
            PS["qpos"] = PS["queue"].index(tid) if tid in PS["queue"] else 0
            if CFG["shuffle"]: _shuffle_rest()
        else:
            PS["qpos"] = PS["queue"].index(tid) if tid in PS["queue"] else PS["qpos"]
        PS.update(pos=0.0, dur=float(t.get("dur") or 0), status="Playing", loaded=False, ended=False, t0=time.time())
        try:
            player.pause = False
            player.loop_file = "inf" if CFG["repeat"] == "one" else "no"
            player.play(t["path"])
        except Exception as e:
            log("playback did not start:", repr(e)[:100]); PS["status"] = "Stopped"; return False
        _mpris_claim(); _mpris_push(full=True)
    return True

def toggle(want=None):
    if not player or cur_track() is None: return False
    with _lk:
        playing = PS["status"] == "Playing"
        if want is None: want = not playing
        if want and PS["ended"]:
            PS["ended"] = False; return play_track(PS["queue"][PS["qpos"]])
        try: player.pause = not want
        except Exception: return False
        PS["status"] = "Playing" if want else "Paused"
        _mpris_push()
    return True

def seek_abs(pos):
    if not player or cur_track() is None: return
    d = PS["dur"] or 0
    pos = max(0.0, float(pos))
    if d: pos = min(pos, max(0.0, d - 0.5))
    try: player.seek(pos, reference="absolute")
    except Exception as e: log("seek:", repr(e)[:60]); return
    PS["pos"] = pos; _mpris_seeked()

def go_next(auto=False):
    with _lk:
        q, i = PS["queue"], PS["qpos"]
        if not q: return False
        if not auto and CFG["repeat"] == "one":           # with "repeat one" next/previous restart the same song
            seek_abs(0)
            if PS["status"] != "Playing": toggle(True)
            return True
        j = i + 1
        if j >= len(q):
            if CFG["repeat"] == "all": j = 0
            else:
                if auto: PS["status"] = "Stopped"; PS["ended"] = True; _mpris_push()
                return False
        return play_track(q[j])

def go_prev():
    with _lk:
        q, i = PS["queue"], PS["qpos"]
        if not q: return False
        if PS["pos"] > 3 or CFG["repeat"] == "one" or i <= 0:
            seek_abs(0); return True
        return play_track(q[i - 1])

def set_shuffle(on):
    with _lk:
        CFG["shuffle"] = bool(on); save_cfg()
        cur = PS["queue"][PS["qpos"]] if 0 <= PS["qpos"] < len(PS["queue"]) else None
        if on: _shuffle_rest()
        else:                                                     # original order, staying on the playing track
            PS["queue"] = list(PS["orig"]) or PS["queue"]
            PS["qpos"] = PS["queue"].index(cur) if cur in PS["queue"] else PS["qpos"]
        _mpris_push()

def set_repeat(mode):
    if mode not in ("off", "all", "one"): mode = "off"
    CFG["repeat"] = mode; save_cfg()
    if player:
        try: player.loop_file = "inf" if mode == "one" else "no"
        except Exception: pass
    _mpris_push()

def _tick():
    if not player or cur_track() is None: return
    with _lk:
        try: tp = player.time_pos; du = player.duration; paused = bool(player.pause); eof = bool(player.eof_reached)
        except Exception: return
        if tp is not None: PS["loaded"] = True; PS["pos"] = float(tp)
        if du and abs(float(du) - PS["dur"]) > 1: PS["dur"] = float(du); _mpris_push(full=True)
        if eof and PS["status"] == "Playing" and time.time() - PS.get("t0", 0) > 1.5:     # right after a new start mpv still reports the end of the previous track
            if not go_next(auto=True): PS["status"] = "Stopped"; PS["ended"] = True; _mpris_push()
            return
        if PS["loaded"] and not eof and not _mp["hold"]:
            st = "Paused" if paused else "Playing"
            if st != PS["status"] and PS["status"] in ("Playing", "Paused"): PS["status"] = st; _mpris_push()

def _ticker():
    while True:
        try: _tick()
        except Exception as e: log("tick:", repr(e)[:80])
        time.sleep(0.5)

# ═════════════════════════ System player (MPRIS) ═════════════════════════
def _meta():
    t = cur_track()
    if not t: return {}
    from dbus_next import Variant
    m = {"mpris:trackid": Variant("o", "/org/volta/musica/t" + t["id"]), "xesam:title": Variant("s", t["title"]),
         "xesam:artist": Variant("as", [t["artist"] or ""]), "xesam:album": Variant("s", t["album"] or ""),
         "mpris:artUrl": Variant("s", "http://127.0.0.1:%d/cover/%s.jpg" % (PORT, t["akey"]))}
    d = PS["dur"] or t.get("dur") or 0
    if d: m["mpris:length"] = Variant("x", int(d * 1e6))
    return m

def _pb(): return "Paused" if (_mp["hold"] and PS["status"] == "Playing") else PS["status"]
def _loop_status(): return {"one": "Track", "all": "Playlist"}.get(CFG["repeat"], "None")

def _mpris_push(full=False):
    if not _mp["ok"]: return
    def apply():
        try:
            has = cur_track() is not None
            ch = {"PlaybackStatus": _pb(), "CanGoNext": has, "CanGoPrevious": has, "CanPlay": has, "CanPause": has, "CanSeek": has,
                  "LoopStatus": _loop_status(), "Shuffle": bool(CFG["shuffle"])}
            if full: ch["Metadata"] = _meta()
            _mp["player"].emit_properties_changed(ch)
        except Exception as e: log("mpris:", repr(e)[:80])
    try: _mp["loop"].call_soon_threadsafe(apply)
    except Exception: pass

def _mpris_seeked():
    if not _mp["ok"]: return
    def apply():
        try: _mp["player"].Seeked(int(PS["pos"] * 1e6))
        except Exception: pass
    try: _mp["loop"].call_soon_threadsafe(apply)
    except Exception: pass

def _mpris_claim():
    """On first playback announces the player to the system. Starts 1 s paused: the system player considers
    'just started' only whoever changes state, so the mini player shows it and the other music is paused."""
    if not _mp["ok"] or _mp["claimed"]: return
    _mp["claimed"] = True; _mp["hold"] = True
    try: player.pause = True
    except Exception: pass
    import asyncio
    async def go():
        try: await _mp["bus"].request_name(MPRIS_NAME)
        except Exception as e:
            _mp["claimed"] = False; _mp["hold"] = False; log("MPRIS: name not obtained:", repr(e)[:80])
            try:
                if PS["status"] == "Playing": player.pause = False
            except Exception: pass
            return
        await asyncio.sleep(1.0)
        _mp["hold"] = False
        try:
            if PS["status"] == "Playing": player.pause = False
        except Exception: pass
        _mpris_push(full=True)
    try: asyncio.run_coroutine_threadsafe(go(), _mp["loop"])
    except Exception as e: _mp["claimed"] = False; log("MPRIS:", repr(e)[:80])

def start_mpris():
    def run():
        import asyncio
        try:
            from dbus_next.aio import MessageBus
            from dbus_next.service import ServiceInterface, method, dbus_property, signal
            from dbus_next.constants import PropertyAccess
        except Exception as e:
            log("dbus-next missing (%r): the mini player will not see the music." % e); return
        def bg(fn, *a): threading.Thread(target=fn, args=a, daemon=True).start()

        class Root(ServiceInterface):
            def __init__(self): super().__init__("org.mpris.MediaPlayer2")
            @method()
            def Raise(self): pass
            @method()
            def Quit(self): pass
            @dbus_property(access=PropertyAccess.READ)
            def CanQuit(self) -> "b": return False
            @dbus_property(access=PropertyAccess.READ)
            def CanRaise(self) -> "b": return False
            @dbus_property(access=PropertyAccess.READ)
            def HasTrackList(self) -> "b": return False
            @dbus_property(access=PropertyAccess.READ)
            def Identity(self) -> "s": return "Musica"
            @dbus_property(access=PropertyAccess.READ)
            def SupportedUriSchemes(self) -> "as": return []
            @dbus_property(access=PropertyAccess.READ)
            def SupportedMimeTypes(self) -> "as": return []

        class Player(ServiceInterface):
            def __init__(self): super().__init__("org.mpris.MediaPlayer2.Player")
            @method()
            def Next(self): bg(go_next)
            @method()
            def Previous(self): bg(go_prev)
            @method()
            def Pause(self): bg(toggle, False)
            @method()
            def PlayPause(self): bg(toggle, None)
            @method()
            def Stop(self): bg(toggle, False)
            @method()
            def Play(self): bg(toggle, True)
            @method()
            def Seek(self, offset: "x"): bg(lambda: seek_abs(PS["pos"] + offset / 1e6))
            @method()
            def SetPosition(self, track_id: "o", position: "x"): bg(seek_abs, position / 1e6)
            @method()
            def OpenUri(self, uri: "s"): pass
            @signal()
            def Seeked(self) -> "x": return int(PS["pos"] * 1e6)
            @dbus_property(access=PropertyAccess.READ)
            def PlaybackStatus(self) -> "s": return _pb()
            @dbus_property(access=PropertyAccess.READ)
            def LoopStatus(self) -> "s": return _loop_status()
            @dbus_property(access=PropertyAccess.READ)
            def Shuffle(self) -> "b": return bool(CFG["shuffle"])
            @dbus_property(access=PropertyAccess.READ)
            def Rate(self) -> "d": return 1.0
            @dbus_property(access=PropertyAccess.READ)
            def Metadata(self) -> "a{sv}": return _meta()
            @dbus_property(access=PropertyAccess.READ)
            def Volume(self) -> "d": return 1.0
            @dbus_property(access=PropertyAccess.READ)
            def Position(self) -> "x": return int(PS["pos"] * 1e6)
            @dbus_property(access=PropertyAccess.READ)
            def MinimumRate(self) -> "d": return 1.0
            @dbus_property(access=PropertyAccess.READ)
            def MaximumRate(self) -> "d": return 1.0
            @dbus_property(access=PropertyAccess.READ)
            def CanGoNext(self) -> "b": return cur_track() is not None
            @dbus_property(access=PropertyAccess.READ)
            def CanGoPrevious(self) -> "b": return cur_track() is not None
            @dbus_property(access=PropertyAccess.READ)
            def CanPlay(self) -> "b": return cur_track() is not None
            @dbus_property(access=PropertyAccess.READ)
            def CanPause(self) -> "b": return cur_track() is not None
            @dbus_property(access=PropertyAccess.READ)
            def CanSeek(self) -> "b": return cur_track() is not None
            @dbus_property(access=PropertyAccess.READ)
            def CanControl(self) -> "b": return True

        async def main():
            bus = await MessageBus().connect()
            r, p = Root(), Player()
            bus.export("/org/mpris/MediaPlayer2", r); bus.export("/org/mpris/MediaPlayer2", p)
            _mp.update(loop=asyncio.get_running_loop(), player=p, bus=bus, ok=True, claimed=False)
            log("MPRIS pronto (il nome sul bus viene preso alla prima riproduzione)")
            await bus.wait_for_disconnect()
        try: asyncio.run(main())
        except Exception as e: log("MPRIS not active:", repr(e)[:100]); _mp["ok"] = False
    threading.Thread(target=run, daemon=True).start()

# ═════════════════════════ API ═════════════════════════
@app.route("/health")
def health(): return jsonify({"ok": True, "mpv": player is not None, "mpris": _mp["ok"], "tracks": len(all_tracks())})

@app.route("/sources")
def sources_route():
    cnt = {}
    for t in all_tracks(): cnt[t["src"]] = cnt.get(t["src"], 0) + 1
    out = [dict(s, tracks=cnt.get(s["id"], 0)) for s in sources()]
    return jsonify({"sources": out, "scan": SCAN, "music_dir": _music_dir()})

@app.route("/scan")
def scan_route():
    scan_all(); return jsonify({"ok": True, "scan": SCAN})

@app.route("/tracks")
def tracks_route():
    q = (freq.args.get("q") or "").strip().lower()
    tr = all_tracks()
    if freq.args.get("src"): tr = [t for t in tr if t["src"] == freq.args["src"]]
    if freq.args.get("kind") in ("pc", "usb"):
        ids = _kind_ids(freq.args["kind"]); tr = [t for t in tr if t["src"] in ids]
    if q: tr = [t for t in tr if q in t["title"].lower() or q in t["artist"].lower() or q in t["album"].lower()]
    tr.sort(key=lambda t: (t["title"].lower(), t["artist"].lower()))
    off = max(0, int(freq.args.get("offset", 0) or 0)); lim = max(1, min(int(freq.args.get("limit", 500) or 500), 2000))
    return jsonify({"total": len(tr), "tracks": [pub(t) for t in tr[off:off + lim]]})

@app.route("/albums")
def albums_route():
    q = (freq.args.get("q") or "").strip().lower()
    al = {}
    for t in all_tracks():
        a = al.setdefault(t["akey"], {"key": t["akey"], "album": t["album"], "artist": t.get("albumartist") or t["artist"], "year": t.get("year", ""), "count": 0, "dur": 0})
        a["count"] += 1; a["dur"] += t.get("dur", 0)
        if not a["year"]: a["year"] = t.get("year", "")
    out = [a for a in al.values() if not q or q in a["album"].lower() or q in a["artist"].lower()]
    out.sort(key=lambda a: (a["artist"].lower(), a["album"].lower()))
    return jsonify({"albums": out})

@app.route("/artists")
def artists_route():
    q = (freq.args.get("q") or "").strip().lower()
    ar = {}
    for t in all_tracks():
        n = (t.get("albumartist") or t["artist"] or "Sconosciuto")
        a = ar.setdefault(n.lower(), {"name": n, "count": 0, "albums": set(), "akey": t["akey"]})
        a["count"] += 1; a["albums"].add(t["akey"])
    out = [{"name": a["name"], "count": a["count"], "albums": len(a["albums"]), "akey": a["akey"]} for a in ar.values() if not q or q in a["name"].lower()]
    out.sort(key=lambda a: a["name"].lower())
    return jsonify({"artists": out})

@app.route("/ctx")
def ctx_route():
    """Tracks of an album / artist / playlist / Liked."""
    return jsonify({"tracks": [pub(t) for t in _ctx_tracks(freq.args.get("ctx", "all"))]})

@app.route("/search")
def search_route():
    q = (freq.args.get("q") or "").strip().lower()
    if len(q) < 1: return jsonify({"tracks": [], "albums": [], "artists": []})
    tr = [t for t in all_tracks() if q in t["title"].lower() or q in t["artist"].lower() or q in t["album"].lower()]
    tr.sort(key=lambda t: (not t["title"].lower().startswith(q), t["title"].lower()))
    albums = albums_route().get_json()["albums"]; artists = artists_route().get_json()["artists"]
    return jsonify({"tracks": [pub(t) for t in tr[:60]], "albums": [a for a in albums if q in a["album"].lower() or q in a["artist"].lower()][:20],
                    "artists": [a for a in artists if q in a["name"].lower()][:20]})

@app.route("/cover/<akey>.jpg")
def cover_route(akey):
    if not re.fullmatch(r"[0-9a-f]{12}", akey): return Response(status=404)
    data = cover_bytes(akey)
    if data is None: return Response(status=404)
    return Response(data, mimetype="image/jpeg", headers={"Cache-Control": "public, max-age=86400"})

# ── preferiti e playlist ──
@app.route("/like")
def like_route():
    tid = freq.args.get("id", "")
    if tid in CFG["likes"]: CFG["likes"].remove(tid); on = False
    else: CFG["likes"].insert(0, tid); on = True
    save_cfg(); return jsonify({"ok": True, "like": on})

@app.route("/playlists")
def playlists_route():
    idx = _by_id(); ok = present_ids()
    def alive(ids): return [i for i in ids if i in idx and idx[i].get("src") in ok]
    def ak(ids):
        a = alive(ids); return idx[a[0]]["akey"] if a else ""
    return jsonify({"playlists": [{"id": p["id"], "name": p["name"], "count": len(alive(p["tracks"])), "akey": ak(p["tracks"])} for p in CFG["playlists"]],
                    "likes": len(alive(CFG["likes"])), "likes_akey": ak(CFG["likes"])})

@app.route("/playlists/create")
def pl_create():
    name = (freq.args.get("name") or "").strip()[:60]
    if not name: return jsonify({"ok": False}), 400
    p = {"id": _md5(name + str(time.time()))[:8], "name": name, "tracks": []}
    CFG["playlists"].append(p); save_cfg(); return jsonify({"ok": True, "id": p["id"]})

@app.route("/playlists/add")
def pl_add():
    for p in CFG["playlists"]:
        if p["id"] == freq.args.get("id"):
            tid = freq.args.get("track", "")
            if tid and tid not in p["tracks"]: p["tracks"].append(tid)
            save_cfg(); return jsonify({"ok": True})
    return jsonify({"ok": False}), 404

@app.route("/playlists/remove")
def pl_remove():
    for p in CFG["playlists"]:
        if p["id"] == freq.args.get("id") and freq.args.get("track") in p["tracks"]:
            p["tracks"].remove(freq.args["track"]); save_cfg(); return jsonify({"ok": True})
    return jsonify({"ok": False}), 404

@app.route("/playlists/delete")
def pl_delete():
    CFG["playlists"] = [p for p in CFG["playlists"] if p["id"] != freq.args.get("id")]; save_cfg(); return jsonify({"ok": True})

# ── player ──
@app.route("/play")
def play_route():
    tid = freq.args.get("id", ""); ctx = freq.args.get("ctx", "all")
    if not player: return jsonify({"ok": False, "error": "mpv not available"}), 503
    q = [t["id"] for t in _ctx_tracks(ctx)] if ctx != "single" else [tid]
    if tid not in q:
        q = [tid]
    ok = play_track(tid, queue=q)
    return jsonify({"ok": ok})

@app.route("/play_all")
def play_all_route():
    """Plays a context from the start; with shuffle=1 it starts from a random track."""
    ctx = freq.args.get("ctx", "all"); tr = _ctx_tracks(ctx)
    if not tr: return jsonify({"ok": False}), 404
    if freq.args.get("shuffle") == "1": set_shuffle(True); first = random.choice(tr)
    else: first = tr[0]
    return jsonify({"ok": play_track(first["id"], queue=[t["id"] for t in tr])})

@app.route("/player/pause")
def pause_route():
    st = freq.args.get("state")
    toggle(None if st is None else (st != "1")); return jsonify({"ok": True})

@app.route("/player/next")
def next_route(): return jsonify({"ok": go_next()})
@app.route("/player/prev")
def prev_route(): return jsonify({"ok": go_prev()})

@app.route("/player/seek")
def seek_route():
    try:
        pct = max(0.0, min(float(freq.args.get("pct", 0)), 1.0))
        if PS["dur"]: seek_abs(pct * PS["dur"])
    except ValueError: pass
    return jsonify({"ok": True})

@app.route("/player/shuffle")
def shuffle_route():
    st = freq.args.get("state"); set_shuffle((not CFG["shuffle"]) if st is None else st == "1")
    return jsonify({"ok": True, "shuffle": CFG["shuffle"], "repeat": CFG["repeat"]})

@app.route("/player/repeat")
def repeat_route():
    m = freq.args.get("mode")
    if m not in ("off", "all", "one"): m = {"off": "one", "one": "all"}.get(CFG["repeat"], "off")
    set_repeat(m); return jsonify({"ok": True, "shuffle": CFG["shuffle"], "repeat": CFG["repeat"]})

@app.route("/player/enqueue")
def enqueue_route():
    tid = freq.args.get("id", "")
    if tid not in _by_id(): return jsonify({"ok": False}), 404
    with _lk:
        if not PS["queue"]: return jsonify({"ok": play_track(tid, queue=[tid])})
        at = PS["qpos"] + 1 if freq.args.get("next") == "1" else len(PS["queue"])
        PS["queue"].insert(at, tid); PS["orig"].append(tid)
    return jsonify({"ok": True})

@app.route("/player/jump")
def jump_route():
    """Jumps to a point of the queue (pos = index)."""
    try: i = int(freq.args.get("pos", "-1"))
    except ValueError: i = -1
    with _lk:
        if not (0 <= i < len(PS["queue"])): return jsonify({"ok": False}), 404
        return jsonify({"ok": play_track(PS["queue"][i])})

@app.route("/player/queue")
def queue_route():
    idx = _by_id(); q = PS["queue"]; i = PS["qpos"]
    return jsonify({"pos": i, "queue": [pub(idx[x]) for x in q if x in idx]})

@app.route("/player/status")
def status_route():
    t = cur_track()
    return jsonify({"track": pub(t) if t else None, "is_playing": PS["status"] == "Playing", "progress_ms": int(PS["pos"] * 1000),
                    "duration_ms": int((PS["dur"] or (t or {}).get("dur", 0) or 0) * 1000), "shuffle": CFG["shuffle"], "repeat": CFG["repeat"],
                    "qpos": PS["qpos"], "queue_len": len(PS["queue"]), "scan": SCAN})

def main():
    load_cfg(); load_index(); init_mpv(); start_mpris()
    threading.Thread(target=_ticker, daemon=True).start()
    threading.Thread(target=_watch_usb, daemon=True).start()
    scan_all()
    app.run(host="127.0.0.1", port=PORT, threaded=True)

if __name__ == "__main__":
    main()
