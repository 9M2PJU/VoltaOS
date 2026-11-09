#!/bin/bash
# round67: gamescope instead of a "bare" Xwayland (round66, abandoned —
# Wine kept ignoring our dedicated DISPLAY and always went back to the
# native Wayland driver toward the normal desktop, showing a
# Wine window disconnected from our compositor, not what we wanted).
#
# gamescope is Valve's tool (the same as the Steam Deck), designed
# exactly for this scenario: IT connects to our compositor
# as a Wayland client (WAYLAND_DISPLAY=wayland-volta, same trick used
# so far), and inside it hosts and runs the command we pass it
# after "--" in a graphical environment of its own (its own Xwayland/its own
# internal management) — it handles all the complexity of
# subsurfaces/graphics driver. Toward OUR compositor it exposes ONE clean
# surface, like any other app — the exact same
# simple situation as Waydroid, which we already embed perfectly.
#
# Key difference from round66: we no longer have to force DISPLAY or
# remove WAYLAND_DISPLAY for Wine — gamescope itself sets them for the
# child process it launches (bottles-cli run inherits that environment
# normally, like any child process). No more --env/--unset-env
# tricks on our side.
#
# Uso: native_game_gamescope_launch.sh <bottle> <-p|-e> <programma-o-percorso>
#   es: native_game_gamescope_launch.sh "pes 2012" -p "Cuphead"
#   es: native_game_gamescope_launch.sh "pes 2012" -e "/percorso/Limbo.exe"

set -u

# round80: "-m" (job control / monitor mode) even if the script is not
# interactive. Without this, the job launched in the background with "&" below
# would inherit the process group OF THIS SCRIPT, and a kill of only
# GSPID (gamescope) does not reliably propagate to the whole tree that
# gamescope hosts inside itself (flatpak/bwrap of the sandbox, bottles-cli,
# wineserver, the real game .exe, gamescope's internal Xwayland...).
# With "set -m" instead bash creates a NEW process group on purpose for this
# job, with pgid == GSPID: so we can shut down the whole tree in one
# go with "kill -TERM -$GSPID" (the minus before the PID = sends the signal
# to the WHOLE process group, not just the process) from Arcade.qml, see
# stopNativeGame()/endNativeGame() — instead of hoping that bottles-cli stop
# + pkill -f with text patterns really find all the right processes.
set -m

# round96: "Wine on the system with an always-warm session" mode (opt-in).
# VOLTA_HOST=0 (default): current launch inside flatpak, as so far.
# VOLTA_HOST=1: same Wine commands but run on the system, without flatpak,
# with a persistent wineserver: the Wine boot (services.exe & co., ~4 s)
# is only paid by the first game after the PC starts, the following ones do not.
# It is enabled from Settings › Arcade › Quick launch (Arcade.qml passes VOLTA_HOST=1).
# Measured: inside flatpak Wine takes ~3.8 s for every game; on the system 2.8 s the
# first time and 0.14 s with the session already warm.
# "--warm <bottle>": prepares only the session (Arcade.qml launches it when you open
# the Arcade), so even the first game starts right away.
VOLTA_HOST="${VOLTA_HOST:-0}"
WARMFLAG="/tmp/volta_wine_warm"   # contains the prefix (bottle) of the warm session

WARM_ONLY=0
if [ "${1:-}" = "--warm" ]; then WARM_ONLY=1; VOLTA_HOST=1; shift; set -- "$1" "-p" "-"; fi
BOTTLE="$1"
FLAG="$2"      # -p (program) or -e (direct executable)
VALUE="$3"

PIDFILE="/tmp/volta_native_game_gamescope.pid"

# round90: stopwatch. Writes to /tmp/volta_game_timing.log the time (in
# seconds since the start of this script) at which the various pieces appear: it serves to
# understand WHERE the 7-10 seconds go (flatpak/bottles-cli, wineserver, the game's
# .exe) before optimizing blindly.
TLOG="/tmp/volta_game_timing.log"
T0="$(date +%s.%N)"
tmark() { awk -v a="$(date +%s.%N)" -v b="$T0" -v m="$1" 'BEGIN{printf "%7.2fs  %s\n", a-b, m}' >> "$TLOG"; }
echo "=== $(date +%H:%M:%S) start: ${VALUE} ===" >> "$TLOG"
tmark "script started"

