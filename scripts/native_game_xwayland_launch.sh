#!/bin/bash
# round66: launches a Bottles/Wine game through a DEDICATED Xwayland
# attached to our compositor (wayland-volta), instead of connecting Wine
# directly as a native Wayland client (--env=WAYLAND_DISPLAY=wayland-volta,
# round58-65). With native Wine the game draws its real content on a
# child wl_subsurface, not on the main toplevel — and there we run into
# a QtWaylandCompositor bug (QQuickItem::stackBefore on itself) that
# we could not solve from QML in any way (see the comments
# round62/63/65 in qml/NativeAppView.qml): contenuto presente, dimensionato
# right, but never composed on screen — audio yes, video no, confirmed
# identical with both DXVK/Vulkan and WineD3D/OpenGL, with both
# Proton and vanilla runners.
#
# With Xwayland something different happens: Xwayland acts as a BRIDGE between X11 (which
# Wine will use normally, the most mature and tested X11 driver that exists) and
# Wayland. For every X11 window of the game, it creates a NORMAL xdg_toplevel on the
# Wayland compositor it is connected to — in this case OURS, because we
# launch it with WAYLAND_DISPLAY=wayland-volta in its environment. The game's content
# therefore ends up on the MAIN surface of the toplevel, not on
# a child subsurface: the exact same situation as Android Auto, which
# already works perfectly with NativeAppView/ShellSurfaceItem. We bypass
# the whole family of subsurface bugs this way, instead of continuing to
# provare a ripararla.
#
# round68 — THE REAL BLOCKER FOUND: searching online for how Wine's
# Wayland driver works, we found an example .reg that
# enables it like this:
#   wine reg.exe add HKCU\Software\Wine\Drivers /v Graphics /d x11,wayland
# that is: it is NOT a runtime switch tied to an environment variable.
# It is a value WRITTEN IN THE BOTTLE'S REGISTRY (the prefix's "user.reg"
# file), with a list of drivers to try in order ("wayland,x11" =
# try wayland first, then x11 as a fallback). Being in the registry and not
# in an env var, --unset-env=WAYLAND_DISPLAY (round66b) does not touch it at
# all: Wine keeps trying wayland FIRST at every launch, regardless
# of what we put in DISPLAY/WAYLAND_DISPLAY in the sandbox — and
# if it finds ANY visible Wayland socket (even the real one of the
# normal desktop, not ours!) it connects there, completely bypassing
# our dedicated Xwayland. It explains why the test with "Wayland
# (Experimental)" turned off in the bottle, but run through the
# gamescope script of the previous evening, showed Cuphead in a window
# with GNOME's frames: Wine had connected anyway to the REAL Wayland
# of the normal desktop (not to our compositor nor to our gamescope,
# which stayed "headless" and invisible as already confirmed in the logs).
#
# Below, BEFORE launching the game, we find the bottle's prefix folder
# and force that value to "Graphics"="x11" — without
# any wayland in the list, in any case — so Wine has no
# other choice than our dedicated Xwayland (DISPLAY=:50). When the
# game ends we restore the original value (automatic backup/restore),
# so the bottle's "Wayland (Experimental)" toggle goes back to
# behaving as the user had set it for normal uses, outside
# this script.
#
# Precaution: we write to the file ONLY after stopping any
# wineserver already active on this bottle (bottles-cli stop). Wine
# keeps the registry in memory while running and rewrites it to
# disk on close — if wineserver had already started BEFORE
# our change, that final rewrite would silently undo
# what we just did.
#
# If the bottle's folder or its user.reg are not found (e.g.
# folder name different from what we expect), the script
# does NOT stop: it prints a warning and proceeds anyway with Xwayland
# only, as in the previous rounds — likely result: the same
# bug as tonight (wayland wins anyway). The warning message says
# where we looked, useful to understand the real folder name if
# the search needs adjusting.
#
# Uso: native_game_xwayland_launch.sh <bottle> <-p|-e> <programma-o-percorso>
#   es: native_game_xwayland_launch.sh "pes 2012" -p "Cuphead"
#   es: native_game_xwayland_launch.sh "pes 2012" -e "/percorso/Limbo.exe"

set -u

BOTTLE="$1"
FLAG="$2"      # -p (program, see Bottles "Program") or -e (direct executable)
VALUE="$3"

DISPLAYNUM=50
PIDFILE="/tmp/volta_native_game_xwayland.pid"
XPID=""

# ── Cleanup of a previous instance left hanging ──────────────────────
# (e.g. an unclean close from the previous round — harmless if there is
# nothing to clean).
if [ -f "$PIDFILE" ]; then
    OLDPID="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$OLDPID" ] && kill -0 "$OLDPID" 2>/dev/null; then
        kill "$OLDPID" 2>/dev/null
        sleep 0.3
        kill -9 "$OLDPID" 2>/dev/null
    fi
    rm -f "$PIDFILE"
