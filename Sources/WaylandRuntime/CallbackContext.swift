/// Describes registration or subscription lifecycle failures.
public enum CallbackContextError: Error, Equatable, Sendable {
    /// A registration can issue only one cancellation-owning subscription.
    case subscriptionAlreadyIssued
    /// Delivery was canceled before subscription publication.
    case cancelled
}

/// Returns handler failures as values so Swift errors never unwind through C.
public enum CallbackDeliveryResult: Sendable {
    /// The handler returned normally.
    case delivered
    /// User delivery was canceled; native context remains attached.
    case cancelled
    /// No valid session, native frame, or live registration was available.
    case unavailable
    /// The handler threw; the adapter must apply its protocol-specific error policy.
    case failed(any Error)
}

/// Describes native attachment success or an explicit rollback obligation.
///
/// A failed installation must provide rollback if C retained userdata. Nil rollback
/// asserts that no native consumer can call or retain that pointer. A successful
/// detach must prevent future calls and quiesce concurrent native entry before
/// returning. This API does not model a proxy listener with no removal operation.
public enum CallbackInstallResult: ~Copyable {
    /// Transfers a nonthrowing, thread-compatible physical detach action.
    case installed(detach: () -> Void)
    /// Reports installation failure with optional cleanup of partial native attachment.
    case failed(any Error, rollback: (() -> Void)?)
}

@usableFromInline struct DeliveryState: Sendable {
    var cancelled = false
    var subscriptionIssued = false
}

/// Stores only cancellation bits; it owns no context, runtime cell, or native pointer.
@usableFromInline final class CallbackDeliveryGate: Sendable {
    @usableFromInline let state: RuntimeMutex<DeliveryState>
    init() throws { state = try RuntimeMutex(DeliveryState()) }
    func cancel() { state.withLock { $0.cancelled = true; state.setNotification(true) } }
    @usableFromInline var cancelled: Bool { state.notificationPending }
    func issue() throws {
        try state.withLock { value in
            guard !value.subscriptionIssued else { throw CallbackContextError.subscriptionAlreadyIssued }
            guard !value.cancelled else { throw CallbackContextError.cancelled }
            value.subscriptionIssued = true
        }
    }
}

/// Allows thread-safe cancellation without transferring a native lifetime capability.
public struct CallbackCancellation: Sendable {
    let gate: CallbackDeliveryGate
    /// Stops future user delivery without detaching or freeing C userdata.
    public func cancel() { gate.cancel() }
    /// Reports logical cancellation, independently of physical attachment lifetime.
    public var isCancelled: Bool { gate.cancelled }
}

/// Owns logical delivery cancellation, not physical C registration lifetime.
///
/// Dropping or canceling this token leaves the stable native dispatcher attached.
/// Its flag-only cancellation handle can cross tasks without retaining user data.
public struct CallbackSubscription: ~Copyable {
    /// Produces a copyable cancellation signal with no native resource access.
    public let cancellation: CallbackCancellation
    /// Cancels delivery idempotently; an already admitted handler may finish.
    public borrowing func cancel() { cancellation.cancel() }
    deinit { cancellation.cancel() }
}

@usableFromInline final class CallbackStorage<Context: AnyObject> {
    @usableFromInline let gate: CallbackDeliveryGate
    @usableFromInline var observer: NativeDestructionObserver?
    @usableFromInline var context: Context?
    var detach: (() -> Void)?

    init(_ context: Context) throws {
        self.context = context
        gate = try CallbackDeliveryGate()
    }

    func retire() {
        gate.cancel()
        let action = detach
        detach = nil
        action?()
        context = nil
        withExtendedLifetime(action) {}
    }
}

/// Owns the physical lifetime of one detachable native callback context.
///
/// The cleanup record retains stable userdata independently of this value. Logical
/// subscription cancellation does not consume that record. Context and detach
/// captures are released after physical detach and outer native-frame quiescence.
/// Thread-affine callbacks remain unsupported. Permanent proxy dispatchers use
/// ProxyDispatcherOwner instead of this detachable registration.
public struct CallbackAttachment<Context: AnyObject>: ~Copyable {
    private let storage: CallbackStorage<Context>
    private let owner: OwnedHandle

    fileprivate init(storage: CallbackStorage<Context>, owner: consuming OwnedHandle) {
        self.storage = storage
        self.owner = owner
    }

