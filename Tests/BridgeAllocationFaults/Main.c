#include "CWaylandProtocol.h"
#include "CWaylandRuntime.h"
#include <errno.h>
#include <pthread.h>
#include "CWaylandServer.h"
#include "CWaylandUtilities.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static void *allocations[64];
static size_t live, attempts, failure;
static int fail_mutex_initialization;

int runtime_fault_pthread_mutex_init(pthread_mutex_t *mutex, const pthread_mutexattr_t *attributes)
{
    if (fail_mutex_initialization) return EAGAIN;
    return pthread_mutex_init(mutex, attributes);
}

static void *track(void *pointer)
{
    assert(pointer && live < sizeof(allocations) / sizeof(allocations[0]));
    allocations[live++] = pointer;
    return pointer;
}

void *runtime_fault_malloc(size_t size)
{
    if (++attempts == failure) return NULL;
    return track(malloc(size));
}

void *runtime_fault_calloc(size_t count, size_t size)
{
    if (++attempts == failure) return NULL;
    return track(calloc(count, size));
}

void runtime_fault_free(void *pointer)
{
    if (!pointer) return;
    size_t index = 0;
    while (index < live && allocations[index] != pointer) index++;
    assert(index < live);
    allocations[index] = allocations[--live];
    free(pointer);
}

static void reset(size_t selected)
{
    assert(live == 0);
    attempts = 0;
    failure = selected;
}

static void notified(void *data) { (*(unsigned *)data)++; }

static struct wayland_kit_descriptors *build_descriptors(void)
{
    struct wayland_kit_descriptors *arena = wayland_kit_descriptors_create(2, 16384);
    if (!arena) return NULL;
    if (wayland_kit_descriptors_interface(arena, 0, "alpha", 2, 1, 0) < 0 ||
        wayland_kit_descriptors_interface(arena, 1, "beta", 1, 0, 1) < 0 ||
        wayland_kit_descriptors_message(arena, 0, 0, 0, "create", "n", 1) < 0 ||
        wayland_kit_descriptors_message(arena, 1, 1, 0, "reference", "ou", 2) < 0) {
        wayland_kit_descriptors_destroy(arena);
        return NULL;
    }
    assert(wayland_kit_descriptors_argument(arena, 0, 0, 0, 0, 1) == 0);
    assert(wayland_kit_descriptors_argument(arena, 1, 1, 0, 0, 0) == 0);
    assert(wayland_kit_descriptors_seal(arena) == 0);
    const struct wl_interface *alpha = wayland_kit_descriptors_get(arena, 0);
    assert(alpha && alpha->methods[0].types[0]->events[0].types[0] == alpha);
    assert(wayland_kit_descriptors_bytes(arena) <= 16384);
    assert(wayland_kit_descriptors_interface(arena, 0, "changed", 1, 0, 0) == -1);
    assert(wayland_kit_descriptors_argument(arena, 0, 0, 0, 0, 0) == -1);
    assert(wayland_kit_descriptors_seal(arena) == -1);
    return arena;
}

