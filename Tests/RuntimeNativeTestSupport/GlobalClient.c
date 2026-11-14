#include "RuntimeNativeTestSupport.h"
#include <wayland-client.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>
struct runtime_test_global_client {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_compositor *compositor;
    struct wl_surface *surface;
    struct wl_callback *callback;
    int advertised;
    int removed;
    int bind;
};
static void found_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version)
{
    struct runtime_test_global_client *client = data;
    if (strcmp(interface, "wl_compositor") != 0) return;
    client->advertised++;
    if (client->bind) {
        client->compositor = wl_registry_bind(registry, name, &wl_compositor_interface, version < 1 ? version : 1);
        assert(client->compositor);
        client->surface = wl_compositor_create_surface(client->compositor);
        assert(client->surface);
    }
}
static void removed_global(void *data, struct wl_registry *registry, uint32_t name)
{
    (void)registry; (void)name;
    ((struct runtime_test_global_client *)data)->removed++;
}
static void global_sync_done(void *data, struct wl_callback *callback, uint32_t serial)
{
    (void)serial;
    ((struct runtime_test_global_client *)data)->callback = NULL;
    wl_callback_destroy(callback);
}
static struct runtime_test_global_client *create_global_client(struct wl_display *display, int bind)
{
    static const struct wl_registry_listener listener = { found_global, removed_global };
    assert(display);
    struct runtime_test_global_client *client = calloc(1, sizeof(*client));
    assert(client);
    client->display = display;
    client->bind = bind;
    client->registry = wl_display_get_registry(display);
    assert(client->registry);
    wl_registry_add_listener(client->registry, &listener, client);
    static const struct wl_callback_listener sync_listener = { global_sync_done };
    client->callback = wl_display_sync(display);
    assert(client->callback);
    wl_callback_add_listener(client->callback, &sync_listener, client);
    assert(wl_display_flush(display) >= 0);
    return client;
}
struct runtime_test_global_client *runtime_test_global_client_create(int descriptor, int bind)
{
    return create_global_client(wl_display_connect_to_fd(descriptor), bind);
}
struct runtime_test_global_client *runtime_test_global_client_connect(const char *path, int bind)
{
    return create_global_client(wl_display_connect(path), bind);
}
int runtime_test_global_client_dispatch(struct runtime_test_global_client *client)
{
    int result = wl_display_dispatch(client->display);
    if (result >= 0) wl_display_flush(client->display);
    return result;
}
int runtime_test_global_client_advertised(struct runtime_test_global_client *client) { return client->advertised; }
int runtime_test_global_client_removed(struct runtime_test_global_client *client) { return client->removed; }
void runtime_test_global_client_destroy(struct runtime_test_global_client *client)
{
    if (client->callback) wl_callback_destroy(client->callback);
    if (client->surface) wl_surface_destroy(client->surface);
    if (client->compositor) wl_compositor_destroy(client->compositor);
    wl_registry_destroy(client->registry);
    wl_display_disconnect(client->display);
    free(client);
}
