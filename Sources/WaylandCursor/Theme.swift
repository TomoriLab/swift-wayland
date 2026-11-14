import CWaylandCursor
import WaylandClient
import WaylandProtocol
import WaylandRuntime

/// Describes validated theme inputs and native lookup failures.
public enum CursorError: Error, Equatable, Sendable {
    /// The size is nonpositive, exceeds the safe initial allocation bound, or a name contains NUL.
    case invalidInput
    /// Native theme or lazy buffer allocation failed.
    case allocationFailed
    /// The requested image is outside the native cursor's image collection.
    case invalidImage
}

/// Contains copied image geometry and animation delay, without native memory access.
public struct CursorImageMetadata: Equatable, Sendable {
    /// The image width in pixels.
    public let width: UInt32
    /// The image height in pixels.
    public let height: UInt32
    /// The pointer hotspot's horizontal coordinate.
    public let hotspotX: UInt32
    /// The pointer hotspot's vertical coordinate.
    public let hotspotY: UInt32
    /// The native frame delay in milliseconds.
    public let delay: UInt32
}

/// Contains a validated native animation index and delay until the next frame.
public struct CursorFrame: Equatable, Sendable {
    /// The current zero-based image index.
    public let index: Int
    /// The remaining native frame duration; zero denotes a static cursor.
    public let duration: UInt32
}

/// Owns one native theme and every cursor, image, pool, and buffer it contains.
@safe public struct CursorTheme: ~Copyable {
    private let owner: OwnedHandle
    private let pointer: OpaquePointer
    private let group: ForeignClientProxyGroup

    /// Loads the named native theme or native fallback with an initial size of 1 through 1024 pixels.
    ///
    /// The caller must trust the selected native parser inputs and search configuration
    /// and establish that aggregate image/pool sizes fit native C integer and mapping
    /// bounds. The public native loader exposes no aggregate quota. Initial size
    /// validation alone does not prove that condition. Publication failure destroys
    /// the acquired aggregate before returning the error.
    @unsafe public init(sharedMemory: ClientObjectReference<WlShm>, name: String? = nil, size: Int32 = 24) throws {
        guard size > 0 && size <= 1024, name?.utf8.contains(0) != true else { throw CursorError.invalidInput }
        let group = ForeignClientProxyGroup(connectionOf: sharedMemory)
        let acquired: OwnedHandle = unsafe try sharedMemory.withUnsafeNativeProxy { proxy in
            let pointer: OpaquePointer?
            if let name { unsafe pointer = name.withCString { unsafe wl_cursor_theme_load($0, size, proxy) } }
            else { unsafe pointer = wl_cursor_theme_load(nil, size, proxy) }
            guard let pointer = unsafe pointer else { throw CursorError.allocationFailed }
            do {
                let owner = unsafe try sharedMemory.lifetime.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)),
                    kind: .cursorTheme, dependencies: [sharedMemory.lifetime]) {
                        unsafe wl_cursor_theme_destroy(pointer)
                        group.retire()
                    }
                group.attach(to: owner.reference)
                return owner
            } catch {
                unsafe wl_cursor_theme_destroy(pointer)
                throw error
            }
        }
        unsafe pointer = OpaquePointer(bitPattern: UInt(acquired.reference.identity.nativeIdentifier))!
        owner = consume acquired
        self.group = group
    }

    /// Provides lifetime observations without theme destruction authority.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }

    /// Looks up a cursor and returns a checked reference whose images remain theme-owned.
    public borrowing func cursor(named name: String) throws -> CursorReference? {
        guard !name.utf8.contains(0) else { throw CursorError.invalidInput }
        return try lifetime.withAccess(matching: .cursorTheme) {
            guard let cursor = name.withCString({ unsafe wl_cursor_theme_get_cursor(pointer, $0) }) else { return nil }
            return unsafe CursorReference(pointer: cursor, lifetime: lifetime, group: group)
        }
    }

    /// Rejects new operations and requests aggregate destruction after native quiescence.
    @discardableResult public borrowing func requestClose() -> CloseProgress { owner.requestClose() }
    /// Consumes theme authority and requests aggregate destruction.
    @discardableResult public consuming func close() -> CloseProgress { owner.close() }
}

