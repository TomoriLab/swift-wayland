#define _GNU_SOURCE
#include "RuntimeNativeTestSupport.h"
#include <wayland-client.h>
#include <sys/mman.h>
#include <unistd.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>
struct runtime_test_shm_client {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_shm *shm;
    struct wl_shm_pool *pool;
    struct wl_buffer *buffer;
    int descriptor;
};
static void format(void *data, struct wl_shm *shm, uint32_t format) { (void)data; (void)shm; (void)format; }
static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version)
{
    (void)version;
    struct runtime_test_shm_client *client = data;
    if (strcmp(interface, "wl_shm")) return;
    client->shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    assert(client->shm);
    static const struct wl_shm_listener listener = { format };
    assert(wl_shm_add_listener(client->shm, &listener, client) == 0);
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) { (void)data; (void)registry; (void)name; }
struct runtime_test_shm_client *runtime_test_shm_client_create(int descriptor)
{
    struct runtime_test_shm_client *client = calloc(1, sizeof(*client));
    assert(client);
    client->descriptor = -1;
    client->display = wl_display_connect_to_fd(descriptor);
    assert(client->display);
    client->registry = wl_display_get_registry(client->display);
    static const struct wl_registry_listener listener = { global, removed };
    assert(wl_registry_add_listener(client->registry, &listener, client) == 0);
    assert(wl_display_flush(client->display) >= 0);
    return client;
}
int runtime_test_shm_client_dispatch(struct runtime_test_shm_client *client)
{
    int result = wl_display_dispatch(client->display);
    if (result >= 0) assert(wl_display_flush(client->display) >= 0);
    return result;
}
uint32_t runtime_test_shm_client_buffer_layout(struct runtime_test_shm_client *client, int32_t width, int32_t height, int32_t stride, uint32_t format)
{
    assert(client->shm && !client->buffer);
    client->descriptor = memfd_create("waylandkit-test-shm", MFD_CLOEXEC);
    assert(client->descriptor >= 0 && ftruncate(client->descriptor, 8192) == 0);
    unsigned char bytes[40] = {0};
    for (unsigned index = 0; index < 8; index++) { bytes[16 + index] = index + 1; bytes[28 + index] = index + 9; }
    assert(pwrite(client->descriptor, bytes, sizeof(bytes), 0) == sizeof(bytes));
    client->pool = wl_shm_create_pool(client->shm, client->descriptor, 4096);
    assert(client->pool);
    client->buffer = wl_shm_pool_create_buffer(client->pool, 16, width, height, stride, format);
    assert(client->buffer);
    assert(wl_display_flush(client->display) >= 0);
    return wl_proxy_get_id((struct wl_proxy *)client->buffer);
}
void runtime_test_shm_client_resize(struct runtime_test_shm_client *client)
{
    wl_shm_pool_resize(client->pool, 8192);
    assert(wl_display_flush(client->display) >= 0);
}
void runtime_test_shm_client_destroy(struct runtime_test_shm_client *client)
{
    if (client->buffer) wl_buffer_destroy(client->buffer);
    if (client->pool) wl_shm_pool_destroy(client->pool);
    if (client->shm) wl_shm_destroy(client->shm);
    wl_registry_destroy(client->registry);
    wl_display_disconnect(client->display);
    if (client->descriptor >= 0) close(client->descriptor);
    free(client);
}

uint32_t runtime_test_shm_client_buffer(struct runtime_test_shm_client *client)
{
    return runtime_test_shm_client_buffer_layout(client, 2, 2, 12, WL_SHM_FORMAT_ARGB8888);
}
int runtime_test_shm_client_truncate(struct runtime_test_shm_client *client, int64_t size)
{
    return ftruncate(client->descriptor, size);
}
