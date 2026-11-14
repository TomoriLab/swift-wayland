#define _GNU_SOURCE
#include "RuntimeNativeTestSupport.h"
#include <wayland-client.h>
#include <assert.h>
#include <time.h>
#include <dlfcn.h>
static void (*allocation_begin)(void);
static uint64_t (*allocation_end)(void);
int runtime_test_allocation_available(void)
{
    allocation_begin = dlsym(RTLD_DEFAULT, "waylandkit_allocation_begin");
    allocation_end = dlsym(RTLD_DEFAULT, "waylandkit_allocation_end");
    return allocation_begin && allocation_end;
}
void runtime_test_allocation_begin(void) { if (allocation_begin) allocation_begin(); }
uint64_t runtime_test_allocation_end(void) { return allocation_end ? allocation_end() : UINT64_MAX; }
uint64_t runtime_test_clock_nanoseconds(void)
{
    struct timespec time;
    assert(clock_gettime(CLOCK_MONOTONIC, &time) == 0);
    return (uint64_t)time.tv_sec * UINT64_C(1000000000) + (uint64_t)time.tv_nsec;
}
static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version)
{ (void)data; (void)registry; (void)name; (void)interface; (void)version; }
static void removed(void *data, struct wl_registry *registry, uint32_t name) { (void)data; (void)registry; (void)name; }
static int scalar(const void *implementation, void *target, uint32_t opcode, const struct wl_message *message, union wl_argument *arguments)
{
    (void)target; (void)message;
    assert(opcode == 2 && arguments[0].u == 17);
    (*(unsigned *)implementation)++;
    return 0;
}
static double benchmark_with_dispatcher(unsigned iterations, unsigned batch, uint64_t *allocations, uint64_t *latencies, double *cpu_seconds, double *teardown_seconds, uint64_t *phase_nanoseconds, runtime_test_scalar_dispatcher dispatcher, runtime_test_read_dispatcher read_dispatcher)
{
    int descriptor;
    struct runtime_core_server *server = runtime_core_server_create(&descriptor);
    struct wl_display *display = wl_display_connect_to_fd(descriptor);
    assert(display);
    struct wl_registry *registry = wl_display_get_registry(display);
    static const struct wl_registry_listener listener = { global, removed };
    assert(wl_registry_add_listener(registry, &listener, NULL) == 0);
    assert(wl_display_flush(display) >= 0 && runtime_core_server_dispatch(server) == 0);
    assert(wl_display_prepare_read(display) == 0 && wl_display_read_events(display) == 0);
    assert(wl_display_dispatch_pending(display) >= 0);
    struct wl_data_offer *offer = wl_registry_bind(registry, runtime_core_server_global(server, "wl_data_offer"), &wl_data_offer_interface, 3);
    assert(offer);
    unsigned count = 0;
    assert(wl_proxy_add_dispatcher((struct wl_proxy *)offer, dispatcher, &count, NULL) == 0);
    assert(wl_display_flush(display) >= 0 && runtime_core_server_dispatch(server) == 0);
    uint32_t identifier = wl_proxy_get_id((struct wl_proxy *)offer);
    runtime_core_server_scalar_batch(server, identifier, batch);
    assert(wl_display_prepare_read(display) == 0 && wl_display_read_events(display) == 0);
    assert(wl_display_dispatch_pending(display) >= 0);
    count = 0;
    uint64_t cpu_start = runtime_test_thread_nanoseconds();
    runtime_test_allocation_begin();
    uint64_t start = runtime_test_clock_nanoseconds();
    for (unsigned index = 0; index < iterations; index += batch) {
        unsigned number = iterations - index < batch ? iterations - index : batch;
        uint64_t batch_start = latencies ? runtime_test_clock_nanoseconds() : 0;
        uint64_t phase_start = phase_nanoseconds ? runtime_test_clock_nanoseconds() : 0;
        runtime_core_server_scalar_batch(server, identifier, number);
        uint64_t sent = phase_nanoseconds ? runtime_test_clock_nanoseconds() : 0;
        if (read_dispatcher) {
            assert(read_dispatcher(display) == 0);
        } else {
            assert(wl_display_prepare_read(display) == 0 && wl_display_read_events(display) == 0);
        }
        uint64_t read = phase_nanoseconds ? runtime_test_clock_nanoseconds() : 0;
        if (!read_dispatcher) assert(wl_display_dispatch_pending(display) >= 0);
        if (phase_nanoseconds) {
            uint64_t dispatched = runtime_test_clock_nanoseconds();
            phase_nanoseconds[0] += sent - phase_start;
            phase_nanoseconds[1] += read - sent;
            phase_nanoseconds[2] += dispatched - read;
        }
        if (latencies) latencies[index / batch] = runtime_test_clock_nanoseconds() - batch_start;
    }
    uint64_t elapsed = runtime_test_clock_nanoseconds() - start;
    *allocations = runtime_test_allocation_end();
    *cpu_seconds = (double)(runtime_test_thread_nanoseconds() - cpu_start) / 1e9;
    uint64_t teardown_start = runtime_test_clock_nanoseconds();
    assert(count == iterations);
    wl_data_offer_destroy(offer);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    runtime_core_server_destroy(server);
    *teardown_seconds = (double)(runtime_test_clock_nanoseconds() - teardown_start) / 1e9;
    return (double)elapsed / 1e9;
}

