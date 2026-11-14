import Glibc
import CWaylandClient
import CWaylandProtocol
import WaylandProtocol
import WaylandRuntime

enum ClientWireValue {
    case signed(Int32), unsigned(UInt32), fixed(ProtocolFixed), string(String?), bytes([UInt8]), descriptor(BorrowedFileDescriptor)
    case object(TypedClientEndpoint?), constructor
}

private func stringWireBytes(_ string: String) throws -> Int {
    let count = string.utf8.count
    guard count < 4096, !string.utf8.contains(0) else { throw TypedProtocolError.invalidPayload }
    return 4 + ((count + 4) & ~3)
}

extension ClientObjectReference {
    func sendString(opcode: UInt32, value: String?) throws {
        try endpoint.lifetime.withAccess {
            let message = try endpoint.message(opcode)
            guard !message.destructor, message.arguments.count == 1,
                  message.arguments[0].kind == .string else { throw TypedProtocolError.invalidMessage }
            if let value {
                guard try stringWireBytes(value) + 8 <= 4096 else { throw TypedProtocolError.invalidPayload }
            } else if !message.arguments[0].nullable { throw TypedProtocolError.invalidPayload }
            var argument = unsafe wl_argument()
            func marshal(_ bytes: UnsafePointer<CChar>?) throws {
                unsafe argument.s = bytes
                // Native serialization finishes before the scoped argument and UTF-8 storage expire.
                _ = unsafe wl_proxy_marshal_array_flags(endpoint.pointer, opcode, nil, endpoint.version, 0, &argument)
                let error = unsafe wl_display_get_error(endpoint.registry.display)
                guard error == 0 else { throw ClientError.nativeFailure(error) }
            }
            if let value { try value.withCString { unsafe try marshal($0) } }
            else { try marshal(nil) }
        }
    }
    func send(opcode: UInt32, arguments: [ClientWireValue]) throws {
        try endpoint.send(opcode: opcode, arguments: arguments)
    }

    func construct<Target: ClientInterface>(
        opcode: UInt32, arguments: [ClientWireValue], as type: Target.Type,
        version: UInt32? = nil, advertisedVersion: UInt32? = nil
    ) throws -> ClientObject<Target> {
        try endpoint.lifetime.withAccess {
            let target = try CoreProtocol.requireSchema(for: Target.self)
            let message = try endpoint.message(opcode)
            guard let constructor = message.arguments.first(where: { $0.kind == .newIdentifier }),
                  constructor.interface == nil || constructor.interface == target.name else { throw TypedProtocolError.wrongInterface }
            let requested = version ?? min(endpoint.version, target.version)
            guard requested > 0 && requested <= target.version,
                  advertisedVersion.map({ requested <= $0 }) ?? (constructor.interface != nil) else {
                throw TypedProtocolError.unsupportedVersion
            }
            return unsafe try endpoint.withArguments(arguments, message: message) { values in
                guard unsafe wl_display_get_error(endpoint.registry.display) == 0 else { throw ClientError.nativeFailure(EPIPE) }
                let native = target.name.withCString { unsafe wayland_kit_client_core_interface($0) }
                guard let native = unsafe native else { throw TypedProtocolError.wrongInterface }
                let result = unsafe wl_proxy_marshal_array_flags(endpoint.pointer, opcode, native, requested, 0, values)
                let saved = errno
                let error = unsafe wl_display_get_error(endpoint.registry.display)
                guard let pointer = unsafe result else { throw ClientError.nativeFailure(error != 0 ? error : (saved != 0 ? saved : ENOMEM)) }
                guard error == 0 else { unsafe wl_proxy_destroy(pointer); throw ClientError.nativeFailure(error) }
                return unsafe try endpoint.registry.own(pointer, as: type)
            }
        }
    }

}

extension TypedClientEndpoint {
    func send(opcode: UInt32, arguments: [ClientWireValue], terminal: Bool = false) throws {
        try lifetime.withAccess {
            if !terminal && arguments.isEmpty && opcode < 64 && emptyRequestMask & (UInt64(1) << opcode) != 0 {
                // Native nonconstructor marshal rejects an existing display error before allocating or sending a closure.
                _ = unsafe wl_proxy_marshal_array_flags(pointer, opcode, nil, version, 0, nil)
                let error = unsafe wl_display_get_error(registry.display)
                guard error == 0 else { throw ClientError.nativeFailure(error) }
                return
            }
            let message = try message(opcode)
            guard message.destructor == terminal && !message.arguments.contains(where: { $0.kind == .newIdentifier }) else {
                throw TypedProtocolError.invalidMessage
            }
            if terminal && schema.events.contains(where: { $0.arguments.contains(where: { $0.kind == .newIdentifier }) }) {
                guard registry.queueState.canRelease() else { throw ClientCoordinationError.eventsPending }
            }
            unsafe try withArguments(arguments, message: message) { values in
                guard unsafe wl_display_get_error(registry.display) == 0 else { throw ClientError.nativeFailure(EPIPE) }
                if terminal { try withContext { $0.destructor = nil } }
                _ = unsafe wl_proxy_marshal_array_flags(pointer, opcode, nil, version, 0, values)
                let error = unsafe wl_display_get_error(registry.display)
                guard error == 0 else { throw ClientError.nativeFailure(error) }
            }
        }
    }

