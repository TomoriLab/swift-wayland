#include "RuntimeNativeTestSupport.h"
#include <wayland-server.h>
#include <assert.h>
#include <stddef.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <unistd.h>
struct runtime_list_fixture { struct wl_list head; };
struct runtime_list_node { int value; struct wl_list link; };
struct runtime_list_fixture *runtime_test_list_create(void)
{
    struct runtime_list_fixture *fixture = malloc(sizeof(*fixture)); assert(fixture);
    wl_list_init(&fixture->head);
    for (int value = 1; value <= 3; value++) {
        struct runtime_list_node *node = malloc(sizeof(*node)); assert(node);
        node->value = value;
        wl_list_insert(fixture->head.prev, &node->link);
    }
    return fixture;
}
struct wl_list *runtime_test_list_head(struct runtime_list_fixture *fixture) { return &fixture->head; }
size_t runtime_test_list_offset(void) { return offsetof(struct runtime_list_node, link); }
int runtime_test_list_value(void *pointer) { return ((struct runtime_list_node *)pointer)->value; }
void runtime_test_list_remove(void *pointer)
{
    struct runtime_list_node *node = pointer;
    wl_list_remove(&node->link); free(node);
}
void runtime_test_list_destroy(struct runtime_list_fixture *fixture)
{
    struct runtime_list_node *node, *next;
    wl_list_for_each_safe(node, next, &fixture->head, link) runtime_test_list_remove(node);
    free(fixture);
}
struct runtime_resource_list { struct wl_display *display; struct wl_list head; };
static void unlink_resource(struct wl_resource *resource) { wl_list_remove(wl_resource_get_link(resource)); }
struct runtime_resource_list *runtime_test_resource_list_create(int *descriptor)
{
    int sockets[2]; assert(socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sockets) == 0);
    struct runtime_resource_list *fixture = calloc(1, sizeof(*fixture)); assert(fixture);
    fixture->display = wl_display_create(); assert(fixture->display); wl_list_init(&fixture->head);
    struct wl_client *client = wl_client_create(fixture->display, sockets[0]); assert(client);
    for (int count = 0; count < 3; count++) {
        struct wl_resource *resource = wl_resource_create(client, &wl_callback_interface, 1, 0); assert(resource);
        wl_resource_set_implementation(resource, NULL, NULL, unlink_resource);
        wl_list_insert(fixture->head.prev, wl_resource_get_link(resource));
    }
    *descriptor = sockets[1]; return fixture;
}
struct wl_list *runtime_test_resource_list_head(struct runtime_resource_list *fixture) { return &fixture->head; }
void runtime_test_resource_list_destroy(struct runtime_resource_list *fixture)
{
    wl_display_destroy_clients(fixture->display); wl_display_destroy(fixture->display); free(fixture);
}
struct wl_array *runtime_test_array_fixture(void)
{
    static uint32_t values[] = { 17, 29, 41 };
    static struct wl_array array = { sizeof(values), sizeof(values), values };
    return &array;
}
union wl_argument runtime_test_argument(unsigned field)
{
    static struct wl_array array;
    static const char text[] = "waylandkit-union";
    union wl_argument argument = {0};
    switch (field) {
    case 0: argument.i = -123; break;
    case 1: argument.u = UINT32_C(0xfedcba98); break;
    case 2: argument.f = -456; break;
    case 3: argument.s = text; break;
    case 4: argument.o = (struct wl_object *)&array; break;
    case 5: argument.n = 73; break;
    case 6: argument.a = &array; break;
    case 7: argument.h = 19; break;
    default: abort();
    }
    return argument;
}
