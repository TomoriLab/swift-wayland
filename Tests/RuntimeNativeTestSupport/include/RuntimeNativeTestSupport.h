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


/* Descriptor helpers are independent libc oracles for runtime ownership tests. */
int runtime_test_descriptor_open(void);
int runtime_test_descriptor_is_open(int descriptor);
int runtime_test_descriptor_cloexec(int descriptor);
int runtime_test_descriptor_close(int descriptor);
int runtime_test_descriptor_replace(int descriptor);
int runtime_test_high_descriptor_count(void);

struct runtime_test_callback_slot;
typedef int (*runtime_test_context_callback)(void *data, int descriptor);
struct runtime_test_callback_slot *runtime_test_callback_slot_create(void);
void runtime_test_callback_slot_destroy(struct runtime_test_callback_slot *slot);
void runtime_test_callback_install(struct runtime_test_callback_slot *slot, runtime_test_context_callback callback, void *data);
int runtime_test_callback_invoke(struct runtime_test_callback_slot *slot, int descriptor);
void runtime_test_callback_detach(struct runtime_test_callback_slot *slot, int invoke_while_detaching);
int runtime_test_callback_detach_count(const struct runtime_test_callback_slot *slot);

int runtime_test_matching_descriptor_count(int descriptor);

struct runtime_test_peer;
struct wl_display;
struct wl_proxy;
struct runtime_test_peer *runtime_test_peer_create(void);
struct wl_display *runtime_test_peer_display(struct runtime_test_peer *peer);
struct wl_proxy *runtime_test_peer_proxy(struct runtime_test_peer *peer);
void runtime_test_peer_post(struct runtime_test_peer *peer, unsigned opcode, int descriptor);
int runtime_test_peer_dispatch(struct runtime_test_peer *peer);
void runtime_test_peer_disconnect(struct runtime_test_peer *peer);
void runtime_test_peer_destroy(struct runtime_test_peer *peer);
struct runtime_test_server;
struct runtime_test_server *runtime_test_server_create(int *client_descriptor);
int runtime_test_server_dispatch(struct runtime_test_server *server);
void runtime_test_server_destroy(struct runtime_test_server *server);
int runtime_test_socket_pair(int *server_descriptor, int *client_descriptor);
struct runtime_test_c_client;
struct runtime_test_c_client *runtime_test_c_client_create(int descriptor);
int runtime_test_c_client_dispatch(struct runtime_test_c_client *client);
void runtime_test_c_client_destroy(struct runtime_test_c_client *client);
double runtime_test_c_benchmark(unsigned iterations);
#endif
