# Getting started with WaylandKit

Build a client that discovers a compositor, creates an unmapped surface, and shuts down with checked resource retirement.

## Requirements

Use Swift 6.4.2 in Swift 6 language mode on x86_64 Linux with libwayland 1.26.0 development headers, libraries, pkg-config metadata, and wayland-scanner. Other Swift releases are not the verified baseline. aarch64 verification remains deferred. A real Wayland compositor is required for the desktop-session walkthrough; the paired server example below provides a separate control-plane test without a desktop session.

```sh
swift --version
pkg-config --modversion wayland-client wayland-server wayland-cursor wayland-egl
wayland-scanner --version
```

The compiler must report Swift 6.4.2. The native components must match the pinned libwayland baseline. If the libraries are installed outside the default search paths, configure PKG_CONFIG_PATH for their `.pc` files and LD_LIBRARY_PATH for their shared libraries. The package's system-library targets obtain build paths from pkg-config.

## Add the package

Create a separate executable package. Replace `/absolute/path/to/swift-wayland` with the checkout location. A local dependency makes this walkthrough reproducible against the source being reviewed without assuming a published release tag.

```sh
mkdir RegistryExample
cd RegistryExample
swift package init --type executable --name RegistryExample
```

Replace Package.swift with:

```swift
// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "RegistryExample",
    dependencies: [.package(path: "/absolute/path/to/swift-wayland")],
    targets: [.executableTarget(name: "RegistryExample", dependencies: [.product(name: "WaylandKit", package: "swift-wayland")],
                                swiftSettings: [.strictMemorySafety()])],
    swiftLanguageModes: [.v6]
)
```

Replace the generated executable source with the complete client below. Keep only one entry point in the executable target. `import WaylandKit` exposes the client facade, protocol value types, and ownership runtime. Server, cursor, EGL, and utility APIs have separate products and imports; see <doc:Project> for their roles.

## Discover globals and create a surface

```swift
import WaylandKit

private final class RegistrySnapshot {
    var globals: [String: (UInt32, UInt32)] = [:]
    var synchronized = false
}
@main struct RegistryExample {
    static func main() throws {
        let connection = try ClientConnection()
        let registry = try connection.protocolDisplay().getRegistry()
        let observed = RegistrySnapshot()
        let subscription = try registry.onEvent { event in
            switch consume event {
            case .global(let name, let interface, let version): observed.globals[interface] = (name, version)
            case .globalRemove: break
            }
        }
        let synchronization = try connection.protocolDisplay().sync()
        let synchronized = try synchronization.onEvent { event in
            switch consume event { case .done: observed.synchronized = true }
        }
        let cancellation = try ReadCancellation()
        try connection.flush()
        for _ in 0..<10 where !observed.synchronized {
            _ = try connection.dispatchOnce(timeoutMilliseconds: 1_000, cancellation: cancellation)
        }
        guard observed.synchronized else { throw ExampleError.timeout }
        guard let (name, advertised) = observed.globals[WlCompositor.interfaceName] else { throw ExampleError.missingCompositor }
        let version = min(advertised, WlCompositor.schema.version)
        let compositor = try registry.reference.bind(name: name, as: WlCompositor.self, version: version, advertisedVersion: advertised)
        let surface = try compositor.reference.createSurface()
        try surface.reference.commit()
        try surface.destroy()
        try connection.flush()
        withExtendedLifetime(subscription) {}
        withExtendedLifetime(synchronized) {}
        connection.requestClose()
        let snapshot = try connection.snapshot()
        guard snapshot.retainedRecords == 0 else { throw ExampleError.incompleteCleanup }
        print("Observed \(observed.globals.count) interface names; sync completed; unmapped surface created and destroyed; all ownership records retired.")
    }
    enum ExampleError: Error { case timeout, missingCompositor, incompleteCleanup }
}
```

The client proceeds through these stages:

