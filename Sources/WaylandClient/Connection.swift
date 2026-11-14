import Glibc
import CWaylandClient
import WaylandRuntime
import WaylandProtocol

/// Describes coordination failures before a native client operation is attempted.
public enum ClientCoordinationError: Error, Equatable, Sendable {
    /// Pending events must be dispatched before preparing a read.
    case eventsPending
    /// This connection already holds a prepared-read reservation.
    case readAlreadyPrepared
    /// The read reservation has already been read or canceled.
    case reservationResolved
    /// Recursive dispatch or read preparation from a callback is prohibited.
    case recursiveDispatch
}

// Native pointers remain private and are used only under checked display access.
@safe private final class DisplayStorage {
    let pointer: OpaquePointer
    let metadata: ClientProtocolMetadata
    var prepared = false
    var preparedGeneration: UInt64 = 0
    var dispatching = false
    var protocolRegistry: TypedClientRegistry?
    let queueState: ClientQueueState
    init(_ pointer: OpaquePointer, metadata: ClientProtocolMetadata, lifetime: ObjectHandle) {
        unsafe self.pointer = pointer; self.metadata = metadata
        queueState = unsafe ClientQueueState(pointer, metadata: metadata, lifetime: lifetime)
    }
}

/// Provides a noncopyable synchronous read-or-cancel capability without per-read heap allocation.
///
/// The connection's complete native frame encloses this borrowed token. A
/// nonwrapping display-local generation prevents a resolved outer token from
/// consuming a newer nested reservation. Early exit and throw cancel exactly
/// the originating preparation. Read may block without established readiness.
public struct ClientReadReservation: ~Copyable {
    private let display: DisplayStorage
    private let lifetime: ObjectHandle
    private let generation: UInt64
    fileprivate init(display: DisplayStorage, lifetime: ObjectHandle) {
        self.display = display; self.lifetime = lifetime; generation = display.preparedGeneration
    }
    /// Reports whether this generation has read, canceled, or been superseded.
    public var isResolved: Bool { borrowing get { !display.prepared || generation != display.preparedGeneration } }
    /// Consumes exactly this native read preparation, including on a native error.
    public borrowing func read() throws {
        guard !isResolved else { throw ClientCoordinationError.reservationResolved }
        guard lifetime.isValidInCurrentNativeFrame else { cancel(); throw OwnershipError.closedSession }
        display.prepared = false
        let result = unsafe wl_display_read_events(display.pointer)
        let error = errno
        guard result >= 0 else { throw ClientError.nativeFailure(error) }
    }
    /// Cancels only this generation, without affecting a newer nested reservation.
    public borrowing func cancel() {
        guard !isResolved else { return }
        display.prepared = false
        unsafe wl_display_cancel_read(display.pointer)
    }
    deinit { cancel() }
}

/// Owns a native event queue and its display lifetime dependency.
@safe public struct ClientEventQueue: ~Copyable {
    private let pointer: OpaquePointer
    private let owner: OwnedHandle
    fileprivate init(pointer: OpaquePointer, owner: consuming OwnedHandle) {
        unsafe self.pointer = pointer
        self.owner = owner
    }
    /// Provides checked queue identity without exposing its pointer.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Consumes queue authority; assigned tracked proxies are released first.
    @discardableResult
    public consuming func close() -> CloseProgress { owner.close() }
    fileprivate borrowing func withQueue<Result: ~Copyable>(_ body: (OpaquePointer) throws -> Result) throws -> Result {
        try owner.reference.withAccess(matching: .eventQueue) { unsafe try body(pointer) }
    }
}

/// Owns one serialized client display and its authoritative runtime session.
///
/// Native children depend on the display record. Explicit or fallback shutdown
/// destroys tracked children before disconnect. The initial facade is public
/// access and synchronous; it does not coordinate foreign Mesa/EGL readers.
public struct ClientConnection: ~Copyable {
    private let session: OwnershipSession
    private let storage: DisplayStorage
    private let owner: OwnedHandle

