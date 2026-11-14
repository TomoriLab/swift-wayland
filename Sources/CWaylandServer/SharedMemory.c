#include "CWaylandServer.h"
#include <stdint.h>
#include <string.h>
#include <errno.h>

static _Thread_local int snapshot_active;
int wayland_kit_shm_snapshot(struct wl_shm_buffer *buffer, unsigned char *output, size_t length)
{
    if (snapshot_active) return EBUSY;
    int32_t width = wl_shm_buffer_get_width(buffer);
    int32_t height = wl_shm_buffer_get_height(buffer);
    int32_t stride = wl_shm_buffer_get_stride(buffer);
    uint32_t format = wl_shm_buffer_get_format(buffer);
    if ((format != WL_SHM_FORMAT_ARGB8888 && format != WL_SHM_FORMAT_XRGB8888) ||
        width <= 0 || height <= 0 || width > INT32_MAX / 4 || stride < width * 4)
        return EINVAL;
    size_t row = (size_t)width * 4;
    if ((size_t)height > SIZE_MAX / row || length != row * (size_t)height ||
        (size_t)(height - 1) > (SIZE_MAX - row) / (size_t)stride || !output)
        return EINVAL;
    snapshot_active = 1;
    struct wl_shm_pool *pool = wl_shm_buffer_ref_pool(buffer);
    wl_shm_buffer_begin_access(buffer);
    const unsigned char *data = wl_shm_buffer_get_data(buffer);
    for (int32_t index = 0; index < height; index++)
        memcpy(output + (size_t)index * row, data + (size_t)index * (size_t)stride, row);
    wl_shm_buffer_end_access(buffer);
    wl_shm_pool_unref(pool);
    snapshot_active = 0;
    return 0;
}
