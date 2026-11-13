# WaylandKit repository instructions

## Scope and current phase

This repository develops WaylandKit, a Swift interface to libwayland. Implementation is authorized in stages. The current work includes the ownership runtime and staged client/server/generator slices on x86_64 Linux: handle invalidation, authoritative cleanup records, dependency ordering, deferred release, descriptor ownership, and detachable callback context lifetime. The user explicitly deferred aarch64 verification; it is a follow-up requirement rather than a blocker for this milestone. Keep phase 1 experiments separate under Tests/Toolchain. Production runtime code belongs in Sources/WaylandRuntime with a narrowly audited CWaylandRuntime synchronization shim. Concrete adapters live in WaylandClient and WaylandServer with their matching C bridges; deterministic protocol schema metadata lives in WaylandProtocol. The user authorized progressing through the documented stages. Record supported behavior, actual tests, and unresolved native contracts before advancing each independently verified stage. Read docs/WaylandKit.docc/ImplementationProgress.md for completed work and remaining gates; do not treat the full plan as complete.

Read `docs/README.md`, `docs/decisions.md`, and the relevant articles under `docs/WaylandKit.docc/` before changing architecture. Read `SafetyReview.md`, `OwnershipAndFFI.md`, `MathematicalModel.md`, and `DispatchAndConcurrency.md` before changing ownership or execution rules. More specific applicable project policy takes precedence within its scope; system and developer instructions always retain their precedence.

## Design priorities

1. Preserve memory safety and explicit resource ownership.
2. Preserve native semantics and complete public API coverage.
3. Maintain performance through measured, bounded overhead.
4. Keep ownership machinery centralized and maintainable.
5. Document every public contract in detail through Swift DocC.

Target Swift 6.4.2 in Swift 6 language mode and libwayland 1.26.0 unless an explicit decision updates the baseline. Initialize the local shell with `source ~/.zshrc` before using `swift`. Its shell function invokes Swiftly and currently selects Swift 6.4.2; the uninitialized PATH instead resolves OpenStack python-swiftclient. Use `/home/zeroday0619/.local/share/swiftly/bin/swiftly run <tool>` for tools such as swiftc and docc that may not be on PATH. Verify the selected version rather than assuming shell initialization pins it forever. Do not infer released feature availability from an accepted proposal or the development branch. Verify language features and build options on the exact toolchain before relying on them.

## Ownership and FFI requirements

- Every successful native acquisition and native ref increment creates one tracked release obligation. Record ownership on success, failure, partial initialization, native destruction, cancellation, and parent shutdown.
- Use noncopyable authority owners and generation/session-checked reference cells. Copyable references have no independent native destruction authority and never cache a reusable raw pointer.
- Keep authoritative cleanup records independent of weak Swift cell indexes. Root-owner closure must not depend on child references disappearing or a parent control block reaching ARC deinit.
- Record transitive dependency leases, backing-storage borrows, callback activity, and outer native frames. A callback returning does not establish native quiescence.
- Separate logical close from physical release. Callback-triggered close rejects new work immediately and defers native free until the relevant outer C frames and dependent users finish. Do not synchronously wait for the current frame to end from inside itself.
- Distinguish subscription delivery lifetime from native attachment lifetime. A canceled client subscription cannot free userdata still reachable by its proxy's installed dispatcher. Mandatory event cleanup continues without user delivery.
- Native destruction consumes the shared cleanup record and invalidates references. Do not attempt to defer or repeat a free controlled by libwayland. User destroy handlers receive copied snapshots rather than live native borrows.
- Stable C callback storage, vtables, signatures, proxy tags, and interface metadata must outlive every native consumer. Do not retain pointers into temporary Swift values or ended buffer/string scopes.
- A nonescaping closure alone is not a lifetime proof. Use compiler-checked nonescapable views with valid dependencies, lease-checked operation-only views, or owned copies. Raw pointers cannot escape a safe view.
- Protect against reentrant resize, remap, release, and parent destruction while a view is active. Track aliasing by backing allocation identity. Do not reinterpret peer bytes as arbitrary Swift types.
- Close or transfer every incoming fd and constructor obligation on partial decoding, ignored delivery, cancellation, failure, queue rejection, and shutdown. Descriptor integers are not durable resource identities.
- SHM access is scoped, same-thread, non-suspending, and balanced. Preserve native buffer/pool references and mapping stability. Peer-writable SHM is not immutable Sendable Swift storage; owned byte snapshots are the default safe path.
- Keep unsafe interoperability explicit and outside the safe facade's guarantees. Full C mapping does not require pretending untyped userdata, arbitrary object adoption, varargs, intrusive pointer arithmetic, or foreign lifetime behavior is safe.
- Audit unsafe sites with pointer provenance, size/alignment, lifetime, domain, retention, failure transfer, cleanup, invariant IDs, and test IDs. Do not broaden unsafe boundaries merely to silence diagnostics.

## Concurrency and shutdown requirements

The initial safe core is synchronous and serialized. Non-Sendable handles and actors do not replace runtime isolation or establish fixed-thread affinity. Separate the logical execution-domain claim from short-lived bookkeeping locks. Do not hold mutation locks across blocking poll, native callback delivery, user code, or continuation resumption.

Pair each successful prepared read with exactly one read or cancel through the originating coordinator. Do not mix independent native readers without an explicit integration contract. Cancellation wakes the coordinator rather than closing its borrowed transport fd. Resume each published continuation exactly once, including cancellation before publication. Keep wake resources alive until all producers and native waits quiesce.

