import Glibc
import CWaylandServer
import CWaylandProtocol
import WaylandProtocol
import WaylandRuntime

/// Provides scoped decoding of a native server request with single-use owned fields.
@safe public struct ServerMessageReader: ~Copyable {
    let registry: TypedServerRegistry
    let interfaceName: String
    let schema: ProtocolMessageSchema
    let version: UInt32
    let descriptor: ProtocolDescriptor?
    private let arguments: UnsafeMutablePointer<wl_argument>?
    private var claimed: UInt32 = 0
    init(registry: TypedServerRegistry, interfaceName: String, schema: ProtocolMessageSchema, version: UInt32,
         descriptor: ProtocolDescriptor? = nil, arguments: UnsafeMutablePointer<wl_argument>?) {
        self.registry = registry; self.interfaceName = interfaceName; self.schema = schema; self.version = version
        self.descriptor = descriptor
        unsafe self.arguments = arguments
    }
    private func argument(_ index: Int) -> (kind: ProtocolArgumentKind, nullable: Bool, interface: String?)? {
        var cursor = 0
        for argument in schema.arguments {
            if argument.kind == .newIdentifier && argument.interface == nil {
                if index == cursor { return (.string, false, nil) }
                if index == cursor + 1 { return (.unsigned, false, nil) }
                cursor += 2
            }
            if cursor == index { return (argument.kind, argument.nullable, argument.interface) }
            cursor += 1
        }
        return nil
    }
    /// Returns the copied opcode for generated switch dispatch.
    public var opcode: UInt32 { schema.opcode }
    private func check(_ index: Int, _ kind: ProtocolArgumentKind) throws {
        guard index >= 0, index < 32, argument(index)?.kind == kind,
              unsafe arguments != nil else { throw ServerProtocolError.invalidMessage }
    }
    /// Copies a signed scalar.
    public func signed(_ index: Int) throws -> Int32 { try check(index, .signed); return unsafe arguments![index].i }
    /// Copies an unsigned scalar without rejecting unknown enumeration bits.
    public func unsigned(_ index: Int) throws -> UInt32 { try check(index, .unsigned); return unsafe arguments![index].u }
    /// Copies fixed-point bits without a floating-point conversion.
    public func fixed(_ index: Int) throws -> ProtocolFixed { try check(index, .fixed); return ProtocolFixed(rawValue: unsafe arguments![index].f) }
    /// Copies a nullable native UTF-8 string while its closure remains live.
    public func string(_ index: Int) throws -> String? {
        try check(index, .string)
        guard let pointer = unsafe arguments![index].s else {
            guard argument(index)?.nullable == true else { throw ServerProtocolError.invalidMessage }; return nil
        }
        return unsafe String(cString: pointer)
    }
    /// Copies a required native string.
    public func requiredString(_ index: Int) throws -> String {
        guard let string = try string(index) else { throw ServerProtocolError.invalidMessage }; return string
    }
    /// Copies native array bytes without exposing a peer-owned pointer.
    public func bytes(_ index: Int) throws -> [UInt8] {
        try check(index, .array)
        guard let array = unsafe arguments![index].a else { throw ServerProtocolError.invalidMessage }
        let count = unsafe array.pointee.size
        guard count <= 4096 else { throw ServerProtocolError.invalidMessage }
        if count == 0 { return [] }
        guard let pointer = unsafe array.pointee.data else { throw ServerProtocolError.invalidMessage }
        return unsafe Array(UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self), count: count))
    }
    /// Disarms and consumes one received FD before runtime publication.
    public mutating func descriptor(_ index: Int) throws -> OwnedFileDescriptor {
        try check(index, .descriptor)
        let bit = UInt32(1) << index
        guard claimed & bit == 0 else { throw ServerProtocolError.invalidMessage }
        claimed |= bit
        let raw = unsafe arguments![index].h
        unsafe arguments![index].h = -1
        var received: ReceivedFileDescriptor? = unsafe ReceivedFileDescriptor(receiving: raw)
        return try registry.observer.withLiveReference { reference in
            guard let owner = received.take() else { throw ServerProtocolError.invalidMessage }
            return try owner.register(in: reference)
        }
    }
    /// Claims a typed numeric constructor; dropping its result rejects the client.
    public mutating func constructor<I: ServerInterface>(_ index: Int, as type: I.Type) throws -> ServerNewIdentifier<I> {
        try check(index, .newIdentifier)
        let schema = try CoreProtocol.requireSchema(for: I.self)
        guard argument(index)?.interface == schema.name else { throw ServerProtocolError.invalidMessage }
        return ServerNewIdentifier(try pending(index, interface: schema.name, version: min(version, schema.version)))
    }
    /// Claims an expanded generic constructor together with its requested interface and version.
    public mutating func dynamicConstructor(_ index: Int) throws -> ServerDynamicIdentifier {
        try check(index, .newIdentifier)
        guard argument(index)?.interface == nil, index >= 2 else { throw ServerProtocolError.invalidMessage }
        let interface = try requiredString(index - 2)
        let version = try unsigned(index - 1)
        guard version > 0 else { throw ServerProtocolError.unsupportedVersion }
        if descriptor == nil {
            guard let supported = CoreProtocol.interfaces.first(where: { $0.name == interface })?.version,
                  version <= supported else { throw ServerProtocolError.unsupportedVersion }
        }
        return ServerDynamicIdentifier(try pending(index, interface: interface, version: version))
    }
    /// Claims an imported fixed-interface constructor from this message's arena.
    public mutating func protocolConstructor(_ index: Int) throws -> ServerDynamicIdentifier {
        try check(index, .newIdentifier)
        guard let descriptor, let interface = argument(index)?.interface else { throw ServerProtocolError.invalidMessage }
        let target = try descriptor.relatedInterface(named: interface)
        return ServerDynamicIdentifier(try pending(index, interface: interface, version: min(version, target.schema.version),
                                                   requiredDescriptor: target))
    }
    private mutating func pending(_ index: Int, interface: String, version: UInt32,
                                  requiredDescriptor: ProtocolDescriptor? = nil) throws -> PendingServerIdentifier {
        let bit = UInt32(1) << index
        let identifier = unsafe arguments![index].n
        guard claimed & bit == 0, identifier != 0 else { throw ServerProtocolError.invalidMessage }
        claimed |= bit
        return PendingServerIdentifier(registry: registry, identifier: identifier, interface: interface, version: version,
                                       requiredDescriptor: requiredDescriptor)
    }
    func rejectUnclaimedConstructors() {
        var index = 0
        for argument in schema.arguments {
            if argument.kind == .newIdentifier {
                if claimed & (UInt32(1) << (index + (argument.interface == nil ? 2 : 0))) == 0 {
                    registry.reject()
                }
                return
            }
            index += argument.kind == .newIdentifier && argument.interface == nil ? 3 : 1
        }
    }
    /// Resolves a nullable argument only through this client's tracked resource registry.
    public func object<I: ServerInterface>(_ index: Int, as type: I.Type) throws -> ServerObjectReference<I>? {
        try check(index, .object)
        guard let pointer = unsafe arguments![index].o else {
            guard argument(index)?.nullable == true else { throw ServerProtocolError.invalidMessage }; return nil
        }
        return unsafe try registry.reference(UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: wl_resource.self), as: type)
    }
    /// Resolves a required typed resource argument.
    public func requiredObject<I: ServerInterface>(_ index: Int, as type: I.Type) throws -> ServerObjectReference<I> {
        guard let object = try object(index, as: type) else { throw ServerProtocolError.invalidMessage }; return object
    }
    /// Resolves a nullable interface-generic resource argument.
    public func anyObject(_ index: Int) throws -> AnyServerObjectReference? {
        try check(index, .object)
        guard let pointer = unsafe arguments![index].o else {
            guard argument(index)?.nullable == true else { throw ServerProtocolError.invalidMessage }; return nil
        }
        guard let endpoint = registry.objects[UInt(bitPattern: pointer)]?.value, endpoint.lifetime.isValid else { throw ServerProtocolError.foreignObject }
        return AnyServerObjectReference(endpoint: endpoint)
    }
    /// Resolves a required interface-generic resource argument.
    public func requiredAnyObject(_ index: Int) throws -> AnyServerObjectReference {
        guard let object = try anyObject(index) else { throw ServerProtocolError.invalidMessage }; return object
    }
}

