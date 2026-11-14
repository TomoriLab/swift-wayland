# Ownership runtime implementation

Track real release obligations independently of handles and defer native free until the outer synchronous invocation completes.

## Milestone and supported scope

The user explicitly deferred aarch64 validation and authorized the x86_64 implementation. Phase 2 now has an actual SwiftPM WaylandRuntime target and a small CWaylandRuntime synchronization target. Client/server, protocol, and advanced adapters now share this public runtime product. The client-first WaylandKit facade reuses its ownership types without adding an independent lifetime model.

The supported execution environment is Swift 6.4.2 on x86_64 Linux. aarch64 remains deferred and unverified. The runtime has no third-party package dependency. It uses libc/pthread for bookkeeping synchronization; only the native test fixture links libwayland-server. The original Tests/Toolchain experiments remain separate.

## Ownership and identity

| Type | Authority | Lifetime and behavior |
|---|---|---|
| OwnershipSession | Noncopyable root authority | Explicit or fallback close invalidates the session even if child cells survive |
| OwnedHandle | Noncopyable record authority | Borrowing requestClose supports callbacks; consuming close and deinit share one arbiter |
| ObjectHandle | Copyable checked reference | Retains bookkeeping without acquiring native destruction authority; no pointer getter |
| HandleIdentity | Sendable copied metadata | Session, monotonic generation, native identifier, and namespace; does not authorize access |
| CleanupRecord | Internal authoritative obligation | Retained by the control independently of weak or absent handle cells |
| RuntimeControl | Non-Sendable mutable runtime | Logical single-thread admission, dependency graph, release arbitration, and deferred drain |
| RuntimeMutex | Narrow audited synchronization primitive | Private native pointer and Sendable value; no runtime object gains Sendable conformance |

Native identifiers are unique per HandleKind within one session. Retiring and registering the same native identifier produces a new generation; an old ObjectHandle cannot become valid again. Session IDs are allocated by a process-local pthread-protected counter. Both counters reject exhaustion rather than wrapping. This identity is unrelated to protocol serial wrapping.

A successful unsafe adoption creates the sole cleanup record. Duplicate identity, foreign/dead dependency, exhausted generation, capacity, and closed-session failures leave native ownership with the caller and do not invoke the supplied action. The adapter must own the native resource and verify the native success/failure contract before adoption. A failed native factory is not converted into a record.

Cleanup captures must not strongly retain their owning session or cells, form ownership cycles, or independently destroy the target allocation when the closure itself is discarded. The release action is nonthrowing and must be valid on any serialized caller thread. Thread-affine resources are excluded from this initial adapter contract. Adoption and native destruction notification are explicitly unsafe public operations because the runtime cannot inspect or prove these native facts.

## State machine and destruction arbitration

```text
live --owner/root/prerequisite close--> closing
closing --quiescent leaf drain--> runtimeReleasing --action returns--> retired
live/closing --proven native destruction--> nativeConsumed --quiescence--> retired
live --explicit ownership handoff--> transferred --quiescence--> retired
```

A native notification during runtimeReleasing observes the already claimed action and cannot claim it again. A duplicate notification after retirement returns false. nativeConsumed discharges the native obligation immediately but retains captured bookkeeping until the outer frame returns. The associated native identifier remains reserved until that retirement, preventing a new generation from sharing still-reachable callback context storage.

Native notifications require an existing enclosing native frame and a leaf with no retained dependents. Automatic native cascading destruction of unknown children is not inferred. The server adapter has a separate, source-audited operation for client/resource subtrees described in <doc:ClientAndServer>. A child notification retains its cleanup record until frame exit, so simply reporting children first inside the same native call does not satisfy this condition. Other parent cascades with retained children remain unsupported and require a dedicated audited cascade operation before those adapters are exposed. The runtime cannot pin an allocation that an external native owner has already freed.

## Dependency order

New records may depend only on already live records in the same session. This construction order produces a directed acyclic graph without a separate cycle-breaking algorithm. Dependencies are deduplicated. Closing a prerequisite invalidates and closes its entire dependent subtree.

The ready queue contains closing or native-consumed records with no remaining dependents. Retiring a leaf updates its prerequisites and makes eligible parents ready. All mutation is performed under logical execution ownership, and native actions run outside the bookkeeping mutex. Sibling release order is unspecified; the dependent-before-prerequisite partial order is required. A tested diamond releases its shared leaf once and a tested 1,000-record chain releases in reverse dependency order.

## Admission, reentrancy, and deferred release

Admission records the current pthread identity and nested entry count under a short native mutex. Another thread cannot inspect or mutate records and receives domainBusy for ordinary access. Same-thread reentrancy can issue permitted operations without recursively locking a held bookkeeping mutex. No bookkeeping lock spans user code, native dispatch, or a cleanup action.

