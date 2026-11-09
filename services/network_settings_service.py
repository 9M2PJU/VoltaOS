#!/usr/bin/env python3
"""
network_settings_service.py — REAL Wi-Fi and Bluetooth for the
UI's Settings page. It is not a mockup: it drives NetworkManager (nmcli) for
Wi-Fi and BlueZ (D-Bus, same mechanism already used by phone_service.py) for
Bluetooth. The Qt/QML UI talks to this service over local HTTP, as it already
does with the project's other microservices (Spotify, YT Music, etc.).

Port: 9097

Wi-Fi (nmcli):
  GET  /wifi/status        radio state + currently connected network
  GET  /wifi/scan          networks available nearby
  GET  /wifi/saved         previously saved networks
  POST /wifi/connect       {ssid, password?}  connects (or creates+connects)
  POST /wifi/disconnect    disconnects the current network
  POST /wifi/forget        {ssid}  forgets a saved network
  POST /wifi/toggle        {on: bool}  turns Wi-Fi on/off

Bluetooth (BlueZ via dbus_next, system bus):
  GET  /bt/status          adapter on? discovering?
  POST /bt/toggle          {on: bool}  turns Bluetooth on/off
  GET  /bt/devices         known devices (paired and not)
  POST /bt/scan            {on: bool}  starts/stops discovery
  POST /bt/pair            {address}  pairs a device
  POST /bt/connect         {address}  connects a paired device
  POST /bt/disconnect      {address}  disconnects a device
  POST /bt/forget          {address}  removes a paired device

Bluetooth audio from the phone (AVRCP, org.bluez.MediaPlayer1):
  GET  /bt/player          track playing from the connected phone
                           {available, device, is_playing, status, track:{title,
                            subtitle, album, cover}, progress_ms, duration_ms}
  POST /bt/player/play | /pause | /next | /prev   commands to the phone
  GET  /bt/player/pause?state=1                    compatible with the other music
                                                   services (1=pause, 0=play)

Requirements: pip install --break-system-packages dbus-next flask
              NetworkManager (nmcli) and BlueZ must already be installed/active
              (they are the standard stack of Debian/Ubuntu Desktop).
"""
import asyncio
import subprocess
import sys
import threading
import time

from flask import Flask, jsonify, request

app = Flask(__name__)
from local_security import protect
protect(app)
PORT = 9097


def log(*a):
    print("[netsettings]", *a, file=sys.stderr, flush=True)


# ════════════════════════ WI-FI (nmcli, sincrono) ════════════════════════

def _nmcli(args, timeout=15):
    """Esegue nmcli e ritorna (returncode, stdout, stderr)."""
    try:
        r = subprocess.run(
            ["nmcli"] + args,
            capture_output=True, text=True, timeout=timeout
        )
        return r.returncode, r.stdout, r.stderr
    except FileNotFoundError:
        return -1, "", "nmcli not found — install network-manager"
    except subprocess.TimeoutExpired:
        return -1, "", "timeout"


def _wifi_device_name():
    """Finds the name of the Wi-Fi device (e.g. wlan0) — it may not always be
    that one, better to ask NetworkManager instead of taking it for granted."""
    rc, out, _ = _nmcli(["-t", "-f", "DEVICE,TYPE", "dev", "status"])
    if rc != 0:
        return None
    for line in out.strip().splitlines():
        parts = line.split(":")
        if len(parts) >= 2 and parts[1] == "wifi":
            return parts[0]
    return None


@app.route("/wifi/status")
def wifi_status():
    rc, out, err = _nmcli(["-t", "-f", "WIFI", "radio"])
    radio_on = rc == 0 and out.strip().lower().startswith("enabled")

    connected_ssid = None
    signal = None
    dev = _wifi_device_name()
    if dev and radio_on:
        rc2, out2, _ = _nmcli(["-t", "-f", "GENERAL.STATE,GENERAL.CONNECTION", "dev", "show", dev])
        if rc2 == 0:
            info = {}
            for line in out2.strip().splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    info[k] = v
            state = info.get("GENERAL.STATE", "")
            conn = info.get("GENERAL.CONNECTION", "")
            if conn and conn != "--" and "connected" in state.lower():
                connected_ssid = conn
                # signal of the current network, if available in the scan list
                rc3, out3, _ = _nmcli(["-t", "-f", "IN-USE,SIGNAL,SSID", "dev", "wifi", "list"])
                if rc3 == 0:
                    for line in out3.strip().splitlines():
                        parts = line.split(":")
                        if len(parts) >= 3 and parts[0] == "*":
                            try: signal = int(parts[1])
                            except: pass
                            break

    return jsonify({
        "radioOn": radio_on,
        "connected": connected_ssid,
        "signal": signal,
        "available": dev is not None,
    })


