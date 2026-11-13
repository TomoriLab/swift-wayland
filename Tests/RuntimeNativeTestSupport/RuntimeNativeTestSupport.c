#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <time.h>
#include "RuntimeNativeTestSupport.h"
#include <assert.h>
#include <stdlib.h>
#include <wayland-server-core.h>
#include <sys/socket.h>
#include <wayland-client.h>
struct runtime_test_observer {
    int releases;
    int active;
};

struct runtime_test_resource {
    struct wl_display *display;
    struct runtime_test_observer *observer;
    runtime_test_callback callback;
    void *data;
    int stage;
};

static void dispatch_idle(void *data)
{
    struct runtime_test_resource *resource = data;
    resource->stage = 1;
    resource->callback(resource->data);
    /* Native code still uses the resource after the Swift callback returns. */
    assert(resource->observer->releases == 0);
    resource->stage = 2;
}

struct runtime_test_observer *runtime_test_observer_create(void)
{
    return calloc(1, sizeof(struct runtime_test_observer));
}

void runtime_test_observer_destroy(struct runtime_test_observer *observer)
{
    assert(observer->active == 0);
    free(observer);
}

int runtime_test_release_count(const struct runtime_test_observer *observer)
{
    return observer->releases;
}

struct runtime_test_resource *runtime_test_resource_create(struct runtime_test_observer *observer,
                                                         runtime_test_callback callback, void *data)
{
    struct runtime_test_resource *resource = calloc(1, sizeof *resource);
    if (resource == NULL)
        return NULL;
    resource->display = wl_display_create();
    if (resource->display == NULL) {
        free(resource);
        return NULL;
    }
    resource->observer = observer;
    resource->callback = callback;
    resource->data = data;
    if (wl_event_loop_add_idle(wl_display_get_event_loop(resource->display), dispatch_idle, resource) == NULL) {
        wl_display_destroy(resource->display);
        free(resource);
        return NULL;
    }
    observer->active++;
    return resource;
}

int runtime_test_dispatch(struct runtime_test_resource *resource)
{
    wl_event_loop_dispatch_idle(wl_display_get_event_loop(resource->display));
    assert(resource->observer->releases == 0);
    return resource->stage;
}

void runtime_test_resource_destroy(struct runtime_test_resource *resource)
{
    wl_display_destroy(resource->display);
    resource->observer->releases++;
    resource->observer->active--;
    free(resource);
}


int runtime_test_descriptor_open(void)
{
    int original = open("/dev/null", O_RDWR);
    int result;
    if (original < 0)
        return -1;
    result = fcntl(original, F_DUPFD_CLOEXEC, 1024);
    close(original);
    return result;
}

int runtime_test_descriptor_is_open(int descriptor) { return fcntl(descriptor, F_GETFD) >= 0; }
int runtime_test_descriptor_cloexec(int descriptor)
{
    int flags = fcntl(descriptor, F_GETFD);
    return flags >= 0 && (flags & FD_CLOEXEC) != 0;
}
int runtime_test_descriptor_close(int descriptor) { return close(descriptor) < 0 ? errno : 0; }
int runtime_test_descriptor_replace(int descriptor)
{
    int source = open("/dev/null", O_RDWR);
    int result;
    if (source < 0)
        return -1;
    result = dup2(source, descriptor);
    if (source != descriptor)
        close(source);
    return result;
}
int runtime_test_high_descriptor_count(void)
{
    DIR *directory = opendir("/proc/self/fd");
    struct dirent *entry;
    int count = 0;
    if (directory == NULL)
        return -1;
    while ((entry = readdir(directory)) != NULL) {
        if (strtol(entry->d_name, NULL, 10) >= 1024)
            count++;
    }
    closedir(directory);
    return count;
}

struct runtime_test_callback_slot {
    runtime_test_context_callback callback;
    void *data;
    int detaches;
};
struct runtime_test_callback_slot *runtime_test_callback_slot_create(void)
{
    return calloc(1, sizeof(struct runtime_test_callback_slot));
}
void runtime_test_callback_slot_destroy(struct runtime_test_callback_slot *slot)
{
    assert(slot->callback == NULL);
    free(slot);
}
void runtime_test_callback_install(struct runtime_test_callback_slot *slot, runtime_test_context_callback callback, void *data)
{
    assert(slot->callback == NULL);
    slot->callback = callback;
    slot->data = data;
}
int runtime_test_callback_invoke(struct runtime_test_callback_slot *slot, int descriptor)
{
    if (slot->callback == NULL) {
        if (descriptor >= 0)
            close(descriptor);
        return -1;
    }
    return slot->callback(slot->data, descriptor);
}
void runtime_test_callback_detach(struct runtime_test_callback_slot *slot, int invoke_while_detaching)
{
    assert(slot->callback != NULL);
    if (invoke_while_detaching)
        slot->callback(slot->data, -1);
    slot->callback = NULL;
    slot->data = NULL;
    slot->detaches++;
}
int runtime_test_callback_detach_count(const struct runtime_test_callback_slot *slot) { return slot->detaches; }

