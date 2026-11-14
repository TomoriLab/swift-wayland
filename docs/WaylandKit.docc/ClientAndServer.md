# Client and server implementation slices

Use one ownership runtime for client read coordination and server native-destruction observation.

## Implemented modules and release boundary

WaylandClient, WaylandServer, and WaylandProtocol are public SwiftPM products on Swift 6.4.2 and x86_64 Linux. CWaylandClient and CWaylandServer import the installed native headers and contain small adapters. These targets add the already planned libwayland dependencies, not a third-party Swift package or XML runtime dependency. The public WaylandKit facade provides explicit client-first aliases. Native mapping availability and release acceptance are tracked separately in <doc:ImplementationProgress>.

The permanent dispatcher adapter is documented in <doc:ProxyDispatcher>. The observation API exposes owned snapshots. Its descriptor and constructor fields remain markers whose obligations are discharged by the trampoline. Separate typed core request/event bindings now transfer these obligations through noncopyable values; see <doc:TypedProtocol>. Object IDs in snapshots never authorize native access.

## Client ownership graph

```text
ClientConnection -> root session + display record
queue record -> display dependency
permanent proxy record -> display and optional queue dependencies
native invocation -> temporary frame over the complete synchronous call
read reservation -> temporary display lease + one prepared-read obligation
```

ClientConnection's explicit root-close request or stored OwnershipSession fallback invalidates children and drains them before disconnect. A surviving proxy/queue owner retains only invalidated bookkeeping. Raw receive initializers consume input ownership on every outcome. ClientConnection(receiving:) uses the native connector's consume-on-failure contract. Native connection success followed by runtime initialization failure disconnects once.

The named connector preserves native environment/socket lookup semantics and rejects embedded NUL in a supplied name. Independent named-socket fixtures and a workstation KWin smoke test exercise that branch. The C socketpair fixtures exercise the descriptor connector separately.

Registry and sync constructors run under checked display access and immediately publish permanent dispatcher ownership. Native construction and record publication share the display lease. Queue-specific sync uses a temporary proxy wrapper, assigns its queue, constructs the child, and destroys the wrapper. It never temporarily reassigns the shared display proxy. The child depends on both display and queue; queue close therefore retires assigned tracked proxies first.

## Prepared-read transaction

One DisplayStorage tracks whether a native preparation is active. Both queue variants use the same prepareRead implementation. Nested prepare and dispatch while prepared are rejected. Recursive dispatch and read preparation from a dispatch callback are rejected separately. Callback request construction and nonblocking flush remain permitted under the native frame.

ClientConnection.readAndDispatchPending combines default-queue preparation, one read, and pending dispatch under the same checked native frame. It returns the native dispatched-event count and may block in read without established readiness. Pending default or managed-queue events still reject another preparation. A close notification after read is checked before dispatch, and physical disconnect remains deferred until the combined frame exits. The separate prepared-read and dispatch methods remain available when a caller needs explicit poll, cancellation, or queue selection.

The borrowing closure receives a noncopyable ClientReadReservation. Its private state permits one read or cancel. read marks the reservation consumed before calling native read_events, including on error. cancel is idempotent. Scope exit always cancels an unresolved preparation before the enclosing frame can disconnect the display. Root closure observed before read causes cancellation and closedSession rather than a new native read. No await, migration, or uncoordinated foreign reader is supported in this initial facade.

Read can block if called without readiness; the low-level reservation API preserves this native behavior. dispatchOnce provides a synchronous poll transaction instead:

1. Reject an already canceled signal and dispatch pending default-queue events.
2. Prepare exactly one read and flush pending requests.
3. Poll the borrowed transport and separately owned wake eventfd. Flush EAGAIN requests writable readiness; EINTR preserves the original monotonic timeout deadline.
4. On timeout, cancellation, or wait failure, cancel preparation. On readability, read consumes preparation even on native error.
5. Dispatch the queued events after the read scope resolves.

Native dispatch counts include internal display-queue work such as delete_id. They are not user-handler invocation counts. Native errno is preserved; structured protocol-error snapshots and advanced low-level timeout/single-event variants remain unmapped.

## Cancellation wake lifetime

ReadCancellation is a checked Sendable class containing only RuntimeMutex-protected descriptor and flag values. It holds no connection, context, proxy, or continuation. The descriptor is created atomically with NONBLOCK and CLOEXEC, signaled once, never consumed by a waiter, and closed only in final deinit. Each producer and poll scope retains the signal through its native syscall, preventing a late write to a reused number. Cancellation never closes the display's borrowed transport descriptor.

This synchronous implementation has no published Swift continuation, so it does not claim to implement the asynchronous waiter arbiter in M17. Cancellation before preparation and concurrent cancellation are tested; asynchronous bounded event queues remain future work. Arbitrary user retention of a cancellation signal intentionally keeps its independent wake resource alive.

