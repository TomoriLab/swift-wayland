import CWaylandUtilities
import WaylandRuntime

/// Describes invalid byte-array sizes, mutation conflicts, and expired view tokens.
public enum ByteArrayError: Error, Equatable, Sendable {
    /// Native allocation failed without changing the original contents.
    case allocationFailed
    /// A view of this backing allocation is still active.
    case activeView
    /// The view scope has ended.
    case expiredView
    /// A byte index or range lies outside initialized storage.
    case outOfBounds
    /// The array would exceed its configured byte quota.
    case quotaExceeded
}
@safe fileprivate final class ByteArrayStorage {
    let pointer: UnsafeMutablePointer<wl_array>
    let maximumBytes: Int
    var views = 0
    init(pointer: UnsafeMutablePointer<wl_array>, maximumBytes: Int) {
        unsafe self.pointer = pointer
        self.maximumBytes = maximumBytes
    }
}
fileprivate final class ByteArrayViewToken { var active = true }

/// Owns initialized native byte storage with mutation checks shared by all references.
public struct NativeByteArray: ~Copyable {
    private let session: OwnershipSession
    private let owner: OwnedHandle
    private let storage: ByteArrayStorage
    /// Creates an empty native array with a bounded growth policy.
    ///
    /// Native allocation and failed runtime publication both release their temporary
    /// storage. Fatal Swift allocation failure is not recoverable through this API.
    public init(maximumBytes: Int = 64 * 1024 * 1024) throws {
        guard maximumBytes >= 0 else { throw ByteArrayError.quotaExceeded }
        guard let pointer = unsafe wayland_kit_array_create() else { throw ByteArrayError.allocationFailed }
        let session: OwnershipSession
        do { session = try OwnershipSession() }
        catch { unsafe wayland_kit_array_destroy(pointer); throw error }
        let owner: OwnedHandle
        do {
            owner = unsafe try session.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .byteArray) {
                unsafe wayland_kit_array_destroy(pointer)
            }
        } catch { unsafe wayland_kit_array_destroy(pointer); throw error }
        storage = unsafe ByteArrayStorage(pointer: pointer, maximumBytes: maximumBytes)
        self.session = consume session
        self.owner = consume owner
    }
    /// Creates a checked reference without copying native destruction authority.
    public var reference: NativeByteArrayReference { borrowing get { NativeByteArrayReference(lifetime: owner.reference, storage: storage) } }
    /// Returns ownership accounting, including after logical closure.
    public borrowing func snapshot() throws -> OwnershipSnapshot { try session.snapshot() }
    /// Rejects new operations and releases storage after active views quiesce.
    @discardableResult public borrowing func requestClose() -> CloseProgress { owner.requestClose() }
    /// Consumes the allocation's destruction authority.
    @discardableResult public consuming func close() -> CloseProgress { owner.close() }
}

/// Shares checked byte-array operations and the backing allocation's mutation guard.
public struct NativeByteArrayReference {
    /// Provides lifetime metadata without native allocation access.
    public let lifetime: ObjectHandle
    private let storage: ByteArrayStorage
    fileprivate init(lifetime: ObjectHandle, storage: ByteArrayStorage) { self.lifetime = lifetime; self.storage = storage }
    /// Appends initialized bytes without mutating storage on quota or native allocation failure.
    public func append(_ bytes: [UInt8]) throws {
        try lifetime.withAccess(matching: .byteArray) {
            guard storage.views == 0 else { throw ByteArrayError.activeView }
            let size = unsafe storage.pointer.pointee.size
            guard bytes.count <= storage.maximumBytes - size else { throw ByteArrayError.quotaExceeded }
            if bytes.isEmpty { return }
            guard let destination = unsafe wl_array_add(storage.pointer, bytes.count) else { throw ByteArrayError.allocationFailed }
            bytes.withUnsafeBytes { buffer in
                unsafe destination.copyMemory(from: buffer.baseAddress!, byteCount: bytes.count)
            }
        }
    }
    /// Removes all initialized bytes while preserving native reserved capacity.
    public func clear() throws {
        try lifetime.withAccess(matching: .byteArray) {
            guard storage.views == 0 else { throw ByteArrayError.activeView }
            unsafe storage.pointer.pointee.size = 0
        }
    }
    /// Grants an operation-only view during one synchronous, nonsuspending native frame.
    ///
    /// Escaped views reject later operations. All aliases reject mutation until
    /// the body exits, including throwing exits. Closing inside the body logically
    /// invalidates views immediately and defers native release until this returns.
    public func withView<Result: ~Copyable>(_ body: (NativeByteArrayView) throws -> Result) throws -> Result {
        try lifetime.withAccess(matching: .byteArray) {
            let token = ByteArrayViewToken()
            storage.views += 1
            defer { token.active = false; storage.views -= 1 }
            return try body(NativeByteArrayView(lifetime: lifetime, storage: storage, token: token))
        }
    }
    /// Copies every initialized byte independently of subsequent mutation or closure.
    public func bytes() throws -> [UInt8] { try withView { try $0.bytes() } }
}

/// Provides checked byte operations without exposing or binding native storage pointers.
public struct NativeByteArrayView {
    private let lifetime: ObjectHandle
    private let storage: ByteArrayStorage
    private let token: ByteArrayViewToken
    fileprivate init(lifetime: ObjectHandle, storage: ByteArrayStorage, token: ByteArrayViewToken) {
        self.lifetime = lifetime; self.storage = storage; self.token = token
    }
    /// Returns initialized byte count only while this scope and allocation remain live.
    public func count() throws -> Int {
        guard token.active else { throw ByteArrayError.expiredView }
        return try lifetime.withAccess(matching: .byteArray) { unsafe storage.pointer.pointee.size }
    }
    /// Copies one initialized byte after index and scope validation.
    public func byte(at index: Int) throws -> UInt8 {
        guard token.active else { throw ByteArrayError.expiredView }
        return try lifetime.withAccess(matching: .byteArray) {
            guard unsafe index >= 0 && index < storage.pointer.pointee.size else { throw ByteArrayError.outOfBounds }
            return unsafe storage.pointer.pointee.data!.load(fromByteOffset: index, as: UInt8.self)
        }
    }
    /// Returns an owned copy of initialized bytes, without retaining native backing memory.
    public func bytes() throws -> [UInt8] {
        guard token.active else { throw ByteArrayError.expiredView }
        return try lifetime.withAccess(matching: .byteArray) {
            let count = unsafe storage.pointer.pointee.size
            if count == 0 { return [] }
            return unsafe Array(UnsafeRawBufferPointer(start: storage.pointer.pointee.data!, count: count))
        }
    }
}
