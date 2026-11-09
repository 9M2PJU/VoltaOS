#!/usr/bin/env python3
"""
phone_service.py — Bridge between the Bluetooth phone and the Qt UI.

Tasks:
  1. PBAP via BlueZ obexd: downloads the address book and call history when the
     phone connects. The vCards are parsed and made available
     via DBus (com.volta.Phone.GetContacts / GetRecentCalls).
  2. HFP via PipeWire (org.pipewire.Telephony, oFono-compatible API):
     - Listens to CallAdded / CallRemoved to notify the UI when a
       call arrives (IncomingCall signal) or ends (CallEnded).
     - Exposes Dial(number), Answer(), Hangup() as DBus methods for the UI.

Auto-reconnection: if the phone disconnects/reconnects, the service
automatically downloads the contacts again and stays attached to the PipeWire modem.

Requirements:
    pip install --break-system-packages dbus-next  vobject
    (bluez-obexd must be installed: sudo apt install bluez-obexd)
"""
import asyncio
import json
import os
import re
import time
from pathlib import Path

try:
    import vobject  # parser vCard completo (consigliato)
    HAVE_VOBJECT = True
except ImportError:
    vobject = None
    HAVE_VOBJECT = False
    print("[phone] 'vobject' not installed — using the internal vCard parser.")
    print("[phone] For more robust parsing: pip install --break-system-packages vobject")

from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method, signal, dbus_property
from dbus_next.constants import BusType, PropertyAccess
from dbus_next import Variant

BLUEZ_BUS   = "org.bluez"
OBEX_BUS    = "org.bluez.obex"
OBEX_PATH   = "/org/bluez/obex"
OFONO_PATH  = "/org/pipewire/Telephony"    # PipeWire espone API oFono-like
OFONO_BUS   = "org.pipewire.Telephony"

# Cache file (avoids downloading the address book again at every start)
CACHE_DIR   = Path.home() / ".cache" / "volta-phone"
CACHE_CONTACTS = CACHE_DIR / "contacts.json"
CACHE_CALLS    = CACHE_DIR / "recent_calls.json"

# Bus name exposed by the Qt UI
UI_BUS      = "com.volta.Phone"
UI_PATH     = "/com/volta/Phone"

def log(*a):
    print("[phone]", *a, flush=True)


# ═════════════════════════════════════════════════════════════════════
# PBAP (Phonebook Access Profile) — contatti e cronologia via BlueZ obex
# ═════════════════════════════════════════════════════════════════════