## Server ownership and native cascades

ServerDisplay owns the display and event-loop invocation frame. ServerClient and ServerResource have ordinary cleanup records plus C-allocated destroy-watch nodes. A watch owns copied identity and only a weak runtime link; notification therefore still works after the last Swift handle cell disappears. Native signal traversal unlinks the watch before entering Swift. The authoritative record retains the watch until complete native-frame retirement, and retirement frees it even when an invalidated owner survives.

The [libwayland 1.26.0 server implementation](https://raw.githubusercontent.com/wayland-mirror/wayland/1.26.0/src/wayland-server.c) emits client destruction before destroying resources. NativeDestructionObserver therefore supports a narrowly defined server-client cascade: it validates that every tracked descendant below the client root is a serverResource, consumes each still-owned obligation, and invalidates all references before native resource cleanup continues. Child notifications are idempotent. A different dependent kind rejects the operation before any state changes. Unknown native cascades remain unsupported.

Runtime-initiated shutdown instead closes resource leaves first, then clients, then the display. Destruction callbacks observe runtimeReleasing and cannot claim the native release again. Watch retirement occurs after the outer native frame. Resource references never expose a native pointer or a live resource to a destroy handler.

wl_client_create leaves its input socket with the caller on native failure. The consuming server factory closes it on that failure and destroys a newly created client if record publication fails. This differs from the client display connector. Version/interface metadata checks precede resource creation; raw immutable interface adoption remains explicitly unsafe and its storage must outlive native consumers.

## One-shot idle sources

ServerIdleSource separates callback execution from native source removal. The enclosing event-loop dispatch frame keeps context reachable. Callback entry validates the live record before optional user code. A throwing handler records failure without unwinding through C. Before returning, the callback consumes the source obligation as a proven native one-shot completion; native dispatch performs removal afterwards. Self-close and root close only invalidate while that frame remains active, so no second source remove occurs.

Canceling before execution uses the ordinary runtime cleanup action to remove the source. The tests distinguish runtime removal from native one-shot completion in the ledger. FD/timer/signal sources, globals/offers, filters, protocol loggers, and mutation-safe iteration require their own native adapters and remain incomplete.

## Verification and remaining gates

The combined suite has 68 Swift Testing tests, including C-server registry/sync/queue interoperability, an independent C client's sync request, native client/resource cascades, idle self-close, idle throw, recursive dispatch rejection, socket publication failure, prepared-read exception/fallback/close paths, and concurrent poll cancellation. Permanent proxy tests additionally include 10,000 real native lifecycles and canceled descriptor/constructor events.

The client compiler harness accepts scoped cancellation and rejects copied/escaped read tokens and Sendable connection capture in debug and release. Runtime compiler checks cover proxy owner copying and checked Sendable cancellation signals. The generator's 11 adversarial-input and generation tests and native scanner equivalence checks are separate from the Swift suite.

Named compositor connection, live desktop/compositor integration, truly concurrent foreign native readers, flush-EAGAIN and EINTR fault injection, all allocation sites, exhaustive per-opcode behavioral acceptance, and the full API inventory remain open. aarch64 remains deferred. See <doc:ImplementationProgress> for phase status and <doc:OwnershipRuntime> for reproduction commands.

## Complexity and bounded behavior

Checked native access and cancellation flag observations use constant-time bookkeeping. Proxy installation adds one record plus its declared dependency edges. Event snapshots cost O(argument count + copied bytes) and allocate owned payload storage; they are not the generated allocation-free scalar path. Dispatch returns native work counts and can invoke any number of queued callbacks.

A server-client cascade visits its tracked resource subtree in O(vertices + edges) time and O(vertices) temporary storage. Client roots cannot contain another client record in the native cascade. Root shutdown and dependency propagation are proportional to retained records/edges. Records are bounded by the configured session capacity; complete event/byte/descriptor quotas remain an M19 gate.

A manually invoked read can block until native readiness. dispatchOnce preserves a monotonic poll deadline, except that scheduling delay and native call execution can extend observed wall-clock completion. Callbacks that never return and fatal allocation/process failures remain outside shutdown liveness guarantees.

## Named connections and copied protocol errors

ClientConnection(name:) preserves native absolute-path and environment-based socket lookup. The named-path fixture binds a real UNIX listening socket and connects through an absolute path without changing the process environment. ClientConnection.protocolError copies interface name, object ID, and code only when the native sticky display error is EPROTO; transport failures return no protocol snapshot. The copied Sendable snapshot remains valid after root shutdown. Queries require a live display lease and never expose wl_interface pointers.

Scripts/verify-wait-faults.py compiles the actual production C wait loop with isolated syscall substitutions. Eight scenarios cover flush EINTR/EAGAIN, poll EINTR and deadline expiry, writable retry, timeout, cancellation priority, transport failure, and invalid native/wake descriptors. Address/undefined sanitizer instrumentation remains enabled. These deterministic loop tests supplement complete prepared-read/cancellation integration tests rather than claiming a real peer reproduces each syscall errno.

## Additional event sources

FD and timer sources use distinct owning/reference types so operations cannot be applied to the wrong native source kind. Source callback storage is retained by its cleanup record until complete native-frame retirement. Native callback return 0/1 is represented explicitly as done/recheck. User exceptions are copied into diagnostics and return done without unwinding across C. Source removal and root shutdown share one authoritative obligation.

FD registration duplicates the supplied borrowed descriptor into the display's runtime before native source installation. The source depends on this duplicate; the caller retains the original descriptor independently. Closing the source or display removes the native source before closing the duplicate. The callback exposes copied readiness bits. Its reference provides scoped descriptor interoperation while holding both source and FD leases. Timer update accepts nonnegative milliseconds; zero disarms according to the native contract. Explicit check uses the native recheck mechanism.

Signal registration changes the calling thread's signal mask in libwayland and removal does not restore the previous mask. The adapter therefore remains explicitly unsafe: the caller owns process/thread signal policy, blocks relevant signals on every required thread, and excludes incompatible foreign handlers. Swift callbacks run only from ordinary native event-loop dispatch, never asynchronous POSIX signal context. A non-Sendable token is not presented as proof of signal-mask affinity.

Native contracts are pinned to [libwayland 1.26.0 event-loop.c](https://raw.githubusercontent.com/wayland-mirror/wayland/1.26.0/src/event-loop.c).

## Global publication and root-managed clients

A published global owns one native wl_global allocation and callback context until deferred destruction. Removing it and destroying it are different transitions. Removal is idempotent in the wrapper because native wl_global_remove aborts on a repeated call. The native withdrawn callback may run synchronously during removal or later after the final registry offer disappears. Context and metadata remain alive through the full enclosing native call.

A global bind carries a noncopyable pending constructor. It either publishes the requested typed resource or rejects the client. Display-accepted clients that have no application owner are registered under root authority before any typed resources are published. Surrendering a child owner to root authority leaves its authoritative record live; root closure or native client destruction still consumes that obligation. A copied client reference does not acquire native destruction authority. Existing explicit ServerClient owners retain their original close authority.

Global filters receive only copied process credentials and interface/version metadata. No borrowed raw pointer escapes, and filter snapshots do not call wl_global_get_name because that query would recursively invoke the filter. Replacing a library-managed filter detaches the old registration logically; its later cleanup cannot clear the replacement. Clearing the current native filter precedes context retirement. Exceptions fail closed. Foreign replacement of library-managed userdata or callbacks remains an unsafe contract violation.

Named server sockets are internal display-owned native allocations and are removed by display destruction. An externally prepared listening descriptor can instead enter an explicitly unsafe consuming registration that returns a removable socket owner; native failure and record-publication failure each consume the descriptor exactly once. The caller must prove CLOEXEC, bind/listen, and path-lock policy before that raw handoff. Native run/terminate operations remain serialized by complete display frames and prohibit recursive dispatch; termination is synchronous domain access rather than a thread-safe wake primitive.

Server client/resource iteration returns owned metadata snapshots. It completes native traversal before returning user-visible values and does not expose intrusive list links or live mutable iterator borrows. Resource snapshots include native-reserved objects without claiming destruction authority for them. Typed object lookup returns only resources already tracked by that client's registry.

Protocol logger callbacks copy resource/message metadata and initialized arguments while native closure storage is live. Descriptor arguments are observation markers, never owned FD handoffs. Request new_id is a copied numeric ID; event new_id becomes a copied resource ID. Logger cancellation defers native list removal until the full surrounding native invocation retires because libwayland traverses the logger list with a non-safe iterator. Exceptions are stored and cannot unwind through C. Logger callbacks must avoid uncontrolled recursive logging through request/event emission.

Native destroy handlers receive copied credential/resource snapshots only after bookkeeping invalidation. The watch retains storage through complete native-frame retirement even after all checked cells disappear. User handlers cannot throw across C and cannot recover native access from the snapshot. Retirement clears handler captures as well as typed context so an invalidated owner retained for diagnostics does not retain callback closures indefinitely.


## Cross-queue retention policy

The safe serialized read coordinator rejects another socket read while any other live managed queue contains pending native events. Native prepare-read checks only its selected queue, so repeated reads through an empty queue could otherwise grow an undispatched queue outside the decoded-event ledger. Preflight uses balanced prepare/cancel probes and never dispatches a user callback. Default-only operation adds no extra native probe. Explicitly dispatch the pending queue before retrying. Queue readiness entries contain raw pointers and copied-identity weak-control observers and retire with authoritative queue cleanup. The pending-managed-queue regression verifies that an empty default queue cannot bypass this policy. Independent raw readers and queue reassignment remain unsafe integration responsibilities.
