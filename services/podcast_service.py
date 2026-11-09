#!/usr/bin/env python3
# podcast_service.py — Podcast app: iTunes search, RSS feeds, subscriptions, playback (mpv) and system player (MPRIS)
#
# Port 8094 (127.0.0.1 only). No account: podcasts are public RSS feeds; the catalog (search,
# charts, categories) comes from the public iTunes APIs. Data saved in ~/.config/volta/podcast.json.
#
# Dependencies: flask, requests (already present), python-mpv (already used by YT Music), dbus-next (already used by the phone).
import os, sys, re, json, time, html, hashlib, threading, tempfile
from collections import deque
from concurrent.futures import ThreadPoolExecutor, wait as _fwait
from email.utils import parsedate_to_datetime
from xml.etree import ElementTree as ET

from flask import Flask, jsonify, request as freq

PORT      = int(os.environ.get("PODCAST_PORT", "8094"))
DATA_PATH = os.environ.get("PODCAST_DATA", os.path.expanduser("~/.config/volta/podcast.json"))
COUNTRY   = os.environ.get("PODCAST_COUNTRY") or {"it": "it", "en": "us", "es": "es", "fr": "fr", "pt": "pt"}.get(os.environ.get("VOLTA_LANG", "en"), "us")
UA        = "VoltaPodcast/1.0 (+car infotainment)"
app = Flask(__name__)
from local_security import protect
protect(app)

def log(*a): print("[podcast]", *a, file=sys.stderr, flush=True)

# ════════════════════════ Rete ════════════════════════
def http_get(url, timeout=(5, 15), max_bytes=20 * 1024 * 1024):
    """Downloads an address. Single function: the tests replace it."""
    try:
        import requests
    except ImportError:
        requests = None
    if requests is None:                      # without requests: standard library urllib
        import urllib.request
        rq = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
        with urllib.request.urlopen(rq, timeout=timeout[1]) as r:
            return r.read(max_bytes)
    r = requests.get(url, headers={"User-Agent": UA, "Accept": "*/*"}, timeout=timeout, stream=True)
    r.raise_for_status()
    buf = bytearray()
    for chunk in r.iter_content(65536):
        buf += chunk
        if len(buf) > max_bytes: break
    r.close()
    return bytes(buf)

# iTunes: about 20 requests per minute per address, BUT only for search and lookup (itunes.apple.com/search|lookup).
# The charts (…/rss/… and rss.marketingtools.apple.com) are static files and have no such limit.
# We make at most 16 per minute, wait a few seconds if needed, and cache everything.
class RateLimited(Exception): pass
_itunes_calls = deque()
_itunes_lock = threading.Lock()
ITUNES_PER_MIN = 16
SLOT_WAIT = float(os.environ.get("PODCAST_SLOT_WAIT", "8"))

def _itunes_slot(wait=None):
    deadline = time.time() + (SLOT_WAIT if wait is None else wait)
    while True:
        with _itunes_lock:
            now = time.time()
            while _itunes_calls and now - _itunes_calls[0] > 60: _itunes_calls.popleft()
            if len(_itunes_calls) < ITUNES_PER_MIN:
                _itunes_calls.append(now); return
            free_in = 60 - (now - _itunes_calls[0]) + 0.05
        if time.time() + free_in > deadline: raise RateLimited()
        time.sleep(min(free_in, 1.0))

def _limited_url(url):
    return "itunes.apple.com/search" in url or "itunes.apple.com/lookup" in url

_cache = {}
_cache_lock = threading.Lock()
def cached(key, ttl, fn, stale_ok=True):
    """Cached result; if the network fails and an old copy exists, it uses that."""
    now = time.time()
    with _cache_lock:
        hit = _cache.get(key)
    if hit and now - hit[0] < ttl: return hit[1]
    try:
        val = fn()
    except Exception as e:
        if stale_ok and hit:
            log("network not available for", key[:60], "-> copia vecchia:", repr(e)[:80])
            return hit[1]
        raise
    with _cache_lock:
        _cache[key] = (now, val)
    return val

def itunes_json(url):
    if _limited_url(url): _itunes_slot()
    return json.loads(http_get(url, timeout=(5, 12)).decode("utf-8", "replace"))

def _q(s):
    from urllib.parse import quote
    return quote(str(s), safe="")

# ════════════════════════ Categorie (generi Apple Podcasts) ════════════════════════
GENRES = [
    {"id": "1303", "name": "Commedia"},          {"id": "1488", "name": "True crime"},
    {"id": "1311", "name": "Notizie"},           {"id": "1487", "name": "Storia"},
    {"id": "1324", "name": "Society & Culture"}, {"id": "1321", "name": "Business"},
    {"id": "1318", "name": "Tecnologia"},        {"id": "1315", "name": "Scienza"},
    {"id": "1316", "name": "Sport"},             {"id": "1307", "name": "Salute e benessere"},
    {"id": "1304", "name": "Istruzione"},        {"id": "1301", "name": "Arte"},
    {"id": "1310", "name": "Musica"},            {"id": "1309", "name": "TV e cinema"},
    {"id": "1483", "name": "Narrativa"},         {"id": "1305", "name": "Bambini e famiglia"},
    {"id": "1502", "name": "Tempo libero"},      {"id": "1325", "name": "Governo"},
]
GENRE_NAME = {g["id"]: g["name"] for g in GENRES}
_COL = ["#F59E0B", "#14B8A6", "#3B34E0", "#F97316", "#E11D74", "#16A34A", "#0EA5E9", "#9333EA", "#DC2626", "#0D9488",
        "#CA8A04", "#7C3AED", "#2563EB", "#DB2777", "#059669", "#EA580C", "#4F46E5", "#B45309", "#475569"]
for _i, _g in enumerate(GENRES): _g["color"] = _COL[_i % len(_COL)]

def _art(url):
    """Copertina piu' grande (iTunes: ...100x100bb.jpg -> 600x600bb)."""
    if not url: return ""
    return re.sub(r"/(\d+)x(\d+)(bb|-\d+)?\.(jpg|png|webp)$", r"/600x600bb.\4", url) if "mzstatic" in url else url

def _item_from_lookup(r):
    return {
        "id": str(r.get("collectionId") or r.get("trackId") or ""),
        "title": r.get("collectionName") or r.get("trackName") or "",
        "author": r.get("artistName") or "",
        "cover": r.get("artworkUrl600") or _art(r.get("artworkUrl100") or ""),
        "feed": r.get("feedUrl") or "",
        "genre": r.get("primaryGenreName") or "",
        "count": r.get("trackCount") or 0,
    }

