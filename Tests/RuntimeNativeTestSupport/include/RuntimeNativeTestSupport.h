#ifndef WAYLAND_RUNTIME_NATIVE_TEST_SUPPORT_H
#define WAYLAND_RUNTIME_NATIVE_TEST_SUPPORT_H
#include <stdint.h>
#include <stddef.h>
#include <wayland-util.h>

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
int runtime_test_descriptor_write_one(int descriptor);
int runtime_test_descriptor_read_one(int descriptor);
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
void runtime_test_server_add_typed_globals(struct runtime_test_server *server);
int runtime_test_listening_socket(const char *path);
int runtime_test_server_listen(struct runtime_test_server *, const char *path);
void runtime_test_server_protocol_error(struct runtime_test_server *, unsigned identifier);
int runtime_test_server_dispatch(struct runtime_test_server *server);
void runtime_test_server_destroy(struct runtime_test_server *server);
int runtime_test_socket_pair(int *server_descriptor, int *client_descriptor);
struct runtime_test_c_client;
struct runtime_test_c_client *runtime_test_c_client_create(int descriptor);
int runtime_test_c_client_dispatch(struct runtime_test_c_client *client);
void runtime_test_c_client_destroy(struct runtime_test_c_client *client);
double runtime_test_c_benchmark(unsigned iterations);
struct runtime_test_typed_client;
struct runtime_test_typed_client *runtime_test_typed_client_create(int descriptor, unsigned kind);
int runtime_test_typed_client_construct(struct runtime_test_typed_client *, int descriptor);
int runtime_test_typed_client_destroy_child(struct runtime_test_typed_client *);
unsigned runtime_test_typed_client_protocol_error(struct runtime_test_typed_client *);
int runtime_test_typed_client_dispatch(struct runtime_test_typed_client *);
int runtime_test_typed_client_descriptors(struct runtime_test_typed_client *);
int runtime_test_typed_client_offers(struct runtime_test_typed_client *);
void runtime_test_typed_client_destroy(struct runtime_test_typed_client *);
struct runtime_test_global_client;
struct runtime_test_global_client *runtime_test_global_client_create(int descriptor, int bind);
struct runtime_test_global_client *runtime_test_global_client_connect(const char *path, int bind);
int runtime_test_global_client_dispatch(struct runtime_test_global_client *);
int runtime_test_global_client_advertised(struct runtime_test_global_client *);
int runtime_test_global_client_removed(struct runtime_test_global_client *);
void runtime_test_global_client_destroy(struct runtime_test_global_client *);
uint64_t runtime_native_abi_value(unsigned index);
struct runtime_core_server;
struct runtime_core_server *runtime_core_server_create(int *descriptor);
unsigned runtime_core_server_global(struct runtime_core_server *, const char *name);
int runtime_core_server_dispatch(struct runtime_core_server *);
unsigned runtime_core_server_requests(struct runtime_core_server *);
unsigned runtime_core_server_opcode(struct runtime_core_server *);
const char *runtime_core_server_interface(struct runtime_core_server *);
const char *runtime_core_server_constructor(struct runtime_core_server *);
void runtime_core_server_event(struct runtime_core_server *, uint32_t identifier, uint32_t opcode, const uint32_t *objects, int descriptor, int use_null);
void runtime_core_server_destroy(struct runtime_core_server *);
struct runtime_core_client;
struct runtime_core_client *runtime_core_client_create(int descriptor, const char *interface);
int runtime_core_client_advertisements(struct runtime_core_client *);
uint32_t runtime_core_client_object(struct runtime_core_client *, const char *interface);
int runtime_core_client_request(struct runtime_core_client *, uint32_t opcode, const uint32_t *objects, int descriptor, int use_null);
int runtime_core_client_events(struct runtime_core_client *);
unsigned runtime_core_client_event_count(struct runtime_core_client *);
unsigned runtime_core_client_opcode(struct runtime_core_client *);
const char *runtime_core_client_constructor(struct runtime_core_client *);
void runtime_core_client_destroy(struct runtime_core_client *);
struct wl_client;
void runtime_test_client_destroy_resource(struct wl_client *, uint32_t identifier);
int runtime_test_peer_generate_log(struct runtime_test_peer *);
int runtime_test_server_generate_log(struct runtime_test_server *);
struct wl_list *runtime_test_server_clients(struct runtime_test_server *);
struct runtime_list_fixture;
struct runtime_list_fixture *runtime_test_list_create(void);
struct wl_list *runtime_test_list_head(struct runtime_list_fixture *);
size_t runtime_test_list_offset(void);
int runtime_test_list_value(void *pointer);
void runtime_test_list_remove(void *pointer);
void runtime_test_list_destroy(struct runtime_list_fixture *);
struct runtime_resource_list;
struct runtime_resource_list *runtime_test_resource_list_create(int *descriptor);
struct wl_list *runtime_test_resource_list_head(struct runtime_resource_list *);
void runtime_test_resource_list_destroy(struct runtime_resource_list *);

