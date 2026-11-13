import Glibc
import CWaylandServer
import WaylandRuntime

/// Describes a recoverable native server failure.
package enum ServerError: Error, Equatable, Sendable {
    /// A native allocation or operation failed with the saved errno.
    case nativeFailure(Int32)
    /// Recursive native event-loop dispatch is prohibited.
    case recursiveDispatch
}

@unsafe private func notifyClientDestroyed(_ pointer: UnsafeMutableRawPointer?) {
    guard let pointer = unsafe pointer else { return }
    let observer = unsafe Unmanaged<NativeDestructionObserver>.fromOpaque(pointer).takeUnretainedValue()
    do { _ = unsafe try observer.destroyed(serverClientCascade: true) }
    catch { preconditionFailure("Native client destruction violated the framed server-subtree contract: \(error)") }
}

@unsafe private func notifyResourceDestroyed(_ pointer: UnsafeMutableRawPointer?) {
    guard let pointer = unsafe pointer else { return }
    let observer = unsafe Unmanaged<NativeDestructionObserver>.fromOpaque(pointer).takeUnretainedValue()
    do { _ = unsafe try observer.destroyed() }
    catch { preconditionFailure("Native resource destruction violated the framed leaf contract: \(error)") }
}

// The cleanup record retains watch storage through complete native-frame retirement.
@safe private final class ServerNativeStorage {
    let pointer: OpaquePointer
    var observer: NativeDestructionObserver?
    var watch: OpaquePointer?
    var dispatching = false
    init(_ pointer: OpaquePointer) { unsafe self.pointer = pointer }
    func retireWatch() {
        if let watch = unsafe watch { unsafe wayland_kit_watch_destroy(watch) }
        unsafe watch = nil
        observer = nil
    }
    deinit { retireWatch() }
}

private final class ServerWatchRetirement {
    let storage: ServerNativeStorage
    init(_ storage: ServerNativeStorage) { self.storage = storage }
    deinit { storage.retireWatch() }
}

/// Owns a native server resource with external-destruction invalidation.
///
/// The native destroy watch retains copied identity through record retirement.
/// A surviving reference never authorizes native access after client destruction.
@safe package struct ServerResource: ~Copyable {
    private let storage: ServerNativeStorage
    private let owner: OwnedHandle
    fileprivate init(storage: ServerNativeStorage, owner: consuming OwnedHandle) {
        self.storage = storage
        self.owner = owner
    }
    /// Provides checked resource identity without native pointer exposure.
    package var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Returns the native identifier only while the resource remains live.
    package borrowing func identifier() throws -> UInt32 {
        try lifetime.withAccess(matching: .serverResource) { unsafe wl_resource_get_id(UnsafeMutablePointer<wl_resource>(storage.pointer)) }
    }
    /// Requests local destruction through the shared cleanup arbiter.
    @discardableResult
    package borrowing func requestClose() -> CloseProgress { owner.requestClose() }
    /// Consumes resource authority; native-consumed records never destroy twice.
    @discardableResult
    package consuming func close() -> CloseProgress { owner.close() }
}

/// Owns a server client and observes native client/resource cascading destruction.
@safe package struct ServerClient: ~Copyable {
    private let storage: ServerNativeStorage
    private let owner: OwnedHandle
    fileprivate init(storage: ServerNativeStorage, owner: consuming OwnedHandle) {
        self.storage = storage
        self.owner = owner
    }
    /// Provides checked client identity and the root for its native resource subtree.
    package var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Requests client destruction after tracked resource dependents retire.
    @discardableResult
    package borrowing func requestClose() -> CloseProgress { owner.requestClose() }
    /// Consumes client authority without repeating an external native destroy.
    @discardableResult
    package consuming func close() -> CloseProgress { owner.close() }

    /// Creates an ordinary native resource with immutable, caller-owned metadata.
    ///
    /// The interface must outlive all native users. Its version and identifier
    /// must obey the protocol constructor contract. This low-level allocation
    /// does not install an arbitrary request implementation or pretend its raw
    /// metadata is safe. Creation and watch failure roll back the native resource.
    @unsafe package borrowing func createResource(
        in session: borrowing OwnershipSession, interface: UnsafePointer<wl_interface>, version: Int32, identifier: UInt32 = 0
    ) throws -> ServerResource {
        try lifetime.withAccess(matching: .serverClient) {
            guard version > 0 && version <= (unsafe interface.pointee.version) else { throw ServerError.nativeFailure(EINVAL) }
            guard let pointer = unsafe wl_resource_create(storage.pointer, interface, version, identifier) else {
                throw ServerError.nativeFailure(errno)
            }
            let resource = unsafe ServerNativeStorage(OpaquePointer(pointer))
            let retirement = ServerWatchRetirement(resource)
            var adopted = false
            defer { if !adopted { unsafe wl_resource_destroy(pointer) } }
            let owner = unsafe try session.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .serverResource,
                                                dependencies: [lifetime]) {
                withExtendedLifetime(retirement) { unsafe wl_resource_destroy(UnsafeMutablePointer<wl_resource>(resource.pointer)) }
            }
            adopted = true
            let observer = owner.reference.destructionObserver()
            resource.observer = observer
            unsafe resource.watch = wayland_kit_watch_resource(pointer, notifyResourceDestroyed,
                                                              Unmanaged.passUnretained(observer).toOpaque())
            guard unsafe resource.watch != nil else { throw ServerError.nativeFailure(ENOMEM) }
            return ServerResource(storage: resource, owner: owner)
        }
    }
}

