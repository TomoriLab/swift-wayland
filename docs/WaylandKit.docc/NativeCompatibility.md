# Explicit native compatibility

Map native declarations without disguising raw interoperability as a safe ownership facade.

## Boundary

The typed ownership APIs validate lifetime and domain invariants. The native compatibility namespaces preserve direct access to the pinned C ABI and are explicitly unsafe, including functions whose C signatures happen to contain only scalars. Calling native destruction, changing userdata/listeners/dispatchers, mutating intrusive lists, or driving independent readers can violate a safe owner's contract. A caller must establish native pointer provenance, alignment, bounds, initialized values, native lifetime, serialization, callback retention, and exclusive destruction authority. No native alias acquires a cleanup record automatically.

Function aliases retain the actual imported C function type rather than maintaining a second handwritten Swift signature. This preserves nullability, calling convention, native enum and callback types, and default C argument representation. Deterministic generation and compile-time checks establish availability and ABI shape; representative native tests exercise each family. They do not prove arbitrary caller-supplied pointers or callbacks valid.

Native variadic request/event helpers map to their native array counterparts. Literal error helpers use a C bridge with a constant printf format and an explicit message string. A Swift call cannot forward an arbitrary C ellipsis. The mapping manifest records each calling-convention adaptation and keeps unsafe compatibility distinct from generated typed requests.

Immutable core interface data is exposed as pointers to process-lifetime native metadata, never temporary Swift copies. Native complete record aliases retain their imported C field layout. Opaque records map to opaque pointer handles, not invented Swift value layouts. Callback type aliases retain their C convention and native retention requirements. Numerical opcode, version, enum, and flag constants preserve their native values. Include guards and C-only declaration attributes are classified as preprocessing controls with no Swift runtime API; classifying them does not pretend they are executable functionality.

Function-like intrusive iteration/container macros require explicit unsafe adapters with caller-proven native layout and mutation rules. Type inference and source-language declaration attributes have no directly interchangeable Swift value. Their classifications and replacements are recorded rather than silently omitted.

## Acceptance accounting

The native inventory distinguishes high-level ownership implementations, direct unsafe ABI mappings, generated typed protocol coverage, and C-only preprocessing exclusions. A direct import alone is insufficient. Each mapping requires an explicit generated declaration or adapter, a documented contract, and compiler/native verification appropriate to its behavior. Complete native classification does not by itself establish the advanced safe ownership families or the performance acceptance gate.

## Log callback adaptation

The native va_list callback typedef cannot be exported directly through the tested Swift 6.4.2 module boundary: consuming that imported alias crashes compiler deserialization, and a handwritten CVaListPointer C convention type is rejected as unrepresentable. The compatibility callback therefore receives the original format pointer and an opaque, callback-scoped argument frame. The C trampoline copies the native va_list into that frame. UtilitiesInterop.formatLogMessage performs a second va_copy in C, formats once into bounded storage, returns owned text, and frees the temporary allocation on every outcome. This avoids architecture-specific Swift reinterpretation and incompatible C function-pointer casts. Native setter names map to the explicit bridge in the manifest. A nil raw handler uses stderr through the permanent bridge; foreign native callback replacement and concurrent native setter calls remain unsafe integration responsibilities.

## EGL window ownership gate

The pinned `egl/wayland-egl.c` stores the surface pointer without acquiring a proxy reference. A native-window record therefore depends on the typed surface record. Creation and publication occur within the surface's native access frame. Failed publication destroys the newly allocated window exactly once. Logical surface or session closure invalidates the window before releasing the surface. The initial safe window is unbound: it has no foreign driver callbacks or thread-affinity requirement. Width and height must be positive. Attached size is native state and can remain zero before a driver attaches a buffer.

Foreign EGL integration is an explicitly unsafe scoped operation. Its caller must detach all driver state before returning, prevent retained window pointers and callbacks, obey the driver's thread affinity, and restore the unbound state even when throwing. The scope does not establish these properties automatically. Keeping a driver attachment beyond the scope requires a separate ownership adapter and is outside this API's contract. The safe facade never claims to own an EGL context, EGL surface, or graphics driver.

