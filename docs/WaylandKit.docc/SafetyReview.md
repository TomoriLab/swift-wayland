# Memory-safety design review

Record identified ownership gaps, the required corrections, and evidence still needed before implementation.

## Review boundary

Reviewed on 2026-11-13 against the conceptual design and libwayland 1.26.0 public headers plus version-tagged native source. Changes in this review are documentation and repository policy only. No Swift/C implementation, executable test harness, dependency, or package manifest is added. Correcting a specification does not establish that an implementation is memory-safe.

The review rejects three earlier simplifying assumptions: that all registrations can be physically detached when a subscription is canceled; that the end of a Swift callback is necessarily the end of native access; and that weak child cells constitute a complete cleanup inventory. The normative rules now live in <doc:OwnershipAndFFI>, <doc:MathematicalModel>, and <doc:DispatchAndConcurrency>.

## Findings and required validation

| ID | Gap and failure scenario | Required correction | Invariants | Future counterexample validation |
|---|---|---|---|---|
| SR1 | Weak registry loses an obligation when the last Swift handle disappears | Strong authoritative cleanup records independent of weak cell indexes; parent authority token requests close | M1, M13 | Drop child handles, retain references, then drop parent owner; all native counts return to zero |
| SR2 | Subscription cancel frees userdata still stored by a client proxy | Stable lifetime-long dispatcher; delivery cancellation does not detach | M5, M15 | Cancel, then dispatch fd and constructor events without user delivery |
| SR3 | Last callback returns while libwayland dispatch still uses display/loop/source | Track outer native frames and defer physical teardown past their return | M9, M10 | Close display inside callback and continue native dispatch safely |
| SR4 | Idle callback cancels a source that native code removes again afterwards | Executing one-shot state; no second native remove | M1, M10, M15 | Self-cancel and parent-close inside idle callback |
| SR5 | Native destroy notification is mistaken for runtime-controlled deferred free | Invalidate immediately, consume native authority, provide only copied destroy snapshots | M1, M2, M10 | Native resource destroy followed by retained reference access |
| SR6 | Nonescaping closure returns a copyable pointer-backed view | Compiler-checked nonescapable dependency or operation-only checked view; owned copy fallback | M3 | Return/store/capture/await attempts must fail or remain safe |
| SR7 | Callback mutates/frees storage while a span into it remains in scope | Backing-storage borrow guards and transitive dependency leases | M4, M10, M14 | Resize array or close pool/window prerequisite inside borrow |
| SR8 | C call retains temporary strings, tags, vtables, or type arrays | Transitive pinned metadata ownership and arenas without ARC cycles | M3, M15 | Delayed callback after creation scopes and external descriptor release |
| SR9 | Dropped or failed event delivery leaks fd/new_id obligations | Decode scope and exactly-once transfer/cleanup on all exits | M7, M16 | Multiple fds with partial decode failure, missing handler, full queue |
| SR10 | Domain mutex held over user callback or native poll deadlocks shutdown | Logical domain claim separate from bookkeeping mutex; wake/rendezvous | M9, M10, M17 | Reentrant request and close; concurrent cancellation while polling |
| SR11 | Thread migration or nested unrelated SHM pools violates native TLS access | Same-thread access token; no await; restrict nesting and retain native refs | M8, M18 | Cross-thread completion rejected; different-pool nesting rejected |
| SR12 | Peer-writable SHM is exposed as immutable Swift storage | Owned byte copy by default; explicit external-memory capability for zero-copy | M4, M14, M18 | Mutation/truncation during access without invalid typed values or stale spans |
| SR13 | Child reference keeps bookkeeping alive and unintentionally prevents parent close | Distinct parent owner authority; no reliance on control deinit | M1, M13 | Retain child after dropping parent; child rejects new operations |
| SR14 | fd number or wake endpoint is reused after premature close | Descriptor identity/lease, close-on-exec duplication, producer quiescence | M7, M17 | Late wake and cancellation after descriptor reuse |
| SR15 | Cancellation arrives before continuation publication | One registration/completion transaction with a pending-cancel state | M17 | Enumerate cancellation/readiness/timeout orderings |
| SR16 | Unbounded event or descriptor retention is treated as a leak-free design | Explicit quotas and bounded terminal cleanup | M16, M19 | Peer floods payloads, constructors, descriptors, and dynamic metadata |
| SR17 | Thread-affine cleanup relies on an executor that may be gone | Safe facade gated on live affine endpoint and fallback proof | M9, M10, M18 | Last release after coordinator shutdown |
| SR18 | Process log trampoline calls a released handler or reenters unsafely | Stable C trampoline, synchronized retirement, recursion policy | M5, M15 | Concurrent log and handler removal; nested log |

