import Glibc
import CWaylandClient
import CWaylandProtocol
import WaylandProtocol
import WaylandRuntime

/// Associates one generated core interface with its ownership-bearing event type.
public protocol ClientInterface: CoreInterface {
    /// The generated noncopyable event sum type.
    associatedtype Event: ~Copyable
    /// Decodes owned arguments before optional delivery.
    static func decodeEvent(_ reader: inout ClientMessageReader) throws -> Event
}

/// Describes local schema, ownership, or connection validation failures.
public enum TypedProtocolError: Error, Equatable, Sendable {
    /// A native interface does not match the generated marker.
    case wrongInterface
    /// An object belongs to another connection or is not runtime managed.
    case foreignObject
    /// The message, payload shape, or ownership slot is invalid.
    case invalidMessage
    /// The negotiated version cannot accept the requested operation.
    case unsupportedVersion
    /// A string contains an interior NUL or a payload exceeds the native wire quota.
    case invalidPayload
    /// Retaining another arena would exceed the connection metadata quota.
    case metadataQuotaExceeded
}

final class WeakClientEndpoint {
    weak var value: TypedClientEndpoint?
    init(_ value: TypedClientEndpoint) { self.value = value }
}

@safe final class TypedClientRegistry {
    let display: OpaquePointer
    let observer: NativeDestructionObserver
    let metadata: ClientProtocolMetadata
    let queueState: ClientQueueState
    var objects: [UInt: WeakClientEndpoint] = [:]
    init(display: OpaquePointer, lifetime: ObjectHandle, metadata: ClientProtocolMetadata, queueState: ClientQueueState) {
        unsafe self.display = display
        observer = lifetime.destructionObserver()
        self.metadata = metadata
        self.queueState = queueState
    }

    @unsafe func own<I: ClientInterface>(_ pointer: OpaquePointer, as type: I.Type, descriptor: ProtocolDescriptor? = nil) throws -> ClientObject<I> {
        let schema: ProtocolInterfaceSchema
        do {
            schema = try CoreProtocol.requireSchema(for: I.self)
            if let descriptor {
                guard descriptor.schema.name == schema.name else { throw TypedProtocolError.wrongInterface }
                _ = try descriptor.coreInterface(as: I.self)
            }
        }
        catch { unsafe wl_proxy_destroy(pointer); throw error }
        let object = unsafe try attach(pointer, schema: schema, descriptor: descriptor) { reader in
            try reader.discardProtocolOwnedArguments()
        }
        return ClientObject(owner: object.owner, endpoint: object.endpoint)
    }

    @unsafe func ownDynamic(_ pointer: OpaquePointer, descriptor: ProtocolDescriptor) throws -> ClientProtocolObject {
        var entered = false
        defer { if !entered { unsafe wl_proxy_destroy(pointer) } }
        return try observer.withLiveReference { _ in
            try metadata.withPinnedDescriptor(descriptor) {
                entered = true
                return unsafe try attach(pointer, schema: descriptor.schema, descriptor: descriptor) { reader in
                    try reader.discardProtocolOwnedArguments()
                }
            }
        }
    }

    @unsafe func ownCoreForCleanup(_ pointer: OpaquePointer, name: String) throws -> ClientProtocolObject {
        guard let schema = CoreProtocol.interfaces.first(where: { $0.name == name }) else {
            unsafe wl_proxy_destroy(pointer)
            throw TypedProtocolError.wrongInterface
        }
        return unsafe try attach(pointer, schema: schema, descriptor: nil) { reader in
            try reader.discardProtocolOwnedArguments()
        }
    }

