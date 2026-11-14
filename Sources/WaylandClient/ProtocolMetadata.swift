import WaylandProtocol
import WaylandRuntime

/// Reports the bounded display-owned metadata retained for queued native closures.
public struct ClientProtocolMetadataSnapshot: Sendable {
    /// The number of distinct retained descriptor arenas, never greater than 64.
    public let arenas: Int
    /// Native arena bytes including their C allocation bookkeeping.
    public let nativeBytes: Int
    /// The configured native byte bound; immutable Swift schema values are separate.
    public let maximumNativeBytes: Int
    /// Whether native disconnect has completed and every retention entry has retired.
    public let retired: Bool
    /// A native fatal error prevented proof that pending queues were fully disposed.
    public let cleanupError: Int32?
}

private final class ProtocolMetadataEntry {
    let descriptor: ProtocolDescriptor
    let bytes: Int
    var reservations = 0
    var committed = false
    init(_ descriptor: ProtocolDescriptor) { self.descriptor = descriptor; bytes = descriptor.arenaBytes }
}
final class ClientProtocolMetadata {
    private var descriptors: [ObjectIdentifier: ProtocolMetadataEntry] = [:]
    private let metrics: RuntimeMutex<ClientProtocolMetadataSnapshot>
    init(maximumBytes: Int) throws {
        guard maximumBytes >= 0 else { throw TypedProtocolError.metadataQuotaExceeded }
        metrics = try RuntimeMutex(ClientProtocolMetadataSnapshot(arenas: 0, nativeBytes: 0, maximumNativeBytes: maximumBytes, retired: false, cleanupError: nil))
    }
    func snapshot() -> ClientProtocolMetadataSnapshot { metrics.withLock { $0 } }
    func withPinnedDescriptor<Result: ~Copyable>(_ descriptor: ProtocolDescriptor, _ body: () throws -> Result) throws -> Result {
        let key = descriptor.arenaIdentity
        let entry: ProtocolMetadataEntry
        let before = snapshot()
        guard !before.retired else { throw OwnershipError.closedSession }
        if let existing = descriptors[key] { entry = existing }
        else {
            let bytes = descriptor.arenaBytes
            guard before.arenas < 64, bytes <= before.maximumNativeBytes - before.nativeBytes else {
                throw TypedProtocolError.metadataQuotaExceeded
            }
            entry = ProtocolMetadataEntry(descriptor)
            descriptors[key] = entry
            metrics.withLock { state in
                state = ClientProtocolMetadataSnapshot(arenas: state.arenas + 1, nativeBytes: state.nativeBytes + bytes,
                    maximumNativeBytes: state.maximumNativeBytes, retired: false, cleanupError: state.cleanupError)
            }
        }
        entry.reservations += 1
        defer {
            entry.reservations -= 1
            if !entry.committed && entry.reservations == 0 {
                descriptors.removeValue(forKey: key)
                metrics.withLock { state in
                    state = ClientProtocolMetadataSnapshot(arenas: state.arenas - 1, nativeBytes: state.nativeBytes - entry.bytes,
                        maximumNativeBytes: state.maximumNativeBytes, retired: false, cleanupError: state.cleanupError)
                }
            }
        }
        let result = try body()
        entry.committed = true
        return result
    }
    func recordCleanupError(_ error: Int32) {
        metrics.withLock { state in
            state = ClientProtocolMetadataSnapshot(arenas: state.arenas, nativeBytes: state.nativeBytes,
                maximumNativeBytes: state.maximumNativeBytes, retired: state.retired, cleanupError: state.cleanupError ?? error)
        }
    }
    func retire() {
        // Native queues have finished reading message signatures before descriptor release.
        descriptors.removeAll(keepingCapacity: false)
        metrics.withLock { state in
            state = ClientProtocolMetadataSnapshot(arenas: 0, nativeBytes: 0, maximumNativeBytes: state.maximumNativeBytes, retired: true, cleanupError: state.cleanupError)
        }
    }
}