# ── Cleanup of a previous instance left hanging ──────────────────────
# round80: now we kill the WHOLE process group of that instance (not just
# gamescope's PID), same reason explained above — otherwise an old
# flatpak/wine/game can stay alive and conflict with the new one
# we are about to launch.
if [ -f "$PIDFILE" ]; then
    OLDPID="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$OLDPID" ] && kill -0 "$OLDPID" 2>/dev/null; then
        kill -TERM -"$OLDPID" 2>/dev/null
        sleep 0.3
        kill -KILL -"$OLDPID" 2>/dev/null
    fi
    rm -f "$PIDFILE"
fi

# ── gamescope attached to OUR compositor ────────────────────────────
# -W/-H: gamescope's internal resolution — a reasonable
# starting point, it need not be exact: NativeAppView/ShellSurfaceItem
# resize the surface afterwards anyway, as with any other app
# (see sendResize/forceResize in NativeAppView.qml). Adjustable
# later if needed.
#
# round72: ENABLE_GAMESCOPE_WSI=0 on the INNER command (bottles-cli), same
# reason as round71 but the other way around — there it served to prevent a "ghost"
# gamescope (gamescope-brokey) from launching itself and intercepting
# the Vulkan surface BEFORE our dedicated Xwayland; here we want
# to BE the gamescope that sees that surface, so we must
# prevent Proton/Wine from trying to launch a second, nested one,
# inside the one we already launched (same symptom seen in the logs:
# "Failed to bind socket @/tmp/.X11-unix/X0: Address already in use" —
# the nested gamescope tries to take the same X11 sockets as the
# nostro gamescope esterno).
# round81: speeding up the game start with WINEESYNC/WINEFSYNC/DXVK_ASYNC
# — REMOVED at round85: right after this change reports started
# "it starts, I hear the audio, black screen" (swapchain created in the log, so
# DXVK/gamescope really draw, but the frame never reaches the screen —
# compatible with a synchronization problem of the buffer exchanged between
# DXVK/gamescope and OUR nested compositor, introduced exactly by
# WINEESYNC/WINEFSYNC/DXVK_ASYNC). No QML change of this session
# touches shellSurface/waylandToplevel of NativeAppView — they stay identical to
# when the video was visible — so this is the main suspect.
# All three removed: if the video comes back, it was one of these (they can be
# reintroduced one at a time to isolate which, if the speed
# optimization is still needed).
# round88: every recent log says "Creating headless backend" instead of an
# explicit "wayland" backend (normally gamescope chooses it by itself
# seeing WAYLAND_DISPLAY, but here it no longer does) — we had never
# verified it as the cause of the black screen. "--backend wayland" forces it, removing
# any autodetection ambiguity.
# round90 (point 1, shader cache): MESA_SHADER_CACHE_MAX_SIZE raises the ceiling
# of Mesa's shader cache (default 1 GB, it may discard old already
# compiled shaders and force DXVK/RADV to recompile them at every start).
# round92 (point 3): DIRECT WINE LAUNCH, without bottles-cli.
# From the stopwatch: 3.8 s between "bottles-cli sandbox started" and "wineserver
# appeared" go into Bottles' Python/catalog (plus an extra first
# Wine start seen in the log). bottles-cli in the end runs
#     wine start /wait /d <cartella> <exe>
# with an environment that we read from /proc of the real process (WINEPREFIX,
# soda runner, shader cache, etc.). Here we replicate it. LatencyFleX is NOT
# included (turned off on purpose, in a car it is not needed).
# If something cannot be resolved (bottle, runner, game path) we fall back
# automatically to bottles-cli. VOLTA_DIRECT=0 forces the old path;
# VOLTA_DRYRUN=1 prints the command and nothing else (for checks).
BDATA="$HOME/.var/app/com.usebottles.bottles/data/bottles"
DIRECT_OUT=""
if [ "${VOLTA_DIRECT:-1}" = "1" ]; then
    DIRECT_OUT="$(python3 - "$BDATA" "$BOTTLE" "$FLAG" "$VALUE" 2>/dev/null <<'PY'
