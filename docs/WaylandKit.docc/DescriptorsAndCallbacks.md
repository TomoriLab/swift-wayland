# Descriptor ownership and callback context lifetime

Manage descriptor transfer and detachable callback contexts through authoritative cleanup records.

## Implemented boundary

This package-access implementation targets Swift 6.4.2 on x86_64 Linux. It adds descriptor owners, received-event cleanup scopes, detachable callback contexts, and delivery cancellation to <doc:OwnershipRuntime>. It does not yet connect every libwayland event or constructor to these primitives. Nonremovable proxy dispatchers now use the separate <doc:ProxyDispatcher> adapter whose context follows the proxy lifetime; they cannot use a fabricated no-op detach action.

All native owners, borrowed references, subscriptions, and attachments remain non-Sendable. Only CallbackCancellation is Sendable: it stores synchronized cancellation bits and retains no context, native pointer, or session. The implementation adds no production dependency.

## Descriptor authority

| Operation | Success | Failure |
|---|---|---|
| OwnershipSession.adoptFileDescriptor | Publishes one descriptor cleanup record | Caller keeps the original ownership obligation |
| OwnershipSession.receiveFileDescriptor | Publishes one descriptor cleanup record | Closes the exclusively received descriptor once |
| ReceivedFileDescriptor.init(adopting:) | Takes exclusive incoming ownership before decoding | Invalid input creates no owner |
| ReceivedFileDescriptor.register(in:) | Moves the obligation into the session | Disarms the incoming scope before registration; the receiving factory closes on failure |
| BorrowedFileDescriptor.duplicate | Returns an independent session-owned CLOEXEC descriptor | Leaves the original owned; closes a duplicate if record publication fails |
| OwnedFileDescriptor.takeRawDescriptor | Consumes the owner and transfers its descriptor without closing | Consumed-owner fallback closes after outstanding borrows and native frames exit |
| OwnedFileDescriptor.close or fallback destruction | Invalidates references and retires through the shared record | Reports saved close errno after the physical attempt; never retries close |