@app.route("/wifi/scan")
def wifi_scan():
    dev = _wifi_device_name()
    if not dev:
        return jsonify({"networks": [], "error": "no Wi-Fi adapter found"})

    # An explicit rescan before reading, for fresh data (we ignore
    # the outcome: if NetworkManager has already scanned recently it refuses it,
    # it is not a real error).
    _nmcli(["dev", "wifi", "rescan"], timeout=5)
    time.sleep(1.2)  # minimum time for the rescan to produce results

    rc, out, err = _nmcli(["-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list"])
    if rc != 0:
        return jsonify({"networks": [], "error": err or "scan fallita"})

    seen = set()
    networks = []
    for line in out.strip().splitlines():
        # nmcli -t separates with ":" but the SSID field may contain it — it is not
        # 100% perfect with exotic SSIDs, but it covers the vast
        # majority of real cases.
        parts = line.split(":")
        if len(parts) < 4:
            continue
        in_use, ssid, signal, security = parts[0], parts[1], parts[2], ":".join(parts[3:])
        if not ssid or ssid in seen:
            continue
        seen.add(ssid)
        try:
            sig = int(signal)
        except Exception:
            sig = 0
        networks.append({
            "ssid": ssid,
            "signal": sig,
            "secured": bool(security and security != "--"),
            "connected": in_use == "*",
        })
    networks.sort(key=lambda n: -n["signal"])
    return jsonify({"networks": networks})


@app.route("/wifi/saved")
def wifi_saved():
    rc, out, err = _nmcli(["-t", "-f", "NAME,TYPE", "con", "show"])
    if rc != 0:
        return jsonify({"saved": []})
    saved = []
    for line in out.strip().splitlines():
        parts = line.split(":")
        if len(parts) >= 2 and parts[1] in ("802-11-wireless", "wifi"):
            saved.append(parts[0])
    return jsonify({"saved": saved})


@app.route("/wifi/connect", methods=["POST"])
def wifi_connect():
    data = request.get_json(silent=True) or {}
    ssid = (data.get("ssid") or "").strip()
    password = data.get("password") or ""
    if not ssid:
        return jsonify({"ok": False, "message": "SSID mancante"}), 400

    args = ["dev", "wifi", "connect", ssid]
    if password:
        args += ["password", password]
    rc, out, err = _nmcli(args, timeout=25)
    if rc == 0:
        return jsonify({"ok": True})
    return jsonify({"ok": False, "message": err.strip() or out.strip() or "connessione fallita"}), 400


@app.route("/wifi/disconnect", methods=["POST"])
def wifi_disconnect():
    dev = _wifi_device_name()
    if not dev:
        return jsonify({"ok": False, "message": "no Wi-Fi adapter"}), 400
    rc, out, err = _nmcli(["dev", "disconnect", dev])
    return jsonify({"ok": rc == 0, "message": err.strip() if rc != 0 else ""})


@app.route("/wifi/forget", methods=["POST"])
def wifi_forget():
    data = request.get_json(silent=True) or {}
    ssid = (data.get("ssid") or "").strip()
    if not ssid:
        return jsonify({"ok": False, "message": "SSID mancante"}), 400
    rc, out, err = _nmcli(["con", "delete", ssid])
    return jsonify({"ok": rc == 0, "message": err.strip() if rc != 0 else ""})


@app.route("/wifi/toggle", methods=["POST"])
def wifi_toggle():
    data = request.get_json(silent=True) or {}
    on = bool(data.get("on", True))
    rc, out, err = _nmcli(["radio", "wifi", "on" if on else "off"])
    return jsonify({"ok": rc == 0, "message": err.strip() if rc != 0 else ""})


# ═══════════════ BLUETOOTH (BlueZ via dbus_next, asincrono) ═══════════════
# Flask is synchronous, dbus_next is asynchronous: we keep a dedicated asyncio loop
# in a separate thread and every Flask endpoint submits a coroutine to it
# waiting for the result — same approach, same D-Bus interfaces
# (org.bluez.Adapter1 / Device1) already used and tested in phone_service.py.

