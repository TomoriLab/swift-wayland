# Dispatch and concurrency

Serialize mutable native state while preserving libwayland queue and read semantics.

## Execution domains

A connection has one designated read coordinator and one serialized dispatch domain per managed queue. The safe initial implementation supports one dispatch domain for a connection. Complete compatibility mapping still exposes multiple queues and low-level read coordination through explicit advanced contracts. A future safe multithreaded facade must preserve a single shared read coordinator and independently serialized callbacks per queue; it must not invent an independent transport for each queue.

An actor alone is insufficient: an actor can reenter at suspension, and an actor does not promise a fixed OS thread. The synchronous native domain executes without suspension. Its logical ownership extends across native calls and poll/read transactions. A short-lived bookkeeping mutex protects state but is released before invoking C callbacks, blocking poll, or user code. A separate logical dispatch claim prevents another thread from entering while that mutex is released; reentrant permitted requests use the current domain token. Close and cancellation only enqueue/defer work until the outer native frame is quiescent. An optional async coordinator submits owned commands and resumes awaiters after native operations complete. Thread-affine integrations require a dedicated thread or a verified thread-affine executor, not MainActor as a substitute.

Native callbacks execute synchronously on the dispatching domain. They never call an actor-isolated method directly from arbitrary C execution. Async callbacks receive owned snapshots only. If async delivery is enabled, the coordinator maintains explicit capacity limits and ordering. Silent dropping of protocol events is forbidden; capacity exhaustion produces backpressure or a documented terminal error. Coalescing is permitted only for an event family with explicitly defined equivalent semantics.

## Client read transaction

The implementation must conform to libwayland's documented prepared-read protocol. Dispatching pending events and preparing a read are distinct operations; a readable fd is not evidence that the desired queue has no pending events. [Wayland client API](https://wayland.freedesktop.org/docs/html/apb.html).

The following is algorithmic pseudocode, not compiled Swift:

```text
enter connection domain
reject recursive dispatch and an existing reservation owned by this coordinator
repeat:
    dispatch pending events for the selected queue
    if a callback closed the connection: return closed
    if prepare_read_queue succeeds: create reservation; break
    if documented pending-events condition: repeat
    otherwise: snapshot error; return failure
flush buffered outgoing data
if flush would block: include write readiness in the poll interests
if flush fails fatally: cancel reservation; enter failed state
wait for read readiness, write readiness, shutdown notification, or deadline
if readable and still allowed to read:
    consume reservation through read_events
else:
    cancel reservation
if writable: retry flush without a busy loop
leave prepared-read state before dispatching callbacks again
```

Every successful prepare must be paired with a read or cancel on timeout, interruption, task cancellation, poll error, shutdown, and ordinary return. A read_events call consumes the reservation even when it reports a native error; confirm exact error semantics against the version-pinned implementation. Retry EINTR only while the reservation remains valid and the deadline permits it. EAGAIN during flush is backpressure, not an immediate connection failure. Transport failure and protocol error produce immutable error snapshots before teardown invalidates native query storage.

The runtime never mixes a prepared read with a convenience dispatch/roundtrip call that can read independently. A ReadReservation token prevents this through domain state and its terminal action. Existing low-level timeout and single-pending-event APIs remain separately mapped; they are not all reimplemented using a full dispatch loop with different observable behavior.

## Queue reassignment and wrappers

Queue changes affect callback affinity and object association. Set queue only under the connection coordination rule and document how already queued events behave in the pinned native version. Use proxy wrappers for queue-specific construction where required rather than temporarily mutating a shared object's queue. Wrapper destruction is distinct from destruction of the underlying proxy. A queue cannot be safely destroyed while its assignment or callback obligations remain unresolved.

## Cancellation and shutdown

