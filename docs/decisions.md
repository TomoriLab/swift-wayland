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
