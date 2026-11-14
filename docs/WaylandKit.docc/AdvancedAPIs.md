# Advanced ownership adapters

Use aggregate owners, explicit native refcounts, and backing-storage guards for APIs outside ordinary protocol proxy ownership.

## Native baseline and execution

These adapters target Swift 6.4.2 and libwayland 1.26.0 on x86_64 Linux. Cursor, EGL, SHM, and utility owners are synchronous and non-Sendable. Their checked operations use the same serialized ownership runtime as client/server objects. Native cleanup captures retain storage and copied/weak identity information without a strong control-block back edge. Process logging is the exception: its handler storage is Sendable because the native process globals may log concurrently. It owns no display or native resource.

See <doc:NativeCompatibility> for source-audited native contracts and unsafe interoperability. All incoming native allocations or ref increments are published transactionally. Publication failure undoes the acquisition before returning. Fatal Swift/native allocator termination and caller-created ARC cycles are outside recoverable cleanup guarantees.

## Ownership ledger

| Adapter | Acquisition | Checked prerequisites | Physical release | Native destruction |
|---|---|---|---|---|
| CursorTheme | wl_cursor_theme_load | Typed wl_shm and display domain | wl_cursor_theme_destroy once after dependent operations | Theme owns all cursor/image/pool/buffer allocations |
| CursorReference / CursorImageReference | No native acquisition | Theme generation and bounds | None | Theme closure rejects later operations |
| Cursor image buffer reference | Lazy native buffer owned by theme | Theme generation; original listener/userdata preserved | Theme destroys it | No separate protocol destructor authority |
| NativeWindow | wl_egl_window_create | Typed wl_surface | wl_egl_window_destroy before surface destruction | Safe owner remains unbound to foreign drivers |
| SharedMemoryBuffer | One wl_shm_buffer_ref | Display for release; resource watch for access | One wl_shm_buffer_unref | Client destruction does not consume the external ref |
| SharedMemoryPool | One wl_shm_buffer_ref_pool | Display | One wl_shm_pool_unref | Native mapping relocation remains deferred until external refs drain |
| NativeByteArray | wl_array allocation | Its own ownership session | wl_array_release and metadata free | Active views delay physical release |
| ProcessLogSubscription | Handler generation, no native allocation ownership | Completed quiescent installation | Clears only the matching handler generation | Permanent callback code remains installed |

Native SHM buffer/pool addresses can appear in several simultaneous external increments. Each record uses the address of its distinct retained storage box as the obligation identifier. That address is reserved until record retirement. It is not exposed as an interchangeable native buffer pointer. This satisfies M1, M3, M7, and M13 without rejecting legal multiple native ref increments.

## Cursor themes and EGL windows

Theme loading requires an explicit unsafe input-trust assertion because native Xcursor loading exposes no aggregate allocation quota. The caller must trust selected files and establish native image/pool integer bounds. Subsequent theme lookup copies names and metadata. Checked image lookup validates indices. Native animation selection returns an index and duration and validates the index before creating a view. Lazy buffers are registered only in a weak typed lookup table under the theme generation. They are not individually adopted and receive no Swift dispatcher. Closing the theme invalidates cursor/image/buffer operations immediately; whole-frame quiescence precedes aggregate destruction.

A native EGL window depends on the surface because native creation does not retain it. Positive dimensions are validated before native calls. Attached dimensions can remain zero while unbound. The explicit unsafe foreign scope requires the caller to detach foreign EGL state and callbacks on every exit and restore the unbound state. It cannot retain a native pointer for later rendering. Long-lived real graphics-driver integration requires an independently proven thread-affine adapter.

CursorAndWindowTests verifies lazy buffer identity, image bounds, post-close failures, surface-driven invalidation, and complete root retirement. These tests use native cursor loading and unbound native EGL operations. They do not prove arbitrary theme parser inputs or a real GPU driver lifecycle.

## Shared-memory snapshots

Initialization publishes the native display-owned SHM global. Format advertisement is a compositor policy and does not add Swift pixel decoders. A typed wl_buffer resource must be a native SHM implementation and belong to the display. Acquiring a buffer reference adds an explicit native refcount obligation independently of its resource watch. Copies of the owner are forbidden; reference() performs another real native increment and creates another owner.

snapshot() supports packed ARGB8888/XRGB8888 only. It validates positive dimensions, multiplication, stride, and the caller's byte quota before allocating output. It copies each pixel row and omits padding. A temporary pool reference prevents relocation throughout native begin-access, data lookup, row copies, and end-access. The bridge uses one OS thread and exposes no suspension or Swift user closure. A thread-local guard rejects nested bridge access. Raw integrations must not overlap independent native SHM scopes.

A peer can modify pixels concurrently, so the owned copy need not be an atomic frame. Native SIGBUS recovery may zero faulty mappings and report a protocol error. Resource/client destruction rejects later safe access even while an external ref remains held. The external ref can still be safely released. SharedMemoryTests covers offset/padded rows, quota rejection, multiple buffer/pool refs, deferred resize, resource invalidation after client closure, and failed-publication rollback. Additional malformed peer and isolated truncation tests belong to the native fault matrix.

## Utility view model

NativeByteArrayReference shares one backing identity. withView() retains its frame and increments a read-view count. A view exposes copied bytes and checked byte loads, never raw pointers or arbitrary Swift type binding. Every exit expires the token and decrements the count. Escaped view values remain representable but every operation throws expiredView. All aliases reject append/clear while a view is active. Closing from inside the scope rejects new accesses while deferring physical storage release until return. ByteArrayTests checks these M14/SR4 transitions, quota failure, independent copies, and throwing cleanup.

Intrusive C list macros remain unsafe because arbitrary embedded node layouts cannot be validated by a safe Swift container. NativeAdapterTests exercises all nine container/array/list/client/resource macro adapters against actual C allocations, including removal of the current node only in the native safe-iteration variants. Every wl_argument union projection also has a C-produced runtime value test, separate from layout and field compilation checks.

## Process log handlers

Initial native handler installation requires an explicit unsafe quiescence assertion. Later observe() calls safely replace a Sendable closure and return a generation-scoped token. Canceling an older token cannot clear its replacement. Cancellation does not wait for a handler already retained by a native callback. Handler invocation and final release of replaced/canceled closures occur outside the slot mutex because captured-value destructors can reenter logging.

The bridge copies native va_list arguments entirely in C and bounds copied text to 65536 bytes. Invalid UTF-8 is replaced and truncation is reported. Empty slots and nested delivery use stderr. Native callback code remains process-lifetime stable after initialization. NativeAdapterTests checks repeated va_list copying, truncation, replacement, stale cancellation, callback reentry, and cancellation without fabricated callback detach.

## Source references

The ownership contracts are based on the pinned upstream implementation: [cursor aggregates](https://gitlab.freedesktop.org/wayland/wayland/-/blob/1.26.0/cursor/wayland-cursor.c), [EGL windows](https://gitlab.freedesktop.org/wayland/wayland/-/blob/1.26.0/egl/wayland-egl.c), [SHM references and SIGBUS scopes](https://gitlab.freedesktop.org/wayland/wayland/-/blob/1.26.0/src/wayland-shm.c), and [native utility allocation](https://gitlab.freedesktop.org/wayland/wayland/-/blob/1.26.0/src/wayland-util.c). The isolated source archive and hash are recorded by the native instrumentation tooling.
