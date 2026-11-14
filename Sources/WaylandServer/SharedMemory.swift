import Glibc
import CWaylandServer
import WaylandProtocol
import WaylandRuntime

/// Describes checked SHM acquisition and snapshot failures.
public enum SharedMemoryError: Error, Equatable, Sendable {
    /// The resource is not a native SHM buffer.
    case notSharedMemory
    /// The native format is not one of the supported packed four-byte formats.
    case unsupportedFormat
    /// Native dimensions or stride cannot describe a bounded packed snapshot.
    case invalidLayout
    /// The requested owned copy exceeds the caller's byte quota.
    case quotaExceeded
    /// The guarded native copy rejected a nested access or invalid layout.
    case nativeFailure(Int32)
}

/// Contains copied native SHM geometry and format, without a pixel pointer.
public struct SharedMemoryMetadata: Equatable, Sendable {
    /// The native width in pixels.
    public let width: Int32
    /// The native height in pixels.
    public let height: Int32
    /// The native byte distance between rows.
    public let stride: Int32
    /// The unmodified native format code, including unrecognized formats.
    public let format: UInt32
}

@safe private final class SharedMemoryBufferStorage {
    let pointer: OpaquePointer
    init(_ pointer: OpaquePointer) { unsafe self.pointer = pointer }
}
@safe private final class SharedMemoryPoolStorage {
    let pointer: OpaquePointer
    init(_ pointer: OpaquePointer) { unsafe self.pointer = pointer }
}

/// Owns one explicit native buffer reference independently of the client's native resource.
///
/// Resource destruction invalidates metadata and pixel access but does not consume
/// this external reference. Display closure releases every remaining external ref.
@safe public struct SharedMemoryBuffer: ~Copyable {
    private let owner: OwnedHandle
    private let storage: SharedMemoryBufferStorage
    private let resource: ServerObjectReference<WlBuffer>
    private let display: ObjectHandle

    fileprivate init(owner: consuming OwnedHandle, storage: SharedMemoryBufferStorage,
         resource: ServerObjectReference<WlBuffer>, display: ObjectHandle) {
        self.owner = owner
        self.storage = storage
        self.resource = resource
        self.display = display
    }
    /// Exposes this external reference's lifetime without granting release authority.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Copies native geometry only while both the external reference and resource remain live.
    public borrowing func metadata() throws -> SharedMemoryMetadata {
        try lifetime.withAccess(matching: .sharedMemoryBuffer) {
            try resource.lifetime.withAccess {
                unsafe SharedMemoryMetadata(width: wl_shm_buffer_get_width(storage.pointer), height: wl_shm_buffer_get_height(storage.pointer),
                                            stride: wl_shm_buffer_get_stride(storage.pointer), format: wl_shm_buffer_get_format(storage.pointer))
            }
        }
    }
    /// Acquires another independently accounted external buffer reference.
    public borrowing func reference() throws -> SharedMemoryBuffer {
        try lifetime.withAccess(matching: .sharedMemoryBuffer) {
            try resource.lifetime.withAccess { unsafe try acquireSharedMemory(resource: resource, display: display, pointer: storage.pointer) }
        }
    }
    /// Acquires an independent pool reference that prevents native mapping relocation until released.
    public borrowing func referencePool() throws -> SharedMemoryPool {
        try lifetime.withAccess(matching: .sharedMemoryBuffer) {
            try resource.lifetime.withAccess {
                let pointer = unsafe wl_shm_buffer_ref_pool(storage.pointer)!
                let state = unsafe SharedMemoryPoolStorage(pointer)
                do {
                    let owner = unsafe try display.adopt(nativeIdentifier: UInt64(UInt(bitPattern: Unmanaged.passUnretained(state).toOpaque())),
                        kind: .sharedMemoryPool, dependencies: [display]) { unsafe wl_shm_pool_unref(state.pointer) }
                    return SharedMemoryPool(owner: owner)
                } catch { unsafe wl_shm_pool_unref(pointer); throw error }
            }
        }
    }
    /// Copies tightly packed ARGB8888/XRGB8888 rows inside a balanced same-thread native access scope.
    ///
    /// The result owns its bytes and omits native row padding. Concurrent peer writes
    /// may produce a mixed frame. Native SIGBUS recovery may also post a client error.
    /// No caller closure executes while mapped pixels are borrowed.
    public borrowing func snapshot(maximumBytes: Int = 64 * 1024 * 1024) throws -> [UInt8] {
        try lifetime.withAccess(matching: .sharedMemoryBuffer) {
            try resource.lifetime.withAccess {
                let metadata = try self.metadata()
                guard metadata.format == 0 || metadata.format == 1 else { throw SharedMemoryError.unsupportedFormat }
                guard metadata.width > 0, metadata.height > 0, metadata.width <= Int32.max / 4,
                      metadata.stride >= metadata.width * 4 else { throw SharedMemoryError.invalidLayout }
                let (count, overflow) = (Int(metadata.width) * 4).multipliedReportingOverflow(by: Int(metadata.height))
                guard !overflow else { throw SharedMemoryError.invalidLayout }
                guard maximumBytes >= 0 && count <= maximumBytes else { throw SharedMemoryError.quotaExceeded }
                var bytes = [UInt8](repeating: 0, count: count)
                let result = bytes.withUnsafeMutableBufferPointer {
                    unsafe wayland_kit_shm_snapshot(storage.pointer, $0.baseAddress, $0.count)
                }
                guard result == 0 else { throw SharedMemoryError.nativeFailure(result) }
                return bytes
            }
        }
    }
    /// Requests exactly one native external unref after active scopes quiesce.
    @discardableResult public borrowing func requestClose() -> CloseProgress { owner.requestClose() }
    /// Consumes authority for exactly one external native unref.
    @discardableResult public consuming func close() -> CloseProgress { owner.close() }
}