def itunes_lookup(ids):
    ids = [str(i) for i in ids if i]
    if not ids: return {}
    out = {}
    for i in range(0, len(ids), 40):
        chunk = ids[i:i + 40]
        url = "https://itunes.apple.com/lookup?id=%s&entity=podcast&country=%s" % (",".join(chunk), COUNTRY)
        d = cached("lk:" + ",".join(chunk), 86400, lambda u=url: itunes_json(u))
        for r in d.get("results", []):
            if r.get("wrapperType") in ("track", None) or r.get("kind") == "podcast" or r.get("feedUrl"):
                it = _item_from_lookup(r)
                if it["id"]: out[it["id"]] = it
    return out

def search_podcasts(term, limit=25):
    url = "https://itunes.apple.com/search?media=podcast&entity=podcast&country=%s&limit=%d&term=%s" % (COUNTRY, limit, _q(term))
    d = cached("sp:" + term.lower(), 3600, lambda: itunes_json(url))
    return [it for it in (_item_from_lookup(r) for r in d.get("results", [])) if it["id"] and it["feed"]]

def _ep_from_itunes(r):
    audio = r.get("episodeUrl") or ""
    if not audio: return None
    ts = _iso_to_ts(r.get("releaseDate"))
    return {
        "guid": r.get("episodeGuid") or audio, "title": r.get("trackName") or "",
        "podcast": r.get("collectionName") or "", "feed": r.get("feedUrl") or "",
        "cover": r.get("artworkUrl600") or _art(r.get("artworkUrl160") or r.get("artworkUrl100") or ""),
        "audio": audio, "dur": int((r.get("trackTimeMillis") or 0) / 1000),
        "date": ts, "dateLabel": _fmt_date(ts),
        "desc": _clean(r.get("description") or r.get("shortDescription") or "", 400),
        "trackId": str(r.get("trackId") or ""),
    }

def search_episodes(term, limit=12):
    url = "https://itunes.apple.com/search?media=podcast&entity=podcastEpisode&country=%s&limit=%d&term=%s" % (COUNTRY, limit, _q(term))
    d = cached("se:" + term.lower(), 3600, lambda: itunes_json(url))
    return [e for e in (_ep_from_itunes(r) for r in d.get("results", [])) if e]

def top_episodes(genre="", limit=12):
    """Episodes in the chart. First Apple's episode chart; if it does not answer,
    the latest episode of each podcast in the chart."""
    def go():
        try:
            if genre: raise ValueError("Apple episode chart: general only")
            d = itunes_json("https://rss.marketingtools.apple.com/api/v2/%s/podcasts/top/%d/podcast-episodes.json" % (COUNTRY, limit))
            ids = [str(r["id"]) for r in d["feed"]["results"]]
            lk = itunes_json("https://itunes.apple.com/lookup?id=%s&entity=podcastEpisode&country=%s" % (",".join(ids), COUNTRY))
            byid = {}
            for r in lk.get("results", []):
                e = _ep_from_itunes(r)
                if e: byid[e["trackId"]] = e
            out = [byid[i] for i in ids if i in byid]
            if out: return out
        except ValueError: pass
        except Exception as e:
            log("Apple episode chart not available:", repr(e)[:80])
        shows = with_feeds(charts(genre)[:limit])
        pool = ThreadPoolExecutor(max_workers=6)
        futs = [pool.submit(get_feed, s["feed"]) for s in shows]
        _fwait(futs, timeout=25); pool.shutdown(wait=False)
        out = []
        for s, f in zip(shows, futs):
            try:
                info = f.result(timeout=0); e = info["episodes"][0]
            except Exception: continue
            out.append(dict(e, feed=s["feed"], podcast=info["title"], cover=e.get("cover") or info["cover"]))
        if not out: raise RuntimeError("no episodes in the chart")
        if genre: out.sort(key=lambda e: e.get("date", 0), reverse=True)      # in category: most recent first
        return out
    return cached("te:%s:%d" % (genre, limit), 3 * 3600, go)

def _parse_chart(d):
    """Accepts both the old format (feed.entry) and the new one (feed.results)."""
    feed = d.get("feed", {}) if isinstance(d, dict) else {}
    out = []
    ent = feed.get("entry")
    if isinstance(ent, dict): ent = [ent]
    for e in ent or []:
        try:
            pid = e["id"]["attributes"]["im:id"]
            imgs = e.get("im:image") or []
            cover = _art(imgs[-1]["label"]) if imgs else ""
            out.append({"id": str(pid), "title": e["im:name"]["label"], "author": (e.get("im:artist") or {}).get("label", ""), "cover": cover})
        except Exception:
            continue
    for r in feed.get("results") or []:
        try:
            out.append({"id": str(r["id"]), "title": r.get("name", ""), "author": r.get("artistName", ""),
                        "cover": _art(r.get("artworkUrl100", "")), "genreIds": [g.get("genreId") for g in r.get("genres", [])]})
        except Exception:
            continue
    return out

def with_feeds(shows):
    """Completes the feed address (a single lookup for all)."""
    miss = [s["id"] for s in shows if not s.get("feed") and s.get("id")]
    full = itunes_lookup(miss) if miss else {}
    out = []
    for s in shows:
        if not s.get("feed"):
            f = full.get(s.get("id"))
            if not f or not f["feed"]: continue
            s = dict(s, feed=f["feed"], genre=f["genre"], count=f["count"], cover=s.get("cover") or f["cover"])
        out.append(s)
    return out

def _mt_top(n):
    return cached("mt:%d" % n, 3600, lambda: _parse_chart(itunes_json("https://rss.marketingtools.apple.com/api/v2/%s/podcasts/top/%d/podcasts.json" % (COUNTRY, n))))

