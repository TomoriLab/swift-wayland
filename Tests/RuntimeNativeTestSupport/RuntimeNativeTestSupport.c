#include "RuntimeNativeTestSupport.h"
#include <assert.h>
#include <stdlib.h>
#include <wayland-server-core.h>

struct runtime_test_observer {
    int releases;
    int active;
};

struct runtime_test_resource {
    struct wl_display *display;
    struct runtime_test_observer *observer;
    runtime_test_callback callback;
    void *data;
    int stage;
};

static void dispatch_idle(void *data)
{
    struct runtime_test_resource *resource = data;
    resource->stage = 1;
    resource->callback(resource->data);
    /* Native code still uses the resource after the Swift callback returns. */
    assert(resource->observer->releases == 0);
    resource->stage = 2;
}

struct runtime_test_observer *runtime_test_observer_create(void)
{
    return calloc(1, sizeof(struct runtime_test_observer));
}

void runtime_test_observer_destroy(struct runtime_test_observer *observer)
{
    assert(observer->active == 0);
    free(observer);
}

int runtime_test_release_count(const struct runtime_test_observer *observer)
{
    return observer->releases;
}

struct runtime_test_resource *runtime_test_resource_create(struct runtime_test_observer *observer,
                                                         runtime_test_callback callback, void *data)
{
    struct runtime_test_resource *resource = calloc(1, sizeof *resource);
    if (resource == NULL)
        return NULL;
    resource->display = wl_display_create();
    if (resource->display == NULL) {
        free(resource);
        return NULL;
    }
    resource->observer = observer;
    resource->callback = callback;
    resource->data = data;
    if (wl_event_loop_add_idle(wl_display_get_event_loop(resource->display), dispatch_idle, resource) == NULL) {
        wl_display_destroy(resource->display);
        free(resource);
        return NULL;
    }
    observer->active++;
    return resource;
}

int runtime_test_dispatch(struct runtime_test_resource *resource)
{
    wl_event_loop_dispatch_idle(wl_display_get_event_loop(resource->display));
    assert(resource->observer->releases == 0);
    return resource->stage;
}

void runtime_test_resource_destroy(struct runtime_test_resource *resource)
{
    wl_display_destroy(resource->display);
    resource->observer->releases++;
    resource->observer->active--;
    free(resource);
}