    @unsafe private func attach(_ pointer: OpaquePointer, schema: ProtocolInterfaceSchema, descriptor: ProtocolDescriptor?,
                                discard: @escaping (inout ClientMessageReader) throws -> Void) throws -> ClientProtocolObject {
        var handedOff = false
        defer { if !handedOff { unsafe wl_proxy_destroy(pointer) } }
        guard unsafe String(cString: wl_proxy_get_class(pointer)) == schema.name else { throw TypedProtocolError.wrongInterface }
        guard let nativeInterface = unsafe wl_proxy_get_interface(pointer),
              unsafe nativeInterface.pointee.event_count >= 0,
              Int(unsafe nativeInterface.pointee.event_count) == schema.events.count else { throw TypedProtocolError.invalidMessage }
        let eventCount = schema.events.count
        let nativeEvents = unsafe nativeInterface.pointee.events
        guard eventCount == 0 || (unsafe nativeEvents != nil) else { throw TypedProtocolError.invalidMessage }
        var eventCleanupMask: UInt64 = 0
        for index in 0..<eventCount {
            guard let nativeName = unsafe nativeEvents![index].name,
                  let nativeSignature = unsafe nativeEvents![index].signature else { throw TypedProtocolError.invalidMessage }
            let signature = unsafe String(cString: nativeSignature)
            guard unsafe String(cString: nativeName) == schema.events[index].name,
                  signature == schema.events[index].nativeSignature else { throw TypedProtocolError.invalidMessage }
            // Either metadata source may impose cleanup; only their joint absence skips the C scan.
            let needsCleanup = signature.contains("h") || signature.contains("n") || schema.events[index].arguments.contains {
                $0.kind == .descriptor || $0.kind == .newIdentifier
            }
            if index < 64 && needsCleanup { eventCleanupMask |= UInt64(1) << index }
        }
        return try observer.withLiveReference { display in
            let version = max(1, min(unsafe wl_proxy_get_version(pointer), schema.version))
            let context = unsafe TypedClientContext(registry: self, pointer: pointer, schema: schema, version: version,
                                                    eventCleanupMask: eventCleanupMask, descriptor: descriptor, discard: discard)
            handedOff = true
            let owner = unsafe try display.receiveQueuedProxyDispatcher(nativeIdentifier: UInt64(UInt(bitPattern: pointer)),
                context: context, dependencies: [display],
                releaseReadiness: schema.events.contains(where: { $0.arguments.contains(where: { $0.kind == .newIdentifier }) }) ? { self.queueState.canRelease() } : nil,
                install: { data in
                    // Retained native userdata owns context; the implementation pointer only avoids a storage lookup on delivery.
                    context.cancellation = unsafe ProxyDispatcherOwner<TypedClientContext>.cancellationForNativeContext(userData: data)
                    let implementation = unsafe Unmanaged.passUnretained(context).toOpaque()
                    return unsafe wayland_kit_install_dispatcher_with_implementation(pointer, dispatchTypedClient, implementation, data) == 0
                }, destroy: {
                    if let opcode = context.destructor, unsafe wl_display_get_error(self.display) == 0 {
                        _ = unsafe wl_proxy_marshal_array_flags(pointer, opcode, nil, version, 0, nil)
                    }
                    unsafe wl_proxy_destroy(pointer)
                    self.objects.removeValue(forKey: UInt(bitPattern: pointer))
                })
            let endpoint = unsafe TypedClientEndpoint(pointer: pointer, lifetime: owner.lifetime, registry: self,
                                                     schema: schema, version: version)
            unsafe endpoint.contextPointer = Unmanaged.passUnretained(context).toOpaque()
            endpoint.diagnostics = context.diagnostics
            context.observer = owner.lifetime.destructionObserver()
            objects[endpoint.key] = WeakClientEndpoint(endpoint)
            return ClientProtocolObject(owner: owner, endpoint: endpoint)
        }
    }
}

final class TypedClientDiagnostics { var failure: (any Error)? }

