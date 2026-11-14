/// Retains only copied identity and a weak link to authoritative bookkeeping.
///
/// Native destroy listeners remain reachable through their cleanup record even
/// after the last handle cell disappears. An observer must therefore not depend
/// on a weak cell being present when the native signal fires.
public final class NativeDestructionObserver {
    private weak var control: RuntimeControl?
    private let lifetime: RecordLifetime?
    /// A copied identity snapshot suitable for destruction notifications.
    public let identity: HandleIdentity
    init(_ handle: ObjectHandle) { control = handle.cell.control; identity = handle.identity; lifetime = handle.cell.lifetime }

    /// Consumes native authority inside an existing enclosing native frame.
    ///
    /// A server-client cascade guarantees native destruction of every tracked
    /// server resource, self-detaching resource-watch, or wire-authorized resource-destruction descendant. No other dependent kind may be silently
    /// consumed. Foreign unframed destruction violates this unsafe contract.
    @unsafe public func destroyed(serverClientCascade: Bool = false) throws -> Bool {
        guard let control else { return false }
        let cell = HandleCell(control: control, identity: identity, lifetime: lifetime)
        if serverClientCascade { return unsafe try control.nativeDestroyedServerSubtree(cell) }
        return unsafe try control.nativeDestroyed(cell)
    }
}

extension ObjectHandle {
    /// Creates a native-notification observer that does not retain this session or cell.
    public func destructionObserver() -> NativeDestructionObserver { NativeDestructionObserver(self) }
}

extension NativeDestructionObserver {
    /// Validates native callback admission without converting its scope into an outer C frame.
    public func withCallback<Result: ~Copyable>(_ body: () throws -> Result) throws -> Result {
        try admitCallback()
        return try body()
    }
}


extension NativeDestructionObserver {
    /// Reconstructs and validates a temporary reference without retaining a root in callback storage.
    public func withLiveReference<Result: ~Copyable>(_ body: (ObjectHandle) throws -> Result) throws -> Result {
        guard let control else { throw OwnershipError.closedSession }
        let reference = ObjectHandle(cell: HandleCell(control: control, identity: identity, lifetime: lifetime))
        return try reference.withAccess { try body(reference) }
    }
    /// Requests a metadata-proven protocol terminal transition inside the native frame.
    @unsafe public func protocolClosed() -> CloseProgress {
        control?.requestClose(generation: identity.generation) ?? .complete
    }
}


extension NativeDestructionObserver {
    /// Validates callback delivery under an already retained enclosing native invocation.
    @usableFromInline func admitCallback() throws {
        if let lifetime, lifetime.admission.hasUninterruptedNativeFrame {
            guard lifetime.live else { throw OwnershipError.invalidHandle }
            return
        }
        guard let control else { throw OwnershipError.invalidHandle }
        try control.admitCallback(identity, lifetime: lifetime)
    }

    @usableFromInline func admitCallback(gate: CallbackDeliveryGate) throws -> Bool {
        if let lifetime {
            let state = lifetime.admission.callbackState(cancellation: gate.state)
            if state != 0 {
                guard lifetime.live else { throw OwnershipError.invalidHandle }
                return state == 1
            }
        }
        try admitCallback()
        return !gate.cancelled
    }

    /// Admits mandatory typed cleanup while checking a copied cancellation authority.
    @unsafe package func admitTypedCallback(cancellation: CallbackCancellation) throws -> Bool {
        try admitCallback(gate: cancellation.gate)
    }

    /// Admits cleanup after logical closure while an outer native frame retains the record.
    @unsafe package func admitTypedClosingCallback() throws {
        try admitClosingCallback()
    }
}


extension NativeDestructionObserver {
    /// Proves that cleanup userdata remains retained inside an existing native invocation.
    @usableFromInline func admitClosingCallback() throws {
        guard let control else { throw OwnershipError.invalidHandle }
        try control.admitClosingCallback(identity)
    }
}
