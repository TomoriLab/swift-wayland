#ifndef WAYLAND_RUNTIME_SYNCHRONIZATION_H
#define WAYLAND_RUNTIME_SYNCHRONIZATION_H

#include <stdint.h>

struct wayland_runtime_mutex;
/* The caller provides a valid error slot. Success owns one allocation; failure frees partial storage. */
struct wayland_runtime_mutex *wayland_runtime_mutex_create(int *error);
/* The mutex must remain initialized and owned throughout the paired lock/unlock interval. */
int wayland_runtime_mutex_lock(struct wayland_runtime_mutex *mutex);
int wayland_runtime_mutex_unlock(struct wayland_runtime_mutex *mutex);
/* No method or native consumer may retain the mutex when its wrapper is destroyed. */
void wayland_runtime_mutex_destroy(struct wayland_runtime_mutex *mutex);
/* A static mutex serializes a nonwrapping process-local counter; zero reports exhaustion. */
uint64_t wayland_runtime_next_session(void);

/* Validation and duplication do not consume the input descriptor. */
int wayland_runtime_descriptor_validate(int descriptor);
/* The caller owns a successful close-on-exec duplicate; failure writes a scoped error code. */
int wayland_runtime_descriptor_duplicate(int descriptor, int *error);
/* Exactly one Linux close attempt is made; the result is zero or the saved errno. */
int wayland_runtime_descriptor_close(int descriptor);

/* The caller owns a successful nonblocking close-on-exec eventfd. */
int wayland_runtime_wake_create(void);
#endif
