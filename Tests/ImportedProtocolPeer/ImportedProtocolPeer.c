#define _GNU_SOURCE
#include "ImportedProtocolPeer.h"
#include <wayland-server.h>
#include <assert.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <unistd.h>

extern const struct wl_interface xdg_wm_base_interface;
extern const struct wl_interface xdg_positioner_interface;
extern const struct wl_interface xdg_surface_interface;
extern const struct wl_interface xdg_toplevel_interface;

struct imported_protocol_peer {
    struct wl_display *display;
    struct wl_client *client;
    struct wl_global *global;
    struct wl_global *compositor_global;
    struct wl_resource *resource;
    struct wl_resource *positioner;
    struct wl_resource *compositor;
    struct wl_resource *surface;
    struct wl_resource *xdg_surface;
    struct wl_resource *toplevel;
    unsigned pongs;
    unsigned positioner_sizes;
    unsigned configure_acks;
};

static void resource_destroyed(struct wl_resource *resource);

static int handle_request(const void *implementation, void *target, uint32_t opcode,
                          const struct wl_message *message, union wl_argument *arguments)
{
    struct imported_protocol_peer *peer = (struct imported_protocol_peer *)implementation;
    struct wl_resource *resource = target;
    if (resource == peer->positioner) {
        assert(opcode < (uint32_t)xdg_positioner_interface.method_count);
        assert(message == &xdg_positioner_interface.methods[opcode]);
        if (opcode == 0) wl_resource_destroy(resource);
        else if (opcode == 1) {
            assert(arguments[0].i == 100 && arguments[1].i == 200);
            peer->positioner_sizes++;
        } else abort();
    } else if (resource == peer->compositor) {
        assert(opcode == 0 && message == &wl_compositor_interface.methods[opcode]);
        assert(peer->surface == NULL);
        peer->surface = wl_resource_create(peer->client, &wl_surface_interface,
                                           wl_resource_get_version(resource), arguments[0].n);
        assert(peer->surface);
        wl_resource_set_dispatcher(peer->surface, handle_request, peer, peer, resource_destroyed);
    } else if (resource == peer->surface) {
        assert(opcode == 0 && message == &wl_surface_interface.methods[opcode]);
        wl_resource_destroy(resource);
    } else if (resource == peer->xdg_surface) {
        assert(opcode < (uint32_t)xdg_surface_interface.method_count);
        assert(message == &xdg_surface_interface.methods[opcode]);
        if (opcode == 0) wl_resource_destroy(resource);
        else if (opcode == 1) {
            assert(peer->toplevel == NULL);
            peer->toplevel = wl_resource_create(peer->client, &xdg_toplevel_interface,
                                                wl_resource_get_version(resource), arguments[0].n);
            assert(peer->toplevel);
            wl_resource_set_dispatcher(peer->toplevel, handle_request, peer, peer, resource_destroyed);
            struct wl_array states;
            wl_array_init(&states);
            wl_resource_post_event(peer->toplevel, 0, 800, 600, &states);
            wl_resource_post_event(resource, 0, UINT32_C(0xabcdef12));
            wl_array_release(&states);
        } else if (opcode == 4) {
            assert(arguments[0].u == UINT32_C(0xabcdef12));
            peer->configure_acks++;
        } else abort();
    } else if (resource == peer->toplevel) {
        assert(opcode == 0 && message == &xdg_toplevel_interface.methods[opcode]);
        wl_resource_destroy(resource);
    } else {
        assert(resource == peer->resource);
        assert(opcode < (uint32_t)xdg_wm_base_interface.method_count);
        assert(message == &xdg_wm_base_interface.methods[opcode]);
        if (opcode == 1) {
            assert(peer->positioner == NULL);
            peer->positioner = wl_resource_create(peer->client, &xdg_positioner_interface,
                                                  wl_resource_get_version(resource), arguments[0].n);
            assert(peer->positioner);
            wl_resource_set_dispatcher(peer->positioner, handle_request, peer, peer, resource_destroyed);
        } else if (opcode == 2) {
            assert((void *)arguments[1].o == (void *)peer->surface && peer->xdg_surface == NULL);
            peer->xdg_surface = wl_resource_create(peer->client, &xdg_surface_interface,
                                                   wl_resource_get_version(resource), arguments[0].n);
            assert(peer->xdg_surface);
            wl_resource_set_dispatcher(peer->xdg_surface, handle_request, peer, peer, resource_destroyed);
        } else if (opcode == 0) {
            wl_resource_destroy(resource);
        } else if (opcode == 3) {
            assert(arguments[0].u == 0x12345678);
            peer->pongs++;
        } else abort();
    }
    return 0;
}