import os, re, sys, shlex, glob
bdata, bottle, flag, value = sys.argv[1:5]

def unq(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
        v = v[1:-1]
    return v

def find_bottle():
    for yml in glob.glob(os.path.join(bdata, "bottles", "*", "bottle.yml")):
        txt = open(yml, encoding="utf-8").read()
        m = re.search(r"^Name: (.*)$", txt, re.M)
        if m and unq(m.group(1)) == bottle:
            return os.path.dirname(yml), txt
    return None, None

def scalar(txt, key):
    m = re.search(r"^%s: (.*)$" % key, txt, re.M)
    return unq(m.group(1)) if m else ""

def programs(txt):
    lines = txt.split("\n")
    try:
        i = lines.index("External_Programs:")
    except ValueError:
        return []
    out, cur, last = [], None, None
    for ln in lines[i + 1:]:
        if ln and not ln.startswith(" "):
            break
        if re.match(r"^    [0-9a-fA-F-]{36}:\s*$", ln):
            cur = {}; out.append(cur); last = None; continue
        if cur is None:
            continue
        m = re.match(r"^        ([A-Za-z_0-9]+):(?: (.*))?$", ln)
        if m:
            last = m.group(1); cur[last] = unq(m.group(2) or ""); continue
        m = re.match(r"^            (\S.*)$", ln)
        if m and last:
            cur[last] = (cur[last] + " " + m.group(1).strip()).strip()
    return out

def ci_exists(root, rel_parts):
    cur = root
    for part in rel_parts:
        try:
            names = os.listdir(cur)
        except OSError:
            return False
        hit = next((n for n in names if n.lower() == part.lower()), None)
        if hit is None:
            return False
        cur = os.path.join(cur, hit)
    return True

prefix, txt = find_bottle()
if not prefix:
    sys.exit(1)
runner = scalar(txt, "Runner")
wine = os.path.join(bdata, "runners", runner, "bin", "wine")
if not runner or not os.access(wine, os.X_OK):
    sys.exit(2)

if value == "-":                       # --warm: serves only the bottle, no game
    for k, v in (("D_WINE", wine), ("D_PREFIX", prefix), ("D_RUNNER", os.path.join(bdata, "runners", runner)),
                 ("D_WDIR", ""), ("D_WEXE", ""), ("D_BDATA", bdata)):
        print("%s=%s" % (k, shlex.quote(v)))
    sys.exit(0)
if flag == "-p":
    prog = next((p for p in programs(txt) if p.get("name") == value), None)
    if not prog or not prog.get("path"):
        sys.exit(3)
    path = prog["path"]
else:
    path = value

drive_c = os.path.join(prefix, "drive_c")
if re.match(r"^[A-Za-z]:\\", path):
    wpath = path
    rel = [x for x in path[3:].split("\\") if x]
else:
    if not path.startswith(drive_c + "/"):
        sys.exit(4)
    rel = [x for x in path[len(drive_c) + 1:].split("/") if x]
    wpath = "C:\\" + "\\".join(rel)
if not ci_exists(drive_c, rel):
    sys.exit(5)
wdir = wpath.rsplit("\\", 1)[0]
for k, v in (("D_WINE", wine), ("D_PREFIX", prefix), ("D_RUNNER", os.path.join(bdata, "runners", runner)),
             ("D_WDIR", wdir), ("D_WEXE", wpath), ("D_BDATA", bdata)):
    print("%s=%s" % (k, shlex.quote(v)))
PY
)"
fi

