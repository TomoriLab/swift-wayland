import CWaylandRuntime

/// Encapsulates the single audited unchecked synchronization primitive.
///
/// Every access to value takes the same native mutex. Value must be Sendable,
/// the native pointer is private, and an active withLock retains this wrapper
/// through unlock. No runtime control, handle, or cleanup closure is made Sendable.
/// pthread operations are used consistently in all configurations so sanitizer
/// visibility does not depend on uninstrumented standard-library atomic paths.
@safe @usableFromInline package final class RuntimeMutex<Value: Sendable>: @unchecked Sendable {
    private let native: OpaquePointer
    private let storage: UnsafeMutablePointer<Value>

    /// Creates the package bookkeeping primitive or throws a synchronization error.
    package init(_ value: Value) throws {
        var error: Int32 = 0
        // The C constructor writes only this initialized error slot and retains no Swift pointer.
        guard let native = unsafe wayland_runtime_mutex_create(&error) else {
            throw OwnershipError.synchronizationUnavailable(error)
        }
        unsafe (self.native = native)
        // One initialized slot has the typed alignment and remains private until final wrapper release.
        unsafe storage = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        unsafe storage.initialize(to: value)
    }

    /// Runs a short value-only transaction without native calls or user callbacks.
    package func withLock<Result: ~Copyable>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        let locked = unsafe wayland_runtime_mutex_lock(native)
        precondition(locked == 0, "The bookkeeping mutex could not be locked.")
        defer {
            let unlocked = unsafe wayland_runtime_mutex_unlock(native)
            precondition(unlocked == 0, "The bookkeeping mutex could not be unlocked.")
            withExtendedLifetime(self) {}
        }
        // The same nonrecursive mutex grants exclusive access to this fixed storage on every entry.
        return unsafe try body(&storage.pointee)
    }

    /// Proves that this thread is inside a retained native invocation for this exact domain.
    var matchesNativeFrame: Bool { unsafe wayland_runtime_native_frame_matches(native) != 0 }
    /// Checks frame identity and the close mailbox at one native call boundary.
    var hasUninterruptedNativeFrame: Bool { unsafe wayland_runtime_native_frame_uninterrupted(native) != 0 }
    /// Separates live delivery, canceled cleanup, and slow-path admission in one native entry.
    func callbackState<Other: Sendable>(cancellation: RuntimeMutex<Other>) -> Int32 {
        unsafe wayland_runtime_callback_state(native, cancellation.native)
    }
    /// Reads only the atomic mailbox notification, never unsynchronized domain-owned state.
    var notificationPending: Bool { unsafe wayland_runtime_notification_pending(native) != 0 }
    /// Publishes mailbox state while its caller holds this mutex.
    func setNotification(_ pending: Bool) { unsafe wayland_runtime_notification_set(native, pending ? 1 : 0) }
    /// Restores the previous native domain even across throwing or nested unrelated scopes.
    func withNativeScope<Result: ~Copyable>(_ body: () throws -> Result) rethrows -> Result {
        let previous = unsafe wayland_runtime_native_frame_enter(native)
        defer {
            unsafe wayland_runtime_native_frame_leave(previous)
            withExtendedLifetime(self) {}
        }
        return try body()
    }

    deinit {
        // The wrapper has no surviving method lease or raw-pointer consumer at final release.
        unsafe wayland_runtime_mutex_destroy(native)
        unsafe storage.deinitialize(count: 1)
        unsafe storage.deallocate()
    }
}
