#include "probe.h"

#include <stdlib.h>
#include <dirent.h>
#include <string.h>
#include <wayland-cursor.h>
#include <wayland-server-core.h>

struct wayland_probe_registration {
    struct wl_display *display;
    struct wl_listener listener;
    wayland_probe_callback callback;
    void *data;
    int32_t stage;
};

static void notify_destroy(struct wl_listener *listener, void *data)
{
    struct wayland_probe_registration *registration =
        wl_container_of(listener, registration, listener);
    (void)data;
    registration->stage = 1;
    registration->callback(registration->data, registration->stage);
    wl_list_remove(&listener->link);
    registration->stage = 2;
}

struct wayland_probe_registration *wayland_probe_create(wayland_probe_callback callback, void *data, int32_t failure_stage)
{
    struct wayland_probe_registration *registration;
    if (failure_stage == 1)
        return NULL;
    registration = calloc(1, sizeof *registration);
    if (registration == NULL)
        return NULL;
    if (failure_stage == 2) {
        free(registration);
        return NULL;
    }
    registration->display = wl_display_create();
    if (registration->display == NULL) {
        free(registration);
        return NULL;
    }
    registration->callback = callback;
    registration->data = data;
    registration->listener.notify = notify_destroy;
    wl_display_add_destroy_listener(registration->display, &registration->listener);
    if (failure_stage == 3) {
        /* Attached rollback can call Swift before construction returns failure. */
        wl_display_destroy(registration->display);
        free(registration);
        return NULL;
    }
    return registration;
}

int32_t wayland_probe_destroy(struct wayland_probe_registration *registration)
{
    int32_t stage;
    wl_display_destroy(registration->display);
    stage = registration->stage;
    free(registration);
    return stage;
}

size_t wayland_probe_array_size(void) { return sizeof(struct wl_array); }
size_t wayland_probe_array_alignment(void) { return _Alignof(struct wl_array); }
int32_t wayland_probe_fixed_roundtrip(int32_t value)
{
    return wl_fixed_to_int(wl_fixed_from_int(value));
}

int32_t wayland_probe_open_descriptor_count(void)
{
    DIR *directory = opendir("/proc/self/fd");
    struct dirent *entry;
    int32_t count = 0;
    if (directory == NULL)
        return -1;
    while ((entry = readdir(directory)) != NULL) {
        if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0)
            count++;
    }
    closedir(directory);
    return count;
}

size_t wayland_probe_cursor_image_size(void) { return sizeof(struct wl_cursor_image); }
