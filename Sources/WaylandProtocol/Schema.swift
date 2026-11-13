/// Describes the protocol argument's exact native representation.
package enum ProtocolArgumentKind: String, Sendable {
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
    package init?(rawValue: String) {
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
    package var hashValue: Int { rawValue.hashValue }
    /// Combines the native type spelling into the caller's hasher.
    package func hash(into hasher: inout Hasher) { rawValue.hash(into: &hasher) }
}

/// Defines argument metadata without storing transient native pointers.
package struct ProtocolArgumentSchema: Sendable {
    /// The source argument name.
    package let name: String
    /// The exact native representation.
    package let kind: ProtocolArgumentKind
    /// Whether the schema permits a null value.
    package let nullable: Bool
    /// The named native interface, when specified.
    package let interface: String?
    /// The qualified enum reference, when specified.
    package let enumeration: String?
}

/// Describes a versioned request or event in source opcode order.
package struct ProtocolMessageSchema: Sendable {
    /// The source message name.
    package let name: String
    /// The source-order opcode.
    package let opcode: UInt32
    /// The earliest interface version accepting this message.
    package let since: UInt32
    /// The version at which the message became deprecated, when specified.
    package let deprecatedSince: UInt32?
    /// Whether the message consumes its protocol object's authority.
    package let destructor: Bool
    /// Arguments in wire order, including generic constructor semantics.
    package let arguments: [ProtocolArgumentSchema]
    /// Rejects sending the message through an older negotiated interface version.
    package func requireAvailable(version: UInt32) throws {
        guard version >= since else { throw ProtocolSchemaError.unsupportedVersion }
    }
}

/// Describes an enum entry while preserving all 32 native value bits.
package struct ProtocolEnumEntry: Sendable {
    /// The native source spelling.
    package let name: String
    /// The 32-bit native representation, including negative signed values.
    package let value: UInt32
    /// The entry's introduction version.
    package let since: UInt32
}

/// Describes a protocol enum without rejecting future unknown values.
package struct ProtocolEnumSchema: Sendable {
    /// The native source spelling.
    package let name: String
    /// Whether values combine as a bitfield.
    package let bitfield: Bool
    /// Entries in source order.
    package let entries: [ProtocolEnumEntry]
}

/// Holds one complete immutable interface schema.
package struct ProtocolInterfaceSchema: Sendable {
    /// The native interface name.
    package let name: String
    /// The maximum supported version in the pinned source.
    package let version: UInt32
    /// Client requests in opcode order.
    package let requests: [ProtocolMessageSchema]
    /// Server events in opcode order.
    package let events: [ProtocolMessageSchema]
    /// Native enums and all their entries.
    package let enumerations: [ProtocolEnumSchema]
}

/// Describes a schema validation failure before native marshalling.
package enum ProtocolSchemaError: Error, Equatable, Sendable {
    /// The message is newer than the negotiated object version.
    case unsupportedVersion
}
