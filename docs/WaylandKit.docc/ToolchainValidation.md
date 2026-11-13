# Swift 6.4.2 toolchain validation

Establish compiler and native ABI evidence before implementing the ownership runtime.

## Milestone and scope

Implementation has been authorized in stages. This milestone adds a reproducible compiler harness and isolated executable experiments under Tests/Toolchain. It does not expose a production Swift package or native wrapper API. Phase 1 host validation is distinct from the two-architecture phase 1 exit gate.

The verified host is x86_64 Linux with Swift 6.4.2 (swift-6.4.2-RELEASE). Client, server, and cursor pkg-config modules report 1.26.0. The EGL pkg-config module reports 18.1.0; that metadata uses its own version and is not rewritten as 1.26.0. The installed cross SDK is swift-6.3.3-RELEASE_static-linux-0.1.0 and cannot establish Swift 6.4.2 aarch64 compatibility. aarch64 remains unverified.

## Compiler settings and result interpretation

The harness invokes the actual swiftc executable, verifies its reported version and target, and uses these common options:

```text
-swift-version 6
-strict-concurrency=complete
-strict-memory-safety
-warnings-as-errors
-parse-as-library
```

Each fixture is tested in debug (`-Onone`) and release (`-O`). Positive probes link and execute. Negative probes compile to object code so diagnostics from ownership lowering are exercised; a type-check-only success is not sufficient. A negative result passes only for the expected semantic diagnostics and a normal compiler rejection, not an arbitrary process failure. Compiler crashes fail the suite.

The suite has 19 fixtures: eight execution probes, ten safety counterexamples, and one default-feature availability gate. A normal run has 38 configuration results. AddressSanitizer and ThreadSanitizer are separate runs of the same matrix. Machine-readable reports contain the exact commands, compiler target, native versions, source hashes, diagnostics, and executable outputs. Fixture changes during a run invalidate its report.

## Recorded host results

The following matrix passed on the inspected host on 2026-11-13:

| Command mode | Debug results | Release results | Executable runs | Expected compiler rejections |
|---|---:|---:|---:|---:|
| Default | 19/19 | 19/19 | 16 | 22 |
| AddressSanitizer with leak detection | 19/19 | 19/19 | 16 | 22 |
| ThreadSanitizer | 19/19 | 19/19 | 16 | 22 |

This totals 114 configuration results: 48 successful executable runs and 66 expected compiler rejections, including six feature-gate rejections. The native callback experiment ran once in each configuration/mode. No runtime stderr or sanitizer diagnostics were recorded. Expected rejection is deliberately reported separately from successful execution.

## Feature and ownership evidence

| Fixture | Expected result | Evidence boundary | Related obligations |
|---|---|---|---|
| Ownership | Runs | Noncopyable transfer, borrowing, consuming close, fallback and typed-throw cleanup; UniqueArray storage | M1; compiler ownership subset |
| Span | Runs | Safe array-backed Span construction, indexing, and borrowed parameter | M3, M4 for the tested owned storage |
| SpanAcrossAwait | Runs | Locally backed Span survives await; nonescapability alone is not a native no-suspension rule | M3, M18 boundary |
| AsyncCleanup | Runs | Async defer executes after deterministic cancellation; shield observes cancellation masked during cleanup | Async cleanup capability, not full M17 |
| AuditedPointer | Runs | Explicit @unsafe declaration and unsafe call under strict checking | Unsafe audit mechanism |
| ConsumeInDeinit | Runs | A noncopyable field is consumed in deinit and destroyed once without experimental flags | Specific SE-0544-style consumption pattern |
| OwnershipGraph | Runs | Root drop closes despite surviving references; lost reference retains record; frame exit drains once | Reference-model subset of M1, M2, M10, M13 |
| NativeCallback | Runs | Four C module imports, C layouts, fixed conversion, real listener callback, rollback, weak context release, descriptor balance | ABI and callback-lifetime experiment; M5/M7/M15 subset |
| DoubleConsume | Rejected | Owner cannot be consumed twice | M1 |
| UseAfterConsume | Rejected | Owner cannot be borrowed after consumption | M1 |
| ConsumeBorrow | Rejected | Borrowing parameter cannot be consumed | M1 |
| CopyOwner | Rejected | Explicit copy cannot duplicate noncopyable value | M1 |
| StoreSpan | Rejected | Escapable stored container cannot contain a nonescapable Span | M3 |
| EscapeSpan | Rejected | Span cannot outlive its local backing array | M3 |
| CaptureSpan | Rejected | Borrowed Span cannot escape through a captured closure | M3 |
| MutateBorrowedArray | Rejected | Mutation overlaps the live span borrow of the same array | M14 for this direct alias |
| SendableCapture | Rejected | Non-Sendable mutable state cannot enter the tested Sendable closure | M9 static boundary |
| UncheckedPointer | Rejected | Unmarked pointer access fails strict memory-safety diagnostics | Unsafe audit mechanism |
| CustomLifetime | Rejected | Public @lifetime return signature requires experimental LifetimeDependence in this toolchain | Public API feature gate |