Close may be posted by a foreign thread as value-only work. A root-close request publishes a permanent shutdown bit so new access is rejected. The admitted thread applies pending transitions and drains them before surrendering the domain; the final mailbox check and relinquishment use the same mutex. No task, executor, wake descriptor, or thread-affine queue is needed for this synchronous milestone. Poll wakeup and asynchronous coordination remain future work.

withNativeFrame protects the complete native call, including native instructions executed after a Swift callback returns. ObjectHandle.withAccess validates identity/kind and adds another frame around a synchronous operation. When a handle retains its matching RecordLifetime, admission checks its monotonic live flag under the domain lock instead of looking up the record by generation. Every transition away from live clears that flag before record retirement; handles without a lifetime still use the authoritative record lookup, while a mismatched lifetime is rejected. Close invalidates new access immediately but physical release waits until the global session frame depth is zero. This initial implementation conservatively defers all session releases while any frame remains active, including unrelated records.

A native cleanup action is itself treated as a native frame. Reentrant destruction callbacks can request root close or report native destruction without releasing prerequisites while the original destructor still uses them. Logical close may return deferred inside a callback. Outside active frames, an idle caller drains synchronously. Every throwing body exits its frame through defer.

## Synchronization implementation and sanitizer boundary

An initial implementation used Synchronization.Mutex. On this installed Swift 6.4.2 toolchain, TSan also reported races for an isolated counter protected exclusively by that standard primitive, independently of the ownership runtime. The runtime now consistently uses a small pthread mutex adapter so the same synchronization is visible to TSan in debug and release configurations. This is a local reproducer result, not a claim that all standard-library Mutex implementations are incorrect.

RuntimeMutex is the only production unchecked Sendable conformance. Its Value is constrained to Sendable, its native allocation is private, all value access occurs between pthread lock/unlock, and an active method retains the wrapper through unlock. It is marked @safe because the pointer storage is encapsulated; each raw operation inside is explicitly marked unsafe. RuntimeControl, owners, handles, and release closures remain non-Sendable.

| Boundary | Provenance and ownership | Terminal behavior and verification |
|---|---|---|
| Mutex constructor | C malloc plus pthread_mutex_init; writes a scoped Int32 error slot | Partial initialization failure frees C storage and throws synchronizationUnavailable |
| Mutex lock/unlock | Private initialized mutex retained by the method | Unexpected pthread failure terminates before unprotected state access |
| Mutex destruction | Last Swift wrapper reference with no surviving method lease | pthread_mutex_destroy must succeed before free |
| Mutex value storage | One private, typed, initialized Swift allocation with capacity one | Last wrapper release deinitializes the value exactly once and deallocates its slot after native mutex destruction |
| Session allocator | Static C counter and static pthread mutex | Returns zero on UInt64 exhaustion; no dynamic native allocation |
| Unsafe native adoption | Caller-proven exclusive native ownership and thread-compatible action | Ownership transfers only after record publication |
| Native destruction notification | Caller-proven leaf destruction inside a native frame | Never invokes that leaf's native release action again |

The mutex value resides in one fixed `UnsafeMutablePointer<Value>` slot owned only by its wrapper. The typed allocator supplies size and alignment; initialization occurs after native mutex creation and before publication. Every pointee access acquires the same nonrecursive pthread mutex. The `inout` closure remains synchronous and nonescaping, the slot pointer is never exposed, and no successful operation changes its address. This replaces stored-property dynamic exclusivity tracking with the existing mutex's exclusive-access guarantee; it does not remove locking or relax `Value: Sendable`. Same-mutex recursive locking remains prohibited. An explicit `withExtendedLifetime(self)` after unlock and native-frame restoration retains the wrapper until each scope has finished using its pointers, even when the body removes the last external reference. Final deinitialization cannot overlap a legal access. Final release destroys the native mutex, deinitializes exactly one value, and deallocates the slot. A failed native constructor creates no slot; fatal Swift allocation failure retains the project's process-termination boundary. This adds one allocation at wrapper construction and none per lock operation.

These storage obligations preserve M1, M3–M4, M9–M10, and M14. `RuntimeMutexTests` verifies mutation followed by a thrown error, 1,000 concurrent increments after that error, exactly-once retirement of a reference-bearing payload after wrapper aliases leave scope, and last-external-reference removal inside both normal and throwing lock bodies. Native address/thread sanitizer runs provide separate evidence for use-after-free, leaks, and cross-thread accesses. No unchecked conformance, public pointer, or suppression is added.

