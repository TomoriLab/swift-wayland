import Glibc
import CWaylandServer
import WaylandProtocol
import WaylandRuntime

/// Copies native client credentials without borrowing a live client pointer.
public struct ServerClientSnapshot: Equatable, Sendable {
    /// The peer process identifier reported by the native connection.
    public let processIdentifier: Int32
    /// The peer user identifier reported by the native connection.
    public let userIdentifier: UInt32
    /// The peer group identifier reported by the native connection.
    public let groupIdentifier: UInt32
}
/// Copies the global metadata usable from a filter without recursive name lookup.
public struct ServerGlobalSnapshot: Equatable, Sendable {
    /// The immutable native interface name.
    public let interfaceName: String
    /// The version advertised by the global.
    public let version: UInt32
}
@unsafe func snapshotClient(_ pointer: OpaquePointer) -> ServerClientSnapshot {
    var process: pid_t = 0
    var user: uid_t = 0
    var group: gid_t = 0
    unsafe wl_client_get_credentials(pointer, &process, &user, &group)
    return ServerClientSnapshot(processIdentifier: process, userIdentifier: user, groupIdentifier: group)
}

extension ServerNativeStorage {
    @unsafe func clientRegistry(_ pointer: OpaquePointer) throws -> TypedServerRegistry {
        guard let observer else { throw OwnershipError.closedSession }
        return try observer.withLiveReference { display in
            let key = UInt(bitPattern: pointer)
            let client: ServerNativeStorage
            if let existing = clients[key] { client = existing }
            else {
                client = unsafe ServerNativeStorage(pointer)
                let retirement = ServerWatchRetirement(client) { [weak self] in self?.clients.removeValue(forKey: key) }
                let owner = unsafe try display.adopt(nativeIdentifier: UInt64(key), kind: .serverClient, dependencies: [display]) {
                    withExtendedLifetime(retirement) { unsafe wl_client_destroy(client.pointer) }
                }
                let notification = owner.reference.destructionObserver()
                client.observer = notification
                unsafe client.watch = wayland_kit_watch_client(pointer, notifyClientDestroyed,
                    Unmanaged.passUnretained(client).toOpaque())
                guard unsafe client.watch != nil else { throw ServerError.nativeFailure(ENOMEM) }
                _ = owner.surrenderToRoot()
                clients[key] = client
            }
            guard let notification = client.observer else { throw OwnershipError.invalidHandle }
            return try notification.withLiveReference { reference in
                if let registry = client.typedRegistry { return registry }
                let registry = unsafe TypedServerRegistry(client: pointer, lifetime: reference)
                registry.storage = client
                client.typedRegistry = registry
                return registry
            }
        }
    }
}

/// Provides checked client operations while destruction remains with an owner or display root.
public struct ServerClientReference {
    let registry: TypedServerRegistry
    /// Provides checked client identity without destruction authority.
    public let lifetime: ObjectHandle
    /// Creates an unpublished resource with a server-selected ID.
    public func createObject<I: ServerInterface>(as type: I.Type, version: UInt32) throws -> ServerObject<I> {
        try lifetime.withAccess(matching: .serverClient) { try registry.create(type, identifier: 0, version: version) }
    }
    /// Copies peer credentials while the client remains live.
    public func snapshot() throws -> ServerClientSnapshot {
        try lifetime.withAccess(matching: .serverClient) { unsafe snapshotClient(registry.client) }
    }
}
extension ServerNewIdentifier {
    /// Produces a client reference without transferring or resolving this constructor obligation.
    public borrowing func clientReference() throws -> ServerClientReference {
        try pending.registry.observer.withLiveReference { ServerClientReference(registry: pending.registry, lifetime: $0) }
    }
}