class PbapClient:
    """PBAP client that downloads the address book and history as vCards, parses them,
    and exposes them as Python lists."""

    def __init__(self, bus: MessageBus):
        self.bus = bus
        self.contacts: list[dict] = []
        self.recent_calls: list[dict] = []
        self._load_cache()

    def _load_cache(self):
        try:
            if CACHE_CONTACTS.exists():
                self.contacts = json.loads(CACHE_CONTACTS.read_text())
                log(f"cache: {len(self.contacts)} contatti caricati")
        except Exception as e:
            log("cache contatti err:", e)
        try:
            if CACHE_CALLS.exists():
                self.recent_calls = json.loads(CACHE_CALLS.read_text())
        except Exception as e:
            log("cache calls err:", e)

    def _save_cache(self):
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        CACHE_CONTACTS.write_text(json.dumps(self.contacts, ensure_ascii=False, indent=1))
        CACHE_CALLS.write_text(json.dumps(self.recent_calls, ensure_ascii=False, indent=1))

    async def download(self, device_addr: str, on_updated=None):
        """Downloads address book + history from the phone `device_addr`.
        on_updated: optional callback invoked after the update."""
        log(f"downloading address book from {device_addr}…")
        # 1. Crea sessione OBEX PBAP
        obex_intro = await self.bus.introspect(OBEX_BUS, OBEX_PATH, timeout=30.0)
        obex_obj   = self.bus.get_proxy_object(OBEX_BUS, OBEX_PATH, obex_intro)
        client_if  = obex_obj.get_interface("org.bluez.obex.Client1")
        try:
            session_path = await client_if.call_create_session(
                device_addr, {"Target": Variant("s", "pbap")})
        except Exception as e:
            log("CreateSession PBAP error:", e)
            return False
        log("sessione PBAP:", session_path)

        try:
            sess_intro = await self.bus.introspect(OBEX_BUS, session_path, timeout=30.0)
            sess_obj   = self.bus.get_proxy_object(OBEX_BUS, session_path, sess_intro)
            pbap       = sess_obj.get_interface("org.bluez.obex.PhonebookAccess1")

            # 2. Rubrica principale
            try:
                await pbap.call_select("int", "PB")
                # PullAll(target_file, filters) — target_file="" = ritorno inline
                filters = {"Format": Variant("s", "vcard30")}
                transfer_path, props = await pbap.call_pull_all("", filters)
                vcf = await self._wait_transfer(transfer_path, props)
                if vcf:
                    self.contacts = self._parse_vcards(vcf)
                    log(f"rubrica: {len(self.contacts)} contatti")
            except Exception as e:
                log("address book pull error:", e)

            # 3. Cronologia chiamate (combined: incoming + outgoing + missed)
            try:
                await pbap.call_select("int", "cch")
                filters = {"Format": Variant("s", "vcard30")}
                transfer_path, props = await pbap.call_pull_all("", filters)
                vcf = await self._wait_transfer(transfer_path, props)
                if vcf:
                    self.recent_calls = self._parse_call_history(vcf)
                    log(f"cronologia: {len(self.recent_calls)} chiamate")
            except Exception as e:
                log("history not available (iPhones often block it):", e)

            self._save_cache()
            if on_updated:
                on_updated()
            return True
        finally:
            try:
                await client_if.call_remove_session(session_path)
            except Exception:
                pass

    async def _wait_transfer(self, transfer_path, initial_props):
        """Waits for the completion of an OBEX transfer and returns
        the downloaded vCard content."""
        filename = initial_props.get("Filename")
        if isinstance(filename, Variant):
            filename = filename.value
        if not filename:
            log("no filename in transfer_props")
            return None

        # Listens to PropertiesChanged on the transfer to know when it is "complete"
        loop = asyncio.get_event_loop()
        done = loop.create_future()

        intro = await self.bus.introspect(OBEX_BUS, transfer_path, timeout=30.0)
        obj   = self.bus.get_proxy_object(OBEX_BUS, transfer_path, intro)
        props_if = obj.get_interface("org.freedesktop.DBus.Properties")

        def on_props(interface, changed, invalidated):
            status = changed.get("Status")
            if isinstance(status, Variant):
                status = status.value
            if status in ("complete", "error") and not done.done():
                done.set_result(status)

        props_if.on_properties_changed(on_props)
        try:
            status = await asyncio.wait_for(done, timeout=30)
        except asyncio.TimeoutError:
            log("timeout transfer PBAP")
            return None
        finally:
            try:
                props_if.off_properties_changed(on_props)
            except Exception:
                pass

        if status != "complete":
            log("transfer status:", status)
            return None

        # Il file scaricato sta in ~/.cache/obexd/
        try:
            content = Path(filename).read_text(encoding="utf-8", errors="ignore")
            return content
        except Exception as e:
            log("read error", filename, ":", e)
            return None

    def _parse_vcards(self, vcf_text: str) -> list[dict]:
        if not HAVE_VOBJECT:
            return self._parse_vcards_fallback(vcf_text)
        out = []
        try:
            for v in vobject.readComponents(vcf_text):
                name = v.fn.value if hasattr(v, "fn") else ""
                phones = []
                if hasattr(v, "tel"):
                    for tel in (v.tel_list if hasattr(v, "tel_list") else [v.tel]):
                        num = self._normalize_phone(tel.value)
                        if num:
                            phones.append(num)
                if name and phones:
                    out.append({
                        "name":   name.strip(),
                        "phone":  phones[0],
                        "phones": phones,
                        "avatar": "",
                    })
        except Exception as e:
            log("vCards parsing error:", e)
        # alphabetical sort by name
        out.sort(key=lambda c: c["name"].lower())
        return out

    def _parse_vcards_fallback(self, vcf_text: str) -> list[dict]:
        """Minimal vCard parser used when 'vobject' is not installed.
        It only reads FN/N and TEL, which is all the car address book needs."""
        out = []
        for block in vcf_text.split("BEGIN:VCARD"):
            if "TEL" not in block.upper():
                continue
            name, phones = "", []
            for raw in block.splitlines():
                line = raw.strip()
                up = line.upper()
                if up.startswith("FN:") and not name:
                    name = line.split(":", 1)[1].strip()
                elif up.startswith("N:") and not name:
                    # N:Cognome;Nome;;;  → "Nome Cognome"
                    parts = line.split(":", 1)[1].split(";")
                    surname = parts[0].strip() if len(parts) > 0 else ""
                    first   = parts[1].strip() if len(parts) > 1 else ""
                    name = (first + " " + surname).strip()
                elif up.startswith("TEL"):
                    num = self._normalize_phone(line.split(":", 1)[-1])
                    if num and num not in phones:
                        phones.append(num)
            if name and phones:
                out.append({"name": name, "phone": phones[0],
                            "phones": phones, "avatar": ""})
        out.sort(key=lambda c: c["name"].lower())
        return out

    def _parse_call_history(self, vcf_text: str) -> list[dict]:
        """The PBAP history arrives as vCards with the X-IRMC-CALL-DATETIME property"""
        if not HAVE_VOBJECT:
            # Without vobject we do not read the TYPE parameters: we still show
            # name and number, without distinguishing missed/received/made.
            base = self._parse_vcards_fallback(vcf_text)
            return [{"name": c["name"], "phone": c["phone"], "time": "",
                     "type": "incoming", "missed": False} for c in base][:50]
        out = []
        try:
            for v in vobject.readComponents(vcf_text):
                name = v.fn.value if hasattr(v, "fn") else "Sconosciuto"
                phone = ""
                if hasattr(v, "tel"):
                    tel = v.tel_list[0] if hasattr(v, "tel_list") else v.tel
                    phone = self._normalize_phone(tel.value)
                # X-IRMC-CALL-DATETIME;<TYPE>:<TIMESTAMP>
                call_type = "incoming"
                timestamp = None
                for key, prop in v.contents.items():
                    if key.lower().startswith("x-irmc-call-datetime"):
                        p0 = prop[0]
                        for param_key, param_vals in p0.params.items():
                            if param_key.upper() == "TYPE":
                                t = str(param_vals[0]).upper() if param_vals else ""
                                if "MISSED" in t: call_type = "missed"
                                elif "DIALED" in t: call_type = "outgoing"
                                elif "RECEIVED" in t: call_type = "incoming"
                        timestamp = p0.value
                nm = name.strip()
                # Unsaved number: on PBAP vCards the FN sometimes matches
                # the number, other times it is empty or "Unknown". In those cases
                # we look in the contacts; if still nothing, we show the
                # number as the name so the card does not look empty.
                if (not nm or nm.lower() in ("unknown", "sconosciuto")
                        or nm == phone):
                    match = next((c["name"] for c in self.contacts
                                  if c.get("phone") == phone
                                     or phone in c.get("phones", [])), None)
                    nm = match or phone or "Sconosciuto"
                out.append({
                    "name":  nm,
                    "phone": phone,
                    "time":  self._fmt_ts(timestamp),
                    "type":  call_type,
                    "missed": call_type == "missed",
                })
        except Exception as e:
            log("history parsing error:", e)
        return out[:50]  # ultime 50 chiamate

    def _normalize_phone(self, s: str) -> str:
        return re.sub(r"[^\d+]", "", s or "")

    def _fmt_ts(self, ts: str) -> str:
        # ISO 8601: 20260722T220000
        if not ts:
            return ""
        try:
            t = time.strptime(ts[:15], "%Y%m%dT%H%M%S")
            now = time.localtime()
            if t.tm_year == now.tm_year and t.tm_yday == now.tm_yday:
                return f"Today {t.tm_hour:02d}:{t.tm_min:02d}"
            days_ago = now.tm_yday - t.tm_yday
            if 1 <= days_ago <= 6:
                return ["Yesterday","2d ago","3d ago","4d ago","5d ago","6d ago"][days_ago-1] + f" {t.tm_hour:02d}:{t.tm_min:02d}"
            return time.strftime("%d/%m %H:%M", t)
        except Exception:
            return ""


# ═════════════════════════════════════════════════════════════════════
# MAP (Message Access Profile) — SMS/messaggi via BlueZ obex
# ═════════════════════════════════════════════════════════════════════
# Exactly the same mechanism as PbapClient above (OBEX session via
# obexd), only with Target="map" instead of "pbap" and the
# MessageAccess1 interface instead of PhonebookAccess1. Conversations are obtained by
# grouping the inbox+sent messages by phone number.

CACHE_MESSAGES = CACHE_DIR / "messages.json"

