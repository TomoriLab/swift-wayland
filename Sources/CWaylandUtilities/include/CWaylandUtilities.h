#ifndef CWAYLANDUTILITIES_H
#define CWAYLANDUTILITIES_H
#include <wayland-util.h>
#include <wayland-version.h>
struct wl_array *wayland_kit_array_create(void);
void wayland_kit_array_destroy(struct wl_array *array);
#endif
