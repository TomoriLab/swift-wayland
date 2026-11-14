#include "CWaylandRuntime.h"
#include "WaylandLogScope.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
char *wayland_runtime_copy_log_message(const char *format, void *opaque, size_t maximum, size_t *length, int *truncated)
{
    if (!format || !opaque || maximum > 1048576 || !length || !truncated) { errno = EINVAL; return NULL; }
    struct wayland_runtime_log_scope *scope = opaque;
    char *message = malloc(maximum + 1);
    if (!message) return NULL;
    va_list arguments;
    va_copy(arguments, scope->arguments);
    int needed = vsnprintf(message, maximum + 1, format, arguments);
    va_end(arguments);
    if (needed < 0) { free(message); return NULL; }
    size_t count = (size_t)needed > maximum ? maximum : (size_t)needed;
    *length = count; *truncated = (size_t)needed > maximum;
    return message;
}
void wayland_runtime_free_log_message(char *message) { free(message); }

void wayland_runtime_print_log_message(const char *format, void *arguments)
{
    struct wayland_runtime_log_scope *scope = arguments;
    va_list copied;
    va_copy(copied, scope->arguments);
    vfprintf(stderr, format, copied);
    va_end(copied);
}