@safe private final class ServerGlobalState {
    let display: ServerNativeStorage
    let schema: ProtocolInterfaceSchema
    let descriptor: ProtocolDescriptor?
    let version: UInt32
    let handler: (PendingServerIdentifier) throws -> Void
    var observer: NativeDestructionObserver?
    var pointer: OpaquePointer?
    var removed = false
    var withdrawn = false
    var failure: (any Error)?
    var withdrawalHandler: (() throws -> Void)?
    init(display: ServerNativeStorage, schema: ProtocolInterfaceSchema, descriptor: ProtocolDescriptor?, version: UInt32,
         handler: @escaping (PendingServerIdentifier) throws -> Void) {
        self.display = display; self.schema = schema; self.descriptor = descriptor
        self.version = version; self.handler = handler
    }
}
@unsafe private func bindGlobal(_ client: OpaquePointer?, _ pointer: UnsafeMutableRawPointer?, _ version: UInt32, _ identifier: UInt32) {
    guard let client = unsafe client, let pointer = unsafe pointer else { return }
    let state = unsafe Unmanaged<ServerGlobalState>.fromOpaque(pointer).takeUnretainedValue()
    do {
        guard let observer = state.observer else { throw OwnershipError.invalidHandle }
        try observer.withCallback {
            guard version > 0, version <= state.version else { throw ServerProtocolError.unsupportedVersion }
            let registry = unsafe try state.display.clientRegistry(client)
            let pending = PendingServerIdentifier(registry: registry, identifier: identifier, interface: state.schema.name,
                                                  version: version, requiredDescriptor: state.descriptor)
            try state.handler(pending)
        }
    } catch {
        state.failure = error
        unsafe wayland_kit_reject_constructor(client)
    }
}
@unsafe private func globalWithdrawn(_ global: OpaquePointer?) {
    guard let global = unsafe global, let pointer = unsafe wl_global_get_user_data(global) else { return }
    let state = unsafe Unmanaged<ServerGlobalState>.fromOpaque(pointer).takeUnretainedValue()
    state.withdrawn = true
    do { try state.observer?.withCallback { try state.withdrawalHandler?() } }
    catch { state.failure = error }
}

/// Owns a published global, its typed bind callback, and native withdrawal notification.
public struct ServerGlobal<Interface: ServerInterface>: ~Copyable {
    private let state: ServerGlobalState
    private let owner: OwnedHandle
    fileprivate init(state: ServerGlobalState, owner: consuming OwnedHandle) { self.state = state; self.owner = owner }
    /// Provides checked global identity without raw userdata access.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Returns a copied advertised version.
    public var version: UInt32 { borrowing get { state.version } }
    /// Reports the native withdrawn notification, including after invalidation.
    public var isWithdrawn: Bool { borrowing get { state.withdrawn } }
    /// Returns a saved bind or withdrawal callback failure.
    public var failure: (any Error)? { borrowing get { state.failure } }
    /// Installs the optional synchronous withdrawn handler while this global is live.
    public borrowing func onWithdrawn(_ body: @escaping () throws -> Void) throws {
        try lifetime.withAccess(matching: .serverGlobal) { state.withdrawalHandler = body }
    }
    /// Removes advertisement once while retaining allocation and context for native offers.
    public borrowing func withdraw() throws {
        try lifetime.withAccess(matching: .serverGlobal) {
            if state.removed { return }
            guard let pointer = unsafe state.pointer else { throw OwnershipError.invalidHandle }
            state.removed = true
            unsafe wl_global_remove(pointer)
        }
    }
    /// Returns this global's visible name for one live client, preserving native filter policy.
    public borrowing func name(for client: ServerClientReference) throws -> UInt32 {
        guard client.lifetime.identity.session == lifetime.identity.session else { throw OwnershipError.foreignSession }
        return try lifetime.withAccess(matching: .serverGlobal) {
            try client.lifetime.withAccess(matching: .serverClient) {
                guard let pointer = unsafe state.pointer else { throw OwnershipError.invalidHandle }
                return unsafe wl_global_get_name(pointer, client.registry.client)
            }
        }
    }
    /// Requests deferred global destruction independently of withdrawn delivery.
    @discardableResult public borrowing func requestClose() -> CloseProgress { owner.requestClose() }
    /// Consumes global authority and destroys remaining native offers exactly once.
    @discardableResult public consuming func close() -> CloseProgress { owner.close() }
}