warm_ok=0
if [ -n "$DIRECT_OUT" ] && [ "$VOLTA_HOST" = "1" ]; then
    eval "$DIRECT_OUT"
    HVARS=(
        "WINEARCH=win64"
        "WINEPREFIX=${D_PREFIX}"
        "WINESERVER=${D_RUNNER}/bin/wineserver"
        "WINEDLLOVERRIDES=winemenubuilder=d"
        "WINEDEBUG=fixme-all"
        "WINEFSYNC=1"
        "WINE_LARGE_ADDRESS_AWARE=1"
        "STAGING_SHARED_MEMORY=1"
        "ENABLE_GAMESCOPE_WSI=0"
        "MESA_SHADER_CACHE_DIR=${D_PREFIX}/cache/mesa_shader"
        "MESA_SHADER_CACHE_MAX_SIZE=10G"
        "DXVK_SHADER_CACHE_PATH=${D_PREFIX}/cache/dxvk_shader"
        "VKD3D_SHADER_CACHE_PATH=${D_PREFIX}/cache/vkd3d_shader"
        "LD_LIBRARY_PATH=${D_RUNNER}/lib:${D_RUNNER}/lib/wine/x86_64-unix"
        "PATH=${D_RUNNER}/bin:${PATH}"
    )
    if [ "${VOLTA_DRYRUN:-0}" = "1" ]; then
        warm_ok=1
    elif pgrep -u "$(id -u)" -x wineserver >/dev/null 2>&1 && [ "$(cat "$WARMFLAG" 2>/dev/null)" = "$D_PREFIX" ]; then
        tmark "Wine session ALREADY WARM (boot skipped)"
        warm_ok=1
    else
        # Cold: a possible non-persistent wineserver left over must be closed,
        # then the persistent one is started and the boot (services) is done ONCE,
        # without DISPLAY (the services do not use X; the window is created by the game
        # inside gamescope, with its own DISPLAY).
        pkill -9 -x wineserver 2>/dev/null; sleep 0.2
        if env -u DISPLAY -u WAYLAND_DISPLAY "${HVARS[@]}" "${D_RUNNER}/bin/wineserver" -p \
           && timeout 30 env -u DISPLAY -u WAYLAND_DISPLAY "${HVARS[@]}" "${D_WINE}" wineboot --init >/dev/null 2>&1; then
            printf '%s' "$D_PREFIX" > "$WARMFLAG"   # warm session of THIS bottle
            tmark "sessione Wine avviata a freddo (persistente)"
            warm_ok=1
        else
            tmark "WARNING: Wine on the system does not start, falling back to flatpak"
            pkill -9 -x wineserver 2>/dev/null
        fi
    fi
fi

if [ "$WARM_ONLY" = "1" ]; then
    tmark "only Wine session preparation: done (ok=$warm_ok)"
    exit 0
fi
if [ "$warm_ok" = "1" ]; then
    INNER=(env "${HVARS[@]}" "${D_WINE}" start /wait /d "${D_WDIR}" "${D_WEXE}")
    tmark "start on the SYSTEM's Wine (warm session): ${D_WEXE}"
elif [ -n "$DIRECT_OUT" ]; then
    rm -f "$WARMFLAG"
    eval "$DIRECT_OUT"
    INNER=(flatpak run
        --env="ENABLE_GAMESCOPE_WSI=0"
        --env="WINEARCH=win64"
        --env="WINEPREFIX=${D_PREFIX}"
        --env="WINEDLLOVERRIDES=winemenubuilder=d"
        --env="WINEDEBUG=fixme-all"
        --env="WINEFSYNC=1"
        --env="WINE_LARGE_ADDRESS_AWARE=1"
        --env="STAGING_SHARED_MEMORY=1"
        --env="MESA_SHADER_CACHE_DIR=${D_PREFIX}/cache/mesa_shader"
        --env="MESA_SHADER_CACHE_MAX_SIZE=10G"
        --env="DXVK_SHADER_CACHE_PATH=${D_PREFIX}/cache/dxvk_shader"
        --env="VKD3D_SHADER_CACHE_PATH=${D_PREFIX}/cache/vkd3d_shader"
        --env="LD_LIBRARY_PATH=${D_RUNNER}/lib:${D_RUNNER}/lib/wine/x86_64-unix:${D_RUNNER}/lib/wine/i386-unix"
        --env="PATH=/app/bin:/app/utils/bin:/usr/bin"
        --env="VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json:/usr/lib/x86_64-linux-gnu/GL/vulkan/icd.d/radeon_icd.x86_64.json:/usr/lib/i386-linux-gnu/GL/vulkan/icd.d/radeon_icd.i686.json"
        --command="${D_WINE}" com.usebottles.bottles
        start /wait /d "${D_WDIR}" "${D_WEXE}")
    tmark "DIRECT wine start: ${D_WEXE}"
