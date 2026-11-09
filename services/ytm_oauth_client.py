#!/usr/bin/env python3
# ytm_oauth_client.py — sets up (once) the YouTube Music login with the QR code and TESTS it.
#
# Usage:  python3 ytm_oauth_client.py            (asks for client ID and secret, saves them, tests them)
#        python3 ytm_oauth_client.py --test      (asks nothing: tests the already saved file)
#
# Saves to ~/.config/volta/yt_oauth_client.json (permissions 600). The secret is NOT shown
# while you type it and is NEVER printed.
#
# WHAT YOU NEED FIRST (once, on console.cloud.google.com — menu names may change):
#  1. Create a project (or use the one you already have).
#  2. "API e servizi" > Libreria > abilita "YouTube Data API v3".
#  3. OAuth consent screen / "Google Auth Platform": user type "External"; put your
#     Gmail address among the test users; then "PUBLISH THE APP" (status "In production").
#     IMPORTANT: as long as the app stays in "Testing", Google makes the login expire every 7 days.
#     In production without verification the "unverified app" warning appears: it is normal for personal
#     use, you go on with "Advanced" > "Go to ...".
#  4. Credentials > Create credentials > OAuth client ID > type "TVs and Limited Input devices".
#     Copia ID client e Segreto client.
# (the credentials.json you had in the project, if it is of type "Desktop", does NOT work here.)
import getpass, json, os, sys, urllib.error, urllib.parse, urllib.request

PATH = os.path.expanduser("~/.config/volta/yt_oauth_client.json")
SCOPE = "https://www.googleapis.com/auth/youtube"

def carica():
    try:
        with open(PATH) as f:
            d = json.load(f)
        if d.get("client_id") and d.get("client_secret"):
            return d
    except Exception:
        pass
    return None

def salva(cid, sec):
    os.makedirs(os.path.dirname(PATH), exist_ok=True)
    with open(PATH, "w") as f:
        json.dump({"client_id": cid, "client_secret": sec}, f)
    os.chmod(PATH, 0o600)

def prova(cid):
    """Asks Google for an access code: if it gives one, the client ID and type are right.
    It does not complete any login and does not need the secret."""
    data = urllib.parse.urlencode({"client_id": cid, "scope": SCOPE}).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request("https://oauth2.googleapis.com/device/code", data=data), timeout=20) as r:
            d = json.loads(r.read().decode())
        print("  OK: Google accepted the client. Test code:", d.get("user_code"),
              "(expires in %s s, it is useless)" % d.get("expires_in"))
        return True
    except urllib.error.HTTPError as e:
        try: err = json.loads(e.read().decode())
        except Exception: err = {}
        code = err.get("error", "")
        print("  ERROR from Google:", code or e.code, "-", err.get("error_description", ""))
        if code in ("invalid_client", "unauthorized_client"):
            print("  -> The client ID is not of type 'TVs and Limited Input devices' (or it is wrong).")
        elif code == "invalid_scope":
            print("  -> Enable 'YouTube Data API v3' in the project.")
        elif code == "access_denied":
            print("  -> Add your Gmail among the test users, or publish the app.")
        return False
    except Exception as e:
        print("  Cannot reach Google:", e)
        return False

def controlla_qr():
    for mod in ("segno", "qrcode"):
        try:
            __import__(mod); print("  QR: library '%s' present in this terminal's python." % mod); return
        except ImportError:
            pass
    print("  QR: no library in this terminal's python. The service runs with /usr/bin/python3:")
    print("      /usr/bin/python3 -c 'import segno' || /usr/bin/python3 -m pip install --break-system-packages segno")
    print("      (or: sudo apt install python3-segno). Without it, the app only shows the code to type.")

def main():
    if "--prova" in sys.argv:
        d = carica()
        if not d: print("No valid file in", PATH); sys.exit(1)
        print("Trying the client saved in", PATH); sys.exit(0 if prova(d["client_id"]) else 1)
    print("YouTube Music login setup (read the instructions at the top of this file).")
    cid = input("Client ID (ends with .apps.googleusercontent.com): ").strip()
    if not cid.endswith(".apps.googleusercontent.com"):
        print("This does not look like a Google client ID. Stopping, nothing saved."); sys.exit(1)
    sec = getpass.getpass("Client secret (not shown while you type): ").strip()
    if len(sec) < 10:
        print("Secret too short. Stopping, nothing saved."); sys.exit(1)
    print("Testing the client with Google...")
    ok = prova(cid)
    if not ok:
        r = input("The test failed. Save anyway? [y/N] ").strip().lower()
        if r != "s": print("Non ho salvato niente."); sys.exit(1)
    salva(cid, sec)
    print("Salvato in", PATH, "(permessi 600).")
    controlla_qr()
    print("Done. Restart the app: in the YouTube Music home, if you are not connected, 'Sign in' appears.")

if __name__ == "__main__":
    main()
