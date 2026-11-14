# Design decision register

Status: proposed decisions for implementation review. Recorded 2026-11-13.

| ID | Decision | Reason | Alternative and cost |
|---|---|---|---|
| D1 | Swift 6.4.2, libwayland 1.26.0 initial baseline | Fixed feature and ABI boundary | Older versions multiply conditional code and test scope |
| D2 | Client umbrella with explicit server/cursor/EGL products | Avoid unnecessary linking and keep ownership domains distinct | Monolithic product is simpler to import but pulls unused dependencies |
| D3 | Noncopyable owner plus generation-checked reference cell | Handles both unique ownership and native external destruction | Raw pointer wrapper cannot detect stale aliases |
| D4 | Synchronous serialized core, optional owned async commands | C callbacks cannot safely suspend with borrowed memory | Actor-only core risks reentrancy and thread-affinity assumptions |
| D5 | Generated typed protocol layer and explicit unsafe compatibility | Complete mapping without claiming arbitrary C pointers are safe | Making every C operation appear safe hides caller obligations |
| D6 | Stable C callback storage and quiescent release | Native libraries retain callback pointers beyond stack lifetime | Addresses of Swift values are not a stable ownership strategy |
| D7 | Exact native inventory plus XML manifest | Makes completeness measurable | Hand-maintained high-level feature list misses APIs and constants |
| D8 | docs-based DocC conceptual catalog before source | Keeps design review separate from implementation | Premature source stubs create misleading public API commitments |
| D9 | Explicit close and deterministic fallback cleanup | Covers early exits and avoids task-dependent teardown | ARC-only design misses native ownership and callback cycles |
| D10 | Checked-in generated code initially | Reviewable source and reproducible packaging | Mandatory plugin generation adds host-tool bootstrapping complexity |

## Follow-up ownership decisions

| ID | Decision | Reason |
|---|---|---|
| D11 | Root-owned authoritative cleanup records; weak cell index is auxiliary | Native obligations must survive loss of Swift references |
| D12 | Separate user delivery, physical attachment, and outer native-frame states | Cancellation and callback return do not prove native quiescence |
| D13 | Logical close may precede physical free; outside-frame drain is explicit | Callback-triggered synchronous teardown can invalidate C stack users |
| D14 | Backing-allocation borrow guards and transitive dependency edges | Scoped lifetime alone does not prevent reentrant mutation or aliasing |
| D15 | Owned byte copy is the default for externally writable SHM | Peer synchronization is outside compiler-proven Swift exclusivity |
| D16 | Unproven affine cleanup stays unsafe/unavailable | Explicit close cannot replace reliable fallback cleanup |

## Questions that require evidence before implementation

| Question | Required evidence | Default until resolved |
|---|---|---|
| Custom native lifetime syntax and remaining generic constraints | Phase 1 probes validate standard Span and noncopyable transfer; public @lifetime return remains gated | Owned copies or verified checked views; no experimental flags or underscored public annotations |
| Destruction from non-dispatch threads | Native source audit and race tests | Explicit domain close; serialized fallback with documented affinity |
| Descriptor ownership on failed constructors/adoption | Version-pinned source and injected errors | Do not expose safe adoption until known |
| Native client/resource/global-offer destruction ordering | Source audit, C fixture, callback traces | Registry invalidation and deferred context release |
| SHM SIGBUS and access thread contract | Native source audit and truncation test | No safe pixel view for unverified access paths |
| Exact safe API naming and return-value contracts | Header/source comparison and compiled vertical slice | Family names in design are provisional |
| XML parsing implementation | Parser correctness and dependency assessment | No new production dependency |
| DocC cross-module symbol linking and visual layout | Standalone conversion passed on Swiftly 6.4.2; still need symbol graphs and visual inspection | Nine conceptual pages verified; no symbol/example/visual verification claim |
| Safe multithreaded queue facade | Shared read-coordination model and stress tests | One safe dispatch domain; explicit advanced compatibility |
| Foreign object lifetime coordination | Integration-specific ownership contract | Unsafe borrowing/adoption only |

## Review checklist