int runtime_test_matching_descriptor_count(int descriptor)
{
    struct stat original;
    struct stat candidate;
    DIR *directory;
    struct dirent *entry;
    int count = 0;
    if (fstat(descriptor, &original) < 0)
        return -1;
    directory = opendir("/proc/self/fd");
    if (directory == NULL)
        return -1;
    while ((entry = readdir(directory)) != NULL) {
        char *end;
        long value = strtol(entry->d_name, &end, 10);
        if (*end != '\0')
            continue;
        if (fstat((int)value, &candidate) == 0 && candidate.st_dev == original.st_dev && candidate.st_ino == original.st_ino)
            count++;
    }
    closedir(directory);
    return count;
}


static const struct wl_interface dispatcher_child_interface = {
    "wayland_kit_test_child", 1, 0, NULL, 0, NULL
};
static const struct wl_interface *dispatcher_child_types[] = { &dispatcher_child_interface };
static const struct wl_message dispatcher_events[] = {
    { "tick", "u", NULL },
    { "descriptor", "h", NULL },
    { "child", "n", dispatcher_child_types }
};
static const struct wl_interface dispatcher_interface = {
    "wayland_kit_test_dispatcher", 1, 0, NULL, 3, dispatcher_events
};
struct runtime_test_peer {
    struct wl_display *server_display;
    struct wl_client *server_client;
    struct wl_resource *resource;
    struct wl_display *client_display;
};
struct runtime_test_peer *runtime_test_peer_create(void)
{
    int sockets[2];
    struct runtime_test_peer *peer = calloc(1, sizeof(*peer));
    if (!peer) return NULL;
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sockets) < 0) { free(peer); return NULL; }
    peer->server_display = wl_display_create();
    assert(peer->server_display);
    peer->server_client = wl_client_create(peer->server_display, sockets[0]);
    assert(peer->server_client);
    peer->client_display = wl_display_connect_to_fd(sockets[1]);
    assert(peer->client_display);
    return peer;
}
struct wl_display *runtime_test_peer_display(struct runtime_test_peer *peer) { return peer->client_display; }
struct wl_proxy *runtime_test_peer_proxy(struct runtime_test_peer *peer)
{
    assert(peer->resource == NULL);
    struct wl_proxy *proxy = wl_proxy_create((struct wl_proxy *)peer->client_display, &dispatcher_interface);
    assert(proxy);
    peer->resource = wl_resource_create(peer->server_client, &dispatcher_interface, 1, wl_proxy_get_id(proxy));
    assert(peer->resource);
    return proxy;
}
void runtime_test_peer_post(struct runtime_test_peer *peer, unsigned opcode, int descriptor)
{
    union wl_argument argument;
    if (opcode == 0) argument.u = 42;
    else if (opcode == 1) argument.h = descriptor;
    else {
        struct wl_resource *child = wl_resource_create(peer->server_client, &dispatcher_child_interface, 1, 0);
        assert(child);
        argument.o = (struct wl_object *)child;
    }
    wl_resource_post_event_array(peer->resource, opcode, &argument);
    wl_client_flush(peer->server_client);
}
int runtime_test_peer_dispatch(struct runtime_test_peer *peer)
{
    if (wl_display_prepare_read(peer->client_display) < 0)
        return wl_display_dispatch_pending(peer->client_display);
    if (wl_display_read_events(peer->client_display) < 0) return -1;
    return wl_display_dispatch_pending(peer->client_display);
}
void runtime_test_peer_disconnect(struct runtime_test_peer *peer)
{
    assert(peer->client_display);
    wl_display_disconnect(peer->client_display);
    peer->client_display = NULL;
}
void runtime_test_peer_destroy(struct runtime_test_peer *peer)
{
    if (peer->client_display) wl_display_disconnect(peer->client_display);
    wl_client_destroy(peer->server_client);
    wl_display_destroy(peer->server_display);
    free(peer);
}