def charts(genre="", limit=50, fill_search=True):
    """Italy chart (optional: per category). Several sources are merged, so that even the less popular
    categories have a full list: 1) Apple's per-category chart, 2) general chart
    (200 places) filtered by category, 3) search by category name."""
    genre = genre if genre in GENRE_NAME else ""
    def go():
        errs = []
        items, seen = [], set()
        def add(lst):
            for i in lst:
                if i["id"] and i["id"] not in seen:
                    seen.add(i["id"]); items.append(i)
        try:
            u = "https://itunes.apple.com/%s/rss/toppodcasts/limit=%d%s/json" % (COUNTRY, limit, ("/genre=" + genre) if genre else "")
            add(_parse_chart(itunes_json(u)))
        except Exception as e: errs.append(repr(e)[:80])
        if len(items) < 25:
            try:
                lst = list(_mt_top(200 if genre else limit))
                if genre: lst = [i for i in lst if genre in [str(g) for g in i.get("genreIds", [])]]
                add(lst)
            except Exception as e: errs.append(repr(e)[:80])
        # No lookup here: the charts do not count toward Apple's limit. The feed address
        # is only worked out when the podcast is opened (/podcast?id=...) or really needed (with_feeds).
        res = [{"id": i["id"], "title": i["title"], "author": i["author"], "cover": i["cover"], "feed": "", "genre": "", "count": 0}
               for i in items[:limit]]
        if len(res) < 20 and fill_search:
            try:
                have = set(r["id"] for r in res)
                for f in search_podcasts(GENRE_NAME.get(genre, "podcast"), 50):
                    if f["id"] not in have: have.add(f["id"]); res.append(f)
            except Exception as e: errs.append(repr(e)[:80])
        if not res: raise RuntimeError("chart not available: " + "; ".join(errs))
        return res
    return cached("ch:%s:%d%s" % (genre, limit, "" if fill_search else ":s"), 6 * 3600, go)

# ════════════════════════ Feed RSS ════════════════════════
NS = {"itunes": "http://www.itunes.com/dtds/podcast-1.0.dtd", "content": "http://purl.org/rss/1.0/modules/content/",
      "media": "http://search.yahoo.com/mrss/", "pod": "https://podcastindex.org/namespace/1.0"}
MESI = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]

def _clean(s, maxlen=0):
    if not s: return ""
    s = re.sub(r"(?is)<(script|style).*?</\1>", " ", s)
    s = re.sub(r"(?i)<br\s*/?>|</p>|</li>", "\n", s)
    s = re.sub(r"<[^>]+>", " ", s)
    s = html.unescape(s)
    s = re.sub(r"[ \t\r\f\v]+", " ", s)
    s = re.sub(r"\n\s*\n+", "\n", s).strip()
    if maxlen and len(s) > maxlen: s = s[:maxlen].rsplit(" ", 1)[0] + "…"
    return s

def _dur(s):
    if not s: return 0
    s = s.strip()
    try:
        if ":" in s:
            p = [float(x) for x in s.split(":")][-3:]
            sec = 0
            for x in p: sec = sec * 60 + x
            return int(sec)
        return int(float(s))
    except Exception:
        return 0

def _date_ts(s):
    if not s: return 0
    try: return int(parsedate_to_datetime(s.strip()).timestamp())
    except Exception: pass
    return _iso_to_ts(s)

def _iso_to_ts(s):
    if not s: return 0
    try:
        from datetime import datetime, timezone
        return int(datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp())
    except Exception:
        return 0

def _fmt_date(ts):
    if not ts: return ""
    t = time.localtime(ts)
    return "%d %s %d" % (t.tm_mday, MESI[t.tm_mon - 1], t.tm_year)

def _txt(el, path):
    x = el.find(path, NS)
    return (x.text or "").strip() if x is not None and x.text else ""

def _img(el):
    x = el.find("itunes:image", NS)
    if x is not None and x.get("href"): return x.get("href")
    x = el.find("image/url")
    if x is not None and x.text: return x.text.strip()
    x = el.find("media:thumbnail", NS)
    if x is not None and x.get("url"): return x.get("url")
    return ""

def _persons(el):
    """<podcast:person role="host|guest" img="..." href="...">Nome</podcast:person>"""
    out = []
    for p in el.findall("pod:person", NS):
        name = (p.text or "").strip()
        if not name: continue
        role = (p.get("role") or "host").strip().lower()
        out.append({"name": name, "role": role, "img": (p.get("img") or "").strip(), "href": (p.get("href") or "").strip()})
    return out

def sha(s, n): return hashlib.sha1(s.encode("utf-8", "ignore")).hexdigest()[:n]
def ep_key(feed, guid): return sha(feed, 8) + sha(guid, 10)

def parse_feed(data, feed_url):
    if b"<!ENTITY" in data[:4096] or b"<!entity" in data[:4096]:
        raise ValueError("invalid feed (XML entity)")
    root = ET.fromstring(data)
    ch = root.find("channel")
    if ch is None: raise ValueError("not an RSS feed")
    show_cover = _img(ch)
    info = {
        "feed": feed_url,
        "title": _txt(ch, "title"),
        "author": _txt(ch, "itunes:author") or _txt(ch, "managingEditor") or "",
        "desc": _clean(_txt(ch, "description") or _txt(ch, "itunes:summary"), 2500),
        "cover": show_cover, "lang": _txt(ch, "language"),
        "genre": (ch.find("itunes:category", NS).get("text") if ch.find("itunes:category", NS) is not None else ""),
        "link": _txt(ch, "link"),
    }
    eps = []; trailers = []; ep_persons = []
    for n, it in enumerate(ch.findall("item")):
        enc = it.find("enclosure")
        audio = enc.get("url") if enc is not None else ""
        if not audio:
            mc = it.find("media:content", NS)
            audio = mc.get("url") if mc is not None else ""
        if not audio: continue
        guid = _txt(it, "guid") or audio
        ts = _date_ts(_txt(it, "pubDate"))
        desc = _txt(it, "content:encoded") or _txt(it, "description") or _txt(it, "itunes:summary")
        is_tr = (_txt(it, "itunes:episodeType") or "").lower() == "trailer"
        (trailers if is_tr else eps).append({
            "guid": guid, "ek": ep_key(feed_url, guid), "title": _clean(_txt(it, "title")) or "Episodio",
            "desc": _clean(desc, 1500), "date": ts, "dateLabel": _fmt_date(ts),
            "dur": _dur(_txt(it, "itunes:duration")), "audio": audio,
            "cover": _img(it) or show_cover, "season": _txt(it, "itunes:season"), "episode": _txt(it, "itunes:episode"),
            "type": _txt(it, "itunes:episodeType") or "full", "_n": n,
        })
        if not is_tr: ep_persons.append((ts, n, _persons(it)))
    # order: most recent first (for equal dates the feed order applies)
    eps.sort(key=lambda e: (-e["date"], e["_n"]))
    for e in eps: e.pop("_n", None)
    trailers.sort(key=lambda e: (-e["date"], e["_n"]))
    for e in trailers: e.pop("_n", None)
    info["episodes"] = eps
    info["trailer"] = trailers[0] if trailers else None
    # hosts and guests: channel host + people of the latest episodes (guests)
    ep_persons.sort(key=lambda t: (-t[0], t[1]))
    people, seen = [], set()
    chp = _persons(ch)
    for src in [chp] + [pp for _, _, pp in ep_persons[:15]]:
        for pr in src:
            k = pr["name"].lower()
            if k in seen: continue
            seen.add(k); people.append(pr)
    if not people and info["author"]:
        people.append({"name": info["author"], "role": "host", "img": "", "href": ""})
    people.sort(key=lambda x: 0 if x["role"] == "host" else 1)     # stable: host first
    info["persons"] = people[:24]
    return info