These examples establish particular compiler behaviors, not arbitrary generic signatures or imported C ownership. The reference graph is single-threaded and uses Swift objects to represent obligations. It is not a production runtime and does not validate cross-thread shutdown, native queue coordination, or all M1–M19 invariants.

## Native lifetime and unsafe audit

The C experiment allocates a stable registration containing a server display destroy listener. Swift retains callback userdata before the C call. Normal destruction invokes Swift, returns to C, completes native destruction, and only then releases the retained context. The C stage value distinguishes callback execution from the return of the outer native call. Failed attachment after installing the listener also calls Swift before the constructor returns failure; provisional userdata must already be valid.

Each native executable runs one warm-up followed by 1,000 normal cycles and 1,000 cycles at each of three injected failure stages. A weak Swift reference must clear after every retained context is released. The open descriptor count must return to baseline after all cycles. This is a 4,001-attempt ABI experiment, not the design's full 10,000-cycle per-scenario production leak acceptance.

| Unsafe boundary | Provenance and lifetime | Failure and cleanup |
|---|---|---|
| Unmanaged retained userdata | Swift CallbackState; one retained count before native attachment | Release on constructor failure or after outer destroy returns; weak reference verifies release |
| C callback userdata recovery | Exact pointer created for this callback registration | Borrowed recovery only during the native call; never take retained ownership in callback |
| Opaque registration pointer | C calloc allocation, owned until native destroy returns | Never cached past destroy; injected failure rolls back allocations |
| Native listener and container-of | Listener is embedded in its own stable C allocation | Unlink inside native notification; free registration after native frame returns |
| wl_array layout access | Clang-imported C record; size/alignment compared with C | No raw array memory is dereferenced by this test |
| AuditedPointer read | Synchronous withUnsafePointer over initialized Int storage | Pointer never escapes the call; no manual deallocation |

No async callback, raw foreign adoption, SHM mapping, cursor theme, EGL surface/window lifecycle, or competing process hook is implemented by these experiments. Scalar C imports may be considered safe by compiler diagnostics, while pointer-bearing types remain unsafe; the audit follows actual diagnostics instead of adding blanket unsafe markers.

## Reproduction and reports

From the repository root:

```sh
python3 Scripts/verify-toolchain.py
python3 Scripts/verify-toolchain.py --sanitize address
python3 Scripts/verify-toolchain.py --sanitize thread
```

The runner uses the standard Python library and installed toolchain/native development packages. No dependency is installed. Exact local reports are written under .build/toolchain-probes/{none,address,thread}/report.json. Leak detection is explicitly enabled for AddressSanitizer and the fixture C code is compiled with the matching sanitizer. System libwayland has not been rebuilt with instrumentation, so passing sanitizers does not establish safety of all native internal memory accesses. The async probe and reference graph do not create the full runtime race scenarios required by phase 2.

## Design consequences and next gate

Use the verified noncopyable owner and record-arbiter pattern as the basis for phase 2. The field-consumption pattern in deinit is available on the tested host without an experimental feature flag. This is not blanket verification of every proposed SE-0544 operation.

Do not use public @lifetime-returning wrappers in the baseline API without a separate feature decision. Standard-library Span parameters are usable, but custom native views must use an actually verified lifetime mechanism, an operation-only checked view, or owned copies. A synchronous closure shape alone remains insufficient. Suspending with a locally backed Span is memory-safe in the tested example; native thread affinity and borrowed external storage still require explicit restrictions.

Before the two-architecture phase 1 gate closes, run this suite with matching Swift 6.4.2 and libwayland 1.26.0 on aarch64. Before promoting the ownership model to production, review native ownership/failure contracts and test real handle invalidation, domain synchronization, native outer-frame leases, fd ownership, asynchronous races, and failure recovery. Independent peer interoperability, instrumented libwayland, production soak tests, performance benchmarks, and human code review remain required.

## Subsequent milestone scope

The user subsequently deferred aarch64 validation and authorized the actual ownership runtime on x86_64. That implementation and its separate package test results are documented in <doc:OwnershipRuntime>. The original phase 1 experiments and two-architecture evidence limits remain historical facts; they do not block the explicitly authorized x86_64 milestone.
