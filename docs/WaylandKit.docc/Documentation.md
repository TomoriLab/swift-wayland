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

The package now contains the actual WaylandRuntime target. Package-access symbol graphs are extracted with SwiftPM and combined with this catalog using bundled DocC; no DocC plugin dependency is installed. The current build renders 143 pages, including all 121 extracted runtime symbols. Every extracted symbol has a documentation comment. Symbol external IDs were checked against generated page metadata. Visual inspection remains outstanding.

The verified local workflow, run from the repository root, is:

```sh
source ~/.zshrc
swift package dump-symbol-graph --minimum-access-level package
mkdir -p .build/runtime-documentation
"${SWIFTLY_BIN_DIR:-$HOME/.local/share/swiftly/bin}/swiftly" run docc convert docs/WaylandKit.docc \
  --additional-symbol-graph-dir .build/out/symbolgraph \
  --output-dir .build/runtime-documentation/WaylandRuntime.doccarchive \
  --fallback-display-name WaylandRuntime \
  --fallback-bundle-identifier org.tomorilab.WaylandKit \
  --warnings-as-errors
```

The symbol graph path is the observed Swift 6.4.2 Swift Build output layout. Future build tooling must resolve the corresponding output path when using a different backend. The archive is ignored by Git. No generated archive is committed.

The bundled DocC failed an internal precondition when the fallback display name was WaylandKit, matching the existing conceptual article. The same graph and catalog convert successfully with the fallback display name WaylandRuntime. Use the verified module name rather than the earlier standalone conceptual-catalog command. This is a documentation tool/configuration finding and does not change source API access levels.

The original conceptual-only catalog had nine pages and was later extended to ten for toolchain validation. The current catalog includes a module documentation extension and requires the symbol graph in the command above. Swift source examples still require their own compilation checks; producing a page does not prove its example executes correctly.

The intended pipeline is: build module → extract symbol graphs → compile DocC with warnings treated as errors → build tutorial examples → inspect landing pages, topic links, ownership tables, and unsafe warnings → publish a versioned static archive. The package phase may use `swift package generate-documentation` only after the corresponding plugin is explicitly present; it is not assumed to be a built-in command in the current repository.

Release gates require all public symbols to be documented, all coverage IDs to resolve, no broken internal references, no unexpected DocC diagnostics, and no unverified safety claims. Inspect at least client, server, and unsafe module pages at desktop and narrow widths. Keep design status distinct from released API availability.
