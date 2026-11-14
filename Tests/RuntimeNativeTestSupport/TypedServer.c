#include "RuntimeNativeTestSupport.h"
#include <wayland-server.h>
#include <assert.h>
#include <unistd.h>
struct runtime_test_server { struct wl_display *display; struct wl_client *client; struct wl_global *global; };
static void typed_destroy(struct wl_client *client, struct wl_resource *resource)
{
    (void)client;
    wl_resource_destroy(resource);
}
static void typed_surface(struct wl_client *client, struct wl_resource *parent, uint32_t identifier)
{
    static const struct wl_surface_interface implementation = { .destroy = typed_destroy };
    struct wl_resource *resource = wl_resource_create(client, &wl_surface_interface, wl_resource_get_version(parent), identifier);
    assert(resource);
    wl_resource_set_implementation(resource, &implementation, NULL, NULL);
}
void bind_test_compositor(struct wl_client *client, void *data, uint32_t version, uint32_t identifier)
{
    (void)data;
    static const struct wl_compositor_interface implementation = { .create_surface = typed_surface };
    struct wl_resource *resource = wl_resource_create(client, &wl_compositor_interface, (int)version, identifier);
    assert(resource);
    wl_resource_set_implementation(resource, &implementation, NULL, NULL);
}
static void bind_typed_keyboard(struct wl_client *client, void *data, uint32_t version, uint32_t identifier)
{
    (void)data;
    struct wl_resource *resource = wl_resource_create(client, &wl_keyboard_interface, (int)version, identifier);
    assert(resource);
    int descriptor = runtime_test_descriptor_open();
    wl_keyboard_send_keymap(resource, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, descriptor, 17);
    close(descriptor);
}
static void bind_typed_data_device(struct wl_client *client, void *data, uint32_t version, uint32_t identifier)
{
    (void)data;
    struct wl_resource *resource = wl_resource_create(client, &wl_data_device_interface, (int)version, identifier);
    struct wl_resource *offer = wl_resource_create(client, &wl_data_offer_interface, (int)version, 0);
    assert(resource && offer);
    static const struct wl_data_offer_interface implementation = { .destroy = typed_destroy };
    wl_resource_set_implementation(offer, &implementation, NULL, NULL);
    wl_data_device_send_data_offer(resource, offer);
    wl_data_offer_send_offer(offer, "text/plain");
}
void runtime_test_server_add_typed_globals(struct runtime_test_server *server)
{
    assert(wl_global_create(server->display, &wl_keyboard_interface, 1, NULL, bind_typed_keyboard));
    assert(wl_global_create(server->display, &wl_data_device_interface, 1, NULL, bind_typed_data_device));
}