_bt_loop = None
_bt_loop_ready = threading.Event()

def _start_bt_loop():
    global _bt_loop
    _bt_loop = asyncio.new_event_loop()
    asyncio.set_event_loop(_bt_loop)
    _bt_loop_ready.set()
    _bt_loop.run_forever()

threading.Thread(target=_start_bt_loop, daemon=True).start()
_bt_loop_ready.wait(timeout=5)


def bt_run(coro, timeout=20):
    """Runs a coroutine on the dedicated D-Bus loop and waits for the result
    (called from a synchronous Flask handler)."""
    fut = asyncio.run_coroutine_threadsafe(coro, _bt_loop)
    return fut.result(timeout=timeout)


async def _get_bus():
    from dbus_next.aio import MessageBus
    from dbus_next.constants import BusType
    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    return bus


# ── Bluetooth events: instead of asking for the state every second, the UI waits here ──
# A permanent D-Bus connection listens to BlueZ signals (device connected/
# disconnected, track changed, play/pause, new devices) and advances a counter.
# /bt/wait?v=N answers as soon as the counter exceeds N, after 25 s at most.
_bt_ev = {"v": 0}
_bt_ev_cond = threading.Condition()

def _bt_bump():
    with _bt_ev_cond:
        _bt_ev["v"] += 1
        _bt_ev_cond.notify_all()

async def _bt_watch():
    from dbus_next import Message, MessageType
    while True:
        try:
            bus = await _get_bus()
            def on_msg(msg):
                if msg.message_type == MessageType.SIGNAL and msg.member in (
                        "PropertiesChanged", "InterfacesAdded", "InterfacesRemoved"):
                    _bt_bump()
            bus.add_message_handler(on_msg)
            await bus.call(Message(destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
                                   interface="org.freedesktop.DBus", member="AddMatch",
                                   signature="s", body=["type='signal',sender='org.bluez'"]))
            _bt_bump()                       # (re)connected: the UI re-reads everything
            await bus.wait_for_disconnect()
        except Exception as e:
            print("[netsettings] ascolto Bluetooth interrotto:", e, flush=True)
        await asyncio.sleep(5)               # BlueZ restarted or bus dropped: try again

asyncio.run_coroutine_threadsafe(_bt_watch(), _bt_loop)

@app.route("/bt/wait")
def bt_wait():
    try: since = int(request.args.get("v", "-1"))
    except ValueError: since = -1
    with _bt_ev_cond:
        _bt_ev_cond.wait_for(lambda: _bt_ev["v"] != since, timeout=25)
        return jsonify({"v": _bt_ev["v"]})


async def _get_adapter_path(bus):
    """Finds the path of the first Bluetooth adapter (e.g. /org/bluez/hci0)."""
    introspection = await bus.introspect("org.bluez", "/")
    obj = bus.get_proxy_object("org.bluez", "/", introspection)
    om = obj.get_interface("org.freedesktop.DBus.ObjectManager")
    objects = await om.call_get_managed_objects()
    for path, ifaces in objects.items():
        if "org.bluez.Adapter1" in ifaces:
            return path
    return None


async def _bt_status():
    bus = await _get_bus()
    try:
        adapter_path = await _get_adapter_path(bus)
        if not adapter_path:
            return {"available": False, "poweredOn": False, "discovering": False}
        introspection = await bus.introspect("org.bluez", adapter_path)
        obj = bus.get_proxy_object("org.bluez", adapter_path, introspection)
        props = obj.get_interface("org.freedesktop.DBus.Properties")
        powered = await props.call_get("org.bluez.Adapter1", "Powered")
        discovering = await props.call_get("org.bluez.Adapter1", "Discovering")
        return {
            "available": True,
            "poweredOn": bool(powered.value),
            "discovering": bool(discovering.value),
        }
    finally:
        bus.disconnect()


@app.route("/bt/status")
def bt_status():
    try:
        return jsonify(bt_run(_bt_status()))
    except Exception as e:
        log("bt_status err:", repr(e))
        return jsonify({"available": False, "poweredOn": False, "discovering": False, "error": str(e)})