class MapClient:
    """MAP client: downloads SMS from inbox/sent, groups them by conversation
    (by sender/recipient number), and allows sending new ones."""

    def __init__(self, bus: MessageBus):
        self.bus = bus
        self.conversations: list[dict] = []   # [{number, name, messages:[{text,from,time}]}]
        self._session_path: str | None = None
        self._map_iface = None
        self._device_addr: str | None = None
        self._load_cache()

    def _load_cache(self):
        try:
            if CACHE_MESSAGES.exists():
                self.conversations = json.loads(CACHE_MESSAGES.read_text())
                log(f"cache: {len(self.conversations)} conversazioni caricate")
        except Exception as e:
            log("cache messaggi err:", e)

    def _save_cache(self):
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        CACHE_MESSAGES.write_text(json.dumps(self.conversations, ensure_ascii=False, indent=1))

    async def _open_session(self, device_addr: str):
        """Opens (or reuses if already open for the same device) the MAP session —
        we keep it alive even after the initial download, it is needed for PushMessage
        when the user replies from an open app."""
        if self._session_path and self._device_addr == device_addr:
            return True
        obex_intro = await self.bus.introspect(OBEX_BUS, OBEX_PATH, timeout=30.0)
        obex_obj   = self.bus.get_proxy_object(OBEX_BUS, OBEX_PATH, obex_intro)
        client_if  = obex_obj.get_interface("org.bluez.obex.Client1")
        try:
            session_path = await client_if.call_create_session(
                device_addr, {"Target": Variant("s", "map")})
        except Exception as e:
            log("CreateSession MAP error:", e)
            return False
        sess_intro = await self.bus.introspect(OBEX_BUS, session_path, timeout=30.0)
        sess_obj   = self.bus.get_proxy_object(OBEX_BUS, session_path, sess_intro)
        self._map_iface    = sess_obj.get_interface("org.bluez.obex.MessageAccess1")
        self._session_path = session_path
        self._device_addr  = device_addr
        log("sessione MAP:", session_path)
        return True

    async def _goto_folder(self, path: str):
        """SetFolder in BlueZ MAP navigates ONE LEVEL at a time (like a `cd`),
        it does not accept a whole path with slashes in a single call —
        passing it that way gave "Bad Request". First we go back to the root
        (empty string), then we descend one folder at a time."""
        await self._map_iface.call_set_folder("")
        for segment in path.split("/"):
            if segment:
                await self._map_iface.call_set_folder(segment)

    async def download(self, device_addr: str, on_updated=None, max_per_folder: int = 60):
        """Downloads the latest messages from inbox and sent, groups them by
        number, and saves them. Keeps the session open for the next send."""
        log(f"downloading messages from {device_addr}…")
        if not await self._open_session(device_addr):
            return False

        try:
            grouped: dict[str, dict] = {}   # number -> {name, messages: [...]}
            for folder, direction in (("telecom/msg/inbox", "them"), ("telecom/msg/sent", "me")):
                try:
                    await self._goto_folder(folder)
                except Exception as e:
                    log(f"SetFolder({folder}) err:", e)
                    continue
                try:
                    filters = {"MaxCount": Variant("q", max_per_folder)}
                    entries = await self._map_iface.call_list_messages("", filters)
                except Exception as e:
                    log(f"ListMessages({folder}) err:", e)
                    continue

                for msg_path, props in entries.items():
                    number = self._prop(props, "SenderAddress" if direction == "them" else "RecipientAddress")
                    name   = self._prop(props, "Sender" if direction == "them" else "Recipient")
                    ts     = self._prop(props, "Timestamp") or ""
                    text   = self._prop(props, "Subject") or ""  # preview; the full text needs GetMessage
                    if not number:
                        continue
                    number = number.strip()
                    bucket = grouped.setdefault(number, {"number": number, "name": name or number, "messages": []})
                    if name and bucket["name"] == bucket["number"]:
                        bucket["name"] = name
                    bucket["messages"].append({
                        "text": text, "from": direction,
                        "time": self._fmt_time(ts), "_ts": ts, "_path": msg_path,
                    })

            # Sorts the messages of each conversation by timestamp, and the
            # conversations themselves by most recent message.
            convos = list(grouped.values())
            for c in convos:
                c["messages"].sort(key=lambda m: m.get("_ts") or "")
            convos.sort(key=lambda c: (c["messages"][-1]["_ts"] if c["messages"] else ""), reverse=True)

            # Union with any "local" messages (just sent by
            # send(), not yet synced from the phone in "sent"):
            # without this, the next download() erased them from the UI
            # after a few seconds, even if the sending really succeeded —
            # it looked like the message vanished into thin air.
            by_number = {c["number"]: c for c in convos}
            for old_c in self.conversations:
                local_msgs = [m for m in old_c.get("messages", []) if m.get("_local")]
                if not local_msgs:
                    continue
                fresh_texts = set()
                if old_c["number"] in by_number:
                    fresh_texts = {m["text"] for m in by_number[old_c["number"]]["messages"]}
                still_missing = [m for m in local_msgs if m["text"] not in fresh_texts]
                if not still_missing:
                    continue
                if old_c["number"] not in by_number:
                    by_number[old_c["number"]] = {"number": old_c["number"], "name": old_c["name"], "messages": []}
                    # The position does not matter here: the final sort below
                    # puts it in its place based on the real timestamp — before
                    # it was inserted fixed at the top ("insert(0, ...)"), which
                    # made it stay stuck at the top of the conversation list
                    # even when a more recent message arrived elsewhere
                    # (reported bug: a message sent from here
                    # always stayed "on top" even if older than one
                    # received later).
                    convos.append(by_number[old_c["number"]])
                by_number[old_c["number"]]["messages"].extend(still_missing)
                by_number[old_c["number"]]["messages"].sort(key=lambda m: m.get("_ts") or "")

            # Sort again AFTER the union: a local message just
            # merged may have changed which is the most recent message of
            # that conversation (the sort at line 434 comes before
            # the union, so it did not know yet).
            convos.sort(key=lambda c: (c["messages"][-1]["_ts"] if c["messages"] else ""), reverse=True)

            self.conversations = convos
            self._save_cache()
            log(f"messaggi: {len(convos)} conversazioni")
            if on_updated:
                on_updated()
            return True
        except Exception as e:
            log("MAP download error:", e)
            return False

    async def fetch_full_body(self, msg_path: str) -> str | None:
        """Downloads the full body of ONE message (ListMessages only gives
        a preview) — called when the user opens a conversation."""
        if not self._map_iface:
            return None
        try:
            tmp_target = f"/tmp/volta_msg_{int(time.time()*1000)}.bmsg"
            transfer_path, props = await self._map_iface.call_get_message(msg_path, tmp_target, {})
            content = await self._wait_transfer(transfer_path, props, tmp_target)
            if not content:
                return None
            return self._extract_bmsg_body(content)
        except Exception as e:
            log("GetMessage err:", e)
            return None

    async def send(self, number: str, text: str) -> bool:
        """Builds a minimal bMessage and sends it via PushMessage."""
        if not self._map_iface or not self._session_path:
            log("send: no MAP session open")
            return False
        bmsg = self._build_bmsg(number, text)
        tmp_path = f"/tmp/volta_send_{int(time.time()*1000)}.bmsg"
        try:
            # Same bug already found for SetFolder: after a download() the
            # session stays positioned in "sent" — passing an absolute
            # path to PushMessage with the session already elsewhere produced
            # a nonsensical navigation (relative, not from root). We
            # position explicitly in outbox BEFORE sending, then
            # passiamo "" (cartella corrente) a PushMessage.
            await self._goto_folder("telecom/msg/outbox")

            Path(tmp_path).write_text(bmsg, encoding="utf-8")
            transfer_path, props = await self._map_iface.call_push_message(
                tmp_path, "", {"Transparent": Variant("b", False)})
            await self._wait_transfer(transfer_path, props, None)
            log(f"messaggio inviato a {number}")

            # IMPORTANT: PushMessage really sends the message to the phone,
            # but does not update our local list by itself — without this,
            # the UI always showed the same data as before (it looked like
            # sending did nothing). We add the message just
            # sent directly to the right conversation, so it appears
            # right away, instead of waiting for a new full download.
            # "_local: True" protects it from the next automatic download():
            # if the phone has not yet synced "sent" (it happens, it is
            # not instant), it must not disappear from the UI meanwhile.
            now_ts = time.strftime("%Y%m%dT%H%M%S")
            bucket = next((c for c in self.conversations if c["number"] == number), None)
            if bucket is None:
                bucket = {"number": number, "name": number, "messages": []}
                self.conversations.append(bucket)
            bucket["messages"].append({
                "text": text, "from": "me", "time": self._fmt_time(now_ts), "_ts": now_ts,
                "_path": None, "_local": True,
            })
            # Sort by most recent message (same criterion as
            # download()), instead of ALWAYS moving this conversation to the
            # top "regardless" — reported bug: a message sent from
            # here stayed stuck at the top of the list even when another
            # conversation later received a more recent message.
            self.conversations.sort(key=lambda c: (c["messages"][-1]["_ts"] if c.get("messages") else ""), reverse=True)
            self._save_cache()
            return True
        except Exception as e:
            log("PushMessage err:", e)
            return False
        finally:
            try:
                os.remove(tmp_path)
            except Exception:
                pass

    # ── Helper ──────────────────────────────────────────────────────────

    @staticmethod
    def _prop(props: dict, key: str):
        v = props.get(key)
        return v.value if isinstance(v, Variant) else v

    @staticmethod
    def _fmt_time(ts: str) -> str:
        # Timestamp MAP tipico: "20260830T164523" (IrMC/vCal-like)
        m = re.match(r"^\d{8}T(\d{2})(\d{2})", ts or "")
        return f"{m.group(1)}:{m.group(2)}" if m else ""

    @staticmethod
    def _extract_bmsg_body(bmsg_text: str) -> str:
        """Extracts the text between BEGIN:MSG / END:MSG from a downloaded bMessage."""
        m = re.search(r"BEGIN:MSG\r?\n(.*?)\r?\nEND:MSG", bmsg_text, re.DOTALL)
        return m.group(1).strip() if m else ""

    @staticmethod
    def _build_bmsg(number: str, text: str) -> str:
        """Minimal bMessage for outgoing SMS (simplified IrMC/MAP spec —
        the fields phones really check are BEGIN/END and the body)."""
        body = text.replace("\r\n", "\n").replace("\n", "\r\n")
        return (
            "BEGIN:BMSG\r\n"
            "VERSION:1.0\r\n"
            "STATUS:UNREAD\r\n"
            "TYPE:SMS_GSM\r\n"
            "FOLDER:telecom/msg/outbox\r\n"
            "BEGIN:VCARD\r\n"
            "VERSION:2.1\r\n"
            "N:;;;;\r\n"
            f"TEL:{number}\r\n"
            "END:VCARD\r\n"
            "BEGIN:BENV\r\n"
            "BEGIN:BBODY\r\n"
            "CHARSET:UTF-8\r\n"
            f"LENGTH:{len(body)}\r\n"
            "BEGIN:MSG\r\n"
            f"{body}\r\n"
            "END:MSG\r\n"
            "END:BBODY\r\n"
            "END:BENV\r\n"
            "END:BMSG\r\n"
        )

    async def _wait_transfer(self, transfer_path, initial_props, forced_filename):
        """Same logic as PbapClient._wait_transfer, with optional filename
        (GetMessage/PushMessage sometimes do not put it in the initial props)."""
        filename = forced_filename
        if not filename:
            fn = initial_props.get("Filename")
            filename = fn.value if isinstance(fn, Variant) else fn
        if not filename:
            return None

        loop = asyncio.get_event_loop()
        done = loop.create_future()
        intro = await self.bus.introspect(OBEX_BUS, transfer_path, timeout=30.0)
        obj   = self.bus.get_proxy_object(OBEX_BUS, transfer_path, intro)
        props_if = obj.get_interface("org.freedesktop.DBus.Properties")

        def on_props(interface, changed, invalidated):
            status = changed.get("Status")
            if isinstance(status, Variant):
                status = status.value
            if status in ("complete", "error") and not done.done():
                done.set_result(status)

        props_if.on_properties_changed(on_props)
        try:
            status = await asyncio.wait_for(done, timeout=30)
        except asyncio.TimeoutError:
            log("timeout transfer MAP")
            return None
        finally:
            try:
                props_if.off_properties_changed(on_props)
            except Exception:
                pass

        if status != "complete":
            return None
        try:
            return Path(filename).read_text(encoding="utf-8", errors="ignore")
        except Exception as e:
            log("read error", filename, ":", e)
            return None

    async def watch_new_messages(self, on_new):
        """Live notification of incoming messages: registers the session for
        MAP notifications and re-downloads when something new arrives in the inbox.
        NOTE: NotificationRegistration is a PROPERTY of MessageAccess1 (it is
        set with Properties.Set, as we already do for Bluetooth's "Powered"
        elsewhere in this file) — not a callable method, hence
        the error 'has no attribute call_set_notification_registration'."""
        if not self._map_iface:
            return
        try:
            sess_intro = await self.bus.introspect(OBEX_BUS, self._session_path, timeout=30.0)
            sess_obj   = self.bus.get_proxy_object(OBEX_BUS, self._session_path, sess_intro)
            props_if   = sess_obj.get_interface("org.freedesktop.DBus.Properties")
            await props_if.call_set("org.bluez.obex.MessageAccess1",
                                     "NotificationRegistration", Variant("b", True))

            intro = await self.bus.introspect(OBEX_BUS, self._session_path, timeout=30.0)
            obj   = self.bus.get_proxy_object(OBEX_BUS, self._session_path, intro)
            om    = obj.get_interface("org.freedesktop.DBus.ObjectManager")

            def on_added(path, interfaces):
                if "org.bluez.obex.Message1" in interfaces:
                    log("nuovo messaggio notificato:", path)
                    if on_new:
                        on_new()
            om.on_interfaces_added(on_added)
            log("notifiche MAP registrate")
        except Exception as e:
            log("MAP notifications not available (using polling only):", e)



