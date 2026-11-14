#include "CWaylandUtilities.h"
#include <stdlib.h>
struct wl_array *wayland_kit_array_create(void)
{
    struct wl_array *array = malloc(sizeof(*array));
    if (array) wl_array_init(array);
    return array;
}
void wayland_kit_array_destroy(struct wl_array *array)
{
    wl_array_release(array);
    free(array);
}
