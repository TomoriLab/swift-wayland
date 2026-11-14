#include "RuntimeNativeTestSupport.h"
#include "CWaylandServer.h"
#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <string.h>

struct fixture {
    struct wl_display *display;
    struct wl_client *client;
    struct runtime_test_shm_client *peer;
    struct wl_shm_buffer *buffer;
};
static struct wl_shm_buffer *nested_buffer;
static int nested_result = -1;
static unsigned char nested_bytes[16];
static void log_message(const char *format, va_list arguments) { vfprintf(stderr, format, arguments); }
static void nested_log(const char *format, va_list arguments)
{
    (void)format; (void)arguments;
    nested_result = wayland_kit_shm_snapshot(nested_buffer, nested_bytes, sizeof(nested_bytes));
}
static void dispatch(struct fixture *fixture)
{
    assert(wl_event_loop_dispatch(wl_display_get_event_loop(fixture->display), 0) == 0);
    wl_display_flush_clients(fixture->display);
}
static struct fixture create(int width, int height, int stride, uint32_t format)
{
    struct fixture fixture = {0};
    int descriptors[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, descriptors) == 0);
    fixture.display = wl_display_create(); assert(fixture.display);
    assert(wl_display_init_shm(fixture.display) == 0);
    if (format > 1) assert(wl_display_add_shm_format(fixture.display, format));
    fixture.client = wl_client_create(fixture.display, descriptors[0]); assert(fixture.client);
    fixture.peer = runtime_test_shm_client_create(descriptors[1]); assert(fixture.peer);
    dispatch(&fixture);
    assert(runtime_test_shm_client_dispatch(fixture.peer) >= 0);
    uint32_t identifier = runtime_test_shm_client_buffer_layout(fixture.peer, width, height, stride, format);
    dispatch(&fixture);
    struct wl_resource *resource = wl_list_empty(wl_display_get_client_list(fixture.display)) ? NULL : wl_client_get_object(fixture.client, identifier);
    fixture.buffer = resource ? wl_shm_buffer_get(resource) : NULL;
    return fixture;
}
static void destroy(struct fixture *fixture)
{
    runtime_test_shm_client_destroy(fixture->peer);
    wl_display_destroy_clients(fixture->display);
    wl_display_destroy(fixture->display);
}
int main(void)
{
    wl_log_set_handler_server(log_message);
    struct fixture first = create(2, 2, 12, WL_SHM_FORMAT_ARGB8888);
    struct fixture second = create(2, 2, 12, WL_SHM_FORMAT_XRGB8888);
    assert(first.buffer && second.buffer);
    unsigned char bytes[16];
    assert(wayland_kit_shm_snapshot(first.buffer, bytes, sizeof(bytes)) == 0);
    for (unsigned index = 0; index < sizeof(bytes); index++) assert(bytes[index] == index + 1);
    assert(wayland_kit_shm_snapshot(first.buffer, bytes, 15) == EINVAL);
    struct wl_shm_pool *pool = wl_shm_buffer_ref_pool(first.buffer);
    runtime_test_shm_client_resize(first.peer);
    dispatch(&first);
    nested_buffer = second.buffer;
    wl_log_set_handler_server(nested_log);
    assert(wayland_kit_shm_snapshot(first.buffer, bytes, sizeof(bytes)) == 0);
    assert(nested_result == EBUSY);
    wl_log_set_handler_server(log_message);
    wl_shm_pool_unref(pool);
    assert(wayland_kit_shm_snapshot(second.buffer, bytes, sizeof(bytes)) == 0);
    assert(runtime_test_shm_client_truncate(first.peer, 0) == 0);
    assert(wayland_kit_shm_snapshot(first.buffer, bytes, sizeof(bytes)) == 0);
    for (unsigned index = 0; index < sizeof(bytes); index++) assert(bytes[index] == 0);
    wl_display_flush_clients(first.display);
    assert(runtime_test_shm_client_dispatch(first.peer) == -1);
    destroy(&first); destroy(&second);
    struct fixture narrow = create(2, 2, 2, WL_SHM_FORMAT_ARGB8888);
    assert(narrow.buffer && wayland_kit_shm_snapshot(narrow.buffer, bytes, sizeof(bytes)) == EINVAL);
    destroy(&narrow);
    struct fixture unknown = create(2, 2, 12, UINT32_C(0x36314752));
    assert(unknown.buffer && wayland_kit_shm_snapshot(unknown.buffer, bytes, sizeof(bytes)) == EINVAL);
    destroy(&unknown);
    struct fixture overflow = create(INT32_MAX, 2, INT32_MAX, WL_SHM_FORMAT_ARGB8888);
    assert(!overflow.buffer);
    assert(runtime_test_shm_client_dispatch(overflow.peer) == -1);
    destroy(&overflow);
    puts("PASS SHM rows/quota/nested-pools/resize/truncation/SIGBUS/unsupported-format/stride/overflow");
    return 0;
}