int main(void)
{
    reset(1);
    int error = 0;
    assert(!wayland_runtime_mutex_create(&error));
    assert(error == ENOMEM && live == 0);
    reset(0);
    fail_mutex_initialization = 1;
    error = 0;
    assert(!wayland_runtime_mutex_create(&error));
    assert(error == EAGAIN && live == 0);
    fail_mutex_initialization = 0;
    reset(0);
    struct wayland_runtime_mutex *mutex = wayland_runtime_mutex_create(&error);
    assert(mutex && error == 0 && live == 1);
    assert(wayland_runtime_mutex_lock(mutex) == 0);
    assert(wayland_runtime_mutex_unlock(mutex) == 0);
    wayland_runtime_mutex_destroy(mutex);
    assert(live == 0);
    for (size_t count = 0; count <= 32; count++) {
        reset(0);
        struct wayland_kit_arguments *boundary = wayland_kit_arguments_create(count);
        assert(boundary);
        for (size_t index = 0; index < count; index++) {
            assert(wayland_kit_arguments_string(boundary, index, "slot") == 0);
            assert(!strcmp(wayland_kit_arguments_values(boundary)[index].s, "slot"));
        }
        assert(wayland_kit_arguments_string(boundary, count, "outside") == -1);
        wayland_kit_arguments_destroy(boundary);
        assert(live == 0);
    }
    reset(0);
    assert(!wayland_kit_arguments_create(33));
    assert(live == 0);
    for (size_t index = 1; index <= 1; index++) {
        reset(index);
        assert(!wayland_kit_arguments_create(2));
        assert(live == 0);
    }
    for (size_t index = 1; index <= 3; index++) {
        reset(0);
        struct wayland_kit_arguments *arguments = wayland_kit_arguments_create(2);
        assert(arguments);
        failure = attempts + index;
        int string_result = wayland_kit_arguments_string(arguments, 0, "retained payload");
        int array_result = string_result == 0 ? wayland_kit_arguments_array(arguments, 1, "bytes", 5) : -1;
        assert(string_result == -1 || array_result == -1);
        wayland_kit_arguments_destroy(arguments);
        assert(live == 0);
    }
    reset(0);
    struct wayland_kit_arguments *arguments = wayland_kit_arguments_create(2);
    assert(arguments);
    assert(wayland_kit_arguments_string(arguments, 0, "complete") == 0);
    assert(wayland_kit_arguments_array(arguments, 1, "bytes", 5) == 0);
    assert(!strcmp(wayland_kit_arguments_values(arguments)[0].s, "complete"));
    assert(wayland_kit_arguments_values(arguments)[1].a->size == 5);
    wayland_kit_arguments_destroy(arguments);
    for (size_t stage = 1; stage <= 2; stage++) {
        reset(0);
        arguments = wayland_kit_arguments_create(1);
        assert(arguments && wayland_kit_arguments_string(arguments, 0, "original") == 0);
        failure = attempts + stage;
        assert(wayland_kit_arguments_array(arguments, 0, "replacement", 11) == -1);
        assert(!strcmp(wayland_kit_arguments_values(arguments)[0].s, "original"));
        failure = 0;
        assert(wayland_kit_arguments_array(arguments, 0, "replacement", 11) == 0);
        struct wl_array *previous = wayland_kit_arguments_values(arguments)[0].a;
        assert(wayland_kit_arguments_array(arguments, 0, previous->data, previous->size) == 0);
        assert(wayland_kit_arguments_values(arguments)[0].a->size == 11);
        assert(!memcmp(wayland_kit_arguments_values(arguments)[0].a->data, "replacement", 11));
        assert(wayland_kit_arguments_string(arguments, 0, "final") == 0);
        const char *previous_string = wayland_kit_arguments_values(arguments)[0].s;
        assert(wayland_kit_arguments_string(arguments, 0, previous_string) == 0);
        assert(!strcmp(wayland_kit_arguments_values(arguments)[0].s, "final"));
        failure = attempts + 1;
        assert(wayland_kit_arguments_string(arguments, 0, "failed") == -1);
        assert(!strcmp(wayland_kit_arguments_values(arguments)[0].s, "final"));
        failure = 0;
        assert(wayland_kit_arguments_string(arguments, 0, NULL) == 0);
        assert(live == 1 && wayland_kit_arguments_values(arguments)[0].s == NULL);
        wayland_kit_arguments_destroy(arguments);
        assert(live == 0);
    }
    reset(1);
    assert(!wayland_kit_array_create());
    reset(0);
    struct wl_array *array = wayland_kit_array_create();
    assert(array && array->size == 0);
    wayland_kit_array_destroy(array);

    reset(1);
    assert(!wayland_kit_watch_client(NULL, notified, NULL));
    reset(1);
    assert(!wayland_kit_watch_resource(NULL, notified, NULL));
    reset(0);
    struct wl_display *display = wl_display_create();
    int descriptors[2];
    assert(display && socketpair(AF_UNIX, SOCK_STREAM, 0, descriptors) == 0);
    struct wl_client *client = wl_client_create(display, descriptors[0]);
    assert(client);
    struct wl_resource *resource = wl_resource_create(client, &wl_callback_interface, 1, 0);
    assert(resource);
    unsigned notifications = 0;
    struct wayland_kit_destroy_watch *client_watch = wayland_kit_watch_client(client, notified, &notifications);
    struct wayland_kit_destroy_watch *resource_watch = wayland_kit_watch_resource(resource, notified, &notifications);
    assert(client_watch && resource_watch);
    wl_client_destroy(client);
    assert(notifications == 2);
    wayland_kit_watch_destroy(resource_watch);
    wayland_kit_watch_destroy(client_watch);
    wl_display_destroy(display);
    close(descriptors[1]);
    assert(live == 0);
    size_t arena_failures = 0;
    for (size_t index = 1; index <= 64; index++) {
        reset(index);
        struct wayland_kit_descriptors *arena = build_descriptors();
        if (arena) {
            wayland_kit_descriptors_destroy(arena);
            assert(live == 0);
            break;
        }
        arena_failures++;
        assert(live == 0);
    }
    assert(arena_failures > 0 && arena_failures < 64);
    reset(0);
    struct wayland_kit_descriptors *arena = wayland_kit_descriptors_create(1, 16384);
    assert(arena && wayland_kit_descriptors_get(arena, 0) == NULL);
    assert(wayland_kit_descriptors_seal(arena) == -1);
    assert(wayland_kit_descriptors_interface(arena, 0, "alpha", 1, 1, 0) == 0);
    assert(wayland_kit_descriptors_message(arena, 0, 0, 0, "invalid", "ou", 1) == -1);
    assert(wayland_kit_descriptors_seal(arena) == -1);
    wayland_kit_descriptors_destroy(arena);
    assert(live == 0);
    printf("PASS: %zu injected bridge allocation/initialization failures and successful retirement controls.\n", 13 + arena_failures);
    return 0;
}