fi
rm -f "/tmp/.X11-unix/X${DISPLAYNUM}" "/tmp/.X${DISPLAYNUM}-lock" 2>/dev/null

# ── round68: find this bottle's prefix folder ───────────
# Bottles (flatpak) keeps every bottle in a folder with (normally) the
# same name shown in the app, inside this base. We compare the names
# ignoring case and spaces/underscores/dashes, to tolerate
# small differences in how Bottles named the folder.
BOTTLES_BASE="$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles"
BOTTLE_DIR=""
if [ -d "$BOTTLES_BASE" ]; then
    NORM_WANTED="$(printf '%s' "$BOTTLE" | tr '[:upper:]' '[:lower:]' | tr -d ' _-')"
    for d in "$BOTTLES_BASE"/*/; do
        [ -d "$d" ] || continue
        NAME="$(basename "$d")"
        NORM_NAME="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' | tr -d ' _-')"
        if [ "$NORM_NAME" = "$NORM_WANTED" ]; then
            BOTTLE_DIR="${d%/}"
            break
        fi
    done
fi

REG_PATCHED=0
if [ -n "$BOTTLE_DIR" ] && [ -f "$BOTTLE_DIR/user.reg" ]; then
    # Stops any wineserver already active on this bottle BEFORE
    # touching the file — see explanation above (it prevents the in-memory
    # copy of the registry from overwriting our change on close).
    flatpak run --command=bottles-cli com.usebottles.bottles stop -b "${BOTTLE}" >/dev/null 2>&1
    sleep 0.5

    REGFILE="$BOTTLE_DIR/user.reg"
    cp "$REGFILE" "$REGFILE.volta-bak"

    awk '
        BEGIN { in_section = 0; done = 0 }
        /^\[Software\\\\Wine\\\\Drivers\]/ {
            print
            in_section = 1
            next
        }
        /^\[/ {
            if (in_section && !done) {
                print "\"Graphics\"=\"x11\""
                done = 1
            }
            in_section = 0
            print
            next
        }
        {
            if (in_section && $0 ~ /^"Graphics"=/) {
                print "\"Graphics\"=\"x11\""
                done = 1
                next
            }
            print
        }
        END {
            if (!done) {
                print "[Software\\\\Wine\\\\Drivers] 1700000000"
                print "#time=0"
                print "\"Graphics\"=\"x11\""
            }
        }
    ' "$REGFILE" > "$REGFILE.volta-tmp" && mv "$REGFILE.volta-tmp" "$REGFILE"

    REG_PATCHED=1
    echo "[native_game_xwayland_launch] Bottle '${BOTTLE}' registry forced to Graphics=x11 (backup in ${REGFILE}.volta-bak)" >&2
else
    echo "[native_game_xwayland_launch] WARNING: user.reg not found for bottle '${BOTTLE}' (searched under ${BOTTLES_BASE}) — cannot force the graphics driver, so the Wayland toggle problem may persist. If the bottle exists but is not found, check the exact name of its folder." >&2
fi

# ── Guaranteed cleanup, even on abnormal exit ──────────────────
# round68: before we only did it at the end of the script (two lines after
# the blocking bottles-cli run) — if the script was interrupted before
# getting there (e.g. an external kill -9 during tonight's many tests), both the
# hanging Xwayland and, worse, the bottle's registry stayed
# forced to x11 afterwards. With the EXIT trap this cleanup always fires.
restore_registry() {
    if [ "$REG_PATCHED" = "1" ] && [ -f "$BOTTLE_DIR/user.reg.volta-bak" ]; then
        mv "$BOTTLE_DIR/user.reg.volta-bak" "$BOTTLE_DIR/user.reg"
    fi
}
cleanup() {
    if [ -n "$XPID" ]; then
        kill "$XPID" 2>/dev/null
    fi
    rm -f "$PIDFILE"
    restore_registry
}
trap cleanup EXIT

# ── Start Xwayland attached to OUR compositor ───────────────────────
# WAYLAND_DISPLAY=wayland-volta: Xwayland connects as a Wayland CLIENT to
# our compositor (not to the desktop's normal Wayland session). At the
# same time it acts as an X11 SERVER on display ":50" — that is where Wine will
# connect, as it would with any normal X11 server.
# -nolisten tcp: no network socket, only the local Unix socket (safer,
# and it is all we need anyway).
#
# round68b (ABANDONED): I had added "-rootless" thinking a separate
# surface per window was needed, like Android Auto. Wrong: Xwayland's
# man page clearly says that rootless mode requires the
# COMPOSITOR to also act as the X11 window manager (a dedicated component,
# with its own dedicated channel, "-wm fd") — it is what Mutter/KWin/Sway
# wrote for their respective compositors, their code, not an option
# that can be turned on from outside. Without it, rootless Xwayland has nobody to
# hand the windows to: confirmed in the test log, zero toplevels
# arrived at the compositor, not even the generic one from round68.
#
# round68c: we go back WITHOUT "-rootless" (the round68 one, which HAD
# made a toplevel arrive — "Xwayland on :50" — confirming that the
# registry forced to x11 works, Wine really connects to us). Without
# "-rootless" Xwayland does everything by itself: a SINGLE surface that
# represents a complete X11 desktop (we see it as a single
# xdg_toplevel), with any real X11 window inside — including the
# game. "-geometry" fixes the size of that fake desktop: if it is bigger
# than the game window, the panel shows empty X11 background
# around a smaller Wine window (with its frames drawn
# by Wine itself, there being no window manager) — probably what
# has been seen so far. Starting size 1280x720 (typical
# resolution of these games): if the game does not use it entirely, it is the first
# number to adjust. "-geometry" (not "-screen", that one is for normal
# Xorg) is the right flag for Xwayland in rootful mode, verified
# on the man page — incompatible with "-rootless", another reason
# why the two could not be used together.
WAYLAND_DISPLAY=wayland-volta Xwayland ":${DISPLAYNUM}" -nolisten tcp -geometry 1280x720 &
XPID=$!
echo "$XPID" > "$PIDFILE"

# ── Wait for the X socket to be ready (max ~5s) before launching Wine ──
READY=0
for _ in $(seq 1 50); do
    if [ -S "/tmp/.X11-unix/X${DISPLAYNUM}" ]; then
        READY=1
        break
    fi
    sleep 0.1
done

if [ "$READY" != "1" ]; then
    echo "[native_game_xwayland_launch] Xwayland (PID $XPID) not ready after 5s, giving up." >&2
    exit 1
fi

# ── Launch the game via Bottles, pointed at OUR Xwayland (DISPLAY=:50) ─
# round66b: --unset-env removes WAYLAND_DISPLAY from the sandbox instead of
# just overriding it (not enough on its own, see round68 above:
# the real blocker was in the registry, not in the environment — but we leave it
# anyway, it does no harm and closes the door on an inherited WAYLAND_DISPLAY).
#
# round71 — THE REAL BLOCKER of this round, found in the log: no
# "[Compositor] Nuovo toplevel" line EVER appeared, even though our
# Xwayland started and the registry was forced correctly — the
# game never even tried to connect to us. The log shows
# why: among Vulkan's "Enabled instance extensions" there is
# VK_KHR_win32_surface (not VK_KHR_xlib_surface), and right after
# "[Gamescope WSI] Application info: ... Cuphead.exe" / "Made gamescope
# surface for xid: 0xc00031" — a gamescope Vulkan layer (separate from
# OUR gamescope, one called "gamescope-brokey" with
# headless backend was seen, started BY ITSELF) intercepts the creation of the game's
# Vulkan surface BEFORE DXVK can create it on the X11 DISPLAY
# we prepared for it — regardless of the Wine registry, our
# DISPLAY, anything we put in the script. It is always active
# (verified: ENABLE_GAMESCOPE_WSI is the variable that Valve itself
# documents for this, normally set by Proton/by the Wine runners
# for Vulkan titles, here evidently always 1 in Bottles'
# environment) and intercepts BEFORE Wine/winex11.drv come into play.
# Explicitly disabled here for our launch: with this at 0,
# DXVK should create its surface through the "normal" Vulkan path
# (X11/xlib, since the registry forces Graphics=x11), which is
# the one that really reaches our Xwayland and therefore our
# compositor.
#
# NOT CONFIRMED: it only solves gamescope's interception. It does not
# guarantee that DXVK then really chooses xlib_surface instead of some
# other fallback — next concrete experiment, to be verified with the log
# (cercare "Nuovo toplevel" e "VK_KHR_xlib_surface"/"VK_KHR_wayland_surface"
# nelle "Enabled instance extensions").
#
# Blocking: bottles-cli run waits until the game exits (or
# until "bottles-cli stop" terminates it from outside — see stopNativeGame()
# in Arcade.qml, unchanged: it keeps working exactly as before).
flatpak run --unset-env=WAYLAND_DISPLAY --env="DISPLAY=:${DISPLAYNUM}" --env="ENABLE_GAMESCOPE_WSI=0" --command=bottles-cli com.usebottles.bottles run -b "${BOTTLE}" "${FLAG}" "${VALUE}"

# The cleanup (Xwayland + registry restore) fires from the EXIT trap above.