@safe final class TypedClientEndpoint {
    let pointer: OpaquePointer
    let key: UInt
    let lifetime: ObjectHandle
    let registry: TypedClientRegistry
    let schema: ProtocolInterfaceSchema
    let version: UInt32
    let emptyRequestMask: UInt64
    let requestArgumentLayouts: [[(ProtocolArgumentKind, Bool, String?)]]
    var contextPointer: UnsafeMutableRawPointer?
    var diagnostics = TypedClientDiagnostics()
    init(pointer: OpaquePointer, lifetime: ObjectHandle, registry: TypedClientRegistry,
         schema: ProtocolInterfaceSchema, version: UInt32) {
        unsafe self.pointer = pointer
        key = UInt(bitPattern: pointer)
        self.lifetime = lifetime; self.registry = registry; self.schema = schema; self.version = version
        requestArgumentLayouts = schema.requests.map { message in
            message.arguments.flatMap { argument -> [(ProtocolArgumentKind, Bool, String?)] in
                let field = (argument.kind, argument.nullable, argument.interface)
                if argument.kind == .newIdentifier && argument.interface == nil {
                    return [(.string, false, nil), (.unsigned, false, nil), field]
                }
                return [field]
            }
        }
        emptyRequestMask = schema.requests.enumerated().reduce(UInt64(0)) { mask, entry in
            let (index, message) = entry
            guard index < 64, message.since <= version, !message.destructor, message.arguments.isEmpty else { return mask }
            return mask | (UInt64(1) << index)
        }
    }
    func withContext<Result: ~Copyable>(_ body: (TypedClientContext) throws -> Result) throws -> Result {
        try lifetime.withAccess {
            guard let pointer = unsafe contextPointer else { throw OwnershipError.invalidHandle }
            let context = unsafe Unmanaged<TypedClientContext>.fromOpaque(pointer).takeUnretainedValue()
            return try body(context)
        }
    }
    func message(_ opcode: UInt32) throws -> ProtocolMessageSchema {
        guard Int(opcode) < schema.requests.count else { throw TypedProtocolError.invalidMessage }
        let message = schema.requests[Int(opcode)]
        guard message.since <= version else { throw TypedProtocolError.unsupportedVersion }
        return message
    }
}

@safe final class TypedClientContext {
    let registry: TypedClientRegistry
    let pointer: OpaquePointer
    let schema: ProtocolInterfaceSchema
    let version: UInt32
    let eventCleanupMask: UInt64
    var observer: NativeDestructionObserver?
    var cancellation: CallbackCancellation?
    var handler: ((inout ClientMessageReader) throws -> Void)?
    var scalarEventMask: UInt64 = 0
    var scalarHandler: ((UInt32, UnsafeMutablePointer<wl_argument>?) throws -> Void)?
    let discard: (inout ClientMessageReader) throws -> Void
    let diagnostics = TypedClientDiagnostics()
    let descriptor: ProtocolDescriptor?
    var destructor: UInt32?
    init(registry: TypedClientRegistry, pointer: OpaquePointer, schema: ProtocolInterfaceSchema, version: UInt32,
         eventCleanupMask: UInt64, descriptor: ProtocolDescriptor? = nil,
         discard: @escaping (inout ClientMessageReader) throws -> Void) {
        self.registry = registry; unsafe self.pointer = pointer; self.schema = schema; self.version = version
        self.eventCleanupMask = eventCleanupMask
        self.discard = discard
        self.descriptor = descriptor
        destructor = schema.requests.first { $0.destructor && $0.arguments.isEmpty && $0.since <= version }?.opcode
    }
}

