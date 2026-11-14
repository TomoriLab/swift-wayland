#include "RuntimeNativeTestSupport.h"
#include <wayland-client.h>
#include <wayland-server.h>
#include <assert.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
struct descriptor_peer {
    const struct wl_interface *alpha;
    struct wl_resource *resource;
    struct wl_proxy *proxy;
    uint32_t name;
    unsigned events;
};
static int descriptor_request(const void *implementation, void *target, uint32_t opcode,
                              const struct wl_message *message, union wl_argument *arguments)
{
    struct descriptor_peer *peer = (struct descriptor_peer *)implementation;
    assert(opcode == 0 && target == peer->resource && message == &peer->alpha->methods[0]);
    struct wl_resource *child = wl_resource_create(wl_resource_get_client(target), peer->alpha->methods[0].types[0], 1, arguments[0].n);
    assert(child);
    union wl_argument event[] = {{.o = (struct wl_object *)target}, {.u = 17}};
    wl_resource_post_event_array(child, 0, event);
    return 0;
}
static void descriptor_bind(struct wl_client *client, void *data, uint32_t version, uint32_t identifier)
{
    struct descriptor_peer *peer = data;
    peer->resource = wl_resource_create(client, peer->alpha, (int)version, identifier);
    assert(peer->resource);
    wl_resource_set_dispatcher(peer->resource, descriptor_request, peer, NULL, NULL);
}
static void descriptor_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version)
{
    (void)registry;
    struct descriptor_peer *peer = data;
    if (!strcmp(interface, peer->alpha->name)) { assert(version == 2); peer->name = name; }
}
static void descriptor_removed(void *data, struct wl_registry *registry, uint32_t name) { (void)data; (void)registry; (void)name; }
static int descriptor_event(const void *implementation, void *target, uint32_t opcode,
                            const struct wl_message *message, union wl_argument *arguments)
{
    (void)target;
    struct descriptor_peer *peer = (struct descriptor_peer *)implementation;
    assert(opcode == 0 && message == &peer->alpha->methods[0].types[0]->events[0]);
    assert(arguments[0].o == (struct wl_object *)peer->proxy && arguments[1].u == 17);
    peer->events++;
    return 0;
}
static void descriptor_transfer(struct wl_display *server, struct wl_display *client, int read)
{
    assert(wl_display_flush(client) >= 0);
    assert(wl_event_loop_dispatch(wl_display_get_event_loop(server), 0) >= 0);
    wl_display_flush_clients(server);
    if (read) {
        assert(wl_display_prepare_read(client) == 0);
        assert(wl_display_read_events(client) == 0);
        assert(wl_display_dispatch_pending(client) >= 0);
    }
}
int runtime_descriptor_roundtrip(const struct wl_interface *alpha)
{
    assert(alpha && !strcmp(alpha->name, "alpha") && alpha->version == 2 && alpha->method_count == 1);
    const struct wl_interface *beta = alpha->methods[0].types[0];
    assert(beta && !strcmp(beta->name, "beta") && beta->event_count == 1);
    assert(!strcmp(alpha->methods[0].signature, "n") && !strcmp(beta->events[0].signature, "ou"));
    assert(beta->events[0].types[0] == alpha && beta->events[0].types[1] == NULL);
    struct descriptor_peer peer = {.alpha = alpha};
    struct wl_display *server = wl_display_create();
    int sockets[2];
    assert(server && socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sockets) == 0);
    assert(wl_client_create(server, sockets[0]));
    struct wl_display *client = wl_display_connect_to_fd(sockets[1]);
    assert(client);
    struct wl_global *global = wl_global_create(server, alpha, 2, &peer, descriptor_bind);
    assert(global);
    struct wl_registry *registry = wl_display_get_registry(client);
    const struct wl_registry_listener listener = {descriptor_global, descriptor_removed};
    assert(wl_registry_add_listener(registry, &listener, &peer) == 0);
    descriptor_transfer(server, client, 1);
    assert(peer.name);
    peer.proxy = wl_registry_bind(registry, peer.name, alpha, 2);
    assert(peer.proxy);
    descriptor_transfer(server, client, 0);
    union wl_argument constructor[] = {{.o = NULL}};
    struct wl_proxy *child = wl_proxy_marshal_array_constructor_versioned(peer.proxy, 0, constructor, beta, 1);
    assert(child && wl_proxy_add_dispatcher(child, descriptor_event, &peer, NULL) == 0);
    descriptor_transfer(server, client, 1);
    assert(peer.events == 1);
    wl_proxy_destroy(child);
    wl_proxy_destroy(peer.proxy);
    wl_registry_destroy(registry);
    wl_display_disconnect(client);
    wl_display_destroy_clients(server);
    wl_global_destroy(global);
    wl_display_destroy(server);
    return 1;
}
