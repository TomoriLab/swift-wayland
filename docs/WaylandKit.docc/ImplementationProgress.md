# Implementation progress and open delivery gates

Distinguish executable implementation from schema metadata and complete native coverage.

## Current delivery state

The permanent proxy dispatcher and its lifetime tests are implemented. The subsequent work now includes client connection/registry/sync/queue/read coordination, a server ownership/idle-source slice, deterministic core schema generation, an executable native API inventory, isolated native instrumentation, and a dispatcher benchmark. The complete phase 0–7 plan is not finished.

| Phase | Implemented evidence | Remaining exit obligations |
|---|---|---|
| 0: design review | Ownership model, unsafe boundaries, source contracts, and repository policy | Human review of the current patch |
| 1: toolchain and ABI | Swift 6.4.2 x86_64 compiler and native ABI probes | aarch64 remains deferred by user instruction |
| 2: ownership runtime | Handles, records, deferred cleanup, FD ownership, detachable and permanent contexts; failure and sanitizer tests | Human review; broader allocation failure injection |
| 3: client slice | Socket connection, registry, sync, assigned queue, prepare/read/cancel, poll wake cancellation, shutdown; independent C server tests | Named compositor path, structured protocol-error snapshots, EAGAIN/EINTR fault injection, optional async coordination |
| 4: server slice | Display, connected client, resource, native destruction watches/cascades, idle source, shutdown; independent C client test | Globals/offers, filters, fd/timer/signal sources, request implementations, iteration/loggers and their lifetime tests |
| 5: generator and coverage | Pinned XML, validated IR, deterministic Swift schema for 23 interfaces/134 messages, native scanner equivalence; Clang/preprocessor/export inventory | Typed request/event methods and constructor/destructor decoders; complete implemented/documented/tested mapping |
| 6: advanced APIs | Native declarations are inventoried | Cursor/EGL owners, guarded SHM, logging, utilities and unsafe/deprecated compatibility adapters |
| 7: documentation and performance | DocC contracts, scalar dispatcher benchmark, native lifetime soak tests, native instrumentation workflow | Complete tutorials, visual inspection, equivalent typed C/Swift workloads (the observation comparison is documented in <doc:DispatcherBenchmark>), allocation/latency distributions, representative compositor and complete soak matrix |

## Coverage accounting

Scripts/verify-api-coverage.py combines Clang AST declarations, preprocessor macros, dynamic exports, and the pinned XML. The current snapshot contains 452 functions and 1,535 total declaration/macro/message items. Thirty function mappings are recorded as implemented. All remaining records remain explicitly unmapped. Schema generation does not mark a protocol message as an executable binding. Test-file references are review pointers, not a claim that every native branch has been exercised.

The native inventory is stored in docs/reference/native-api-coverage.json. It deliberately reports releaseGatePassed=false. Raising that flag requires every baseline item to have an implemented contract and adequate documentation/tests; importing a C header or generating a schema is insufficient.

## Generator boundary

Protocols/wayland.xml is pinned with SHA-256 cc860987e54f8d85c940e97fa1270c69b6e4ad31fbcf5a7f00107ce1157f5e07 and retains its upstream copyright/license. The host generator uses the Python standard library. It accepts UTF-8 XML and rejects alternative encodings, DTD/entities, oversized input, unknown semantic elements/attributes, invalid nesting, duplicate names, unknown type/interface/enum references, invalid nullability, and inconsistent version order. It preserves source opcode order, constructors, destructor flags, enum bits, and source descriptions in the IR. Copyright is emitted as line-comment data; an adversarial copyright fixture is compiled with the actual Swift compiler to reject source injection.

Generated Swift metadata includes every core interface, request, event, argument, enum, and enum entry. It uses initialized owned values and retains no native pointer. requireAvailable rejects a message newer than the negotiated interface version; raw enum values are not forced into a closed Swift enum. Scripts/verify-protocol.py checks deterministic regeneration and compares all 134 native scanner message names, opcode positions, and expanded signatures, including generic new_id expansion.

The generator currently handles one self-contained protocol XML. Imported extension interfaces, complete descriptive metadata rendering, generated executable bindings, schema-driven ownership-taking event decoding, dynamic metadata arenas, fuzzing campaigns, and full declaration-level behavior coverage remain open. Native special helpers can encode ownership effects beyond a simple XML destructor flag; those require source-audited manifest rules before typed code generation.
