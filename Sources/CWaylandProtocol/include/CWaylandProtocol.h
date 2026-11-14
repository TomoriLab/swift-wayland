#ifndef WAYLAND_KIT_PROTOCOL_ARGUMENTS_H
#define WAYLAND_KIT_PROTOCOL_ARGUMENTS_H
#include <wayland-util.h>
struct wayland_kit_arguments;
/* Temporary argument storage owns copied strings and arrays, never descriptors or objects. */
struct wayland_kit_arguments *wayland_kit_arguments_create(size_t count);
void wayland_kit_arguments_destroy(struct wayland_kit_arguments *);
union wl_argument *wayland_kit_arguments_values(struct wayland_kit_arguments *);
int wayland_kit_arguments_string(struct wayland_kit_arguments *, size_t, const char *);
int wayland_kit_arguments_array(struct wayland_kit_arguments *, size_t, const void *, size_t);
struct wayland_kit_descriptors;
struct wayland_kit_descriptors *wayland_kit_descriptors_create(size_t count, size_t maximum);
void wayland_kit_descriptors_destroy(struct wayland_kit_descriptors *);
int wayland_kit_descriptors_interface(struct wayland_kit_descriptors *, size_t index, const char *name, int version, size_t requests, size_t events);
int wayland_kit_descriptors_message(struct wayland_kit_descriptors *, size_t index, int event, size_t opcode, const char *name, const char *signature, size_t arguments);
int wayland_kit_descriptors_argument(struct wayland_kit_descriptors *, size_t index, int event, size_t opcode, size_t argument, size_t target);
int wayland_kit_descriptors_seal(struct wayland_kit_descriptors *);
const struct wl_interface *wayland_kit_descriptors_get(struct wayland_kit_descriptors *, size_t index);
size_t wayland_kit_descriptors_bytes(const struct wayland_kit_descriptors *);
#endif
