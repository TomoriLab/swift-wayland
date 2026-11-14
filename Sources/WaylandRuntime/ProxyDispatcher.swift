/// Reports permanent dispatcher installation failures.
public enum ProxyDispatcherError: Error, Equatable, Sendable {
    /// Native installation rejected the proxy without retaining the provisional context.
    case installationFailed
}

/// Owns a proxy and its permanent dispatcher as one cleanup obligation.
///
/// Canceling or dropping a subscription leaves native storage attached. Closing
/// this owner destroys the proxy before releasing context. An enclosing native
/// frame defers both actions together. This value intentionally is not Sendable.
public struct ProxyDispatcherOwner<Context: AnyObject>: ~Copyable {
    private let storage: CallbackStorage<Context>
    private let owner: OwnedHandle

    init(storage: CallbackStorage<Context>, owner: consuming OwnedHandle) {
        self.storage = storage
        self.owner = owner
    }

    /// Provides checked identity for access and connection dependency tracking.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Provides cancellation without native pointer or context ownership.
    public var cancellation: CallbackCancellation {
        borrowing get { CallbackCancellation(gate: storage.gate) }
    }
    /// Issues the sole logical delivery subscription without changing native registration.
    public borrowing func subscription() throws -> CallbackSubscription {
        try storage.gate.issue()
        return CallbackSubscription(cancellation: cancellation)
    }
    /// Invalidates access and requests proxy destruction at native quiescence.
    @discardableResult
    public borrowing func requestClose() -> CloseProgress {
        storage.gate.cancel()
        return owner.requestClose()
    }
    /// Consumes proxy authority and requests the same single cleanup action.
    @discardableResult
    public consuming func close() -> CloseProgress {
        storage.gate.cancel()
        return owner.requestClose()
    }
    deinit { storage.gate.cancel() }

    /// Delivers a native event while a complete enclosing native invocation is leased.
    ///
    /// The pointer must originate from receiveProxyDispatcher with the identical
    /// Context type and still belong to an undestroyed proxy. Foreign destruction,
    /// replacement, and concurrent uncoordinated dispatch violate this contract.
    /// Mandatory payload cleanup belongs outside this optional-delivery scope.
    @unsafe public static func deliver(
        userData: UnsafeMutableRawPointer?, _ body: (Context) throws -> Void
    ) -> CallbackDeliveryResult {
        guard let pointer = unsafe userData else { return .unavailable }
        let storage = unsafe Unmanaged<CallbackStorage<Context>>.fromOpaque(pointer).takeUnretainedValue()
        if storage.gate.cancelled { return .cancelled }
        guard let observer = storage.observer else { return .unavailable }
        do {
            return try observer.withCallback {
                if storage.gate.cancelled { return .cancelled }
                guard let context = storage.context else { return .unavailable }
                do { try body(context); return .delivered }
                catch { return .failed(error) }
            }
        } catch { return .unavailable }
    }
}

extension RuntimeControl {
    /// Consumes an exclusively owned proxy and installs its permanent context.
    ///
    /// Every outcome consumes the incoming native obligation. The caller supplies
    /// a nonthrowing local destructor valid on any serialized caller thread.
    /// Installation returns false only when native code retained no userdata.
    /// Neither action nor context may strongly retain this session or its cells.
    /// The native proxy must never be independently destroyed or handed off.
    /// Metadata and native dispatch must obey the complete outer-frame contract.
    /// Native construction and handoff must already lease tracked prerequisites;
    /// an unregistered raw child cannot survive a prerequisite destroyed before admission.
    @unsafe func receiveProxyDispatcher<Context: AnyObject>(
        nativeIdentifier: UInt64,
        context: Context,
        dependencies: [ObjectHandle] = [],
        releaseReadiness: (() -> Bool)? = nil,
        install: (UnsafeMutableRawPointer) -> Bool,
        destroy: @escaping () -> Void
    ) throws -> ProxyDispatcherOwner<Context> {
        var entered = false
        do {
            return try withNativeFrame {
                entered = true
                var recorded = false
                do {
                    let storage = try CallbackStorage(context)
                    let pointer = unsafe Unmanaged.passRetained(storage).toOpaque()
                    let owner: OwnedHandle
                    do {
                        owner = unsafe try adopt(nativeIdentifier: nativeIdentifier, kind: .clientProxy,
                                                        dependencies: dependencies, releaseReadiness: releaseReadiness) {
                            storage.gate.cancel()
                            // Proxy destruction is the physical detach boundary for permanent dispatchers.
                            destroy()
                            storage.retire()
                            unsafe Unmanaged<CallbackStorage<Context>>.fromOpaque(pointer).release()
                        }
                    } catch {
                        unsafe Unmanaged<CallbackStorage<Context>>.fromOpaque(pointer).release()
                        throw error
                    }
                    recorded = true
                    storage.observer = owner.reference.destructionObserver()
                    guard owner.reference.isValid else { throw OwnershipError.closedSession }
                    guard unsafe install(pointer) else { throw ProxyDispatcherError.installationFailed }
                    guard owner.reference.isValid else { throw OwnershipError.closedSession }
                    return ProxyDispatcherOwner(storage: storage, owner: owner)
                } catch {
                    // Rollback runs before this native frame can drain prerequisite destruction.
                    if !recorded { destroy() }
                    throw error
                }
            }
        } catch {
            // No admitted frame means no record could acquire this incoming obligation.
            if !entered { destroy() }
            throw error
        }
    }
}


