#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
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


int runtime_test_descriptor_open(void)
{
    int original = open("/dev/null", O_RDWR);
    int result;
    if (original < 0)
        return -1;
    result = fcntl(original, F_DUPFD_CLOEXEC, 1024);
    close(original);
    return result;
}

int runtime_test_descriptor_is_open(int descriptor) { return fcntl(descriptor, F_GETFD) >= 0; }
int runtime_test_descriptor_cloexec(int descriptor)
{
    int flags = fcntl(descriptor, F_GETFD);
    return flags >= 0 && (flags & FD_CLOEXEC) != 0;
}
int runtime_test_descriptor_close(int descriptor) { return close(descriptor) < 0 ? errno : 0; }
int runtime_test_descriptor_replace(int descriptor)
{
    int source = open("/dev/null", O_RDWR);
    int result;
    if (source < 0)
        return -1;
    result = dup2(source, descriptor);
    if (source != descriptor)
        close(source);
    return result;
}
int runtime_test_high_descriptor_count(void)
{
    DIR *directory = opendir("/proc/self/fd");
    struct dirent *entry;
    int count = 0;
    if (directory == NULL)
        return -1;
    while ((entry = readdir(directory)) != NULL) {
        if (strtol(entry->d_name, NULL, 10) >= 1024)
            count++;
    }
    closedir(directory);
    return count;
}

struct runtime_test_callback_slot {
    runtime_test_context_callback callback;
    void *data;
    int detaches;
};
struct runtime_test_callback_slot *runtime_test_callback_slot_create(void)
{
    return calloc(1, sizeof(struct runtime_test_callback_slot));
}
void runtime_test_callback_slot_destroy(struct runtime_test_callback_slot *slot)
{
    assert(slot->callback == NULL);
    free(slot);
}
void runtime_test_callback_install(struct runtime_test_callback_slot *slot, runtime_test_context_callback callback, void *data)
{
    assert(slot->callback == NULL);
    slot->callback = callback;
    slot->data = data;
}
int runtime_test_callback_invoke(struct runtime_test_callback_slot *slot, int descriptor)
{
    if (slot->callback == NULL) {
        if (descriptor >= 0)
            close(descriptor);
        return -1;
    }
    return slot->callback(slot->data, descriptor);
}
void runtime_test_callback_detach(struct runtime_test_callback_slot *slot, int invoke_while_detaching)
{
    assert(slot->callback != NULL);
    if (invoke_while_detaching)
        slot->callback(slot->data, -1);
    slot->callback = NULL;
    slot->data = NULL;
    slot->detaches++;
}
int runtime_test_callback_detach_count(const struct runtime_test_callback_slot *slot) { return slot->detaches; }

int runtime_test_matching_descriptor_count(int descriptor)
{
    struct stat original;
    struct stat candidate;
    DIR *directory;
    struct dirent *entry;
    int count = 0;
    if (fstat(descriptor, &original) < 0)
        return -1;
    directory = opendir("/proc/self/fd");
    if (directory == NULL)
        return -1;
    while ((entry = readdir(directory)) != NULL) {
        char *end;
        long value = strtol(entry->d_name, &end, 10);
        if (*end != '\0')
            continue;
        if (fstat((int)value, &candidate) == 0 && candidate.st_dev == original.st_dev && candidate.st_ino == original.st_ino)
            count++;
    }
    closedir(directory);
    return count;
}
