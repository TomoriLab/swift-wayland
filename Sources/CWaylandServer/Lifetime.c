#include "CWaylandServer.h"
#include <stdlib.h>
struct wayland_kit_destroy_watch {
    struct wl_listener listener;
    wayland_kit_destroy_notify callback;
    void *data;
    int attached;
};
static void notify_destroy(struct wl_listener *listener, void *object)
{
    struct wayland_kit_destroy_watch *watch = wl_container_of(listener, watch, listener);
    (void)object;
    wl_list_remove(&watch->listener.link);
    wl_list_init(&watch->listener.link);
    watch->attached = 0;
    watch->callback(watch->data);
}
static struct wayland_kit_destroy_watch *create_watch(wayland_kit_destroy_notify callback, void *data)
{
    struct wayland_kit_destroy_watch *watch = calloc(1, sizeof(*watch));
    if (!watch) return NULL;
    watch->listener.notify = notify_destroy;
    wl_list_init(&watch->listener.link);
    watch->callback = callback;
    watch->data = data;
    return watch;
}
struct wayland_kit_destroy_watch *wayland_kit_watch_client(struct wl_client *client, wayland_kit_destroy_notify callback, void *data)
{
    struct wayland_kit_destroy_watch *watch = create_watch(callback, data);
    if (!watch) return NULL;
    wl_client_add_destroy_listener(client, &watch->listener);
    watch->attached = 1;
    return watch;
}
struct wayland_kit_destroy_watch *wayland_kit_watch_resource(struct wl_resource *resource, wayland_kit_destroy_notify callback, void *data)
{
    struct wayland_kit_destroy_watch *watch = create_watch(callback, data);
    if (!watch) return NULL;
    wl_resource_add_destroy_listener(resource, &watch->listener);
    watch->attached = 1;
    return watch;
}
void wayland_kit_watch_destroy(struct wayland_kit_destroy_watch *watch)
{
    if (watch->attached) wl_list_remove(&watch->listener.link);
    free(watch);
}

const struct wl_interface *wayland_kit_callback_interface(void) { return &wl_callback_interface; }