    /// Provides checked native-lifetime identity without exposing raw userdata.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Provides a thread-safe delivery-only cancellation signal.
    public var cancellation: CallbackCancellation {
        borrowing get { CallbackCancellation(gate: storage.gate) }
    }

    /// Issues the sole RAII subscription; dropping it cancels only user delivery.
    public borrowing func subscription() throws -> CallbackSubscription {
        try storage.gate.issue()
        return CallbackSubscription(cancellation: CallbackCancellation(gate: storage.gate))
    }

    /// Cancels delivery and requests physical detach through the cleanup record.
    @discardableResult
    public borrowing func requestClose() -> CloseProgress {
        storage.gate.cancel()
        return owner.requestClose()
    }

    /// Consumes attachment authority; active native frames defer physical detach.
    @discardableResult
    public consuming func close() -> CloseProgress {
        storage.gate.cancel()
        return owner.requestClose()
    }

    deinit { storage.gate.cancel() }

    /// Enters Swift from a native callback using the still-attached userdata pointer.
    ///
    /// The native caller must hold the complete outer call in withNativeFrame and
    /// guarantee userdata is alive before entry, including concurrent entry races.
    /// The context type must match this specialization. A detach action must never
    /// return while native code can still enter this function with the old pointer.
    /// Busy or closed domains decline delivery without reading the user context.
    /// Handler errors become values; no thrown error crosses the C boundary.
    /// Owned event payloads must remain in the trampoline's RAII scope even when
    /// delivery is canceled, unavailable, or failed.
    @unsafe public static func deliver(
        userData: UnsafeMutableRawPointer?, _ body: (Context) throws -> Void
    ) -> CallbackDeliveryResult {
        guard let userData = unsafe userData else { return .unavailable }
        // Native attachment owns one retained count until detach and quiescence complete.
        let storage = unsafe Unmanaged<CallbackStorage<Context>>.fromOpaque(userData).takeUnretainedValue()
        if storage.gate.cancelled { return .cancelled }
        guard let observer = storage.observer else { return .unavailable }
        do {
            return try observer.withCallback {
                if storage.gate.cancelled { return .cancelled }
                guard let context = storage.context else { return .unavailable }
                do {
                    try body(context)
                    return .delivered
                } catch { return .failed(error) }
            }
        } catch { return .unavailable }
    }
}

extension OwnershipSession {
    /// Installs a stable detachable callback with provisional context and rollback.
    ///
    /// The context is initialized and retained before install can call back. An
    /// authoritative record is reserved before C attachment. Its dependencies
    /// remain valid until detach returns. Install and detach must obey their exact
    /// native retention/quiescence contracts and must not strongly retain the
    /// owning session/cell. Failure after attachment must return rollback. Root
    /// close during synchronous installation is handled after rollback is stored.
    /// Context fields are accessed only in the serialized runtime domain; callers
    /// must avoid unsynchronized external mutation and user-created ARC cycles.
    ///
    /// - Throws: An installation error or a runtime allocation/state error.
    @unsafe public borrowing func attachCallback<Context: AnyObject>(
        context: Context,
        dependencies: [ObjectHandle] = [],
        install: (UnsafeMutableRawPointer) -> CallbackInstallResult
    ) throws -> CallbackAttachment<Context> {
        try control.withNativeFrame {
            let storage = try CallbackStorage(context)
            let pointer = unsafe Unmanaged.passRetained(storage).toOpaque()
            let owner: OwnedHandle
            do {
                owner = unsafe try control.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .registration,
                                                dependencies: dependencies) {
                    storage.retire()
                    unsafe Unmanaged<CallbackStorage<Context>>.fromOpaque(pointer).release()
                }
            } catch {
                unsafe Unmanaged<CallbackStorage<Context>>.fromOpaque(pointer).release()
                throw error
            }
            storage.observer = owner.reference.destructionObserver()
            guard owner.reference.isValid else { throw OwnershipError.closedSession }
            let result = unsafe install(pointer)
            switch consume result {
            case .installed(let detach): storage.detach = detach
            case .failed(let error, let rollback):
                storage.detach = rollback
                throw error
            }
            guard owner.reference.isValid else { throw OwnershipError.closedSession }
            return CallbackAttachment(storage: storage, owner: owner)
        }
    }
}