/// Owns a published imported global and retains its descriptor through native destruction.
public struct ServerProtocolGlobal: ~Copyable {
    fileprivate let state: ServerGlobalState
    fileprivate let owner: OwnedHandle
    fileprivate init(state: ServerGlobalState, owner: consuming OwnedHandle) {
        self.state = state; self.owner = owner
    }
    /// Provides the authoritative global identity.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Returns the advertised version.
    public var version: UInt32 { borrowing get { state.version } }
    /// Reports native withdrawal after removing the advertisement.
    public var isWithdrawn: Bool { borrowing get { state.withdrawn } }
    /// Returns a saved bind or withdrawal callback failure.
    public var failure: (any Error)? { borrowing get { state.failure } }
    /// Installs a synchronous withdrawn callback under the global's runtime lease.
    public borrowing func onWithdrawn(_ body: @escaping () throws -> Void) throws {
        try lifetime.withAccess(matching: .serverGlobal) { state.withdrawalHandler = body }
    }
    /// Removes advertisement once while retaining native offer storage.
    public borrowing func withdraw() throws {
        try lifetime.withAccess(matching: .serverGlobal) {
            if state.removed { return }
            guard let pointer = unsafe state.pointer else { throw OwnershipError.invalidHandle }
            state.removed = true
            unsafe wl_global_remove(pointer)
        }
    }
    /// Returns this global's visible name for one live client.
    public borrowing func name(for client: ServerClientReference) throws -> UInt32 {
        guard client.lifetime.identity.session == lifetime.identity.session else { throw OwnershipError.foreignSession }
        return try lifetime.withAccess(matching: .serverGlobal) {
            try client.lifetime.withAccess(matching: .serverClient) {
                guard let pointer = unsafe state.pointer else { throw OwnershipError.invalidHandle }
                return unsafe wl_global_get_name(pointer, client.registry.client)
            }
        }
    }
    /// Requests deferred destruction through the existing global record.
    @discardableResult public borrowing func requestClose() -> CloseProgress { owner.requestClose() }
    /// Consumes global authority and destroys native offers exactly once.
    @discardableResult public consuming func close() -> CloseProgress { owner.close() }
}

extension ServerDisplay {
    /// Publishes pinned core metadata with a consuming typed bind constructor.
    ///
    /// Every bind must accept its constructor or reject the client. Accepted
    /// clients are root-managed when no explicit application owner exists.
    public borrowing func addGlobal<I: ServerInterface>(
        as type: I.Type, version: UInt32, handler: @escaping (consuming ServerNewIdentifier<I>) throws -> Void
    ) throws -> ServerGlobal<I> {
        let schema = try CoreProtocol.requireSchema(for: I.self)
        let global = try addManagedGlobal(schema: schema, descriptor: nil, version: version) { pending in
            try handler(ServerNewIdentifier(pending))
        }
        return ServerGlobal(state: global.state, owner: consume global.owner)
    }

    /// Advertises a sealed imported interface with an owned bind constructor.
    public borrowing func addProtocolGlobal(descriptor: ProtocolDescriptor, version: UInt32,
        handler: @escaping (consuming ServerDynamicIdentifier) throws -> Void) throws -> ServerProtocolGlobal {
        try addManagedGlobal(schema: descriptor.schema, descriptor: descriptor, version: version) { pending in
            try handler(ServerDynamicIdentifier(pending))
        }
    }