# ═════════════════════════════════════════════════════════════════════
# HFP tramite PipeWire Telephony (API oFono)
# ═════════════════════════════════════════════════════════════════════

class HfpClient:
    """Handles calls: Dial/Answer/Hangup + CallAdded/CallRemoved notifications."""

    def __init__(self, bus: MessageBus):
        # PipeWire Telephony lives on the SESSION (org.pipewire.Telephony)
        self.bus = bus
        self._retry_task = None
        self.modem_path: str | None = None
        self.vcm = None                     # VoiceCallManager interface
        self.active_calls: dict[str, dict] = {}  # path -> {name, number, state}

        # Callback toward the UI DBus service
        self.on_incoming_call   = None      # (name, number) -> None
        self.on_call_answered   = None
        self.on_call_ended      = None
        self.on_call_dialing    = None
        self.on_state_change    = None      # (state_str) -> None

    async def start(self):
        """Attaches the PipeWire modem and the oFono signals."""
        try:
            intro = await self.bus.introspect(OFONO_BUS, OFONO_PATH)
            mgr_obj = self.bus.get_proxy_object(OFONO_BUS, OFONO_PATH, intro)
            manager = mgr_obj.get_interface("org.ofono.Manager")
            modems = await manager.call_get_modems()
            if not modems:
                log("no PipeWire modem — phone not connected over HFP")
                return
            if isinstance(modems, dict):
                self.modem_path = next(iter(modems))
            else:
                self.modem_path = modems[0][0]
            log("modem PipeWire:", self.modem_path)

            m_intro = await self.bus.introspect(OFONO_BUS, self.modem_path)
            m_obj   = self.bus.get_proxy_object(OFONO_BUS, self.modem_path, m_intro)
            self.vcm = m_obj.get_interface("org.ofono.VoiceCallManager")

            # Segnali: chiamata aggiunta / rimossa
            # dbus-next passes the arguments (path, props) to the handler
            # synchronously. Ours is async: we need a wrapper that schedules the
            # coroutine on the loop and returns nothing.
            def _added_cb(path, props):
                asyncio.ensure_future(self._on_call_added(path, props))
            self.vcm.on_call_added(_added_cb)
            self.vcm.on_call_removed(self._on_call_removed)

            # If there are already active calls (rare), we attach to them
            try:
                calls = await self.vcm.call_get_calls()
                if isinstance(calls, dict):
                    calls = list(calls.items())
                for path, props in calls:
                    await self._on_call_added(path, props)
            except Exception as e:
                log("get_calls err:", e)
        except Exception as e:
            log(f"HFP start failed: {type(e).__name__}: {e or '(no details)'}")
            # The modem appears when WirePlumber attaches the phone in HFP.
            # Ci riproviamo periodicamente in background.
            if not self._retry_task:
                self._retry_task = asyncio.ensure_future(self._retry_loop())

    async def _retry_loop(self):
        while not self.vcm:
            await asyncio.sleep(5)
            log("HFP retry…")
            try:
                intro = await self.bus.introspect(OFONO_BUS, OFONO_PATH)
                mgr_obj = self.bus.get_proxy_object(OFONO_BUS, OFONO_PATH, intro)
                manager = mgr_obj.get_interface("org.ofono.Manager")
                modems = await manager.call_get_modems()
                if not modems:
                    continue
                # oFono GetModems returns a{oa{sv}}: dict path->props on some
                # buses, list of (path, props) tuples on others. We handle both.
                if isinstance(modems, dict):
                    self.modem_path = next(iter(modems))
                else:
                    self.modem_path = modems[0][0]
                log("modem PipeWire:", self.modem_path)
                m_intro = await self.bus.introspect(OFONO_BUS, self.modem_path)
                m_obj   = self.bus.get_proxy_object(OFONO_BUS, self.modem_path, m_intro)
                self.vcm = m_obj.get_interface("org.ofono.VoiceCallManager")
                def _added_cb(path, props):
                    asyncio.ensure_future(self._on_call_added(path, props))
                self.vcm.on_call_added(_added_cb)
                self.vcm.on_call_removed(self._on_call_removed)
                calls = await self.vcm.call_get_calls()
                if isinstance(calls, dict):
                    calls = list(calls.items())
                for path, props in calls:
                    await self._on_call_added(path, props)
                return
            except Exception as e:
                log(f"  retry err: {type(e).__name__}: {e or '(no details)'}")

    async def _on_call_added(self, path, props):
        try:
            state = props.get("State")
            if isinstance(state, Variant): state = state.value
            number = props.get("LineIdentification")
            if isinstance(number, Variant): number = number.value
            name = props.get("Name")
            if isinstance(name, Variant): name = name.value
            # Name from the address book if it does not come from the signal
            display_name = name
            if (not display_name) and number:
                display_name = next(
                    (c["name"] for c in getattr(self, '_contacts_ref', [])
                     if c.get("phone") == number
                        or number in c.get("phones", [])), None)
            self.active_calls[path] = {
                "number": number or "",
                "name":   display_name or number or "Sconosciuto",
                "state":  state or "",
            }
            log(f"call added: {path} state={state} num={number}")

            # Notifica UI
            if state == "incoming":
                if self.on_incoming_call:
                    self.on_incoming_call(name or number or "", number or "")
            elif state == "dialing" or state == "alerting":
                if self.on_call_dialing:
                    self.on_call_dialing(name or number or "", number or "")
            elif state == "active":
                if self.on_call_answered:
                    self.on_call_answered()

            # Listens to the state changes of the single call.
            # oFono espone "PropertyChanged(s, v)" sull'interfaccia
            # org.ofono.VoiceCall — much simpler than the generic
            # PropertiesChanged because ONE property arrives at a time.
            try:
                c_intro = await self.bus.introspect(OFONO_BUS, path)
                c_obj   = self.bus.get_proxy_object(OFONO_BUS, path, c_intro)
                voice_if = c_obj.get_interface("org.ofono.VoiceCall")

                def make_handler(call_path):
                    def handler(name, value):
                        # dbus-next already unwraps the Variant for us
                        if name != "State": return
                        st = value.value if isinstance(value, Variant) else value
                        log(f"  call {call_path} → {st}")
                        if call_path in self.active_calls:
                            self.active_calls[call_path]["state"] = st
                        if st == "active" and self.on_call_answered:
                            self.on_call_answered()
                        if self.on_state_change:
                            self.on_state_change(st)
                    return handler

                voice_if.on_property_changed(make_handler(path))
            except Exception as e:
                import traceback
                log("watch call err:", e)
                log("TB:\n" + traceback.format_exc())
        except Exception as e:
            import traceback
            log("on_call_added err:", e)
            log("TRACEBACK:\n" + traceback.format_exc())

    def _on_call_removed(self, path):
        log(f"call removed: {path}")
        self.active_calls.pop(path, None)
        if self.on_call_ended:
            self.on_call_ended()

    async def dial(self, number: str) -> bool:
        if not self.vcm:
            log("Dial: modem not ready")
            return False
        try:
            # PipeWire Telephony.Dial vuole 1 argomento ('s') e ritorna
            # the VoiceCall's object path ('o'). dbus-next complains if
            # we do not handle the return: we catch it this way so the signature validates.
            new_path = await self.vcm.call_dial(number)
            log(f"Dial OK, call path: {new_path}")
            return True
        except Exception as e:
            # If the return signature does not match dbus-next raises an error
            # AFTER the call has actually started: the call is
            # real, but the return value was not decoded. In that
            # case 'CallAdded' has already arrived and the UI will be updated.
            if "unexpected signature" in str(e):
                log("dial: signature mismatch (chiamata partita comunque)")
                return True
            log("dial err:", e)
            return False

    async def answer(self) -> bool:
        for path, info in list(self.active_calls.items()):
            if info.get("state") in ("incoming", "waiting"):
                try:
                    intro = await self.bus.introspect(OFONO_BUS, path)
                    obj   = self.bus.get_proxy_object(OFONO_BUS, path, intro)
                    vc    = obj.get_interface("org.ofono.VoiceCall")
                    await vc.call_answer()
                    return True
                except Exception as e:
                    log("answer err:", e)
        return False

    async def hangup(self) -> bool:
        if not self.vcm:
            return False
        try:
            await self.vcm.call_hangup_all()
            return True
        except Exception as e:
            log("hangup err:", e)
            return False


