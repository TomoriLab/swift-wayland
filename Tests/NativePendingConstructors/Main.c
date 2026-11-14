#include "RuntimeNativeTestSupport.h"
#include <wayland-client.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct observations { unsigned calls; int expected_null; };
static int received(const void *implementation, void *target, uint32_t opcode,
                    const struct wl_message *message, union wl_argument *arguments)
{
    (void)target;
    struct observations *observations = (struct observations *)implementation;
    assert(opcode == 1 && !strcmp(message->signature, "nho"));
    assert(!observations->expected_null || arguments[2].o == NULL);
    observations->calls++;
    close(arguments[1].h);
    arguments[1].h = -1;
    wl_proxy_destroy((struct wl_proxy *)arguments[0].o);
    return 0;
}
static void read_pending(struct wl_display *display)
{
    assert(wl_display_prepare_read(display) == 0);
    assert(wl_display_read_events(display) == 0);
}
static void reproduce(int mode)
{
    int descriptor = -1;
    struct runtime_protocol_peer *peer = runtime_protocol_peer_create(&descriptor);
    assert(peer);
    struct wl_display *display = wl_display_connect_to_fd(descriptor);
    assert(display);
    struct wl_registry *registry = wl_display_get_registry(display);
    unsigned name = runtime_protocol_peer_global(peer);
    struct wl_proxy *first = wl_registry_bind(registry, name, runtime_protocol_peer_interface(), 2);
    assert(first);
    struct wl_proxy *receiver = first;
    if (mode == 2) receiver = wl_registry_bind(registry, name, runtime_protocol_peer_interface(), 2);
    struct observations observations = {.expected_null = mode == 2};
    assert(wl_proxy_add_dispatcher(receiver, received, &observations, NULL) == 0);
    assert(wl_display_flush(display) >= 0 && runtime_protocol_peer_dispatch(peer) == 0);
    read_pending(display);
    assert(wl_display_dispatch_pending(display) >= 0);
    int oracle = open("/dev/null", O_RDWR | O_CLOEXEC);
    assert(oracle >= 0);
    if (mode == 3) runtime_protocol_peer_emit_invalid_object(peer, oracle);
    else runtime_protocol_peer_emit(peer, mode == 2 ? 3 : 1, oracle);
    if (mode == 1) runtime_protocol_peer_error(peer);
    if (mode == 3) {
        assert(wl_display_prepare_read(display) == 0);
        assert(wl_display_read_events(display) == -1);
    } else read_pending(display);
    if (mode == 0) {
        wl_proxy_destroy(receiver);
        assert(wl_display_dispatch_pending(display) >= 0);
        assert(observations.calls == 0);
    } else if (mode == 1) {
        assert(wl_display_dispatch_pending(display) == -1 && wl_display_get_error(display) == EPROTO);
        assert(observations.calls == 0);
        wl_proxy_destroy(receiver);
    } else if (mode == 2) {
        wl_proxy_destroy(first);
        assert(wl_display_dispatch_pending(display) >= 0 && observations.calls == 1);
        wl_proxy_destroy(receiver);
    } else {
        assert(observations.calls == 0);
        wl_proxy_destroy(receiver);
    }
    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    runtime_protocol_peer_destroy(peer);
    close(oracle);
}
int main(int count, char **arguments)
{
    assert(count == 2);
    int mode = atoi(arguments[1]);
    assert(mode >= 0 && mode <= 3);
    reproduce(mode);
    printf("Completed native queued-ownership scenario %d.\n", mode);
    return 0;
}