    private borrowing func addManagedGlobal(schema: ProtocolInterfaceSchema, descriptor: ProtocolDescriptor?, version: UInt32,
        handler: @escaping (PendingServerIdentifier) throws -> Void) throws -> ServerProtocolGlobal {
        guard schema.name != "wl_display", schema.name != "wl_registry", version > 0, version <= schema.version else {
            throw ServerProtocolError.unsupportedVersion
        }
        return try lifetime.withAccess(matching: .serverDisplay) {
            let state = ServerGlobalState(display: storage, schema: schema, descriptor: descriptor, version: version, handler: handler)
            let pointer: OpaquePointer?
            if let descriptor {
                unsafe pointer = descriptor.withUnsafeInterface { interface in
                    unsafe wl_global_create(storage.pointer, interface, Int32(version), Unmanaged.passUnretained(state).toOpaque(), bindGlobal)
                }
            } else {
                let interface = schema.name.withCString { unsafe wayland_kit_server_core_interface($0) }
                unsafe pointer = interface.flatMap { unsafe wl_global_create(storage.pointer, $0, Int32(version), Unmanaged.passUnretained(state).toOpaque(), bindGlobal) }
            }
            guard let pointer = unsafe pointer else {
                throw ServerError.nativeFailure(ENOMEM)
            }
            unsafe state.pointer = pointer
            var adopted = false
            defer { if !adopted { unsafe wl_global_destroy(pointer) } }
            let owner = unsafe try lifetime.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .serverGlobal, dependencies: [lifetime]) {
                withExtendedLifetime(state) { unsafe wl_global_destroy(pointer); unsafe state.pointer = nil }
            }
            adopted = true
            state.observer = owner.reference.destructionObserver()
            unsafe wl_global_set_withdrawn_listener(pointer, globalWithdrawn)
            return ServerProtocolGlobal(state: state, owner: owner)
        }
    }
}

@safe final class ServerGlobalFilterState {
    weak var display: ServerNativeStorage?
    let handler: (ServerClientSnapshot, ServerGlobalSnapshot) throws -> Bool
    var observer: NativeDestructionObserver?
    var attached = false
    var failure: (any Error)?
    init(display: ServerNativeStorage, handler: @escaping (ServerClientSnapshot, ServerGlobalSnapshot) throws -> Bool) {
        self.display = display; self.handler = handler
    }
}
@unsafe private func filterGlobal(_ client: OpaquePointer?, _ global: OpaquePointer?, _ pointer: UnsafeMutableRawPointer?) -> Bool {
    guard let client = unsafe client, let global = unsafe global, let pointer = unsafe pointer else { return false }
    let state = unsafe Unmanaged<ServerGlobalFilterState>.fromOpaque(pointer).takeUnretainedValue()
    do {
        guard let observer = state.observer else { return false }
        return try observer.withCallback {
            let interface = unsafe wl_global_get_interface(global)!
            let snapshot = unsafe ServerGlobalSnapshot(interfaceName: String(cString: interface.pointee.name), version: wl_global_get_version(global))
            return try state.handler(unsafe snapshotClient(client), snapshot)
        }
    } catch { state.failure = error; return false }
}
/// Owns one managed filter installation; replacement retirement cannot clear its successor.
public struct ServerGlobalFilter: ~Copyable {
    private let state: ServerGlobalFilterState
    private let owner: OwnedHandle
    fileprivate init(state: ServerGlobalFilterState, owner: consuming OwnedHandle) { self.state = state; self.owner = owner }
    /// Reports whether this installation is still the native display's current filter.
    public var isAttached: Bool { borrowing get { state.attached } }
    /// Returns a saved filter exception; throwing filters fail closed.
    public var failure: (any Error)? { borrowing get { state.failure } }
    /// Consumes registration authority and clears only this current installation.
    @discardableResult public consuming func close() -> CloseProgress { owner.close() }
}
extension ServerDisplay {
    /// Replaces the library-managed global filter with copied, nonescaping metadata inputs.
    public borrowing func setGlobalFilter(
        _ handler: @escaping (ServerClientSnapshot, ServerGlobalSnapshot) throws -> Bool
    ) throws -> ServerGlobalFilter {
        try lifetime.withAccess(matching: .serverDisplay) {
            let state = ServerGlobalFilterState(display: storage, handler: handler)
            let pointer = unsafe Unmanaged.passUnretained(state).toOpaque()
            let owner = unsafe try lifetime.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .registration, dependencies: [lifetime]) {
                if state.attached, let display = state.display {
                    unsafe wl_display_set_global_filter(display.pointer, nil, nil)
                    state.attached = false
                    if display.globalFilter === state { display.globalFilter = nil }
                }
            }
            state.observer = owner.reference.destructionObserver()
            storage.globalFilter?.attached = false
            unsafe wl_display_set_global_filter(storage.pointer, filterGlobal, pointer)
            state.attached = true
            storage.globalFilter = state
            return ServerGlobalFilter(state: state, owner: owner)
        }
    }
}
