#include "RuntimeNativeTestSupport.h"
#include <wayland-server.h>
#include <sys/socket.h>
#include <assert.h>
#include <ctype.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "CorePeerTables.h"
#define CORE_COUNT (sizeof(core_interfaces) / sizeof(core_interfaces[0]))
struct core_global_context { struct runtime_core_server *server; unsigned interface; struct wl_global *global; };
struct runtime_core_server {
    struct wl_display *display;
    struct wl_client *client;
    struct core_global_context globals[CORE_COUNT];
    unsigned requests, last_opcode, resources;
    const char *last_interface;
    const char *last_constructor;
};
struct core_resource_context { struct runtime_core_server *server; unsigned interface; };
static unsigned core_index(const struct wl_interface *interface)
{
    for (unsigned index = 0; index < CORE_COUNT; index++)
        if (!strcmp(interface->name, core_interfaces[index]->name)) return index;
    abort();
}
static struct wl_resource *core_resource(struct runtime_core_server *, unsigned, int, uint32_t);
static int core_dispatch(const void *implementation, void *target, uint32_t opcode,
                         const struct wl_message *message, union wl_argument *arguments)
{
    (void)implementation;
    struct wl_resource *resource = target;
    struct core_resource_context *context = wl_resource_get_user_data(resource);
    struct runtime_core_server *server = context->server;
    const char *signature = message->signature;
    unsigned index = 0;
    int nullable = 0;
    server->requests++;
    server->last_opcode = opcode;
    server->last_interface = core_interfaces[context->interface]->name;
    server->last_constructor = NULL;
    for (; *signature; signature++) {
        char kind = *signature;
        if (isdigit((unsigned char)kind)) continue;
        if (kind == '?') { nullable = 1; continue; }
        assert(index < 20);
        switch (kind) {
        case 'i': assert(arguments[index].i == -123); break;
        case 'u': assert(arguments[index].u == 17); break;
        case 'f': assert(arguments[index].f == -123); break;
        case 's':
            if (!arguments[index].s) assert(nullable);
            else assert(!strcmp(arguments[index].s, "waylandkit-test"));
            break;
        case 'a':
            assert(arguments[index].a && arguments[index].a->size == 3);
            assert(!memcmp(arguments[index].a->data, "\x21\x22\x23", 3));
            break;
        case 'h':
            assert(fcntl(arguments[index].h, F_GETFD) >= 0);
            close(arguments[index].h); arguments[index].h = -1;
            break;
        case 'o':
            if (!arguments[index].o) assert(nullable);
            else if (message->types[index])
                assert(!strcmp(wl_resource_get_class((struct wl_resource *)arguments[index].o), message->types[index]->name));
            break;
        case 'n': {
            assert(message->types[index]);
            unsigned child = core_index(message->types[index]);
            int version = wl_resource_get_version(resource);
            if (version > core_interfaces[child]->version) version = core_interfaces[child]->version;
            assert(core_resource(server, child, version, arguments[index].n));
            server->last_constructor = core_interfaces[child]->name;
            break;
        }
        default: abort();
        }
        nullable = 0;
        index++;
    }
    if (!strcmp(core_interfaces[context->interface]->name, "wl_fixes") && opcode == 1)
        wl_resource_destroy((struct wl_resource *)arguments[0].o);
    if (requests_destructors[context->interface] & (UINT64_C(1) << opcode)) wl_resource_destroy(resource);
    return 0;
}
static void destroy_core_resource(struct wl_resource *resource)
{
    struct core_resource_context *context = wl_resource_get_user_data(resource);
    assert(context->server->resources > 0);
    context->server->resources--;
    free(context);
}
static struct wl_resource *core_resource(struct runtime_core_server *server, unsigned interface, int version, uint32_t identifier)
{
    struct wl_resource *resource = wl_resource_create(server->client, core_interfaces[interface], version, identifier);
    assert(resource);
    struct core_resource_context *context = malloc(sizeof(*context));
    assert(context);
    context->server = server; context->interface = interface;
    server->resources++;
    wl_resource_set_dispatcher(resource, core_dispatch, NULL, context, destroy_core_resource);
    return resource;
}
static void bind_core_global(struct wl_client *client, void *data, uint32_t version, uint32_t identifier)
{
    struct core_global_context *context = data;
    assert(client == context->server->client);
    core_resource(context->server, context->interface, (int)version, identifier);
}
struct runtime_core_server *runtime_core_server_create(int *descriptor)
{
    int sockets[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sockets) == 0);
    struct runtime_core_server *server = calloc(1, sizeof(*server));
    assert(server);
    server->display = wl_display_create(); assert(server->display);
    server->client = wl_client_create(server->display, sockets[0]); assert(server->client);
    for (unsigned index = 2; index < CORE_COUNT; index++) {
        server->globals[index].server = server; server->globals[index].interface = index;
        server->globals[index].global = wl_global_create(server->display, core_interfaces[index], core_interfaces[index]->version,
                                                       &server->globals[index], bind_core_global);
        assert(server->globals[index].global);
    }
    *descriptor = sockets[1];
    return server;
}
unsigned runtime_core_server_global(struct runtime_core_server *server, const char *name)
{
    for (unsigned index = 2; index < CORE_COUNT; index++)
        if (!strcmp(core_interfaces[index]->name, name)) return wl_global_get_name(server->globals[index].global, server->client);
    abort();
}
int runtime_core_server_dispatch(struct runtime_core_server *server)
{
    int result = wl_event_loop_dispatch(wl_display_get_event_loop(server->display), 0);
    wl_display_flush_clients(server->display);
    return result;
}
unsigned runtime_core_server_requests(struct runtime_core_server *server) { return server->requests; }
unsigned runtime_core_server_opcode(struct runtime_core_server *server) { return server->last_opcode; }
const char *runtime_core_server_interface(struct runtime_core_server *server) { return server->last_interface; }
const char *runtime_core_server_constructor(struct runtime_core_server *server) { return server->last_constructor; }
void runtime_core_server_event(struct runtime_core_server *server, uint32_t identifier, uint32_t opcode,
                                const uint32_t *objects, int descriptor, int use_null)
{
    struct wl_resource *resource = wl_client_get_object(server->client, identifier);
    assert(resource);
    const struct wl_interface *interface = wl_resource_get_interface(resource);
    unsigned source = core_index(interface);
    assert(opcode < (unsigned)interface->event_count);
    const struct wl_message *message = &interface->events[opcode];
    union wl_argument arguments[20] = { 0 };
    unsigned index = 0;
    int nullable = 0;
    static const unsigned char bytes[] = { 0x21, 0x22, 0x23 };
    struct wl_array array = { sizeof(bytes), sizeof(bytes), (void *)bytes };
    for (const char *signature = message->signature; *signature; signature++) {
        char kind = *signature;
        if (isdigit((unsigned char)kind)) continue;
        if (kind == '?') { nullable = 1; continue; }
        assert(index < 20);
        switch (kind) {
        case 'i': arguments[index].i = -123; break;
        case 'u': arguments[index].u = 17; break;
        case 'f': arguments[index].f = -123; break;
        case 's': arguments[index].s = nullable && use_null ? NULL : "waylandkit-test"; break;
        case 'a': arguments[index].a = &array; break;
        case 'h': arguments[index].h = descriptor; break;
        case 'o': arguments[index].o = !(nullable && use_null) && objects[index] ? (struct wl_object *)wl_client_get_object(server->client, objects[index]) : NULL; break;
        case 'n': {
            unsigned child = core_index(message->types[index]);
            int version = wl_resource_get_version(resource);
            if (version > core_interfaces[child]->version) version = core_interfaces[child]->version;
            arguments[index].o = (struct wl_object *)core_resource(server, child, version, 0);
            break;
        }
        default: abort();
        }
        nullable = 0; index++;
    }
    wl_resource_post_event_array(resource, opcode, arguments);
    if (events_destructors[source] & (UINT64_C(1) << opcode)) wl_resource_destroy(resource);
    wl_client_flush(server->client);
}
void runtime_core_server_destroy(struct runtime_core_server *server)
{
    wl_display_destroy_clients(server->display);
    assert(server->resources == 0);
    wl_display_destroy(server->display);
    free(server);
}
void runtime_core_server_scalar_batch(struct runtime_core_server *server, uint32_t identifier, unsigned count)
{
    struct wl_resource *resource = wl_client_get_object(server->client, identifier);
    assert(resource && !strcmp(wl_resource_get_class(resource), "wl_data_offer"));
    union wl_argument argument = { .u = 17 };
    for (unsigned index = 0; index < count; index++) wl_resource_post_event_array(resource, 2, &argument);
    wl_client_flush(server->client);
}
