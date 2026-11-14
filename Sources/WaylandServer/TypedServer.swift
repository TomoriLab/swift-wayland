import Glibc
import CWaylandServer
import WaylandProtocol
import WaylandRuntime

/// Associates a core interface with its ownership-bearing request sum type.
public protocol ServerInterface: CoreInterface {
    /// The generated noncopyable request type.
    associatedtype Request: ~Copyable
    /// Decodes arguments in wire order and transfers incoming obligations.
    static func decodeRequest(_ reader: inout ServerMessageReader) throws -> Request
}

/// Describes typed server validation failures before resource publication or event delivery.
public enum ServerProtocolError: Error, Equatable, Sendable {
    /// The native interface, message, payload, or constructor capability is incompatible.
    case invalidMessage
    /// The negotiated version does not support the operation.
    case unsupportedVersion
    /// An object belongs to another client or has already been invalidated.
    case foreignObject
}

final class WeakServerEndpoint {
    weak var value: TypedServerEndpoint?
    init(_ value: TypedServerEndpoint) { self.value = value }
}
final class ServerDiagnostics { var failure: (any Error)? }
final class ServerDeliveryGate { var enabled = true; var issued = false }

/// Cancels request delivery while preserving mandatory request decoding and native context lifetime.
public struct ServerRequestSubscription: ~Copyable {
    private let gate: ServerDeliveryGate
    init(_ gate: ServerDeliveryGate) { self.gate = gate }
    /// Disables optional user delivery without detaching the resource dispatcher.
    public borrowing func cancel() { gate.enabled = false }
    deinit { gate.enabled = false }
}

@safe final class TypedServerRegistry {
    let client: OpaquePointer
    let observer: NativeDestructionObserver
    var objects: [UInt: WeakServerEndpoint] = [:]
    var destroying: [UInt: HandleIdentity] = [:]
    weak var storage: ServerNativeStorage?
    init(client: OpaquePointer, lifetime: ObjectHandle) {
        unsafe self.client = client
        observer = lifetime.destructionObserver()
    }
    func reject() {
        try? observer.withLiveReference { _ in
            unsafe wayland_kit_reject_constructor(client)
            _ = unsafe observer.protocolClosed()
        }
    }
    func create<I: ServerInterface>(_ type: I.Type, identifier: UInt32, version: UInt32) throws -> ServerObject<I> {
        let schema = try CoreProtocol.requireSchema(for: I.self)
        let object = try createManaged(schema: schema, descriptor: nil, identifier: identifier, version: version) { reader in
            let request = try I.decodeRequest(&reader)
            _ = consume request
        }
        return ServerObject(resource: consume object.resource, endpoint: object.endpoint)
    }
    func create(descriptor: ProtocolDescriptor, identifier: UInt32, version: UInt32) throws -> ServerProtocolObject {
        try createManaged(schema: descriptor.schema, descriptor: descriptor, identifier: identifier, version: version) { _ in }
    }
    private func createManaged(schema: ProtocolInterfaceSchema, descriptor: ProtocolDescriptor?, identifier: UInt32,
                               version: UInt32, discard: @escaping (inout ServerMessageReader) throws -> Void) throws -> ServerProtocolObject {
        guard schema.name != "wl_display", version > 0, version <= schema.version else { throw ServerProtocolError.unsupportedVersion }
        return try observer.withLiveReference { clientLifetime in
            let pointer: UnsafeMutablePointer<wl_resource>?
            if let descriptor {
                unsafe pointer = descriptor.withUnsafeInterface { interface in
                    unsafe wl_resource_create(client, interface, Int32(version), identifier)
                }
            } else {
                let interface = schema.name.withCString { unsafe wayland_kit_server_core_interface($0) }
                unsafe pointer = interface.flatMap { unsafe wl_resource_create(client, $0, Int32(version), identifier) }
            }
            guard let pointer = unsafe pointer else {
                throw ServerError.nativeFailure(ENOMEM)
            }
            var adopted = false
            defer { if !adopted { unsafe wl_resource_destroy(pointer) } }
            let storage = unsafe ServerNativeStorage(OpaquePointer(pointer))
            let key = UInt(bitPattern: pointer)
            let retirement = ServerWatchRetirement(storage) { [weak clientStorage = self.storage, weak self] in
                if let identity = storage.nativeIdentity, clientStorage?.resourceObservers[key]?.identity == identity {
                    clientStorage?.resourceObservers.removeValue(forKey: key)
                }
                if self?.objects[key]?.value == nil || self?.objects[key]?.value?.lifetime.identity == storage.nativeIdentity { self?.objects.removeValue(forKey: key) }
            }
            let owner = unsafe try clientLifetime.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .serverResource,
                                                        dependencies: [clientLifetime]) {
                withExtendedLifetime(retirement) { unsafe wl_resource_destroy(UnsafeMutablePointer<wl_resource>(storage.pointer)) }
            }
            adopted = true
            let resourceObserver = owner.reference.destructionObserver()
            storage.observer = resourceObserver
            storage.nativeIdentity = resourceObserver.identity
            unsafe storage.watch = wayland_kit_watch_resource(pointer, notifyResourceDestroyed,
                Unmanaged.passUnretained(storage).toOpaque())
            guard unsafe storage.watch != nil else { throw ServerError.nativeFailure(ENOMEM) }
            let context = TypedServerContext(registry: self, observer: resourceObserver, schema: schema, descriptor: descriptor,
                                             version: version, discard: discard)
            storage.typedContext = context
            unsafe wl_resource_set_dispatcher(pointer, dispatchTypedServer, nil, Unmanaged.passUnretained(context).toOpaque(), nil)
            let endpoint = unsafe TypedServerEndpoint(pointer: pointer, lifetime: owner.reference, registry: self,
                                                      schema: schema, version: version, context: context, published: identifier != 0)
            self.storage?.resourceObservers[endpoint.key] = resourceObserver
            objects[endpoint.key] = WeakServerEndpoint(endpoint)
            return ServerProtocolObject(resource: ServerResource(storage: storage, owner: owner), endpoint: endpoint)
        }
    }
}

