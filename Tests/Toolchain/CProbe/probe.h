#ifndef WAYLAND_COMPILER_PROBE_H
#define WAYLAND_COMPILER_PROBE_H

#include <stddef.h>
#include <stdint.h>

struct wayland_probe_registration;
typedef void (*wayland_probe_callback)(void *data, int32_t stage);

struct wayland_probe_registration *wayland_probe_create(wayland_probe_callback callback, void *data, int32_t failure_stage);
int32_t wayland_probe_destroy(struct wayland_probe_registration *registration);
int32_t wayland_probe_open_descriptor_count(void);
size_t wayland_probe_cursor_image_size(void);
size_t wayland_probe_array_size(void);
size_t wayland_probe_array_alignment(void);
int32_t wayland_probe_fixed_roundtrip(int32_t value);

#endif