Raw adoption and transfer are unsafe because an integer cannot prove exclusive native ownership. The caller must never adopt a borrowed descriptor or a number already owned by another runtime record. Descriptor flags are preserved on adoption. Duplication uses F_DUPFD_CLOEXEC rather than a separate flag-setting syscall, preserving atomic close-on-exec creation. See [F_DUPFD](https://man7.org/linux/man-pages/man2/F_DUPFD.2const.html).

A borrowed reference retains bookkeeping, not independent destruction authority. withUnsafeDescriptor validates the record and opens a synchronous native frame and borrow scope. Closing the root or owner during that scope immediately rejects new access but defers the syscall. Transfer is rejected while any raw borrow or dependent native consumer remains. The raw number must not escape the scope, be closed, or be sent to another task. An ordinary Int32 cannot encode that restriction, so raw access remains explicitly unsafe.

Physical close first disarms storage and records its sole attempt. Linux releases descriptor numbers early in close, including most error paths. Retrying can close an unrelated descriptor that reused the number. The runtime therefore records errno and never retries, including EINTR. Its test injects EBADF through a deliberate external-close contract violation; EINTR and storage writeback errors are not fault-injected. See [close](https://man7.org/linux/man-pages/man2/close.2.html).

A FileDescriptorCloseResult with deferred progress does not promise syscall success. BorrowedFileDescriptor.snapshot remains available for accounting after invalidation and reports the eventual close attempt and error. Borrowed native transport descriptors must never enter an owning receive scope.

## Received event cleanup

A trampoline must acquire ReceivedFileDescriptor ownership immediately after native handoff, before optional user delivery or decoding later fields. Every initialized field retains its own cleanup obligation. Ignored events, canceled subscriptions, unavailable domains, decode failure, and thrown handlers then release initialized receive scopes even if no session is usable.

The callback dispatcher itself does not know a protocol's payload ownership. It cannot close arbitrary integers automatically. The native adapter must keep incoming RAII values outside the optional delivery closure and move them into session ownership only when needed. No pointer to a stack-local receive scope may be retained by C.

## Three separate callback lifetimes

| Capability | Ownership | Terminal action |
|---|---|---|
| CallbackSubscription | Logical user delivery | Drop or cancel sets a flag; the native attachment stays alive |
| CallbackCancellation | Copyable Sendable signal | Idempotently stops future admission; an already admitted handler may finish |
| CallbackAttachment | Noncopyable physical attachment authority | Requests cleanup of the authoritative registration record |
| Cleanup record | Stable retained userdata and detach action | Detaches after outer native frames quiesce, then releases context and the retained userdata count |

At most one subscription is issued per attachment. Cancellation is permanent. Tokens can survive native teardown without retaining the context. The context remains retained even when the user subscription disappears. If the attachment authority disappears inside a native frame, the record still retains everything needed for later physical cleanup.

## Installation transaction

Installation runs inside a complete runtime native frame:

1. Initialize the context storage and cancellation gate.
2. Retain stable userdata with one explicit Unmanaged retain.
3. Reserve a registration cleanup record with its prerequisite handles. Failure releases the provisional retained count without calling native install.
4. Publish the weak checked cell before C can call synchronously.
5. Invoke install. Success supplies detach. Partial failure supplies rollback; nil rollback asserts that no native consumer retained userdata.
6. Store detach or rollback before propagating failure or observing reentrant root closure.
7. Publish attachment authority only while its record remains valid. Otherwise owner fallback and frame exit execute the registered cleanup.

The cleanup action cancels delivery first. It moves detach out of storage, invokes it without a bookkeeping lock, and keeps the context alive until detach returns. It then releases the context and explicit userdata retain. A callback occurring synchronously during detach observes cancellation. Dependencies ensure detach finishes before a prerequisite descriptor is closed.

Context and detach captures must not strongly retain their owning session or reference cell. User-created ARC cycles and independent external context mutation violate the unsafe adapter contract. The runtime does not claim to collect arbitrary cycles.

## Native entry and quiescence

CallbackAttachment.deliver converts handler errors into CallbackDeliveryResult.failed. No Swift error unwinds through a C ABI frame. The trampoline must map the result to the native protocol's error policy and must clean event payloads on every result.

The adapter must already enclose the complete native invocation in OwnershipSession.withNativeFrame. A callback entry without an existing frame is rejected. Protecting only the Swift callback cannot protect native instructions after the callback returns. Requesting root close inside a handler invalidates capabilities immediately but detaches and frees context only after the enclosing native call returns.

Recovering Unmanaged storage is necessarily unsafe: C must guarantee that userdata is alive before entry and that the generic context type matches. Detach must stop future entries and quiesce concurrent native callers before returning. Runtime serialization cannot rescue an entry that starts with an already freed pointer. Thread-affine teardown and native APIs without a matching quiescence operation remain unsupported. Cancellation from another thread is supported; arbitrary concurrent context access is not.

## Unsafe-site review ledger

| Boundary | Provenance, lifetime, and execution requirements | Cleanup and verification |
|---|---|---|
| FD adoption/receive | Caller owns an exclusive valid Linux descriptor; serialized record publication uses the fileDescriptor namespace | Success-only adoption versus consuming receive; M7/M16; capacity and shutdown tests |
| Raw FD borrow | Checked cell authorizes the scoped integer; storage borrow and outer native frame prevent close; no escape or concurrent raw use | defer balances borrow on throw; M3/M9; borrow-close and transfer-rejection tests |
| FD duplicate | Initialized C Int32 errno slot exists for the complete syscall; successful output has independent ownership | Failed publication closes the output; M7; 1,000 failures compared with native descriptor-table counts |
| FD transfer | Live leaf with no active borrow; recipient assumes native ownership before any later use | transferred record never invokes close; M1/M7/M13; number-reuse and dependent-consumer rejection tests |
| Stable callback pointer | Unmanaged retained heap object provides its own alignment; C returns the unchanged opaque pointer with the exact Context specialization | Provisional failure releases the retain; physical detach releases it once; M5/M10; weak-context, rollback, and stress tests |
| Native callback entry | Native detacher guarantees storage remains reachable before entry; complete outer native call already holds a frame | Handler errors become values; mandatory payload owners survive canceled delivery; M5/M9/M16; C callback fixture tests |
| Physical detach | Nonthrowing thread-compatible native action stops entry and completes native quiescence; context remains retained throughout action | Dependency-ordered cleanup runs outside mutexes; M5/M10/M13; reentrant detach and root-close tests |

## Accounting and liveness

The runtime ledger now records explicit transfers separately:

```text
acquisitions = runtimeReleases + nativeReleases + transfers + outstandingObligations
```

Transfer changes a live record to transferred, rejects further access, and retains its identifier until quiescent retirement. It discards the release action without executing close. The raw recipient now owns the obligation. A descriptor number reused by another native owner is never closed by the retired record.

Callback registration contributes one acquisition and one physical cleanup, irrespective of cancellation count or subscription lifetime. Finite native frames and terminating detach actions permit deferred records to drain. Fatal termination, callbacks that never return, native contract violations, and arbitrary reference cycles are outside this liveness claim. These mechanisms exercise portions of M3, M5, M7, M9, M10, M13, and M16; they do not prove complete protocol coverage.

## Validation evidence

The serialized descriptor/callback suite uses independent C descriptor-table inspection and a C callback slot. It tests acquisition versus receive failure, closed-session receive, failed duplicate publication, CLOEXEC duplication, borrowing and throwing exits, ownership transfer and number reuse, single-attempt EBADF reporting, subscription cancellation and drop, synchronous installation callbacks, partial rollback, root shutdown during installation and delivery, dependency teardown, and handler failure with owned incoming descriptors.

Stress cases include 10,000 descriptor lifecycles, 10,000 physical callback attachments, 1,000 failed duplicate publications with independent descriptor counts, and 500 concurrent cancellation signals. Weak context observations and C detach counts check release separately from runtime ledger totals. Compiler rejection probes verify noncopyable descriptor/receive/subscription authority and explicit unsafe raw access. See <doc:OwnershipRuntime> for exact commands and recorded build, sanitizer, compiler, and DocC results.

Native pthread allocation failure, true concurrent native callback/detach quiescence, Linux EINTR close injection, and asynchronous transport cancellation remain unverified or unimplemented. Nonremovable libwayland proxy dispatchers are implemented separately in <doc:ProxyDispatcher>. aarch64 remains deferred.
