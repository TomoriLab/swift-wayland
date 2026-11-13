# Architecture

Separate the C ABI boundary from ownership, protocol generation, and optional integration layers.

## Scope and guarantee

The baseline includes libwayland-client, libwayland-server, libwayland-cursor, libwayland-egl, public utility types, macros, deprecated APIs, and the complete core wayland.xml. A binding must preserve observable semantics, error conditions, ordering, and ownership effects. A safe replacement may change the source-level calling convention, such as replacing varargs with typed arguments. Deprecated functionality remains available in the compatibility layer with migration guidance.

wayland-protocols extensions, compositor policy, rendering, EGL context management, Vulkan, and toolkit widgets are separate from the libwayland baseline. The generator must support external protocol XML, including xdg-shell, without requiring changes to the ownership runtime. Extension support is an explicit capability of the generator, not a claim that every external protocol is bundled.

The safe API assumes a correct libwayland implementation, valid operating-system behavior, and exclusive ownership of adopted objects. It must tolerate malformed peer input to the extent libwayland reports it safely. It cannot repair undefined behavior inside libwayland, a malicious native plugin, or another library destroying an adopted pointer without participating in the lifetime contract. These assumptions define the trusted computing base, not an excuse to expose raw memory through safe methods.

## Proposed target graph

| Target | Responsibility | Dependencies |
|---|---|---|
| CWaylandClient | System module for client headers | System libwayland-client |
| CWaylandServer | System module for server headers | System libwayland-server |
| CWaylandCursor / CWaylandEGL | Optional system modules | Corresponding system libraries |
| WaylandCBridge | Small audited C adapters, stable callback storage, varargs formatting | Relevant C modules |
| WaylandRuntime | Handle cells, ownership, checked arguments, errors, execution domain | WaylandCBridge |
| WaylandClient | Client connection, queues, generated client protocol API | WaylandRuntime, CWaylandClient |
| WaylandServer | Server display, event loop, clients, resources, generated server API | WaylandRuntime, CWaylandServer |
| WaylandCursor / WaylandEGL | Theme/image views and EGL native window integration | WaylandClient and optional C module |
| WaylandUnsafe | Explicit C-semantic interoperation and deprecated compatibility | Runtime and relevant C modules |
| WaylandKit | Client-focused umbrella | WaylandClient |
| WaylandScanner | Deterministic XML-to-Swift/C generator, future build plugin | Host-side XML parser to be selected |

Client-only applications must not link the server, cursor, or EGL libraries merely by importing WaylandKit. Server and optional modules are explicit products. Split bridge code by dependency where SwiftPM linking would otherwise pull optional libraries into the core. Public products use the Kit-style naming externally while module names distinguish client and server `wl_display` meanings.

No production dependency is added by this design. Implementation starts with the standard library, libc, and system libwayland. A third-party XML parser or runtime dependency requires approval before addition. DocC tooling and test tools are development dependencies and must be pinned separately.

## API families

| C family | Planned safe facade | Required semantics |
|---|---|---|
| Client display and queues | ClientConnection, EventQueue, ReadReservation | Disconnect invalidates all children; queues have one dispatch owner |
| Proxy creation and marshalling | Generated interface owners and checked object references | Typed arguments; negotiated version; local versus wire destruction |
| Listeners and dispatchers | EventSubscription and generated handler protocols | Stable contexts; one terminal release; reentrancy rules |
| Server display, sockets, serials | ServerDisplay, SocketRegistration, Serial | Distinct client/server identity; serial wrapping |
| Server client and resource | ClientReference, ResourceOwner, ResourceReference | External destruction invalidates aliases before callback return |
| Globals and global offers | GlobalRegistration, GlobalOffer | Visibility, withdrawal, binding, removal acknowledgement |
| Event loop and sources | EventLoop, FDSource, TimerSource, SignalSource, IdleSource | Source-kind constraints and one-shot idle invalidation |
| Shared memory | SharedMemoryBuffer, SharedMemoryAccess, SharedMemoryPool | Ref/unref and begin/end balance; format-aware bounds |
| Protocol loggers and global logging | ProtocolLoggerRegistration, ProcessLogHandler | Borrowed message access; process-global installation policy |
| Cursor | CursorTheme, CursorReference, CursorImageReference | Theme owns image and buffer lifetime |
| EGL | NativeWindow | Surface and connection remain valid until window destruction |
| Utility | Fixed, ByteArray, scoped list/signal facades, InterfaceDescriptor | Checked conversion and pinned storage |

The one-to-one compatibility identifiers are listed in the reference inventory. Safe methods will reference these identifiers in DocC so ergonomic naming never hides missing coverage.

## Ownership representation

Use noncopyable value owners for uniquely owned native resources. An owner holds an internal reference-counted HandleCell. Copyable object references hold the cell, never a cached raw pointer; they do not acquire destruction authority. The cell records pointer, state, identity, generation, parent identity, isolation domain, and active native call depth.

Parent control blocks own authoritative cleanup records independently of Swift reference cells. Each record stores the native release obligation, dependency edges, generation, and bridge-context ownership until terminal cleanup. The control block may index cells weakly, but a weak cell index is never the cleanup inventory. Losing the last Swift cell must not lose a native obligation. Child cells retain the parent bookkeeping control; cleanup records and callback contexts have no strong edge back to that control. Active operations temporarily retain the control through their outermost native frame.

