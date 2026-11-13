/// Retains only copied identity and a weak link to authoritative bookkeeping.
///
/// Native destroy listeners remain reachable through their cleanup record even
/// after the last handle cell disappears. An observer must therefore not depend
/// on a weak cell being present when the native signal fires.
package final class NativeDestructionObserver {
    private weak var control: RuntimeControl?
    /// A copied identity snapshot suitable for destruction notifications.
    package let identity: HandleIdentity
    init(_ handle: ObjectHandle) { control = handle.cell.control; identity = handle.identity }

    /// Consumes native authority inside an existing enclosing native frame.
    ///
    /// A server-client cascade guarantees native destruction of every tracked
    /// server resource descendant. No other dependent kind may be silently
    /// consumed. Foreign unframed destruction violates this unsafe contract.
    @unsafe package func destroyed(serverClientCascade: Bool = false) throws -> Bool {
        guard let control else { return false }
        let cell = HandleCell(control: control, identity: identity)
        if serverClientCascade { return unsafe try control.nativeDestroyedServerSubtree(cell) }
        return unsafe try control.nativeDestroyed(cell)
    }
}

extension ObjectHandle {
    /// Creates a native-notification observer that does not retain this session or cell.
    package func destructionObserver() -> NativeDestructionObserver { NativeDestructionObserver(self) }
}

extension NativeDestructionObserver {
    /// Validates native callback admission without converting its scope into an outer C frame.
    package func withCallback<Result: ~Copyable>(_ body: () throws -> Result) throws -> Result {
        guard let control else { throw OwnershipError.invalidHandle }
        return try control.withCallbackFrame(HandleCell(control: control, identity: identity), matching: identity.kind, body)
    }
}
