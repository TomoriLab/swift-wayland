import Glibc
import CWaylandClient
import WaylandRuntime

/// Describes coordination failures before a native client operation is attempted.
package enum ClientCoordinationError: Error, Equatable, Sendable {
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
    var prepared = false
    var dispatching = false
    init(_ pointer: OpaquePointer) { unsafe self.pointer = pointer }
}

private final class PreparedReadStorage {
    let display: DisplayStorage
    let lifetime: ObjectHandle
    var resolved = false
    init(display: DisplayStorage, lifetime: ObjectHandle) {
        self.display = display
        self.lifetime = lifetime
    }
    func cancel() {
        guard !resolved else { return }
        resolved = true
        unsafe wl_display_cancel_read(display.pointer)
        display.prepared = false
    }
    func read() throws {
        guard !resolved else { throw ClientCoordinationError.reservationResolved }
        guard lifetime.isValid else { cancel(); throw OwnershipError.closedSession }
        resolved = true
        // Native read consumes the reservation even when it returns an error.
        let result = unsafe wl_display_read_events(display.pointer)
        let error = errno
        display.prepared = false
        guard result >= 0 else { throw ClientError.nativeFailure(error) }
    }
    deinit { cancel() }
}

/// Provides a noncopyable synchronous read-or-cancel capability.
///
/// The connection's complete native frame encloses this token's scope. It cannot
/// be consumed out of the borrowing closure. Early exit, throw, and root shutdown
/// cancel unresolved reservations before disconnect. No await or foreign reader
/// is supported while prepared. Reading can block unless readiness was established.
package struct ClientReadReservation: ~Copyable {
    private let storage: PreparedReadStorage
    fileprivate init(_ storage: PreparedReadStorage) { self.storage = storage }
    /// Reports whether exactly one read or cancellation has resolved the reservation.
    package var isResolved: Bool { borrowing get { storage.resolved } }
    /// Consumes native read preparation, including on a native error.
    package borrowing func read() throws { try storage.read() }
    /// Cancels native read preparation idempotently.
    package borrowing func cancel() { storage.cancel() }
}

/// Owns a native event queue and its display lifetime dependency.
@safe package struct ClientEventQueue: ~Copyable {
    private let pointer: OpaquePointer
    private let owner: OwnedHandle
    fileprivate init(pointer: OpaquePointer, owner: consuming OwnedHandle) {
        unsafe self.pointer = pointer
        self.owner = owner
    }
    /// Provides checked queue identity without exposing its pointer.
    package var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Consumes queue authority; assigned tracked proxies are released first.
    @discardableResult
    package consuming func close() -> CloseProgress { owner.close() }
    fileprivate borrowing func withQueue<Result: ~Copyable>(_ body: (OpaquePointer) throws -> Result) throws -> Result {
        try owner.reference.withAccess(matching: .eventQueue) { unsafe try body(pointer) }
    }
}

