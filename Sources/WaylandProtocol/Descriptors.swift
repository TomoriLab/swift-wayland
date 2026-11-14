public import CWaylandProtocol

/// Reports schema validation or bounded native metadata allocation failure.
public enum ProtocolDescriptorError: Error, Equatable, Sendable {
    /// A name, version, opcode, argument, or reference violates the native schema.
    case invalidSchema
    /// A configured bound or schema cardinality exceeds the supported limits.
    case quotaExceeded
    /// The bounded native arena could not initialize or copy a definition.
    case allocationFailed
    /// The requested interface is not defined by this bundle.
    case unknownInterface
}

/// Owns one immutable, bounded native descriptor graph, including cyclic references.
///
/// Construction validates all schemas before native allocation, copies every string,
/// and publishes only a sealed arena. Failure releases every partial allocation.
/// No connection or executor is required for destruction. This type is not Sendable.
/// Descriptor values retain this owner; raw native consumers require explicit retention
/// through native teardown and outer-frame quiescence. Value metadata alone cannot
/// authorize an external CoreInterface conformance.
@safe public final class ProtocolDescriptorBundle {
    private let pointer: OpaquePointer
    private let schemas: [ProtocolInterfaceSchema]
    private let indices: [String: Int]

    /// Builds native metadata from complete immutable definitions and a byte quota.
    ///
    /// Every referenced interface and enum must appear in this bundle, including
    /// imported core definitions. Interface names are unique. Wire versions fit Int32;
    /// each message has at most twenty expanded arguments. The byte limit includes
    /// arena bookkeeping and cannot exceed sixteen MiB. The arena has no Swift retain
    /// cycles even when its native type references form cycles.
    public init(interfaces: [ProtocolInterfaceSchema], maximumBytes: Int = 16 * 1024 * 1024) throws {
        guard maximumBytes > 0, maximumBytes <= 16 * 1024 * 1024 else { throw ProtocolDescriptorError.quotaExceeded }
        let indices = try Self.validate(interfaces)
        guard let pointer = unsafe wayland_kit_descriptors_create(interfaces.count, maximumBytes) else {
            throw ProtocolDescriptorError.allocationFailed
        }
        var published = false
        defer { if !published { unsafe wayland_kit_descriptors_destroy(pointer) } }
        for (index, schema) in interfaces.enumerated() {
            let result = schema.name.withCString { name in
                unsafe wayland_kit_descriptors_interface(pointer, index, name, Int32(schema.version), schema.requests.count, schema.events.count)
            }
            guard result == 0 else { throw ProtocolDescriptorError.allocationFailed }
        }
        for (index, schema) in interfaces.enumerated() {
            for (event, messages) in [schema.requests, schema.events].enumerated() {
                for message in messages {
                    let signature = message.nativeSignature
                    let count = message.arguments.reduce(0) { $0 + ($1.kind == .newIdentifier && $1.interface == nil ? 3 : 1) }
                    let result = message.name.withCString { name in
                        signature.withCString { signature in
                            unsafe wayland_kit_descriptors_message(pointer, index, Int32(event), Int(message.opcode), name, signature, count)
                        }
                    }
                    guard result == 0 else { throw ProtocolDescriptorError.allocationFailed }
                    var argumentIndex = 0
                    for argument in message.arguments {
                        if argument.kind == .newIdentifier && argument.interface == nil { argumentIndex += 2 }
                        if let target = argument.interface {
                            guard let targetIndex = indices[target], unsafe wayland_kit_descriptors_argument(pointer, index, Int32(event), Int(message.opcode), argumentIndex, targetIndex) == 0 else {
                                throw ProtocolDescriptorError.invalidSchema
                            }
                        }
                        argumentIndex += 1
                    }
                }
            }
        }
        guard unsafe wayland_kit_descriptors_seal(pointer) == 0 else { throw ProtocolDescriptorError.invalidSchema }
        unsafe self.pointer = pointer
        schemas = interfaces
        self.indices = indices
        published = true
    }

    deinit { unsafe wayland_kit_descriptors_destroy(pointer) }

