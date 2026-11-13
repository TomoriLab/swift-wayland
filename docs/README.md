# WaylandKit design

Status: ownership runtime with staged client/server and generator implementation on x86_64 Linux; aarch64 validation is deferred by user instruction. Baseline date: 2026-11-14.

WaylandKit will provide a memory-safe Swift interface to the complete public libwayland surface. Safety takes priority over avoiding a copy or preserving an unsafe C calling convention. Performance requirements are measured against an equivalent C program rather than assumed from the language or ownership model.

The design targets Swift 6.4.2 in Swift 6 language mode and libwayland 1.26.0 on Linux x86_64 and aarch64. These are initial supported baselines, not claims of compatibility with every older library. Future public API additions require an inventory update. Swift 6.4.2 is an official release; after `source ~/.zshrc`, the shell function `swift` invokes Swiftly and reports Swift 6.4.2 targeting x86_64-unknown-linux-gnu. Without that shell initialization, PATH resolves the unrelated OpenStack python-swiftclient 4.11.0. DocC from the Swiftly 6.4.2 toolchain successfully converts the conceptual catalog with warnings treated as errors. Selected ownership, Span, concurrency, and native ABI patterns now have executable probes; broader production and aarch64 validation remain outstanding. [Swift 6.4.2 announcement](https://forums.swift.org/t/announcing-swift-6-4-2/90337), [Wayland releases](https://wayland.freedesktop.org/releases.html).

## Reading order

1. [Architecture](WaylandKit.docc/Architecture.md): scope, modules, API shape, language feature policy.
2. [Ownership and FFI](WaylandKit.docc/OwnershipAndFFI.md): destruction, callbacks, file descriptors, shared memory.
3. [Mathematical model](WaylandKit.docc/MathematicalModel.md): invariants, transitions, proof obligations.
4. [Dispatch and concurrency](WaylandKit.docc/DispatchAndConcurrency.md): prepared reads, executor confinement, cancellation.
5. [Protocol generation and coverage](WaylandKit.docc/ProtocolGeneration.md): complete mapping and generation contracts.
6. [Documentation contract](WaylandKit.docc/Documentation.md): DocC organization and required API documentation.
7. [Validation and delivery](WaylandKit.docc/Validation.md): safety, leaks, performance, implementation gates.
8. [Decision register](decisions.md): decisions, rejected alternatives, unresolved validation.
9. [Memory-safety review](WaylandKit.docc/SafetyReview.md): ownership gaps, corrections, and remaining evidence gates.
10. [Swift toolchain validation](WaylandKit.docc/ToolchainValidation.md): executable capability and ownership probes.
11. [Descriptors and callbacks](WaylandKit.docc/DescriptorsAndCallbacks.md): implemented FD transfer, receive cleanup, and detachable userdata lifetime.
12. [Ownership runtime](WaylandKit.docc/OwnershipRuntime.md): implemented package-level contracts and runtime tests.
13. [Permanent proxy dispatcher](WaylandKit.docc/ProxyDispatcher.md): nonremovable context, cancellation, and local destruction.
14. [Client and server slices](WaylandKit.docc/ClientAndServer.md): read coordination, native cascades, and idle sources.
15. [Implementation progress](WaylandKit.docc/ImplementationProgress.md): completed work and remaining release gates.
16. [C API inventory](reference/api-inventory.md) and [core protocol inventory](reference/core-protocol-inventory.md).

The DocC catalog is rooted at [WaylandKit.docc](WaylandKit.docc/WaylandKit.md). It combines conceptual articles with package-access symbol graphs for WaylandRuntime, WaylandClient, WaylandServer, and WaylandProtocol. Independent C peer tests and the schema scanner exist; application-facing APIs, complete typed bindings, tutorials, and CI remain incomplete. The Markdown reference inventories and generated JSON coverage manifest remain adjacent to the catalog. See [ImplementationProgress](WaylandKit.docc/ImplementationProgress.md) before interpreting a generated schema or imported header as completed API coverage.

## Acceptance contract

| Requirement | Design artifact | Implementation acceptance |
|---|---|---|
| Memory safety first | OwnershipAndFFI; MathematicalModel | Compile-fail lifetime tests; runtime invalidation and sanitizer tests |
| Preserve performance | Architecture; Validation | Equivalent C/Swift benchmarks with recorded allocation and latency data |
| Maintainability | Architecture; ProtocolGeneration | Single ownership runtime and generator manifest; no per-interface lifetime logic |
| Detailed DocC | Documentation | Every public symbol has a contract, examples, and source mapping |
| All libwayland functionality | Reference inventories; ProtocolGeneration | Zero unclassified public declarations or protocol messages |
| Swift 6.4.2 features | Architecture feature policy | Positive and negative feature probes on the exact toolchain |
| No library-owned leaks | MathematicalModel; Validation | Balanced resource ledgers and clean repeated lifecycle tests |
| Mathematical model | MathematicalModel | Traceable invariant IDs and model-derived tests |

A design obligation is not a verified property. The current change establishes the obligations and the planned validation, not a proof that future code is memory-safe or leak-free. Human review is required before implementation changes are accepted.

The 2026-11-13 follow-up review separates native attachments from subscriptions, native frames from callbacks, and cleanup records from reference cells. Safety obligations now cover M1–M19 and review scenarios SR1–SR18. Repository instructions are maintained in AGENTS.md.
