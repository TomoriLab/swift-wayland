#include "RuntimeNativeTestSupport.h"
#include <wayland-server-core.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <string.h>
#include <unistd.h>
struct runtime_test_server { struct wl_display *display; struct wl_client *client; struct wl_global *global; };
int runtime_test_server_listen(struct runtime_test_server *server, const char *path)
{
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    if (strlen(path) >= sizeof(address.sun_path)) return -1;
    strcpy(address.sun_path, path);
    int descriptor = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (descriptor < 0) return -1;
    if (bind(descriptor, (struct sockaddr *)&address, sizeof(address)) < 0 || listen(descriptor, 8) < 0 ||
        wl_display_add_socket_fd(server->display, descriptor) < 0) {
        close(descriptor); return -1;
    }
    return 0;
}
int runtime_test_listening_socket(const char *path)
{
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    if (strlen(path) >= sizeof(address.sun_path)) return -1;
    strcpy(address.sun_path, path);
    int descriptor = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (descriptor < 0) return -1;
    if (bind(descriptor, (struct sockaddr *)&address, sizeof(address)) < 0 || listen(descriptor, 8) < 0) {
        close(descriptor); return -1;
    }
    return descriptor;
}