extension OwnershipSession {
    /// Consumes a native proxy on every outcome and attaches its permanent context.
    ///
    /// Native construction must lease its tracked prerequisites. Install must not
    /// retain userdata on failure. Context/destructor captures must be acyclic and
    /// valid on any serialized caller thread; no independent destruction is allowed.
    @unsafe public borrowing func receiveProxyDispatcher<Context: AnyObject>(
        nativeIdentifier: UInt64, context: Context, dependencies: [ObjectHandle] = [],
        install: (UnsafeMutableRawPointer) -> Bool, destroy: @escaping () -> Void
    ) throws -> ProxyDispatcherOwner<Context> {
        unsafe try control.receiveProxyDispatcher(nativeIdentifier: nativeIdentifier, context: context,
            dependencies: dependencies, install: install, destroy: destroy)
    }
}

extension ObjectHandle {
    /// Consumes an incoming proxy using the same control without creating another root owner.
    ///
    /// The caller must hold a complete native frame and own a valid ordinary proxy.
    /// The same installation, prerequisite, capture, and failure contracts as the
    /// session receive factory apply; every outcome consumes the native proxy.
    @unsafe public func receiveProxyDispatcher<Context: AnyObject>(
        nativeIdentifier: UInt64, context: Context, dependencies: [ObjectHandle],
        install: (UnsafeMutableRawPointer) -> Bool, destroy: @escaping () -> Void
    ) throws -> ProxyDispatcherOwner<Context> {
        unsafe try cell.control.receiveProxyDispatcher(nativeIdentifier: nativeIdentifier, context: context,
            dependencies: dependencies, install: install, destroy: destroy)
    }
}

extension ObjectHandle {
    /// Attaches a proxy whose queued native constructors must quiesce before destruction.
    ///
    /// Readiness executes under the same domain and a complete native frame, without
    /// a bookkeeping lock. It must not retain this control, invoke user delivery,
    /// transfer authority, or indefinitely postpone root shutdown. All other unsafe
    /// receive contracts remain applicable, including consume-on-every-outcome.
    @unsafe package func receiveQueuedProxyDispatcher<Context: AnyObject>(
        nativeIdentifier: UInt64, context: Context, dependencies: [ObjectHandle],
        releaseReadiness: (() -> Bool)?, install: (UnsafeMutableRawPointer) -> Bool, destroy: @escaping () -> Void
    ) throws -> ProxyDispatcherOwner<Context> {
        unsafe try cell.control.receiveProxyDispatcher(nativeIdentifier: nativeIdentifier, context: context,
            dependencies: dependencies, releaseReadiness: releaseReadiness, install: install, destroy: destroy)
    }
}

extension ProxyDispatcherOwner {
    /// Copies cancellation authority from retained dispatcher userdata during installation.
    ///
    /// The caller must not store the raw pointer beyond the attached proxy lifetime.
    @unsafe package static func cancellationForNativeContext(userData: UnsafeMutableRawPointer) -> CallbackCancellation {
        let storage = unsafe Unmanaged<CallbackStorage<Context>>.fromOpaque(userData).takeUnretainedValue()
        return CallbackCancellation(gate: storage.gate)
    }

    /// Runs mandatory decoding independently of the logical subscription gate.
    ///
    /// Native userdata and the complete outer frame must still be valid. The
    /// Boolean controls only optional user delivery; mandatory ownership cleanup
    /// must run even when false. A closed target declines context access unless
    /// allowClosingCleanup is set. That mode requires a retained nonretired record
    /// and outer native frame and grants payload disposal only, never live receiver
    /// access or user delivery. Raw callers must enforce those restrictions.
    @inlinable @unsafe public static func withNativeContext(
        userData: UnsafeMutableRawPointer?, allowClosingCleanup: Bool = false, _ body: (Context, Bool) throws -> Void
    ) -> CallbackDeliveryResult {
        guard let pointer = unsafe userData else { return .unavailable }
        let storage = unsafe Unmanaged<CallbackStorage<Context>>.fromOpaque(pointer).takeUnretainedValue()
        guard let observer = storage.observer else { return .unavailable }
        do {
            let enabled: Bool
            do { enabled = try observer.admitCallback(gate: storage.gate) }
            catch {
                guard allowClosingCleanup else { return .unavailable }
                try observer.admitClosingCallback()
                enabled = false
            }
            guard let context = storage.context else { return .unavailable }
            do { try body(context, enabled); return .delivered }
            catch { return .failed(error) }
        } catch { return .unavailable }
    }
}