The bridge fault fixture compiles the production synchronization constructor with isolated allocator and pthread-initializer substitution. It verifies ENOMEM without an allocation, EAGAIN after allocation with immediate rollback, and successful lock/unlock/destruction with zero outstanding tracked allocations. This exercises C rollback rather than forcing an actual host allocator or pthread resource exhaustion. Unexpected lock/unlock/destroy failures are treated as internal invariant violations. Arbitrary callbacks that never return, process termination, unsafe adapter contract violations, and externally destroyed uncoordinated resources remain outside cleanup liveness guarantees.

## Executable validation

The runtime tests exercise externally observable behavior rather than comparing private implementation fields. Selected tests use @testable access for generation exhaustion and deliberate cross-thread calls; a test-only unchecked transfer wrapper bypasses static isolation to verify domainBusy and mailbox behavior. It is not a production Sendable escape hatch.

| Scenario | Evidence |
|---|---|
| Copied references, fallback close, root drop | All old references reject access; live child authority cannot keep a closed session usable |
| Lost last cell inside a frame | The weak cell disappears while its authoritative record and obligation remain until drain |
| Nested frames and throw | No action before outermost return, including exceptional exits |
| Dependency graph | Diamond and 1,000-record chain release in dependent-first order without duplicate cleanup |
| Identifier/kind/session checks | Duplicate, stale generation, foreign dependency, and wrong-kind access are rejected |
| Native-consumed resource | Immediate invalidation, delayed capture release, no second native destructor |
| Reentrant native destructor | Notification, root close, and snapshot do not deadlock or double-release |
| Real Wayland idle dispatch | C code touches its live resource after Swift requests close; physical free occurs only after native dispatch returns |
| Foreign thread and concurrent close | Ordinary access is rejected; 500 simultaneous close requests converge to one release |
| Resource accounting | 10,000 create/close cycles finish with zero records and balanced obligations |
| Bounded state traces | All 256 four-event traces over close/root-close/native-notification/access preserve the tested conservation relation |
| Swift API ownership | Actual package-module compiler probes reject double consumption, owner copying, reference close, Sendable capture, and unmarked unsafe adoption |

The tested accounting relation is acquisitions = runtimeReleases + nativeReleases + transfers + outstandingObligations. Retained native-consumed records are counted separately until callback captures become unreachable. These tests are not a proof of all M1–M19 invariants or all native APIs.

## Reproduction

Run from the repository root after initializing the configured Swift environment:

```sh
source ~/.zshrc
swift test --disable-xctest -Xswiftc -warnings-as-errors
swift test -c release --disable-xctest -Xswiftc -warnings-as-errors
python3 Scripts/verify-runtime-ownership.py
ASAN_OPTIONS=detect_leaks=1:halt_on_error=1:abort_on_error=0:exitcode=23 LSAN_OPTIONS=exitcode=23 \
  swift test --scratch-path .build/runtime-address --disable-xctest --sanitize address -Xswiftc -warnings-as-errors
TSAN_OPTIONS=halt_on_error=1:exitcode=66 \
  swift test --scratch-path .build/runtime-thread --disable-xctest --sanitize thread -Xswiftc -warnings-as-errors
```

The tests use Swift Testing only. The initial default runner also invoked an empty XCTest suite that reported 432 bytes of XCTest-owned leaks before Swift Testing executed. --disable-xctest avoids that unrelated runner path while keeping leak detection enabled; no suppression file or sanitizer exclusion is used. Swift sources, the C synchronization shim, and the C native test fixture are instrumented. Ordinary runs use system libwayland. Additional isolated ASan/TSan native builds are verified as described below.

## Recorded results

| Check | Result |
|---|---|
| Swift Testing, debug and release, warnings as errors | 68 tests passed in each configuration |
| AddressSanitizer with leak detection and no suppressions | 68 tests passed |
| ThreadSanitizer with halt on error and no suppressions | 68 tests passed |
| Actual module ownership compiler matrix | 24 runtime results and eight concrete-client results passed |
| Package-access symbol graph and DocC | 275 documented symbols matched rendered pages across four modules; 361 combined pages; warnings as errors passed |

The separate minimal standard-Mutex reproducer initially returned TSan exit code 66; it is not counted as a runtime pass. The earlier XCTest-runner leak is not counted as clean leak evidence. The final commands use the documented pthread primitive and Swift Testing-only runner with leak detection enabled.

## Limits and next steps