def get_feed(feed_url, force=False):
    def go():
        return parse_feed(http_get(feed_url), feed_url)
    return cached("feed:" + feed_url, 0 if force else 900, go)

# ════════════════════════ User data (subscriptions, progress) ════════════════════════
_st_lock = threading.RLock()
ST = {"subs": [], "prog": {}, "saved": {}, "speed": 1.0, "autoplay": True}

def load_state():
    try:
        with open(DATA_PATH) as f: d = json.load(f)
        for k in ST:
            if k in d: ST[k] = d[k]
    except FileNotFoundError: pass
    except Exception as e: log("data not readable, starting from scratch:", repr(e))

def save_state():
    with _st_lock:
        try:
            os.makedirs(os.path.dirname(DATA_PATH), exist_ok=True)
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(DATA_PATH), prefix=".podcast_")
            with os.fdopen(fd, "w") as f: json.dump(ST, f, ensure_ascii=False)
            os.replace(tmp, DATA_PATH)
        except Exception as e:
            log("saving failed:", repr(e))

def is_sub(feed): return any(s["feed"] == feed for s in ST["subs"])

def prog_of(ek): return ST["prog"].get(ek) or {}

def annotate(ep):
    p = prog_of(ep["ek"])
    out = dict(ep)
    out["pos"] = int(p.get("pos", 0)); out["done"] = bool(p.get("done", False))
    out["saved"] = ep["ek"] in ST["saved"]
    if p.get("dur") and not out.get("dur"): out["dur"] = int(p["dur"])
    return out

def set_progress(ep, pos, dur, done=None):
    with _st_lock:
        p = ST["prog"].setdefault(ep["ek"], {})
        p.update({"pos": int(pos), "ts": int(time.time()), "feed": ep.get("feed", ""), "guid": ep["guid"], "title": ep["title"],
                  "podcast": ep.get("podcast", ""), "cover": ep.get("cover", ""), "audio": ep["audio"], "date": ep.get("date", 0)})
        if dur and dur > 1: p["dur"] = int(dur)
        d = p.get("dur") or 0
        if done is None: done = bool(d and pos >= d - 30)
        if done: p["done"] = True
        elif pos < max(0, (d or 0) - 30): p["done"] = False
        # keep at most 400 progress entries (the most recent)
        if len(ST["prog"]) > 400:
            for k, _ in sorted(ST["prog"].items(), key=lambda kv: kv[1].get("ts", 0))[:len(ST["prog"]) - 400]:
                ST["prog"].pop(k, None)

# ════════════════════════ Riproduzione (mpv) ════════════════════════
player = None
def init_mpv():
    global player
    try:
        import mpv
        player = mpv.MPV(video=False, ytdl=False)
        try: player["af"] = "loudnorm=I=-16:TP=-1.5:LRA=11"      # same level as YT Music and Spotify (-16 LUFS)
        except Exception: pass
        for k, v in (("keep-open", "yes"), ("audio-display", "no"), ("user-agent", UA),
                     ("force-seekable", "yes"), ("cache", "yes")):
            try: player[k] = v
            except Exception: pass
        try: player.speed = float(ST.get("speed", 1.0))
        except Exception: pass
    except Exception as e:
        player = None
        log("mpv not available (%r): search and feeds work, playback does not." % e)

_pl_lock = threading.RLock()
PS = {"ep": None, "queue": [], "qpos": -1, "status": "Stopped", "pos": 0.0, "dur": 0.0, "sleep_at": 0.0, "loaded": False, "seeked_at": 0.0}

def _ep_brief(e):
    return {k: e.get(k, "") for k in ("ek", "feed", "guid", "title", "podcast", "cover", "audio", "date", "dateLabel", "dur", "desc")}

def _save_current(done=None):
    ep = PS["ep"]
    if not ep: return
    pos = PS["pos"]; dur = PS["dur"] or ep.get("dur") or 0
    if pos > 1 or done: set_progress(ep, pos, dur, done)

def build_queue(feed_url, ep):
    """Podcast queue: from the oldest to the most recent (next = newest episode)."""
    try:
        eps = [dict(e, feed=feed_url) for e in reversed(get_feed(feed_url)["episodes"])]
        info = get_feed(feed_url)
        for e in eps: e["podcast"] = info["title"]; e["cover"] = e.get("cover") or info["cover"]
        for i, e in enumerate(eps):
            if e["ek"] == ep["ek"]: return eps, i
    except Exception as e:
        log("queue not built:", repr(e)[:80])
    return [ep], 0

def play_ep(ep, queue=None, qpos=None, start=None):
    if not player: return False
    with _pl_lock:
        _save_current()
        PS["ep"] = ep
        if queue is not None: PS["queue"], PS["qpos"] = queue, qpos
        p = prog_of(ep["ek"])
        if start is None:
            start = 0 if p.get("done") else max(0, int(p.get("pos", 0)) - 3)
            if start < 10: start = 0
        PS.update({"pos": float(start), "dur": float(ep.get("dur") or p.get("dur") or 0), "status": "Playing", "loaded": False,
                   "seeked_at": time.time()})
        try:
            player.pause = False
            if start > 0:
                try: player.loadfile(ep["audio"], start=str(start))
                except Exception: player.play(ep["audio"])
            else:
                player.play(ep["audio"])
        except Exception as e:
            log("playback did not start:", repr(e)[:120]); PS["status"] = "Stopped"; return False
        set_progress(ep, start, PS["dur"], None) if start else None
        _mpris_claim()
        _mpris_push(full=True)
    save_state()
    return True

def toggle(want=None):
    if not player or not PS["ep"]: return False
    with _pl_lock:
        playing = PS["status"] == "Playing"
        if want is None: want = not playing
        try: player.pause = not want
        except Exception: return False
        if want and PS.get("ended"):          # fine episodio: ricomincia
            PS["ended"] = False; play_ep(PS["ep"], start=0); return True
        PS["status"] = "Playing" if want else "Paused"
        if not want: _save_current(); save_state()
        _mpris_push()
    return True

