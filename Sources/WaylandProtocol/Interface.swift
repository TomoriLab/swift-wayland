/// Identifies an immutable interface from the pinned core protocol.
public protocol CoreInterface {
    /// The exact native interface name.
    static var interfaceName: String { get }
}

extension CoreInterface {
    /// The immutable schema shared by both protocol directions.
    ///
    /// This property requires an exact generated core marker. Safe native factories
    /// use requireSchema(for:) and reject external marker conformances with an error.
    public static var schema: ProtocolInterfaceSchema {
        try! CoreProtocol.requireSchema(for: Self.self)
    }
}

/// Preserves the exact signed 24.8 wire representation without unchecked floating conversion.
public struct ProtocolFixed: Equatable, Hashable, Sendable {
    /// The exact native fixed-point bits.
    public let rawValue: Int32
    /// Creates a fixed-point value from its exact wire representation.
    public init(rawValue: Int32) { self.rawValue = rawValue }
}


/// Rejects protocol conformance as a substitute for verified native metadata.
public enum CoreInterfaceError: Error, Equatable, Sendable {
    /// The metatype is not one of the generated core interface markers.
    case unsupportedMarker
}