enum ServerWireValue {
    case signed(Int32), unsigned(UInt32), fixed(ProtocolFixed), string(String?), bytes([UInt8]), descriptor(BorrowedFileDescriptor)
    case object(TypedServerEndpoint?)
}
/// Carries a schema-checked outgoing server event value.
public enum ServerEventArgument {
    /// A signed native scalar.
    case signed(Int32)
    /// An unsigned native scalar, including unknown enumeration bits.
    case unsigned(UInt32)
    /// The exact signed 24.8 fixed-point representation.
    case fixed(ProtocolFixed)
    /// A copied nullable UTF-8 string.
    case string(String?)
    /// Copied array bytes.
    case bytes([UInt8])
    /// A borrowed descriptor whose owner retains close authority.
    case descriptor(BorrowedFileDescriptor)
    /// A checked resource reference, or a schema-permitted null.
    case object(AnyServerObjectReference?)

    var wire: ServerWireValue {
        switch self {
        case .signed(let value): .signed(value)
        case .unsigned(let value): .unsigned(value)
        case .fixed(let value): .fixed(value)
        case .string(let value): .string(value)
        case .bytes(let value): .bytes(value)
        case .descriptor(let value): .descriptor(value)
        case .object(let value): .object(value?.endpoint)
        }
    }
}
extension TypedServerEndpoint {
    func send(opcode: UInt32, arguments values: [ServerWireValue]) throws {
        try lifetime.withAccess {
            guard published else { throw ServerProtocolError.foreignObject }
            guard Int(opcode) < schema.events.count else { throw ServerProtocolError.invalidMessage }
            let message = schema.events[Int(opcode)]
            guard message.since <= version else { throw ServerProtocolError.unsupportedVersion }
            guard message.arguments.count == values.count, values.count <= 20 else { throw ServerProtocolError.invalidMessage }
            var wireBytes = 8
            for (index, value) in values.enumerated() {
                let argument = message.arguments[index]
                switch (argument.kind, value) {
                case (.signed, .signed), (.unsigned, .unsigned), (.fixed, .fixed): wireBytes += 4
                case (.descriptor, .descriptor): break
                case (.object, .object(let object)), (.newIdentifier, .object(let object)):
                    guard let object else { if argument.nullable { wireBytes += 4; continue }; throw ServerProtocolError.invalidMessage }
                    guard object.registry === registry,
                          argument.interface == nil || object.schema.name == argument.interface else { throw ServerProtocolError.foreignObject }
                    guard argument.kind == .newIdentifier ? !object.published : object.published else { throw ServerProtocolError.invalidMessage }
                    wireBytes += 4
                case (.string, .string(let string)):
                    guard let string else { if argument.nullable { wireBytes += 4; continue }; throw ServerProtocolError.invalidMessage }
                    guard !string.utf8.contains(0), string.utf8.count < 4096 else { throw ServerProtocolError.invalidMessage }
                    wireBytes += 4 + ((string.utf8.count + 4) & ~3)
                case (.array, .bytes(let bytes)):
                    guard bytes.count <= 4096 else { throw ServerProtocolError.invalidMessage }
                    wireBytes += 4 + ((bytes.count + 3) & ~3)
                default: throw ServerProtocolError.invalidMessage
                }
            }
            guard wireBytes <= 4096 else { throw ServerProtocolError.invalidMessage }
            guard let arena = unsafe wayland_kit_arguments_create(values.count) else { throw ServerError.nativeFailure(ENOMEM) }
            defer { unsafe wayland_kit_arguments_destroy(arena) }
            let arguments = unsafe wayland_kit_arguments_values(arena)!
            for (index, value) in values.enumerated() {
                switch value {
                case .signed(let value): unsafe arguments[index].i = value
                case .unsigned(let value): unsafe arguments[index].u = value
                case .fixed(let value): unsafe arguments[index].f = value.rawValue
                case .string(let value):
                    let result = value.map { value in value.withCString { unsafe wayland_kit_arguments_string(arena, index, $0) } }
                        ?? (unsafe wayland_kit_arguments_string(arena, index, nil))
                    guard result == 0 else { throw ServerError.nativeFailure(ENOMEM) }
                case .bytes(let value):
                    let result = value.withUnsafeBytes { unsafe wayland_kit_arguments_array(arena, index, $0.baseAddress, $0.count) }
                    guard result == 0 else { throw ServerError.nativeFailure(ENOMEM) }
                case .descriptor, .object: break
                }
            }
            func leased(_ index: Int) throws {
                if index == values.count {
                    for (position, value) in values.enumerated() where message.arguments[position].kind == .newIdentifier {
                        if case .object(let object) = value { object?.published = true }
                    }
                    unsafe wl_resource_post_event_array(pointer, opcode, arguments)
                    return
                }
                switch values[index] {
                case .descriptor(let descriptor):
                    unsafe try descriptor.withUnsafeDescriptor { raw in unsafe arguments[index].h = raw; try leased(index + 1) }
                case .object(let object):
                    guard let object else { unsafe arguments[index].o = nil; try leased(index + 1); return }
                    try object.lifetime.withAccess { unsafe arguments[index].o = UnsafeMutableRawPointer(object.pointer).assumingMemoryBound(to: wl_object.self); try leased(index + 1) }
                default: try leased(index + 1)
                }
            }
            try leased(0)
        }
    }
}
extension ServerObjectReference {
    func send(opcode: UInt32, arguments values: [ServerWireValue]) throws {
        try endpoint.send(opcode: opcode, arguments: values)
    }
}