## Cursor aggregate ownership gate

The pinned `cursor/wayland-cursor.c` owns its image allocations, SHM pool, and lazily created image buffers inside the theme. Image buffers must not be independently destroyed. Theme cleanup is one aggregate obligation depending on the `wl_shm` proxy. Checked cursor and image references share the theme generation. Borrowed buffer references use that same generation, leave native userdata and release listeners intact, and cannot obtain a protocol destructor. Aggregate retirement removes only weak lookup entries of its own generation. It never closes another independently tracked proxy.

Theme loading is explicitly unsafe and uses the native Xcursor parser and its native fallback theme. The caller establishes trusted inputs and aggregate native integer/mapping bounds because the native loader has no quota callback. The Swift boundary validates dimensions and strings but does not claim a bounded total allocation for arbitrary external theme files. Native parser allocation failure and theme-not-found behavior remain native behavior. Metadata is copied; images and buffer access reject a logically closed theme. Animation selection uses the native frame function within the theme lease and validates the returned image index before exposing it.

## Shared-memory reference and snapshot gate

The pinned `src/wayland-shm.c` separates native resource ownership from explicit external buffer and pool refcounts. A retained external buffer survives resource/client destruction. Buffer and pool release records therefore depend on the display, not the client subtree consumed by native destruction. Each increment has its own allocation-backed obligation identifier; the native buffer address is not a unique identifier for multiple increments. Native resource watches remain separate and guard operations requiring a live resource.

A snapshot leases both the external reference and the resource watch. It temporarily increments the native pool reference to prevent a pending resize from moving the mapping. The C bridge performs begin-access, row copies, end-access, and pool unref synchronously on the same thread. A thread-local bridge guard rejects nested snapshots before entering native SHM access. No Swift user closure runs while bytes are borrowed. The bridge accepts only native ARGB8888/XRGB8888 metadata with checked width, height, stride, byte multiplication, and output quota; it copies pixel rows without exposing padding or native pointers. Unknown formats remain available through explicitly unsafe compatibility, not through an invented pixel interpretation.

Native SIGBUS recovery can replace a faulty peer mapping and post a protocol error. A returned snapshot is an owned copy but does not promise atomic frame contents against concurrent peer writes. Native begin-access has a void API and may fail its private TLS allocation before end-access aborts; fatal native allocation failure is outside recoverable error guarantees. The adapter does not suppress SIGBUS or replace libwayland's recovery handler. Explicit raw integrations must not overlap independent SHM begin/end scopes with this adapter.

## Managed process logging gate

Native client/server logging setters mutate process globals and expose no getter or concurrent replacement protocol. Initial installation is explicitly unsafe and requires a quiescent process with no foreign handler replacement. After installation, a permanent C trampoline and a synchronized Swift slot permit safe Sendable-handler replacement. Each subscription has a nonwrapping generation; retiring an older subscription cannot remove a newer handler. Handler invocation occurs outside the slot mutex with an owned bounded text copy. Cancellation prevents subsequent slot acquisition but does not wait for a handler already copied by an in-flight call.

The C trampoline rejects recursive Swift delivery using thread-local state and prints nested messages to stderr instead. An empty managed slot also prints to stderr. Native signal callbacks must not enter Swift logging; source inspection of the pinned SHM SIGBUS handler shows no logging callback on its recovery path. This does not authorize arbitrary foreign signal handlers to log through this facade. Foreign native setter use after installation remains unsafe and can displace the permanent trampoline.

## Utility backing-storage gate

The safe byte-array owner uses native `wl_array` allocation and release with one runtime obligation. Copies are byte-oriented and never bind peer memory as arbitrary Swift values. Checked references share its generation. A view token grants operation-only access during one synchronous scope; escaped tokens reject access after that scope ends. The entire scope holds a native frame and increments a backing-identity borrow count. Append, clear, and nested mutation reject active views before invoking native allocation or changing size. Callback-triggered close invalidates access immediately and defers native release until the outer scope returns. Owned snapshots are independent of the source array's later mutation or closure. Intrusive arbitrary-layout lists remain explicitly unsafe compatibility adapters because Swift cannot validate foreign embedded-node provenance.
