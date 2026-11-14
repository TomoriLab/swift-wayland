#include <stddef.h>
#include <stdint.h>
extern void *__libc_malloc(size_t);
extern void *__libc_calloc(size_t, size_t);
extern void *__libc_realloc(void *, size_t);
extern void *__libc_memalign(size_t, size_t);
static _Thread_local int active;
static _Thread_local uint64_t count;
void waylandkit_allocation_begin(void) { count = 0; active = 1; }
uint64_t waylandkit_allocation_end(void) { active = 0; return count; }
void *malloc(size_t size) { if (active) count++; return __libc_malloc(size); }
void *calloc(size_t number, size_t size) { if (active) count++; return __libc_calloc(number, size); }
void *realloc(void *pointer, size_t size) { if (active) count++; return __libc_realloc(pointer, size); }
void *aligned_alloc(size_t alignment, size_t size) { if (active) count++; return __libc_memalign(alignment, size); }
int posix_memalign(void **pointer, size_t alignment, size_t size)
{
    if (alignment < sizeof(void *) || alignment % sizeof(void *) || (alignment & (alignment - 1))) return 22;
    if (active) count++;
    void *result = __libc_memalign(alignment, size);
    if (!result) return 12;
    *pointer = result;
    return 0;
}