    func withArguments<Result: ~Copyable>(
        _ values: [ClientWireValue], message: ProtocolMessageSchema,
        _ body: (UnsafeMutablePointer<wl_argument>) throws -> Result
    ) throws -> Result {
        if values.isEmpty && message.arguments.isEmpty {
            // An empty signature consumes no slots; initialized stack storage preserves the scoped pointer contract.
            var empty = unsafe wl_argument()
            return try withUnsafeMutablePointer(to: &empty) { pointer in
                unsafe try body(pointer)
            }
        }
        guard Int(message.opcode) < requestArgumentLayouts.count else { throw TypedProtocolError.invalidMessage }
        let expected = requestArgumentLayouts[Int(message.opcode)]
        guard values.count == expected.count, values.count <= 20 else { throw TypedProtocolError.invalidMessage }
        var wireBytes = 8
        for (index, value) in values.enumerated() {
            let (kind, nullable, interface) = expected[index]
            switch (kind, value) {
            case (.signed, .signed), (.unsigned, .unsigned), (.fixed, .fixed), (.newIdentifier, .constructor): wireBytes += 4
            case (.descriptor, .descriptor): break
            case (.object, .object(let object)):
                guard let object else { if nullable { wireBytes += 4; continue }; throw TypedProtocolError.invalidPayload }
                guard object.registry === registry, interface == nil || object.schema.name == interface else { throw TypedProtocolError.foreignObject }
                wireBytes += 4
            case (.string, .string(let string)):
                guard let string else { if nullable { wireBytes += 4; continue }; throw TypedProtocolError.invalidPayload }
                wireBytes += try stringWireBytes(string)
            case (.array, .bytes(let bytes)):
                guard bytes.count <= 4096 else { throw TypedProtocolError.invalidPayload }
                wireBytes += 4 + ((bytes.count + 3) & ~3)
            default: throw TypedProtocolError.invalidMessage
            }
        }
        guard wireBytes <= 4096 else { throw TypedProtocolError.invalidPayload }
        if values.count == 1, case .string(let value) = values[0] {
            // Native marshalling serializes strings before returning, so both scopes cover every pointer use.
            var argument = unsafe wl_argument()
            return try withUnsafeMutablePointer(to: &argument) { pointer in
                if let value {
                    var result: Result?
                    try value.withCString { bytes in
                        unsafe pointer.pointee.s = bytes
                        result = unsafe try body(pointer)
                    }
                    return result.take()!
                }
                unsafe pointer.pointee.s = nil
                return unsafe try body(pointer)
            }
        }
        guard let arena = unsafe wayland_kit_arguments_create(values.count) else { throw ClientError.nativeFailure(ENOMEM) }
        defer { unsafe wayland_kit_arguments_destroy(arena) }
        let arguments = unsafe wayland_kit_arguments_values(arena)!
        for (index, value) in values.enumerated() {
            switch value {
            case .signed(let value): unsafe arguments[index].i = value
            case .unsigned(let value): unsafe arguments[index].u = value
            case .fixed(let value): unsafe arguments[index].f = value.rawValue
            case .string(let value):
                let result: Int32
                if let value { result = value.withCString { unsafe wayland_kit_arguments_string(arena, index, $0) } }
                else { result = unsafe wayland_kit_arguments_string(arena, index, nil) }
                guard result == 0 else { throw ClientError.nativeFailure(ENOMEM) }
            case .bytes(let value):
                let result = value.withUnsafeBytes { unsafe wayland_kit_arguments_array(arena, index, $0.baseAddress, $0.count) }
                guard result == 0 else { throw ClientError.nativeFailure(ENOMEM) }
            case .constructor: unsafe arguments[index].o = nil
            case .object, .descriptor: break
            }
        }
        func leased(_ index: Int) throws -> Result {
            if index == values.count { return unsafe try body(arguments) }
            switch values[index] {
            case .descriptor(let descriptor):
                return unsafe try descriptor.withUnsafeDescriptor { raw in
                    unsafe arguments[index].h = raw
                    return try leased(index + 1)
                }
            case .object(let object):
                guard let object else { unsafe arguments[index].o = nil; return try leased(index + 1) }
                return try object.lifetime.withAccess {
                    unsafe arguments[index].o = object.pointer
                    return try leased(index + 1)
                }
            default: return try leased(index + 1)
            }
        }
        return try leased(0)
    }
}

extension ClientMessageReader {
    /// Copies a required string after nullability validation.
    public func requiredString(_ index: Int) throws -> String {
        guard let value = try string(index) else { throw TypedProtocolError.invalidMessage }; return value
    }
    /// Resolves a required typed object without granting destruction authority.
    public func requiredObject<I: ClientInterface>(_ index: Int, as type: I.Type) throws -> ClientObjectReference<I> {
        guard let value = try object(index, as: type) else { throw TypedProtocolError.invalidMessage }; return value
    }
    /// Resolves a required generic object without exposing its pointer.
    public func requiredAnyObject(_ index: Int) throws -> AnyClientObjectReference {
        guard let value = try anyObject(index) else { throw TypedProtocolError.invalidMessage }; return value
    }
}

extension ClientObjectReference where Interface == WlFixes {
    /// Consumes the registry argument even when validation or marshalling fails.
    func destroyRegistryObject(_ registry: consuming ClientObject<WlRegistry>) throws {
        try send(opcode: 1, arguments: [.object(registry.reference.endpoint)])
        registry.close()
    }
}
