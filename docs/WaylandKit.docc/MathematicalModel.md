# Mathematical model

Express memory and resource safety as invariants over a transition system.

## State space

A runtime state is S = (O, R, C, F, Q, D, N, B, E), where O is the set of object cells and authoritative cleanup records, R is the set of registrations, C is callback activity, F is descriptor ownership, Q is read/dispatch state, D is execution-domain state, N is enclosing native-frame activity, B is backing-storage borrow state, and E is dependency edges and pending event obligations. Each object has identity (connection, nativeID, generation), a native pointer or null, a state, a parent, and one destruction authority where ownership exists.

Object states are constructing, live, closing, and dead. Publication only occurs after successful initialization. An operation is permitted only if its object and required ancestors are live, its generation matches, and it executes in the object's domain. The transition from live to closing is the linearization point for destruction: no new access leases may start afterwards.

This model is a design-level specification. It is not a machine-checked proof of Swift, C, the allocator, or the operating system.

## Invariants and obligations

| ID | Predicate | Enforcement | Counterexample test |
|---|---|---|---|
| M1: unique destruction | destructionAuthority(o) is at most one | Noncopyable owner plus terminal cell transition | Duplicate adoption and close/destroy race |
| M2: valid access | newAccess(o) implies live(o), matching generation/session, live dependencies, and a held lease; existing borrows retain backing until their end | Validate and acquire within one execution guard | Parent closes while a child reference survives |
| M3: borrow containment | lifetime(view) is a subset of lifetime(access lease) | Nonescapable type or synchronous closure | Return, store, capture, or await with callback bytes |
| M4: bounds | offset ≥ 0, length ≥ 0, offset + length ≤ initializedExtent | Checked arithmetic and bounds checks | Overflow, negative dimensions, truncated arrays |
| M5: callback balance | retainedContexts − releasedContexts = provisional + nativeReachable + retiredButLeased contexts | Separate delivery and attachment state machines | Self-removal, failed attachment, and proxy subscription cancellation |
| M6: read balance | successfulPrepare = completedRead + cancelledRead + activeReservations | Noncopyable read reservation | Timeout, cancellation, error, early return |
| M7: fd balance | acquiredFDs = closedFDs + transferredFDs + liveOwnedFDs | Descriptor owners and transfer state | Decode failure after receiving fd |
| M8: SHM balance | beginAccess = endAccess + activeAccess | Scoped access token | Throw during pixel processing |
| M9: isolation | overlapping mutations of a native domain are serialized | Domain guard and non-Sendable handles | Concurrent close and dispatch |
| M10: no premature free | runtimeFree(o) implies no callback, native-frame, backing-borrow, or dependent-consumer lease requiring its storage | Outermost-frame cleanup and dependency ordering | Close display inside callback while C dispatch resumes |
| M11: identity separation | equal IDs on different connections do not alias | Composite key and generation | Reused pointer and ID after disconnect |
| M12: protocol admissibility | opcode exists, since ≤ negotiatedVersion, arguments satisfy schema | Generated metadata validation | New opcode sent to older object |
| M13: complete cleanup inventory | every live native obligation has exactly one cleanup record independent of Swift cell reachability | Root-owned acyclic records | Last child cell disappears before parent close |
| M14: storage exclusivity | writeLease(storage) excludes all overlapping library-managed read/write leases | Backing-storage identity and borrow guards | Resize wl_array from its borrowed-view closure |
| M15: native reachability | nativeMayCallback(context) implies context, trampoline, metadata, and transitive backing remain valid | Physical attachment state distinct from user delivery | Cancel subscription then receive fd event |
| M16: incoming balance | received obligations = released + transferred + pendingDecodeOrDelivery | Decode cleanup scopes | Throw after first of several fd arguments |
| M17: wait completion | every published waiter has exactly one terminal result and no retained continuation afterwards | Pending/completing/finished arbiter | Cancellation versus readiness before waiter publication |
| M18: execution identity | thread-bound native sessions begin and end on the same proven OS thread | Scoped synchronous thread guard | Await during SHM access |
| M19: bounded retention | pending bytes, descriptors, events, dynamic metadata, and cleanup records stay within declared limits | Quotas and native configuration | Peer floods constructors or large arrays |

Generation counters must not wrap into a still-reachable identity. Use a checked sufficiently wide counter and fail creation before wrap. Native serials are a different type with protocol-defined wrapping semantics; ordinary unsigned ordering does not establish serial chronology.

## Conservation and leak freedom

For each owned native resource class k:

```text
A_k(t) = X_k(t) + T_k(t) + L_k(t)
```

A is successful acquisitions, X is terminal releases, T is explicit transfers out of the runtime, and L is live obligations. A native ref increment counts as an acquisition even if its pointer already exists. Failed acquisitions do not count, but any partially allocated subresources have their own obligations.

