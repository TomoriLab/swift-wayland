import Glibc
import CWaylandServer
import WaylandRuntime

/// Describes a recoverable native server failure.
public enum ServerError: Error, Equatable, Sendable {
    /// A native allocation or operation failed with the saved errno.
    case nativeFailure(Int32)
    /// Recursive native event-loop dispatch is prohibited.
    case recursiveDispatch
}

@unsafe func notifyClientDestroyed(_ pointer: UnsafeMutableRawPointer?) {
    guard let pointer = unsafe pointer else { return }
    let storage = unsafe Unmanaged<ServerNativeStorage>.fromOpaque(pointer).takeUnretainedValue()
    guard let observer = storage.observer else { preconditionFailure("Native client watch has no observer.") }
    let snapshot = unsafe snapshotClient(storage.pointer)
    do { _ = unsafe try observer.destroyed(serverClientCascade: true) }
    catch { preconditionFailure("Native client destruction violated the framed server-subtree contract: \(error)") }
    storage.clientDestructionSnapshot = snapshot
    storage.clientDestroyHandler?(snapshot)
}

@unsafe func notifyResourceDestroyed(_ pointer: UnsafeMutableRawPointer?) {
    guard let pointer = unsafe pointer else { return }
    let storage = unsafe Unmanaged<ServerNativeStorage>.fromOpaque(pointer).takeUnretainedValue()
    guard let observer = storage.observer else { preconditionFailure("Native resource watch has no observer.") }
    let snapshot = unsafe snapshotResource(UnsafeMutablePointer<wl_resource>(storage.pointer))
    do { _ = unsafe try observer.destroyed() }
    catch { preconditionFailure("Native resource destruction violated the framed leaf contract: \(error)") }
    storage.resourceDestructionSnapshot = snapshot
    storage.resourceDestroyHandler?(snapshot)
}

// The cleanup record retains watch storage through complete native-frame retirement.
@safe final class ServerNativeStorage {
    let pointer: OpaquePointer
    var observer: NativeDestructionObserver?
    var watch: OpaquePointer?
    var dispatching = false
    var typedRegistry: TypedServerRegistry?
    var typedContext: AnyObject?
    var clients: [UInt: ServerNativeStorage] = [:]
    var globalFilter: ServerGlobalFilterState?
    var nativeIdentity: HandleIdentity?
    var resourceObservers: [UInt: NativeDestructionObserver] = [:]
    var resourceDestroyHandler: ((ServerResourceSnapshot) -> Void)?
    var clientDestroyHandler: ((ServerClientSnapshot) -> Void)?
    var resourceDestructionSnapshot: ServerResourceSnapshot?
    var clientDestructionSnapshot: ServerClientSnapshot?
    init(_ pointer: OpaquePointer) { unsafe self.pointer = pointer }
    func retireWatch() {
        if let watch = unsafe watch { unsafe wayland_kit_watch_destroy(watch) }
        unsafe watch = nil
        observer = nil
        typedContext = nil
        resourceDestroyHandler = nil
        clientDestroyHandler = nil
    }
    deinit { retireWatch() }
}

final class ServerWatchRetirement {
    let storage: ServerNativeStorage
    private let onRetire: () -> Void
    init(_ storage: ServerNativeStorage, onRetire: @escaping () -> Void = {}) { self.storage = storage; self.onRetire = onRetire }
    deinit { storage.retireWatch(); onRetire() }
}

/// Owns a native server resource with external-destruction invalidation.
///
/// The native destroy watch retains copied identity through record retirement.
/// A surviving reference never authorizes native access after client destruction.
@safe public struct ServerResource: ~Copyable {
    let storage: ServerNativeStorage
    private let owner: OwnedHandle
    init(storage: ServerNativeStorage, owner: consuming OwnedHandle) {
        self.storage = storage
        self.owner = owner
    }
    /// Provides checked resource identity without native pointer exposure.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Returns the native identifier only while the resource remains live.
    public borrowing func identifier() throws -> UInt32 {
        try lifetime.withAccess(matching: .serverResource) { unsafe wl_resource_get_id(UnsafeMutablePointer<wl_resource>(storage.pointer)) }
    }
    /// Requests local destruction through the shared cleanup arbiter.
    @discardableResult
    public borrowing func requestClose() -> CloseProgress { owner.requestClose() }
    /// Consumes resource authority; native-consumed records never destroy twice.
    @discardableResult
    public consuming func close() -> CloseProgress { owner.close() }
}