    /// Connects through the native default or named display lookup.
    ///
    /// The native environment and socket lookup policy are preserved. Null native
    /// results throw the saved errno. Failure to publish the runtime record rolls
    /// back the newly connected display. No production public dependency is added.
    public init(name: String? = nil, maximumRecords: Int = 65_536, maximumProtocolMetadataBytes: Int = 16 * 1024 * 1024) throws {
        let pointer: OpaquePointer?
        if let name {
            guard !name.utf8.contains(0) else { throw ClientError.nativeFailure(EINVAL) }
            unsafe pointer = name.withCString { unsafe wl_display_connect($0) }
        } else { unsafe pointer = wl_display_connect(nil) }
        guard let pointer = unsafe pointer else { throw ClientError.nativeFailure(errno) }
        unsafe try self.init(owning: pointer, maximumRecords: maximumRecords, maximumProtocolMetadataBytes: maximumProtocolMetadataBytes)
    }

    /// Connects to an exclusively owned connected socket, consuming it on every outcome.
    ///
    /// The caller must not retain another owner or independently use the socket.
    /// libwayland 1.26.0 consumes the descriptor on native connection failure too.
    @unsafe public init(receiving descriptor: Int32, maximumRecords: Int = 65_536, maximumProtocolMetadataBytes: Int = 16 * 1024 * 1024) throws {
        guard let pointer = unsafe wl_display_connect_to_fd(descriptor) else { throw ClientError.nativeFailure(errno) }
        unsafe try self.init(owning: pointer, maximumRecords: maximumRecords, maximumProtocolMetadataBytes: maximumProtocolMetadataBytes)
    }

