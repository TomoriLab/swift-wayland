# Client and server implementation slices

Use one ownership runtime for client read coordination and server native-destruction observation.

## Implemented modules and release boundary

WaylandClient, WaylandServer, and WaylandProtocol are package-access implementation targets on Swift 6.4.2 and x86_64 Linux. CWaylandClient and CWaylandServer import the installed native headers and contain small adapters. These targets add the already planned libwayland dependencies, not a third-party Swift package or XML runtime dependency. Their existence is not a completed application API or complete native coverage claim.

The permanent dispatcher adapter is documented in <doc:ProxyDispatcher>. Client events currently expose owned observation snapshots. Descriptor and constructor fields are markers; their native obligations are discharged by the trampoline. Ownership-taking typed constructor/event decoders remain a generator gate. Object IDs in snapshots never authorize native access.

## Client ownership graph

```text
ClientConnection -> root session + display record
queue record -> display dependency
permanent proxy record -> display and optional queue dependencies
native invocation -> temporary frame over the complete synchronous call
read reservation -> temporary display lease + one prepared-read obligation
```

ClientConnection's explicit root-close request or stored OwnershipSession fallback invalidates children and drains them before disconnect. A surviving proxy/queue owner retains only invalidated bookkeeping. Raw receive initializers consume input ownership on every outcome. ClientConnection(receiving:) uses the native connector's consume-on-failure contract. Native connection success followed by runtime initialization failure disconnects once.

The named connector preserves native environment/socket lookup semantics and rejects embedded NUL in a supplied name. That branch is implemented but has not been exercised against an external named compositor. The C socketpair fixture tests the descriptor connector instead.

Registry and sync constructors run under checked display access and immediately publish permanent dispatcher ownership. Native construction and record publication share the display lease. Queue-specific sync uses a temporary proxy wrapper, assigns its queue, constructs the child, and destroys the wrapper. It never temporarily reassigns the shared display proxy. The child depends on both display and queue; queue close therefore retires assigned tracked proxies first.

## Prepared-read transaction

One DisplayStorage tracks whether a native preparation is active. Both queue variants use the same prepareRead implementation. Nested prepare and dispatch while prepared are rejected. Recursive dispatch and read preparation from a dispatch callback are rejected separately. Callback request construction and nonblocking flush remain permitted under the native frame.

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

Named compositor connection, live desktop/compositor integration, truly concurrent foreign native readers, flush-EAGAIN and EINTR fault injection, all allocation sites, typed constructor ownership delivery, and the full API inventory remain open. aarch64 remains deferred. See <doc:ImplementationProgress> for phase status and <doc:OwnershipRuntime> for reproduction commands.

## Complexity and bounded behavior

Checked native access and cancellation flag observations use constant-time bookkeeping. Proxy installation adds one record plus its declared dependency edges. Event snapshots cost O(argument count + copied bytes) and allocate owned payload storage; they are not the generated allocation-free scalar path. Dispatch returns native work counts and can invoke any number of queued callbacks.

A server-client cascade visits its tracked resource subtree in O(vertices + edges) time and O(vertices) temporary storage. Client roots cannot contain another client record in the native cascade. Root shutdown and dependency propagation are proportional to retained records/edges. Records are bounded by the configured session capacity; complete event/byte/descriptor quotas remain an M19 gate.

A manually invoked read can block until native readiness. dispatchOnce preserves a monotonic poll deadline, except that scheduling delay and native call execution can extend observed wall-clock completion. Callbacks that never return and fatal allocation/process failures remain outside shutdown liveness guarantees.
