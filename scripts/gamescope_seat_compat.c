// gamescope_seat_compat.c — LD_PRELOAD shim for gamescope ONLY.
//
// Problem: gamescope (3.15 .. 3.16.x) accepts wl_seat only if the version
// announced by the compositor is >= 8 (WaylandBackend.cpp: "uVersion >= 8u").
// The Volta compositor is QtWayland, which ALWAYS announces wl_seat version 4
// (qwaylandseat.cpp: d->init(display, 4)). Result:
//   "xdg_backend: Couldn't create Wayland input objects."
//
// This shim, loaded only inside gamescope:
//  1) shows wl_seat to gamescope as version 8 (from the registry callback)
//  2) when gamescope binds v8, it brings it back to the real version (4),
//     so the server does not answer with "invalid version".
// gamescope uses nothing newer than v3 (wl_pointer_release /
// wl_keyboard_release), so everything works with v4.
// It does not touch any other process (it is active only if the name is "gamescope*").
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

#define NARGS 12
static int g_on = -1;
static struct { uint32_t name, version; int used; } g_seat[16];

static int enabled(void)
{
    if (g_on < 0) {
        const char *n = program_invocation_short_name;
        g_on = (n && !strncmp(n, "gamescope", 9)) ? 1 : 0;
        if (g_on && getenv("VOLTA_SEAT_COMPAT_DEBUG"))
            fprintf(stderr, "[seat-compat] attivo in %s\n", n);
    }
    return g_on;
}

struct reg_wrap {
    const struct wl_registry_listener *orig;
    void *odata;
};

static void w_global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t version)
{
    struct reg_wrap *w = d;
    if (iface && !strcmp(iface, "wl_seat") && version < 8) {
        for (int i = 0; i < 16; i++) {
            if (!g_seat[i].used || g_seat[i].name == name) {
                g_seat[i].used = 1; g_seat[i].name = name; g_seat[i].version = version;
                break;
            }
        }
        if (getenv("VOLTA_SEAT_COMPAT_DEBUG"))
            fprintf(stderr, "[seat-compat] wl_seat v%u annunciato come v8\n", version);
        version = 8;
    }
    if (w->orig && w->orig->global) w->orig->global(w->odata, r, name, iface, version);
}

static void w_remove(void *d, struct wl_registry *r, uint32_t name)
{
    struct reg_wrap *w = d;
    if (w->orig && w->orig->global_remove) w->orig->global_remove(w->odata, r, name);
}

static const struct wl_registry_listener g_wrapper = { w_global, w_remove };

int wl_proxy_add_listener(struct wl_proxy *proxy, void (**impl)(void), void *data)
{
    static int (*real)(struct wl_proxy *, void (**)(void), void *);
    if (!real) real = dlsym(RTLD_NEXT, "wl_proxy_add_listener");
    if (enabled()) {
        const char *cls = wl_proxy_get_class(proxy);
        if (cls && !strcmp(cls, "wl_registry")) {
            struct reg_wrap *w = malloc(sizeof *w);
            if (w) {
                w->orig = (const struct wl_registry_listener *)impl;
                w->odata = data;
                return real(proxy, (void (**)(void))&g_wrapper, w);
            }
        }
    }
    return real(proxy, impl, data);
}

static uint32_t seat_real_version(uint32_t name)
{
    for (int i = 0; i < 16; i++)
        if (g_seat[i].used && g_seat[i].name == name) return g_seat[i].version;
    return 0;
}

// Rewrites (if needed) the parameters of a bind to wl_seat. a[0]=name a[1]=interface
// name a[2]=version (see wl_registry_bind in wayland-client-protocol.h)
static void fix_bind(struct wl_proxy *proxy, uint32_t opcode, const struct wl_interface *iface,
                     uint32_t *version, uintptr_t *a)
{
    if (!enabled() || opcode != 0 || !iface || !iface->name || strcmp(iface->name, "wl_seat")) return;
    const char *cls = wl_proxy_get_class(proxy);
    if (!cls || strcmp(cls, "wl_registry")) return;
    uint32_t rv = seat_real_version((uint32_t)a[0]);
    if (rv && *version > rv) {
        if (getenv("VOLTA_SEAT_COMPAT_DEBUG"))
            fprintf(stderr, "[seat-compat] bind wl_seat v%u -> v%u\n", *version, rv);
        *version = rv;
        a[2] = rv;
    }
}

// The variadic arguments of libwayland are all of "integer" class on
// x86-64 (uint/int/pointers/fd/new_id=NULL): I read them back as uintptr_t and
// pass them unchanged to the real function. Only the bind to wl_seat is touched.
struct wl_proxy *wl_proxy_marshal_flags(struct wl_proxy *proxy, uint32_t opcode,
                                        const struct wl_interface *interface,
                                        uint32_t version, uint32_t flags, ...)
{
    static struct wl_proxy *(*real)(struct wl_proxy *, uint32_t, const struct wl_interface *,
                                    uint32_t, uint32_t, ...);
    if (!real) real = dlsym(RTLD_NEXT, "wl_proxy_marshal_flags");
    uintptr_t a[NARGS];
    va_list ap;
    va_start(ap, flags);
    for (int i = 0; i < NARGS; i++) a[i] = va_arg(ap, uintptr_t);
    va_end(ap);
    fix_bind(proxy, opcode, interface, &version, a);
    return real(proxy, opcode, interface, version, flags,
                a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11]);
}

// Old version of the API (libwayland < 1.20), just in case.
struct wl_proxy *wl_proxy_marshal_constructor_versioned(struct wl_proxy *proxy, uint32_t opcode,
                                                        const struct wl_interface *interface,
                                                        uint32_t version, ...)
{
    static struct wl_proxy *(*real)(struct wl_proxy *, uint32_t, const struct wl_interface *,
                                    uint32_t, ...);
    if (!real) real = dlsym(RTLD_NEXT, "wl_proxy_marshal_constructor_versioned");
    uintptr_t a[NARGS];
    va_list ap;
    va_start(ap, version);
    for (int i = 0; i < NARGS; i++) a[i] = va_arg(ap, uintptr_t);
    va_end(ap);
    fix_bind(proxy, opcode, interface, &version, a);
    return real(proxy, opcode, interface, version,
                a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11]);
}