@safe final class TypedServerEndpoint {
    let pointer: UnsafeMutablePointer<wl_resource>
    let key: UInt
    let lifetime: ObjectHandle
    let registry: TypedServerRegistry
    let schema: ProtocolInterfaceSchema
    let version: UInt32
    let diagnostics: ServerDiagnostics
    var published: Bool
    weak var context: TypedServerContext?
    init(pointer: UnsafeMutablePointer<wl_resource>, lifetime: ObjectHandle, registry: TypedServerRegistry,
         schema: ProtocolInterfaceSchema, version: UInt32, context: TypedServerContext?, published: Bool) {
        unsafe self.pointer = pointer
        key = UInt(bitPattern: pointer)
        self.lifetime = lifetime; self.registry = registry; self.schema = schema; self.version = version
        self.context = context; diagnostics = context?.diagnostics ?? ServerDiagnostics(); self.published = published
    }
}
final class TypedServerContext {
    let registry: TypedServerRegistry
    let observer: NativeDestructionObserver
    let schema: ProtocolInterfaceSchema
    let descriptor: ProtocolDescriptor?
    let version: UInt32
    let diagnostics = ServerDiagnostics()
    let gate = ServerDeliveryGate()
    let discard: (inout ServerMessageReader) throws -> Void
    var handler: ((inout ServerMessageReader) throws -> Void)?
    init(registry: TypedServerRegistry, observer: NativeDestructionObserver, schema: ProtocolInterfaceSchema, descriptor: ProtocolDescriptor?,
         version: UInt32, discard: @escaping (inout ServerMessageReader) throws -> Void) {
        self.registry = registry; self.observer = observer; self.schema = schema; self.descriptor = descriptor
        self.version = version; self.discard = discard
    }
    deinit {
        let key = UInt(observer.identity.nativeIdentifier)
        if registry.objects[key]?.value == nil || registry.objects[key]?.value?.lifetime.identity == observer.identity {
            registry.objects.removeValue(forKey: key)
        }
    }
}

