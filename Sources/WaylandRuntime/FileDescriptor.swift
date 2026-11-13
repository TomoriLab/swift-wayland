import CWaylandRuntime

/// Describes descriptor-specific failures without losing native errno information.
package enum FileDescriptorError: Error, Equatable, Sendable {
    /// The raw value was negative, closed, or otherwise invalid at adoption.
    case invalidDescriptor(Int32)
    /// F_DUPFD_CLOEXEC failed and produced no new descriptor.
    case duplicationFailed(Int32)
    /// A raw-value borrow is active, so ownership cannot be transferred.
    case activeBorrow
    /// The descriptor has already been closed or transferred.
    case noOwnership
}

/// Reports a close request without confusing deferred cleanup with syscall success.
package struct FileDescriptorCloseResult: Equatable, Sendable {
    /// Whether the runtime record has completed retirement.
    package let progress: CloseProgress
    /// The saved Linux close error, available after the single attempt finishes.
    package let errorCode: Int32?
}

/// Provides observable descriptor accounting without exposing a reusable raw number.
package struct FileDescriptorSnapshot: Equatable, Sendable {
    /// Whether this storage still owns a descriptor number.
    package let ownsDescriptor: Bool
    /// The number of scoped raw-value borrows currently active.
    package let activeBorrows: Int
    /// The number of close syscalls attempted by this storage.
    package let closeAttempts: Int
    /// The result of the completed close syscall, or nil if none failed.
    package let closeError: Int32?
}

private struct DescriptorValue: Sendable {
    var descriptor: Int32?
    var borrows = 0
    var closeAttempts = 0
    var closeError: Int32?
}

final class DescriptorStorage {
    private let value: RuntimeMutex<DescriptorValue>

    init(_ descriptor: Int32) throws { value = try RuntimeMutex(DescriptorValue(descriptor: descriptor)) }

    func borrow<Result: ~Copyable>(_ body: (Int32) throws -> Result) throws -> Result {
        let descriptor = try value.withLock { state in
            guard let descriptor = state.descriptor else { throw FileDescriptorError.noOwnership }
            state.borrows += 1
            return descriptor
        }
        defer { value.withLock { $0.borrows -= 1 } }
        return try body(descriptor)
    }

    func transfer(_ relinquish: () throws -> Void) throws -> Int32 {
        try value.withLock { state in
            guard state.borrows == 0 else { throw FileDescriptorError.activeBorrow }
            guard let descriptor = state.descriptor else { throw FileDescriptorError.noOwnership }
            // The caller holds a native frame, so relinquish cannot execute a cleanup action here.
            try relinquish()
            state.descriptor = nil
            return descriptor
        }
    }

    func close() {
        let descriptor = value.withLock { state -> Int32? in
            guard let descriptor = state.descriptor else { return nil }
            precondition(state.borrows == 0)
            state.descriptor = nil
            state.closeAttempts += 1
            return descriptor
        }
        if let descriptor {
            let error = wayland_runtime_descriptor_close(descriptor)
            value.withLock { $0.closeError = error == 0 ? nil : error }
        }
    }

    func snapshot() -> FileDescriptorSnapshot {
        value.withLock {
            FileDescriptorSnapshot(ownsDescriptor: $0.descriptor != nil, activeBorrows: $0.borrows,
                                   closeAttempts: $0.closeAttempts, closeError: $0.closeError)
        }
    }
}

/// Owns one descriptor through the session's authoritative cleanup record.
///
/// Implicit destruction requests the same cleanup as explicit close. Session close
/// invalidates references even when this owner remains alive. This owner is not
/// Sendable; transferring a raw number is a separate, explicitly unsafe operation.
package struct OwnedFileDescriptor: ~Copyable {
    private let storage: DescriptorStorage
    private let owner: OwnedHandle

    init(storage: DescriptorStorage, owner: consuming OwnedHandle) {
        self.storage = storage
        self.owner = owner
    }

    /// Produces a copyable checked reference with no independent close authority.
    package var borrowed: BorrowedFileDescriptor {
        borrowing get { BorrowedFileDescriptor(storage: storage, reference: owner.reference) }
    }

    /// Provides a lifetime dependency for native consumers of this descriptor.
    package var lifetime: ObjectHandle { borrowing get { owner.reference } }

    /// Requests closure, deferring the single close syscall while a native frame is active.
    @discardableResult
    package borrowing func requestClose() -> FileDescriptorCloseResult {
        FileDescriptorCloseResult(progress: owner.requestClose(), errorCode: storage.snapshot().closeError)
    }

    /// Consumes the owner and requests closure; deferred results do not promise syscall success.
    @discardableResult
    package consuming func close() -> FileDescriptorCloseResult {
        let progress = owner.close()
        return FileDescriptorCloseResult(progress: progress, errorCode: storage.snapshot().closeError)
    }

    /// Consumes this owner and transfers the raw descriptor without closing it.
    ///
    /// The recipient must close it or follow the receiving C API's exact ownership
    /// contract. Transfer is rejected during a raw borrow or while dependent native
    /// consumers remain. On a throwing transfer this consumed owner's fallback
    /// cleanup still closes its descriptor. No await is permitted in this transaction.
    @unsafe package consuming func takeRawDescriptor() throws -> Int32 {
        let reference = owner.reference
        return try reference.withAccess(matching: .fileDescriptor) {
            try storage.transfer { unsafe try reference.cell.control.relinquish(reference.cell) }
        }
    }
}