struct runtime_test_server {
    struct wl_display *display;
    struct wl_client *client;
    struct wl_global *global;
};
static void bind_test_compositor(struct wl_client *client, void *data, uint32_t version, uint32_t identifier)
{
    (void)data;
    if (!wl_resource_create(client, &wl_compositor_interface, (int)version, identifier)) abort();
}
struct runtime_test_server *runtime_test_server_create(int *client_descriptor)
{
    int sockets[2];
    struct runtime_test_server *server = calloc(1, sizeof(*server));
    if (!server) return NULL;
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sockets) < 0) { free(server); return NULL; }
    server->display = wl_display_create();
    assert(server->display);
    server->client = wl_client_create(server->display, sockets[0]);
    assert(server->client);
    server->global = wl_global_create(server->display, &wl_compositor_interface, 1, NULL, bind_test_compositor);
    assert(server->global);
    *client_descriptor = sockets[1];
    return server;
}
int runtime_test_server_dispatch(struct runtime_test_server *server)
{
    int result = wl_event_loop_dispatch(wl_display_get_event_loop(server->display), 0);
    wl_display_flush_clients(server->display);
    return result;
}
void runtime_test_server_destroy(struct runtime_test_server *server)
{
    wl_display_destroy_clients(server->display);
    wl_global_destroy(server->global);
    wl_display_destroy(server->display);
    free(server);
}

int runtime_test_socket_pair(int *server_descriptor, int *client_descriptor)
{
    int sockets[2];
    int result = socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sockets);
    if (result == 0) { *server_descriptor = sockets[0]; *client_descriptor = sockets[1]; }
    return result;
}
struct runtime_test_c_client {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_callback *callback;
    int synchronized;
};
static void client_sync_done(void *data, struct wl_callback *callback, uint32_t serial)
{
    struct runtime_test_c_client *client = data;
    (void)serial;
    client->synchronized++;
    wl_callback_destroy(callback);
    client->callback = NULL;
}
static const struct wl_callback_listener client_sync_listener = { client_sync_done };
struct runtime_test_c_client *runtime_test_c_client_create(int descriptor)
{
    struct runtime_test_c_client *client = calloc(1, sizeof(*client));
    assert(client);
    client->display = wl_display_connect_to_fd(descriptor);
    assert(client->display);
    client->callback = wl_display_sync(client->display);
    assert(client->callback);
    if (wl_callback_add_listener(client->callback, &client_sync_listener, client) != 0) abort();
    if (wl_display_flush(client->display) < 0) abort();
    return client;
}
int runtime_test_c_client_dispatch(struct runtime_test_c_client *client)
{
    if (wl_display_prepare_read(client->display) != 0) abort();
    if (wl_display_read_events(client->display) < 0) return -1;
    if (wl_display_dispatch_pending(client->display) < 0) return -1;
    return client->synchronized;
}
void runtime_test_c_client_destroy(struct runtime_test_c_client *client)
{
    if (client->callback) wl_callback_destroy(client->callback);
    wl_display_disconnect(client->display);
    free(client);
}

static int benchmark_dispatcher(const void *implementation, void *target, uint32_t opcode,
                                const struct wl_message *message, union wl_argument *arguments)
{
    unsigned *count = (unsigned *)implementation;
    (void)target;
    assert(opcode == 0 && arguments[0].u == 42);
    assert(message->name[0] == 't');
    (*count)++;
    return 0;
}
double runtime_test_c_benchmark(unsigned iterations)
{
    struct runtime_test_peer *peer = runtime_test_peer_create();
    assert(peer);
    struct wl_proxy *proxy = runtime_test_peer_proxy(peer);
    unsigned count = 0;
    if (wl_proxy_add_dispatcher(proxy, benchmark_dispatcher, &count, NULL) != 0) abort();
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (unsigned index = 0; index < iterations; index++) {
        runtime_test_peer_post(peer, 0, -1);
        if (runtime_test_peer_dispatch(peer) < 0) abort();
    }
    clock_gettime(CLOCK_MONOTONIC, &end);
    assert(count == iterations);
    wl_proxy_destroy(proxy);
    runtime_test_peer_destroy(peer);
    return (double)(end.tv_sec - start.tv_sec) + (double)(end.tv_nsec - start.tv_nsec) / 1000000000.0;
}