    /// Returns the native arena's live bytes, including allocation bookkeeping.
    public var allocatedBytes: Int { unsafe wayland_kit_descriptors_bytes(pointer) }
    /// Returns all interface names in input order without granting pointer access.
    public var interfaceNames: [String] { schemas.map(\.name) }
    /// Looks up a retaining descriptor value without changing native authority.
    public func interface(named name: String) throws -> ProtocolDescriptor {
        guard let index = indices[name] else { throw ProtocolDescriptorError.unknownInterface }
        return ProtocolDescriptor(bundle: self, index: index)
    }
    fileprivate func schema(_ index: Int) -> ProtocolInterfaceSchema { schemas[index] }
    @unsafe fileprivate func withPointer<Result: ~Copyable>(at index: Int, _ body: (UnsafePointer<wl_interface>) throws -> Result) rethrows -> Result {
        // A sealed arena contains every validated index and stays retained for the call.
        let interface = unsafe wayland_kit_descriptors_get(pointer, index)!
        return unsafe try body(interface)
    }

    fileprivate func requireCoreCompatibility(named root: String) throws {
        try requireEquivalent(named: root, to: CoreProtocol.interfaces)
    }

    fileprivate func requireEquivalent(named root: String, to expectedInterfaces: [ProtocolInterfaceSchema]) throws {
        var expected: [String: ProtocolInterfaceSchema] = [:]
        for interface in expectedInterfaces {
            guard expected.updateValue(interface, forKey: interface.name) == nil else {
                throw ProtocolDescriptorError.invalidSchema
            }
        }
        var pending = [root]
        var visited: Set<String> = []
        while let name = pending.popLast() {
            if !visited.insert(name).inserted { continue }
            guard let index = indices[name], let canonical = expected[name] else {
                throw ProtocolDescriptorError.invalidSchema
            }
            let actual = schemas[index]
            guard actual == canonical else { throw ProtocolDescriptorError.invalidSchema }
            for messages in [actual.requests, actual.events] {
                for message in messages {
                    for argument in message.arguments {
                        if let target = argument.interface { pending.append(target) }
                        if let enumeration = argument.enumeration { pending.append(String(enumeration.split(separator: ".")[0])) }
                    }
                }
            }
        }
    }

    private static func identifier(_ name: String, entry: Bool = false) -> Bool {
        let bytes = name.utf8
        guard let first = bytes.first, bytes.count <= 255 else { return false }
        func letter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 }
        return (entry || letter(first)) && bytes.allSatisfy { letter($0) || (48...57).contains($0) }
    }
    private static func validate(_ interfaces: [ProtocolInterfaceSchema]) throws -> [String: Int] {
        guard !interfaces.isEmpty, interfaces.count <= 4096 else { throw ProtocolDescriptorError.quotaExceeded }
        var indices: [String: Int] = [:]
        var enumerations: Set<String> = []
        var messageCount = 0
        for (index, schema) in interfaces.enumerated() {
            guard identifier(schema.name), schema.version > 0, schema.version <= Int32.max,
                  indices.updateValue(index, forKey: schema.name) == nil else { throw ProtocolDescriptorError.invalidSchema }
            guard schema.enumerations.count <= 65535 else { throw ProtocolDescriptorError.quotaExceeded }
            for enumeration in schema.enumerations {
                guard identifier(enumeration.name), enumerations.insert(schema.name + "." + enumeration.name).inserted else { throw ProtocolDescriptorError.invalidSchema }
                guard enumeration.entries.count <= 65535 else { throw ProtocolDescriptorError.quotaExceeded }
                var entries: Set<String> = []
                for entry in enumeration.entries {
                    guard identifier(entry.name, entry: true), entries.insert(entry.name).inserted,
                          entry.since > 0, entry.since <= schema.version else { throw ProtocolDescriptorError.invalidSchema }
                }
            }
            guard schema.requests.count <= 65535, schema.events.count <= 65535 else { throw ProtocolDescriptorError.quotaExceeded }
            messageCount += schema.requests.count + schema.events.count
            guard messageCount <= 65535 else { throw ProtocolDescriptorError.quotaExceeded }
        }
        for schema in interfaces {
            for (event, messages) in [schema.requests, schema.events].enumerated() {
                var names: Set<String> = []
                var previous: UInt32 = 1
                for (opcode, message) in messages.enumerated() {
                    guard identifier(message.name), names.insert(message.name).inserted, message.opcode == UInt32(opcode),
                          message.since >= previous, message.since <= schema.version else { throw ProtocolDescriptorError.invalidSchema }
                    previous = message.since
                    if let deprecated = message.deprecatedSince {
                        guard deprecated >= message.since, deprecated <= schema.version else { throw ProtocolDescriptorError.invalidSchema }
                    }
                    guard message.arguments.count <= 20 else { throw ProtocolDescriptorError.quotaExceeded }
                    var arguments: Set<String> = []
                    var count = 0, constructors = 0
                    for argument in message.arguments {
                        guard identifier(argument.name), arguments.insert(argument.name).inserted else { throw ProtocolDescriptorError.invalidSchema }
                        if argument.nullable && ![.object, .string, .array].contains(argument.kind) { throw ProtocolDescriptorError.invalidSchema }
                        if let target = argument.interface {
                            guard [.object, .newIdentifier].contains(argument.kind), indices[target] != nil else { throw ProtocolDescriptorError.invalidSchema }
                        }
                        if let enumeration = argument.enumeration {
                            guard [.signed, .unsigned].contains(argument.kind), enumerations.contains(enumeration) else { throw ProtocolDescriptorError.invalidSchema }
                        }
                        if argument.kind == .newIdentifier {
                            constructors += 1
                            if argument.interface == nil {
                                guard event == 0 else { throw ProtocolDescriptorError.invalidSchema }
                                count += 2
                            }
                        }
                        count += 1
                    }
                    guard count <= 20, constructors <= 1 else { throw ProtocolDescriptorError.quotaExceeded }
                }
            }
        }
        return indices
    }
}