# ═════════════════════════════════════════════════════════════════════
# AUDIO BRIDGE — routes the call audio to the car's speaker/mic
# ═════════════════════════════════════════════════════════════════════
#
# Why it is needed: PipeWire exposes the phone as a Bluetooth device, but the
# card stays in the A2DP profile (music, output only). A call needs
# the HFP/HSP profile (bidirectional, with microphone). And even with the
# right profile, the audio does not reach the car's speakers by itself: they must be
# creati i loopback.
#
# Grafo costruito a chiamata attiva:
#     telefono (BT source) ──> echo-cancel ──> speaker auto
#     mic auto ──> echo-cancel (AEC ref) ──> telefono (BT sink)
#
# When the call ends everything is torn down and we go back to A2DP, so the music
# from the phone stays in high quality (HFP samples at 8/16 kHz).

class AudioBridge:
    def __init__(self):
        self.modules: list[str] = []      # ids of the loaded pactl modules
        self.card_name: str | None = None
        self.prev_profile: str | None = None
        self.active = False

    def _pactl(self, *args) -> str:
        import subprocess
        try:
            r = subprocess.run(["pactl", *args], capture_output=True,
                               text=True, timeout=6)
            return r.stdout.strip()
        except Exception as e:
            log("pactl err:", e)
            return ""

    def _find_bt_card(self) -> str | None:
        """Name of the phone's PipeWire card (e.g. bluez_card.2C_BE_...)."""
        out = self._pactl("list", "short", "cards")
        for line in out.splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1].startswith("bluez_card."):
                return parts[1]
        return None

    def _card_profiles(self, card: str) -> list[str]:
        """Lists the profiles available on the card (the names vary between
        BlueZ versions: headset-head-unit, headset-head-unit-msbc, …)."""
        out = self._pactl("list", "cards")
        profiles, in_card, in_profiles = [], False, False
        for line in out.splitlines():
            s = line.strip()
            if s.startswith("Name: "):
                in_card = (s.split("Name: ", 1)[1] == card)
                in_profiles = False
            elif in_card and s.startswith("Profiles:"):
                in_profiles = True
            elif in_card and in_profiles:
                if s.startswith("Active Profile:"):
                    in_profiles = False
                elif ":" in s:
                    profiles.append(s.split(":", 1)[0].strip())
        return profiles

    def _active_profile(self, card: str) -> str | None:
        out = self._pactl("list", "cards")
        in_card = False
        for line in out.splitlines():
            s = line.strip()
            if s.startswith("Name: "):
                in_card = (s.split("Name: ", 1)[1] == card)
            elif in_card and s.startswith("Active Profile:"):
                return s.split("Active Profile:", 1)[1].strip()
        return None

    def _pick_hfp_profile(self, profiles: list[str]) -> str | None:
        """Prefers mSBC (wideband, cleaner voice) if available."""
        for pref in ("headset-head-unit-msbc", "headset-head-unit-cvsd",
                     "headset-head-unit", "handsfree-head-unit"):
            if pref in profiles:
                return pref
        for p in profiles:
            if "head-unit" in p or "headset" in p:
                return p
        return None

    def _find_bt_streams(self) -> tuple[str | None, str | None]:
        """Bluetooth sink and source (after switching to HFP)."""
        sink = source = None
        for line in self._pactl("list", "short", "sinks").splitlines():
            p = line.split()
            if len(p) >= 2 and p[1].startswith("bluez_output."):
                sink = p[1]
        for line in self._pactl("list", "short", "sources").splitlines():
            p = line.split()
            if len(p) >= 2 and p[1].startswith("bluez_input."):
                source = p[1]
        return sink, source

    def _default_local(self) -> tuple[str | None, str | None]:
        """Sink e source locali dell'auto (altoparlanti + microfono)."""
        sink = self._pactl("get-default-sink") or None
        source = self._pactl("get-default-source") or None
        # Avoids using a Bluetooth device as "local"
        if sink and sink.startswith("bluez"):   sink = None
        if source and source.startswith("bluez"): source = None
        return sink, source

    def _load_module(self, name: str, *args) -> str | None:
        mid = self._pactl("load-module", name, *args)
        if mid and mid.isdigit():
            self.modules.append(mid)
            return mid
        log(f"load-module {name} fallito: {mid}")
        return None

    def up(self):
        """Builds the audio bridge (active call)."""
        if self.active:
            return
        card = self._find_bt_card()
        if not card:
            log("audio bridge: no Bluetooth card found")
            return
        self.card_name = card
        self.prev_profile = self._active_profile(card)

        # 1. Switch to the HFP profile (bidirectional, with microphone)
        profs = self._card_profiles(card)
        hfp = self._pick_hfp_profile(profs)
        if not hfp:
            log("audio bridge: no HFP profile on", card, "→", profs)
            return
        log(f"audio bridge: {card} {self.prev_profile} → {hfp}")
        self._pactl("set-card-profile", card, hfp)
        time.sleep(1.2)   # the HFP device takes a moment to appear

        bt_sink, bt_source = self._find_bt_streams()
        loc_sink, loc_source = self._default_local()
        if not (bt_sink and bt_source and loc_sink and loc_source):
            log("audio bridge: stream mancanti",
                f"bt_sink={bt_sink} bt_source={bt_source} "
                f"loc_sink={loc_sink} loc_source={loc_source}")
            return

        # 2. Echo cancellation between car microphone and car speakers:
        #    avoids the other party's voice coming back into the microphone.
        self._load_module(
            "module-echo-cancel",
            f"source_name=volta_aec_src", f"sink_name=volta_aec_sink",
            f"source_master={loc_source}", f"sink_master={loc_sink}",
            "aec_method=webrtc", "use_master_format=1")
        time.sleep(0.4)

        # 3. Voce dell'interlocutore → altoparlanti auto (via AEC)
        self._load_module("module-loopback",
                          f"source={bt_source}", "sink=volta_aec_sink",
                          "latency_msec=40", "source_dont_move=true",
                          "sink_dont_move=true")
        # 4. Car microphone (cleaned by AEC) → phone
        self._load_module("module-loopback",
                          "source=volta_aec_src", f"sink={bt_sink}",
                          "latency_msec=40", "source_dont_move=true",
                          "sink_dont_move=true")

        self.active = True
        log(f"audio bridge attivo ({len(self.modules)} moduli)")

    def down(self):
        """Tears down the bridge and restores A2DP for the music."""
        if not self.active and not self.modules:
            return
        for mid in reversed(self.modules):
            self._pactl("unload-module", mid)
        self.modules.clear()
        # Back to the previous profile (normally a2dp-sink)
        if self.card_name:
            target = self.prev_profile if (self.prev_profile and
                     "head-unit" not in self.prev_profile) else "a2dp-sink"
            self._pactl("set-card-profile", self.card_name, target)
            log(f"audio bridge: ripristinato profilo {target}")
        self.active = False


