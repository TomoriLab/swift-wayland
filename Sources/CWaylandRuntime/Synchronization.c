#include "CWaylandRuntime.h"
#include <errno.h>
#include <pthread.h>
#include <stdlib.h>

struct wayland_runtime_mutex {
    pthread_mutex_t value;
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