double runtime_core_benchmark_c(unsigned iterations, unsigned batch, uint64_t *allocations, uint64_t *latencies, double *cpu_seconds, double *teardown_seconds, uint64_t *phase_nanoseconds)
{
    return benchmark_with_dispatcher(iterations, batch, allocations, latencies, cpu_seconds, teardown_seconds, phase_nanoseconds, scalar, NULL);
}

double runtime_core_benchmark_swift_callback(unsigned iterations, unsigned batch, runtime_test_scalar_dispatcher dispatcher)
{
    uint64_t allocations = 0;
    double cpu_seconds = 0, teardown_seconds = 0;
    return benchmark_with_dispatcher(iterations, batch, &allocations, NULL, &cpu_seconds, &teardown_seconds, NULL, dispatcher, NULL);
}

double runtime_core_benchmark_swift_read(unsigned iterations, unsigned batch, runtime_test_scalar_dispatcher dispatcher, runtime_test_read_dispatcher read_dispatcher)
{
    uint64_t allocations = 0;
    double cpu_seconds = 0, teardown_seconds = 0;
    return benchmark_with_dispatcher(iterations, batch, &allocations, NULL, &cpu_seconds, &teardown_seconds, NULL, dispatcher, read_dispatcher);
}

uint64_t runtime_test_thread_nanoseconds(void)
{
    struct timespec time;
    assert(clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time) == 0);
    return (uint64_t)time.tv_sec * UINT64_C(1000000000) + (uint64_t)time.tv_nsec;
}

/* Both request fixtures drain each batch before checking the peer's exact count. */
double runtime_core_benchmark_requests(unsigned iterations, unsigned batch, uint64_t *allocations, uint64_t *latencies)
{
    int descriptor;
    struct runtime_core_server *server = runtime_core_server_create(&descriptor);
    struct wl_display *display = wl_display_connect_to_fd(descriptor);
    assert(display);
    struct wl_registry *registry = wl_display_get_registry(display);
    struct wl_surface *surface = wl_registry_bind(registry, runtime_core_server_global(server, "wl_surface"), &wl_surface_interface, 1);
    assert(surface);
    wl_surface_commit(surface);
    assert(wl_display_flush(display) >= 0 && runtime_core_server_dispatch(server) == 0);
    unsigned before = runtime_core_server_requests(server);
    runtime_test_allocation_begin();
    uint64_t start = runtime_test_clock_nanoseconds();
    for (unsigned index = 0; index < iterations; index += batch) {
        unsigned count = iterations - index < batch ? iterations - index : batch;
        uint64_t batch_start = latencies ? runtime_test_clock_nanoseconds() : 0;
        for (unsigned item = 0; item < count; item++) wl_surface_commit(surface);
        assert(wl_display_flush(display) >= 0 && runtime_core_server_dispatch(server) == 0);
        if (latencies) latencies[index / batch] = runtime_test_clock_nanoseconds() - batch_start;
    }
    uint64_t elapsed = runtime_test_clock_nanoseconds() - start;
    *allocations = runtime_test_allocation_end();
    assert(runtime_core_server_requests(server) - before == iterations);
    wl_surface_destroy(surface);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    runtime_core_server_destroy(server);
    return (double)elapsed / 1e9;
}

double runtime_core_benchmark_string_requests(unsigned iterations, unsigned batch, uint64_t *allocations, uint64_t *latencies)
{
    int descriptor;
    struct runtime_core_server *server = runtime_core_server_create(&descriptor);
    struct wl_display *display = wl_display_connect_to_fd(descriptor);
    assert(display);
    struct wl_registry *registry = wl_display_get_registry(display);
    struct wl_data_source *source = wl_registry_bind(registry, runtime_core_server_global(server, "wl_data_source"), &wl_data_source_interface, 1);
    assert(source);
    wl_data_source_offer(source, "waylandkit-test");
    assert(wl_display_flush(display) >= 0 && runtime_core_server_dispatch(server) == 0);
    unsigned before = runtime_core_server_requests(server);
    runtime_test_allocation_begin();
    uint64_t start = runtime_test_clock_nanoseconds();
    for (unsigned index = 0; index < iterations; index += batch) {
        unsigned count = iterations - index < batch ? iterations - index : batch;
        uint64_t batch_start = latencies ? runtime_test_clock_nanoseconds() : 0;
        for (unsigned item = 0; item < count; item++) wl_data_source_offer(source, "waylandkit-test");
        assert(wl_display_flush(display) >= 0 && runtime_core_server_dispatch(server) == 0);
        if (latencies) latencies[index / batch] = runtime_test_clock_nanoseconds() - batch_start;
    }
    uint64_t elapsed = runtime_test_clock_nanoseconds() - start;
    *allocations = runtime_test_allocation_end();
    assert(runtime_core_server_requests(server) - before == iterations);
    wl_data_source_destroy(source);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    runtime_core_server_destroy(server);
    return (double)elapsed / 1e9;
}
