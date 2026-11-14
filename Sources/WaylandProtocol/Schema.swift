/// Describes the protocol argument's exact native representation.
public enum ProtocolArgumentKind: String, Sendable {
    /// A signed 32-bit integer.
    case signed = "int"
    /// An unsigned 32-bit integer.
    case unsigned = "uint"
    /// A native signed 24.8 fixed-point number.
    case fixed
    /// A nullable or required UTF-8 string.
    case string
    /// An object reference with optional interface constraints.
    case object
    /// A typed or generic constructor obligation.
    case newIdentifier = "new_id"
    /// An initialized byte array.
    case array
    /// An incoming ownership or outgoing scoped descriptor argument.
    case descriptor = "fd"

    /// Accepts exactly the native schema type spellings and rejects unknown kinds.
    public init?(rawValue: String) {
        switch rawValue {
        case "int": self = .signed
        case "uint": self = .unsigned
        case "fixed": self = .fixed
        case "string": self = .string
        case "object": self = .object
        case "new_id": self = .newIdentifier
        case "array": self = .array
        case "fd": self = .descriptor
        default: return nil
        }
    }
    /// Returns the current process's hash of this native type spelling.
    public var hashValue: Int { rawValue.hashValue }
    /// Combines the native type spelling into the caller's hasher.
    public func hash(into hasher: inout Hasher) { rawValue.hash(into: &hasher) }
}

/// Defines argument metadata without storing transient native pointers.
public struct ProtocolArgumentSchema: Equatable, Sendable {
    /// The source argument name.
    public let name: String
    /// The exact native representation.
    public let kind: ProtocolArgumentKind
    /// Whether the schema permits a null value.
    public let nullable: Bool
    /// The named native interface, when specified.
    public let interface: String?
    /// The qualified enum reference, when specified.
    public let enumeration: String?

    /// Creates immutable value metadata without granting native descriptor authority.
    ///
    /// Native consumers must separately validate the complete descriptor bundle.
    public init(name: String, kind: ProtocolArgumentKind, nullable: Bool, interface: String?, enumeration: String?) {
        self.name = name
        self.kind = kind
        self.nullable = nullable
        self.interface = interface
        self.enumeration = enumeration
    }
}

/// Describes a versioned request or event in source opcode order.
public struct ProtocolMessageSchema: Equatable, Sendable {
    /// The source message name.
    public let name: String
    /// The source-order opcode.
    public let opcode: UInt32
    /// The earliest interface version accepting this message.
    public let since: UInt32
    /// The version at which the message became deprecated, when specified.
    public let deprecatedSince: UInt32?
    /// Whether the message consumes its protocol object's authority.
    public let destructor: Bool
    /// Arguments in wire order, including generic constructor semantics.
    public let arguments: [ProtocolArgumentSchema]
    /// The expanded libwayland signature validated before native argument indexing.
    public var nativeSignature: String {
        let codes: [ProtocolArgumentKind: String] = [.signed: "i", .unsigned: "u", .fixed: "f", .string: "s", .object: "o", .newIdentifier: "n", .array: "a", .descriptor: "h"]
        return (since > 1 ? String(since) : "") + arguments.map { argument in
            (argument.kind == .newIdentifier && argument.interface == nil ? "su" : "") + (argument.nullable ? "?" : "") + codes[argument.kind]!
        }.joined()
    }
    /// Rejects sending the message through an older negotiated interface version.
    public func requireAvailable(version: UInt32) throws {
        guard version >= since else { throw ProtocolSchemaError.unsupportedVersion }
    }

    /// Creates immutable value metadata without granting native descriptor authority.
    ///
    /// Native consumers must separately validate the complete descriptor bundle.
    public init(name: String, opcode: UInt32, since: UInt32, deprecatedSince: UInt32?, destructor: Bool, arguments: [ProtocolArgumentSchema]) {
        self.name = name
        self.opcode = opcode
        self.since = since
        self.deprecatedSince = deprecatedSince
        self.destructor = destructor
        self.arguments = arguments
    }
}

/// Describes an enum entry while preserving all 32 native value bits.
public struct ProtocolEnumEntry: Equatable, Sendable {
    /// The native source spelling.
    public let name: String
    /// The 32-bit native representation, including negative signed values.
    public let value: UInt32
    /// The entry's introduction version.
    public let since: UInt32

    /// Creates immutable value metadata without granting native descriptor authority.
    ///
    /// Native consumers must separately validate the complete descriptor bundle.
    public init(name: String, value: UInt32, since: UInt32) {
        self.name = name
        self.value = value
        self.since = since
    }
}

/// Describes a protocol enum without rejecting future unknown values.
public struct ProtocolEnumSchema: Equatable, Sendable {
    /// The native source spelling.
    public let name: String
    /// Whether values combine as a bitfield.
    public let bitfield: Bool
    /// Entries in source order.
    public let entries: [ProtocolEnumEntry]

    /// Creates immutable value metadata without granting native descriptor authority.
    ///
    /// Native consumers must separately validate the complete descriptor bundle.
    public init(name: String, bitfield: Bool, entries: [ProtocolEnumEntry]) {
        self.name = name
        self.bitfield = bitfield
        self.entries = entries
    }
}

/// Holds one complete immutable interface schema.
public struct ProtocolInterfaceSchema: Equatable, Sendable {
    /// The native interface name.
    public let name: String
    /// The maximum supported version in the pinned source.
    public let version: UInt32
    /// Client requests in opcode order.
    public let requests: [ProtocolMessageSchema]
    /// Server events in opcode order.
    public let events: [ProtocolMessageSchema]
    /// Native enums and all their entries.
    public let enumerations: [ProtocolEnumSchema]

    /// Creates immutable value metadata without granting native descriptor authority.
    ///
    /// Native consumers must separately validate the complete descriptor bundle.
    public init(name: String, version: UInt32, requests: [ProtocolMessageSchema], events: [ProtocolMessageSchema], enumerations: [ProtocolEnumSchema]) {
        self.name = name
        self.version = version
        self.requests = requests
        self.events = events
        self.enumerations = enumerations
    }
}

/// Describes a schema validation failure before native marshalling.
public enum ProtocolSchemaError: Error, Equatable, Sendable {
    /// The message is newer than the negotiated object version.
    case unsupportedVersion
}
