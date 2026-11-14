import Glibc
import CWaylandServer
import WaylandRuntime

/// Preserves native readiness bits, including unknown future flags.
public struct ServerEventMask: OptionSet, Hashable, Sendable {
    /// The exact native readiness mask.
    public let rawValue: UInt32
    /// Creates a mask without dropping unknown native bits.
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    /// Indicates descriptor readability.
    public static let readable = Self(rawValue: 1)
    /// Indicates descriptor writability.
    public static let writable = Self(rawValue: 2)
    /// Indicates the peer closed its endpoint.
    public static let hangup = Self(rawValue: 4)
    /// Indicates a native descriptor error.
    public static let error = Self(rawValue: 8)
    /// Hashes the exact native bits.
    public var hashValue: Int { rawValue.hashValue }
    /// Combines the native bits into the caller hasher.
    public func hash(into hasher: inout Hasher) { rawValue.hash(into: &hasher) }
}
/// Preserves the native callback contract for sources registered for explicit checks.
public enum ServerSourceAction: Int32, Sendable {
    /// Ends the current recheck iteration.
    case done = 0
    /// Requests another check when the source participates in native checking.
    case recheck = 1
    /// Creates an action only for the two defined native callback return values.
    public init?(rawValue: Int32) {
        switch rawValue { case 0: self = .done; case 1: self = .recheck; default: return nil }
    }
    /// Hashes the exact native callback return value.
    public var hashValue: Int { rawValue.hashValue }
    /// Combines the native callback return value into the caller hasher.
    public func hash(into hasher: inout Hasher) { rawValue.hash(into: &hasher) }
}
/// Distinguishes valid native source operations at compile time.
public protocol ServerSourceKind {}
/// Identifies descriptor readiness sources.
public enum ServerDescriptorSourceKind: ServerSourceKind {}
/// Identifies millisecond timer sources.
public enum ServerTimerSourceKind: ServerSourceKind {}
/// Identifies explicitly unsafe native signal sources.
public enum ServerSignalSourceKind: ServerSourceKind {}

private enum PersistentSourceEvent { case descriptor(ServerEventMask), timer, signal(Int32) }
@safe private final class PersistentSourceState {
    var pointer: OpaquePointer?
    var observer: NativeDestructionObserver?
    var failure: (any Error)?
    var checked = false
    let handler: (PersistentSourceEvent) throws -> ServerSourceAction
    init(_ handler: @escaping (PersistentSourceEvent) throws -> ServerSourceAction) { self.handler = handler }
    func invoke(_ event: PersistentSourceEvent) -> Int32 {
        guard let observer else { return 0 }
        do { return try observer.withCallback { try handler(event).rawValue } }
        catch { failure = error; return 0 }
    }
}
@unsafe private func invokeDescriptor(_ descriptor: Int32, _ mask: UInt32, _ pointer: UnsafeMutableRawPointer?) -> Int32 {
    guard let pointer = unsafe pointer else { return 0 }
    let context = unsafe Unmanaged<PersistentSourceState>.fromOpaque(pointer).takeUnretainedValue()
    return context.invoke(.descriptor(ServerEventMask(rawValue: mask)))
}
@unsafe private func invokeTimer(_ pointer: UnsafeMutableRawPointer?) -> Int32 {
    guard let pointer = unsafe pointer else { return 0 }
    return unsafe Unmanaged<PersistentSourceState>.fromOpaque(pointer).takeUnretainedValue().invoke(.timer)
}
@unsafe private func invokeSignal(_ number: Int32, _ pointer: UnsafeMutableRawPointer?) -> Int32 {
    guard let pointer = unsafe pointer else { return 0 }
    return unsafe Unmanaged<PersistentSourceState>.fromOpaque(pointer).takeUnretainedValue().invoke(.signal(number))
}
private struct PersistentSourceOwner: ~Copyable {
    let state: PersistentSourceState
    let owner: OwnedHandle
}

