# Ownership and FFI

Define an acquisition and terminal action for every native resource and callback context.

## Resource ledger

| Resource | Acquisition | Owner | Terminal action |
|---|---|---|---|
| Client display | connect / successful descriptor adoption | ClientConnection | disconnect once |
| Client queue | create queue / create named queue | EventQueue | destroy before display disconnect |
| Owned proxy | generated constructor / valid adoption | Generated owner | protocol destructor when applicable, otherwise local proxy destroy |
| Proxy wrapper | create wrapper | ProxyWrapper | wrapper destroy, never proxy destroy |
| Server display | create | ServerDisplay | destroy clients and registrations, then display destroy |
| Server client | create or native client-created callback | Server registry | native client destroy or external invalidation |
| Resource | resource create | One cleanup record; ResourceOwner holds its authority token | native destroy notification consumes the record once |
| Global / global offer | create / offer | Registration | version-specific withdraw/remove/destroy sequence |
| Standalone event loop | event loop create | EventLoop | remove sources, then loop destroy |
| Display event loop | display get event loop | Borrowed reference | no independent destroy |
| Event source | add fd/timer/signal/idle | Source registration | remove or native one-shot completion |
| Listener/dispatcher storage | provisional allocation and attachment | Physical attachment record, separate from subscription | native-specific detach/destroy, outer-frame quiescence, then context release |
| SHM buffer / pool ref | matching ref operation | Reference owner | matching unref |
| SHM access | begin access | Scoped access token | end access on every exit |
| Cursor theme | theme load | CursorTheme | theme destroy |
| Cursor/image/buffer view | theme lookup | Borrowed reference | invalidate with theme; no independent destroy |
| EGL window | native window create | NativeWindow | window destroy before surface lifetime ends |
| Protocol logger | logger add | Logger registration | logger destroy and context release |
| Owned descriptor | receive, duplicate, successful adoption | OwnedFileDescriptor | close exactly once unless transferred |

For each ledger row, implementation must record nullability, failure behavior, callback reentrancy, thread contract, and the exact libwayland source location that establishes ownership. The table is an intended ownership policy; ambiguous native failure-path ownership must be resolved from version-pinned source and tested before exposing a safe API.

## Owner, reference, and borrow contracts

An owning value cannot be implicitly copied. `close` consumes the owner or atomically moves its cell to a terminal state. Repeated close through another path returns an already-closed result without touching freed native memory. A checked object reference validates cell state and generation under the same execution-domain guard as the C call. Copyable object references are not memory borrows; only scoped byte/argument views are borrows. The guard remains held logically until the native operation completes; checking a pointer and then releasing the guard before use is prohibited.

Generated object references carry interface identity and connection identity. Equal numeric IDs from different displays are unrelated. An owned proxy created by the generator has a destructor policy derived from protocol metadata. Releasing a proxy locally does not automatically mean sending a protocol destructor. An explicit close may send the destructor while connected. Fallback cleanup after a terminal connection error performs local release only and cannot pretend the remote destructor succeeded.

During parent shutdown, acquire logical domain ownership and mark the session closing. Reject new user operations, wake outstanding waits, and resolve prepared reads on their coordinator. Native frees wait for all relevant outer native frames, memory borrows, and dependent consumers to finish. Stop user delivery while keeping mandatory cleanup dispatchers alive; then process authoritative cleanup records in reverse dependency order. Invalidate references before releasing their native backing, destroy owned proxies and queues before client disconnect, and finally destroy the parent. Cursor/EGL children precede their underlying client objects. A record consumed by a native cascading destructor must not be released again.

Low-level cleanup does not launch detached Tasks. A top-level close outside a native frame drains eligible work synchronously. Close requested inside a callback is a logical close that returns while physical release is pending until the outer native frame exits. A synchronous close-and-drain operation is prohibited inside that frame; waiting for itself would deadlock. Report deferred versus complete closure in the API contract rather than promising immediate destruction from every context.