/// Owns one explicit native pool reference without exposing its mapped storage.
public struct SharedMemoryPool: ~Copyable {
    private let owner: OwnedHandle
    init(owner: consuming OwnedHandle) { self.owner = owner }
    /// Exposes this independent pool obligation's lifetime.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Releases the reference and permits a deferred native resize when it is the last external ref.
    @discardableResult public borrowing func requestClose() -> CloseProgress { owner.requestClose() }
    /// Consumes authority and releases one native pool reference.
    @discardableResult public consuming func close() -> CloseProgress { owner.close() }
}

@unsafe private func acquireSharedMemory(resource: ServerObjectReference<WlBuffer>, display: ObjectHandle,
                                        pointer: OpaquePointer) throws -> SharedMemoryBuffer {
    let pointer = unsafe wl_shm_buffer_ref(pointer)!
    let state = unsafe SharedMemoryBufferStorage(pointer)
    do {
        let owner = unsafe try display.adopt(nativeIdentifier: UInt64(UInt(bitPattern: Unmanaged.passUnretained(state).toOpaque())),
            kind: .sharedMemoryBuffer, dependencies: [display]) { unsafe wl_shm_buffer_unref(state.pointer) }
        return SharedMemoryBuffer(owner: owner, storage: state, resource: resource, display: display)
    } catch { unsafe wl_shm_buffer_unref(pointer); throw error }
}

extension ServerDisplay {
    /// Creates native display-owned SHM globals and their standard format announcements.
    ///
    /// Call once before clients bind SHM. Native display destruction owns its globals.
    public borrowing func initializeSharedMemory() throws {
        try lifetime.withAccess(matching: .serverDisplay) {
            guard unsafe wl_display_init_shm(storage.pointer) == 0 else { throw ServerError.nativeFailure(errno) }
        }
    }
    /// Adds a native SHM format under the caller's compositor support policy.
    ///
    /// Advertisement does not implement format decoding or change snapshot support.
    public borrowing func addSharedMemoryFormat(_ format: UInt32) throws {
        try lifetime.withAccess(matching: .serverDisplay) {
            guard unsafe wl_display_add_shm_format(storage.pointer, format) != nil else { throw ServerError.nativeFailure(ENOMEM) }
        }
    }
    /// Acquires one external reference from a live, same-display native SHM buffer resource.
    public borrowing func sharedMemoryBuffer(for resource: ServerObjectReference<WlBuffer>) throws -> SharedMemoryBuffer {
        guard resource.lifetime.identity.session == lifetime.identity.session else { throw OwnershipError.foreignSession }
        return try lifetime.withAccess(matching: .serverDisplay) {
            unsafe try resource.withUnsafeNativeResource { pointer in
                guard let buffer = unsafe wl_shm_buffer_get(pointer) else { throw SharedMemoryError.notSharedMemory }
                return unsafe try acquireSharedMemory(resource: resource, display: lifetime, pointer: buffer)
            }
        }
    }
}
