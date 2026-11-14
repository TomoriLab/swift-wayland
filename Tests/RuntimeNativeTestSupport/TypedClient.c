#include "RuntimeNativeTestSupport.h"
#include <wayland-client.h>
#include <assert.h>
#include <stdlib.h>
#include <unistd.h>
struct runtime_test_typed_client {
    struct wl_display *display;
    struct wl_proxy *root;
    struct wl_proxy *child;
    unsigned kind;
    int descriptors;
    int offers;
};
static void typed_keymap(void *data, struct wl_keyboard *keyboard, uint32_t format, int descriptor, uint32_t size)
{
    (void)keyboard;
    assert(format == WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1 && size == 17);
    ((struct runtime_test_typed_client *)data)->descriptors++;
    close(descriptor);
}
static void typed_offer(void *data, struct wl_data_offer *offer, const char *mime)
{
    (void)offer; (void)mime;
    ((struct runtime_test_typed_client *)data)->offers++;
}
static void typed_data_offer(void *data, struct wl_data_device *device, struct wl_data_offer *offer)
{
    (void)device;
    static const struct wl_data_offer_listener listener = { .offer = typed_offer };
    struct runtime_test_typed_client *client = data;
    client->child = (struct wl_proxy *)offer;
    wl_data_offer_add_listener(offer, &listener, data);
}
struct runtime_test_typed_client *runtime_test_typed_client_create(int descriptor, unsigned kind)
{
    struct runtime_test_typed_client *client = calloc(1, sizeof(*client));
    assert(client);
    client->display = wl_display_connect_to_fd(descriptor);
    assert(client->display);
    const struct wl_interface *interface = kind == 0 ? &wl_compositor_interface : kind == 1 ? &wl_shm_interface :
                                         kind == 2 ? &wl_keyboard_interface : &wl_data_device_interface;
    client->root = wl_proxy_create((struct wl_proxy *)client->display, interface);
    assert(client->root && wl_proxy_get_id(client->root) == 2);
    client->kind = kind;
    if (kind == 2) {
        static const struct wl_keyboard_listener listener = { .keymap = typed_keymap };
        wl_keyboard_add_listener((struct wl_keyboard *)client->root, &listener, client);
    } else if (kind == 3) {
        static const struct wl_data_device_listener listener = { .data_offer = typed_data_offer };
        wl_data_device_add_listener((struct wl_data_device *)client->root, &listener, client);
    }
    return client;
}
int runtime_test_typed_client_construct(struct runtime_test_typed_client *client, int descriptor)
{
    if (client->kind == 0) client->child = (struct wl_proxy *)wl_compositor_create_surface((struct wl_compositor *)client->root);
    else client->child = (struct wl_proxy *)wl_shm_create_pool((struct wl_shm *)client->root, descriptor, 17);
    return wl_display_flush(client->display);
}
int runtime_test_typed_client_destroy_child(struct runtime_test_typed_client *client)
{
    assert(client->child);
    if (client->kind == 0) wl_surface_destroy((struct wl_surface *)client->child);
    else if (client->kind == 1) wl_shm_pool_destroy((struct wl_shm_pool *)client->child);
    else wl_data_offer_destroy((struct wl_data_offer *)client->child);
    client->child = NULL;
    return wl_display_flush(client->display);
}
int runtime_test_typed_client_dispatch(struct runtime_test_typed_client *client) { return wl_display_dispatch(client->display); }
int runtime_test_typed_client_descriptors(struct runtime_test_typed_client *client) { return client->descriptors; }
int runtime_test_typed_client_offers(struct runtime_test_typed_client *client) { return client->offers; }
void runtime_test_typed_client_destroy(struct runtime_test_typed_client *client)
{
    if (client->child) wl_proxy_destroy(client->child);
    wl_proxy_destroy(client->root);
    wl_display_disconnect(client->display);
    free(client);
}

unsigned runtime_test_typed_client_protocol_error(struct runtime_test_typed_client *client)
{
    return wl_display_get_protocol_error(client->display, NULL, NULL);
}
