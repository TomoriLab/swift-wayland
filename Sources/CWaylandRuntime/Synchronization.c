#include "CWaylandRuntime.h"
#include <errno.h>
#include <pthread.h>
#include <stdlib.h>
#include <stdatomic.h>

struct wayland_runtime_mutex {
    pthread_mutex_t value;
    _Atomic int notification;
};

struct wayland_runtime_mutex *wayland_runtime_mutex_create(int *error)
{
    struct wayland_runtime_mutex *mutex = malloc(sizeof *mutex);
    if (mutex == NULL) {
        *error = ENOMEM;
        return NULL;
    }
    *error = pthread_mutex_init(&mutex->value, NULL);
    if (*error != 0) {
        free(mutex);
        return NULL;
    }
    atomic_init(&mutex->notification, 0);
    return mutex;
}

int wayland_runtime_mutex_lock(struct wayland_runtime_mutex *mutex)
{
    return pthread_mutex_lock(&mutex->value);
}

int wayland_runtime_mutex_unlock(struct wayland_runtime_mutex *mutex)
{
    return pthread_mutex_unlock(&mutex->value);
}

void wayland_runtime_mutex_destroy(struct wayland_runtime_mutex *mutex)
{
    /* An active Swift method retains the wrapper, so destruction requires an unlocked mutex. */
    if (pthread_mutex_destroy(&mutex->value) != 0)
        abort();
    free(mutex);
}

uint64_t wayland_runtime_next_session(void)
{
    static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
    static uint64_t counter;
    uint64_t result;
    if (pthread_mutex_lock(&mutex) != 0)
        abort();
    result = counter == UINT64_MAX ? 0 : ++counter;
    if (pthread_mutex_unlock(&mutex) != 0)
        abort();
    return result;
}

static _Thread_local struct wayland_runtime_mutex *native_frame;
struct wayland_runtime_mutex *wayland_runtime_native_frame_enter(struct wayland_runtime_mutex *mutex)
{
    struct wayland_runtime_mutex *previous = native_frame;
    native_frame = mutex;
    return previous;
}
void wayland_runtime_native_frame_leave(struct wayland_runtime_mutex *previous) { native_frame = previous; }
int wayland_runtime_native_frame_matches(struct wayland_runtime_mutex *mutex) { return native_frame == mutex; }
int wayland_runtime_native_frame_uninterrupted(struct wayland_runtime_mutex *mutex)
{
    return native_frame == mutex && !atomic_load(&mutex->notification);
}
int wayland_runtime_callback_state(struct wayland_runtime_mutex *admission, struct wayland_runtime_mutex *cancellation)
{
    if (native_frame != admission || atomic_load(&admission->notification)) return 0;
    return atomic_load(&cancellation->notification) ? 2 : 1;
}
int wayland_runtime_notification_pending(struct wayland_runtime_mutex *mutex) { return atomic_load(&mutex->notification); }
void wayland_runtime_notification_set(struct wayland_runtime_mutex *mutex, int pending) { atomic_store(&mutex->notification, pending); }