Before phase 1, review M1–M19 and the ownership ledger. Before adding a safe API, resolve its native failure/ownership contract. Before calling the library complete, close every inventory item and validate both protocol directions. Before release, review leak evidence, unsafe sites, documentation, and performance results with a human reviewer.

The follow-up review scenarios SR1–SR18 are recorded in [SafetyReview](WaylandKit.docc/SafetyReview.md). Source-inspected behavior narrows the model but does not close the compiler, native integration, failure-injection, or sanitizer gates.

## Phase 1 implementation evidence

Implementation has started with isolated compiler, ownership-graph, and native ABI/callback experiments. The exact matrix, unsafe boundaries, and reproduction commands are documented in [ToolchainValidation](WaylandKit.docc/ToolchainValidation.md). Consuming a noncopyable field in deinit is supported by the tested Swift 6.4.2 host. Custom public @lifetime return signatures remain behind the experimental LifetimeDependence feature and are excluded from the baseline. Span does not universally prevent suspension. The aarch64 run, production runtime, and human code review remain outstanding.

## Phase 2 scope decision

The user explicitly deferred aarch64 validation and authorized actual x86_64 runtime implementation. The ownership core now has package-access authority owners, checked references, authoritative records, dependency-ordered release, and synchronous native-frame quiescence. This milestone does not waive aarch64 testing for future support claims. See [OwnershipRuntime](WaylandKit.docc/OwnershipRuntime.md).

The initial standard Synchronization.Mutex implementation triggered TSan diagnostics also reproduced with an independent protected counter. The runtime consistently uses a narrowly audited pthread mutex shim for sanitizer-visible synchronization rather than adding exclusions. Runtime objects remain non-Sendable. The one unchecked conformance is the private-storage synchronization primitive; no native object is covered by it.

## Descriptor and detachable callback milestone: 2026-11-14

Descriptor ownership now distinguishes success-only adoption, consume-on-failure receive, pre-registration receive scopes, duplication, scoped raw borrow, and explicit transfer. Detachable callback contexts use independent physical registration records and delivery cancellation flags. Their implementation and native quiescence preconditions are documented in [DescriptorsAndCallbacks](WaylandKit.docc/DescriptorsAndCallbacks.md). Nonremovable proxy dispatchers are now implemented separately; see the following milestone. Optional asynchronous transport coordination remains future work.

## Permanent dispatchers and subsequent slices: 2026-11-14

A permanent client dispatcher shares the proxy's single cleanup record. Subscription cancellation never destroys native storage. Local proxy destruction precedes context retirement at the complete outer-frame boundary. Concrete observation delivery always cleans incoming descriptors and unclaimed constructors. Raw construction-to-handoff must lease native prerequisites.

The client slice now includes registry/sync/queue operations, a single prepared-read arbiter, and a separately owned cancellation wake eventfd. The server slice adds native client/resource destruction watches and a restricted cascade operation rather than applying the leaf-only notification to arbitrary parents. Idle completion consumes its one-shot native obligation without a second remove.

The host schema generator uses Python's standard XML parser with input quotas and DTD/entity rejection; no production parser dependency was added. Core schema generation is not executable protocol binding coverage. The generated native manifest intentionally keeps the complete release gate false. See [ImplementationProgress](WaylandKit.docc/ImplementationProgress.md).

## Completion run: 2026-11-14

The user authorized completing Phase 0–7 in order in one continuous implementation run. Automated phase verification proceeds without waiting between stages. Human review remains an external acceptance requirement; aarch64 remains explicitly deferred. Neither condition may be reported as completed by automated x86_64 tests.

The phase 5 inventory must classify every baseline item and complete core binding validation. Its full-native acceptance gate depends on the advanced families scheduled in phase 6; the native release gate stays false until those implementations and their tests exist. This dependency does not permit marking imported declarations as implemented or skipping advanced APIs.

Typed core methods now cover both client/server directions. Reserved native display/registry implementations are preserved. Representative native ownership tests, compiler rejection checks, release builds, instrumented native ASan/TSan, and DocC conversion pass. Per-opcode behavioral acceptance remains distinct from deterministic generation and compilation.

