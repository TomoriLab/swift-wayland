#ifndef WAYLAND_KIT_SERVER_H
#define WAYLAND_KIT_SERVER_H
#include <wayland-server.h>
struct wayland_kit_destroy_watch;
typedef void (*wayland_kit_destroy_notify)(void *data);
/* Watch storage remains owned until the outer native frame returns. */
struct wayland_kit_destroy_watch *wayland_kit_watch_client(struct wl_client *, wayland_kit_destroy_notify, void *);
struct wayland_kit_destroy_watch *wayland_kit_watch_resource(struct wl_resource *, wayland_kit_destroy_notify, void *);
void wayland_kit_watch_destroy(struct wayland_kit_destroy_watch *);
const struct wl_interface *wayland_kit_callback_interface(void);
#endif
