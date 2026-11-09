"""local_security.py — the local services answer only to the UI, not to websites.

The services listen on 127.0.0.1, but a page opened in the built-in browser
(or in any browser on the PC) can still send requests to
http://127.0.0.1:<port>/... (e.g. turn off Wi-Fi or forget a
Bluetooth device). Chromium/Chrome/Firefox always put the
Sec-Fetch-Site / Origin headers on requests coming from a web page; the UI
(QML's XMLHttpRequest), mpv and curl do not. So:

  - Sec-Fetch-Site "cross-site" or "same-site"  -> 403 (request from a site)
  - Origin of a site that is not localhost      -> 403
  - everything else (UI, mpv, curl, address typed by hand in the browser) -> OK

Usage (Flask):  from local_security import protect
                protect(app, allow=("/callback",))   # OAuth return paths
"""
from urllib.parse import urlparse

_LOCAL = {"127.0.0.1", "localhost", "::1", "[::1]"}


def external_origin(headers):
    """True if the request comes from a web page (not from the UI)."""
    sito = (headers.get("Sec-Fetch-Site") or "").lower()
    if sito in ("cross-site", "same-site"):
        return True
    origin = headers.get("Origin")
    if origin and origin != "null":
        host = (urlparse(origin).hostname or "").lower()
        if host not in _LOCAL:
            return True
    return False


def protect(app, allow=()):
    from flask import request

    @app.before_request
    def _ui_only():
        if request.path in allow:
            return None
        if external_origin(request.headers):
            print("[security] blocked request from %s to %s"
                  % (request.headers.get("Origin") or request.headers.get("Referer") or "?", request.path),
                  flush=True)
            return ("Forbidden: this service only answers to Volta OS\n", 403)
        return None
