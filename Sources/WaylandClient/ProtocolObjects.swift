import Glibc
import CWaylandClient
import WaylandProtocol
import WaylandRuntime

/// Carries a schema-checked outgoing value without exposing native argument storage.
///
/// Arguments use original XML field order. A constructor placeholder does not
/// contain an ID or native pointer. Generic constructor interface/version fields
/// are inserted by the factory from its validated descriptor. Object and FD
/// references remain borrowed and are leased for the complete marshalling call.
public enum ClientProtocolArgument {
    /// A signed native scalar.
    case signed(Int32)
    /// An unsigned native scalar, including unknown enum bits.
    case unsigned(UInt32)
    /// The exact signed 24.8 fixed-point representation.
    case fixed(ProtocolFixed)
    /// A copied nullable string; required-field nulls and embedded NUL are rejected.
    case string(String?)
    /// Copied bytes subject to the bounded wire payload quota.
    case bytes([UInt8])
    /// A checked borrowed descriptor whose owner remains responsible for closing it.
    case descriptor(BorrowedFileDescriptor)
    /// A checked same-connection object reference, or a schema-permitted null.
    case object(AnyClientObjectReference?)
    /// The sole constructor field; creation is permitted only through construct or bind.
    case constructor

    var wire: ClientWireValue {
        switch self {
        case .signed(let value): .signed(value)
        case .unsigned(let value): .unsigned(value)
        case .fixed(let value): .fixed(value)
        case .string(let value): .string(value)
        case .bytes(let value): .bytes(value)
        case .descriptor(let value): .descriptor(value)
        case .object(let value): .object(value?.endpoint)
        case .constructor: .constructor
        }
    }
}

/// Owns one extension proxy and its permanently installed, metadata-retaining dispatcher.
///
/// The authoritative cleanup record retains its sealed descriptor arena through
/// native destruction and outer-frame retirement. This owner is noncopyable and
/// non-Sendable. Subscription cancellation disables delivery without freeing native
/// userdata. Fallback sends a known zero-argument destructor when available and
/// otherwise destroys only the local proxy; argument-bearing destructors require
/// an explicit destroy call. Explicit connection closure breaks runtime-held
/// user handler capture cycles.
public struct ClientProtocolObject: ~Copyable {
    let owner: ProxyDispatcherOwner<TypedClientContext>
    let endpoint: TypedClientEndpoint
    init(owner: consuming ProxyDispatcherOwner<TypedClientContext>, endpoint: TypedClientEndpoint) {
        self.owner = owner; self.endpoint = endpoint
    }
    /// Produces a checked copyable reference without destruction authority.
    public var reference: ClientProtocolReference { borrowing get { ClientProtocolReference(endpoint: endpoint) } }
    /// Returns the authoritative runtime identity used for invalidation and accounting.
    public var lifetime: ObjectHandle { borrowing get { owner.lifetime } }
    /// Returns a saved callback/decoder failure without accessing native metadata.
    public var failure: (any Error)? { borrowing get { endpoint.diagnostics.failure } }
    /// Installs the sole event handler under a nonescaping inout reader scope.
    ///
    /// Unclaimed FD/new-proxy obligations are retired after delivery, including
    /// throwing handlers. Canceled delivery still retires owned fields. Reader
    /// methods validate field kinds; incoming constructors select definitions from
    /// this proxy's same sealed arena rather than accepting substitute metadata.
    public borrowing func onEvent(_ body: @escaping (inout ClientMessageReader) throws -> Void) throws -> CallbackSubscription {
        try lifetime.withAccess {
            let subscription = try owner.subscription()
            try endpoint.withContext { context in
                context.handler = { reader in
                    do {
                        try body(&reader)
                        try reader.discardProtocolOwnedArguments()
                    } catch {
                        try? reader.discardProtocolOwnedArguments()
                        throw error
                    }
                }
            }
            return subscription
        }
    }
    /// Converts this owner to a core facade only after transitive metadata equivalence checks.
    ///
    /// The owner is consumed on failure. Success preserves the same cleanup record
    /// and metadata-retaining context; no proxy or native reference is duplicated.
    public consuming func typed<Interface: ClientInterface>(as type: Interface.Type) throws -> ClientObject<Interface> {
        _ = try reference.core(as: type)
        return ClientObject(owner: owner, endpoint: endpoint)
    }
    /// Consumes this proxy while constructing a typed-target replacement from the same arena.
    ///
    /// The destructor/constructor request is marshalled with all argument leases;
    /// local retirement is deferred and cannot retry the terminal request. Failure
    /// consumes this owner and rolls back any newly allocated proxy exactly once.
    public consuming func replace(opcode: UInt32, arguments: [ClientProtocolArgument]) throws -> ClientProtocolObject {
        let result = try endpoint.withContext { context in
            let message = try endpoint.message(opcode)
            guard let name = message.arguments.first(where: { $0.kind == .newIdentifier })?.interface,
                  let descriptor = context.descriptor else { throw TypedProtocolError.invalidMessage }
            return try endpoint.constructProtocol(opcode: opcode, arguments: arguments,
                descriptor: descriptor.relatedInterface(named: name), version: nil, advertisedVersion: nil, generic: false, terminal: true)
        }
        owner.close()
        return result
    }
    /// Consumes this proxy while constructing a generic terminal-request target.
    public consuming func replace(opcode: UInt32, arguments: [ClientProtocolArgument], descriptor: ProtocolDescriptor,
                                  version: UInt32, advertisedVersion: UInt32) throws -> ClientProtocolObject {
        let result = try endpoint.constructProtocol(opcode: opcode, arguments: arguments, descriptor: descriptor,
            version: version, advertisedVersion: advertisedVersion, generic: true, terminal: true)
        owner.close()
        return result
    }
    /// Consumes ownership and defers native proxy/context/metadata retirement until quiescence.
    @discardableResult public consuming func close() -> CloseProgress { owner.close() }
    /// Marshals a validated destructor with leased arguments and consumes ownership on every outcome.
    ///
    /// The protocol request is sent before local retirement. A native error does
    /// not retry the destructor. Falling back without explicit arguments never
    /// fabricates payloads for an argument-bearing destructor.
    public consuming func destroy(opcode: UInt32, arguments: [ClientProtocolArgument] = []) throws {
        let message = try endpoint.message(opcode)
        guard message.destructor else { throw TypedProtocolError.invalidMessage }
        if message.arguments.isEmpty && arguments.isEmpty {
            try endpoint.withContext { $0.destructor = opcode }
        } else {
            try endpoint.send(opcode: opcode, arguments: arguments.map(\.wire), terminal: true)
        }
        owner.close()
    }
}