# ═════════════════════════════════════════════════════════════════════
# BlueZ device tracking — who is the currently connected phone?
# ═════════════════════════════════════════════════════════════════════

async def find_connected_phone(bus: MessageBus) -> str | None:
    """Returns the MAC of the first connected Bluetooth device that supports
    PBAP (Phonebook Access Server, UUID 0000112f-...).

    Expected bus: **SYSTEM bus**, because BlueZ lives there. On the session it gives
    'org.bluez was not provided by any .service files' and concludes nothing.
    """
    PBAP_UUID = "0000112f-0000-1000-8000-00805f9b34fb"
    try:
        intro = await bus.introspect(BLUEZ_BUS, "/")
        root  = bus.get_proxy_object(BLUEZ_BUS, "/", intro)
        om    = root.get_interface("org.freedesktop.DBus.ObjectManager")
        objs  = await om.call_get_managed_objects()
        for path, ifaces in objs.items():
            dev = ifaces.get("org.bluez.Device1")
            if not dev: continue
            connected = dev.get("Connected")
            if isinstance(connected, Variant): connected = connected.value
            if not connected: continue
            uuids = dev.get("UUIDs")
            if isinstance(uuids, Variant): uuids = uuids.value
            if uuids and PBAP_UUID in [u.lower() for u in uuids]:
                addr = dev.get("Address")
                if isinstance(addr, Variant): addr = addr.value
                return addr
    except Exception as e:
        log("find phone err:", e)
    return None


