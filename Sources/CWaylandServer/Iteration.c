#include "CWaylandServer.h"
void wayland_kit_each_client(struct wl_display *display, wayland_kit_client_iterator iterator, void *data)
{
    struct wl_client *client;
    wl_client_for_each(client, wl_display_get_client_list(display)) iterator(client, data);
}