/// Owns one server resource backed by an immutable imported protocol descriptor.
public struct ServerProtocolObject: ~Copyable {
    let resource: ServerResource
    let endpoint: TypedServerEndpoint
    init(resource: consuming ServerResource, endpoint: TypedServerEndpoint) {
        self.resource = resource; self.endpoint = endpoint
    }
    /// Produces a checked reference without native destruction authority.
    public var reference: ServerProtocolReference { borrowing get { ServerProtocolReference(endpoint: endpoint) } }
    /// Provides authoritative invalidation and accounting identity.
    public var lifetime: ObjectHandle { borrowing get { resource.lifetime } }
    /// Returns a saved request handler or decoder error.
    public var failure: (any Error)? { borrowing get { endpoint.diagnostics.failure } }
    /// Delivers request fields only while the native callback frame is active.
    public borrowing func onRequest(_ body: @escaping (inout ServerMessageReader) throws -> Void) throws -> ServerRequestSubscription {
        try lifetime.withAccess {
            guard let context = endpoint.context, !context.gate.issued else { throw ServerProtocolError.invalidMessage }
            context.gate.issued = true
            context.handler = body
            return ServerRequestSubscription(context.gate)
        }
    }
    /// Consumes the single resource destruction obligation.
    @discardableResult public consuming func close() -> CloseProgress { resource.close() }
}

/// Provides checked identity for one managed imported server resource.
public struct ServerProtocolReference {
    let endpoint: TypedServerEndpoint
    init(endpoint: TypedServerEndpoint) { self.endpoint = endpoint }
    /// Reports point-in-time validity; each operation takes a fresh runtime lease.
    public var isValid: Bool { endpoint.lifetime.isValid }
    /// Returns the negotiated interface version.
    public var version: UInt32 { endpoint.version }
    /// Returns the immutable schema used for native metadata.
    public var schema: ProtocolInterfaceSchema { endpoint.schema }
    /// Admits a generated typed wrapper only when the retained native graph matches.
    public func requireEquivalent(to expectedInterfaces: [ProtocolInterfaceSchema]) throws {
        try endpoint.lifetime.withAccess {
            guard let descriptor = endpoint.context?.descriptor else { throw ServerProtocolError.invalidMessage }
            try descriptor.requireEquivalent(to: expectedInterfaces)
        }
    }
    /// Erases the interface while preserving this client's resource checks.
    public var erased: AnyServerObjectReference { AnyServerObjectReference(endpoint: endpoint) }
    /// Sends an event after validating its opcode, version, argument kinds, and leases.
    public func send(opcode: UInt32, arguments: [ServerEventArgument] = []) throws {
        try endpoint.send(opcode: opcode, arguments: arguments.map(\.wire))
    }
}

/// Owns a typed resource and its permanently attached request dispatcher.
public struct ServerObject<Interface: ServerInterface>: ~Copyable {
    let resource: ServerResource
    let endpoint: TypedServerEndpoint
    init(resource: consuming ServerResource, endpoint: TypedServerEndpoint) { self.resource = resource; self.endpoint = endpoint }
    /// Produces a checked reference without resource destruction authority.
    public var reference: ServerObjectReference<Interface> { borrowing get { ServerObjectReference(endpoint) } }
    /// Provides authoritative invalidation and accounting identity.
    public var lifetime: ObjectHandle { borrowing get { resource.lifetime } }
    /// Returns a saved decoder or handler error, including after context retirement.
    public var failure: (any Error)? { borrowing get { endpoint.diagnostics.failure } }
    /// Installs the sole consuming request handler; canceled delivery still decodes owned arguments.
    public borrowing func onRequest(_ body: @escaping (consuming Interface.Request) throws -> Void) throws -> ServerRequestSubscription {
        try lifetime.withAccess {
            guard let context = endpoint.context, !context.gate.issued else { throw ServerProtocolError.invalidMessage }
            context.gate.issued = true
            context.handler = { reader in let request = try Interface.decodeRequest(&reader); try body(consume request) }
            return ServerRequestSubscription(context.gate)
        }
    }
    /// Consumes resource authority and defers native destruction until enclosing frames return.
    @discardableResult public consuming func close() -> CloseProgress { resource.close() }
    consuming func terminalEvent(opcode: UInt32, arguments: [ServerWireValue]) throws {
        try reference.send(opcode: opcode, arguments: arguments)
        resource.close()
    }
}