Non-Sendable owners reduce cross-domain use but do not make destruction run on a particular OS thread. The runtime must validate the execution domain for ordinary calls and use a serialized teardown path that can safely operate from finalization. If a native facility has a strict thread-affinity requirement, its owner must use a domain-owned destruction queue that is synchronously drained during explicit shutdown; fallback cannot depend on an executor that may already have stopped. The initial low-level domain uses serialized, synchronous, non-suspending access and verifies every operation including close; non-Sendable is an additional check, not a runtime lock. The domain claim spans poll/read transactions but the bookkeeping mutex is not held over blocking poll or user code. Foreign-thread cleanup first wakes the coordinator and reaches a rendezvous outside its native frame. It must never block the coordinator on its own teardown.

Thread-affine integrations must remain unsafe or unavailable in the safe facade until a live affine execution endpoint can be proven for the entire owner lifetime, including fallback cleanup. Explicit-close guidance alone does not satisfy fallback safety. This is an implementation gate, not an assumption about ARC.

## Callback bridge and reentrancy

C callback data and listener addresses must remain stable for the entire native registration lifetime. Allocate a context box or bridge allocation; never pass an address of a movable Swift value, a temporary array buffer, or a stack-local listener to a retained C registration. Container-of arithmetic belongs in audited C code operating on its own concrete allocation layout.

Registration proceeds in four steps: allocate context; install the native callback; publish the token on success; release or detach on failure according to the native call's ownership contract. Record the provisional context obligation as soon as allocation succeeds. Transfer it to the native-reachable registration record only after attachment succeeds. Attachment is allowed to call back synchronously, so a fully initialized provisional context and operation lease must exist before the native call. Destruction from the native side and cancellation from Swift race through the same cell transition.

Before invoking user code, the trampoline acquires an active-callback lease and validates the target cell. It decodes arguments into scoped borrowed views. It releases internal mutation locks before invoking user code. After user code returns, it drops the callback lease. This does not itself authorize deferred native destruction: the enclosing dispatch/run/iteration C frame and any transitive dependency leases may still use the object. Drain only at the proven outer frame boundary. A callback may cancel itself; context release waits until its trampoline returns.

User callbacks may query live objects and issue permitted requests. Recursive dispatch, blocking roundtrip, and awaiting while holding a borrowed view are rejected. Destroying the current object marks it closing immediately, preventing new calls, but native free is deferred until the relevant outer native frame has returned to the bridge, not merely until the Swift handler or trampoline returns. Native calls can synchronously invoke destroy listeners; destruction bookkeeping must not hold a nonrecursive mutex over such a call.

Avoid runtime-owned strong closure cycles. Prefer handler objects stored weakly by the runtime, with an explicit registration owner maintaining their lifetime. A closure convenience API must document capture rules and cancellation. The library cannot guarantee collection of arbitrary user-created ARC cycles. In particular, an owner retaining a registration whose closure retains the owner requires weak captures, explicit owner/root closure, or explicit removal of the captured strong references. Flag-only cancellation of a permanent dispatcher does not release its native-reachable context. Library tests must prove that its own registries, tasks, and contexts introduce no such cycle.

Exceptions do not unwind across C. Swift errors are caught before returning to native code. A callback failure becomes a recorded domain error, protocol error, or scheduled shutdown as appropriate. Protocol error messages are data, never printf format strings.

## Arguments and C representation

| Native representation | Safe representation | Checks |
|---|---|---|
| int / uint | Int32 / UInt32 | Exact width and checked conversion |
| wl_fixed_t | Fixed with Int32 storage | Raw round trip; floating-point range and rounding policy |
| string | Scoped UTF-8 bytes or explicit owned String | Nullability, interior NUL on send, decoding policy |
| array | Scoped RawSpan or owned bytes | Initialized length, overflow, alignment only when proven |
| object | Typed checked reference | Interface, generation, connection, nullability |
| new_id | Constructor result / validated incoming identity | Interface/version negotiation and duplicate-ID handling |
| fd | BorrowedFileDescriptor / OwnedFileDescriptor | Ownership transfer, duplication and error cleanup |
| void pointer / arbitrary userdata | Unsafe interoperability only | Cannot be made safe through a generic cast |

