#include "CWaylandServer.h"
#include <stdatomic.h>
#include <stdio.h>
static _Atomic(wayland_runtime_raw_log_callback) raw_callback;
static _Thread_local int delivering;
static void invoke_raw_log(const char *format, va_list arguments)
{
    wayland_runtime_raw_log_callback callback = atomic_load_explicit(&raw_callback, memory_order_acquire);
    if (!callback || delivering) { vfprintf(stderr, format, arguments); return; }
    struct wayland_runtime_log_scope scope;
    va_copy(scope.arguments, arguments);
    delivering = 1;
    callback(format, &scope);
    delivering = 0;
    va_end(scope.arguments);
}
void wayland_kit_server_raw_log_handler(wayland_runtime_raw_log_callback callback)
{
    atomic_store_explicit(&raw_callback, callback, memory_order_release);
    wl_log_set_handler_server(invoke_raw_log);
}