async def _bt_toggle(on):
    bus = await _get_bus()
    try:
        adapter_path = await _get_adapter_path(bus)
        if not adapter_path:
            return False
        introspection = await bus.introspect("org.bluez", adapter_path)
        obj = bus.get_proxy_object("org.bluez", adapter_path, introspection)
        props = obj.get_interface("org.freedesktop.DBus.Properties")
        from dbus_next import Variant
        await props.call_set("org.bluez.Adapter1", "Powered", Variant("b", bool(on)))
        return True
    finally:
        bus.disconnect()


@app.route("/bt/toggle", methods=["POST"])
def bt_toggle():
    data = request.get_json(silent=True) or {}
    on = bool(data.get("on", True))
    try:
        ok = bt_run(_bt_toggle(on))
        return jsonify({"ok": ok})
    except Exception as e:
        log("bt_toggle err:", repr(e))
        return jsonify({"ok": False, "message": str(e)}), 500


async def _bt_devices():
    bus = await _get_bus()
    try:
        introspection = await bus.introspect("org.bluez", "/")
        obj = bus.get_proxy_object("org.bluez", "/", introspection)
        om = obj.get_interface("org.freedesktop.DBus.ObjectManager")
        objects = await om.call_get_managed_objects()
        devices = []
        for path, ifaces in objects.items():
            dev = ifaces.get("org.bluez.Device1")
            if not dev:
                continue
            # bt_skip_unnamed: unpaired devices without a name (beacons) are not needed
            if not (dev.get("Paired") and dev.get("Paired").value) and not dev.get("Name"):
                continue
            devices.append({
                "address": dev.get("Address").value if dev.get("Address") else "",
                "name": dev.get("Name").value if dev.get("Name") else (dev.get("Alias").value if dev.get("Alias") else "Dispositivo sconosciuto"),
                "paired": bool(dev.get("Paired").value) if dev.get("Paired") else False,
                "connected": bool(dev.get("Connected").value) if dev.get("Connected") else False,
                "trusted": bool(dev.get("Trusted").value) if dev.get("Trusted") else False,
                "rssi": dev.get("RSSI").value if dev.get("RSSI") else None,
                # "phone", "audio-headset", "computer", ... (to choose the icon)
                "icon": dev.get("Icon").value if dev.get("Icon") else "",
                "path": path,
            })
        # Paired first, then by name
        devices.sort(key=lambda d: (not d["paired"], d["name"].lower()))
        return devices
    finally:
        bus.disconnect()


@app.route("/bt/devices")
def bt_devices():
    try:
        return jsonify({"devices": bt_run(_bt_devices())})
    except Exception as e:
        log("bt_devices err:", repr(e))
        return jsonify({"devices": [], "error": str(e)})


_bt_scan_bus = None   # D-Bus connection that keeps discovery alive (BlueZ stops it if it closes)


async def _bt_scan(on):
    global _bt_scan_bus
    old, _bt_scan_bus = _bt_scan_bus, None
    if old is not None:
        try: old.disconnect()
        except Exception: pass
    bus = await _get_bus()
    keep = False
    try:
        adapter_path = await _get_adapter_path(bus)
        if not adapter_path:
            return False
        introspection = await bus.introspect("org.bluez", adapter_path)
        obj = bus.get_proxy_object("org.bluez", adapter_path, introspection)
        adapter = obj.get_interface("org.bluez.Adapter1")
        if on:
            try:
                from dbus_next import Variant
                await adapter.call_set_discovery_filter({"Transport": Variant("s", "auto")})
            except Exception as e:
                log("bt_scan filtro:", repr(e))
            try:
                await adapter.call_start_discovery()
            except Exception as e:
                if "InProgress" not in repr(e) and "in progress" not in repr(e).lower():
                    raise
            keep = True
            _bt_scan_bus = bus
        else:
            try: await adapter.call_stop_discovery()
            except Exception as e: log("bt_scan stop:", repr(e))
        return True
    finally:
        if not keep:
            try: bus.disconnect()
            except Exception: pass


@app.route("/bt/scan", methods=["POST"])
def bt_scan():
    data = request.get_json(silent=True) or {}
    on = bool(data.get("on", True))
    try:
        ok = bt_run(_bt_scan(on))
        return jsonify({"ok": ok})
    except Exception as e:
        log("bt_scan err:", repr(e))
        return jsonify({"ok": False, "message": str(e)}), 500