Use array-form marshalling and generated typed trampolines instead of calling arbitrary C varargs from Swift. The compatibility layer maps each varargs function to equivalent typed operations or a C adapter. Format-based error/log APIs require a C adapter using `va_copy` and bounded formatting. A Swift string is passed through a fixed `%s` format rather than being interpreted as a format string.

`wl_proxy` and server `wl_resource` user-data slots are reserved by the runtime for runtime-owned objects. Expose typed Swift associated state separately. Interoperability with another owner requires an explicit adoption/handoff contract; silently replacing another library's listener or user data is prohibited. Borrowed foreign objects are only safe when invalidation is coordinated; otherwise access stays unsafe.

Protocol metadata includes `wl_interface`, `wl_message`, signatures, and type pointer arrays. Generate immutable C storage or pinned process-lifetime storage. Do not keep C pointers into temporary Swift arrays. Metadata is an explicitly bounded process-lifetime allocation, reported separately from connection leaks. Custom dynamic metadata needs an owner retained by every native consumer.

## File descriptors and shared memory

Descriptor ownership is specified per operation, including failure. Do not assume every function taking an fd consumes it. Outgoing borrowed fds remain valid through the native marshalling call; received fds become owned and close if decoding or handler delivery fails. To retain a borrowed display or event-loop fd, explicitly duplicate it. Never close the borrowed transport fd.

SHM access uses a scoped token pairing begin and end on the same OS thread, even if a closure throws. Keep its pool and buffer native refs, mapping stability lease, and domain alive until end_access returns. Compute buffer byte extents with checked arithmetic and format-specific plane rules. Validate dimensions, stride, offsets, and mapping extent before producing a byte view. Unknown formats can expose metadata but cannot automatically produce a safe pixel span. Pixel mutation has protocol synchronization requirements beyond Swift exclusivity.

A hostile client can resize or truncate backing storage. A bounds-checked span alone does not prevent SIGBUS. Use libwayland's supported SHM access mechanism, preserve its thread/signal requirements, and avoid adding a conflicting process-wide signal handler. Test truncation and concurrent resize on the target libwayland. The safe API must document that memory mapping and peer synchronization remain part of the trust contract.

## Unsafe audit record

Every unsafe site must record: native operation; pointer provenance; allocation owner; valid length and alignment; lifetime proof; isolation; callback behavior; transfer behavior on success/failure; cleanup action; and an invariant/test identifier. Unsafe operations outside the bridge/runtime allowlist fail review. Assertions document impossible internal states; recoverable peer errors must not trap safe applications.

## Native attachment lifetime versus subscription lifetime

A Swift subscription is not the C attachment. Client proxy listeners/dispatchers have no general public remove operation. Install one stable runtime dispatcher for the proxy's entire native lifetime. Canceling a subscription disables user delivery but leaves the dispatcher, vtable/metadata, and context valid until proxy destruction and outer-frame quiescence. Events that are not delivered still need protocol-aware cleanup, including received descriptors and constructor objects. Installing a second listener is not a replacement strategy. [libwayland 1.26.0 client implementation](https://raw.githubusercontent.com/wayland-mirror/wayland/1.26.0/src/wayland-client.c).