/// Owns a server client and observes native client/resource cascading destruction.
@safe public struct ServerClient: ~Copyable {
    let storage: ServerNativeStorage
    private let owner: OwnedHandle
    init(storage: ServerNativeStorage, owner: consuming OwnedHandle) {
        self.storage = storage
        self.owner = owner
    }
    /// Provides checked client identity and the root for its native resource subtree.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Requests client destruction after tracked resource dependents retire.
    @discardableResult
    public borrowing func requestClose() -> CloseProgress { owner.requestClose() }
    /// Consumes client authority without repeating an external native destroy.
    @discardableResult
    public consuming func close() -> CloseProgress { owner.close() }

    /// Creates an ordinary native resource with immutable, caller-owned metadata.
    ///
    /// The interface must outlive all native users. Its version and identifier
    /// must obey the protocol constructor contract. This low-level allocation
    /// does not install an arbitrary request implementation or pretend its raw
    /// metadata is safe. Creation and watch failure roll back the native resource.
    @unsafe public borrowing func createResource(
        in session: borrowing OwnershipSession, interface: UnsafePointer<wl_interface>, version: Int32, identifier: UInt32 = 0
    ) throws -> ServerResource {
        try lifetime.withAccess(matching: .serverClient) {
            guard version > 0 && version <= (unsafe interface.pointee.version) else { throw ServerError.nativeFailure(EINVAL) }
            guard let pointer = unsafe wl_resource_create(storage.pointer, interface, version, identifier) else {
                throw ServerError.nativeFailure(errno)
            }
            let resource = unsafe ServerNativeStorage(OpaquePointer(pointer))
            let key = UInt(bitPattern: pointer)
            let retirement = ServerWatchRetirement(resource) { [weak clientStorage = storage] in
                if let identity = resource.nativeIdentity, clientStorage?.resourceObservers[key]?.identity == identity {
                    clientStorage?.resourceObservers.removeValue(forKey: key)
                }
            }
            var adopted = false
            defer { if !adopted { unsafe wl_resource_destroy(pointer) } }
            let owner = unsafe try session.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .serverResource,
                                                dependencies: [lifetime]) {
                withExtendedLifetime(retirement) { unsafe wl_resource_destroy(UnsafeMutablePointer<wl_resource>(resource.pointer)) }
            }
            adopted = true
            let observer = owner.reference.destructionObserver()
            resource.observer = observer
            resource.nativeIdentity = observer.identity
            unsafe resource.watch = wayland_kit_watch_resource(pointer, notifyResourceDestroyed,
                                                              Unmanaged.passUnretained(resource).toOpaque())
            guard unsafe resource.watch != nil else { throw ServerError.nativeFailure(ENOMEM) }
            storage.resourceObservers[key] = observer
            return ServerResource(storage: resource, owner: owner)
        }
    }
}

/// Owns a server display and serialized execution of its event loop.
///
/// Children are released before display destruction. Native client disconnects
/// observed inside dispatch consume their tracked resource subtree immediately,
/// retaining watch storage until the complete event-loop frame exits.
@safe public struct ServerDisplay: ~Copyable {
    let storage: ServerNativeStorage
    private let session: OwnershipSession
    private let owner: OwnedHandle

