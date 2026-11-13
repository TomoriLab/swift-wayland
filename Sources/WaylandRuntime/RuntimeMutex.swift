import CWaylandRuntime

/// Encapsulates the single audited unchecked synchronization primitive.
///
/// Every access to value takes the same native mutex. Value must be Sendable,
/// the native pointer is private, and an active withLock retains this wrapper
/// through unlock. No runtime control, handle, or cleanup closure is made Sendable.
/// pthread operations are used consistently in all configurations so sanitizer
/// visibility does not depend on uninstrumented standard-library atomic paths.
@safe final class RuntimeMutex<Value: Sendable>: @unchecked Sendable {
    private let native: OpaquePointer
    private var value: Value

    init(_ value: Value) throws {
        var error: Int32 = 0
        // The C constructor writes only this initialized error slot and retains no Swift pointer.
        guard let native = unsafe wayland_runtime_mutex_create(&error) else {
            throw OwnershipError.synchronizationUnavailable(error)
        }
        unsafe (self.native = native)
        self.value = value
    }

    func withLock<Result: ~Copyable>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        let locked = unsafe wayland_runtime_mutex_lock(native)
        precondition(locked == 0, "The bookkeeping mutex could not be locked.")
        defer {
            let unlocked = unsafe wayland_runtime_mutex_unlock(native)
            precondition(unlocked == 0, "The bookkeeping mutex could not be unlocked.")
        }
        return try body(&value)
    }

    deinit {
        // The wrapper has no surviving method lease or raw-pointer consumer at final release.
        unsafe wayland_runtime_mutex_destroy(native)
    }
}