Server resource implementations likewise remain installed until a documented native teardown boundary. Do not replace a native implementation/destructor just to cancel a user handler. Intrusive destroy listeners are different: their link can be detached only while the list head and node remain valid, with one attachment flag preventing double removal. A native destruction notification consumes native ownership immediately; it cannot promise to defer a free controlled by libwayland. Retain only Swift bookkeeping and explicitly supported native references afterwards. Native cleanup callbacks must not expose a supposedly live ResourceReference to user code. Use a copied destruction snapshot instead. [libwayland 1.26.0 server implementation](https://raw.githubusercontent.com/wayland-mirror/wayland/1.26.0/src/wayland-server.c).

Idle-source execution is another separate case. Native dispatch removes an idle source after invoking its callback. Mark the source executing before delivery; cancel/self-close only updates logical state while executing and does not call native remove a second time. Release its context when the outer loop frame reaches the relevant quiescent boundary. FD/timer/signal sources follow their own removal contracts. [libwayland 1.26.0 event-loop implementation](https://raw.githubusercontent.com/wayland-mirror/wayland/1.26.0/src/event-loop.c).

## Borrow scopes, aliasing, and temporary storage

A nonescaping closure does not by itself prevent a copyable pointer or pointer-backed custom view from being returned or stored. A safe scoped API requires a compiler-checked nonescapable view with the correct lifetime dependency, or an operation-only view that validates its lease on every access and cannot yield a raw pointer. If the exact 6.4.2 signature cannot express that contract, return owned data. Never treat `withUnsafePointer`-style closure shape as a proof of borrow containment.

Even a nonescapable view can be invalidated by reentrant mutation inside its own closure. While bytes are borrowed, block or defer resizing/releasing the same wl_array, closing/remapping the SHM pool, freeing a callback context, and destroying native dependencies. Track read versus exclusive-write leases by backing allocation identity; two different Swift wrappers may alias the same storage. A mutable span requires exclusive access against all library-managed aliases. Do not bind arbitrary peer bytes to Swift reference-containing or arbitrary generic types. Typed loads require trivial valid bit patterns, proper alignment or explicit unaligned decoding, and checked extent. C Bool/enums are not accepted by unchecked bit reinterpretation.

Keep every nested buffer/string pointer alive through the complete native call and any documented deferred C retention. Do not flatten several `withCString` scopes into pointers that survive each scope. A custom descriptor owns all transitively referenced signatures, type arrays, strings, and cyclic interface references as a single arena; interface cycles must not become ARC cycles. Proxy tags and logger-message metadata also have explicit storage lifetimes.

## Incoming obligations and allocation failures

Before invoking user code, place all received descriptors and new object IDs in a decode cleanup scope. On partial decode failure, handler failure, missing weak handler, canceled subscription, queue overflow, or connection shutdown, discharge every obligation. Optional delivery must not bypass cleanup. A delivered owned value transfers the obligation exactly once; borrowed views do not. If a server request supplies new_id and a handler creates no resource, follow the schema-specific rejection or fatal-error path instead of silently leaving the client waiting. Each event-created proxy gets a cleanup record before publication.

A borrowed fd integer must not escape to a Sendable command without duplication or a full lifetime lease; the same integer can be reused for a different OS resource. Removing an fd source does not imply ownership of its original caller fd. Use close-on-exec duplication where supported. On Linux, do not blindly retry close after EINTR because the fd number may already have been released and reused; verify platform-specific behavior for any future port. [Linux close(2)](https://man7.org/linux/man-pages/man2/close.2.html).

Checked size arithmetic and bounded quotas prevent deliberate unbounded allocation, but Swift runtime out-of-memory termination is not a recoverable thrown error. Native allocation failures with a documented return path must roll back. Process abort, fatal runtime traps, and nonterminating callbacks are outside normal shutdown liveness claims. Cleanup must not allocate unbounded temporary registries or require allocating a new Task during memory pressure.

## Shared-memory trust boundary

SHM begin/end access tracks thread-local state and permits nesting only according to the native pool rules. The safe initial facade prohibits overlapping access sessions for different pools on one thread and prohibits await or thread migration between begin and end. Retain a native buffer reference through end even when its protocol resource is destroyed. Mapping mutation is excluded until all scoped accesses finish. [libwayland 1.26.0 SHM implementation](https://raw.githubusercontent.com/wayland-mirror/wayland/1.26.0/src/wayland-shm.c).

Externally writable pixels are not immutable Swift values. Do not offer peer-controlled bytes as a freely shareable immutable Span or a Sendable value. Safe default processing copies byte-oriented data under the native access guard into initialized owned storage and validates interpreted values; the copy is not an atomic frame snapshot without protocol synchronization. Zero-copy access is an explicitly scoped external-memory capability with documented synchronization assumptions, no references to arbitrary Swift types, and no claim that the Swift compiler proves peer exclusivity. Keep it unsafe if these assumptions cannot be enforced. Native SIGBUS mitigation does not establish an atomic frame, prevent peer mutation, or prove the native implementation recovers from every allocation failure.