At quiescent shutdown, L_k = 0 for connection-scoped resources. No application-visible handle may still reference freed native memory, although invalidated Swift cells may remain until the application releases them. Process-lifetime immutable metadata and external caches are counted separately and must plateau after warm-up. Bounded metadata is not permission for an ever-growing registry.

For the Swift ownership graph, library-owned strong edges must not form a cycle without an explicit bounded teardown root. The recommended graph is owner → cell → parentControl and parentControl → weak child cell. Cleanup records → callbackContext → user handler must not add an owner back-edge. Cleanup records and contexts hold only weak/non-owning links to parent bookkeeping; active outer-frame leases temporarily retain it. User-supplied cycles are outside the unconditional guarantee and require documented weak capture or explicit cancellation.

Leak freedom also requires liveness: a closing object with finite callbacks must eventually reach dead, and every canceled wait must eventually release its reservation. No destructor may enqueue cleanup onto a queue that has already terminated. Allocation balance alone cannot prove that deferred work will execute.

## State transitions

| Entity | Start | Trigger | Result |
|---|---|---|---|
| Object | constructing | Successful native construction and registration | live |
| Object | constructing | Any initialization failure | dead after rollback |
| Object | live | Explicit close, parent shutdown, native destroy notification | closing; reject new leases |
| Object | closing | Last relevant native-frame, callback, borrow, and dependency lease exits | Native release if still owned; dead |
| Native attachment | provisional | Native attachment succeeds | nativeReachable |
| User delivery | enabled | Subscription cancellation | disabled; native attachment may remain |
| Native attachment | nativeReachable | Proven detach, native destroy, or one-shot completion | retired |
| Native attachment | retired | No enclosing native frame, callback, or other retained consumer | released |
| Read reservation | absent | Prepare succeeds | prepared |
| Read reservation | prepared | Read consumes reservation | consumed |
| Read reservation | prepared | Cancel or fallback cleanup | cancelled |
| Connection | open | Fatal transport/protocol error | failed; preserve error snapshot |
| Connection | failed | Explicit/fallback shutdown | closed |

The actual native destructor may itself deliver callbacks. The implementation records destruction authority as consumed before calling it and accepts reentrant notifications as invalidation, never as another destruction obligation.

## Hoare contracts

```text
{ live(o) ∧ domainHeld(o) ∧ schemaValid(arguments) }
    send(o, arguments)
{ live(o) ∨ closing(o) ∨ dead(o) ∨ failed(connection(o)); no escaped borrow; balanced temporary storage }

{ prepared(reservation) }
    readOrCancel(reservation)
{ consumed(reservation) XOR cancelled(reservation) }

{ live(parent) ∧ finiteActiveCallbacks(parent) }
    requestClose(parent)
{ closing(parent) ∨ dead(parent); allNewOperationsRejected }

{ outsideNativeFrames(parent) ∧ finiteActiveCallbacks(parent) ∧ closeRequested(parent) }
    drainClose(parent)
{ dead(parent) ∧ allChildrenInvalid ∧ noNativeOwnedObligations(parent) }
```

The final contract assumes user callbacks terminate and do not invoke prohibited nested dispatch. It cannot be satisfied if arbitrary callbacks never return. Such preconditions must be stated rather than hidden in a claim of unconditional cleanup.

## Proof and model-based testing plan

For each public operation, document preconditions, allowed transitions, rollback, and which invariants it preserves. Generate finite traces containing construction, publication failure, reference copy, read preparation, callbacks, self-removal, external destruction, ID reuse, cancellation, and parent close. After each transition, assert M1–M19 and conservation equations.

Use a small reference state machine in tests; exhaustively enumerate short traces for bounded object counts and seed randomized longer traces. Record the seed and minimized failing trace. Formal specification tools may be added later if state-space analysis demonstrates value; the design does not claim a completed TLA+, Alloy, or theorem-prover verification. Native integration tests are required because a model can faithfully implement an incorrect assumption about C ownership.

## Native destruction and progress assumptions

A runtime lease cannot prevent a foreign/native owner from freeing an allocation. For externally destroyed resources, the safe facade either uses a supported native ref/pin, excludes the invalidating operation while views are active, or returns copied data. Destroy notifications invalidate checked references immediately and carry only snapshots to user handlers. They do not resurrect or extend native allocation lifetime. Arbitrary foreign destruction without coordination remains unsafe.

Terminal-state checks, lease acquisition, and transition publication are one serialized operation; atomically updating a state flag alone does not protect associated pointer storage. A callback retains the enclosing operation's lifetime but cannot force an external native owner to honor it. Each destruction site needs a version-pinned proof of who controls the free and where the last native use occurs.

Leak freedom assumes normal process execution, finite callbacks, fair coordinator progress, and obeyed unsafe preconditions. Root-owner destruction always requests closure independently of child ARC reachability. A blocked native poll must have a nonallocating wake path. Model cancellation-before-publication as well as cancellation-after-registration; a continuation must never be lost between these steps.