private final class SourceDescriptorOwner {
    let owner: OwnedFileDescriptor
    init(_ owner: consuming OwnedFileDescriptor) { self.owner = owner }
}

/// Owns a typed persistent event source with one deferred native removal obligation.
public struct ServerEventSource<Kind: ServerSourceKind>: ~Copyable {
    private let source: PersistentSourceOwner
    private let descriptor: SourceDescriptorOwner?
    fileprivate init(source: consuming PersistentSourceOwner, descriptor: SourceDescriptorOwner? = nil) {
        self.source = source; self.descriptor = descriptor
    }
    /// Produces a checked reference whose operations are restricted to its source kind.
    public var reference: ServerEventSourceReference<Kind> {
        borrowing get { ServerEventSourceReference(state: source.state, lifetime: source.owner.reference, descriptor: descriptor?.owner.borrowed) }
    }
    /// Provides source identity without a native pointer.
    public var lifetime: ObjectHandle { borrowing get { source.owner.reference } }
    /// Returns the saved callback exception without unwinding through native code.
    public var failure: (any Error)? { borrowing get { source.state.failure } }
    /// Requests logical closure while preserving userdata through complete dispatch-frame exit.
    @discardableResult public borrowing func requestClose() -> CloseProgress {
        let progress = source.owner.requestClose()
        _ = descriptor?.owner.requestClose()
        return progress
    }
    /// Consumes authority and removes the source before its owned descriptor is closed.
    @discardableResult public consuming func close() -> CloseProgress { requestClose() }
}
/// Provides descriptor readiness without permitting timer-specific operations.
public typealias ServerFDSource = ServerEventSource<ServerDescriptorSourceKind>
/// Provides timer expiry without permitting descriptor-specific operations.
public typealias ServerTimerSource = ServerEventSource<ServerTimerSourceKind>
/// Owns native signal readiness under the caller's explicit signal-policy contract.
public typealias ServerSignalSource = ServerEventSource<ServerSignalSourceKind>

/// Provides checked persistent-source operations without removal authority.
public struct ServerEventSourceReference<Kind: ServerSourceKind> {
    private let state: PersistentSourceState
    /// Provides checked source identity for dependency and invalidation observations.
    public let lifetime: ObjectHandle
    private let descriptor: BorrowedFileDescriptor?
    fileprivate init(state: PersistentSourceState, lifetime: ObjectHandle, descriptor: BorrowedFileDescriptor?) {
        self.state = state; self.lifetime = lifetime; self.descriptor = descriptor
    }
    /// Registers this source for native post-dispatch checking.
    ///
    /// A handler returning recheck indefinitely can prevent dispatch from finishing.
    public func check() throws {
        try lifetime.withAccess(matching: .eventSource) {
            guard let pointer = unsafe state.pointer else { throw OwnershipError.invalidHandle }
            if !state.checked { state.checked = true; unsafe wl_event_source_check(pointer) }
        }
    }
}
extension ServerEventSourceReference where Kind == ServerDescriptorSourceKind {
    /// Changes the descriptor readiness interest while the source is live.
    public func update(mask: ServerEventMask) throws {
        try lifetime.withAccess(matching: .eventSource) {
            guard let pointer = unsafe state.pointer else { throw OwnershipError.invalidHandle }
            guard unsafe wl_event_source_fd_update(pointer, mask.rawValue) == 0 else { throw ServerError.nativeFailure(errno) }
        }
    }
    /// Borrows the source-owned duplicate while retaining both source and FD leases.
    ///
    /// The caller must not store, close, transfer, or concurrently use this raw number.
    @unsafe public func withUnsafeDescriptor<Result: ~Copyable>(_ body: (Int32) throws -> Result) throws -> Result {
        try lifetime.withAccess(matching: .eventSource) {
            guard let descriptor else { throw OwnershipError.invalidHandle }
            return unsafe try descriptor.withUnsafeDescriptor(body)
        }
    }
}
extension ServerEventSourceReference where Kind == ServerTimerSourceKind {
    /// Arms a millisecond timer; zero disarms it and negative values are rejected.
    public func update(delayMilliseconds: Int32) throws {
        guard delayMilliseconds >= 0 else { throw ServerError.nativeFailure(EINVAL) }
        try lifetime.withAccess(matching: .eventSource) {
            guard let pointer = unsafe state.pointer else { throw OwnershipError.invalidHandle }
            guard unsafe wl_event_source_timer_update(pointer, delayMilliseconds) == 0 else { throw ServerError.nativeFailure(errno) }
        }
    }
}