/// Performs immutable-schema and runtime-lifetime checked extension requests.
public struct ClientProtocolReference {
    let endpoint: TypedClientEndpoint
    /// Reports logical validity; every native operation separately admits a full lease.
    public var isValid: Bool { endpoint.lifetime.isValid }
    /// Returns the copied effective negotiated version, including after invalidation.
    public var version: UInt32 { endpoint.version }
    /// Returns copied metadata without retaining a native allocation authority.
    public var schema: ProtocolInterfaceSchema { endpoint.schema }
    /// Admits a generated typed wrapper only when the entire referenced graph matches.
    public func requireEquivalent(to expectedInterfaces: [ProtocolInterfaceSchema]) throws {
        try endpoint.withContext { context in
            guard let descriptor = context.descriptor else { throw TypedProtocolError.wrongInterface }
            try descriptor.requireEquivalent(to: expectedInterfaces)
        }
    }
    /// Erases interface typing for a checked same-connection object argument.
    public var erased: AnyClientObjectReference { AnyClientObjectReference(endpoint: endpoint) }
    /// Returns the protocol ID only while this generation remains live.
    public func identifier() throws -> UInt32 { try endpoint.lifetime.withAccess { unsafe wl_proxy_get_id(endpoint.pointer) } }
    /// Produces a core reference only when all reachable metadata exactly matches the pinned core graph.
    ///
    /// Matching a native class name alone is insufficient. An external marker
    /// conformance remains rejected without evaluating its name getter.
    public func core<Interface: ClientInterface>(as type: Interface.Type) throws -> ClientObjectReference<Interface> {
        try endpoint.withContext { context in
            let expected = try CoreProtocol.requireSchema(for: type)
            guard endpoint.schema.name == expected.name, let descriptor = context.descriptor else { throw TypedProtocolError.wrongInterface }
            _ = try descriptor.coreInterface(as: type)
            return ClientObjectReference(endpoint)
        }
    }
    /// Sends a nonterminal, nonconstructor request after complete wire-schema validation.
    public func request(opcode: UInt32, arguments: [ClientProtocolArgument] = []) throws {
        try endpoint.send(opcode: opcode, arguments: arguments.map(\.wire))
    }
    /// Creates a typed-target proxy using the exact originating arena definition.
    ///
    /// No caller-supplied descriptor can replace the target's event layout. The
    /// new proxy is consumed on every failure before owner publication.
    public func construct(opcode: UInt32, arguments: [ClientProtocolArgument]) throws -> ClientProtocolObject {
        try endpoint.withContext { context in
            let message = try endpoint.message(opcode)
            guard let constructor = message.arguments.first(where: { $0.kind == .newIdentifier }),
                  let name = constructor.interface, let descriptor = context.descriptor else { throw TypedProtocolError.invalidMessage }
            let target = try descriptor.relatedInterface(named: name)
            return try endpoint.constructProtocol(opcode: opcode, arguments: arguments, descriptor: target, version: nil, advertisedVersion: nil, generic: false)
        }
    }
    /// Creates a generic request target and derives its implicit name/version fields from a descriptor.
    ///
    /// Advertised and requested versions are checked before native allocation.
    /// Arguments remain in original XML order and include one constructor placeholder.
    public func construct(opcode: UInt32, arguments: [ClientProtocolArgument], descriptor: ProtocolDescriptor,
                          version: UInt32, advertisedVersion: UInt32) throws -> ClientProtocolObject {
        try endpoint.constructProtocol(opcode: opcode, arguments: arguments, descriptor: descriptor,
                                       version: version, advertisedVersion: advertisedVersion, generic: true)
    }
}

