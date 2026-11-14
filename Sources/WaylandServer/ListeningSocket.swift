import Glibc
import CWaylandServer
import WaylandRuntime

/// Owns one externally prepared socket after native ownership transfer.
///
/// Removal closes the socket through libwayland. Native registration does not
/// own filesystem path or lock cleanup for an externally supplied descriptor.
public struct ServerListeningSocket: ~Copyable {
    private let owner: OwnedHandle
    init(_ owner: consuming OwnedHandle) { self.owner = owner }
    /// Provides checked registration identity without exposing its descriptor.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Requests deferred native removal and descriptor closure.
    @discardableResult public borrowing func requestClose() -> CloseProgress { owner.requestClose() }
    /// Consumes authority and removes the socket through the single cleanup record.
    @discardableResult public consuming func close() -> CloseProgress { owner.close() }
}
extension ServerDisplay {
    /// Consumes a prepared listening descriptor on success, native failure, or publication failure.
    ///
    /// The caller must exclusively own a CLOEXEC socket already bound, listening,
    /// and protected by appropriate path/lock policy. No other code may close or
    /// remove it. The caller retains responsibility for filesystem path cleanup.
    @unsafe public borrowing func addListeningSocket(receiving descriptor: Int32) throws -> ServerListeningSocket {
        var consumed = false
        defer { if !consumed { _ = Glibc.close(descriptor) } }
        return try lifetime.withAccess(matching: .serverDisplay) {
            guard unsafe wl_display_add_socket_fd(storage.pointer, descriptor) == 0 else { throw ServerError.nativeFailure(errno) }
            consumed = true
            var adopted = false
            defer { if !adopted { _ = unsafe wl_display_remove_socket_fd(storage.pointer, descriptor) } }
            let pointer = unsafe storage.pointer
            let owner = unsafe try lifetime.adopt(nativeIdentifier: UInt64(bitPattern: Int64(descriptor)), kind: .serverSocket, dependencies: [lifetime]) {
                _ = unsafe wl_display_remove_socket_fd(pointer, descriptor)
            }
            adopted = true
            return ServerListeningSocket(owner)
        }
    }
}
