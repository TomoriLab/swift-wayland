/// Reports permanent dispatcher installation failures.
package enum ProxyDispatcherError: Error, Equatable, Sendable {
    /// Native installation rejected the proxy without retaining the provisional context.
    case installationFailed
}

/// Owns a proxy and its permanent dispatcher as one cleanup obligation.
///
/// Canceling or dropping a subscription leaves native storage attached. Closing
/// this owner destroys the proxy before releasing context. An enclosing native
/// frame defers both actions together. This value intentionally is not Sendable.
package struct ProxyDispatcherOwner<Context: AnyObject>: ~Copyable {
    private let storage: CallbackStorage<Context>
    private let owner: OwnedHandle

    init(storage: CallbackStorage<Context>, owner: consuming OwnedHandle) {
        self.storage = storage
        self.owner = owner
    }

    /// Provides checked identity for access and connection dependency tracking.
    package var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Provides cancellation without native pointer or context ownership.
    package var cancellation: CallbackCancellation {
        borrowing get { CallbackCancellation(gate: storage.gate) }
    }
    /// Issues the sole logical delivery subscription without changing native registration.
    package borrowing func subscription() throws -> CallbackSubscription {
        try storage.gate.issue()
        return CallbackSubscription(cancellation: cancellation)
    }
    /// Invalidates access and requests proxy destruction at native quiescence.
    @discardableResult
    package borrowing func requestClose() -> CloseProgress {
        storage.gate.cancel()
        return owner.requestClose()
    }
    /// Consumes proxy authority and requests the same single cleanup action.
    @discardableResult
    package consuming func close() -> CloseProgress {
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
    @unsafe package static func deliver(
        userData: UnsafeMutableRawPointer?, _ body: (Context) throws -> Void
    ) -> CallbackDeliveryResult {
        guard let pointer = unsafe userData else { return .unavailable }
        let storage = unsafe Unmanaged<CallbackStorage<Context>>.fromOpaque(pointer).takeUnretainedValue()
        if storage.gate.cancelled { return .cancelled }
        guard let cell = storage.cell else { return .unavailable }
        do {
            return try cell.control.withCallbackFrame(cell, matching: .clientProxy) {
                if storage.gate.cancelled { return .cancelled }
                guard let context = storage.context else { return .unavailable }
                do { try body(context); return .delivered }
                catch { return .failed(error) }
            }
        } catch { return .unavailable }
    }
}

extension OwnershipSession {
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
    @unsafe package borrowing func receiveProxyDispatcher<Context: AnyObject>(
        nativeIdentifier: UInt64,
        context: Context,
        dependencies: [ObjectHandle] = [],
        install: (UnsafeMutableRawPointer) -> Bool,
        destroy: @escaping () -> Void
    ) throws -> ProxyDispatcherOwner<Context> {
        var entered = false
        do {
            return try control.withNativeFrame {
                entered = true
                var recorded = false
                do {
                    let storage = try CallbackStorage(context)
                    let pointer = unsafe Unmanaged.passRetained(storage).toOpaque()
                    let owner: OwnedHandle
                    do {
                        owner = unsafe try control.adopt(nativeIdentifier: nativeIdentifier, kind: .clientProxy,
                                                        dependencies: dependencies) {
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
                    storage.cell = owner.reference.cell
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