static void resource_destroyed(struct wl_resource *resource)
{
    struct imported_protocol_peer *peer = wl_resource_get_user_data(resource);
    if (peer->resource == resource) peer->resource = NULL;
    else if (peer->positioner == resource) peer->positioner = NULL;
    else if (peer->compositor == resource) peer->compositor = NULL;
    else if (peer->surface == resource) peer->surface = NULL;
    else if (peer->xdg_surface == resource) peer->xdg_surface = NULL;
    else { assert(peer->toplevel == resource); peer->toplevel = NULL; }
}

static void bind_global(struct wl_client *client, void *data, uint32_t version, uint32_t identifier)
{
    struct imported_protocol_peer *peer = data;
    assert(peer->resource == NULL && version <= 7);
    peer->resource = wl_resource_create(client, &xdg_wm_base_interface, (int)version, identifier);
    assert(peer->resource);
    wl_resource_set_dispatcher(peer->resource, handle_request, peer, peer, resource_destroyed);
    wl_resource_post_event(peer->resource, 0, UINT32_C(0x12345678));
}

static void bind_compositor(struct wl_client *client, void *data, uint32_t version, uint32_t identifier)
{
    struct imported_protocol_peer *peer = data;
    assert(peer->compositor == NULL);
    peer->compositor = wl_resource_create(client, &wl_compositor_interface, (int)version, identifier);
    assert(peer->compositor);
    wl_resource_set_dispatcher(peer->compositor, handle_request, peer, peer, resource_destroyed);
}

struct imported_protocol_peer *imported_protocol_peer_create(int *descriptor)
{
    struct imported_protocol_peer *peer = calloc(1, sizeof(*peer));
    if (!peer) return NULL;
    int sockets[2];
    peer->display = wl_display_create();
    if (!peer->display || socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sockets) < 0) {
        if (peer->display) wl_display_destroy(peer->display);
        free(peer);
        return NULL;
    }
    peer->client = wl_client_create(peer->display, sockets[0]);
    if (!peer->client) {
        close(sockets[1]);
        wl_display_destroy(peer->display);
        free(peer);
        return NULL;
    }
    peer->global = wl_global_create(peer->display, &xdg_wm_base_interface, 7, peer, bind_global);
    if (!peer->global) {
        close(sockets[1]);
        wl_display_destroy_clients(peer->display);
        wl_display_destroy(peer->display);
        free(peer);
        return NULL;
    }
    peer->compositor_global = wl_global_create(peer->display, &wl_compositor_interface, 1, peer, bind_compositor);
    if (!peer->compositor_global) {
        close(sockets[1]);
        wl_global_destroy(peer->global);
        wl_display_destroy_clients(peer->display);
        wl_display_destroy(peer->display);
        free(peer);
        return NULL;
    }
    *descriptor = sockets[1];
    return peer;
}

uint32_t imported_protocol_peer_global(struct imported_protocol_peer *peer)
{
    return wl_global_get_name(peer->global, peer->client);
}
uint32_t imported_protocol_peer_compositor_global(struct imported_protocol_peer *peer)
{
    return wl_global_get_name(peer->compositor_global, peer->client);
}

int imported_protocol_peer_dispatch(struct imported_protocol_peer *peer)
{
    int result = wl_event_loop_dispatch(wl_display_get_event_loop(peer->display), 0);
    wl_display_flush_clients(peer->display);
    return result;
}

unsigned imported_protocol_peer_pongs(struct imported_protocol_peer *peer) { return peer->pongs; }
unsigned imported_protocol_peer_positioner_sizes(struct imported_protocol_peer *peer) { return peer->positioner_sizes; }
unsigned imported_protocol_peer_configure_acks(struct imported_protocol_peer *peer) { return peer->configure_acks; }
unsigned imported_protocol_peer_resources(struct imported_protocol_peer *peer)
{
    return (peer->resource != NULL) + (peer->positioner != NULL) + (peer->compositor != NULL) +
           (peer->surface != NULL) + (peer->xdg_surface != NULL) + (peer->toplevel != NULL);
}

void imported_protocol_peer_destroy(struct imported_protocol_peer *peer)
{
    wl_display_destroy_clients(peer->display);
    assert(imported_protocol_peer_resources(peer) == 0);
    wl_global_destroy(peer->compositor_global);
    wl_global_destroy(peer->global);
    wl_display_destroy(peer->display);
    free(peer);
}