int runtime_test_server_initialize_shm(struct runtime_test_server *server);
struct runtime_test_shm_client;
struct runtime_test_shm_client *runtime_test_shm_client_create(int descriptor);
int runtime_test_shm_client_dispatch(struct runtime_test_shm_client *);
uint32_t runtime_test_shm_client_buffer(struct runtime_test_shm_client *);
void runtime_test_shm_client_resize(struct runtime_test_shm_client *);
void runtime_test_shm_client_destroy(struct runtime_test_shm_client *);
void runtime_test_trigger_server_log(void);
struct wl_array *runtime_test_array_fixture(void);
union wl_argument runtime_test_argument(unsigned field);
void runtime_core_server_scalar_batch(struct runtime_core_server *, uint32_t identifier, unsigned count);
int runtime_test_allocation_available(void);
void runtime_test_allocation_begin(void);
uint64_t runtime_test_allocation_end(void);
uint64_t runtime_test_clock_nanoseconds(void);
double runtime_core_benchmark_c(unsigned iterations, unsigned batch, uint64_t *allocations, uint64_t *latencies, double *cpu_seconds, double *teardown_seconds, uint64_t *phase_nanoseconds);
typedef int (*runtime_test_scalar_dispatcher)(const void *, void *, uint32_t, const struct wl_message *, union wl_argument *);
double runtime_core_benchmark_swift_callback(unsigned iterations, unsigned batch, runtime_test_scalar_dispatcher dispatcher);
typedef int (*runtime_test_read_dispatcher)(struct wl_display *);
double runtime_core_benchmark_swift_read(unsigned iterations, unsigned batch, runtime_test_scalar_dispatcher dispatcher, runtime_test_read_dispatcher read_dispatcher);
double runtime_core_benchmark_requests(unsigned iterations, unsigned batch, uint64_t *allocations, uint64_t *latencies);
double runtime_core_benchmark_string_requests(unsigned iterations, unsigned batch, uint64_t *allocations, uint64_t *latencies);
uint64_t runtime_test_thread_nanoseconds(void);
int runtime_test_live_descriptor_count(void);

uint32_t runtime_test_shm_client_buffer_layout(struct runtime_test_shm_client *, int32_t width, int32_t height, int32_t stride, uint32_t format);
int runtime_test_shm_client_truncate(struct runtime_test_shm_client *, int64_t size);
int runtime_descriptor_roundtrip(const struct wl_interface *interface);
struct runtime_protocol_peer;
struct runtime_protocol_peer *runtime_protocol_peer_create(int *descriptor);
void runtime_protocol_peer_destroy(struct runtime_protocol_peer *);
unsigned runtime_protocol_peer_global(struct runtime_protocol_peer *);
int runtime_protocol_peer_dispatch(struct runtime_protocol_peer *);
void runtime_protocol_peer_emit(struct runtime_protocol_peer *, unsigned kind, int descriptor);
unsigned runtime_protocol_peer_resources(struct runtime_protocol_peer *);
unsigned runtime_protocol_peer_destroyed(struct runtime_protocol_peer *);
unsigned runtime_protocol_peer_requests(struct runtime_protocol_peer *);
unsigned runtime_protocol_peer_descriptors(struct runtime_protocol_peer *);
const struct wl_interface *runtime_protocol_peer_interface(void);
const struct wl_interface *runtime_protocol_peer_child_interface(void);
void runtime_protocol_peer_error(struct runtime_protocol_peer *);
void runtime_protocol_peer_emit_invalid_object(struct runtime_protocol_peer *, int descriptor);
struct runtime_extension_server_client;
struct runtime_extension_server_client *runtime_extension_server_client_create(int descriptor);
struct runtime_extension_server_client *runtime_extension_server_client_prepare_global(int descriptor);
int runtime_extension_server_client_bind(struct runtime_extension_server_client *, uint32_t name);
int runtime_extension_server_client_request(struct runtime_extension_server_client *);
int runtime_extension_server_client_construct(struct runtime_extension_server_client *);
int runtime_extension_server_client_destroy_child(struct runtime_extension_server_client *);
int runtime_extension_server_client_dispatch(struct runtime_extension_server_client *);
unsigned runtime_extension_server_client_events(struct runtime_extension_server_client *);
void runtime_extension_server_client_destroy(struct runtime_extension_server_client *);
#endif
