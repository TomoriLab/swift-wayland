#ifndef WAYLAND_KIT_LOG_SCOPE_H
#define WAYLAND_KIT_LOG_SCOPE_H
#include <stdarg.h>
struct wayland_runtime_log_scope { va_list arguments; };
typedef void (*wayland_runtime_raw_log_callback)(const char *format, void *scope);
#endif
