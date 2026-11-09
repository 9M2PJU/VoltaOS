"""Radio from all over the world for Volta OS (it hooks into the maps service, port 9098).

Routes:
  /radio/countries                    countries with stations (Radio Browser)
  /radio/stations?cc=IT&q=&offset=    stations of a country, or search worldwide (empty cc)
  /radio/logo?s=<uuid>&u=<favicon>&h=<homepage>&n=<name>
                                      square PNG logo up to 256 px, the best found

The stations come from Radio Browser (https://www.radio-browser.info), a public and free archive.
The logos from that archive are often tiny (16-64 px): here the station's own is tried first, then
the high-resolution icons of its page (apple-touch-icon, og:image) and Google's favicon service,
the largest is chosen and saved to disk. If nothing decent is found a tile
with the initials is drawn.
"""
import hashlib
import io
import ipaddress
import json
import re
import socket
import threading
import urllib.parse
from pathlib import Path

import requests
from flask import Response, jsonify, request
from PIL import Image, ImageDraw, ImageFont

_UA = "VoltaOS/1.0 (radio)"
_HOSTS = ("de1", "fi1", "at1")
_LOGO_SIZE = 256
_MIN_GOOD = 160            # below this side length (px) better alternatives are searched
_MIN_USABLE = 48           # below this side length the logo is too small: better the tile with the initials
_logo_sem = threading.BoundedSemaphore(6)
_logo_locks = {}
_logo_locks_guard = threading.Lock()


def _rb_get(fetch_cached, path, ttl):
    """GET on Radio Browser trying the servers in turn (with disk cache)."""
    for h in _HOSTS:
        url = f"https://{h}.api.radio-browser.info/json{path}"
        name = hashlib.md5(url.encode()).hexdigest() + ".json"
        data, st = fetch_cached('rb', name, url, ttl=ttl, headers={"User-Agent": _UA}, timeout=(4, 10))
        if data:
            try:
                return json.loads(data)
            except ValueError:
                continue
    return None


def _is_public_url(url):
    """Only http/https toward public addresses (the route is local but the links come from the internet)."""
    try:
        p = urllib.parse.urlparse(url)
        if p.scheme not in ("http", "https") or not p.hostname:
            return False
        for fam, _t, _p, _c, sa in socket.getaddrinfo(p.hostname, None):
            ip = ipaddress.ip_address(sa[0])
            if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast:
                return False
        return True
    except (OSError, ValueError):
        return False


def _fetch_img(url):
    """(PIL image, minimum side) or (None, 0)."""
    if not _is_public_url(url):
        return None, 0
    try:
        r = requests.get(url, timeout=(3, 6), headers={"User-Agent": _UA}, stream=True)
        if r.status_code != 200:
            return None, 0
        data = r.raw.read(4_000_000, decode_content=True)
        im = Image.open(io.BytesIO(data))
        if im.format == "ICO":                       # choose the largest size contained in the file
            sizes = sorted(im.info.get("sizes") or [im.size], key=lambda s: s[0] * s[1])
            im.size = sizes[-1]
        im.load()
        im = im.convert("RGBA")
        return im, min(im.size)
    except Exception:
        return None, 0


def _homepage_icons(home):
    """Icons declared in the page: apple-touch-icon, icon, og:image (the largest first)."""
    if not home or not _is_public_url(home):
        return []
    try:
        r = requests.get(home, timeout=(3, 6), headers={"User-Agent": _UA})
        html = r.text[:400_000]
    except requests.RequestException:
        return []
    found = []
    for m in re.finditer(r"<link\b[^>]*>", html, re.I):
        tag = m.group(0)
        rel = re.search(r'rel=["\']([^"\']+)["\']', tag, re.I)
        href = re.search(r'href=["\']([^"\']+)["\']', tag, re.I)
        if not rel or not href or "icon" not in rel.group(1).lower():
            continue
        sz = re.search(r'sizes=["\'](\d+)x\d+', tag, re.I)
        score = int(sz.group(1)) if sz else (180 if "apple-touch" in rel.group(1).lower() else 32)
        found.append((score, urllib.parse.urljoin(r.url, href.group(1))))
    for m in re.finditer(r'<meta\b[^>]*>', html, re.I):
        tag = m.group(0)
        if re.search(r'property=["\']og:image["\']', tag, re.I):
            c = re.search(r'content=["\']([^"\']+)["\']', tag, re.I)
            if c:
                found.append((100, urllib.parse.urljoin(r.url, c.group(1))))
    found.sort(key=lambda t: -t[0])
    out, seen = [], set()
    for _s, u in found:
        if u not in seen:
            seen.add(u); out.append(u)
    return out[:4]