1. `ClientConnection()` connects using WAYLAND_DISPLAY and XDG_RUNTIME_DIR. Run it as the user who owns the compositor session.
2. `getRegistry()` constructs a registry proxy. The retained subscription records advertised interface names, global identifiers, and versions.
3. `sync()` inserts a synchronization request after registry acquisition. Its `done` event marks completion of the initial registry enumeration. The client flushes and dispatches with bounded waits instead of assuming events arrive immediately.
4. The client selects the lower of the advertised compositor version and the binding's supported version. `bind` receives both the requested and advertised versions for validation.
5. `createSurface()` returns an owning object. Requests use its checked `reference`; `destroy()` consumes the destruction authority.
6. `requestClose()` retires the root session. A final snapshot checks that no tracked cleanup records remain.

`RegistrySnapshot` is mutable state owned by this synchronous example. It does not confer Sendable access to a connection. The one-shot discovery example intentionally ignores global removal; a long-running client must remove globals when `globalRemove` arrives and handle unavailable capabilities.

No buffer is attached to this surface and no window role is assigned. The example therefore creates no visible window. Visible application windows additionally require a shell protocol such as xdg-shell, buffer allocation, configure/ack handling, and compositor-specific integration. This walkthrough does not implement those steps.

## Run against the desktop session

From the standalone package directory:

```sh
swift run -Xswiftc -warnings-as-errors
```

From the WaylandKit checkout, the maintained copy runs with:

```sh
swift run --package-path Examples/Registry -Xswiftc -warnings-as-errors
```

Expected success output has this form; the interface count depends on the compositor:

```text
Observed N interface names; sync completed; unmapped surface created and destroyed; all ownership records retired.
```

The client allows up to ten one-second dispatch waits for the initial synchronization. Missing socket access, native connection errors, absent wl_compositor, timeout, and incomplete cleanup propagate as errors. A successful run confirms the control-plane lifecycle, not rendering or input handling.

## Run a paired server without a desktop session

The repository includes a minimal public server consumer. It announces wl_compositor version 1, accepts typed surface constructors, and waits for surface destruction. It does not render or implement a general compositor. Run both maintained examples through the harness:

```sh
python3 Scripts/verify-examples.py
```

The harness builds the standalone packages, creates a private temporary XDG_RUNTIME_DIR, reads the server's socket name, launches the client with WAYLAND_DISPLAY set to that socket, and waits for both processes. Its report at `.build/examples-report.json` contains `passed: true` only after both consumers succeed and the socket and lock files are removed.

The complete server source is:

```swift
import Foundation
import WaylandServer
import WaylandProtocol

private final class CompositorOwner {
    let owner: ServerObject<WlCompositor>
    let subscription: ServerRequestSubscription
    init(owner: consuming ServerObject<WlCompositor>, subscription: consuming ServerRequestSubscription) {
        self.owner = owner; self.subscription = subscription
    }
}
private final class SurfaceOwner {
    let owner: ServerObject<WlSurface>
    let subscription: ServerRequestSubscription
    init(owner: consuming ServerObject<WlSurface>, subscription: consuming ServerRequestSubscription) {
        self.owner = owner; self.subscription = subscription
    }
}
private final class ServerApplication {
    let display: ServerDisplay
    var compositors: [CompositorOwner] = []
    var surfaces: [SurfaceOwner] = []
    var completed = false
    init() throws { display = try ServerDisplay() }
    func bind(_ identifier: consuming ServerNewIdentifier<WlCompositor>) throws {
        let owner = try identifier.accept()
        let subscription = try owner.onRequest { [weak self] request in
            guard let self else { return }
            switch consume request {
            case .createSurface(let identifier):
                let surface = try identifier.accept()
                let subscription = try surface.onRequest { [weak self] request in
                    switch consume request {
                    case .commit: break
                    case .destroy: self?.completed = true
                    default: throw ServerExampleError.unsupportedRequest
                    }
                }
                self.surfaces.append(SurfaceOwner(owner: surface, subscription: subscription))
            default: throw ServerExampleError.unsupportedRequest
            }
        }
        compositors.append(CompositorOwner(owner: owner, subscription: subscription))
    }
    enum ServerExampleError: Error { case unsupportedRequest, timeout, incompleteCleanup }
}
@main struct MinimalServer {
    static func main() throws {
        let application = try ServerApplication()
        let global = try application.display.addGlobal(as: WlCompositor.self, version: 1) { [weak application] identifier in
            guard let application else { return }
            try application.bind(identifier)
        }
        let socket = try application.display.addAutomaticSocket()
        FileHandle.standardOutput.write(Data((socket + "\n").utf8))
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !application.completed && ContinuousClock.now < deadline { try application.display.dispatch(timeoutMilliseconds: 100) }
        application.display.requestClose()
        let snapshot = try application.display.snapshot()
        guard snapshot.retainedRecords == 0 else { throw ServerApplication.ServerExampleError.incompleteCleanup }
        guard application.completed else { throw ServerApplication.ServerExampleError.timeout }
        withExtendedLifetime(global) {}
        print("Typed surface lifecycle completed; all server ownership records retired.")
    }
}
```