def seek_abs(pos):
    if not player or not PS["ep"]: return
    pos = max(0.0, float(pos))
    d = PS["dur"] or PS["ep"].get("dur") or 0
    if d: pos = min(pos, max(0.0, d - 1))
    try: player.seek(pos, reference="absolute")
    except Exception as e: log("seek:", repr(e)[:80]); return
    PS["pos"] = pos; PS["seeked_at"] = time.time()
    _mpris_seeked()

def seek_rel(sec): seek_abs(PS["pos"] + sec)

def go_next():
    with _pl_lock:
        q, i = PS["queue"], PS["qpos"]
        j = i + 1
        while j < len(q) and prog_of(q[j]["ek"]).get("done"): j += 1
        if j >= len(q): return False
        return play_ep(q[j], q, j)

def go_prev():
    with _pl_lock:
        if PS["pos"] > 5 or PS["qpos"] <= 0:
            seek_abs(0); return True
        q, i = PS["queue"], PS["qpos"]
        return play_ep(q[i - 1], q, i - 1)

def set_speed(x):
    x = max(0.5, min(3.0, float(x)))
    if player:
        try: player.speed = x
        except Exception: pass
    ST["speed"] = x; save_state(); _mpris_push()
    return x

def set_sleep(minutes):
    PS["sleep_at"] = (time.time() + float(minutes) * 60) if minutes and float(minutes) > 0 else 0.0

_last_save = [0.0]
def _tick():
    """Every half second: reads mpv, saves the progress, moves to the next episode, sleep timer."""
    if not player or not PS["ep"]: return
    with _pl_lock:
        try:
            tp = player.time_pos; du = player.duration; paused = bool(player.pause); eof = bool(player.eof_reached)
        except Exception: return
        if tp is not None:
            PS["loaded"] = True
            if time.time() - PS["seeked_at"] > 1.0 or True: PS["pos"] = float(tp)
        if du: 
            if abs(float(du) - PS["dur"]) > 1: PS["dur"] = float(du); _mpris_push(full=True)
        if eof and PS["status"] == "Playing":
            _save_current(done=True); save_state()
            PS["status"] = "Stopped"; PS["ended"] = True
            nxt = ST.get("autoplay", True) and go_next()
            if not nxt: _mpris_push()
            return
        # external state (e.g. pause given by the system player)
        if PS["loaded"] and not eof and not _mp.get("hold"):
            st = "Paused" if paused else "Playing"
            if st != PS["status"] and PS["status"] in ("Playing", "Paused"):
                PS["status"] = st; _mpris_push()
        if PS["sleep_at"] and time.time() >= PS["sleep_at"]:
            PS["sleep_at"] = 0.0
            try: player.pause = True
            except Exception: pass
            if PS["status"] == "Playing": PS["status"] = "Paused"
            _save_current(); save_state(); _mpris_push()
        if PS["status"] == "Playing" and time.time() - _last_save[0] > 5:
            _last_save[0] = time.time(); _save_current(); save_state()

def _ticker():
    while True:
        try: _tick()
        except Exception as e: log("tick:", repr(e)[:100])
        time.sleep(0.5)

# ════════════════════════ System player (MPRIS) ════════════════════════
# So the mini player, the steering-wheel/Bluetooth controls etc. see "Podcast" as a normal player.
_mp = {"loop": None, "root": None, "player": None, "ok": False, "hold": False}
HOLD_S = float(os.environ.get("PODCAST_HOLD", "1.0"))

def _pb():
    """Playback state announced to the system. At first start the player presents itself as 'paused' and
    switches to 'playing' after a moment: the interface (MprisManager) considers 'just started' only whoever
    changes state, not whoever appears already playing. This way the miniplayer shows it and the other music is paused."""
    return "Paused" if (_mp.get("hold") and PS["status"] == "Playing") else PS["status"]

def _meta():
    ep = PS["ep"]
    if not ep: return {}
    from dbus_next import Variant
    m = {"mpris:trackid": Variant("o", "/org/volta/podcast/ep" + ep["ek"]),
         "xesam:title": Variant("s", ep["title"]), "xesam:artist": Variant("as", [ep.get("podcast") or ""]),
         "xesam:album": Variant("s", ep.get("podcast") or "")}
    d = PS["dur"] or ep.get("dur") or 0
    if d: m["mpris:length"] = Variant("x", int(d * 1e6))
    if ep.get("cover"): m["mpris:artUrl"] = Variant("s", ep["cover"])
    return m

def _can_next():
    q, i = PS["queue"], PS["qpos"]
    return any(not prog_of(x["ek"]).get("done") for x in q[i + 1:]) if i >= 0 else False

def _mpris_push(full=False):
    if not _mp["ok"]: return
    loop = _mp["loop"]
    def apply():
        try:
            pl = _mp["player"]
            ch = {"PlaybackStatus": _pb(), "Rate": float(ST.get("speed", 1.0)),
                  "CanGoNext": _can_next(), "CanGoPrevious": PS["ep"] is not None, "CanPlay": PS["ep"] is not None,
                  "CanPause": PS["ep"] is not None, "CanSeek": PS["ep"] is not None}
            if full: ch["Metadata"] = _meta()
            pl.emit_properties_changed(ch)
        except Exception as e: log("mpris:", repr(e)[:100])
    try: loop.call_soon_threadsafe(apply)
    except Exception: pass

def _mpris_seeked():
    if not _mp["ok"]: return
    def apply():
        try: _mp["player"].Seeked(int(PS["pos"] * 1e6))
        except Exception: pass
    try: _mp["loop"].call_soon_threadsafe(apply)
    except Exception: pass

def _mpris_claim():
    """First playback: announces the player to the system (org.mpris.MediaPlayer2.podcast)."""
    if not _mp["ok"] or _mp.get("claimed"): return
    _mp["claimed"] = True
    _mp["hold"] = True
    try: player.pause = True          # audio starts when the system has seen the player (so it does not mix with the music)
    except Exception: pass
    async def go():
        try:
            await _mp["bus"].request_name(os.environ.get("PODCAST_MPRIS_NAME", "org.mpris.MediaPlayer2.podcast"))
            log("MPRIS attivo")
        except Exception as e:
            _mp["claimed"] = False; log("MPRIS: name not obtained:", repr(e)[:100])
            _mp["hold"] = False
            try:
                if PS["status"] == "Playing": player.pause = False
            except Exception: pass
            return
        await asyncio.sleep(HOLD_S)
        _mp["hold"] = False
        try:
            if PS["status"] == "Playing": player.pause = False
        except Exception: pass
        _mpris_push(full=True)
    import asyncio
    try: asyncio.run_coroutine_threadsafe(go(), _mp["loop"])
    except Exception as e: _mp["claimed"] = False; log("MPRIS:", repr(e)[:100])