/// Holds sole destruction authority for one generated client interface.
public struct ClientObject<Interface: ClientInterface>: ~Copyable {
    private let owner: ProxyDispatcherOwner<TypedClientContext>
    let endpoint: TypedClientEndpoint
    init(owner: consuming ProxyDispatcherOwner<TypedClientContext>, endpoint: TypedClientEndpoint) {
        self.owner = owner; self.endpoint = endpoint
    }
    /// Produces a checked, copyable reference without destruction authority.
    public var reference: ClientObjectReference<Interface> { borrowing get { ClientObjectReference(endpoint) } }
    /// Exposes the authoritative lifetime for invalidation/accounting observations.
    public var lifetime: ObjectHandle { borrowing get { owner.lifetime } }
    /// Returns a saved decoder or handler failure after the native callback returns.
    public var failure: (any Error)? { borrowing get { endpoint.diagnostics.failure } }
    /// Issues one delivery subscription and installs its consuming typed handler.
    ///
    /// Dropping the subscription cancels delivery, not native attachment. Avoid
    /// strong capture cycles through owners; initialized event obligations are
    /// cleaned even when delivery is disabled or the handler throws.
    public borrowing func onEvent(_ body: @escaping (consuming Interface.Event) throws -> Void) throws -> CallbackSubscription {
        unsafe try subscribe(body)
    }
    @inline(__always) borrowing func subscribe(
        _ body: @escaping (consuming Interface.Event) throws -> Void,
        scalarEventMask: UInt64 = 0,
        scalarHandler: ((UInt32, UnsafeMutablePointer<wl_argument>?) throws -> Void)? = nil
    ) throws -> CallbackSubscription {
        try lifetime.withAccess {
            let subscription = try owner.subscription()
            try endpoint.withContext { context in
                context.handler = { reader in
                    let event = try Interface.decodeEvent(&reader)
                    try body(consume event)
                }
                if scalarEventMask != 0, let scalarHandler = unsafe scalarHandler {
                    var eligibleMask: UInt64 = 0
                    for event in context.schema.events where event.opcode < 64 && event.since <= context.version && !event.destructor {
                        let bit = UInt64(1) << event.opcode
                        if context.eventCleanupMask & bit == 0 { eligibleMask |= bit }
                    }
                    context.scalarEventMask = scalarEventMask & eligibleMask
                    unsafe context.scalarHandler = scalarHandler
                }
            }
            return subscription
        }
    }
    /// Consumes authority and defers the supported protocol/local destructor until quiescence.
    @discardableResult
    public consuming func close() -> CloseProgress { owner.close() }
    /// Validates a generated zero-argument destructor before consuming native authority.
    consuming func destroy(opcode: UInt32) throws {
        let message = try endpoint.message(opcode)
        guard message.destructor && message.arguments.isEmpty else { throw TypedProtocolError.invalidMessage }
        owner.close()
    }
}

/// Provides interface- and connection-checked access without close authority.
public struct ClientObjectReference<Interface: ClientInterface> {
    let endpoint: TypedClientEndpoint
    init(_ endpoint: TypedClientEndpoint) { self.endpoint = endpoint }
    /// Reports logical validity; native operations perform their own atomic validation.
    public var isValid: Bool { endpoint.lifetime.isValid }
    /// Returns the copied negotiated effective version, including after invalidation.
    public var version: UInt32 { endpoint.version }
    /// Returns the native protocol ID while the reference remains live.
    public func identifier() throws -> UInt32 {
        try endpoint.lifetime.withAccess { unsafe wl_proxy_get_id(endpoint.pointer) }
    }
    /// Erases interface identity while retaining generation and connection checks.
    public var erased: AnyClientObjectReference { AnyClientObjectReference(endpoint: endpoint) }
}

/// Carries a checked reference for schema arguments without a fixed interface.
public struct AnyClientObjectReference {
    let endpoint: TypedClientEndpoint
    /// Reports whether the underlying generation remains live.
    public var isValid: Bool { endpoint.lifetime.isValid }
}

@unsafe private func dispatchTypedClient(
    _ implementation: UnsafeRawPointer?, _ target: UnsafeMutableRawPointer?, _ opcode: UInt32,
    _ message: UnsafePointer<wl_message>?, _ arguments: UnsafeMutablePointer<wl_argument>?
) -> Int32 {
    guard let message = unsafe message else { return -1 }
    var claimedConstructors: UInt32 = 0
    var cleanupRequired = true
    defer {
        // Missing callback context retains the conservative native-signature cleanup path.
        if cleanupRequired { unsafe wayland_kit_discard_unclaimed(message, arguments, claimedConstructors) }
    }
    guard let implementation = unsafe implementation else { return 0 }
    // Proxy destruction precedes context retirement, and the outer dispatch frame retains the record throughout this callback.
    let context = unsafe Unmanaged<TypedClientContext>.fromOpaque(implementation).takeUnretainedValue()
    guard let observer = context.observer, let cancellation = context.cancellation else { return 0 }
    let enabled: Bool
    do { enabled = try unsafe observer.admitTypedCallback(cancellation: cancellation) }
    catch {
        guard (try? unsafe observer.admitTypedClosingCallback()) != nil else { return 0 }
        enabled = false
    }
    if enabled && opcode < 64 && (context.scalarEventMask & (UInt64(1) << opcode)) != 0,
       let scalarHandler = unsafe context.scalarHandler {
        // Subscription admission already checked schema bounds, version, ownership, and terminal-event status.
        cleanupRequired = false
        do { unsafe try scalarHandler(opcode, arguments) }
        catch { context.diagnostics.failure = error; return -1 }
        return 0
    }
    do {
        guard Int(opcode) < context.schema.events.count else { throw TypedProtocolError.invalidMessage }
        cleanupRequired = opcode >= 64 || (context.eventCleanupMask & (UInt64(1) << opcode)) != 0
        guard context.schema.events[Int(opcode)].since <= context.version else { throw TypedProtocolError.unsupportedVersion }
        if context.schema.events[Int(opcode)].destructor {
            context.destructor = nil
            _ = unsafe context.observer?.protocolClosed()
        }
        var input = unsafe ClientMessageReader(context: context, opcode: Int(opcode), arguments: arguments)
        defer { claimedConstructors = input.claimedConstructors }
        do {
            if enabled, let handler = context.handler { try handler(&input) }
            // Both metadata sources prove an ownership-free event needs no payload disposal.
            else if cleanupRequired { try context.discard(&input) }
        } catch {
            try? input.discardProtocolOwnedArguments()
            context.diagnostics.failure = error
            throw error
        }
    } catch { return -1 }
    return 0
}