/// Provides checked access to one resource belonging to a specific client and interface.
public struct ServerObjectReference<Interface: ServerInterface> {
    let endpoint: TypedServerEndpoint
    init(_ endpoint: TypedServerEndpoint) { self.endpoint = endpoint }
    /// Reports point-in-time validity; operations validate their own leases.
    public var isValid: Bool { endpoint.lifetime.isValid }
    /// Returns copied negotiated interface version.
    public var version: UInt32 { endpoint.version }
    /// Erases interface identity while preserving runtime and client checks.
    public var erased: AnyServerObjectReference { AnyServerObjectReference(endpoint: endpoint) }
}
/// Carries an interface-generic checked server resource argument.
public struct AnyServerObjectReference { let endpoint: TypedServerEndpoint }

extension ServerClient {
    /// Creates a server-selected resource ID using pinned core metadata and a tracked request dispatcher.
    ///
    /// Client-supplied constructor IDs must instead be consumed through ServerNewIdentifier.accept.
    public borrowing func createObject<I: ServerInterface>(as type: I.Type, version: UInt32) throws -> ServerObject<I> {
        unsafe try receiveConstructor(identifier: 0, as: type, version: version)
    }
    /// Creates a managed server-selected resource using a sealed external descriptor.
    public borrowing func createProtocolObject(descriptor: ProtocolDescriptor, version: UInt32) throws -> ServerProtocolObject {
        try lifetime.withAccess {
            let registry: TypedServerRegistry
            if let existing = storage.typedRegistry { registry = existing }
            else {
                registry = unsafe TypedServerRegistry(client: storage.pointer, lifetime: lifetime)
                registry.storage = storage
                storage.typedRegistry = registry
            }
            return try registry.create(descriptor: descriptor, identifier: 0, version: version)
        }
    }
    /// Publishes an externally validated client constructor ID with imported metadata.
    ///
    /// The caller must establish that the identifier is pending for this client,
    /// names the requested interface, and is unused. Managed request constructors
    /// should instead use ServerDynamicIdentifier.accept(descriptor:).
    @unsafe public borrowing func receiveProtocolConstructor(identifier: UInt32, descriptor: ProtocolDescriptor,
                                                              version: UInt32) throws -> ServerProtocolObject {
        try lifetime.withAccess {
            let registry: TypedServerRegistry
            if let existing = storage.typedRegistry { registry = existing }
            else {
                registry = unsafe TypedServerRegistry(client: storage.pointer, lifetime: lifetime)
                registry.storage = storage
                storage.typedRegistry = registry
            }
            return try registry.create(descriptor: descriptor, identifier: identifier, version: version)
        }
    }
    /// Publishes an externally validated constructor ID through the typed dispatcher adapter.
    ///
    /// The caller must prove this ID is a pending constructor for this client and
    /// interface, is unused, and obeys its wire version. Zero requests a server ID.
    /// This hook supports native global callbacks without replacing reserved native resources.
    @unsafe public borrowing func receiveConstructor<I: ServerInterface>(identifier: UInt32, as type: I.Type, version: UInt32) throws -> ServerObject<I> {
        try lifetime.withAccess {
            let registry: TypedServerRegistry
            if let existing = storage.typedRegistry { registry = existing }
            else {
                registry = unsafe TypedServerRegistry(client: storage.pointer, lifetime: lifetime)
                registry.storage = storage
                storage.typedRegistry = registry
            }
            return try registry.create(type, identifier: identifier, version: version)
        }
    }
}