# ═════════════════════════════════════════════════════════════════════
# DBus service exposed to the Qt UI (com.volta.Phone)
# ═════════════════════════════════════════════════════════════════════

class PhoneService(ServiceInterface):
    def __init__(self, pbap: PbapClient, hfp: HfpClient, audio: "AudioBridge", mapc: "MapClient"):
        super().__init__(UI_BUS)
        self.pbap  = pbap
        self.hfp   = hfp
        self.audio = audio
        self.mapc  = mapc
        self._call_state = "idle"          # idle | incoming | dialing | active
        self._call_number = ""
        self._call_name = ""
        # Allows HFP to consult the address book to resolve the name
        # of unsaved callers.
        hfp._contacts_ref = pbap.contacts
        # Hooks HFP callbacks → DBus signals for the UI
        hfp.on_incoming_call = self._emit_incoming
        hfp.on_call_answered = self._emit_answered
        hfp.on_call_ended    = self._emit_ended
        hfp.on_call_dialing  = self._emit_dialing

    # ── Methods callable from the UI ────────────────────────────────────

    @method()
    async def Dial(self, number: 's'):
        await self.hfp.dial(number)

    @method()
    async def Answer(self):
        await self.hfp.answer()

    @method()
    async def Hangup(self):
        await self.hfp.hangup()

    @method()
    def GetContacts(self) -> 's':
        return json.dumps(self.pbap.contacts)

    @method()
    def GetRecentCalls(self) -> 's':
        return json.dumps(self.pbap.recent_calls)

    @method()
    def GetConversations(self) -> 's':
        # We do not send the internal fields (_ts/_path) to the UI, it only needs them
        # internally for sorting and for GetFullMessage.
        clean = []
        for c in self.mapc.conversations:
            cc = dict(c)
            cc["messages"] = [{"text": m["text"], "from": m["from"], "time": m["time"], "ts": m.get("_ts", "")}
                               for m in c["messages"]]
            clean.append(cc)
        return json.dumps(clean)

    @method()
    async def GetFullMessage(self, number: 's', index: 'i') -> 's':
        """Downloads the full body of ONE message (ListMessages only gives
        a preview) — the UI calls it when it opens/scrolls a conversation."""
        convo = next((c for c in self.mapc.conversations if c["number"] == number), None)
        if not convo or index < 0 or index >= len(convo["messages"]):
            return ""
        msg = convo["messages"][index]
        path = msg.get("_path")
        if not path:
            return msg.get("text", "")
        body = await self.mapc.fetch_full_body(path)
        return body or msg.get("text", "")

    @method()
    async def SendMessage(self, number: 's', text: 's') -> 'b':
        ok = await self.mapc.send(number, text)
        if ok:
            self.ConversationsUpdated()
        return ok

    @method()
    def GetCallState(self) -> 's':
        return json.dumps({
            "state":  self._call_state,
            "number": self._call_number,
            "name":   self._call_name,
        })

    # ── Signals toward the UI ───────────────────────────────────────────

    # NOTE: in dbus-next signals the DBus signature is declared with the RETURN
    # annotation, not with those of the parameters (those apply to the incoming
    # methods, which I had confused). For several fields a list is returned
    # and the return type is the concatenation of the DBus types.
    @signal()
    def IncomingCall(self, name: str, number: str) -> 'ss':
        return [name, number]

    @signal()
    def CallDialing(self, name: str, number: str) -> 'ss':
        return [name, number]

    @signal()
    def CallAnswered(self):
        pass

    @signal()
    def CallEnded(self):
        pass

    @signal()
    def ContactsUpdated(self):
        pass

    @signal()
    def ConversationsUpdated(self):
        pass

    def _emit_incoming(self, name, number):
        # Look up the name in the contacts if missing
        if not name and number:
            for c in self.pbap.contacts:
                if c.get("phone") == number or number in c.get("phones", []):
                    name = c["name"]; break
        self._call_state, self._call_name, self._call_number = "incoming", name or number, number
        log(f"[SIGNAL] IncomingCall {name} <{number}>")
        self.IncomingCall(name or number, number)

    def _emit_dialing(self, name, number):
        self._call_state, self._call_name, self._call_number = "dialing", name or number, number
        # Mounts the bridge already in dialing: when the other party answers the audio
        # is ready, without the classic "mute first second".
        try:
            self.audio.up()
        except Exception as e:
            log("audio up err:", e)
        self.CallDialing(name or number, number)

    def _emit_answered(self):
        self._call_state = "active"
        try:
            self.audio.up()      # idempotent: if already active it does nothing
        except Exception as e:
            log("audio up err:", e)
        self.CallAnswered()

    def _emit_ended(self):
        self._call_state, self._call_name, self._call_number = "idle", "", ""
        try:
            self.audio.down()    # restore A2DP for the music
        except Exception as e:
            log("audio down err:", e)
        self.CallEnded()


