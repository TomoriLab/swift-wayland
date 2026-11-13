#include "CWaylandRuntime.h"
#include <sys/eventfd.h>

int wayland_runtime_wake_create(void)
{
    return eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
}