def start_mpris():
    def run():
        import asyncio
        try:
            from dbus_next.aio import MessageBus
            from dbus_next.service import ServiceInterface, method, dbus_property, signal
            from dbus_next.constants import PropertyAccess
            from dbus_next import Variant
        except Exception as e:
            log("dbus-next missing (%r): the mini player will not see the podcasts. pip install --break-system-packages dbus-next" % e); return

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
            def Identity(self) -> "s": return "Podcast"
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
            def Seek(self, offset: "x"): bg(seek_rel, offset / 1e6)
            @method()
            def SetPosition(self, track_id: "o", position: "x"):
                ep = PS["ep"]
                if ep and track_id == "/org/volta/podcast/ep" + ep["ek"]: bg(seek_abs, position / 1e6)
            @method()
            def OpenUri(self, uri: "s"): pass
            @signal()
            def Seeked(self) -> "x": return int(PS["pos"] * 1e6)
            @dbus_property(access=PropertyAccess.READ)
            def PlaybackStatus(self) -> "s": return _pb()
            @dbus_property(access=PropertyAccess.READ)
            def Rate(self) -> "d": return float(ST.get("speed", 1.0))
            @dbus_property(access=PropertyAccess.READ)
            def Metadata(self) -> "a{sv}": return _meta()
            @dbus_property(access=PropertyAccess.READ)
            def Volume(self) -> "d": return 1.0
            @dbus_property(access=PropertyAccess.READ)
            def Position(self) -> "x": return int(PS["pos"] * 1e6)
            @dbus_property(access=PropertyAccess.READ)
            def MinimumRate(self) -> "d": return 0.5
            @dbus_property(access=PropertyAccess.READ)
            def MaximumRate(self) -> "d": return 3.0
            @dbus_property(access=PropertyAccess.READ)
            def CanGoNext(self) -> "b": return _can_next()
            @dbus_property(access=PropertyAccess.READ)
            def CanGoPrevious(self) -> "b": return PS["ep"] is not None
            @dbus_property(access=PropertyAccess.READ)
            def CanPlay(self) -> "b": return PS["ep"] is not None
            @dbus_property(access=PropertyAccess.READ)
            def CanPause(self) -> "b": return PS["ep"] is not None
            @dbus_property(access=PropertyAccess.READ)
            def CanSeek(self) -> "b": return PS["ep"] is not None
            @dbus_property(access=PropertyAccess.READ)
            def CanControl(self) -> "b": return True

        async def main():
            bus = await MessageBus().connect()
            r, p = Root(), Player()
            bus.export("/org/mpris/MediaPlayer2", r)
            bus.export("/org/mpris/MediaPlayer2", p)
            # the bus name is taken at the first playback: when stopped the system player does not see "Podcast"
            _mp.update(loop=asyncio.get_running_loop(), root=r, player=p, bus=bus, ok=True, claimed=False)
            log("MPRIS pronto (il nome sul bus viene preso alla prima riproduzione)")
            await bus.wait_for_disconnect()

        try: asyncio.run(main())
        except Exception as e: log("MPRIS not active:", repr(e)[:120]); _mp["ok"] = False
    threading.Thread(target=run, daemon=True).start()

# ════════════════════════ API ════════════════════════
def _err(e, code=502): return jsonify({"ok": False, "error": str(e)[:200]}), code

def _show_item(s):
    return {"id": s.get("id", ""), "title": s["title"], "author": s.get("author", ""), "cover": s.get("cover", ""), "feed": s["feed"]}

@app.route("/health")
def health(): return jsonify({"ok": True, "mpv": player is not None, "mpris": _mp["ok"], "subs": len(ST["subs"])})

@app.route("/genres")
def genres(): return jsonify({"genres": GENRES})

@app.route("/search")
def search():
    q = (freq.args.get("q") or "").strip()
    if len(q) < 2: return jsonify({"podcasts": [], "episodes": []})
    try: pods = search_podcasts(q)
    except RateLimited: return jsonify({"ok": False, "error": "Too many searches in a row, try again shortly."}), 429
    except Exception as e: return _err(e)
    eps = []
    try: eps = search_episodes(q)
    except Exception: pass
    for p in pods: p["subscribed"] = is_sub(p["feed"])
    return jsonify({"podcasts": pods, "episodes": eps})

@app.route("/charts")
def charts_route():
    try: items = charts(freq.args.get("genre", ""))
    except RateLimited: return jsonify({"ok": False, "error": "Too many requests, try again shortly."}), 429
    except Exception as e: return _err(e)
    return jsonify({"items": items})

@app.route("/browse")
def browse_route():
    """Explore: various choices, shuffled at every request (seed), always grouped by category.
    It only uses the charts (static files, no request limit), no searches."""
    import random
    seed = freq.args.get("seed") or str(int(time.time()))
    rnd = random.Random(seed)
    ids = [g["id"] for g in GENRES]; rnd.shuffle(ids)
    NEWS = "1311"
    hero_g = [i for i in ids if i != NEWS][:3]
    shelf_g = [i for i in ids if i != NEWS and i not in hero_g][:6]
    want = list(dict.fromkeys(hero_g + shelf_g + [NEWS, ""]))
    data = {}
    def one(g):
        try: data[g] = charts(g, 50, fill_search=False)
        except Exception as e: log("esplora: categoria", g or "generale", "not available:", repr(e)[:80])
    pool = ThreadPoolExecutor(max_workers=6)
    futs = [pool.submit(one, g) for g in want]
    _fwait(futs, timeout=25); pool.shutdown(wait=False)
    used = set()
    def pick(lst, n):
        pool_ = [x for x in lst if x["id"] not in used]
        rnd.shuffle(pool_); out = pool_[:n]
        for x in out: used.add(x["id"])
        return out
    hero = []
    for g in hero_g:
        got = pick((data.get(g) or [])[:12], 1)
        if got: hero.append({"label": GENRE_NAME[g], "genre": g, "show": got[0]})
    shelves = []
    gen = data.get("") or []
    new = pick(gen[6:60], 14)
    if len(new) >= 4: shelves.append({"id": "new", "title": "New and to discover", "genre": "", "kind": "shows", "items": new})
    news = pick((data.get(NEWS) or [])[:25], 10)
    if len(news) >= 4: shelves.append({"id": "news", "title": "News of the day", "genre": NEWS, "kind": "wide", "items": news})
    for g in shelf_g:
        its = pick(data.get(g) or [], 14)
        if len(its) >= 4: shelves.append({"id": g, "title": GENRE_NAME[g], "genre": g, "kind": "shows", "items": its})
    if not hero and not shelves: return _err("Explore not available at the moment")
    return jsonify({"seed": seed, "hero": hero, "shelves": shelves, "genres": GENRES})