extension ClientObjectReference where Interface == WlRegistry {
    /// Binds an advertised extension interface while retaining its arena in the resulting proxy record.
    ///
    /// Descriptor validation does not waive the caller's advertisement selection:
    /// name must identify a global offering the descriptor's interface. Native
    /// protocol errors remain distinct from local version/schema validation.
    public func bind(name: UInt32, descriptor: ProtocolDescriptor, version: UInt32, advertisedVersion: UInt32) throws -> ClientProtocolObject {
        try endpoint.constructProtocol(opcode: 0, arguments: [.unsigned(name), .constructor], descriptor: descriptor,
                                       version: version, advertisedVersion: advertisedVersion, generic: true)
    }
}

extension TypedClientEndpoint {
    func constructProtocol(opcode: UInt32, arguments: [ClientProtocolArgument], descriptor: ProtocolDescriptor,
                           version requestedVersion: UInt32?, advertisedVersion: UInt32?, generic: Bool, terminal: Bool = false) throws -> ClientProtocolObject {
        try lifetime.withAccess {
            let message = try message(opcode)
            let target = descriptor.schema
            guard message.destructor == terminal, arguments.count == message.arguments.count,
                  let constructor = message.arguments.first(where: { $0.kind == .newIdentifier }),
                  (constructor.interface == nil) == generic,
                  constructor.interface == nil || constructor.interface == target.name else { throw TypedProtocolError.invalidMessage }
            if terminal && schema.events.contains(where: { $0.arguments.contains(where: { $0.kind == .newIdentifier }) }) {
                guard registry.queueState.canRelease() else { throw ClientCoordinationError.eventsPending }
            }
            let requested = requestedVersion ?? min(version, target.version)
            guard requested > 0, requested <= target.version,
                  advertisedVersion.map({ requested <= $0 }) ?? !generic else { throw TypedProtocolError.unsupportedVersion }
            var values: [ClientWireValue] = []
            for (argument, value) in zip(message.arguments, arguments) {
                if argument.kind == .newIdentifier && argument.interface == nil {
                    values += [.string(target.name), .unsigned(requested)]
                }
                values.append(value.wire)
            }
            return try registry.metadata.withPinnedDescriptor(descriptor) {
            return unsafe try withArguments(values, message: message) { values in
                guard unsafe wl_display_get_error(registry.display) == 0 else { throw ClientError.nativeFailure(EPIPE) }
                return unsafe try descriptor.withUnsafeInterface { interface in
                    if terminal { try withContext { $0.destructor = nil } }
                    let result = unsafe wl_proxy_marshal_array_flags(pointer, opcode, interface, requested, 0, values)
                    let saved = errno
                    let error = unsafe wl_display_get_error(registry.display)
                    guard let pointer = unsafe result else { throw ClientError.nativeFailure(error != 0 ? error : (saved != 0 ? saved : ENOMEM)) }
                    guard error == 0 else { unsafe wl_proxy_destroy(pointer); throw ClientError.nativeFailure(error) }
                    return unsafe try registry.ownDynamic(pointer, descriptor: descriptor)
                }
            }
            }
        }
    }
}

extension ClientMessageReader {
    /// Transfers one event-created extension proxy from this message's exact retained arena.
    ///
    /// No arbitrary descriptor argument is accepted. Failure after claiming the
    /// slot destroys the native proxy once; later C closure retirement still owns
    /// its native reference. The returned owner uses the existing runtime session.
    public mutating func protocolConstructor(_ index: Int) throws -> ClientProtocolObject {
        try check(index, .newIdentifier)
        guard let name = schema.arguments[index].interface, let descriptor = context.descriptor else { throw TypedProtocolError.invalidMessage }
        let target = try descriptor.relatedInterface(named: name)
        let pointer = unsafe try takeConstructorPointer(index)
        return unsafe try registry.ownDynamic(pointer, descriptor: target)
    }

    mutating func discardProtocolOwnedArguments() throws {
        var first: (any Error)?
        for (index, argument) in schema.arguments.enumerated() {
            let bit = UInt32(1) << index
            do {
                if argument.kind == .descriptor, claimedDescriptors & bit == 0 {
                    let owner = try descriptor(index)
                    _ = consume owner
                } else if argument.kind == .newIdentifier, claimedConstructors & bit == 0 {
                    if context.descriptor != nil {
                        let owner = try protocolConstructor(index)
                        _ = consume owner
                    } else {
                        guard let name = argument.interface else { throw TypedProtocolError.invalidMessage }
                        let pointer = unsafe try takeConstructorPointer(index)
                        let owner = unsafe try registry.ownCoreForCleanup(pointer, name: name)
                        _ = consume owner
                    }
                }
            } catch { if first == nil { first = error } }
        }
        if let first { throw first }
    }
}