/// Owns a server display and serialized execution of its event loop.
///
/// Children are released before display destruction. Native client disconnects
/// observed inside dispatch consume their tracked resource subtree immediately,
/// retaining watch storage until the complete event-loop frame exits.
@safe package struct ServerDisplay: ~Copyable {
    private let storage: ServerNativeStorage
    private let session: OwnershipSession
    private let owner: OwnedHandle

    /// Allocates a display and publishes its single native destruction obligation.
    package init(maximumRecords: Int = 65_536) throws {
        guard let pointer = unsafe wl_display_create() else { throw ServerError.nativeFailure(errno) }
        var adopted = false
        defer { if !adopted { unsafe wl_display_destroy(pointer) } }
        let session = try OwnershipSession(maximumRecords: maximumRecords)
        let owner = unsafe try session.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .serverDisplay) {
            unsafe wl_display_destroy_clients(pointer)
            unsafe wl_display_destroy(pointer)
        }
        adopted = true
        storage = unsafe ServerNativeStorage(pointer)
        self.session = session
        self.owner = owner
    }
    /// Provides display identity without exposing native storage.
    package var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Returns resource accounting after native dispatch or shutdown.
    package borrowing func snapshot() throws -> OwnershipSnapshot { try session.snapshot() }
    /// Requests shutdown of the complete display domain.
    @discardableResult
    package borrowing func requestClose() -> CloseProgress { session.requestClose() }

    /// Creates a client from an exclusively owned connected socket, consuming every outcome.
    ///
    /// Unlike the client display connector, wl_client_create leaves its fd open
    /// on native failure. This adapter closes that input explicitly on failure.
    @unsafe package borrowing func createClient(receiving descriptor: Int32) throws -> ServerClient {
        var consumed = false
        defer { if !consumed { _ = Glibc.close(descriptor) } }
        return try lifetime.withAccess(matching: .serverDisplay) {
            guard let pointer = unsafe wl_client_create(storage.pointer, descriptor) else { throw ServerError.nativeFailure(errno) }
            consumed = true
            let client = unsafe ServerNativeStorage(pointer)
            let retirement = ServerWatchRetirement(client)
            var adopted = false
            defer { if !adopted { unsafe wl_client_destroy(pointer) } }
            let owner = unsafe try session.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .serverClient,
                                                dependencies: [lifetime]) {
                withExtendedLifetime(retirement) { unsafe wl_client_destroy(client.pointer) }
            }
            adopted = true
            let observer = owner.reference.destructionObserver()
            client.observer = observer
            unsafe client.watch = wayland_kit_watch_client(pointer, notifyClientDestroyed,
                                                          Unmanaged.passUnretained(observer).toOpaque())
            guard unsafe client.watch != nil else { throw ServerError.nativeFailure(ENOMEM) }
            return ServerClient(storage: client, owner: owner)
        }
    }

    // The native loop pointer is confined to sibling adapter installation under display access.
    @unsafe borrowing func withNativeLoop<Result: ~Copyable>(
        _ body: (borrowing OwnershipSession, OpaquePointer) throws -> Result
    ) throws -> Result {
        try lifetime.withAccess(matching: .serverDisplay) {
            guard let loop = unsafe wl_display_get_event_loop(storage.pointer) else { throw ServerError.nativeFailure(EINVAL) }
            return unsafe try body(session, loop)
        }
    }

    /// Dispatches native sources under one complete enclosing native frame.
    package borrowing func dispatch(timeoutMilliseconds: Int32 = 0) throws {
        try lifetime.withAccess(matching: .serverDisplay) {
            guard !storage.dispatching else { throw ServerError.recursiveDispatch }
            storage.dispatching = true
            defer { storage.dispatching = false }
            let loop = unsafe wl_display_get_event_loop(storage.pointer)
            guard unsafe wl_event_loop_dispatch(loop, timeoutMilliseconds) >= 0 else { throw ServerError.nativeFailure(errno) }
            unsafe wl_display_flush_clients(storage.pointer)
        }
    }

    /// Creates a resource in this display's runtime after checking the client dependency.
    @unsafe package borrowing func createResource(
        for client: borrowing ServerClient, interface: UnsafePointer<wl_interface>, version: Int32, identifier: UInt32 = 0
    ) throws -> ServerResource {
        guard client.lifetime.identity.session == lifetime.identity.session else { throw OwnershipError.foreignSession }
        return unsafe try client.createResource(in: session, interface: interface, version: version, identifier: identifier)
    }
}