    @unsafe private init(owning pointer: OpaquePointer, maximumRecords: Int, maximumProtocolMetadataBytes: Int) throws {
        var adopted = false
        defer { if !adopted { unsafe wl_display_disconnect(pointer) } }
        let metadata = try ClientProtocolMetadata(maximumBytes: maximumProtocolMetadataBytes)
        let session = try OwnershipSession(maximumRecords: maximumRecords)
        let owner = unsafe try session.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .clientDisplay) {
            unsafe wl_display_disconnect(pointer)
            metadata.retire()
        }
        adopted = true
        self.session = session
        storage = unsafe DisplayStorage(pointer, metadata: metadata, lifetime: owner.reference)
        self.owner = owner
    }

    /// Provides display identity for dependency and invalidation observations.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Returns the typed display request reference while preserving libwayland's reserved listener.
    public borrowing func protocolDisplay() throws -> ClientObjectReference<WlDisplay> {
        try lifetime.withAccess(matching: .clientDisplay) {
            let registry: TypedClientRegistry
            if let existing = storage.protocolRegistry { registry = existing }
            else {
                registry = unsafe TypedClientRegistry(display: storage.pointer, lifetime: lifetime, metadata: storage.metadata, queueState: storage.queueState)
                storage.protocolRegistry = registry
            }
            let key = unsafe UInt(bitPattern: storage.pointer)
            if let endpoint = registry.objects[key]?.value { return ClientObjectReference(endpoint) }
            let endpoint = unsafe TypedClientEndpoint(pointer: storage.pointer, lifetime: lifetime,
                registry: registry, schema: WlDisplay.schema, version: 1)
            registry.objects[key] = WeakClientEndpoint(endpoint)
            return ClientObjectReference(endpoint)
        }
    }

    /// Returns the authoritative resource ledger for this connection.
    public borrowing func snapshot() throws -> OwnershipSnapshot { try session.snapshot() }
    /// Returns synchronized native metadata retention counters, including after shutdown.
    ///
    /// Queued C closures may retain metadata after the last proxy is locally
    /// destroyed. These arenas retire after native display disconnect, not after
    /// subscription cancellation. The quota covers native arena bytes separately
    /// from caller-owned immutable Swift schema values and allocator overhead.
    public borrowing func protocolMetadataSnapshot() -> ClientProtocolMetadataSnapshot { storage.metadata.snapshot() }
    /// Requests root shutdown; active native frames defer physical disconnect.
    @discardableResult
    public borrowing func requestClose() -> CloseProgress { session.requestClose() }

    /// Sends pending requests without blocking for peer readiness.
    ///
    /// EAGAIN remains native backpressure and is reported with its saved errno.
    public borrowing func flush() throws {
        try lifetime.withAccess(matching: .clientDisplay) {
            guard unsafe wl_display_flush(storage.pointer) >= 0 else { throw ClientError.nativeFailure(errno) }
        }
    }

    /// Dispatches only already queued default-queue events without reading the socket.
    @discardableResult
    public borrowing func dispatchPending() throws -> Int32 {
        try lifetime.withAccess(matching: .clientDisplay) {
            try dispatchPendingInFrame()
        }
    }

    /// Reads and dispatches default-queue events under one checked native frame.
    ///
    /// The call may block in native read until the connection is readable. Pending
    /// events or another prepared read require the caller to resolve that state
    /// first. A close posted before dispatch rejects delivery after read; the
    /// enclosing frame defers physical disconnect until the call returns.
    @discardableResult
    public borrowing func readAndDispatchPending() throws -> Int32 {
        unsafe try prepareRead(queue: nil) { reservation in
            try reservation.read()
            guard lifetime.isValidInCurrentNativeFrame else { throw OwnershipError.closedSession }
            return try dispatchPendingInFrame()
        }
    }

    private borrowing func dispatchPendingInFrame() throws -> Int32 {
        guard !storage.prepared else { throw ClientCoordinationError.readAlreadyPrepared }
        guard !storage.dispatching else { throw ClientCoordinationError.recursiveDispatch }
        storage.dispatching = true
        defer { storage.dispatching = false }
        let result = unsafe wl_display_dispatch_pending(storage.pointer)
        guard result >= 0 else { throw ClientError.nativeFailure(errno) }
        return result
    }

    /// Resolves one successful prepare through read, explicit cancel, or fallback cancel.
    ///
    /// The synchronous closure runs under the complete native frame. It must not
    /// suspend or mix independent native readers. eventsPending requires dispatch
    /// before retry. A throwing closure cancels any unresolved preparation.
    public borrowing func withPreparedRead<Result: ~Copyable>(
        _ body: (borrowing ClientReadReservation) throws -> Result
    ) throws -> Result {
        unsafe try prepareRead(queue: nil, body)
    }

    /// Resolves one prepared read on a checked queue while retaining its native lifetime.
    public borrowing func withPreparedRead<Result: ~Copyable>(
        on queue: borrowing ClientEventQueue, _ body: (borrowing ClientReadReservation) throws -> Result
    ) throws -> Result {
        guard queue.lifetime.identity.session == lifetime.identity.session else { throw OwnershipError.foreignSession }
        return unsafe try queue.withQueue { pointer in unsafe try prepareRead(queue: pointer, body) }
    }

    @unsafe private borrowing func prepareRead<Result: ~Copyable>(
        queue: OpaquePointer?, _ body: (borrowing ClientReadReservation) throws -> Result
    ) throws -> Result {
        try lifetime.withAccess(matching: .clientDisplay) {
            guard !storage.prepared else { throw ClientCoordinationError.readAlreadyPrepared }
            guard !storage.dispatching else { throw ClientCoordinationError.recursiveDispatch }
            guard storage.preparedGeneration < UInt64.max else { throw OwnershipError.identifierExhausted }
            unsafe try requireOtherQueuesDrained(excluding: queue)
            let result: Int32
            if let queue = unsafe queue { result = unsafe wl_display_prepare_read_queue(storage.pointer, queue) }
            else { result = unsafe wl_display_prepare_read(storage.pointer) }
            guard result == 0 else {
                let error = errno
                if error == EAGAIN { throw ClientCoordinationError.eventsPending }
                throw ClientError.nativeFailure(error)
            }
            storage.prepared = true
            storage.preparedGeneration += 1
            let token = ClientReadReservation(display: storage, lifetime: lifetime)
            defer { token.cancel() }
            return try body(token)
        }
    }

    @unsafe private borrowing func requireOtherQueuesDrained(excluding selected: OpaquePointer?) throws {
        if storage.queueState.queues.isEmpty { return }
        func probe(_ queue: OpaquePointer?) throws {
            let result: Int32
            if let queue = unsafe queue { result = unsafe wl_display_prepare_read_queue(storage.pointer, queue) }
            else { result = unsafe wl_display_prepare_read(storage.pointer) }
            guard result == 0 else {
                if errno == EAGAIN { throw ClientCoordinationError.eventsPending }
                throw ClientError.nativeFailure(errno)
            }
            unsafe wl_display_cancel_read(storage.pointer)
        }
        if unsafe selected != nil { try probe(nil) }
        for entry in storage.queueState.queues.values where unsafe entry.pointer != selected {
            do { try entry.observer.withCallback { unsafe try probe(entry.pointer) } }
            catch OwnershipError.invalidHandle { continue }
        }
    }

    /// Dispatches pending events or waits for one read with bounded cancellation cleanup.
    ///
    /// Cancellation wakes poll through an independently retained eventfd. Timeout,
    /// cancellation, and native wait failure cancel preparation. Read consumes it
    /// even on error. EINTR preserves the original monotonic deadline; flush EAGAIN
    /// requests writable readiness without abandoning the read transaction.
    @discardableResult
    public borrowing func dispatchOnce(
        timeoutMilliseconds: Int32, cancellation: ReadCancellation
    ) throws -> Int32 {
        guard !cancellation.isCancelled else { throw CancellationError() }
        let pending = try dispatchPending()
        if pending > 0 { return pending }
        let readable = try withPreparedRead { read in
            let result = unsafe try cancellation.withUnsafeWakeDescriptor { wake in
                var error: Int32 = 0
                let result = unsafe wayland_kit_wait_readable(storage.pointer, wake, timeoutMilliseconds, &error)
                guard result >= 0 else { throw ClientError.nativeFailure(error) }
                return result
            }
            if result == 2 || cancellation.isCancelled { read.cancel(); throw CancellationError() }
            if result == 0 { read.cancel(); return false }
            try read.read()
            return true
        }
        return readable ? try dispatchPending() : 0
    }

    /// Creates a default-queue sync proxy with one permanent observation dispatcher.
    public borrowing func sync<Context: AnyObject>(
        context: Context, handler: @escaping (Context, ClientEvent) throws -> Void
    ) throws -> ClientProxyDispatcher<Context> {
        try lifetime.withAccess(matching: .clientDisplay) {
            guard let proxy = unsafe wl_display_sync(storage.pointer) else { throw ClientError.nativeFailure(errno) }
            return unsafe try ClientProxyDispatcher(receiving: proxy, in: session, dependencies: [lifetime],
                                                    context: context, handler: handler)
        }
    }

    /// Constructs a queue-assigned sync proxy through a temporary native wrapper.
    ///
    /// The shared display proxy's queue is never temporarily changed. Both queue
    /// and display remain dependencies of the constructed proxy.
    public borrowing func sync<Context: AnyObject>(
        on queue: borrowing ClientEventQueue, context: Context,
        handler: @escaping (Context, ClientEvent) throws -> Void
    ) throws -> ClientProxyDispatcher<Context> {
        guard queue.lifetime.identity.session == lifetime.identity.session else { throw OwnershipError.foreignSession }
        return unsafe try queue.withQueue { pointer in
            try lifetime.withAccess(matching: .clientDisplay) {
                guard let proxy = unsafe wayland_kit_sync_on_queue(storage.pointer, pointer) else {
                    throw ClientError.nativeFailure(errno)
                }
                return unsafe try ClientProxyDispatcher(receiving: proxy, in: session,
                    dependencies: [lifetime, queue.lifetime], context: context, handler: handler)
            }
        }
    }

    /// Dispatches only pending events on a checked queue without reading transport.
    @discardableResult
    public borrowing func dispatchPending(on queue: borrowing ClientEventQueue) throws -> Int32 {
        guard queue.lifetime.identity.session == lifetime.identity.session else { throw OwnershipError.foreignSession }
        return unsafe try queue.withQueue { pointer in
            try lifetime.withAccess(matching: .clientDisplay) {
                guard !storage.prepared else { throw ClientCoordinationError.readAlreadyPrepared }
                guard !storage.dispatching else { throw ClientCoordinationError.recursiveDispatch }
                storage.dispatching = true
                defer { storage.dispatching = false }
                let result = unsafe wl_display_dispatch_queue_pending(storage.pointer, pointer)
                guard result >= 0 else { throw ClientError.nativeFailure(errno) }
                return result
            }
        }
    }

    /// Creates a registry proxy with copied global announcements and checked lifetime.
    public borrowing func registry<Context: AnyObject>(
        context: Context, handler: @escaping (Context, ClientEvent) throws -> Void
    ) throws -> ClientProxyDispatcher<Context> {
        try lifetime.withAccess(matching: .clientDisplay) {
            guard let proxy = unsafe wl_display_get_registry(storage.pointer) else { throw ClientError.nativeFailure(errno) }
            return unsafe try ClientProxyDispatcher(receiving: proxy, in: session, dependencies: [lifetime],
                                                    context: context, handler: handler)
        }
    }

    /// Creates a queue that is destroyed before its display disconnects.
    public borrowing func createQueue() throws -> ClientEventQueue {
        try lifetime.withAccess(matching: .clientDisplay) {
            guard let pointer = unsafe wl_display_create_queue(storage.pointer) else { throw ClientError.nativeFailure(errno) }
            do {
                let key = UInt(bitPattern: pointer)
                let display = storage
                let owner = unsafe try session.adopt(nativeIdentifier: UInt64(key), kind: .eventQueue,
                                                    dependencies: [lifetime]) {
                    unsafe wl_event_queue_destroy(pointer)
                    display.queueState.queues.removeValue(forKey: key)
                }
                storage.queueState.queues[key] = unsafe QueueReadiness(pointer: pointer, lifetime: owner.reference)
                return unsafe ClientEventQueue(pointer: pointer, owner: owner)
            } catch { unsafe wl_event_queue_destroy(pointer); throw error }
        }
    }
}