/// Retains immutable native metadata without authorizing an untracked native consumer.
public struct ProtocolDescriptor {
    private let bundle: ProtocolDescriptorBundle
    private let index: Int
    private let canonicalCore: Bool
    fileprivate init(bundle: ProtocolDescriptorBundle, index: Int, canonicalCore: Bool = false) {
        self.bundle = bundle; self.index = index; self.canonicalCore = canonicalCore
    }
    /// Returns the copied immutable schema used to construct this native descriptor.
    public var schema: ProtocolInterfaceSchema { bundle.schema(index) }
    /// Verifies this definition and every reachable interface against generated value schemas.
    ///
    /// Matching a class name alone cannot authorize a typed decoder. The expected
    /// list must contain every interface reached through object or enum references.
    public func requireEquivalent(to expectedInterfaces: [ProtocolInterfaceSchema]) throws {
        try bundle.requireEquivalent(named: schema.name, to: expectedInterfaces)
    }
    /// Identifies the arena allocation without granting pointer access.
    package var arenaIdentity: ObjectIdentifier { ObjectIdentifier(bundle) }
    /// Reports the complete native graph size for connection-level retention quotas.
    package var arenaBytes: Int { bundle.allocatedBytes }
    /// Admits a core view only when every transitively referenced definition is canonical.
    package func coreInterface<Interface: CoreInterface>(as type: Interface.Type) throws -> ProtocolDescriptor {
        let expected = try CoreProtocol.requireSchema(for: type)
        if canonicalCore && schema.name == expected.name { return self }
        let descriptor = try bundle.interface(named: expected.name)
        try bundle.requireCoreCompatibility(named: expected.name)
        return ProtocolDescriptor(bundle: bundle, index: descriptor.index, canonicalCore: true)
    }
    /// Resolves another definition in this same retained metadata graph.
    package func relatedInterface(named name: String) throws -> ProtocolDescriptor { try bundle.interface(named: name) }
    /// Borrows the sealed native interface for explicit raw interoperability.
    ///
    /// The caller must keep this descriptor alive until every native consumer has
    /// stopped reading all transitively referenced descriptors, including deferred
    /// native closures. The pointer cannot independently retain its arena. The
    /// callback must not mutate or free arena storage or install foreign ownership.
    @unsafe public func withUnsafeInterface<Result: ~Copyable>(_ body: (UnsafePointer<wl_interface>) throws -> Result) rethrows -> Result {
        unsafe try bundle.withPointer(at: index, body)
    }
}
