#include "RuntimeNativeTestSupport.h"
#include <wayland-client.h>
#include <assert.h>
#include <stdlib.h>

struct runtime_extension_server_client {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_proxy *parent;
    struct wl_proxy *child;
    unsigned events;
};

static int receive(const void *implementation, void *target, uint32_t opcode,
                   const struct wl_message *message, union wl_argument *arguments)
{
    (void)target;
    (void)message;
    struct runtime_extension_server_client *client = (struct runtime_extension_server_client *)implementation;
    assert(opcode == 0 && arguments[0].u == 17);
    client->events++;
    return 0;
}

struct runtime_extension_server_client *runtime_extension_server_client_create(int descriptor)
{
    struct runtime_extension_server_client *client = calloc(1, sizeof(*client));
    if (!client) return NULL;
    client->display = wl_display_connect_to_fd(descriptor);
    assert(client->display);
    client->parent = wl_proxy_create((struct wl_proxy *)client->display, runtime_protocol_peer_interface());
    assert(client->parent && wl_proxy_get_id(client->parent) == 2);
    assert(wl_proxy_add_dispatcher(client->parent, receive, client, NULL) == 0);
    return client;
}

struct runtime_extension_server_client *runtime_extension_server_client_prepare_global(int descriptor)
{
    struct runtime_extension_server_client *client = calloc(1, sizeof(*client));
    if (!client) return NULL;
    client->display = wl_display_connect_to_fd(descriptor);
    assert(client->display);
    client->registry = wl_display_get_registry(client->display);
    assert(client->registry);
    assert(wl_display_flush(client->display) >= 0);
    return client;
}

int runtime_extension_server_client_bind(struct runtime_extension_server_client *client, uint32_t name)
{
    assert(client->registry && !client->parent && name != 0);
    client->parent = wl_registry_bind(client->registry, name, runtime_protocol_peer_interface(), 2);
    assert(client->parent);
    assert(wl_proxy_add_dispatcher(client->parent, receive, client, NULL) == 0);
    return wl_display_flush(client->display);
}

int runtime_extension_server_client_request(struct runtime_extension_server_client *client)
{
    union wl_argument arguments[] = {{.u = 0}};
    wl_proxy_marshal_array(client->parent, 2, arguments);
    return wl_display_flush(client->display);
}

int runtime_extension_server_client_construct(struct runtime_extension_server_client *client)
{
    client->child = wl_proxy_marshal_constructor(client->parent, 0, runtime_protocol_peer_child_interface());
    assert(client->child);
    return wl_display_flush(client->display);
}

int runtime_extension_server_client_destroy_child(struct runtime_extension_server_client *client)
{
    assert(client->child);
    wl_proxy_marshal(client->child, 0);
    wl_proxy_destroy(client->child);
    client->child = NULL;
    return wl_display_flush(client->display);
}

int runtime_extension_server_client_dispatch(struct runtime_extension_server_client *client)
{
    return wl_display_dispatch(client->display);
}

unsigned runtime_extension_server_client_events(struct runtime_extension_server_client *client)
{
    return client->events;
}

void runtime_extension_server_client_destroy(struct runtime_extension_server_client *client)
{
    if (client->child) wl_proxy_destroy(client->child);
    if (client->parent) wl_proxy_destroy(client->parent);
    if (client->registry) wl_registry_destroy(client->registry);
    wl_display_disconnect(client->display);
    free(client);
}