## Measured typed-path optimization

The first equivalent `wl_data_offer.action` workload measured approximately 47% single-message and 62% batch-64 throughput loss, with exactly one additional glibc allocation entry per prepared read. This fails the 10% target. Optimization preserves callback admission's generation, live-state, pending-close, domain, and enclosing-native-frame checks. A callback already executes inside an admitted outer native frame and need not claim/release the same domain again. It still synchronizes pending foreign closes at admission. The outer frame remains responsible for quiescent cleanup. Prepared-read capabilities can use a nonwrapping display-local generation instead of a separate heap box; old resolved tokens must never resolve a newer nested reservation.

The first optimization removed the read allocation entirely but still measured approximately 44%/54% throughput loss. The next change adds a C thread-local enclosing-frame identity and a sequentially consistent pending-close notification on the existing mutex primitive. Native frame identity proves same-thread admitted access before reading domain-owned records. Callback admission checks the notification, synchronizes pending close requests when present, validates the live record/generation/kind, and retains the outer frame. Foreign producers still publish close requests under the existing mutex and mark the notification before releasing it. Notification clearing occurs only while consuming the mailbox under that same mutex. No cleanup or user callback executes under that mutex. Nested unrelated runtime frames restore the previous thread-local identity on every exit. This changes neither invalidation linearization nor the requirement for a complete enclosing native invocation.

Callback storage now retains a copied-identity observer rather than a weak handle cell. The observer retains no runtime control. This removes callback dependence on cell reachability and avoids imposing weak-reference side tables on every handle copy. Scalar callback admission has no separate Swift-only native frame: the already retained outer C invocation remains the quiescence boundary. A small shared lifetime token may cache the record's monotonic live bit without retaining its cleanup record or control. Every transition away from live clears that bit through the record state setter. The token is checked only after a same-thread native-domain proof and mailbox synchronization; it is never an independent native lifetime authority.

The cached lifetime token retains only the existing synchronization primitive and Sendable admission bits, never RuntimeControl or a handle cell. Clean callback admission can therefore check same-thread frame identity, the atomic close notification, and the monotonic live bit without weak-loading a control or hashing its record index. A pending close always falls back to synchronized authoritative transitions before admission. The primitive remains alive while any token can compare its identity, so a freed/reused mutex address cannot admit an old token. This optimization is restricted to callback entry already protected by an outer native frame; ordinary public handle access retains its authoritative validation path.

## Cursor file trust boundary

The public native theme API accepts a theme name and reads external Xcursor files through process-global search configuration. Its pool allocator performs unsigned growth arithmetic followed by signed-size narrowing and exposes no aggregate quota callback. The wrapper cannot establish an aggregate file/allocation bound before this native parser runs. Loading is therefore an explicit unsafe input-trust boundary, even though the returned theme owner and all subsequent image/buffer operations remain generation checked. The caller must trust the native parser and selected files and establish that native image/pool sizes fit the pinned C implementation's integer/mapping bounds. This is a conservative ownership boundary, not a claim of a demonstrated upstream vulnerability. Independent raw compatibility remains available. No safe constructor silently assumes an initial requested cursor size bounds total theme storage.

## Public protocol marker admission

Public generic signatures require public ClientInterface/ServerInterface constraints, but protocol conformance alone must not authorize native metadata. An external conformer can otherwise return a changing interfaceName and make separate native-class/schema reads disagree. Safe factories admit only the exact generated core marker metatype identities. They obtain one canonical immutable schema before any native acquisition and use its name/version throughout that transaction. External conformances are rejected with a recoverable unsupported-marker error without executing their name getter or decoder. Raw custom metadata remains explicitly unsafe; extension descriptor arenas require a separate verified implementation. This closes a public-API trust gap rather than relying on a documented request not to conform.

## Native queue retention bound

