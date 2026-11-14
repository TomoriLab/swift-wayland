#include "CWaylandServer.h"
void wayland_kit_reject_constructor(struct wl_client *client)
{
    wl_client_post_implementation_error(client, "%s", "A typed constructor was not accepted.");
}
void wayland_kit_resource_error(struct wl_resource *resource, uint32_t code, const char *message)
{
    wl_resource_post_error(resource, code, "%s", message);
}
void wayland_kit_client_error(struct wl_client *client, const char *message)
{
    wl_client_post_implementation_error(client, "%s", message);
}