Task cancellation enqueues a domain command and wakes the native poll through an owned wake mechanism. The wake descriptor has its own ledger entry and stays open until the coordinator has left poll and all producers have surrendered their wake leases. Otherwise fd reuse can redirect a late wake write into an unrelated resource. Cancellation cannot close the borrowed display fd to interrupt a read. Resolve a prepared read first, remove readiness registrations, settle waiters through one completion arbiter, stop user delivery, wait for the outer native call to return, release sources and native children in dependency order, then close transport ownership and the wake mechanism. A callback-triggered close cannot disconnect the display while dispatch/run still has that pointer on its C stack.

An async cancellation handler may run concurrently. It changes only synchronized coordinator state and wakes the domain; it does not mutate libwayland objects directly. Bounded shutdown cleanup may use Swift 6.4 cancellation shields after a compile probe. It must never shield an unbounded wait for an unresponsive peer.

## Server execution

Expose event-loop fd, timer, POSIX signal, idle, source check, explicit dispatch, and display run/terminate semantics. FDSource and TimerSource have different types so fd_update cannot be applied to a timer. Source callbacks preserve the native return-value contract. Idle callbacks are one-shot according to native behavior; their tokens invalidate without a second remove.

Destroy listeners may run during client/resource/display cleanup. Resource references invalidate before user destroy handlers execute, and user destroy handlers receive copied identity/reason snapshots rather than a live resource borrow. Global filters and protocol loggers have scoped borrowed inputs. Resource iterators must define mutation rules for removal during traversal and use the native safe mechanism where available; snapshot iteration may allocate and must be documented as different from live native traversal.

Process-global logging handlers are serialized separately from display domains. Installing a handler returns a scoped registration, with an explicit policy for competing installations. Do not restore a prior handler through a nonexistent native getter; the bridge must either coordinate all installations it owns or state that foreign replacement invalidates the restoration contract.

## Waiter and delivery transactions

Register a waiter and its cancellation token as a single state-machine transaction. Check pending cancellation before publication and again through the same completion arbiter, so cancellation between those steps is not lost. Readiness, deadline, connection failure, and cancellation compete for one terminal result; the winner removes native wait registrations and releases the continuation. No C callback may directly resume a continuation while holding a mutation lock that resumed work could reacquire.

Owned async events have separate obligations for descriptors, event-created proxies, and copied payload bytes. Queue admission transfers ownership only after it succeeds. Rejection, consumer termination, or queue shutdown destroys the event's obligations exactly once. A copyable object reference in a queued event can become invalid before consumption; receiving an event does not promise the referenced native object is still usable. Either pin through a supported native mechanism or document the checked-reference behavior.

Set explicit maximum queued event count, total payload bytes, received descriptors, and constructor objects. Bound pending requests and metadata as well. Prefer synchronous typed delivery for protocol-critical traffic; never stop polling indefinitely in a way that strands a read reservation or deadlocks a peer waiting for a response. Quota exhaustion follows a documented terminal cleanup path when lossless backpressure is impossible.

## Thread-sensitive operations and process hooks

Initial safe prepared-read transactions are synchronous and must be consumed/canceled through their originating coordinator without await or migration. The native library's multireader behavior remains an advanced compatibility contract; the safe facade must not mix coordinated reads with Mesa/EGL or foreign readers unless an integration contract proves compatibility. Native refcounted SHM operations are not assumed thread-safe merely because the wrapper has ARC.

Use a process-lifetime C trampoline for global logging. Dynamic Swift handler storage is synchronized and retired only after all concurrent invocations finish. Default to a single library-managed installation and no unsupported automatic restoration of a foreign handler. Nested logging must have a nonallocating recursion policy. Do not invoke user Swift handlers from async POSIX signal context; only native event-loop signal callbacks dispatched in ordinary execution can enter Swift. Thread-local SHM begin/end access cannot migrate through actor suspension.

The current synchronous client and server slices implement the guarded paths described in <doc:ClientAndServer>. Async coordination, advanced sources, and full native coverage remain open in <doc:ImplementationProgress>.
