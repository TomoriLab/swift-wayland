#ifndef WAYLAND_RUNTIME_NATIVE_TEST_SUPPORT_H
#define WAYLAND_RUNTIME_NATIVE_TEST_SUPPORT_H

struct runtime_test_observer;
struct runtime_test_resource;
typedef void (*runtime_test_callback)(void *data);

struct runtime_test_observer *runtime_test_observer_create(void);
void runtime_test_observer_destroy(struct runtime_test_observer *observer);
int runtime_test_release_count(const struct runtime_test_observer *observer);
struct runtime_test_resource *runtime_test_resource_create(struct runtime_test_observer *observer,
                                                         runtime_test_callback callback, void *data);
int runtime_test_dispatch(struct runtime_test_resource *resource);
void runtime_test_resource_destroy(struct runtime_test_resource *resource);

#endif
