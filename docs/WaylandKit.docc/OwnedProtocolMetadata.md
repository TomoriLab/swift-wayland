# Imported XML and owned native metadata

Generate external value schemas and retain a bounded, immutable native descriptor graph through every native consumer.

## Generator input contract

The host generator accepts one primary XML and explicit imports. It resolves interface and qualified enum references across the complete set before validating each document. Forward and cyclic cross-file references are supported without reordering requests or events. Duplicate interface/protocol definitions, missing imports, unknown semantic attributes, unsupported encodings, DTD/entity declarations, invalid nullability, generic event constructors, and native signed-version overflow are rejected.

Each document is limited to four MiB. A bundle contains at most 64 documents, sixteen MiB of source bytes, and 4,096 interfaces. The manifest records every input SHA-256 and a length-delimited, order-sensitive aggregate hash. Input order determines interface order; message source order remains opcode order. Upstream copyright text is preserved in generated source comments.

```sh
python3 Scripts/generate-protocol.py \
  --xml Protocols/Fixtures/xdg-shell.xml \
  --import Protocols/wayland.xml \
  --output-directory .build/generated-xdg \
  --namespace XdgShellProtocol
```

The output contains `XdgShellProtocol.swift` and `protocol-manifest.json`. The Swift file imports WaylandProtocol and exposes immutable schema values. Place it in a consuming target that depends on the WaylandProtocol product. Add `--check` to verify byte-identical output without rewriting files. No target executable runs during generation and no production XML parser dependency is added.

Generate client/server typed facades from the same primary XML and import set:

```sh
python3 Scripts/generate-extension-bindings.py \
  --xml Protocols/Fixtures/xdg-shell.xml \
  --import Protocols/wayland.xml \
  --output-directory .build/generated-xdg \
  --namespace XdgShellProtocol
```

The additional `XdgShellProtocolBindings.swift` belongs in a target depending on WaylandClient, WaylandServer, WaylandProtocol, and WaylandRuntime. The generator emits wrappers for the five primary xdg-shell interfaces and uses all 28 imported definitions for schema admission. It emits noncopyable client/server owners and owned event/request sums, checked reference methods, open enum values, typed constructor targets, registry bind helpers, and server global bind identifiers. Interface-generic object fields remain checked erased references. Native wire encoding and callback cleanup continue through the managed dynamic adapters. `--check` verifies byte-identical output.

Generated value metadata does not add external types to CoreProtocol.requireSchema. Exact core marker admission remains unchanged. Typed extension facades consume managed dynamic owners only after matching the complete reachable descriptor graph.

## Arena ownership and publication

ProtocolDescriptorBundle validates complete value schemas before native allocation. Public schema initializers create data values only; they do not grant pointer authority. Native interface versions fit Int32, opcodes are consecutive, message introduction versions are monotonic, enum references resolve, and each message has at most twenty expanded arguments. Generic request constructors contribute their implicit string and version slots. Generic event constructors are rejected because their native interface cannot be inferred safely.

The C arena allocates interface records, message records, copied names/signatures, and type-pointer arrays. One allocation ledger owns every block immediately. A failed name/table allocation destroys the entire unpublished arena. Forward and cyclic type pointers refer only to storage in that arena and introduce no Swift retain cycles. Sealing verifies complete initialization and prevents further builder mutation. The configured byte bound includes arena/block bookkeeping and cannot exceed sixteen MiB.

```swift
import WaylandProtocol

func makeDesktopDescriptors() throws -> ProtocolDescriptorBundle {
    try ProtocolDescriptorBundle(interfaces: XdgShellProtocol.interfaces)
}
```

An interface lookup returns a ProtocolDescriptor that strongly retains the complete bundle. Retaining one descriptor therefore retains all of its transitively referenced interfaces. Dropping the bundle variable does not invalidate a surviving descriptor. When the final retaining value disappears, C releases every arena block synchronously without a display, executor, or detached task. Bundle and descriptor values do not conform to Sendable.

Construction and validation take O(total schema fields and encoded bytes) expected time for dictionary lookups. Native storage is bounded by the configured allocation quota. Named lookup is expected O(1). Schema values preserve unknown enum bits; enums do not determine native argument layout.

## Raw integration boundary

ProtocolDescriptor.withUnsafeInterface explicitly borrows a sealed wl_interface pointer. The caller must retain the descriptor until all native consumers and queued native closures stop accessing every linked interface. A closure ending does not establish native quiescence. The caller must not mutate/free arena storage or give another allocator authority over it. Returning the pointer does not extend its lifetime.

Managed extension server resources and globals retain their descriptor through authoritative cleanup records. Generated typed facades consume those managed owners only after matching the complete reachable native schema graph. The standalone arena is not presented as a safe native adoption API. See <doc:TypedProtocol> for existing core ownership behavior.

## Managed client binding and queue lifetime

`WlRegistry.reference.bind(name:descriptor:version:advertisedVersion:)` creates a noncopyable `ClientProtocolObject` backed by the existing client ownership runtime. `ClientProtocolReference` sends schema-checked requests and constructors. `onEvent` receives an operation-scoped `ClientMessageReader`; claiming a constructor transfers the child proxy into a new managed object. Ignored, canceled, and throwing event paths dispose unclaimed file descriptors and child proxies. Zero-argument destructor requests are staged in the cleanup record so a queued constructor event can finish native disposal before physical receiver release. Argument-bearing destructors and terminal replacements reject a receiver while its constructor queue remains pending.

