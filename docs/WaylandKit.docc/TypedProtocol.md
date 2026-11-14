# Typed core protocol ownership

Generate typed messages while preserving native ownership, version, and outer-frame contracts.

## Native gates and chosen transaction

The pinned libwayland 1.26.0 client implementation executes WL_MARSHAL_FLAG_DESTROY even when marshalling fails. Typed cleanup instead marshals zero-argument core destructor requests without that flag at quiescent cleanup, then destroys the local proxy once. Failed displays skip wire destruction. For validated nonterminal empty-signature requests, the pinned nonconstructor marshal checks last_error before allocating or sending a closure. This path performs one error query after marshal and reports the retained native error rather than replacing a preexisting error with EPIPE. Constructor and terminal paths retain their separate preflight and ownership handling. All current core request destructors have zero arguments; generation rejects a different destructor shape until its deferred argument retention is implemented.

Incoming client new_id arguments remain in the native closure until its final unref. An independent claimed-constructor bitmap controls fallback destruction; the argument pointer must not be nulled when ownership moves into Swift. Received fd arguments are disarmed before registration. Runtime publication failures consume the moved obligation. Incoming ownership scopes are initialized before optional handler delivery, including subscription cancellation.

The generated marker and message types derive from the pinned XML. Interface/version/connection checks precede native marshalling. Strings and arrays use native-owned temporary argument storage; descriptor and object borrows span the entire native call. Generated request destructors consume owning values; copied references cannot destroy proxies. wl_display's installed native implementation remains reserved for libwayland's own error and ID management.