Native prepare-read checks only the selected event queue. Reading repeatedly through an empty queue while another managed queue remains pending could retain native events outside the Swift decoded-event ledger. The serialized safe coordinator now preflights every other live managed queue, using balanced native prepare/cancel probes without dispatching user callbacks. Pending work in any queue rejects another read with eventsPending until that queue is explicitly dispatched. Default-only operation has no additional native probe. Raw independent readers/queue reassignment remain outside this policy. Queue lookup storage retains raw pointers and weak-control observers only; its entries retire with authoritative queue cleanup.

## Prepared-read native-frame validity fast path

ClientReadReservation exists only while ClientConnection.withPreparedRead retains a checked client-display native frame. Its read operation previously called ObjectHandle.isValid, reentering the same logical domain and bookkeeping mutex for each read. A local fast path may inspect RecordLifetime.live only when the thread-local native-frame identity matches the record's admission mutex and the atomic pending-close notification is clear. It must compare the exact copied identity, including session and generation. When the notification is set, or the frame identity differs, it must use ordinary validity admission, which applies pending foreign closes before deciding. The fast path does not extend native pointer lifetime or grant an independent frame; the enclosing withPreparedRead lease remains its sole native authority. A close arriving after the check is serialized after this validity decision and remains deferred by the outer frame, as with the prior check. A resolved token still rejects before either path.

## Fused native access admission

The previous access path claimed the execution domain and validated the target with separate mutex acquisitions. The admitted domain and record validation now share one transaction. The transaction applies pending foreign close notifications before checking root and record state, so a close linearized first rejects the access. A close posted after admission is deferred by the retained native frame. Cleanup callbacks must run only after that frame exits: running queued cleanup between validation and native work could close the admitted record. Failed admission releases its domain claim and drains eligible cleanup without entering native code. This reduces the single-message benchmark's measured loss while retaining the same ownership and thread-domain checks.

## Combined prepared read and default-queue dispatch

The common scalar event workload previously entered the connection's ownership domain once for read preparation and again for pending dispatch. ClientConnection.readAndDispatchPending now performs both native operations inside one admitted frame. The read reservation still resolves exactly once and cancels on early exit. Before dispatch, the method checks the frame's current validity so a pending foreign close cannot deliver events after it is observed. It preserves pending-queue and recursive-dispatch rejection and does not change the explicit queue or poll/cancellation APIs. The benchmark uses this public combined call for throughput and latency; its clock-instrumented phase diagnosis intentionally retains the legacy split call to localize costs.

## Combined callback admission and cancellation read

The uncontested typed callback path needs an exact thread-local native frame, no pending close, and an uncanceled delivery gate. The C synchronization shim reads those two independent atomic mailboxes in one native entry. The retained native frame owns both mutex wrappers and callback userdata for the duration of the check. A pending close or cancellation takes the existing slow path, which applies the close before delivery and reports cancellation without publishing a user handler. Cancellation after admission may allow an already admitted handler to finish. The live record flag remains checked after the combined read, while the outer native frame still defers physical release.

## Preclassified client event cleanup

Each attached client proxy retains an immutable native interface and a validated Swift schema. At attachment, the runtime classifies every native event signature and its corresponding schema arguments for descriptor or new-proxy ownership. The trampoline still runs native cleanup when either source contains such an obligation. It also runs the conservative native-signature scan when callback context admission fails, because no classification can then be trusted. Only an admitted event classified ownership-free by both sources skips the C scan. The first 64 classifications are packed into a context-owned bit mask. Higher opcodes always run conservative C cleanup. The context retires after native quiescence. This changes steady-state scalar cost without moving FD or constructor cleanup out of the enclosing native frame.

## Scoped typed-context access

Profiling identified weak-reference side-table retain/release costs on the typed client context. Endpoint access now uses a private opaque context address only inside the endpoint's checked native lease. The authoritative proxy record strongly retains CallbackStorage.context and its cleanup closure until complete native-frame quiescence; therefore a successfully admitted lease proves the context remains allocated. Logical closure rejects access before loading that address. The pointer is written once from the exact TypedClientContext instance before endpoint publication, is never exposed publicly, and cannot authorize access independently of the endpoint generation. This removes redundant weak zeroing rather than removing the lifetime check or adding a control back edge. C callback userdata retains its existing stable allocation and retirement mechanism.

## Imported protocol definition authority