# ── bt_agent_v2: BlueZ pairing agent that shows the PIN to the user ──
_BT_AGENT_PATH = "/volta/btagent"
_bt_agent_bus = None
_bt_pair_req = None     # richiesta in corso, letta dall'interfaccia: {"id","kind","device","passkey","t"}
_bt_pair_fut = None
_bt_pair_seq = 0


def _bt_pair_clear():
    global _bt_pair_req
    _bt_pair_req = None


async def _bt_pair_ask(kind, device, passkey=None, timeout=60):
    """Shows the request to the user and waits for Confirm/Cancel (True/False)."""
    global _bt_pair_req, _bt_pair_fut, _bt_pair_seq
    fut = asyncio.get_running_loop().create_future()
    _bt_pair_seq += 1
    _bt_pair_fut = fut
    _bt_pair_req = {"id": _bt_pair_seq, "kind": kind, "device": str(device),
                    "passkey": passkey, "t": time.time()}
    try:
        return await asyncio.wait_for(fut, timeout)
    except asyncio.TimeoutError:
        return False
    finally:
        _bt_pair_req = None
        _bt_pair_fut = None


async def _bt_dev_icon(device):
    """Device type according to BlueZ (e.g. «audio-headset», «phone»); empty if it cannot be read."""
    try:
        bus = _bt_agent_bus
        intro = await asyncio.wait_for(bus.introspect("org.bluez", str(device)), 2)
        obj = bus.get_proxy_object("org.bluez", str(device), intro)
        props = obj.get_interface("org.freedesktop.DBus.Properties")
        v = await asyncio.wait_for(props.call_get("org.bluez.Device1", "Icon"), 2)
        return str(v.value)
    except Exception as e:
        log("bt icona:", repr(e))
        return ""


def _make_bt_agent():
    from dbus_next.service import ServiceInterface, method
    from dbus_next.errors import DBusError

    class VoltaAgent(ServiceInterface):
        def __init__(self):
            super().__init__("org.bluez.Agent1")

        @method()
        def Release(self):
            _bt_pair_clear()

        @method()
        async def RequestPinCode(self, device: 'o') -> 's':
            # bt_pin_random: random PIN shown on the page; 0000 only for audio (headphones, speakers)
            global _bt_pair_req
            icon = await _bt_dev_icon(device)
            if icon.startswith("audio"):
                return "0000"
            import random
            pin = "%06d" % random.randint(0, 999999)
            _bt_pair_req = {"id": 0, "kind": "display", "device": str(device), "passkey": pin, "t": time.time()}
            return pin

        @method()
        def DisplayPinCode(self, device: 'o', pincode: 's'):
            global _bt_pair_req
            _bt_pair_req = {"id": 0, "kind": "display", "device": str(device), "passkey": str(pincode), "t": time.time()}

        @method()
        def RequestPasskey(self, device: 'o') -> 'u':
            return 0

        @method()
        def DisplayPasskey(self, device: 'o', passkey: 'u', entered: 'q'):
            global _bt_pair_req
            _bt_pair_req = {"id": 0, "kind": "display", "device": str(device), "passkey": "%06d" % passkey, "t": time.time()}

        @method()
        async def RequestConfirmation(self, device: 'o', passkey: 'u'):
            if not await _bt_pair_ask("confirm", device, "%06d" % passkey):
                raise DBusError("org.bluez.Error.Rejected", "Associazione rifiutata")

        @method()
        async def RequestAuthorization(self, device: 'o'):
            if not await _bt_pair_ask("authorize", device):
                raise DBusError("org.bluez.Error.Rejected", "Associazione rifiutata")

        @method()
        def AuthorizeService(self, device: 'o', uuid: 's'):
            pass

        @method()
        def Cancel(self):
            _bt_pair_clear()
            f = _bt_pair_fut
            if f is not None and not f.done():
                f.set_result(False)

    return VoltaAgent()