# ═════════════════════════════════════════════════════════════════════
# Main loop
# ═════════════════════════════════════════════════════════════════════

async def main():
    bus     = await MessageBus(bus_type=BusType.SESSION).connect()
    sys_bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    log("connesso a DBus session + system")

    # PbapClient talks to obexd (session). HfpClient talks to PipeWire
    # Telephony (session). BlueZ, to discover and listen to devices, is
    # on the system bus — a recurring mistake in all the examples around.
    pbap  = PbapClient(bus)          # obex = session bus
    hfp   = HfpClient(bus)           # pipewire telephony = session bus
    audio = AudioBridge()
    mapc  = MapClient(bus)           # obex = session bus, like pbap
    svc   = PhoneService(pbap, hfp, audio, mapc)

    # If the service is killed during a call, we do not leave the card
    # stuck in HFP (music audio at 8 kHz until it reconnects).
    import atexit, signal as _signal
    atexit.register(audio.down)
    for _sig in (_signal.SIGTERM, _signal.SIGINT):
        try:
            asyncio.get_event_loop().add_signal_handler(
                _sig, lambda: (audio.down(), os._exit(0)))
        except Exception:
            pass

    bus.export(UI_PATH, svc)
    await bus.request_name(UI_BUS)
    log(f"servizio DBus esposto: {UI_BUS} {UI_PATH}")

    await hfp.start()

    # Try to download the contacts if a phone is already connected.
    # BlueZ lives on the SYSTEM bus.
    async def try_pbap():
        addr = await find_connected_phone(sys_bus)
        if not addr:
            log("no BT phone with PBAP at the moment")
            return
        log(f"telefono BT connesso: {addr} → scarico rubrica")
        # obexd sometimes takes a long time to answer the introspect (especially
        # if the device has just connected). If the timeout expires, we do not
        # crash the service: we wait 5s and retry.
        for attempt in range(3):
            try:
                ok = await pbap.download(addr, on_updated=svc.ContactsUpdated)
                if ok:
                    log("PBAP: contatti aggiornati")
                return
            except (TimeoutError, asyncio.TimeoutError) as e:
                log(f"PBAP timeout (attempt {attempt+1}/3), retrying in 5s")
                await asyncio.sleep(5)
            except Exception as e:
                log(f"PBAP error: {type(e).__name__}: {e}")
                return
        log("PBAP: giving up after 3 attempts")

    await try_pbap()

    # Same scheme as try_pbap(), for the messages.
    async def try_map():
        addr = await find_connected_phone(sys_bus)
        if not addr:
            log("no BT phone with MAP at the moment")
            return
        log(f"telefono BT connesso: {addr} → scarico messaggi")
        for attempt in range(3):
            try:
                ok = await mapc.download(addr, on_updated=svc.ConversationsUpdated)
                if ok:
                    log("MAP: messaggi aggiornati")
                    # "Best effort" live notifications — if not available, the
                    # periodic polling below stays active anyway.
                    asyncio.ensure_future(mapc.watch_new_messages(
                        lambda: asyncio.ensure_future(try_map())))
                return
            except (TimeoutError, asyncio.TimeoutError) as e:
                log(f"MAP timeout (tentativo {attempt+1}/3), riprovo tra 5s")
                await asyncio.sleep(5)
            except Exception as e:
                log(f"MAP error: {type(e).__name__}: {e}")
                return
        log("MAP: rinuncio dopo 3 tentativi")

    await try_map()

    # Periodic safety polling: live MAP notifications depend on
    # BlueZ details that cannot be fully verified here (even with the fix,
    # they might not work on every phone/BlueZ version). 8s is a
    # good compromise between "feels like real time" and not stressing the
    # Bluetooth too much with too-frequent full redownloads — lowered from 20s
    # on explicit request.
    async def poll_map_periodically():
        while True:
            await asyncio.sleep(8)
            if mapc._device_addr:
                await try_map()

    asyncio.ensure_future(poll_map_periodically())

    async def watch_bluez():
        # BUG fixed: "InterfacesAdded" fires only the FIRST time
        # a phone's Device1 object appears on the bus (new
        # pairing, or bluetoothd restart) — for a phone ALREADY
        # paired previously, its Device1 object already exists from
        # before the UI starts, so "InterfacesAdded" never fires
        # again. When that phone (re)connects later, BlueZ signals the
        # change with a simple "PropertiesChanged" (Connected:
        # False → True) ON THE SAME object, which here was previously not
        # listened to at all — hence address book/messages that stayed empty
        # until the UI was restarted (which instead finds them right away, with
        # find_connected_phone(), because it starts AFTER the connection).
        def watch_device(path):
            async def attach():
                try:
                    intro = await sys_bus.introspect(BLUEZ_BUS, path)
                    obj   = sys_bus.get_proxy_object(BLUEZ_BUS, path, intro)
                    props_if = obj.get_interface("org.freedesktop.DBus.Properties")

                    def on_props(interface, changed, invalidated):
                        if interface != "org.bluez.Device1":
                            return
                        connected = changed.get("Connected")
                        if isinstance(connected, Variant):
                            connected = connected.value
                        if connected:
                            log("telefono BT (ri)connesso:", path)
                            asyncio.ensure_future(try_pbap())
                            asyncio.ensure_future(try_map())
                            asyncio.ensure_future(hfp.start())

                    props_if.on_properties_changed(on_props)
                except Exception as e:
                    log("watch device err:", path, e)
            asyncio.ensure_future(attach())

        try:
            intro = await sys_bus.introspect(BLUEZ_BUS, "/")
            root  = sys_bus.get_proxy_object(BLUEZ_BUS, "/", intro)
            om    = root.get_interface("org.freedesktop.DBus.ObjectManager")

            # Devices already paired/visible NOW (including a
            # phone still disconnected at this moment): we put them
            # under observation right away, not only those that will appear
            # later with InterfacesAdded.
            objs = await om.call_get_managed_objects()
            for path, ifaces in objs.items():
                if "org.bluez.Device1" in ifaces:
                    watch_device(path)

            def on_added(path, interfaces):
                if "org.bluez.Device1" in interfaces:
                    log("nuovo device BT visibile:", path)
                    watch_device(path)
                    asyncio.ensure_future(try_pbap())
                    asyncio.ensure_future(try_map())
                    asyncio.ensure_future(hfp.start())
            om.on_interfaces_added(on_added)
        except Exception as e:
            log("watch bluez err:", e)

    await watch_bluez()

    # Loop infinito
    await asyncio.Future()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