External XML is a generator capability, not permission to supply unchecked native metadata through public marker conformance. A bundle resolves interface and enum names over an explicitly supplied, bounded set of inputs before validating each document. Duplicate definitions, missing imports, unknown semantic attributes, invalid nullable/new-ID forms, and target-native integer overflow are errors. File order is explicit and contributes to a length-delimited aggregate source hash. Interfaces retain source opcode order; cyclic cross-file references do not require a topological sort. Generated metadata uses immutable value schemas with no native pointer authority. Public value initializers do not admit external marker conformances or bypass CoreProtocol.requireSchema. Dynamic native descriptor allocation and consumer retention remain separately gated until the owned-arena transaction is implemented and tested.

## Owned native metadata arena transaction

A custom descriptor bundle is one ARC-owned, immutable arena, independent of a connection. Validation derives all native signatures and verifies every interface reference before native allocation. C allocates complete interface/message/type storage in an arena with an aggregate byte quota. Forward and cyclic references are raw links within that arena; they create no Swift ownership edges. Every partial allocation belongs to the arena immediately, so one rollback releases the entire unpublished transaction. Sealing rejects missing definitions and prevents subsequent mutation. Safe descriptor values retain the arena and expose copied schemas; unsafe raw interoperability requires the caller to retain the descriptor through every native consumer. Managed dynamic consumers must retain a descriptor in their authoritative cleanup capture until native destruction and outer-frame retirement, not merely in a temporary factory variable. This last integration remains an explicit gate until implemented. Metadata allocation cannot depend on a running executor or a native display destructor.

## Managed extension client attachment

A managed extension proxy retains its sealed ProtocolDescriptor in TypedClientContext. The authoritative proxy cleanup capture and permanent callback storage keep that context alive through physical proxy destruction and complete outer-frame retirement. Endpoint references keep copied schema/diagnostics, not independent metadata authority; an invalidated owner cannot dereference a retired context. Extension factories accept validated descriptors without admitting external CoreInterface conformances.

A typed constructor target is resolved from the originating context's same arena. A caller cannot substitute another bundle with the same interface name and a different event layout. Generic request constructors alone accept an explicit descriptor, and the factory inserts interface/version wire fields from that immutable descriptor rather than trusting caller-supplied strings. Every request validates schema, negotiated version, argument kind/nullability, connection identity, and object/FD leases before marshalling. Incoming extension constructors inherit the exact arena definition selected by the native message metadata.

Extension handlers receive the existing noncopyable inout reader. After delivery, cancellation, or handler failure, unclaimed owned fields are decoded and retired through the existing runtime, with C fallback disposal for failed runtime admission. This supports zero-argument protocol destructor fallback without changing the core scalar dispatcher hot path. Explicit argument-bearing destructors marshal while arguments are leased and then consume local ownership; fallback never fabricates missing destructor arguments. The public raw descriptor borrowing boundary remains unsafe and is not used to waive managed lifetime requirements.

Core interoperability from an imported arena requires exact schema equality for the target and every transitively referenced interface/enum owner, including versions, opcode order, argument layouts, ownership effects, and enum definitions. A matching class name alone is rejected. A successful core owner conversion preserves the same cleanup record and metadata-retaining context. Incoming core constructors from imported metadata pass that descriptor into core attachment rather than dropping its arena owner. This prevents a copied/custom wl_interface layout from being decoded with a different canonical event schema or freed while its core facade survives.

## Generated extension facade admission

An external generated Swift wrapper must not admit a managed object by native class name alone. Its fixed generated value schemas are the decoder and encoder authority; a runtime descriptor can share the class name while changing any opcode, argument, ownership effect, or referenced interface. ProtocolDescriptor.requireEquivalent compares the root and every transitively referenced interface and enum owner against the generated graph before a noncopyable wrapper consumes the dynamic object. Duplicate expected definitions and missing references fail rather than trapping or weakening the comparison. Import order and unrelated extra definitions do not alter reachable graph equivalence. The dynamic owner remains responsible for native cleanup if wrapper admission throws.