The server retains each owning object and its noncopyable request subscription in a reference-type holder. Weak application captures prevent the handler storage from strongly retaining its application owner. A new identifier is accepted exactly once to establish the server resource; unsupported requests fail explicitly. The dispatch loop has a ten-second deadline, and root closure is checked before exit. The global remains alive through dispatch.

To build this server in another package, depend on the WaylandServer and WaylandProtocol products and use their matching imports, as shown in `Examples/MinimalServer/Package.swift`. Foundation is used here only to publish the socket name through standard output.

## Ownership and subscriptions

ClientConnection owns the root session. A ClientObject owns one native proxy obligation. Its copyable reference permits checked protocol requests but has no protocol destructor. Constructor results must be retained while their native object is needed. Consuming destroy/release methods invalidate their references immediately. Native memory release waits for enclosing native calls and dependents to quiesce.

onEvent returns a noncopyable subscription. Keep it alive while delivery is needed. Cancellation disables user delivery without removing a permanent native dispatcher or freeing userdata. Received descriptors and new proxies still undergo mandatory decoding and cleanup. Avoid strongly capturing an owner in a handler retained by that owner's context; use weak application state or explicitly close the owner/root or break the captured strong references. Flag-only subscription cancellation does not release native-reachable context and does not by itself break that capture cycle.

ReadCancellation is Sendable and owns only a wake descriptor and synchronized cancellation state. It carries no display access. The connection and its objects remain non-Sendable. dispatchOnce integrates a prepared read with timeout, flush backpressure, and cancellation. withPreparedRead is a lower-level synchronous borrowed capability: it must resolve by read/cancel on the originating coordinator and cannot escape or suspend.

## Errors and shutdown

Version/class/session and payload validation happen before native marshalling. A failed native constructor or record publication rolls back every newly acquired obligation. Native protocol errors are connection-terminal and remain distinct from local argument errors. protocolError() returns copied interface/object/code information that remains usable after disconnect.

requestClose() is idempotent. It invalidates all descendants immediately and can report deferred while inside a native call. Root closure does not depend on the last Swift reference disappearing. A final snapshot with zero retained records establishes that this session's tracked obligations retired; it is not a proof against arbitrary user ARC cycles or fatal process termination.


## Next steps

Read <doc:TypedProtocol> for typed request and event contracts, <doc:OwnedProtocolMetadata> for imported protocol metadata, and <doc:ClientAndServer> for queue coordination and server-resource lifetimes. Use <doc:AdvancedAPIs> for optional cursor, EGL, SHM, and utility integrations. <doc:ContinuousIntegration> describes the full verification matrix and its current limitations.
