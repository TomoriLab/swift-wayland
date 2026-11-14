#ifndef WAYLAND_RUNTIME_SYNCHRONIZATION_H
#define WAYLAND_RUNTIME_SYNCHRONIZATION_H

#include <stdint.h>
#include <stddef.h>
#include "WaylandLogScope.h"

struct wayland_runtime_mutex;
/* The caller provides a valid error slot. Success owns one allocation; failure frees partial storage. */
struct wayland_runtime_mutex *wayland_runtime_mutex_create(int *error);
/* The mutex must remain initialized and owned throughout the paired lock/unlock interval. */
int wayland_runtime_mutex_lock(struct wayland_runtime_mutex *mutex);
int wayland_runtime_mutex_unlock(struct wayland_runtime_mutex *mutex);
/* No method or native consumer may retain the mutex when its wrapper is destroyed. */
void wayland_runtime_mutex_destroy(struct wayland_runtime_mutex *mutex);
/* Native frame identity is thread-local and restored before the scoped owner can be released. */
struct wayland_runtime_mutex *wayland_runtime_native_frame_enter(struct wayland_runtime_mutex *mutex);
void wayland_runtime_native_frame_leave(struct wayland_runtime_mutex *previous);
int wayland_runtime_native_frame_matches(struct wayland_runtime_mutex *mutex);
int wayland_runtime_native_frame_uninterrupted(struct wayland_runtime_mutex *mutex);
/* Returns 0 for fallback admission, 1 for active delivery, or 2 for canceled delivery. */
int wayland_runtime_callback_state(struct wayland_runtime_mutex *admission, struct wayland_runtime_mutex *cancellation);
/* Producers set and mailbox consumers clear the notification while holding this same mutex. */
int wayland_runtime_notification_pending(struct wayland_runtime_mutex *mutex);
void wayland_runtime_notification_set(struct wayland_runtime_mutex *mutex, int pending);
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
char *wayland_runtime_copy_log_message(const char *format, void *scope, size_t maximum, size_t *length, int *truncated);
void wayland_runtime_free_log_message(char *message);
void wayland_runtime_print_log_message(const char *format, void *scope);
#endif
