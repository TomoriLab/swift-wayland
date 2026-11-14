#include "CWaylandClient.h"
#include <string.h>

const struct wl_interface *wayland_kit_client_core_interface(const char *name)
{
    if (strcmp(name, "wl_display") == 0) return &wl_display_interface;
    if (strcmp(name, "wl_registry") == 0) return &wl_registry_interface;
    if (strcmp(name, "wl_callback") == 0) return &wl_callback_interface;
    if (strcmp(name, "wl_compositor") == 0) return &wl_compositor_interface;
    if (strcmp(name, "wl_shm_pool") == 0) return &wl_shm_pool_interface;
    if (strcmp(name, "wl_shm") == 0) return &wl_shm_interface;
    if (strcmp(name, "wl_buffer") == 0) return &wl_buffer_interface;
    if (strcmp(name, "wl_data_offer") == 0) return &wl_data_offer_interface;
    if (strcmp(name, "wl_data_source") == 0) return &wl_data_source_interface;
    if (strcmp(name, "wl_data_device") == 0) return &wl_data_device_interface;
    if (strcmp(name, "wl_data_device_manager") == 0) return &wl_data_device_manager_interface;
    if (strcmp(name, "wl_shell") == 0) return &wl_shell_interface;
    if (strcmp(name, "wl_shell_surface") == 0) return &wl_shell_surface_interface;
    if (strcmp(name, "wl_surface") == 0) return &wl_surface_interface;
    if (strcmp(name, "wl_seat") == 0) return &wl_seat_interface;
    if (strcmp(name, "wl_pointer") == 0) return &wl_pointer_interface;
    if (strcmp(name, "wl_keyboard") == 0) return &wl_keyboard_interface;
    if (strcmp(name, "wl_touch") == 0) return &wl_touch_interface;
    if (strcmp(name, "wl_output") == 0) return &wl_output_interface;
    if (strcmp(name, "wl_region") == 0) return &wl_region_interface;
    if (strcmp(name, "wl_subcompositor") == 0) return &wl_subcompositor_interface;
    if (strcmp(name, "wl_subsurface") == 0) return &wl_subsurface_interface;
    if (strcmp(name, "wl_fixes") == 0) return &wl_fixes_interface;
    return NULL;
}
