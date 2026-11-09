"""keys.py — reads the API keys from keys.env (in the project folder).

Usage:  from keys import key
        TOKEN = key("MAPBOX_TOKEN")

Order: environment variable > keys.env > default.
See keys.env.example for the full list. The old name chiavi.env is still read
if keys.env does not exist.
"""
import os

# keys.env lives in the project root (this file is in services/)
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_FILE = os.path.join(_ROOT, "keys.env")
if not os.path.exists(_FILE) and os.path.exists(os.path.join(_ROOT, "chiavi.env")):
    _FILE = os.path.join(_ROOT, "chiavi.env")   # legacy name


def _load():
    try:
        with open(_FILE, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k, v = k.strip(), v.strip().strip('"').strip("'")
                if k and v:
                    os.environ.setdefault(k, v)   # the environment wins over the file
    except FileNotFoundError:
        print("[keys] keys.env not found: copy keys.env.example to keys.env", flush=True)


_load()


def key(name, default=""):
    return (os.environ.get(name) or default).strip()
