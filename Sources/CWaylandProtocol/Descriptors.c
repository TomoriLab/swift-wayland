#include "CWaylandProtocol.h"
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct descriptor_block {
    struct descriptor_block *next;
    max_align_t alignment;
    unsigned char bytes[];
};
struct wayland_kit_descriptors {
    struct descriptor_block *blocks;
    struct wl_interface *interfaces;
    size_t count, allocated, maximum;
    int sealed;
};
static void *descriptor_allocate(struct wayland_kit_descriptors *arena, size_t count, size_t size)
{
    if (size && count > (SIZE_MAX - offsetof(struct descriptor_block, bytes)) / size) return NULL;
    size_t total = offsetof(struct descriptor_block, bytes) + count * size;
    if (arena->allocated > arena->maximum || total > arena->maximum - arena->allocated) return NULL;
    struct descriptor_block *block = calloc(1, total);
    if (!block) return NULL;
    block->next = arena->blocks;
    arena->blocks = block;
    arena->allocated += total;
    return block->bytes;
}
static char *descriptor_string(struct wayland_kit_descriptors *arena, const char *value)
{
    if (!value) return NULL;
    size_t size = strlen(value);
    if (size == SIZE_MAX) return NULL;
    char *copy = descriptor_allocate(arena, size + 1, 1);
    if (copy) memcpy(copy, value, size + 1);
    return copy;
}
void wayland_kit_descriptors_destroy(struct wayland_kit_descriptors *arena)
{
    if (!arena) return;
    struct descriptor_block *block = arena->blocks;
    while (block) {
        struct descriptor_block *next = block->next;
        free(block);
        block = next;
    }
    free(arena);
}
struct wayland_kit_descriptors *wayland_kit_descriptors_create(size_t count, size_t maximum)
{
    if (!count || count > 4096 || maximum <= sizeof(struct wayland_kit_descriptors) || maximum > 16 * 1024 * 1024) return NULL;
    struct wayland_kit_descriptors *arena = calloc(1, sizeof(*arena));
    if (!arena) return NULL;
    arena->count = count;
    arena->maximum = maximum - sizeof(*arena);
    arena->interfaces = descriptor_allocate(arena, count, sizeof(*arena->interfaces));
    if (!arena->interfaces) { wayland_kit_descriptors_destroy(arena); return NULL; }
    return arena;
}
int wayland_kit_descriptors_interface(struct wayland_kit_descriptors *arena, size_t index,
                                    const char *name, int version, size_t requests, size_t events)
{
    if (arena->sealed || index >= arena->count || version <= 0 || requests > 65535 || events > 65535) return -1;
    struct wl_interface *interface = &arena->interfaces[index];
    if (interface->name) return -1;
    interface->name = descriptor_string(arena, name);
    if (!interface->name) return -1;
    interface->version = version;
    interface->method_count = (int)requests;
    interface->event_count = (int)events;
    if (requests) interface->methods = descriptor_allocate(arena, requests, sizeof(struct wl_message));
    if (events) interface->events = descriptor_allocate(arena, events, sizeof(struct wl_message));
    return (requests && !interface->methods) || (events && !interface->events) ? -1 : 0;
}
static struct wl_message *descriptor_message(struct wayland_kit_descriptors *arena, size_t index, int event, size_t opcode)
{
    if (arena->sealed || index >= arena->count || (event != 0 && event != 1)) return NULL;
    struct wl_interface *interface = &arena->interfaces[index];
    size_t count = (size_t)(event ? interface->event_count : interface->method_count);
    const struct wl_message *messages = event ? interface->events : interface->methods;
    if (!messages || opcode >= count) return NULL;
    return (struct wl_message *)&messages[opcode];
}
int wayland_kit_descriptors_message(struct wayland_kit_descriptors *arena, size_t index, int event, size_t opcode,
                                  const char *name, const char *signature, size_t arguments)
{
    struct wl_message *message = descriptor_message(arena, index, event, opcode);
    if (!message || message->name || arguments > 20 || !signature) return -1;
    const char *character = signature;
    while (*character >= '0' && *character <= '9') character++;
    size_t count = 0;
    while (*character) {
        if (*character == '?') {
            character++;
            if (!*character || !strchr("soa", *character)) return -1;
        }
        if (!*character || !strchr("iufsonah", *character++)) return -1;
        count++;
    }
    if (count != arguments) return -1;
    message->name = descriptor_string(arena, name);
    message->signature = descriptor_string(arena, signature);
    if (arguments) message->types = descriptor_allocate(arena, arguments, sizeof(struct wl_interface *));
    return !message->name || !message->signature || (arguments && !message->types) ? -1 : 0;
}
int wayland_kit_descriptors_argument(struct wayland_kit_descriptors *arena, size_t index, int event,
                                   size_t opcode, size_t argument, size_t target)
{
    struct wl_message *message = descriptor_message(arena, index, event, opcode);
    if (!message || !message->signature || !message->types || target >= arena->count) return -1;
    size_t count = 0;
    for (const char *character = message->signature; *character; character++) {
        if (strchr("iufsonah", *character)) count++;
    }
    if (argument >= count) return -1;
    ((const struct wl_interface **)message->types)[argument] = &arena->interfaces[target];
    return 0;
}
int wayland_kit_descriptors_seal(struct wayland_kit_descriptors *arena)
{
    if (arena->sealed) return -1;
    for (size_t index = 0; index < arena->count; index++) {
        const struct wl_interface *interface = &arena->interfaces[index];
        if (!interface->name || interface->version <= 0) return -1;
        for (int event = 0; event <= 1; event++) {
            const struct wl_message *messages = event ? interface->events : interface->methods;
            int count = event ? interface->event_count : interface->method_count;
            if (count && !messages) return -1;
            for (int opcode = 0; opcode < count; opcode++) {
                if (!messages[opcode].name || !messages[opcode].signature) return -1;
                if (strpbrk(messages[opcode].signature, "iufsonah") && !messages[opcode].types) return -1;
            }
        }
    }
    arena->sealed = 1;
    return 0;
}
const struct wl_interface *wayland_kit_descriptors_get(struct wayland_kit_descriptors *arena, size_t index)
{
    return arena->sealed && index < arena->count ? &arena->interfaces[index] : NULL;
}
size_t wayland_kit_descriptors_bytes(const struct wayland_kit_descriptors *arena) { return arena->allocated + sizeof(*arena); }
