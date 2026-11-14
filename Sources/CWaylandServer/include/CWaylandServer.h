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
const struct wl_interface *wayland_kit_server_core_interface(const char *name);
void wayland_kit_reject_constructor(struct wl_client *client);
typedef void (*wayland_kit_client_iterator)(struct wl_client *, void *);
void wayland_kit_each_client(struct wl_display *, wayland_kit_client_iterator, void *);
void wayland_kit_resource_error(struct wl_resource *, uint32_t, const char *);
void wayland_kit_client_error(struct wl_client *, const char *);
#include "WaylandLogScope.h"
void wayland_kit_server_raw_log_handler(wayland_runtime_raw_log_callback callback);
/* Copies packed native four-byte pixel rows inside one balanced SHM access scope. */
int wayland_kit_shm_snapshot(struct wl_shm_buffer *buffer, unsigned char *output, size_t length);
#endif
