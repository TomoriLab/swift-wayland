#include "RuntimeNativeTestSupport.h"
#include <wayland-client.h>
#include <assert.h>
#include <ctype.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "CorePeerTables.h"
struct runtime_core_client {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_proxy *source;
    struct wl_proxy *objects[64];
    unsigned objects_count, interface, events, last_opcode;
    const char *constructor;
};
#define CORE_COUNT (sizeof(core_interfaces) / sizeof(core_interfaces[0]))
static unsigned find_core(const char *name)
{
    for (unsigned index = 0; index < CORE_COUNT; index++) if (!strcmp(core_interfaces[index]->name, name)) return index;
    abort();
}
static void keep_proxy(struct runtime_core_client *client, struct wl_proxy *proxy)
{
    assert(proxy && client->objects_count < 64);
    client->objects[client->objects_count++] = proxy;
}
static int receive_core(const void *implementation, void *target, uint32_t opcode,
                        const struct wl_message *message, union wl_argument *arguments)
{
    (void)target;
    struct runtime_core_client *client = (void *)implementation;
    unsigned index = 0;
    int nullable = 0;
    client->events++; client->last_opcode = opcode; client->constructor = NULL;
    for (const char *signature = message->signature; *signature; signature++) {
        char kind = *signature;
        if (isdigit((unsigned char)kind)) continue;
        if (kind == '?') { nullable = 1; continue; }
        assert(index < 20);
        switch (kind) {
        case 'i': assert(arguments[index].i == -123); break;
        case 'u': assert(arguments[index].u == 17); break;
        case 'f': assert(arguments[index].f == -123); break;
        case 's': if (!arguments[index].s) assert(nullable); else assert(!strcmp(arguments[index].s, "waylandkit-test")); break;
        case 'a': assert(arguments[index].a && arguments[index].a->size == 3 && !memcmp(arguments[index].a->data, "\x21\x22\x23", 3)); break;
        case 'h': assert(fcntl(arguments[index].h, F_GETFD) >= 0); close(arguments[index].h); arguments[index].h = -1; break;
        case 'o':
            if (!arguments[index].o) assert(nullable);
            else if (message->types[index]) assert(!strcmp(wl_proxy_get_class((struct wl_proxy *)arguments[index].o), message->types[index]->name));
            break;
        case 'n':
            assert(arguments[index].o && message->types[index]);
            client->constructor = wl_proxy_get_class((struct wl_proxy *)arguments[index].o);
            assert(!strcmp(client->constructor, message->types[index]->name));
            keep_proxy(client, (struct wl_proxy *)arguments[index].o);
            break;
        default: abort();
        }
        nullable = 0; index++;
    }
    if (events_destructors[client->interface] & (UINT64_C(1) << opcode)) {
        wl_proxy_destroy(client->source); client->source = NULL;
    }
    return 0;
}
static void core_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version)
{
    struct runtime_core_client *client = data;
    if (strcmp(interface, core_interfaces[client->interface]->name)) return;
    assert(!client->source);
    client->source = wl_registry_bind(registry, name, core_interfaces[client->interface], version);
    assert(client->source);
    assert(wl_proxy_add_dispatcher(client->source, receive_core, client, client) == 0);
}
static void core_removed(void *data, struct wl_registry *registry, uint32_t name) { (void)data; (void)registry; (void)name; }
struct runtime_core_client *runtime_core_client_create(int descriptor, const char *interface)
{
    static const struct wl_registry_listener listener = { core_global, core_removed };
    struct runtime_core_client *client = calloc(1, sizeof(*client)); assert(client);
    client->interface = find_core(interface);
    client->display = wl_display_connect_to_fd(descriptor); assert(client->display);
    client->registry = wl_display_get_registry(client->display); assert(client->registry);
    wl_registry_add_listener(client->registry, &listener, client);
    assert(wl_display_flush(client->display) >= 0);
    return client;
}
int runtime_core_client_advertisements(struct runtime_core_client *client)
{
    int result = wl_display_dispatch(client->display);
    if (result >= 0) assert(wl_display_flush(client->display) >= 0);
    return result;
}
uint32_t runtime_core_client_object(struct runtime_core_client *client, const char *interface)
{
    struct wl_proxy *proxy = wl_proxy_create((struct wl_proxy *)client->display, core_interfaces[find_core(interface)]);
    keep_proxy(client, proxy);
    return wl_proxy_get_id(proxy);
}
int runtime_core_client_request(struct runtime_core_client *client, uint32_t opcode, const uint32_t *objects, int descriptor, int use_null)
{
    assert(client->source);
    const struct wl_interface *interface = core_interfaces[client->interface];
    assert(opcode < (unsigned)interface->method_count);
    const struct wl_message *message = &interface->methods[opcode];
    union wl_argument arguments[20] = { 0 };
    static const unsigned char bytes[] = { 0x21, 0x22, 0x23 };
    struct wl_array array = { 3, 3, (void *)bytes };
    const struct wl_interface *constructor = NULL;
    unsigned index = 0;
    int nullable = 0;
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
        case 'o':
            if (nullable && use_null) break;
            if (objects[index] == 2) arguments[index].o = (struct wl_object *)client->registry;
            else {
                for (unsigned item = 0; item < client->objects_count; item++)
                    if (wl_proxy_get_id(client->objects[item]) == objects[index]) arguments[index].o = (struct wl_object *)client->objects[item];
            }
            break;
        case 'n': constructor = message->types[index]; assert(constructor); break;
        default: abort();
        }
        nullable = 0; index++;
    }
    uint32_t version = wl_proxy_get_version(client->source);
    if (constructor && version > (uint32_t)constructor->version) version = (uint32_t)constructor->version;
    uint32_t flags = requests_destructors[client->interface] & (UINT64_C(1) << opcode) ? WL_MARSHAL_FLAG_DESTROY : 0;
    struct wl_proxy *child = wl_proxy_marshal_array_flags(client->source, opcode, constructor, version, flags, arguments);
    if (constructor) keep_proxy(client, child);
    if (flags) client->source = NULL;
    return wl_display_flush(client->display);
}
int runtime_core_client_events(struct runtime_core_client *client) { return wl_display_dispatch(client->display); }
unsigned runtime_core_client_event_count(struct runtime_core_client *client) { return client->events; }
unsigned runtime_core_client_opcode(struct runtime_core_client *client) { return client->last_opcode; }
const char *runtime_core_client_constructor(struct runtime_core_client *client) { return client->constructor; }
void runtime_core_client_destroy(struct runtime_core_client *client)
{
    for (unsigned index = 0; index < client->objects_count; index++) wl_proxy_destroy(client->objects[index]);
    if (client->source) wl_proxy_destroy(client->source);
    wl_registry_destroy(client->registry);
    wl_display_disconnect(client->display);
    free(client);
}