A noncopyable owner is an authority token for its cleanup record. The record arbitrates release against native destruction and parent shutdown. Dropping the parent owner initiates shutdown even when child references keep its bookkeeping control alive; it does not wait for the control's ARC deinitializer. Child references cannot extend connection usability after parent-owner closure. Connection identity includes a nonreused session generation, not an allocator address.

Dependency edges express more than a parent tree: an EGL window depends on its surface, a cursor theme depends on SHM/connection state, and a proxy may depend on a queue. Close defers a dependent native free or closes dependents first according to the documented policy. Safe operations cannot destroy a prerequisite while a dependent native consumer still uses it. Explicit native refs are separate release obligations and do not automatically grant access after the runtime session closes. See <doc:SafetyReview> for authority and teardown cases.

Reference-counted native resources, including supported SHM buffer and pool references, use a dedicated refcount owner. Each native ref acquisition creates one release obligation. Borrowed cursor buffers never acquire proxy destruction authority.

The default low-level API is synchronous and non-Sendable. An optional async coordinator sends owned commands to a dedicated serialized execution domain. It never exposes raw cells or borrowed event data across suspension.

## Swift 6.4.2 feature policy

| Feature | Planned use | Acceptance condition |
|---|---|---|
| `~Copyable`, `borrowing`, `consuming` | Resource owners and exactly-once read/access tokens | Double-consume and use-after-consume rejection tests |
| `~Escapable` and Span family | Callback strings, argument arrays, scoped borrowed buffers | Escape and async capture rejection tests |
| StrictMemorySafety | Audit every unsafe operation at the bridge boundary | Enable exact supported compiler mode; diagnostics treated as errors |
| Swift 6 concurrency checking | Reject transport of mutable native state | No blanket unchecked Sendable conformances |
| Typed throws | Stable domain errors where failure sets are closed | Do not erase cancellation or unexpected underlying failures |
| Generics over noncopyable values | Statically typed object families and owners | Compile probes for every selected generic shape |
| Swift 6.4 async defer and cancellation shields | Optional coordinator cleanup that must survive cancellation | Toolchain probe and deadlock/cancellation tests |
| Swift 6.4 noncopyable collections | Potential storage for resource owners | Benchmark and API probe before adoption |

Noncopyable types and ownership modifiers are established language features. Nonescapable types and strict memory-safety checking were implemented in Swift 6.2. These are appropriate foundations, but a C pointer does not acquire a verified lifetime merely because a Swift wrapper is noncopyable. [SE-0390](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0390-noncopyable-structs-and-enums.md), [SE-0446](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0446-non-escapable.md), [SE-0458](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md).

Span provides a non-owning bounds-checked view whose lifetime depends on backing storage. Prefer the public safe construction APIs available in 6.4.2; any unsafe construction remains a bridge proof obligation. [Span documentation](https://docs.swift.org/latest/documentation/swift/span/).

Swift 6.4 provides async defer and task cancellation shields. These serve bounded async shutdown, not synchronous native destruction. [Swift 6.4 release](https://www.swift.org/blog/swift-6.4-released/), [SE-0504](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0504-task-cancellation-shields.md).

Do not adopt a proposal solely because it is accepted on the main branch. SE-0544, mutation and consumption in noncopyable deinitializers, is currently listed as accepted rather than assigned a released version in the inspected proposal. The ConsumeInDeinit probe now compiles and executes a specific noncopyable field-consumption pattern on Swift 6.4.2 without experimental flags. Other shapes still require probes. Similarly, custom lifetime annotations must be verified against the exact toolchain; owned copies or a checked nonescaping view API are the baseline fallback. No underscored lifetime attribute is part of the public API contract. [SE-0544](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0544-mutate-or-consume-in-deinit.md).

## Performance policy

Each native operation performs a bounded number of cell validations and one C call where possible. Use static generated dispatch tables and contiguous argument storage. Avoid dictionary lookups, Task creation, String conversion, or dynamic existential dispatch per ordinary typed scalar event unless measurement justifies them. Borrow immutable callback strings and arrays synchronously under verified lifetime guards; copy explicitly for storage or async delivery. Externally writable SHM follows the stricter owned-snapshot policy in <doc:OwnershipAndFFI> and is excluded from the default borrowed-payload path. Do not claim zero-copy across socket IPC or shared-memory setup.

The registry may use expected O(1) identity lookup; worst-case complexity and growth limits must be documented. Type metadata is immutable and shared. Do not mark all public functions inlinable: exposing internal lifetime machinery would constrain maintenance and ABI evolution. Optimize after inspecting SIL/assembly and benchmark data.

## Phase 1 capability boundary

The initial executable matrix is documented in <doc:ToolchainValidation>. Standard-library Span construction and borrowing work without experimental flags, but a custom public @lifetime-returning signature is rejected unless the experimental LifetimeDependence feature is enabled. The baseline does not enable it. A locally backed Span can also survive await; native no-suspension rules therefore require their own verified API and runtime mechanism. The phase 1 reference graph is not the production handle runtime.

## Implemented ownership core

The phase 2 package-level core is documented in <doc:OwnershipRuntime>. It uses handle cells and authoritative dependency records, a short pthread bookkeeping mutex, logical single-thread admission, and a global native-frame depth to defer release. Actions never run under the bookkeeping mutex. Unsafe adoption accepts non-affine, nonthrowing release actions; client/server and affine resource adapters remain separate work. The user explicitly postponed aarch64 validation for this x86_64 milestone.