Do not use detached tasks from destructors. Safe fallback cleanup cannot depend on a stopped executor. Keep thread-affine integrations unsafe or unavailable until their full lifetime and fallback paths have been verified. Process logging uses stable trampolines and synchronized handler retirement; Swift user code must not run in asynchronous POSIX signal context.

## Mathematical model and validation

Treat M1–M19 in `docs/WaylandKit.docc/MathematicalModel.md` and SR1–SR18 in `docs/WaylandKit.docc/SafetyReview.md` as traceable review obligations. Update the state model, resource ledger, counterexample tests, and affected documentation together when changing a contract. Conservation equations require a liveness argument as well as balanced counts.

Before implementation, document unresolved native ownership contracts as explicit gates. During implementation, validate with compile-fail ownership/lifetime tests, independent C peers, model-derived traces, failure injection, separate address/thread sanitizer runs, leak ledgers, fd counts, and measured C/Swift benchmarks as appropriate. Do not create tests that merely duplicate implementation logic.

Do not claim memory safety, leak freedom, complete coverage, performance parity, compiler verification, or rendered DocC validation without evidence. Distinguish design targets, inspected source facts, unverified assumptions, and measured outcomes. Zero RSS growth is not proof of no leaks. Arbitrary user-created ARC cycles and fatal process termination must not be hidden behind an unconditional cleanup guarantee.

## Coverage and documentation

Track all public functions, static inline helpers, data symbols, typedefs, record fields, enum members, macros, callback contracts, and core protocol requests/events. Use Clang AST, preprocessing, exported symbols, and XML together when the coverage tooling is implemented. Current reference inventories are baseline evidence, not completed mappings. Preserve client/server distinction and opcode order.

Keep conceptual design in `docs/WaylandKit.docc/` and baseline inventories in `docs/reference/`. Use `docs/README.md` as the entry point. Every future public symbol requires native mapping, ownership, lifetime/invalidation, execution/reentrancy, failure/rollback, destruction, descriptor behavior, complexity, safety assumptions, availability, and tested examples. Keep generated documentation tied to the same intermediate representation as generated APIs.

Write technical artifacts in neutral English with full descriptive identifiers and complete declarative comments. Explain why a design is required. Use existing repository terminology. User-facing conversation follows the user's language and requested style. Cite primary, version-pinned sources adjacent to native behavior claims. Preserve upstream license notices when copying text or generating derived artifacts.

## Change workflow

Inspect current files, policies, and Git state before editing. Present a plan in no more than three lines before modifying files. Keep changes within scope and preserve user edits. Never treat an untracked file as disposable. Ask before adding a production dependency. Do not commit, push, or publish unless authorized.

For documentation-only changes, validate local Markdown links, DocC article references, invariant/review IDs, final newlines, and whitespace. Inspect new/untracked files directly: ordinary `git diff --check` does not validate their contents. Report checks actually run and remaining toolchain/native validation accurately. No implementation build is required when implementation is absent.

When a commit message is requested, inspect the relevant staged diff and use the installed `git-commit-message --conventional --language en-US` with the existing provider/model configuration. Generate without `--commit` and review the result. A temporary Git index may prepare a message without altering the user's real staging state. If generation fails, report the cause and ask before substituting a manual message. Use concise Conventional Commits and include a body only when needed. Do not use `--no-verify`, add a person's Signed-off-by, or invent model metadata. Human review and validation are required for AI-assisted changes; add Assisted-by only when explicitly permitted or required, using runtime-reported metadata.

## Current runtime verification

Read `docs/WaylandKit.docc/OwnershipRuntime.md` and `docs/WaylandKit.docc/DescriptorsAndCallbacks.md` for the implemented contracts. Callback cancellation is delivery-only. Permanent proxy dispatchers combine proxy destruction and context retirement in one record; they never fabricate detach. The raw construction-to-handoff transaction must lease tracked prerequisites. Other callbacks require a real detach/quiescence contract. Raw FD transfer must reject outstanding borrows and dependents. Runtime owners, handles, and controls remain non-Sendable. The single production unchecked Sendable conformance is the private-storage RuntimeMutex primitive constrained to Sendable values and backed by pthread synchronization. Do not extend this exception to native resources or callback closures. Generic unsafe adoption transfers ownership only on success; consuming receive factories specify cleanup on every outcome. All accept only thread-compatible, acyclic cleanup captures with no independent destructor for the same allocation. Native server cascades may consume only proven server client/resource subtrees. ReadCancellation owns only a synchronized wake descriptor and flag, never native display access.

Use `swift test --disable-xctest -Xswiftc -warnings-as-errors` for the Swift Testing suite, release and separate address/thread sanitizer configurations for native lifetime changes, and `python3 Scripts/verify-runtime-ownership.py` and `python3 Scripts/verify-client-ownership.py` for the actual package APIs' compiler rejection checks. Run `python3 Scripts/verify-protocol.py` for schema validation/scanner equivalence and `python3 Scripts/verify-api-coverage.py` for the native inventory. Instrumented native verification uses `python3 Scripts/verify-instrumented-runtime.py --sanitizer address` and `--sanitizer thread`; no host library is replaced. Keep ASan leak detection enabled. Do not classify TSan output as a runtime defect or toolchain limitation without isolating it; the current pthread primitive was selected after a separate standard-Mutex reproducer reported the same race. No sanitizer suppression is part of the verified configuration.
