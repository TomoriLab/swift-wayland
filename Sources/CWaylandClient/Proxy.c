#include "CWaylandClient.h"
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <time.h>
#include <stdint.h>
int wayland_kit_install_dispatcher(struct wl_proxy *proxy, wayland_kit_dispatcher dispatcher, void *context)
{
    return wl_proxy_add_dispatcher(proxy, dispatcher, context, context);
}

void wayland_kit_discard_event(const struct wl_message *message, union wl_argument *arguments)
{
    const char *signature = message->signature;
    int index = 0;
    for (; *signature; signature++) {
        if ((*signature >= '0' && *signature <= '9') || *signature == '?')
            continue;
        if (*signature == 'h' && arguments[index].h >= 0) {
            close(arguments[index].h);
            arguments[index].h = -1;
        } else if (*signature == 'n' && arguments[index].o != NULL) {
            wl_proxy_destroy((struct wl_proxy *)arguments[index].o);
            /* Queued closure retirement still owns its reference to the destroyed proxy. */
        }
        index++;
    }
}


static int64_t monotonic_milliseconds(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

int wayland_kit_wait_readable(struct wl_display *display, int wake_descriptor, int timeout, int *error)
{
    struct pollfd descriptors[2] = {
        { wl_display_get_fd(display), POLLIN, 0 }, { wake_descriptor, POLLIN, 0 }
    };
    int64_t deadline = timeout >= 0 ? monotonic_milliseconds() + timeout : 0;
    int attempted = 0;
    for (;;) {
        if (attempted && timeout >= 0 && monotonic_milliseconds() >= deadline) return 0;
        attempted = 1;
        if (wl_display_flush(display) < 0) {
            if (errno == EINTR) continue;
            if (errno != EAGAIN) { *error = errno; return -1; }
            descriptors[0].events = POLLIN | POLLOUT;
        } else descriptors[0].events = POLLIN;
        int remaining = -1;
        if (timeout >= 0) {
            int64_t difference = deadline - monotonic_milliseconds();
            remaining = difference > 0 ? (int)difference : 0;
        }
        int result = poll(descriptors, 2, remaining);
        if (result < 0) {
            if (errno == EINTR) continue;
            *error = errno;
            return -1;
        }
        if (result == 0) return 0;
        if (descriptors[1].revents & POLLIN) return 2;
        if (descriptors[1].revents & (POLLERR | POLLHUP | POLLNVAL)) { *error = EBADF; return -1; }
        if (descriptors[0].revents & (POLLIN | POLLERR | POLLHUP)) return 1;
        if (descriptors[0].revents & POLLNVAL) { *error = EBADF; return -1; }
    }
}

struct wl_proxy *wayland_kit_sync_on_queue(struct wl_display *display, struct wl_event_queue *queue)
{
    struct wl_proxy *wrapper = wl_proxy_create_wrapper(display);
    if (!wrapper) return NULL;
    wl_proxy_set_queue(wrapper, queue);
    struct wl_callback *callback = wl_display_sync((struct wl_display *)wrapper);
    int error = errno;
    wl_proxy_wrapper_destroy(wrapper);
    errno = error;
    return (struct wl_proxy *)callback;
}
