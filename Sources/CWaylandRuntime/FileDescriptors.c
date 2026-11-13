#define _POSIX_C_SOURCE 200809L
#include "CWaylandRuntime.h"
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

int wayland_runtime_descriptor_validate(int descriptor)
{
    int result;
    do {
        result = fcntl(descriptor, F_GETFD);
    } while (result < 0 && errno == EINTR);
    return result < 0 ? errno : 0;
}

int wayland_runtime_descriptor_duplicate(int descriptor, int *error)
{
    int result;
    do {
        result = fcntl(descriptor, F_DUPFD_CLOEXEC, 0);
    } while (result < 0 && errno == EINTR);
    *error = result < 0 ? errno : 0;
    return result;
}

int wayland_runtime_descriptor_close(int descriptor)
{
    /* Linux releases the descriptor number even on EINTR, so retrying can close a reused number. */
    return close(descriptor) < 0 ? errno : 0;
}