/// Provides checked, operation-only access to a theme-owned native cursor.
@safe public struct CursorReference {
    private let pointer: UnsafeMutablePointer<wl_cursor>
    private let lifetime: ObjectHandle
    private let group: ForeignClientProxyGroup
    init(pointer: UnsafeMutablePointer<wl_cursor>, lifetime: ObjectHandle, group: ForeignClientProxyGroup) {
        unsafe self.pointer = pointer
        self.lifetime = lifetime
        self.group = group
    }
    /// Copies the native cursor name while the theme remains live.
    public func name() throws -> String {
        try lifetime.withAccess(matching: .cursorTheme) { unsafe String(cString: pointer.pointee.name) }
    }
    /// Copies the number of native images without exposing their backing array.
    public func imageCount() throws -> Int {
        try lifetime.withAccess(matching: .cursorTheme) { unsafe Int(pointer.pointee.image_count) }
    }
    /// Selects an animation frame using native timing semantics and checks the resulting index.
    public func frame(at milliseconds: UInt32) throws -> CursorFrame {
        try lifetime.withAccess(matching: .cursorTheme) {
            guard unsafe pointer.pointee.image_count > 0 && pointer.pointee.image_count <= UInt32(Int32.max) else { throw CursorError.invalidImage }
            var duration: UInt32 = 0
            let index = unsafe wl_cursor_frame_and_duration(pointer, milliseconds, &duration)
            guard unsafe index >= 0 && UInt32(index) < pointer.pointee.image_count else { throw CursorError.invalidImage }
            return CursorFrame(index: Int(index), duration: duration)
        }
    }
    /// Returns an image reference after bounds checking within the theme access frame.
    public func image(at index: Int) throws -> CursorImageReference {
        try lifetime.withAccess(matching: .cursorTheme) {
            guard unsafe index >= 0 && index < Int(pointer.pointee.image_count),
                  let image = unsafe pointer.pointee.images[index] else { throw CursorError.invalidImage }
            return unsafe CursorImageReference(pointer: image, lifetime: lifetime, group: group)
        }
    }
}

/// Provides copied image metadata and checked buffers without owning native image storage.
@safe public struct CursorImageReference {
    private let pointer: UnsafeMutablePointer<wl_cursor_image>
    private let lifetime: ObjectHandle
    private let group: ForeignClientProxyGroup
    init(pointer: UnsafeMutablePointer<wl_cursor_image>, lifetime: ObjectHandle, group: ForeignClientProxyGroup) {
        unsafe self.pointer = pointer
        self.lifetime = lifetime
        self.group = group
    }
    /// Copies image dimensions, hotspot coordinates, and frame delay.
    public func metadata() throws -> CursorImageMetadata {
        try lifetime.withAccess(matching: .cursorTheme) {
            let image = unsafe pointer.pointee
            return CursorImageMetadata(width: image.width, height: image.height, hotspotX: image.hotspot_x,
                                       hotspotY: image.hotspot_y, delay: image.delay)
        }
    }
    /// Lazily obtains the aggregate-owned native buffer without replacing its listener or userdata.
    ///
    /// The returned reference supports typed buffer arguments and lifetime checks.
    /// It has no protocol destruction authority and becomes invalid with the theme.
    public func buffer() throws -> ClientObjectReference<WlBuffer> {
        try lifetime.withAccess(matching: .cursorTheme) {
            guard let buffer = unsafe wl_cursor_image_get_buffer(pointer) else { throw CursorError.allocationFailed }
            return unsafe try group.reference(buffer, as: WlBuffer.self)
        }
    }
}
