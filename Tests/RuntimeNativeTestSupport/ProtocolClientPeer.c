#include "RuntimeNativeTestSupport.h"
#include <wayland-client.h>
#include <wayland-server.h>
#include <assert.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

struct runtime_protocol_peer {
    struct wl_display *display;
    struct wl_client *client;
    struct wl_global *global;
    struct wl_resource *parent, *child, *reference;
    unsigned resources, destroyed, requests, descriptors;
};
static const struct wl_interface parent_interface, child_interface;
static const struct wl_interface *child_constructor[] = {&child_interface};
static const struct wl_interface *invoke_types[] = {NULL, &child_interface, NULL, NULL, NULL};
static const struct wl_interface *created_types[] = {&child_interface, NULL, &parent_interface};
static const struct wl_interface *generic_types[] = {NULL, NULL, NULL};
static const struct wl_interface *one_scalar[] = {NULL};
static const struct wl_message parent_requests[] = {
    {"make_child", "n", child_constructor}, {"invoke", "u?o?sah", invoke_types},
    {"emit", "u", one_scalar}, {"destroy", "", NULL},
    {"replace", "2n", child_constructor}, {"create_generic", "2sun", generic_types},
    {"destroy_with_descriptor", "2h", one_scalar}
};
static const struct wl_message parent_events[] = {
    {"scalar", "u", one_scalar}, {"created", "nho", created_types}, {"terminal", "2h", one_scalar}
};
static const struct wl_message child_requests[] = {{"destroy", "", NULL}, {"mark", "u", one_scalar}};
static const struct wl_message child_events[] = {{"value", "u", one_scalar}, {"terminal", "2h", one_scalar}};
static const struct wl_interface parent_interface = {"waylandkit_parent", 2, 7, parent_requests, 3, parent_events};
static const struct wl_interface child_interface = {"waylandkit_child", 2, 2, child_requests, 2, child_events};
static int protocol_request(const void *, void *, uint32_t, const struct wl_message *, union wl_argument *);
static void protocol_destroyed(struct wl_resource *resource)
{
    struct runtime_protocol_peer *peer = wl_resource_get_user_data(resource);
    assert(peer->resources > 0);
    peer->resources--;
    peer->destroyed++;
    if (peer->parent == resource) peer->parent = NULL;
    if (peer->reference == resource) peer->reference = NULL;
    if (peer->child == resource) peer->child = NULL;
}
static struct wl_resource *protocol_resource(struct runtime_protocol_peer *peer, struct wl_client *client,
                                            const struct wl_interface *interface, uint32_t version, uint32_t identifier)
{
    struct wl_resource *resource = wl_resource_create(client, interface, (int)version, identifier);
    assert(resource);
    peer->resources++;
    wl_resource_set_dispatcher(resource, protocol_request, peer, peer, protocol_destroyed);
    return resource;
}
static void protocol_child_value(struct runtime_protocol_peer *peer, struct wl_resource *parent, uint32_t version, uint32_t identifier)
{
    peer->child = protocol_resource(peer, wl_resource_get_client(parent), &child_interface, version, identifier);
    union wl_argument event[] = {{.u = 17}};
    wl_resource_post_event_array(peer->child, 0, event);
}
void runtime_protocol_peer_emit(struct runtime_protocol_peer *peer, unsigned kind, int descriptor)
{
    assert(peer->parent && kind <= 3);
    if (kind == 0) {
        union wl_argument event[] = {{.u = 17}};
        wl_resource_post_event_array(peer->parent, 0, event);
    } else {
        int duplicate = fcntl(descriptor, F_DUPFD_CLOEXEC, 0);
        assert(duplicate >= 0);
        if (kind == 1 || kind == 3) {
            peer->child = protocol_resource(peer, wl_resource_get_client(peer->parent), &child_interface,
                                            (uint32_t)wl_resource_get_version(peer->parent), 0);
            union wl_argument event[] = {{.o = (struct wl_object *)peer->child}, {.h = duplicate}, {.o = (struct wl_object *)(kind == 3 ? peer->reference : peer->parent)}};
            wl_resource_post_event_array(peer->parent, 1, event);
        } else {
            union wl_argument event[] = {{.h = duplicate}};
            wl_resource_post_event_array(peer->parent, 2, event);
            wl_resource_destroy(peer->parent);
        }
        close(duplicate);
    }
    wl_display_flush_clients(peer->display);
}
static int protocol_request(const void *implementation, void *target, uint32_t opcode,
                            const struct wl_message *message, union wl_argument *arguments)
{
    struct runtime_protocol_peer *peer = (struct runtime_protocol_peer *)implementation;
    struct wl_resource *resource = target;
    peer->requests++;
    if (!strcmp(wl_resource_get_class(resource), child_interface.name)) {
        assert(opcode < 2 && message == &child_requests[opcode]);
        if (opcode == 0) wl_resource_destroy(resource);
        else assert(arguments[0].u == 17);
        return 0;
    }
    assert(resource == peer->parent && opcode < 7 && message == &parent_requests[opcode]);
    switch (opcode) {
    case 0: case 4:
        protocol_child_value(peer, resource, (uint32_t)wl_resource_get_version(resource), arguments[0].n);
        if (opcode == 4) wl_resource_destroy(resource);
        break;
    case 1:
        assert(arguments[0].u == 17);
        if (arguments[1].o) assert(!strcmp(wl_resource_get_class((struct wl_resource *)arguments[1].o), child_interface.name));
        if (arguments[2].s) assert(!strcmp(arguments[2].s, "extension"));
        assert(arguments[3].a && arguments[3].a->size == 3 && !memcmp(arguments[3].a->data, "\1\2\3", 3));
        assert(fcntl(arguments[4].h, F_GETFD) >= 0);
        close(arguments[4].h);
        peer->descriptors++;
        break;
    case 2:
        assert(arguments[0].u == 0);
        runtime_protocol_peer_emit(peer, 0, -1);
        break;
    case 3: wl_resource_destroy(resource); break;
    case 5:
        assert(!strcmp(arguments[0].s, child_interface.name) && arguments[1].u > 0 && arguments[1].u <= 2);
        protocol_child_value(peer, resource, arguments[1].u, arguments[2].n);
        break;
    case 6:
        assert(fcntl(arguments[0].h, F_GETFD) >= 0);
        close(arguments[0].h);
        peer->descriptors++;
        wl_resource_destroy(resource);
        break;
    default: abort();
    }
    return 0;
}
static void protocol_bind(struct wl_client *client, void *data, uint32_t version, uint32_t identifier)
{
    struct runtime_protocol_peer *peer = data;
    peer->parent = protocol_resource(peer, client, &parent_interface, version, identifier);
    if (!peer->reference) peer->reference = peer->parent;
}
struct runtime_protocol_peer *runtime_protocol_peer_create(int *descriptor)
{
    struct runtime_protocol_peer *peer = calloc(1, sizeof(*peer));
    if (!peer) return NULL;
    int sockets[2];
    peer->display = wl_display_create();
    if (!peer->display || socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sockets) < 0) {
        if (peer->display) wl_display_destroy(peer->display);
        free(peer); return NULL;
    }
    peer->client = wl_client_create(peer->display, sockets[0]);
    if (!peer->client) { close(sockets[1]); wl_display_destroy(peer->display); free(peer); return NULL; }
    peer->global = wl_global_create(peer->display, &parent_interface, 2, peer, protocol_bind);
    if (!peer->global) { close(sockets[1]); wl_display_destroy_clients(peer->display); wl_display_destroy(peer->display); free(peer); return NULL; }
    *descriptor = sockets[1];
    return peer;
}
void runtime_protocol_peer_destroy(struct runtime_protocol_peer *peer)
{
    wl_display_destroy_clients(peer->display);
    wl_global_destroy(peer->global);
    wl_display_destroy(peer->display);
    assert(peer->resources == 0);
    free(peer);
}
unsigned runtime_protocol_peer_global(struct runtime_protocol_peer *peer) { return wl_global_get_name(peer->global, peer->client); }
int runtime_protocol_peer_dispatch(struct runtime_protocol_peer *peer)
{
    int result = wl_event_loop_dispatch(wl_display_get_event_loop(peer->display), 0);
    wl_display_flush_clients(peer->display);
    return result;
}
unsigned runtime_protocol_peer_resources(struct runtime_protocol_peer *peer) { return peer->resources; }
unsigned runtime_protocol_peer_destroyed(struct runtime_protocol_peer *peer) { return peer->destroyed; }
unsigned runtime_protocol_peer_requests(struct runtime_protocol_peer *peer) { return peer->requests; }
unsigned runtime_protocol_peer_descriptors(struct runtime_protocol_peer *peer) { return peer->descriptors; }