extension ServerDisplay {
    @unsafe private borrowing func persistentSource(
        dependencies: [ObjectHandle] = [], handler: @escaping (PersistentSourceEvent) throws -> ServerSourceAction,
        install: (OpaquePointer, UnsafeMutableRawPointer) -> OpaquePointer?
    ) throws -> PersistentSourceOwner {
        unsafe try withNativeLoop { session, loop in
            let state = PersistentSourceState(handler)
            guard let pointer = unsafe install(loop, Unmanaged.passUnretained(state).toOpaque()) else {
                throw ServerError.nativeFailure(errno)
            }
            unsafe state.pointer = pointer
            var adopted = false
            defer { if !adopted { _ = unsafe wl_event_source_remove(pointer) } }
            let owner = unsafe try session.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .eventSource,
                                                dependencies: [lifetime] + dependencies) {
                withExtendedLifetime(state) { _ = unsafe wl_event_source_remove(pointer); unsafe state.pointer = nil }
            }
            adopted = true
            state.observer = owner.reference.destructionObserver()
            return PersistentSourceOwner(state: state, owner: owner)
        }
    }
    /// Registers readiness using a display-owned duplicate; the caller retains the original FD.
    public borrowing func addFD(
        _ descriptor: BorrowedFileDescriptor, mask: ServerEventMask,
        handler: @escaping (ServerEventMask) throws -> ServerSourceAction
    ) throws -> ServerFDSource {
        let duplicate = try descriptor.duplicate(in: lifetime)
        let source = unsafe try duplicate.borrowed.withUnsafeDescriptor { raw in
            unsafe try persistentSource(dependencies: [duplicate.lifetime], handler: { event in
                guard case .descriptor(let mask) = event else { return .done }; return try handler(mask)
            }, install: { loop, context in unsafe wl_event_loop_add_fd(loop, raw, mask.rawValue, invokeDescriptor, context) })
        }
        return ServerEventSource(source: source, descriptor: SourceDescriptorOwner(duplicate))
    }
    /// Creates a disarmed timer whose handler preserves the native recheck return contract.
    public borrowing func addTimer(_ handler: @escaping () throws -> ServerSourceAction) throws -> ServerTimerSource {
        let source = unsafe try persistentSource(handler: { _ in try handler() }, install: { loop, context in
            unsafe wl_event_loop_add_timer(loop, invokeTimer, context)
        })
        return ServerEventSource(source: source)
    }
    /// Registers a signal source under caller-owned thread/process mask policy.
    ///
    /// Native registration blocks the signal on the current thread and removal
    /// does not restore that mask. The caller must coordinate all threads and
    /// foreign signal users. Delivery occurs only inside ordinary loop dispatch.
    @unsafe public borrowing func addSignal(
        _ number: Int32, handler: @escaping (Int32) throws -> ServerSourceAction
    ) throws -> ServerSignalSource {
        let source = unsafe try persistentSource(handler: { event in
            guard case .signal(let number) = event else { return .done }; return try handler(number)
        }, install: { loop, context in unsafe wl_event_loop_add_signal(loop, number, invokeSignal, context) })
        return ServerEventSource(source: source)
    }
}