/// Decodes owned event arguments under a temporary native lease.
///
/// Instances are created only by the trampoline. The noncopyable inout reader cannot escape its initialized
/// callback scope. FD slots are disarmed before consuming registration; constructor claims
/// retain the native closure's pointer for its later unref.
@safe public struct ClientMessageReader: ~Copyable {
    let context: TypedClientContext
    private let messageIndex: Int
    var registry: TypedClientRegistry { context.registry }
    var schema: ProtocolMessageSchema { context.schema.events[messageIndex] }
    private let arguments: UnsafeMutablePointer<wl_argument>?
    var claimedConstructors: UInt32 = 0
    var claimedDescriptors: UInt32 = 0
    init(context: TypedClientContext, opcode: Int, arguments: UnsafeMutablePointer<wl_argument>?) {
        self.context = context; messageIndex = opcode; unsafe self.arguments = arguments
    }
    /// Returns the immutable, validated opcode.
    public var opcode: UInt32 { UInt32(messageIndex) }
    func check(_ index: Int, _ kind: ProtocolArgumentKind) throws {
        guard index >= 0, index < 32, unsafe arguments != nil else { throw TypedProtocolError.invalidMessage }
        let message = context.schema.events[messageIndex]
        guard index < message.arguments.count, message.arguments[index].kind == kind else { throw TypedProtocolError.invalidMessage }
    }
    /// Copies a native signed value.
    public func signed(_ index: Int) throws -> Int32 { try check(index, .signed); return unsafe arguments![index].i }
    /// Copies a native unsigned value.
    public func unsigned(_ index: Int) throws -> UInt32 { try check(index, .unsigned); return unsafe arguments![index].u }
    /// Reads a generated core unsigned field after attachment validates every native event signature.
    ///
    /// The generated decoder supplies an XML-proven index and kind; libwayland allocates the
    /// argument array from the validated native signature for the callback's complete frame.
    @unsafe func generatedUnsigned(_ index: Int) throws -> UInt32 {
        guard let arguments = unsafe arguments else { throw TypedProtocolError.invalidMessage }
        return unsafe arguments[index].u
    }
    /// Copies an exact fixed-point representation.
    public func fixed(_ index: Int) throws -> ProtocolFixed { try check(index, .fixed); return unsafe ProtocolFixed(rawValue: arguments![index].f) }
    /// Copies a nullable UTF-8 string without retaining a peer pointer.
    public func string(_ index: Int) throws -> String? {
        try check(index, .string)
        let result = unsafe arguments![index].s.map { unsafe String(cString: $0) }
        guard result != nil || schema.arguments[index].nullable else { throw TypedProtocolError.invalidMessage }
        return result
    }
    /// Copies initialized bytes into owned Swift storage.
    public func bytes(_ index: Int) throws -> [UInt8] {
        try check(index, .array)
        guard let array = unsafe arguments![index].a else { throw TypedProtocolError.invalidMessage }
        let count = unsafe array.pointee.size
        guard count <= 4096 else { throw TypedProtocolError.invalidMessage }
        if count == 0 { return [] }
        guard let pointer = unsafe array.pointee.data else { throw TypedProtocolError.invalidMessage }
        return unsafe Array(UnsafeRawBufferPointer(start: pointer, count: count))
    }
    /// Transfers one received descriptor to the session or closes it on publication failure.
    public mutating func descriptor(_ index: Int) throws -> OwnedFileDescriptor {
        try check(index, .descriptor)
        let bit = UInt32(1) << index
        guard claimedDescriptors & bit == 0 else { throw TypedProtocolError.invalidMessage }
        let raw = unsafe arguments![index].h
        claimedDescriptors |= bit
        unsafe arguments![index].h = -1
        var received: ReceivedFileDescriptor? = unsafe ReceivedFileDescriptor(receiving: raw)
        return try registry.observer.withLiveReference { reference in
            // The temporary receive owner closes on admission failure before ownership moves.
            guard let value = received.take() else { throw TypedProtocolError.invalidMessage }
            return try value.register(in: reference)
        }
    }
    /// Transfers one event-created proxy to a typed runtime owner.
    public mutating func constructor<I: ClientInterface>(_ index: Int, as type: I.Type) throws -> ClientObject<I> {
        let descriptor: ProtocolDescriptor?
        if let origin = context.descriptor {
            try check(index, .newIdentifier)
            let expected = try CoreProtocol.requireSchema(for: type)
            guard schema.arguments[index].interface == expected.name else { throw TypedProtocolError.wrongInterface }
            descriptor = try origin.coreInterface(as: type)
        } else { descriptor = nil }
        let pointer = unsafe try takeConstructorPointer(index)
        return unsafe try registry.own(pointer, as: type, descriptor: descriptor)
    }
    mutating func takeConstructorPointer(_ index: Int) throws -> OpaquePointer {
        try check(index, .newIdentifier)
        let bit = UInt32(1) << index
        guard claimedConstructors & bit == 0, let pointer = unsafe arguments![index].o else { throw TypedProtocolError.invalidMessage }
        claimedConstructors |= bit
        return unsafe pointer
    }
    /// Resolves a nullable existing object through the generation-checked connection registry.
    public func object<I: ClientInterface>(_ index: Int, as type: I.Type) throws -> ClientObjectReference<I>? {
        let target = try CoreProtocol.requireSchema(for: I.self)
        try check(index, .object)
        guard let pointer = unsafe arguments![index].o else {
            guard schema.arguments[index].nullable else { throw TypedProtocolError.invalidMessage }; return nil
        }
        guard let endpoint = registry.objects[UInt(bitPattern: pointer)]?.value,
              endpoint.schema.name == target.name, endpoint.lifetime.isValid else { throw TypedProtocolError.foreignObject }
        return ClientObjectReference(endpoint)
    }
    /// Resolves a schema-generic object without exposing a raw native address.
    public func anyObject(_ index: Int) throws -> AnyClientObjectReference? {
        try check(index, .object)
        guard let pointer = unsafe arguments![index].o else {
            guard schema.arguments[index].nullable else { throw TypedProtocolError.invalidMessage }; return nil
        }
        guard let endpoint = registry.objects[UInt(bitPattern: pointer)]?.value, endpoint.lifetime.isValid else {
            throw TypedProtocolError.foreignObject
        }
        return AnyClientObjectReference(endpoint: endpoint)
    }
}

extension ClientObjectReference {
    /// Provides the checked lifetime used by dependent native adapters without close authority.
    public var lifetime: ObjectHandle { endpoint.lifetime }
    /// Borrows this proxy during one complete checked native invocation.
    ///
    /// The caller must preserve native identity, userdata, dispatcher, queue,
    /// and exclusive destruction authority. Retaining or independently destroying
    /// the pointer violates the borrow unless a separate proven adapter owns it.
    @unsafe public func withUnsafeNativeProxy<Result: ~Copyable>(_ body: (OpaquePointer) throws -> Result) throws -> Result {
        try endpoint.lifetime.withAccess { unsafe try body(endpoint.pointer) }
    }
}
