# Documentation contract

Make ownership, failure, and execution requirements part of every public API description.

## Catalog organization

The current design catalog lives in docs/WaylandKit.docc. Conceptual articles are authored here before implementation. Once Swift package targets exist, attach this catalog to the umbrella documentation build and provide per-module catalogs or generated module landing pages for client, server, cursor, EGL, and unsafe APIs. Do not maintain two editable copies of the same article.

DocC compiles documentation from Markdown catalogs and symbol information. The official documentation is the reference for article directives and publication. [Swift DocC](https://www.swift.org/documentation/docc/), [Swift-DocC source and usage](https://github.com/swiftlang/swift-docc).

During implementation, create symbol comments alongside public declarations. Put long explanations, state machines, migration guides, and tutorials in catalog articles. Generated comments use the same intermediate representation as API generation. A manually maintained overlay adds safety contracts without editing generated output.

## Required symbol contract

Every public symbol, including unsafe and deprecated symbols, must document these fields where applicable:

| Field | Required detail |
|---|---|
| Summary | Operation and observable result |
| Native mapping | C function/type/macro or XML interface/message and supported version |
| Ownership | Borrowed, owned, shared native ref, consumed, or transferred |
| Lifetime | Transitive dependencies, backing aliasing, invalidation triggers, and compiler-enforced view restrictions |
| Execution | Domain, callback execution context, reentrancy, and suspension restrictions |
| Parameters | Units, range, nullability, byte encoding, interface identity |
| Return | Ownership, initialized extent, sentinel translation |
| Errors | Native errno/protocol errors, local argument errors, rollback behavior |
| Destruction | Local versus wire destructor, logical close versus physical free, outer-frame quiescence, explicit close and fallback |
| Descriptor behavior | Who closes on success and on every failure path |
| Complexity | Time complexity, allocation, copy and synchronization behavior |
| Safety | Preconditions for unsafe operations and invariant IDs |
| Examples | Valid lifecycle and a relevant failure or cancellation path |
| Availability | Swift baseline, native baseline, protocol since-version and deprecation |

Typed throws documentation must identify the failure set. If an error preserves errno, snapshot it immediately rather than after unrelated allocations or native calls. Protocol errors include interface/object/code information copied before teardown. Do not turn native error strings into stable machine-readable error identifiers.

## Proposed documentation example

This is a documentation template, not a declaration that has been compiled:

```swift
/// Dispatches events already pending on this connection's selected queue.
///
/// This operation runs callbacks synchronously in the connection's execution
/// domain. A callback may issue requests but must not recursively dispatch.
/// Callback argument views expire when their handler returns.
///
/// - Returns: The number of dispatched events according to the native API.
/// - Throws: A connection error if the native operation fails, or a local
///   state error if the connection is closed or has an active read reservation.
/// - Important: This operation does not imply that outgoing requests have
///   reached the server.
///
/// Native mapping: `wl_display_dispatch_pending`.
/// Ownership: The connection is borrowed; no resource ownership transfers.
/// Safety invariants: M2, M3, M9, M10, M15, and M16.
```

Before using this template in implementation, reconcile return-value and error wording with the exact pinned native operation. Documentation templates must not manufacture stronger guarantees than the C API or runtime provides.

## Tutorials and guides

| Guide | Required scenarios |
|---|---|
| Connect and enumerate globals | Connect failure, registry, version negotiation, ordered cleanup |
| Submit a shared-memory buffer | Allocation, checked extents, buffer release and reuse |
| Dispatch with an existing event loop | Prepared reads, EAGAIN, timeout, cancellation |
| Implement a minimal server | Display, socket, client, resources, protocol errors, shutdown |
| Add a protocol | XML, generation, native mapping, independent C peer validation |
| Integrate cursor and EGL | Borrowed theme buffers, animation units, surface/window ordering |
| Cross an async boundary | Explicit snapshots, capacity limits, cancellation |
| Interoperate with native libraries | Borrow versus adoption, reserved userdata, explicit unsafe scope |
| Diagnose resource leaks | Ledgers, registration cycles, fd counts, reproducible traces |
| Migrate from libwayland C | Full function index, deprecated aliases and ownership differences |

Each tutorial includes complete buildable source, prerequisites, tested toolchain/native versions, expected output, failure handling, and deterministic cleanup. Server/client fixtures run without a user's desktop where possible. Generated code examples must be compiled in CI rather than accepted because they render in DocC.

## Documentation build and publication gate

The package has WaylandRuntime, WaylandClient, WaylandServer, and WaylandProtocol targets. Scripts/build-documentation.py extracts package-access symbol graphs, rejects undocumented symbols, builds each module separately, verifies rendered symbol IDs, and merges the archives. The current build covers 275 documented symbols and 361 combined pages. Conceptual articles come from one source catalog and are copied into isolated per-module build inputs; their namespace differs by module.

```sh
source ~/.zshrc
python3 Scripts/build-documentation.py
```

The combined archive is .build/documentation/WaylandKit.doccarchive. Per-module archives and a machine-readable verification report remain alongside it. The script uses the bundled DocC dependency-link metadata feature for runtime types referenced by client/server APIs, then merges the four archives. The selected DocC accepts the feature flags; no experimental Swift language flag or DocC plugin dependency is added.

The bundled converter rejects multiple main modules in one conversion. An earlier conceptual-catalog fallback name also triggered an internal precondition. The verified workflow therefore uses one main module and matching fallback name per invocation. Empty executable symbol graphs are excluded. Generated documentation remains ignored by Git. Programmatic rendering/link verification does not replace the outstanding visual desktop/narrow-width review or complete tutorial compilation gate.

The intended pipeline is: build module → extract symbol graphs → compile DocC with warnings treated as errors → build tutorial examples → inspect landing pages, topic links, ownership tables, and unsafe warnings → publish a versioned static archive. The package phase may use `swift package generate-documentation` only after the corresponding plugin is explicitly present; it is not assumed to be a built-in command in the current repository.

Release gates require all public symbols to be documented, all coverage IDs to resolve, no broken internal references, no unexpected DocC diagnostics, and no unverified safety claims. Inspect at least client, server, and unsafe module pages at desktop and narrow widths. Keep design status distinct from released API availability.
