import Glibc
import CWaylandRuntime

private struct ReadCancellationState: Sendable {
    let descriptor: Int32
    var cancelled = false
}

/// Provides thread-safe cancellation with a private owned poll-wakeup descriptor.
///
/// No native display capability crosses threads. The wake descriptor remains
/// owned until the last signal, waiter, and active method release this object.
/// Cancellation is permanent and never closes the borrowed display transport.
package final class ReadCancellation: Sendable {
    private let state: RuntimeMutex<ReadCancellationState>

    /// Allocates a nonblocking close-on-exec eventfd and its synchronized state.
    package init() throws {
        let descriptor = wayland_runtime_wake_create()
        guard descriptor >= 0 else { throw OwnershipError.synchronizationUnavailable(errno) }
        do { state = try RuntimeMutex(ReadCancellationState(descriptor: descriptor)) }
        catch { _ = Glibc.close(descriptor); throw error }
    }
    /// Signals cancellation once; late signals retain their own wake resource lifetime.
    package func cancel() {
        state.withLock { value in
            guard !value.cancelled else { return }
            value.cancelled = true
            var signal: UInt64 = 1
            // The descriptor is nonblocking and one signal cannot saturate eventfd.
            var result: Int
            repeat { result = unsafe Glibc.write(value.descriptor, &signal, MemoryLayout<UInt64>.size) }
            while result < 0 && errno == EINTR
            precondition(result == MemoryLayout<UInt64>.size || (result < 0 && errno == EAGAIN))
        }
    }
    /// Reports the synchronized cancellation bit without native resource access.
    package var isCancelled: Bool { state.withLock { $0.cancelled } }

    /// Borrows the wake number for synchronous polling while retaining this object.
    ///
    /// The caller must never close, read, store, or transfer this descriptor.
    @unsafe package func withUnsafeWakeDescriptor<Result: ~Copyable>(_ body: (Int32) throws -> Result) rethrows -> Result {
        defer { withExtendedLifetime(self) {} }
        return try body(state.withLock { $0.descriptor })
    }
    deinit { _ = Glibc.close(state.withLock { $0.descriptor }) }
}
