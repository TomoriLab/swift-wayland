# Validation and delivery

Validate the requested memory, lifecycle, coverage, and performance behavior before expanding the API.

## Current evidence

The original repository contained README, license texts, ignore rules, and an empty untracked AGENTS.md. The initial design added docs only. The follow-up safety review revises docs and fills AGENTS.md with repository policy; it adds no implementation. Installed pkg-config reports libwayland-client and libwayland-server 1.26.0. Public headers and wayland.xml supply the reference inventories.

The initial uninitialized shell resolved `swift` to python-swiftclient 4.11.0. Rechecking after `source ~/.zshrc` resolves a shell function from `~/.zsh_config/_swift.zsh` that runs Swiftly. `swift --version` reports Swift 6.4.2 (swift-6.4.2-RELEASE), target x86_64-unknown-linux-gnu. Swiftly also provides DocC under its 6.4.2 toolchain. A standalone catalog conversion with `--warnings-as-errors` passed and generated all nine conceptual documentation pages; page titles and identifiers were checked in the archive JSON.

Phase 1 now includes executable Swift feature, ownership-reference, and native callback/ABI probes. See <doc:ToolchainValidation> for the exact matrix and evidence. These are isolated experiments rather than production wrapper tests. The actual x86_64 ownership runtime now builds and runs package tests as described in <doc:OwnershipRuntime>. Independent C peer interoperability, isolated native instrumentation, and an exploratory dispatcher benchmark now exist. Core and advanced-API interoperability fixtures, full native mapping classification, equivalent typed measurements, and selected rendered DocC inspection now exist. The throughput acceptance target remains unmet; see <doc:ImplementationProgress> for current evidence and boundaries.

## Delivery gates

| Phase | Work | Exit criterion |
|---|---|---|
| 0: design review | Review ownership, scope, state model, native contracts, language probes | Human review; resolve architecture-changing objections |
| 1: toolchain and ABI experiments | Provision exact 6.4.2, verify import modules, ownership features, callbacks, strict safety | Positive/negative probes compile as expected on both architectures |
| 2: minimal ownership runtime | Handle cells, domain guard, FD owners, stable callback bridge | Invariants and failure-injection tests pass without leaks |
| 3: client vertical slice | Connect, registry, sync callback, queue, prepare/read/cancel, shutdown | Independent C server interoperability and cancellation tests |
| 4: server vertical slice | Display, client, resource, globals, event source, destroy listener | C client interoperability and external-destruction tests |
| 5: generator and core coverage | Validated IR, both directions, all public baseline items | Implemented/documented/tested coverage reaches 100% |
| 6: optional and advanced APIs | Cursor, EGL, SHM, logging, utilities, legacy and unsafe paths | Complete native inventory and ownership audit |
| 7: documentation and performance | DocC, tutorials, benchmark reports, soak tests | Documented thresholds and no unexplained regressions |

Implementation is now authorized in stages. The current implementation spans the baseline client/server/protocol/runtime and advanced products on x86_64. The user explicitly deferred aarch64 testing, so it remains tracked without blocking this milestone. Implement one independently verifiable phase at a time. Do not claim full coverage when only the client registry example works.

## Compile-time safety tests

Positive tests cover unique ownership transfer, nested scoped borrows, ordinary request sending, and explicit owned snapshots. Negative tests must fail for double consumption, use after consume, storing/returning a borrowed callback view, capturing it in an escaping closure, holding it across await, sending a non-Sendable connection to another task, and applying the wrong event-source operation.

Pin diagnostic assertions to semantic rejection rather than complete compiler error text. Verify the strict memory-safety build option on the actual compiler. Audit every accepted unsafe marker; strict mode detects boundaries but does not prove the underlying C call is safe.

## Runtime safety and fault injection

Test explicit close, implicit fallback, initialization failure at every allocation/registration stage, native external destruction, pointer/ID reuse, self-canceling listeners, callback-induced parent close, deferred free, simultaneous cancellation, prepared-read early exit, EINTR, flush EAGAIN, fd decode failure, and peer disconnect during callbacks.

SHM tests include invalid dimensions, overflow, unsupported formats, mapping offsets, truncation, SIGBUS behavior under the native mechanism, and ref/access balance. Cursor tests retain views after theme close and reject access; EGL tests enforce window-before-surface destruction without requiring a physical GPU for ordinary lifetime tests. Real EGL integration uses a separately marked environment-dependent test.

Run AddressSanitizer across Swift and the bridge; run ThreadSanitizer in a separate configuration. Include an instrumented libwayland build when assessing native internals because sanitizing only the wrapper misses native memory accesses. Toolchain/platform sanitizer support must be verified, not assumed. Use leak instrumentation where supported and an independent tool such as Valgrind for the C bridge/native fixture; distinguish unsupported Swift runtime tooling from a clean result.

Fuzz XML parsing, signature decoding, checked dynamic argument conversion, and model transition traces. Add malformed peer integration fixtures against libwayland rather than writing a parallel untrusted wire parser in the wrapper. Seed corpora include nullable objects, generic constructors, enum unknown values, descriptors, and destructor messages.

## Leak acceptance