else
    INNER=(flatpak run
        --env="ENABLE_GAMESCOPE_WSI=0"
        --env="MESA_SHADER_CACHE_MAX_SIZE=10G"
        --command=bottles-cli com.usebottles.bottles run -b "${BOTTLE}" "${FLAG}" "${VALUE}")
    tmark "start via bottles-cli (fallback)"
fi

if [ "${VOLTA_DRYRUN:-0}" = "1" ]; then
    printf 'gamescope --backend wayland -W 1280 -H 800 --'; printf ' %q' "${INNER[@]}"; echo
    exit 0
fi

# gamescope (>= 3.15) accepts wl_seat only from version 8, but the Volta
# compositor (QtWayland) always announces 4 -> "Couldn't create Wayland input
# objects". The gamescope_seat_compat.so shim (only inside gamescope) solves it.
# It compiles itself the first time (needs gcc + libwayland-dev); if it
# cannot be compiled we go on without it (previous behavior).
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SEAT_SHIM="$SCRIPT_DIR/gamescope_seat_compat.so"
SEAT_SRC="$SCRIPT_DIR/gamescope_seat_compat.c"
if [ -f "$SEAT_SRC" ] && { [ ! -f "$SEAT_SHIM" ] || [ "$SEAT_SRC" -nt "$SEAT_SHIM" ]; }; then
    cc -shared -fPIC -O2 -o "$SEAT_SHIM" "$SEAT_SRC" \
        $(pkg-config --cflags --libs wayland-client 2>/dev/null) -ldl 2>/dev/null \
        || echo "[gamescope] shim not compiled (gcc or libwayland-dev missing?)" >&2
fi
GS_ENV=()
[ -f "$SEAT_SHIM" ] && GS_ENV=(LD_PRELOAD="$SEAT_SHIM")
env "${GS_ENV[@]}" WAYLAND_DISPLAY=wayland-volta gamescope --backend wayland -W 1280 -H 800 -- \
    "${INNER[@]}" &
GSPID=$!
echo "$GSPID" > "$PIDFILE"
tmark "gamescope lanciato"

# Background observer: notes when the key processes appear.
# round93: the checks of rounds 90-91 gave false positives (they caught gamescope's
# command line or orphan processes of previous games). Now they
# count ONLY processes born after the start of this script (ps etimes) and every
# pattern uses the [x] trick so as not to catch the grep itself.
seen() {
    local lim
    lim="$(awk -v a="$(date +%s.%N)" -v b="$T0" 'BEGIN{printf "%d", a-b+1}')"
    ps -eo etimes=,args= | awk -v lim="$lim" '$1<=lim' | grep -E -q "$1"
}
(
    declare -A done_m
    tmark "osservatore attivo"
    check() { # $1=key $2=regex $3=text
        if [ -z "${done_m[$1]:-}" ] && seen "$2"; then tmark "$3"; done_m[$1]=1; fi
    }
    for _ in $(seq 1 1200); do
        check sb  '^ *[0-9]+ +[b]wrap .*(bin/wine start|bottles-cli)' "game sandbox started (gamescope ready)"
        check ws  'bin/[w]ineserver( |$)'                              "wineserver comparso"
        check svc '[s]ervices\.exe'                                    "Wine started services.exe (prefix up)"
        check gm  '^ *[0-9]+ +[A-Z]:\\Program'                         "GAME process appeared"
        [ "${#done_m[@]}" -ge 4 ] && break
        sleep 0.1
    done
    tmark "osservatore terminato (${#done_m[@]}/4 segnali trovati)"
) &

wait "$GSPID"
tmark "gamescope ended (the game was closed)"
rm -f "$PIDFILE"