async def _bt_prepare_pair():
    """Stops the scan and makes sure our agent is the default one."""
    global _bt_scan_bus, _bt_agent_bus
    _bt_pair_clear()
    try:
        old, _bt_scan_bus = _bt_scan_bus, None
        if old is not None:
            old.disconnect()
    except Exception as e:
        log("bt_prepare scan:", repr(e))
    try:
        if _bt_agent_bus is not None and getattr(_bt_agent_bus, "connected", False):
            return
        bus = await _get_bus()
        bus.export(_BT_AGENT_PATH, _make_bt_agent())
        introspection = await bus.introspect("org.bluez", "/org/bluez")
        obj = bus.get_proxy_object("org.bluez", "/org/bluez", introspection)
        mgr = obj.get_interface("org.bluez.AgentManager1")
        try:
            await mgr.call_register_agent(_BT_AGENT_PATH, "DisplayYesNo")
        except Exception as e:
            if "AlreadyExists" not in repr(e):
                raise
        await mgr.call_request_default_agent(_BT_AGENT_PATH)
        _bt_agent_bus = bus
        log("bt agente registrato")
    except Exception as e:
        log("bt agente err:", repr(e))


@app.route("/bt/pair/request")
def bt_pair_request():
    r = _bt_pair_req
    if r and r.get("kind") == "display" and time.time() - r.get("t", 0) > 90:
        r = None
    return jsonify({"request": r})


@app.route("/bt/pair/answer", methods=["POST"])
def bt_pair_answer():
    data = request.get_json(silent=True) or {}
    accept = bool(data.get("accept"))
    fut = _bt_pair_fut
    if fut is None or fut.done() or _bt_loop is None:
        _bt_pair_clear()
        return jsonify({"ok": False})
    _bt_loop.call_soon_threadsafe(lambda: (not fut.done()) and fut.set_result(accept))
    return jsonify({"ok": True})


def _device_path_from_address(adapter_path, address):
    return f"{adapter_path}/dev_{address.replace(':', '_')}"


async def _bt_device_action(address, action):
    """action: 'pair' | 'connect' | 'disconnect' | 'forget'"""
    bus = await _get_bus()
    try:
        adapter_path = await _get_adapter_path(bus)
        if not adapter_path:
            return False, "no adapter"
        dev_path = _device_path_from_address(adapter_path, address)

        if action == "forget":
            introspection = await bus.introspect("org.bluez", adapter_path)
            obj = bus.get_proxy_object("org.bluez", adapter_path, introspection)
            adapter = obj.get_interface("org.bluez.Adapter1")
            await adapter.call_remove_device(dev_path)
            return True, ""

        introspection = await bus.introspect("org.bluez", dev_path)
        obj = bus.get_proxy_object("org.bluez", dev_path, introspection)
        device = obj.get_interface("org.bluez.Device1")
        if action == "pair":
            await _bt_prepare_pair()
            await device.call_pair()
            _bt_pair_clear()
            try:
                from dbus_next import Variant
                _pp = obj.get_interface("org.freedesktop.DBus.Properties")
                await _pp.call_set("org.bluez.Device1", "Trusted", Variant("b", True))
            except Exception as _e:
                log("bt trust err:", repr(_e))
            # After pairing we usually connect right away, so the
            # device is usable without a second tap.
            try: await device.call_connect()
            except Exception: pass
        elif action == "connect":
            await device.call_connect()
        elif action == "disconnect":
            await device.call_disconnect()
        return True, ""
    except Exception as e:
        return False, str(e)
    finally:
        bus.disconnect()


def _bt_action_route(action):
    data = request.get_json(silent=True) or {}
    address = (data.get("address") or "").strip()
    if not address:
        return jsonify({"ok": False, "message": "address mancante"}), 400
    try:
        ok, msg = bt_run(_bt_device_action(address, action), timeout=90)
        return jsonify({"ok": ok, "message": msg})
    except Exception as e:
        log(f"bt_{action} err:", repr(e))
        return jsonify({"ok": False, "message": str(e)}), 500


@app.route("/bt/pair", methods=["POST"])
def bt_pair(): return _bt_action_route("pair")

@app.route("/bt/connect", methods=["POST"])
def bt_connect(): return _bt_action_route("connect")

@app.route("/bt/disconnect", methods=["POST"])
def bt_disconnect(): return _bt_action_route("disconnect")

@app.route("/bt/forget", methods=["POST"])
def bt_forget(): return _bt_action_route("forget")


# ════════════════════ AUDIO BLUETOOTH (AVRCP) ════════════════════
# When the phone plays music over Bluetooth (A2DP), BlueZ exposes an
# org.bluez.MediaPlayer1 object under the device (…/dev_XX/playerN) with
# track, state and position, and the Play/Pause/Next/Previous methods.

_player_cache = {"t": 0.0, "data": None}
PLAYER_CACHE_TTL = 0.5   # absorbs the UI polling + AudioFocus