/// Copies a native protocol error without retaining interface or object pointers.
public struct ClientProtocolErrorSnapshot: Equatable, Sendable {
    /// The interface name copied from process-lifetime native metadata, when provided.
    public let interfaceName: String?
    /// The protocol object ID that triggered the error; it grants no access authority.
    public let objectIdentifier: UInt32
    /// The exact interface-specific native error code, including unknown future values.
    public let code: UInt32
}

extension ClientConnection {
    /// Copies the stored protocol error while the display remains owned and accessible.
    ///
    /// A transport error has no protocol snapshot. The returned value remains
    /// valid after shutdown. Native errors are sticky and are not cleared here.
    public borrowing func protocolError() throws -> ClientProtocolErrorSnapshot? {
        try lifetime.withAccess(matching: .clientDisplay) {
            guard unsafe wl_display_get_error(storage.pointer) == EPROTO else { return nil }
            var interface: UnsafePointer<wl_interface>?
            var identifier: UInt32 = 0
            let code = unsafe wl_display_get_protocol_error(storage.pointer, &interface, &identifier)
            let name: String?
            if let interface = unsafe interface { name = unsafe String(cString: interface.pointee.name) }
            else { name = nil }
            return ClientProtocolErrorSnapshot(interfaceName: name, objectIdentifier: identifier, code: code)
        }
    }
}