FD owners, detachable/permanent contexts, typed core client/server bindings, and advanced owners are implemented. See <doc:DescriptorsAndCallbacks>, <doc:ClientAndServer>, <doc:TypedProtocol>, and <doc:AdvancedAPIs>. Repeated SHM increments use distinct retained obligation-storage identities. Native byte-array views enforce backing identity and expiry. Cursor file loading and external EGL driver integration retain explicit unsafe trust contracts. Owned dynamic metadata arenas are implemented as independent immutable owners; managed consumer integration and optional asynchronous transports remain separate work. Record and wire quotas do not prove arbitrary foreign native integrations bounded. User-created capture cycles require weak references or explicit owner/root closure. Current quantitative and cross-architecture limits are recorded in <doc:ImplementationProgress>.

## Cached callback admission

An authoritative record owns a separate RecordLifetime token. Every transition away from live clears its monotonic live bit. The token retains only the existing synchronization primitive and Sendable mailbox state. It has no edge to RuntimeControl, a cleanup record, an owner, or a native allocation. Handle cells and copied-identity observers can share it without granting another destruction authority.

A C thread-local native-frame identity proves the current OS thread still holds this exact runtime's admitted outer native invocation. Nested unrelated runtime frames restore the previous identity on every exit. Callback admission first verifies that identity and checks the sequentially consistent pending-close notification. One native check distinguishes active delivery, canceled delivery requiring mandatory cleanup, and a pending-close or foreign-frame fallback that needs authoritative admission. A clean notification permits the cached live check; a pending close consumes authoritative mailbox transitions before any delivery. Foreign producers publish under the existing mutex and set the notification before unlocking; consumers clear it only under that mutex. No callback/user cleanup runs under the mutex.

Swift callback return creates no independent native quiescence boundary. Its complete outer C frame remains retained throughout delivery and subsequent native instructions. Tests cover foreign close publication before delivery, rejection outside a native frame, restoration after nested runtime frames, invalidation, and native code continuing after callback return. The optimization preserves M2/M3/M9/M10/M13/M15 and does not turn a cached token into native ownership.

## Root-managed obligations

OwnedHandle.surrenderToRoot() consumes the local closing token and returns only a checked reference. The authoritative root already owns the cleanup record. Surrender neither creates another acquisition nor transfers an obligation outside the runtime; acquisition/release/transfer counters remain unchanged. Dropping the returned reference does not close the record. Root closure and native destruction still discharge it exactly once. This supports accepted native server clients and self-detaching resource watches whose lifetime must not depend on an application retaining a temporary Swift owner. The root-surrender regression verifies both the unchanged ledger and eventual single release.

## Instrumented native verification

`python3 Scripts/verify-instrumented-runtime.py --sanitizer address` builds pinned libwayland 1.26.0 under .build and runs the Swift/C wrapper with leak detection enabled. Instrumented client and server libraries run in separate variants because both export the same protocol metadata and loading both instrumented definitions together triggers the sanitizer's ODR check. Cursor/EGL instrumentation accompanies each variant. No ODR check, native memory check, or leak check is suppressed. Loader diagnostics confirm each requested local library initialized.

`python3 Scripts/verify-instrumented-runtime.py --sanitizer thread` runs separate TSan configurations and loads the isolated native client/server/cursor/EGL set together. The native build's TSan link probe explicitly locates the toolchain dispatch and BlocksRuntime libraries. Source/build/install prefixes remain in .build; no host native library is replaced. `python3 Scripts/verify-lifecycle-soak.py --sanitizer address` separately runs 10,000 complete lifecycles in each native address variant and checks record/FD retirement plus exit-time leak instrumentation.

The native archive SHA-256 is 56b3a985cbfe17a926e3bcf037e4d374f44eaa33f3a4b364549dddf0d324cebc. This records review inputs rather than cryptographic publisher authentication. Its XML matches the pinned Protocols/wayland.xml. Verification JSON and loader logs record the actual native variants. Valgrind is not installed and has not been run.

An earlier release benchmark exposed a Swift 6.4.2 cross-module LLVM verification failure for a private dispatcher context through a generic noncopyable owner. Module-internal context visibility resolved it without disabling compiler checks. The release executable and external public consumers continue to cover that configuration. Quantitative throughput acceptance remains distinct from successful release compilation.

## Domain-exit close race

Domain exit synchronizes published close requests and drains ready records outside the admission mutex. Before releasing the outermost domain claim, it rechecks the pending mailbox under the same mutex used by close publishers. A pending root or record close causes exit to repeat synchronization and draining. A nested exit preserves the enclosing domain claim. Cleanup and callbacks never run under the admission mutex.

`finalDomainExitDoesNotLoseRacingRootClose` races a foreign root-close publisher against 500 final access exits and checks the release count before any snapshot or explicit drain can hide stranded work. Existing foreign-close, nested-frame, readiness, reentrant-destruction, and model-trace tests cover related slow paths. This finite stress test supports M2, M9–M10, and M13 without exhausting all thread interleavings.