## Concrete native evidence

Client listener/dispatcher attachment stores callback pointers and userdata in the proxy; the inspected API has no general removal operation. Disconnect requires callers to destroy proxies and queues first. The design therefore retains bridge context through proxy teardown rather than subscription cancellation. [libwayland 1.26.0 client source](https://raw.githubusercontent.com/wayland-mirror/wayland/1.26.0/src/wayland-client.c).

Server client destruction emits destruction notifications and destroys resources as part of native cleanup. Swift logical leases cannot extend an allocation owned by that native path. Client creation consumes its fd on success and leaves ownership with the caller on failure. [libwayland 1.26.0 server source](https://raw.githubusercontent.com/wayland-mirror/wayland/1.26.0/src/wayland-server.c).

Idle dispatch invokes the callback and then removes the source; generic source removal also retires storage through the loop's destruction path. SHM begin/end uses per-thread pool/access state. These justify separate one-shot source state and same-thread SHM access rather than one generic cancel/destruct rule. [Event-loop source](https://raw.githubusercontent.com/wayland-mirror/wayland/1.26.0/src/event-loop.c), [SHM source](https://raw.githubusercontent.com/wayland-mirror/wayland/1.26.0/src/wayland-shm.c).

## Authority and shutdown contract

Each cleanup record has one terminal authority arbiter. Native ownership and a Swift authority token are not two independent destroyers: either path consumes the same record. Provisional construction records are included before C attachment, because callbacks may be synchronous. Records remain reachable until native detachment/destruction and every relevant frame have finished.

Safe root owners default to the following policy: dropping or explicitly closing the root requests logical closure immediately; existing scoped memory borrows retain only the storage they need until their end; checked references reject new operations; an outside-frame drain releases remaining obligations. Parent-control ARC lifetime protects bookkeeping only. It does not keep the connection open after root authority ends.

Physical cleanup runs in reverse dependency order and may need more than a parent tree. In particular, a client proxy can be a cursor-owned borrowed buffer rather than a runtime-owned proxy. Never add a local destroy obligation for it; destroy the theme at its dependency boundary. Foreign EGL/renderer objects that retain native surface pointers require a coordinated lifetime contract. Without it, raw handle escape remains unsafe and the wrapper cannot guarantee external consumers' safety.

A safe API must not admit a lifecycle for which fallback cleanup is known to violate thread affinity or require progress from an already stopped executor. Keep that API unavailable or unsafe until the proof obligation is resolved. Requiring callers to remember close is insufficient for a memory-safe RAII claim.

## Remaining evidence gates

The source audit establishes several native behavior constraints, not every possible success/failure contract. Before implementation, verify each ledger row against the pinned native build, including distribution patches, queue destruction/reassignment, global offers, resource listeners, SHM mapping and SIGBUS failures, fd transfer, native refcounts, and metadata retention. The 452 function rows remain a declaration inventory, not an ownership audit for each function.

Swift 6.4.2 compile-fail tests must demonstrate actual view lifetime and concurrency restrictions. Native integration and sanitizer tests must demonstrate quiescence, no stale access, and balanced resources. Model-derived tests must cover M1–M19 and SR1–SR18. The subsequent toolchain recheck successfully converted all nine conceptual DocC pages with warnings treated as errors. No claim of a machine-checked proof, zero leaks, compiled Swift examples, or visual documentation verification is made by this review.