@app.route("/category")
def category_route():
    """Page of a category: most listened (chart), to discover (shuffled), full chart."""
    import random
    g = (freq.args.get("genre") or "").strip()
    if g not in GENRE_NAME: return _err("categoria sconosciuta", 400)
    rnd = random.Random(freq.args.get("seed") or str(int(time.time())))
    try: items = charts(g, 50)
    except Exception as e: return _err(e)
    top, rest = items[:12], list(items[12:])
    rnd.shuffle(rest)
    info = next(x for x in GENRES if x["id"] == g)
    return jsonify({"genre": info, "top": top, "discover": rest[:14], "all": items})

@app.route("/top_episodes")
def top_episodes_route():
    try: eps = top_episodes(freq.args.get("genre", ""))
    except RateLimited: return jsonify({"ok": False, "error": "Too many requests, try again shortly."}), 429
    except Exception as e: return _err(e)
    out = []
    for e in eps:
        e = dict(e); e["ek"] = ep_key(e.get("feed", "") or "ext", e["guid"])
        out.append(annotate(e))
    return jsonify({"episodes": out})

@app.route("/podcast")
def podcast():
    feed = (freq.args.get("feed") or "").strip()
    pid = (freq.args.get("id") or "").strip()
    try:
        if not feed and pid: feed = (itunes_lookup([pid]).get(pid) or {}).get("feed", "")
        if not feed: return _err("feed missing", 400)
        info = get_feed(feed, force=freq.args.get("fresh") == "1")
    except Exception as e: return _err(e)
    eps = []
    for e in info["episodes"][:400]:
        a = annotate(e); a["feed"] = feed; a["podcast"] = info["title"]
        eps.append(a)
    out = {k: info[k] for k in ("feed", "title", "author", "desc", "cover", "lang", "genre", "link")}
    tr = None
    if info.get("trailer"):
        tr = annotate(info["trailer"]); tr["feed"] = feed; tr["podcast"] = info["title"]
    out.update({"persons": info.get("persons", []), "trailer": tr, "id": pid, "subscribed": is_sub(feed), "total": len(info["episodes"]), "episodes": eps})
    if is_sub(feed):          # keep the saved data (title/cover) up to date
        for s in ST["subs"]:
            if s["feed"] == feed and (s.get("cover") != info["cover"] and info["cover"]): s["cover"] = info["cover"]
    return jsonify(out)

@app.route("/subs")
def subs():
    return jsonify({"subs": sorted(ST["subs"], key=lambda s: s["title"].lower())})

@app.route("/subs/toggle")
def subs_toggle():
    feed = (freq.args.get("feed") or "").strip()
    if not feed: return _err("feed missing", 400)
    with _st_lock:
        if is_sub(feed):
            ST["subs"] = [s for s in ST["subs"] if s["feed"] != feed]; on = False
        else:
            ST["subs"].append({"feed": feed, "id": freq.args.get("id", ""), "title": freq.args.get("title", "") or feed,
                               "author": freq.args.get("author", ""), "cover": freq.args.get("cover", ""), "added": int(time.time())})
            on = True
    save_state()
    return jsonify({"ok": True, "subscribed": on})

@app.route("/new")
def new_episodes():
    subs_ = list(ST["subs"])
    if not subs_: return jsonify({"episodes": []})
    pool = ThreadPoolExecutor(max_workers=6)
    futs = {pool.submit(get_feed, s["feed"]): s for s in subs_}
    done, _ = _fwait(list(futs), timeout=20)
    pool.shutdown(wait=False)
    out = []
    cutoff = time.time() - 45 * 86400
    for f in done:
        s = futs[f]
        try: info = f.result()
        except Exception: continue
        for e in info["episodes"][:3]:
            if e["date"] < cutoff and e["date"] != 0: continue
            a = annotate(e)
            if a["done"]: continue
            a["feed"] = s["feed"]; a["podcast"] = info["title"]; a["cover"] = e.get("cover") or info["cover"]
            out.append(a)
    out.sort(key=lambda e: -e["date"])
    return jsonify({"episodes": out[:40]})

@app.route("/saved")
def saved_list():
    items = sorted(ST["saved"].values(), key=lambda e: -e.get("saved_at", 0))
    return jsonify({"episodes": [annotate(e) for e in items]})

@app.route("/saved/toggle")
def saved_toggle():
    feed = freq.args.get("feed", ""); guid = freq.args.get("guid", "")
    ek = ep_key(feed or "ext", guid)
    with _st_lock:
        if ek in ST["saved"]:
            ST["saved"].pop(ek); on = False
        else:
            try: ep = _episode_from_request()
            except Exception as e: return _err(e)
            if not ep: return _err("episode not found", 404)
            ep = _ep_brief(ep); ep["ek"] = ek; ep["saved_at"] = int(time.time())
            ST["saved"][ek] = ep; on = True
    save_state()
    return jsonify({"ok": True, "saved": on})

@app.route("/continue")
def continue_list():
    items = []
    for ek, p in ST["prog"].items():
        if p.get("done") or int(p.get("pos", 0)) < 15 or not p.get("audio"): continue
        items.append({"ek": ek, "feed": p.get("feed", ""), "guid": p.get("guid", ""), "title": p.get("title", ""),
                      "podcast": p.get("podcast", ""), "cover": p.get("cover", ""), "audio": p.get("audio", ""),
                      "dur": int(p.get("dur", 0)), "pos": int(p.get("pos", 0)), "date": p.get("date", 0),
                      "dateLabel": _fmt_date(p.get("date", 0)), "ts": p.get("ts", 0), "done": False})
    items.sort(key=lambda x: -x["ts"])
    return jsonify({"episodes": items[:20]})