/// Keeps descriptor bookkeeping alive without extending native usability after close.
package struct BorrowedFileDescriptor {
    let storage: DescriptorStorage
    let reference: ObjectHandle

    /// Returns a conservative validity observation, not raw-access authorization.
    package var isValid: Bool { reference.isValid }

    /// Exposes accounting even after the descriptor has been invalidated.
    package var snapshot: FileDescriptorSnapshot { storage.snapshot() }

    /// Creates a distinct CLOEXEC descriptor owned by the same session.
    ///
    /// The original remains owned and unchanged. A registration failure closes the
    /// new duplicate. This operation does not make a copied raw integer durable.
    package func duplicate() throws -> OwnedFileDescriptor {
        try reference.withAccess(matching: .fileDescriptor) {
            try storage.borrow { descriptor in
                var error: Int32 = 0
                let duplicate = unsafe wayland_runtime_descriptor_duplicate(descriptor, &error)
                guard duplicate >= 0 else { throw FileDescriptorError.duplicationFailed(error) }
                return unsafe try registerDescriptor(duplicate, control: reference.cell.control, consumeOnFailure: true)
            }
        }
    }

    /// Borrows the raw number only for synchronous native interoperation.
    ///
    /// The caller must not close, transfer, store, or send this integer to another
    /// task. The runtime preserves native lifetime through the complete scope and
    /// rejects transfer while it is borrowed. A throwing body releases its borrow.
    @unsafe package func withUnsafeDescriptor<Result: ~Copyable>(_ body: (Int32) throws -> Result) throws -> Result {
        try reference.withAccess(matching: .fileDescriptor) { try storage.borrow(body) }
    }
}

@unsafe private func registerDescriptor(
    _ descriptor: Int32, control: RuntimeControl, consumeOnFailure: Bool
) throws -> OwnedFileDescriptor {
    do {
        let error = wayland_runtime_descriptor_validate(descriptor)
        guard error == 0 else { throw FileDescriptorError.invalidDescriptor(error) }
        let storage = try DescriptorStorage(descriptor)
        let owner = unsafe try control.adopt(nativeIdentifier: UInt64(descriptor), kind: .fileDescriptor,
                                            dependencies: []) { storage.close() }
        return OwnedFileDescriptor(storage: storage, owner: owner)
    } catch {
        if consumeOnFailure && descriptor >= 0 { _ = wayland_runtime_descriptor_close(descriptor) }
        throw error
    }
}

extension OwnershipSession {
    /// Takes ownership only after successful validation and record publication.
    ///
    /// The caller must exclusively own a valid raw descriptor and retain its
    /// cleanup obligation on failure. Existing descriptor flags are preserved.
    @unsafe package borrowing func adoptFileDescriptor(_ descriptor: Int32) throws -> OwnedFileDescriptor {
        unsafe try registerDescriptor(descriptor, control: control, consumeOnFailure: false)
    }

    /// Receives an exclusively owned descriptor and consumes it on every outcome.
    ///
    /// Use this for incoming native events and owned duplicates: session shutdown,
    /// capacity failure, and other registration failures must not leak the fd.
    /// The raw value must not already belong to another owner or runtime record.
    @unsafe package borrowing func receiveFileDescriptor(_ descriptor: Int32) throws -> OwnedFileDescriptor {
        unsafe try registerDescriptor(descriptor, control: control, consumeOnFailure: true)
    }
}

/// Owns a received descriptor before decoding, delivery, or session registration.
///
/// Dropping an ignored or partially decoded event closes this value's descriptor
/// even when the session is already closed. No runtime or user context is retained.
package struct ReceivedFileDescriptor: ~Copyable {
    private var descriptor: Int32?

    /// Takes exclusive native ownership of a valid received descriptor.
    ///
    /// The native API must actually transfer ownership; borrowed descriptor numbers
    /// must never enter this constructor. Invalid input creates no owner.
    @unsafe package init(adopting descriptor: Int32) throws {
        let error = wayland_runtime_descriptor_validate(descriptor)
        guard error == 0 else { throw FileDescriptorError.invalidDescriptor(error) }
        self.descriptor = descriptor
    }

    /// Consumes the receive scope and moves ownership into a session or closes on failure.
    ///
    /// Disarming before registration prevents fallback destruction from retrying
    /// a descriptor already consumed by a failed session registration.
    package consuming func register(in session: borrowing OwnershipSession) throws -> OwnedFileDescriptor {
        guard let value = descriptor else { throw FileDescriptorError.noOwnership }
        descriptor = nil
        return unsafe try session.receiveFileDescriptor(value)
    }

    deinit {
        if let descriptor { _ = wayland_runtime_descriptor_close(descriptor) }
    }
}