/// Owns one serialized client display and its authoritative runtime session.
///
/// Native children depend on the display record. Explicit or fallback shutdown
/// destroys tracked children before disconnect. The initial facade is package
/// access and synchronous; it does not coordinate foreign Mesa/EGL readers.
package struct ClientConnection: ~Copyable {
    private let session: OwnershipSession
    private let storage: DisplayStorage
    private let owner: OwnedHandle

    /// Connects through the native default or named display lookup.
    ///
    /// The native environment and socket lookup policy are preserved. Null native
    /// results throw the saved errno. Failure to publish the runtime record rolls
    /// back the newly connected display. No production package dependency is added.
    package init(name: String? = nil) throws {
        let pointer: OpaquePointer?
        if let name {
            guard !name.utf8.contains(0) else { throw ClientError.nativeFailure(EINVAL) }
            unsafe pointer = name.withCString { unsafe wl_display_connect($0) }
        } else { unsafe pointer = wl_display_connect(nil) }
        guard let pointer = unsafe pointer else { throw ClientError.nativeFailure(errno) }
        unsafe try self.init(owning: pointer)
    }

    /// Connects to an exclusively owned connected socket, consuming it on every outcome.
    ///
    /// The caller must not retain another owner or independently use the socket.
    /// libwayland 1.26.0 consumes the descriptor on native connection failure too.
    @unsafe package init(receiving descriptor: Int32) throws {
        guard let pointer = unsafe wl_display_connect_to_fd(descriptor) else { throw ClientError.nativeFailure(errno) }
        unsafe try self.init(owning: pointer)
    }

    @unsafe private init(owning pointer: OpaquePointer) throws {
        var adopted = false
        defer { if !adopted { unsafe wl_display_disconnect(pointer) } }
        let session = try OwnershipSession()
        let owner = unsafe try session.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .clientDisplay) {
            unsafe wl_display_disconnect(pointer)
        }
        adopted = true
        self.session = session
        storage = unsafe DisplayStorage(pointer)
        self.owner = owner
    }

    /// Provides display identity for dependency and invalidation observations.
    package var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Returns the authoritative resource ledger for this connection.
    package borrowing func snapshot() throws -> OwnershipSnapshot { try session.snapshot() }
    /// Requests root shutdown; active native frames defer physical disconnect.
    @discardableResult
    package borrowing func requestClose() -> CloseProgress { session.requestClose() }

    /// Sends pending requests without blocking for peer readiness.
    ///
    /// EAGAIN remains native backpressure and is reported with its saved errno.
    package borrowing func flush() throws {
        try lifetime.withAccess(matching: .clientDisplay) {
            guard unsafe wl_display_flush(storage.pointer) >= 0 else { throw ClientError.nativeFailure(errno) }
        }
    }

    /// Dispatches only already queued default-queue events without reading the socket.
    @discardableResult
    package borrowing func dispatchPending() throws -> Int32 {
        try lifetime.withAccess(matching: .clientDisplay) {
            guard !storage.prepared else { throw ClientCoordinationError.readAlreadyPrepared }
            guard !storage.dispatching else { throw ClientCoordinationError.recursiveDispatch }
            storage.dispatching = true
            defer { storage.dispatching = false }
            let result = unsafe wl_display_dispatch_pending(storage.pointer)
            guard result >= 0 else { throw ClientError.nativeFailure(errno) }
            return result
        }
    }

    /// Resolves one successful prepare through read, explicit cancel, or fallback cancel.
    ///
    /// The synchronous closure runs under the complete native frame. It must not
    /// suspend or mix independent native readers. eventsPending requires dispatch
    /// before retry. A throwing closure cancels any unresolved preparation.
    package borrowing func withPreparedRead<Result: ~Copyable>(
        _ body: (borrowing ClientReadReservation) throws -> Result
    ) throws -> Result {
        unsafe try prepareRead(queue: nil, body)
    }

    /// Resolves one prepared read on a checked queue while retaining its native lifetime.
    package borrowing func withPreparedRead<Result: ~Copyable>(
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
            let result: Int32
            if let queue = unsafe queue { result = unsafe wl_display_prepare_read_queue(storage.pointer, queue) }
            else { result = unsafe wl_display_prepare_read(storage.pointer) }
            guard result == 0 else {
                let error = errno
                if error == EAGAIN { throw ClientCoordinationError.eventsPending }
                throw ClientError.nativeFailure(error)
            }
            storage.prepared = true
            let read = PreparedReadStorage(display: storage, lifetime: lifetime)
            defer { read.cancel() }
            let token = ClientReadReservation(read)
            return try body(token)
        }
    }

    /// Dispatches pending events or waits for one read with bounded cancellation cleanup.
    ///
    /// Cancellation wakes poll through an independently retained eventfd. Timeout,
    /// cancellation, and native wait failure cancel preparation. Read consumes it
    /// even on error. EINTR preserves the original monotonic deadline; flush EAGAIN
    /// requests writable readiness without abandoning the read transaction.
    @discardableResult
    package borrowing func dispatchOnce(
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
    package borrowing func sync<Context: AnyObject>(
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
    package borrowing func sync<Context: AnyObject>(
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
    package borrowing func dispatchPending(on queue: borrowing ClientEventQueue) throws -> Int32 {
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
    package borrowing func registry<Context: AnyObject>(
        context: Context, handler: @escaping (Context, ClientEvent) throws -> Void
    ) throws -> ClientProxyDispatcher<Context> {
        try lifetime.withAccess(matching: .clientDisplay) {
            guard let proxy = unsafe wl_display_get_registry(storage.pointer) else { throw ClientError.nativeFailure(errno) }
            return unsafe try ClientProxyDispatcher(receiving: proxy, in: session, dependencies: [lifetime],
                                                    context: context, handler: handler)
        }
    }

    /// Creates a queue that is destroyed before its display disconnects.
    package borrowing func createQueue() throws -> ClientEventQueue {
        try lifetime.withAccess(matching: .clientDisplay) {
            guard let pointer = unsafe wl_display_create_queue(storage.pointer) else { throw ClientError.nativeFailure(errno) }
            do {
                let owner = unsafe try session.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .eventQueue,
                                                    dependencies: [lifetime]) { unsafe wl_event_queue_destroy(pointer) }
                return unsafe ClientEventQueue(pointer: pointer, owner: owner)
            } catch { unsafe wl_event_queue_destroy(pointer); throw error }
        }
    }
}