Native queued closures retain message metadata after logical proxy destruction. The connection therefore retains every published descriptor arena in a display-owned cell until `wl_display_disconnect` has released its queues. Publication reserves capacity before native binding, commits only after ownership handoff, and rolls back on failure. A connection accepts at most 64 distinct arenas and defaults to sixteen MiB of combined native arena storage; `maximumProtocolMetadataBytes` can lower the byte limit. `protocolMetadataSnapshot()` reports retained arena count, bytes, retirement, and native cleanup errors. Managed queue shutdown drains callbacks without user delivery before native queue release. These paths preserve the outer native frame while consuming incoming ownership obligations.

Conversion to a generated core reference or owner checks the complete transitive canonical schema graph. Matching only an interface name is insufficient because a foreign message layout could otherwise reach a core decoder with incompatible arguments. The safe dynamic API remains synchronous and domain-checked; raw foreign dispatch and untyped native adoption stay explicit unsafe boundaries.

The pinned libwayland 1.26.0 baseline has native queued-proxy leaks outside the public wrapper's repair authority. `Scripts/verify-native-pending-constructors.py` builds the original source and a local candidate patch in separate isolated prefixes. An independent C fixture confirms four original LSan failures and four candidate passes under ASan/UBSan, with native loader and exported-symbol checks. The fourth case sends a malformed object identifier after a valid event constructor so native lookup fails after child-proxy creation. The candidate is not installed on the host or accepted as an upstream fix. Full native review and broader failure-path validation remain required; native baseline leak freedom is a failed release gate.

## Managed server resources

`ServerClient.createProtocolObject(descriptor:version:)` creates a noncopyable resource with a server-selected ID. `ServerProtocolObject.onRequest` delivers an operation-scoped `ServerMessageReader` through the permanent resource dispatcher. `ServerProtocolReference.send` checks event version, argument layout, client identity, resource publication, borrowed object/FD leases, and the 4,096-byte wire bound before posting. An unsafe constructor-ID hook exists only for external native callbacks that can prove the peer's pending ID and interface. Ordinary request constructors use `ServerDynamicIdentifier.accept(descriptor:)` after the reader claims the pending ID.

For fixed-interface constructors, the reader resolves the target from the receiver's sealed descriptor arena. Acceptance requires that exact arena; an interface name match does not permit a substitute definition. Generic constructors can choose a separately validated descriptor. Cancellation or an ignored dynamic request rejects an unclaimed constructor before native callback return. The dispatcher closes unclaimed received FDs after both successful and throwing handlers. Resource metadata stays in its tracked context until native destruction and outer-frame retirement. libwayland 1.26.0 dispatches server request closures within one native client-connection callback and serializes server events before their post/queue calls return; it does not provide the same long-lived event-queue metadata consumer as the client side.

`ServerDisplay.addProtocolGlobal(descriptor:version:handler:)` advertises an imported interface. Its global cleanup record retains the descriptor until `wl_global_destroy` completes. A bind callback produces a `ServerDynamicIdentifier` that accepts only a descriptor from the advertising arena. Imported-global constructors cannot fall through the core marker overload. `ServerProtocolGlobal.withdraw`, `onWithdrawn`, `name(for:)`, and `close` use the same native offer and runtime rules as core globals.

## Verification

Scripts/verify-protocol.py checks cross-file cycles, enum imports, missing and duplicate definitions, malformed imported documents, deterministic CLI output, external Swift module compilation, and independent native scanner signatures. Scripts/verify-imported-protocols.py uses the pinned, license-preserving xdg-shell fixture and core XML to build a separate Swift package, instantiate all 28 native descriptors, and compare all 179 message signatures with wayland-scanner.

DescriptorArenaTests exercises a real C client/server constructor and object/enum event over a cyclic descriptor graph. It also retains one descriptor after its bundle variable disappears, checks collection after final release, builds the complete core arena, and rejects invalid schemas and exhausted allocation bounds. BridgeAllocationFaults injects failure at every allocation in the two-interface arena transaction; its independent pointer ledger rejects untracked/double frees and requires zero live allocations after every failure. The aggregate currently covers 21 bridge allocation failures and successful native retirement controls under ASan/UBSan.

`ProtocolClientTests` exercises managed extension requests, event constructors, file descriptors, terminal replacement, cancellation, receiver destruction, queue shutdown, and root closure against an independent C peer. `generate-extension-fixtures.py --check` ties its fixture schema to XML. `ProtocolMetadataTests` exercises byte/count limits and reentrant publication rollback. These tests do not prove native baseline leak freedom after a fatal display error.

`ProtocolServerTests` uses a separate C client to exercise imported server request dispatch, event delivery, fixed constructor acceptance, canceled constructor rejection, native resource destruction, arena retention through resource close, and registry bind of an imported global.

`generate-extension-fixtures.py --check` verifies both generated fixture files against lifecycle XML. Generated client and server facades complete independent C-peer round trips. A same-name child definition with a different event argument fails parent wrapper admission through the transitive graph check. `verify-imported-protocols.py` compiles the xdg-shell value and binding outputs in a separate Swift package with Swift 6.4.2 strict memory safety; this proves consumer compilation, not xdg-shell compositor behavior.