    /// Allocates a display and publishes its single native destruction obligation.
    public init(maximumRecords: Int = 65_536) throws {
        guard let pointer = unsafe wl_display_create() else { throw ServerError.nativeFailure(errno) }
        var adopted = false
        defer { if !adopted { unsafe wl_display_destroy(pointer) } }
        let session = try OwnershipSession(maximumRecords: maximumRecords)
        let displayStorage = unsafe ServerNativeStorage(pointer)
        let owner = unsafe try session.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .serverDisplay) {
            withExtendedLifetime(displayStorage) {
                unsafe wl_display_destroy_clients(pointer)
                unsafe wl_display_destroy(pointer)
                displayStorage.clients.removeAll()
                displayStorage.globalFilter = nil
            }
        }
        adopted = true
        storage = displayStorage
        displayStorage.observer = owner.reference.destructionObserver()
        self.session = session
        self.owner = owner
    }
    /// Provides display identity without exposing native storage.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Returns resource accounting after native dispatch or shutdown.
    public borrowing func snapshot() throws -> OwnershipSnapshot { try session.snapshot() }
    /// Requests shutdown of the complete display domain.
    @discardableResult
    public borrowing func requestClose() -> CloseProgress {
        try? lifetime.withAccess(matching: .serverDisplay) {
            if storage.dispatching { unsafe wl_display_terminate(storage.pointer) }
        }
        return session.requestClose()
    }

    /// Creates a client from an exclusively owned connected socket, consuming every outcome.
    ///
    /// Unlike the client display connector, wl_client_create leaves its fd open
    /// on native failure. This adapter closes that input explicitly on failure.
    @unsafe public borrowing func createClient(receiving descriptor: Int32) throws -> ServerClient {
        var consumed = false
        defer { if !consumed { _ = Glibc.close(descriptor) } }
        return try lifetime.withAccess(matching: .serverDisplay) {
            guard let pointer = unsafe wl_client_create(storage.pointer, descriptor) else { throw ServerError.nativeFailure(errno) }
            consumed = true
            let client = unsafe ServerNativeStorage(pointer)
            let key = UInt(bitPattern: pointer)
            let retirement = ServerWatchRetirement(client) { [weak displayStorage = storage] in displayStorage?.clients.removeValue(forKey: key) }
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
                                                          Unmanaged.passUnretained(client).toOpaque())
            guard unsafe client.watch != nil else { throw ServerError.nativeFailure(ENOMEM) }
            storage.clients[key] = client
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
    public borrowing func dispatch(timeoutMilliseconds: Int32 = 0) throws {
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
    @unsafe public borrowing func createResource(
        for client: borrowing ServerClient, interface: UnsafePointer<wl_interface>, version: Int32, identifier: UInt32 = 0
    ) throws -> ServerResource {
        guard client.lifetime.identity.session == lifetime.identity.session else { throw OwnershipError.foreignSession }
        return unsafe try client.createResource(in: session, interface: interface, version: version, identifier: identifier)
    }
}

extension ServerClient {
    /// Produces a checked client reference without transferring native close authority.
    public borrowing func reference() throws -> ServerClientReference {
        try lifetime.withAccess(matching: .serverClient) {
            let registry: TypedServerRegistry
            if let existing = storage.typedRegistry { registry = existing }
            else {
                registry = unsafe TypedServerRegistry(client: storage.pointer, lifetime: lifetime)
                registry.storage = storage
                storage.typedRegistry = registry
            }
            return ServerClientReference(registry: registry, lifetime: lifetime)
        }
    }
}

extension ServerDisplay {
    /// Adds a native named socket owned internally until this display is destroyed.
    public borrowing func addSocket(name: String? = nil) throws {
        guard name.map({ !$0.utf8.contains(0) }) ?? true else { throw ServerError.nativeFailure(EINVAL) }
        try lifetime.withAccess(matching: .serverDisplay) {
            let result: Int32
            if let name { result = name.withCString { unsafe wl_display_add_socket(storage.pointer, $0) } }
            else { result = unsafe wl_display_add_socket(storage.pointer, nil) }
            guard result == 0 else { throw ServerError.nativeFailure(errno) }
        }
    }
    /// Chooses a native socket name and returns an owned copy of the display-owned string.
    public borrowing func addAutomaticSocket() throws -> String {
        try lifetime.withAccess(matching: .serverDisplay) {
            guard let name = unsafe wl_display_add_socket_auto(storage.pointer) else { throw ServerError.nativeFailure(errno) }
            return unsafe String(cString: name)
        }
    }
    /// Flushes every native client under the display execution domain.
    public borrowing func flushClients() throws {
        try lifetime.withAccess(matching: .serverDisplay) { unsafe wl_display_flush_clients(storage.pointer) }
    }
    /// Returns the current display serial without advancing it.
    public borrowing func serial() throws -> UInt32 {
        try lifetime.withAccess(matching: .serverDisplay) { unsafe wl_display_get_serial(storage.pointer) }
    }
    /// Advances and returns the native serial, preserving native wraparound semantics.
    public borrowing func nextSerial() throws -> UInt32 {
        try lifetime.withAccess(matching: .serverDisplay) { unsafe wl_display_next_serial(storage.pointer) }
    }
    /// Runs the native loop under one complete frame until terminated or closed.
    public borrowing func run() throws {
        try lifetime.withAccess(matching: .serverDisplay) {
            guard !storage.dispatching else { throw ServerError.recursiveDispatch }
            storage.dispatching = true
            defer { storage.dispatching = false }
            unsafe wl_display_run(storage.pointer)
        }
    }
    /// Terminates a native run loop from its serialized domain, including a synchronous callback.
    public borrowing func terminate() throws {
        try lifetime.withAccess(matching: .serverDisplay) { unsafe wl_display_terminate(storage.pointer) }
    }
    /// Applies the native default client buffer limit without altering existing client policy.
    public borrowing func setDefaultMaximumBufferSize(_ bytes: Int) throws {
        guard bytes >= 0 else { throw ServerError.nativeFailure(EINVAL) }
        try lifetime.withAccess(matching: .serverDisplay) { unsafe wl_display_set_default_max_buffer_size(storage.pointer, bytes) }
    }
}
