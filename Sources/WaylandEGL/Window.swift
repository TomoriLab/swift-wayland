import CWaylandEGL
import WaylandClient
import WaylandProtocol
import WaylandRuntime

/// Describes validation or allocation failure without transferring a window obligation.
public enum NativeWindowError: Error, Equatable, Sendable {
    /// Native dimensions must both be strictly positive.
    case invalidDimensions
    /// Native allocation returned no window.
    case allocationFailed
}

/// Contains copied native buffer dimensions, including zero before attachment.
public struct NativeWindowSize: Equatable, Sendable {
    /// The native attached buffer width.
    public let width: Int32
    /// The native attached buffer height.
    public let height: Int32
}

/// Owns an unbound native EGL window whose surface remains a tracked prerequisite.
///
/// This object does not create an EGL surface or attach a graphics driver. Closing
/// its surface invalidates it and releases its native allocation before the proxy.
/// Operations are synchronous and follow the connection's serialized domain.
@safe public struct NativeWindow: ~Copyable {
    private let owner: OwnedHandle
    private let pointer: OpaquePointer

    /// Creates a native window and publishes its release obligation atomically with surface access.
    ///
    /// Invalid dimensions do not call native code. Failed record publication destroys
    /// the acquired native allocation. Allocation failure leaves the surface unchanged.
    public init(surface: ClientObjectReference<WlSurface>, width: Int32, height: Int32) throws {
        guard width > 0 && height > 0 else { throw NativeWindowError.invalidDimensions }
        let acquired: OwnedHandle = unsafe try surface.withUnsafeNativeProxy { proxy in
            guard let pointer = unsafe wl_egl_window_create(proxy, width, height) else { throw NativeWindowError.allocationFailed }
            do {
                return unsafe try surface.lifetime.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)),
                    kind: .nativeWindow, dependencies: [surface.lifetime]) { unsafe wl_egl_window_destroy(pointer) }
            } catch {
                unsafe wl_egl_window_destroy(pointer)
                throw error
            }
        }
        unsafe pointer = OpaquePointer(bitPattern: UInt(acquired.reference.identity.nativeIdentifier))!
        owner = consume acquired
    }

    /// Exposes checked lifetime information without destruction authority.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }

    /// Updates native geometry without attaching or invoking a foreign driver.
    ///
    /// Surface versions using the offset request must pass zero offsets here.
    public borrowing func resize(width: Int32, height: Int32, offsetX: Int32 = 0, offsetY: Int32 = 0) throws {
        guard width > 0 && height > 0 else { throw NativeWindowError.invalidDimensions }
        try lifetime.withAccess(matching: .nativeWindow) {
            unsafe wl_egl_window_resize(pointer, width, height, offsetX, offsetY)
        }
    }

    /// Copies native attached dimensions without granting access to driver storage.
    public borrowing func attachedSize() throws -> NativeWindowSize {
        try lifetime.withAccess(matching: .nativeWindow) {
            var width: Int32 = 0
            var height: Int32 = 0
            unsafe wl_egl_window_get_attached_size(pointer, &width, &height)
            return NativeWindowSize(width: width, height: height)
        }
    }

    /// Borrows the window for a complete foreign operation that restores its unbound state.
    ///
    /// The caller must detach every driver callback and retained pointer before
    /// returning or throwing and satisfy all foreign thread-affinity requirements.
    @unsafe public borrowing func withUnsafeUnboundWindow<Result: ~Copyable>(
        _ body: (OpaquePointer) throws -> Result
    ) throws -> Result {
        try lifetime.withAccess(matching: .nativeWindow) { unsafe try body(pointer) }
    }

    /// Rejects new access and requests dependency-ordered native destruction.
    @discardableResult public borrowing func requestClose() -> CloseProgress { owner.requestClose() }
    /// Consumes this authority and requests native destruction.
    @discardableResult public consuming func close() -> CloseProgress { owner.close() }
}