@app.route("/history")
def history():
    items = []
    for ek, p in ST["prog"].items():
        if not p.get("audio"): continue
        items.append({"ek": ek, "feed": p.get("feed", ""), "guid": p.get("guid", ""), "title": p.get("title", ""),
                      "podcast": p.get("podcast", ""), "cover": p.get("cover", ""), "audio": p.get("audio", ""),
                      "dur": int(p.get("dur", 0)), "pos": int(p.get("pos", 0)), "date": p.get("date", 0),
                      "dateLabel": _fmt_date(p.get("date", 0)), "ts": p.get("ts", 0), "done": bool(p.get("done"))})
    items.sort(key=lambda x: -x["ts"])
    return jsonify({"episodes": items[:60]})

@app.route("/mark")
def mark():
    feed = freq.args.get("feed", ""); guid = freq.args.get("guid", "")
    done = freq.args.get("done", "1") == "1"
    ep = {"ek": ep_key(feed, guid), "guid": guid, "feed": feed, "title": freq.args.get("title", ""), "audio": freq.args.get("audio", "x")}
    with _st_lock:
        p = ST["prog"].setdefault(ep["ek"], {"pos": 0, "ts": int(time.time()), "feed": feed, "guid": guid, "audio": ep["audio"], "title": ep["title"]})
        p["done"] = done
        if not done: p["pos"] = 0
    save_state()
    return jsonify({"ok": True, "done": done})

def _episode_from_request():
    feed = freq.args.get("feed", "").strip(); guid = freq.args.get("guid", "").strip()
    if feed:
        info = get_feed(feed)
        for e in info["episodes"] + ([info["trailer"]] if info.get("trailer") else []):
            if e["guid"] == guid or e["ek"] == guid:
                return dict(e, feed=feed, podcast=info["title"], cover=e.get("cover") or info["cover"])
    audio = freq.args.get("audio", "").strip()
    if audio:           # episode from iTunes search (without cached feed)
        g = guid or audio
        return {"guid": g, "ek": ep_key(feed or "ext", g), "feed": feed, "title": freq.args.get("title", "Episodio"),
                "podcast": freq.args.get("podcast", ""), "cover": freq.args.get("cover", ""), "audio": audio,
                "dur": int(float(freq.args.get("dur", 0) or 0)), "date": int(float(freq.args.get("date", 0) or 0)),
                "dateLabel": "", "desc": ""}
    return None

@app.route("/play")
def play():
    if not player: return _err("playback not available (python-mpv missing)", 503)
    try: ep = _episode_from_request()
    except Exception as e: return _err(e)
    if not ep: return _err("episode not found", 404)
    start = freq.args.get("start")
    q, i = (build_queue(ep["feed"], ep) if ep.get("feed") else ([ep], 0))
    ok = play_ep(ep, q, i, start=float(start) if start not in (None, "") else None)
    return jsonify({"ok": ok, "state": _state()})

def _state():
    ep = PS["ep"]
    left = max(0, int(PS["sleep_at"] - time.time())) if PS["sleep_at"] else 0
    return {"active": ep is not None, "playing": PS["status"] == "Playing", "status": PS["status"],
            "pos": PS["pos"], "dur": PS["dur"] or (ep or {}).get("dur") or 0, "speed": float(ST.get("speed", 1.0)),
            "sleepLeft": left, "canNext": _can_next(), "canPrev": ep is not None, "autoplay": bool(ST.get("autoplay", True)),
            "loaded": PS["loaded"], "ep": _ep_brief(ep) if ep else None}

@app.route("/player/state")
def player_state(): return jsonify(_state())

@app.route("/player/toggle")
def player_toggle():
    toggle(None); return jsonify(_state())
@app.route("/player/play")
def player_play():
    toggle(True); return jsonify(_state())
@app.route("/player/pause")
def player_pause():
    toggle(False); return jsonify(_state())
@app.route("/player/seek")
def player_seek():
    if freq.args.get("rel"): seek_rel(float(freq.args["rel"]))
    elif freq.args.get("pos"): seek_abs(float(freq.args["pos"]))
    elif freq.args.get("pct"):
        d = PS["dur"] or (PS["ep"] or {}).get("dur") or 0
        if d: seek_abs(float(freq.args["pct"]) * d)
    return jsonify(_state())
SPEEDS = [1.0, 1.25, 1.5, 1.75, 2.0, 0.8]
@app.route("/player/speed")
def player_speed():
    if freq.args.get("cycle"):                     # mini player: next speed of the series
        cur = float(ST.get("speed", 1.0)); i = 0
        for k, v in enumerate(SPEEDS):
            if abs(v - cur) < 0.01: i = k
        set_speed(SPEEDS[(i + 1) % len(SPEEDS)])
    elif freq.args.get("x"): set_speed(freq.args["x"])
    return jsonify(_state())

@app.route("/player/queue")
def player_queue():
    """Episodes after the current one (already listened ones are skipped)."""
    q, i = PS["queue"], PS["qpos"]
    items = []
    for j in range(i + 1, len(q)) if i >= 0 else []:
        if prog_of(q[j]["ek"]).get("done"): continue
        a = annotate(q[j]); a["qi"] = j
        items.append(a)
        if len(items) >= 60: break
    return jsonify({"items": items})

@app.route("/player/jump")
def player_jump():
    try: j = int(freq.args.get("i", "-1"))
    except ValueError: j = -1
    q = PS["queue"]
    if 0 <= j < len(q): play_ep(q[j], q, j)
    return jsonify(_state())
@app.route("/player/next")
def player_next():
    go_next(); return jsonify(_state())
@app.route("/player/prev")
def player_prev():
    go_prev(); return jsonify(_state())
@app.route("/player/sleep")
def player_sleep():
    set_sleep(freq.args.get("min", "0")); return jsonify(_state())
@app.route("/player/autoplay")
def player_autoplay():
    ST["autoplay"] = freq.args.get("on", "1") == "1"; save_state(); return jsonify(_state())

def shutdown_save():
    try: _save_current(); save_state()
    except Exception: pass

def main():
    load_state()
    init_mpv()
    start_mpris()
    threading.Thread(target=_ticker, daemon=True).start()
    import atexit, signal
    atexit.register(shutdown_save)
    def _term(*_): shutdown_save(); os._exit(0)
    try: signal.signal(signal.SIGTERM, _term)
    except Exception: pass
    app.run(host="127.0.0.1", port=PORT, threaded=True)

if __name__ == "__main__":
    main()