const struct wl_interface *runtime_protocol_peer_interface(void) { return &parent_interface; }
const struct wl_interface *runtime_protocol_peer_child_interface(void) { return &child_interface; }
void runtime_protocol_peer_error(struct runtime_protocol_peer *peer) { wl_resource_post_error(peer->parent, 1, "isolated native cleanup regression"); wl_display_flush_clients(peer->display); }

void runtime_protocol_peer_emit_invalid_object(struct runtime_protocol_peer *peer, int descriptor)
{
    assert(peer->parent);
    peer->child = protocol_resource(peer, peer->client, &child_interface, 2, 0);
    uint32_t wire[] = {wl_resource_get_id(peer->parent), (16u << 16) | 1u,
                       wl_resource_get_id(peer->child), UINT32_MAX};
    struct iovec body = {.iov_base = wire, .iov_len = sizeof(wire)};
    union { struct cmsghdr header; unsigned char bytes[CMSG_SPACE(sizeof(int))]; } control;
    memset(&control, 0, sizeof(control));
    struct msghdr message = {.msg_iov = &body, .msg_iovlen = 1,
                             .msg_control = control.bytes, .msg_controllen = sizeof(control.bytes)};
    struct cmsghdr *rights = CMSG_FIRSTHDR(&message);
    rights->cmsg_level = SOL_SOCKET;
    rights->cmsg_type = SCM_RIGHTS;
    rights->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(rights), &descriptor, sizeof(descriptor));
    assert(sendmsg(wl_client_get_fd(peer->client), &message, 0) == (ssize_t)sizeof(wire));
}