Sources: [client implementation](https://raw.githubusercontent.com/wayland-mirror/wayland/1.26.0/src/wayland-client.c), [server implementation](https://raw.githubusercontent.com/wayland-mirror/wayland/1.26.0/src/wayland-server.c), and Protocols/wayland.xml.

Server constructor requests carry numeric IDs rather than allocated proxy pointers. A noncopyable pending constructor must either publish a matching resource or reject the client. Dropping it posts an implementation error and schedules client closure after the complete native frame. No numeric constructor is silently discarded. A server resource owns its request context through the existing destroy-watch retirement capture; the context retains only weak runtime observers. Native client destruction consumes resource records before their later callbacks can attempt another destroy.

## Supported surface and reserved native implementations

Scripts/generate-typed-protocol.py derives 23 interface markers, 72 client request methods, 62 client event cases, 72 server request cases, and 62 server event methods from the same validated IR as the schema generator. Open raw-value enum wrappers preserve unknown bits; ProtocolFixed preserves signed 24.8 bits. The generated manifest is docs/reference/typed-core-bindings.json. Scripts/verify-protocol.py checks deterministic schema and executable-binding regeneration and independently checks every message's name, opcode, and expanded signature against wayland-scanner.

All adapters remain package-access synchronous APIs in Swift 6 language mode on Swift 6.4.2. They are intentionally non-Sendable. These bindings validate interface identity, negotiated version, nullable representation, connection/client identity, native handle generation, and wire-size bounds. They do not implement a compositor's protocol policy, validate every semantic argument relationship, expose guarded SHM memory, or supply extension protocols. The XML descriptions remain in the schema manifest.

The client display reference supports getRegistry and sync. Its native error/delete_id dispatcher remains installed; display events are managed by libwayland rather than exposed as replaceable typed subscriptions. Native server display/registry implementations remain reserved as well. Generated declarations for those interfaces document the schema and permit compiler checking but do not authorize replacing reserved native resources. ServerClient.receiveConstructor is an explicitly unsafe bridge for externally validated global-bind callbacks; the caller must prove the pending ID, interface, client, version, uniqueness, and enclosing native invocation. ServerNewIdentifier.accept is the safe path after typed request decoding. Native global installation itself remains a separate server API milestone.

## Ownership ledger

| Obligation | Entry state | Successful handoff | Failure, cancellation, or drop |
|---|---|---|---|
| Client request constructor | Native proxy returned by marshalling | One permanent-dispatcher record and noncopyable ClientObject | Destroy a nonnull result even if the display also reports an error; registration/installation failure consumes the proxy |
| Client event constructor | Native closure owns a reference to an allocated proxy | Claim bitmap set before the consuming receive factory | Unclaimed proxy is locally destroyed; claimed publication failure is destroyed by the factory; closure argument remains intact for native unref |
| Incoming descriptor in either direction | Native closure owns a numeric FD slot | Slot changed to -1 before immediate RAII receive ownership, then one runtime FD record | Receive owner or failed registration closes once; fallback closes only nonnegative unclaimed native slots |
| Server request constructor | Native message contains a client-selected numeric ID | Noncopyable capability creates a matching native resource and record | Pending capability rejects the client; decoding/registration/handler failure closes the client through the runtime after outer-frame quiescence |
| Server-created event constructor | Resource record exists but peer has not learned its server-selected ID | First typed new_id event marks that resource published while leased | Repeated publication and ordinary events/object arguments using unpublished resources are rejected; closing an unpublished owner destroys it locally |
| Outgoing descriptor/object | Caller retains the owner | Scoped descriptor/object leases cover native marshalling | Validation and buffer-allocation failures retain caller authority; no borrowed FD is closed or transferred |
| Protocol destructor | One live object record | Logical invalidation followed by one quiescent native cleanup | Repeated closure or native client destruction cannot create a second native release |

Server event new_id arguments introduce an existing resource reference to the peer. They do not transfer the resource's owning Swift value. A server-created resource cannot send ordinary events before publication, appear as an existing object before publication, or be published twice. Resources created from client-supplied IDs start published. The check and native marshalling execute in one serialized domain claim.

A client close marshals the available zero-argument protocol destructor and destroys the local proxy at quiescence. An event destructor first disables that outgoing destructor, invalidates the client object, then delivers the copied/owned event. Server destructor requests invalidate their target before optional user delivery and destroy after dispatch returns. Server terminal events consume the resource owner after marshalling. Native event posting returns no delivery acknowledgement; successful return means local marshalling completed, not that the peer received the event.

## Retention and unsafe boundaries

A client endpoint contains the checked handle and raw pointer used only inside its lease. Its callback context retains the registry, static schema, decoder, diagnostics, and user handler. The registry retains a weak runtime observer and weak endpoint entries. It never retains a root owner or checked cell. A server request context is held by ServerNativeStorage through the record's existing watch-retirement capture; the native userdata pointer is unretained and remains valid until the complete native frame retires. Contexts hold weak runtime observers, not resource owners. Watch retirement clears context even if an invalidated Swift owner survives. Diagnostic snapshots use a separate box so failures remain observable after retirement. User closures must avoid unrelated ARC capture cycles.

ClientMessageReader and ServerMessageReader never expose raw slots. Readers are noncopyable inout values tied to their initialized callback scope. Compiler ownership checks reject consuming them out of that scope or capturing them in escaping closures. General reader getters check the argument index and kind before dereferencing. Generated core unsigned getters use XML-proven indices after attachment verifies every native event name and expanded signature against the same pinned schema; they still reject a null argument array. The native parser must provide the argument storage described by that validated signature for the callback frame. Package-generated core `onEvent` overloads register one specialized scalar handler only for events whose complete argument list contains signed integers, unsigned integers, or fixed-point values. The generated handler constructs the event and invokes the user closure without a separate decoder function value. Subscription installation intersects the generated scalar mask with schema bounds, negotiated version, ownership cleanup, and terminal-event checks. The dispatcher checks the resulting mask and active subscription before invoking it. This path constructs no ownership reader and cannot claim an FD or new proxy. Other events and canceled delivery retain the ordinary reader or cleanup path. External `ClientInterface` conformances cannot register this decoder through the public protocol. A throwing scalar handler records the failure before the C callback returns. Strings and arrays are copied. Descriptor/constructor slots can be claimed only once. Static core wl_interface objects and generated trampolines live for the process lifetime. General temporary C argument arenas copy strings and arrays and own no descriptor or object. Validated single-string client requests instead borrow UTF-8 storage only through synchronous native marshalling, as detailed below. Nested checked borrows cover the final native call; all temporary allocations are released on throw. Message size is bounded to 4,096 bytes and the encoder accepts at most 20 wire arguments. The runtime's configurable record limit bounds retained acquisitions; this does not establish a complete backpressure policy for libwayland's own incoming queue.

These contracts cover M1–M3, M5, M7, M9–M10, M13, M15–M16, and the record/message bounds in M19. They address SR1–SR3, SR5–SR6, SR8–SR10. No new unchecked Sendable conformance or asynchronous cleanup path is introduced. Human review of the native contracts and patch remains required.

## Examples

Client request constructors return owning values. Keep subscription values alive for as long as delivery is needed. A copied reference supports requests but cannot destroy the object.

```swift
let registry = try connection.protocolDisplay().getRegistry()
let subscription = try registry.onEvent { event in
    switch consume event {
    case .global(let name, let interface, let version):
        // Store the advertisement for a later typed bind.
        recordAdvertisement(name, interface, version)
    case .globalRemove(let name):
        removeAdvertisement(name)
    }
}
let compositor = try registry.reference.bind(
    name: advertisedName, as: WlCompositor.self,
    version: 1, advertisedVersion: advertisedVersion)
let surface = try compositor.reference.createSurface()
try surface.reference.commit()
try surface.destroy()
```

Server constructor handling moves the obligation into an owned resource. Keeping the resulting resource requires application storage; dropping it closes that resource. A thrown handler, ignored constructor, or canceled constructor subscription rejects the unfulfilled request safely.

```swift
let subscription = try compositor.onRequest { request in
    switch consume request {
    case .createSurface(let identifier):
        let surface = try identifier.accept()
        storeSurface(consume surface)
    case .createRegion(let identifier):
        let region = try identifier.accept()
        storeRegion(consume region)
    case .release:
        break
    }
}
```

These fragments describe ownership flow; application storage and policy helpers are intentionally application-defined. The executable tests provide complete native-peer fixtures.

## Validation boundaries

Tests/WaylandRuntimeTests/TypedProtocolTests.swift uses an independent C server for typed registry binding, surface construction/destruction, terminal callback events, received FDs and newly created proxies, canceled delivery, throwing handlers, constructor rollback, record-capacity failure, and root closure during an FD callback with a queued constructor. Tests/WaylandRuntimeTests/TypedServerTests.swift uses an independent C client for typed request construction/destruction, received FD ownership, pending-ID cancellation, handler failure, partial decode/resource publication failure, and outgoing FDs/new resource IDs. Runtime snapshots and independent /proc/self/fd identity counts check cleanup; sanitizer runs check the native memory boundary. Compiler rejection fixtures check copying owners/events/requests/constructor capabilities, destroying through a copied reference, and passing the wrong interface.

Independent C peers exercise every ordinary core request/event in both directions, including nullable/nonnullable variants and every wire field. Seven native-reserved display/registry messages retain native implementations and have integration tests. This establishes the pinned core wire/ownership scope, not a complete compositor policy. Equivalent typed-path measurements now exist and fail the initial throughput target; native global installation is implemented. External XML imports and owned arenas have separate evidence in <doc:OwnedProtocolMetadata>. Managed extension bindings, optional asynchronous delivery, broader native allocation failpoints, and deferred aarch64 validation remain outside completed core evidence. Arbitrary user capture cycles are not automatically collected; UserCaptureCycleTests demonstrates explicit root closure breaking a retained handler/owner cycle, while flag-only cancellation does not.

## Noncopyable decoder scopes

The generated synchronous hot path uses inout noncopyable message readers rather than allocating a reader object for each scalar event. Reader ownership cannot leave its initialized native callback scope: consuming an inout reader without reinitializing it or capturing it in an escaping closure is rejected by the compiler. Owned FD and constructor fields can still move out through their explicit claim methods. This strengthens the earlier runtime-active-flag approach and avoids a reader heap allocation on each scalar invocation. Compiler fixtures and performance measurements must validate the actual implementation before the allocation budget is considered met.

## Native-owned server resource references

Core messages can reference native-owned objects such as wl_registry or buffers created by the builtin SHM implementation. These objects are not adopted for destruction. The server registry first reuses an existing authoritative resource observer when one exists. Otherwise it installs a resource-destruction watch with a dedicated serverResourceWatch obligation and surrenders that watch token to root authority. A copyable reference leases the watch record before accessing the native resource. The watch's cleanup detaches/frees only its listener storage; it never destroys the native resource.

The native client cascade consumes only server resources, dedicated self-detaching resource watches, and the separately watched serverResourceDestruction records described below. It still rejects arbitrary descendant kinds before any mutation. Watch storage remains retained until native destruction and all enclosing frames complete. A strong copied-identity observer index prevents a missing weak endpoint from granting new access to a logically closed resource; raw-pointer reuse remains rejected until record retirement. This also permits a reference to be reconstructed after its last checked cell disappears without losing the watch obligation.


## Public marker authority

ClientInterface and ServerInterface are public constraints because public generic types require them. External conformance does not authorize native descriptors. CoreProtocol.requireSchema(for:) admits exact generated metatype identities and returns canonical immutable metadata without invoking an external interfaceName getter. Every safe generic native acquisition/reference path validates this authority first and uses one schema snapshot for native name/version checks. ProtocolMarkerTests rejects an external conformer whose getter would terminate the process if called. Raw custom interfaces remain unsafe compatibility; their arena must be retained by every managed consumer before any safe extension factory can be exposed. Owned arena construction is implemented separately.

## Argument-directed protocol destruction

The pinned wl_fixes.destroy_registry description requires the client to stop using its registry argument. Its XML request has no destructor flag and the C inline helper only marshals; the C application must also stop using/destroy its local proxy. Protocols/ownership-effects.json records this explicit non-receiver effect. The typed client consumes ClientObject<WlRegistry> on every outcome, sends the request through a checked reference, and closes the local owner. A failed local validation still consumes that argument; other owners remain unchanged.

The server decoder invalidates the target before user delivery and schedules its native resource destruction at outer-frame quiescence. User delivery receives a copied ServerResourceSnapshot, not a new copyable destruction capability. A separate framed destruction record has a self-detaching native resource watch and a client dependency. Native client/resource destruction can consume that record before its runtime action; its capture retirement then detaches/frees the watch without repeating the resource destructor. A registry destruction index prevents reentrant lookup from granting another live reference until native retirement completes. Canceled/throwing delivery still performs the mandatory target cleanup. This specialized record kind is allowed in the source-audited server-client cascade; arbitrary other dependent kinds remain rejected.

## Scoped typed context access

A typed endpoint stores a non-owning opaque context address. Only withContext converts that address back to a Swift object, after lifetime.withAccess has validated the session/generation and established a complete native frame. The authoritative dispatcher record and its cleanup capture retain the context through that frame. Logical closure rejects admission before pointer conversion; physical retirement waits for every admitted frame. A retained invalidated owner may contain a stale address but cannot dereference it. This avoids a strong endpoint/context cycle and a weak-reference side-table operation on the hot path. The retired-context subscription regression exercises registration after root closure under ordinary and instrumented native runs.

## Request layout preparation

Each client endpoint prepares expanded request argument layouts once from its immutable schema. Generic new-ID arguments include their wire interface-name and version slots. Encoding still checks value count, kinds, nullability, interface identity, descriptor leases, and wire-size limits on every call. This moves layout-array allocation out of steady-state sends at the cost of retained storage proportional to the endpoint request schema. It does not eliminate payload copying or native marshal allocations.

The C argument arena places its argument slots and allocation records in one zero-initialized allocation sized for the actual argument count, bounded to 32. Compile-time alignment assertions protect the trailing allocation-record layout. Zero-argument arenas reserve one addressable slot. This removes two allocations per nonempty encoding operation without reserving 32 slots for every small message. String and array payload storage remains separately owned and released by the arena. The two eliminated constructor allocation stages are no longer failure-injection sites; the current bridge fixture verifies 25 injected failures and successful retirement controls.

Slot replacement is transactional. String and array setters allocate and copy the replacement before retiring previous slot storage, so input may alias that storage. Allocation failure leaves the previous value intact. A successful replacement releases the old payload exactly once; assigning a null string releases any previous string or array payload. The bridge fixture checks allocation failures at each replacement stage, aliased input, preserved contents, and zero outstanding allocations after retirement.

A validated client request with exactly one string argument uses an initialized stack `wl_argument` within `withUnsafeMutablePointer` and `String.withCString`. The existing kind, nullability, interior-NUL, and wire-size checks run first. The endpoint native frame still covers the call. No object or descriptor lease can occur in this signature. All current encoder bodies synchronously marshal and never retain the argument pointer; a thrown error exits both scopes normally. Other nonempty signatures retain the arena path. In libwayland 1.26.0, `wl_proxy_marshal_array_flags` calls `wl_closure_send` and destroys its closure before returning; `serialize_closure` copies the string bytes into the outgoing connection buffer. This scoped path removes the arena and payload-copy allocation without extending a borrowed pointer lifetime. See the pinned [client marshaller](https://gitlab.freedesktop.org/wayland/wayland/-/blob/1.26.0/src/wayland-client.c) and [connection serializer](https://gitlab.freedesktop.org/wayland/wayland/-/blob/1.26.0/src/connection.c). This preserves M2–M4, M10, M12, and SR8; core request wire tests cover native serialization and `SingleStringRequestTests` covers invalid payload rejection before sending.

The core generator routes every nonterminal request containing exactly one string through `sendString`, avoiding the intermediate `[ClientWireValue]` allocation. This currently covers `wl_data_source.offer`, `wl_shell_surface.set_title`, and `wl_shell_surface.set_class`. The internal encoder validates opcode, negotiated version, signature kind/count, nullability, interior NUL, and total wire size before native marshalling under the same lifetime frame. String-size validation is shared with the general encoder. A nonconstructor marshal rejects an existing display error before sending; the post-call error check reports that error or any newly raised failure. The invalid-payload, invalidated-owner, and existing-transport-error regressions exercise this route. Dynamic and mixed-signature requests retain the general encoder.
