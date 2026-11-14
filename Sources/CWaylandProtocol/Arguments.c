#include "CWaylandProtocol.h"
#include <stdlib.h>
#include <string.h>
struct argument_allocation { void *first; void *second; };
struct wayland_kit_arguments {
    size_t count;
    struct argument_allocation *allocations;
    union wl_argument values[];
};
_Static_assert(_Alignof(union wl_argument) >= _Alignof(struct argument_allocation), "Argument storage must align allocation records.");
_Static_assert(sizeof(union wl_argument) % _Alignof(struct argument_allocation) == 0, "Argument slots must preserve allocation-record alignment.");
struct wayland_kit_arguments *wayland_kit_arguments_create(size_t count)
{
    if (count > 32) return NULL;
    size_t slots = count ? count : 1;
    /* The bounded slot count prevents overflow and both arrays share one allocation lifetime. */
    struct wayland_kit_arguments *arguments = calloc(1, sizeof(*arguments) + slots *
        (sizeof(union wl_argument) + sizeof(struct argument_allocation)));
    if (!arguments) return NULL;
    arguments->count = count;
    arguments->allocations = (struct argument_allocation *)(arguments->values + slots);
    return arguments;
}
void wayland_kit_arguments_destroy(struct wayland_kit_arguments *arguments)
{
    if (!arguments) return;
    for (size_t index = 0; index < arguments->count; index++) {
        free(arguments->allocations[index].first);
        free(arguments->allocations[index].second);
    }
    free(arguments);
}
union wl_argument *wayland_kit_arguments_values(struct wayland_kit_arguments *arguments) { return arguments->values; }
static void clear_slot(struct wayland_kit_arguments *arguments, size_t index)
{
    if (arguments->allocations[index].first) free(arguments->allocations[index].first);
    if (arguments->allocations[index].second) free(arguments->allocations[index].second);
    arguments->allocations[index] = (struct argument_allocation){0};
}
int wayland_kit_arguments_string(struct wayland_kit_arguments *arguments, size_t index, const char *value)
{
    if (index >= arguments->count) return -1;
    if (!value) { clear_slot(arguments, index); arguments->values[index].s = NULL; return 0; }
    char *copy = malloc(strlen(value) + 1);
    if (!copy) return -1;
    strcpy(copy, value);
    /* Copying before retirement permits input that aliases the previous slot. */
    clear_slot(arguments, index);
    arguments->allocations[index].first = copy;
    arguments->values[index].s = copy;
    return 0;
}
int wayland_kit_arguments_array(struct wayland_kit_arguments *arguments, size_t index, const void *bytes, size_t size)
{
    if (index >= arguments->count) return -1;
    struct wl_array *array = calloc(1, sizeof(*array));
    if (!array) return -1;
    void *copy = size ? malloc(size) : NULL;
    if (size && !copy) { free(array); return -1; }
    if (size) memcpy(copy, bytes, size);
    array->size = size; array->alloc = size; array->data = copy;
    clear_slot(arguments, index);
    arguments->allocations[index].first = array;
    arguments->allocations[index].second = copy;
    arguments->values[index].a = array;
    return 0;
}