def _square_png(im):
    """Quadrato, fino a 256 px, trasparenza conservata, margine minimo."""
    im = im.convert("RGBA")
    bbox = im.getchannel("A").getbbox()
    if bbox:
        im = im.crop(bbox)
    w, h = im.size
    side = max(w, h)
    pad = max(2, side // 16)
    canvas = Image.new("RGBA", (side + pad * 2, side + pad * 2), (0, 0, 0, 0))
    canvas.paste(im, ((side + pad * 2 - w) // 2, (side + pad * 2 - h) // 2), im)
    if canvas.width > _LOGO_SIZE:
        canvas = canvas.resize((_LOGO_SIZE, _LOGO_SIZE), Image.LANCZOS)
    buf = io.BytesIO()
    canvas.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def _placeholder(name, font_path):
    """Tile with the initials, stable color based on the name."""
    h = int(hashlib.md5((name or "?").encode()).hexdigest()[:6], 16)
    hue = h % 360
    import colorsys
    r, g, b = [int(x * 255) for x in colorsys.hsv_to_rgb(hue / 360, 0.55, 0.55)]
    im = Image.new("RGBA", (_LOGO_SIZE, _LOGO_SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, _LOGO_SIZE - 1, _LOGO_SIZE - 1), radius=_LOGO_SIZE // 6, fill=(r, g, b, 255))
    words = [w for w in re.split(r"[\s\-_.]+", name or "") if w]
    txt = "".join(w[0] for w in words[:2]).upper() or "R"
    try:
        font = ImageFont.truetype(font_path, 110)
    except Exception:
        font = ImageFont.load_default()
    box = d.textbbox((0, 0), txt, font=font)
    d.text(((_LOGO_SIZE - (box[2] - box[0])) / 2 - box[0], (_LOGO_SIZE - (box[3] - box[1])) / 2 - box[1]),
           txt, font=font, fill=(255, 255, 255, 255))
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return buf.getvalue()


def _build_logo(favicon, home, name, font_path):
    best, best_side = None, 0
    cands = []
    if favicon:
        cands.append(favicon)
    for step in range(3):
        # 0: station favicon; 1: page icons; 2: Google favicon service
        if step == 0:
            urls = cands
        elif step == 1:
            if best_side >= _MIN_GOOD:
                break
            urls = _homepage_icons(home)
        else:
            if best_side >= _MIN_GOOD:
                break
            host = urllib.parse.urlparse(home or favicon or "").hostname
            urls = [f"https://www.google.com/s2/favicons?domain={host}&sz=256"] if host else []
        for u in urls:
            im, side = _fetch_img(u)
            if im is not None and side > best_side:
                best, best_side = im, side
            if best_side >= _MIN_GOOD:
                break
    if best is not None and best_side >= _MIN_USABLE:
        return _square_png(best)
    return _placeholder(name, font_path)


def register(app, fetch_cached, cache_root, font_path):
    cache_dir = Path(cache_root) / "radio_logo"
    cache_dir.mkdir(parents=True, exist_ok=True)

    @app.route('/radio/countries')
    def radio_countries():
        data = _rb_get(fetch_cached, "/countries?hidebroken=true&order=name", 86400)
        if data is None:
            return jsonify({"countries": []}), 502
        out = [{"name": c.get("name", ""), "code": c.get("iso_3166_1", ""), "count": c.get("stationcount", 0)}
               for c in data if c.get("iso_3166_1") and c.get("stationcount", 0) >= 3]
        out.sort(key=lambda c: c["name"].lower())
        return jsonify({"countries": out})

    @app.route('/radio/stations')
    def radio_stations():
        cc = (request.args.get('cc') or '').strip().upper()[:2]
        q = (request.args.get('q') or '').strip()
        try:
            limit = max(1, min(int(request.args.get('limit', 60)), 100))
            offset = max(0, int(request.args.get('offset', 0)))
        except ValueError:
            limit, offset = 60, 0
        params = {"hidebroken": "true", "order": "clickcount", "reverse": "true",
                  "limit": str(limit), "offset": str(offset)}
        if cc: params["countrycode"] = cc
        if q: params["name"] = q
        data = _rb_get(fetch_cached, "/stations/search?" + urllib.parse.urlencode(params), 1800)
        if data is None:
            return jsonify({"stations": [], "error": True}), 502
        out, names = [], set()
        for s in data:
            url = (s.get("url_resolved") or s.get("url") or "").strip()
            name = re.sub(r"\s+", " ", (s.get("name") or "")).strip()
            if not url or not name or name.lower() in names:
                continue
            names.add(name.lower())
            logo = "http://127.0.0.1:9098/radio/logo?" + urllib.parse.urlencode(
                {"s": s.get("stationuuid", ""), "u": s.get("favicon", "") or "",
                 "h": s.get("homepage", "") or "", "n": name})
            out.append({"name": name, "url_resolved": url, "stationuuid": s.get("stationuuid", ""),
                        "logoUrl": logo, "countrycode": s.get("countrycode", ""), "country": s.get("country", ""),
                        "codec": s.get("codec", ""), "bitrate": s.get("bitrate", 0)})
        return jsonify({"stations": out, "more": len(data) >= limit})

    @app.route('/radio/logo')
    def radio_logo():
        uid = request.args.get('s', '')
        fav = request.args.get('u', '')
        home = request.args.get('h', '')
        name = request.args.get('n', '')
        key = hashlib.md5(f"{uid}|{fav}|{home}".encode()).hexdigest()
        path = cache_dir / (key + ".png")
        hdr = {"Cache-Control": "public, max-age=604800"}
        try:
            return Response(path.read_bytes(), mimetype="image/png", headers=hdr)
        except OSError:
            pass
        with _logo_locks_guard:
            lock = _logo_locks.setdefault(key, threading.Lock())
        with lock:
            try:
                return Response(path.read_bytes(), mimetype="image/png", headers=hdr)
            except OSError:
                pass
            with _logo_sem:
                png = _build_logo(fav, home, name, font_path)
            try:
                path.write_bytes(png)
            except OSError:
                pass
        return Response(png, mimetype="image/png", headers=hdr)