def _v(x, default=None):
    return x.value if x is not None and hasattr(x, "value") else (x if x is not None else default)


async def _find_player(bus):
    """(player_path, device_name) of the first MediaPlayer1 of a connected device."""
    introspection = await bus.introspect("org.bluez", "/")
    obj = bus.get_proxy_object("org.bluez", "/", introspection)
    om = obj.get_interface("org.freedesktop.DBus.ObjectManager")
    objects = await om.call_get_managed_objects()
    best = None
    for path, ifaces in objects.items():
        mp = ifaces.get("org.bluez.MediaPlayer1")
        if not mp:
            continue
        dev_path = path.rsplit("/", 1)[0]
        dev = objects.get(dev_path, {}).get("org.bluez.Device1", {})
        if dev and not _v(dev.get("Connected"), False):
            continue
        name = _v(dev.get("Alias")) or _v(dev.get("Name")) or "Telefono"
        status = _v(mp.get("Status"), "stopped")
        cand = (path, name, mp)
        # Prefer the player that is playing
        if best is None or status == "playing":
            best = cand
    return best


async def _bt_player_state():
    bus = await _get_bus()
    try:
        found = await _find_player(bus)
        if not found:
            return {"available": False, "is_playing": False, "track": None,
                    "progress_ms": 0, "duration_ms": 1, "device": ""}
        path, dev_name, mp = found
        track = _v(mp.get("Track"), {}) or {}
        title = _v(track.get("Title"), "") or ""
        artist = _v(track.get("Artist"), "") or ""
        album = _v(track.get("Album"), "") or ""
        duration = int(_v(track.get("Duration"), 0) or 0)
        status = _v(mp.get("Status"), "stopped") or "stopped"
        position = int(_v(mp.get("Position"), 0) or 0)
        return {
            "available": True,
            "device": dev_name,
            "status": status,
            "is_playing": status == "playing",
            "track": ({"id": title + "|" + artist, "title": title, "subtitle": artist,
                       "album": album, "cover": ""} if title else None),
            "progress_ms": position,
            "duration_ms": duration if duration > 0 else 1,
            "queue": [],
        }
    finally:
        bus.disconnect()


async def _bt_player_cmd(cmd):
    bus = await _get_bus()
    try:
        found = await _find_player(bus)
        if not found:
            return False
        path = found[0]
        introspection = await bus.introspect("org.bluez", path)
        obj = bus.get_proxy_object("org.bluez", path, introspection)
        mp = obj.get_interface("org.bluez.MediaPlayer1")
        if cmd == "play":   await mp.call_play()
        elif cmd == "pause": await mp.call_pause()
        elif cmd == "next":  await mp.call_next()
        elif cmd == "prev":  await mp.call_previous()
        _player_cache["t"] = 0.0   # stato cambiato: niente cache vecchia
        return True
    finally:
        bus.disconnect()


@app.route("/bt/player")
@app.route("/bt/player/status")
def bt_player():
    now = time.time()
    if _player_cache["data"] is not None and now - _player_cache["t"] < PLAYER_CACHE_TTL:
        return jsonify(_player_cache["data"])
    try:
        data = bt_run(_bt_player_state(), timeout=5)
    except Exception as e:
        log("bt_player err:", repr(e))
        data = {"available": False, "is_playing": False, "track": None,
                "progress_ms": 0, "duration_ms": 1, "device": "", "error": str(e)}
    _player_cache["data"] = data
    _player_cache["t"] = now
    return jsonify(data)


@app.route("/bt/player/<cmd>", methods=["GET", "POST"])
def bt_player_cmd(cmd):
    if cmd == "pause" and request.args.get("state") is not None:
        cmd = "pause" if request.args.get("state") == "1" else "play"
    if cmd not in ("play", "pause", "next", "prev"):
        return jsonify({"ok": False, "message": "comando sconosciuto"}), 400
    try:
        ok = bt_run(_bt_player_cmd(cmd), timeout=8)
        return jsonify({"ok": ok, "paused": cmd == "pause"})
    except Exception as e:
        log(f"bt_player {cmd} err:", repr(e))
        return jsonify({"ok": False, "message": str(e)}), 500


if __name__ == "__main__":
    log(f"Real Wi-Fi + Bluetooth on http://127.0.0.1:{PORT}")
    app.run(host="127.0.0.1", port=PORT, threaded=True)