The extension binding generator consumes the same validated XML bundle as the value generator and emits client/server noncopyable owners, checked references, request/event sum types, open enum values, constructor operations, and bind/global entry points. It emits wrappers only for interfaces defined in the primary XML while importing all referenced schemas for graph checks. FDs and constructor IDs remain single-use ownership values. Interface-generic object fields remain checked erased references because external packages cannot gain an unverified typed view of arbitrary foreign resources. Native marshalling and callback disposal stay in the existing dynamic adapters; generation adds no raw pointer authority. Generated names are collision-checked before writing output.

## Managed extension server resource lifetime

libwayland 1.26.0 resolves a server request's method metadata from the live wl_resource and creates, dispatches, and destroys its wl_closure in one client-connection callback frame. Server event post and queue calls serialize metadata into the connection buffer before returning. A managed extension resource therefore pins its complete descriptor arena in the authoritative resource cleanup context through native resource destruction and outer-frame retirement. Native globals separately retain their wl_interface until wl_global_destroy and pin the descriptor in the global cleanup state. A temporary ServerClient factory variable does not establish either lifetime. Fixed-interface constructors use the same sealed arena as the receiving request or advertising global. Generic constructors may select a separately validated arena because their native message metadata carries no target interface pointer. Explicit raw resource creation remains unsafe and cannot borrow a descriptor as if it were managed.

The dynamic server request reader must account for every incoming FD and constructor ID regardless of handler delivery. The existing dispatcher closes unclaimed FDs after the callback, while a pending constructor object rejects the client on drop. A dynamic handler that never claims a constructor must also reject the client before the native frame ends. All server resource creation continues through the shared server-client registry and native destruction watch so external client destruction consumes exactly the same cleanup record.

## Queued client closure metadata consumer

The initial managed-extension lifetime argument omitted demarshalled closures waiting outside an active native frame. libwayland 1.26.0 event queues retain wl_closure.message and proxy references after wl_proxy_destroy marks a proxy destroyed. Later queue dispatch/release still reads the message signature while retiring arguments. Proxy-context retirement alone therefore cannot free its descriptor arena. Zombie map entries separately copy FD counts and do not retain interface pointers, but that does not remove the queued-closure obligation. See src/wayland-client.c closure destruction, wl_event_queue_release, and proxy_destroy in the pinned native source.

Each display now needs an independent metadata retention cell, captured by its authoritative disconnect action. A successful managed metadata attachment commits a distinct arena to that cell until disconnect releases default/display queues; tracked custom queues retire before disconnect by dependency order. The cell has a native byte quota and at most 64 distinct arenas. Reusing an arena does not grow the cell. A provisional new arena reservation rolls back when proxy publication fails before any native read can enqueue a closure for that new arena. Incoming event constructors reuse their already-retained parent arena. This cell has no control/endpoint back edge. Snapshot counters use the existing Sendable-value RuntimeMutex; descriptor dictionaries mutate only under the runtime execution domain. Native disconnect completes before the cell clears its descriptors, including when invalidated owners and references remain alive.

## Queue-aware client constructor cleanup

A queued constructor event already owns a native child proxy before Swift receives it. Destroying its receiver before dispatch makes libwayland skip the dispatcher, so the wrapper cannot retire the child's initial reference through its usual C fallback. Constructor-bearing receivers therefore require a release-readiness predicate in their authoritative record. Logical close remains immediate; physical destruction waits for managed queues to drain. Local close does not dispatch unrelated live callbacks. Root closure invalidates all tracked receivers first, then drains queued callbacks in cleanup-only admission before physical proxy destruction. Cleanup-only admission proves an existing retained native frame and a nonretired record; it grants no live receiver access and always disables user delivery.

Readiness predicates execute outside bookkeeping locks under a temporary native frame, retain only independent queue state and weak observers, and cannot consume their destruction obligation. A no-progress readiness pass returns deferred rather than spinning. Progress through another record or queue retirement triggers a bounded rescan so root-owner fallback does not depend on a future executor turn. Pending metadata stays pinned at display scope through final queue release. Core and extension mandatory cleanup walk owned fields independently of unrelated object-reference decoding failures.