final class PendingServerIdentifier {
    let registry: TypedServerRegistry
    let identifier: UInt32
    let interface: String
    let version: UInt32
    let requiredDescriptor: ProtocolDescriptor?
    var resolved = false
    init(registry: TypedServerRegistry, identifier: UInt32, interface: String, version: UInt32,
         requiredDescriptor: ProtocolDescriptor? = nil) {
        self.registry = registry; self.identifier = identifier; self.interface = interface; self.version = version
        self.requiredDescriptor = requiredDescriptor
    }
    func accept<I: ServerInterface>(_ type: I.Type) throws -> ServerObject<I> {
        let schema = try CoreProtocol.requireSchema(for: I.self)
        guard !resolved, requiredDescriptor == nil, interface == schema.name else { throw ServerProtocolError.invalidMessage }
        let object = try registry.create(type, identifier: identifier, version: version)
        resolved = true
        return object
    }
    func accept(descriptor: ProtocolDescriptor) throws -> ServerProtocolObject {
        guard !resolved, interface == descriptor.schema.name else { throw ServerProtocolError.invalidMessage }
        if let requiredDescriptor {
            guard requiredDescriptor.arenaIdentity == descriptor.arenaIdentity else { throw ServerProtocolError.invalidMessage }
        }
        let object = try registry.create(descriptor: descriptor, identifier: identifier, version: version)
        resolved = true
        return object
    }
    deinit { if !resolved { registry.reject() } }
}
/// Owns a single client-supplied typed constructor obligation until accepted or rejected.
public struct ServerNewIdentifier<Interface: ServerInterface>: ~Copyable {
    let pending: PendingServerIdentifier
    init(_ pending: PendingServerIdentifier) { self.pending = pending }
    /// Publishes exactly one native resource; every failure rejects the unfulfilled constructor.
    public consuming func accept() throws -> ServerObject<Interface> { try pending.accept(Interface.self) }
}
/// Owns a generic constructor together with its requested native interface and version.
public struct ServerDynamicIdentifier: ~Copyable {
    let pending: PendingServerIdentifier
    init(_ pending: PendingServerIdentifier) { self.pending = pending }
    /// Returns the copied native interface name requested by the peer.
    public var interfaceName: String { borrowing get { pending.interface } }
    /// Returns the copied requested version.
    public var version: UInt32 { borrowing get { pending.version } }
    /// Validates interface identity and publishes one resource or rejects the constructor.
    public consuming func accept<I: ServerInterface>(as type: I.Type) throws -> ServerObject<I> { try pending.accept(type) }
    /// Validates an imported target and publishes exactly one managed resource.
    public consuming func accept(descriptor: ProtocolDescriptor) throws -> ServerProtocolObject { try pending.accept(descriptor: descriptor) }
}

@unsafe private func dispatchTypedServer(
    _ implementation: UnsafeRawPointer?, _ target: UnsafeMutableRawPointer?, _ opcode: UInt32,
    _ message: UnsafePointer<wl_message>?, _ arguments: UnsafeMutablePointer<wl_argument>?
) -> Int32 {
    guard let target = unsafe target,
          let data = unsafe wl_resource_get_user_data(target.assumingMemoryBound(to: wl_resource.self)) else { return -1 }
    let context = unsafe Unmanaged<TypedServerContext>.fromOpaque(data).takeUnretainedValue()
    defer {
        if let message = unsafe message { unsafe discardServerDescriptors(message, arguments) }
    }
    do {
        try context.observer.withCallback {
            guard Int(opcode) < context.schema.requests.count else { throw ServerProtocolError.invalidMessage }
            let schema = context.schema.requests[Int(opcode)]
            guard schema.since <= context.version else { throw ServerProtocolError.unsupportedVersion }
            var input = unsafe ServerMessageReader(registry: context.registry, interfaceName: context.schema.name, schema: schema,
                                                   version: context.version, descriptor: context.descriptor, arguments: arguments)
            if schema.destructor { _ = unsafe context.observer.protocolClosed() }
            if context.gate.enabled, let handler = context.handler { try handler(&input) }
            else { try context.discard(&input) }
            if context.descriptor != nil { input.rejectUnclaimedConstructors() }
        }
        return 0
    } catch {
        context.diagnostics.failure = error
        context.registry.reject()
        return -1
    }
}

@unsafe private func discardServerDescriptors(_ message: UnsafePointer<wl_message>, _ arguments: UnsafeMutablePointer<wl_argument>?) {
    guard let arguments = unsafe arguments else { return }
    let signature = unsafe String(cString: message.pointee.signature)
    var index = 0
    for character in signature where !character.isNumber && character != "?" {
        if character == "h", unsafe arguments[index].h >= 0 { _ = unsafe Glibc.close(arguments[index].h); unsafe arguments[index].h = -1 }
        index += 1
    }
}