For each scenario, warm up once, repeat at least 10,000 connect/create/register/cancel/close cycles, drain every callback and cleanup queue, then compare live ledgers, fd counts, and independently observed allocations to baseline. Application-visible handles may retain invalidated cells, so tests must release those handles before the final accounting checkpoint.

Require zero outstanding library-owned connection resources, registrations, read reservations, SHM references/accesses, and descriptors. Process-lifetime metadata and allocator/runtime caches must plateau after warm-up and have documented bounds. RSS alone is not leak evidence and a stable RSS alone is not proof of no leaks. Record tool output, toolchain, native library build, architecture, and any suppressions with a justification.

Leak tests must include dropping a subscription token, native destruction before token release, throwing callback handlers, canceled async consumers, and invalidated child references outliving the display. Closure tests deliberately create a user ARC cycle and document how explicit root closure or weak capture breaks it; flag-only permanent-dispatcher cancellation does not release its native-reachable context; do not label this a library guarantee.

## Performance experiment design

Compare equivalent optimized C and Swift workloads on the same machine and libwayland build. Separate startup, steady-state request throughput, scalar callback dispatch, strings/arrays, fd passing, queue coordination, SHM access, and teardown. Include both in-process benchmark peers over socketpair and a representative compositor run. Avoid comparing a no-op Swift closure with actual C protocol work.

Measure events/second, median/p95/p99 latency, CPU time, allocations per event, copied bytes, peak/live native allocations, fd count, and teardown duration. Record compiler optimization mode, hardware, affinity, warm-up, sample count, distribution, and confidence intervals. Exclude setup from steady-state allocation counts while reporting it separately.

Initial engineering budgets are hypotheses: no per-event heap allocation in the generated synchronous scalar path after setup; O(1) handle validation; no mandatory payload copy for verified immutable synchronous callback bytes (externally writable SHM excluded); and at most 10% median throughput loss relative to equivalent C for the selected hot-path fixtures. A 10% budget is a project target, not measured evidence. Report latency separately and revise budgets only with an explained review decision. Safety checks cannot be removed to meet a benchmark.

## Implemented validation commands

Run the complete configured x86_64 matrix from the repository root:

```sh
source ~/.zshrc
python3 Scripts/validate.py --native-sanitizers --soak --benchmark
```

The script verifies the pinned toolchain before generation, compiler-rejection, native peer, failure-injection, Debug/Release, example, sanitizer, lifecycle, documentation, and performance checks. It preserves command logs and input hashes under .build/validation. Command completion is separate from acceptance: native baseline leaks, throughput budget failures, and missing performance coverage keep the aggregate result unsuccessful. See <doc:ContinuousIntegration> for prerequisites and targeted commands.

For the ordinary Swift Testing suite, use `swift test --disable-xctest -Xswiftc -warnings-as-errors` and its `-c release` variant. Native lifetime validation uses `python3 Scripts/verify-instrumented-runtime.py --sanitizer address` and `--sanitizer thread` in separate runs with loader verification. These are the implemented harnesses; an uninstrumented native dependency does not establish native memory safety.

## Follow-up review acceptance matrix

Every SR1–SR18 scenario in <doc:SafetyReview> requires a test before its associated safe API is released. Add transition traces for provisional callback attachment, cancellation while physically attached, native-frame reentrancy, deferred root close, self-canceling idle sources, resource destruction snapshots, last-cell disappearance, dependency closure, storage aliasing, and ignored constructors/fds. Inspect M1–M19 after every transition.

Compile-fail tests must prove borrowed views cannot escape through a closure result or capture, not merely that the closure itself is nonescaping. Runtime tests must attempt mutation of the same backing storage through another wrapper while borrowed. Native tests must leave the callback and continue the surrounding C dispatch before checking that delayed teardown occurs; checking only at the end of the Swift callback misses SR3.

Enumerate cancellation before waiter creation, between creation and publication, during poll, during callback delivery, and after readiness wins. Force descriptor-number reuse and late wake attempts. Fail initialization after every metadata/context/record allocation and before/after native attachment. Require immediate cleanup of provisional obligations without assuming native constructors cannot invoke callbacks synchronously.

Use distinct SHM pools on one thread, same-pool nested access, native resource destruction during retained SHM access, peer mutation/truncation, and final release on a different thread. Safe fallback behavior must be demonstrated or the associated API remains gated. Test live thread-affine endpoints after logical coordinator shutdown and prohibit a safe owner if its final native release cannot be scheduled reliably.

## Current staged implementation

The permanent proxy dispatcher and initial client/server slices now have native peer, cancellation, native cascade, and one-shot idle tests. Detailed commands and remaining gates are recorded in <doc:ClientAndServer>, <doc:OwnershipRuntime>, and <doc:ImplementationProgress>. Isolated native builds instrument client and server in separate ASan processes without disabling ODR checks, and together in a TSan process. The configured advanced API, XML fuzz, and 10,000-cycle soak checks have executed successfully. Their scope does not establish exhaustive native allocation failure coverage or remove the performance and native baseline leak gates.

The first scalar observation experiment is recorded in <doc:DispatcherBenchmark>. It does not establish the equivalent generated typed-path budget or complete phase 7.
