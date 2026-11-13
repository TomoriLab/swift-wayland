#ifndef WAYLAND_KIT_CLIENT_H
#define WAYLAND_KIT_CLIENT_H
#include <wayland-client.h>
/* The implementation pointer belongs to one permanent runtime context. */
typedef int (*wayland_kit_dispatcher)(const void *, void *, uint32_t, const struct wl_message *, union wl_argument *);
int wayland_kit_install_dispatcher(struct wl_proxy *proxy, wayland_kit_dispatcher dispatcher, void *context);
/* Consumes owned input obligations that a snapshot handler cannot retain. */
void wayland_kit_discard_event(const struct wl_message *message, union wl_argument *arguments);
/* Returns readable=1, timeout=0, canceled=2, or failure=-1 with saved errno. */
int wayland_kit_wait_readable(struct wl_display *, int wake_descriptor, int timeout, int *error);
struct wl_proxy *wayland_kit_sync_on_queue(struct wl_display *, struct wl_event_queue *);
#endif
