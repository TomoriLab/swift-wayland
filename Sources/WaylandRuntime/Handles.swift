/// Identifies the native namespace of an owned runtime record.
///
/// Numeric identifiers are unique within a kind and session, not across all
/// libwayland allocation families. Protocol interface checks remain the
/// responsibility of future typed bindings.
package enum HandleKind: Hashable, Sendable {
    /// A client display connection that disconnects after its dependent proxies and queues.
    case clientDisplay
    /// A client proxy allocation owned by its adapter.
    case clientProxy
    /// A client event queue whose display dependency must remain valid.
    case eventQueue
    /// A server display with tracked dependents released first.
    case serverDisplay
    /// A server client governed by a separate native destruction contract.
    case serverClient
    /// A server protocol resource whose native lifetime can end externally.
    case serverResource
    /// A native event-loop source; one-shot semantics belong to its adapter.
    case eventSource
    /// Stable native-reachable registration or callback storage.
    case registration
    /// An exclusively owned file descriptor; the number is reserved until retirement.
    case fileDescriptor
    /// An explicitly owned SHM buffer reference, not a pixel borrow.
    case sharedMemoryBuffer
    /// An explicitly owned SHM pool reference.
    case sharedMemoryPool
    /// A cursor theme that owns its borrowed image and buffer views.
    case cursorTheme
    /// An EGL native window whose surface is a prerequisite.
    case nativeWindow
}

/// Carries copied identity information without granting native access.
///
/// Sessions and generations are monotonic and never wrap. Identity snapshots
/// may cross concurrency boundaries; a snapshot does not keep an object usable.
package struct HandleIdentity: Equatable, Sendable {
    /// A process-local, nonreused session identifier.
    package let session: UInt64
    /// The nonwrapping registration generation within the session.
    package let generation: UInt64
    /// Copied native identity metadata without pointer-access authority.
    package let nativeIdentifier: UInt64
    /// The allocation namespace used for identity and access validation.
    package let kind: HandleKind
}

/// Describes recoverable ownership-runtime failures.
package enum OwnershipError: Error, Equatable, Sendable {
    /// The root session no longer accepts new work.
    case closedSession
    /// The record is invalid, or a native notification lacks an enclosing frame.
    case invalidHandle
    /// A dependency or handle belongs to a different session.
    case foreignSession
    /// The requested native namespace differs from the handle namespace.
    case wrongKind
    /// A different OS thread currently holds the logical execution claim.
    case domainBusy
    /// The native key is still reserved, including pending capture retirement.
    case duplicateNativeIdentifier
    /// The configured retained-record limit is nonpositive.
    case invalidCapacity
    /// Retained native records have reached the configured limit.
    case capacityExceeded
    /// A monotonic session or generation counter cannot advance without wrapping.
    case identifierExhausted
    /// A native destruction notification has retained dependent records.
    case liveDependents
    /// A native mutex could not be initialized; the value is its native error code.
    case synchronizationUnavailable(Int32)
}

/// Describes whether requested cleanup is complete at the observation point.
package enum CloseProgress: Equatable, Sendable {
    /// The requested native records have been retired at this observation point.
    case complete
    /// An active native frame or foreign domain owner must complete cleanup later.
    case deferred
}

/// Reports native obligations independently of Swift handle reachability.
///
/// During a native destructor, an in-progress runtime release still counts as
/// an outstanding obligation. Native-consumed records can remain retained for
/// context quiescence even after their release obligation has been discharged.
package struct OwnershipSnapshot: Equatable, Sendable {
    /// The number of successfully published native obligations.
    package let acquisitions: UInt64
    /// The number of release actions that have returned completely.
    package let runtimeReleases: UInt64
    /// The number of obligations consumed by native destruction notifications.
    package let nativeReleases: UInt64
    /// The number of obligations explicitly transferred outside this runtime.
    package let transfers: UInt64
    /// Live, closing, or currently executing native release obligations.
    package let outstandingObligations: Int
    /// All retained records, including native-consumed or transferred captures awaiting quiescence.
    package let retainedRecords: Int
    /// The number of active nested synchronous native frames in this session.
    package let nativeFrames: Int
    /// Whether root shutdown has been applied to the serialized record graph.
    package let closing: Bool
}

final class HandleCell {
    let control: RuntimeControl
    let identity: HandleIdentity

    init(control: RuntimeControl, identity: HandleIdentity) {
        self.control = control
        self.identity = identity
    }
}

/// Provides a copyable checked reference without native destruction authority.
///
/// A reference retains bookkeeping only. Root closure, explicit owner closure,
/// native destruction, and dependency closure can invalidate it. It exposes no
/// native pointer. These values intentionally do not conform to Sendable.
package struct ObjectHandle {
    let cell: HandleCell

    /// Returns immutable identity metadata, even after invalidation.
    package var identity: HandleIdentity { cell.identity }

    /// Returns a conservative point-in-time validity result.
    ///
    /// A busy foreign execution domain returns false. Never use this result as
    /// an authorization for later native access; use withAccess instead.
    package var isValid: Bool { cell.control.isValid(cell) }

    /// Validates the reference and retains the execution domain and native frame.
    ///
    /// Reentrant close rejects subsequent access immediately but cannot release
    /// backing records until all enclosing frames return. The body is synchronous
    /// and may throw; every exit releases its frame. This operation does not expose
    /// native memory or authorize retaining a pointer captured by unsafe adoption.
    ///
    /// - Throws: An ownership error or an error thrown by the body.
    /// - Complexity: Expected O(1) validation, excluding pending cleanup work.
    package func withAccess<Result: ~Copyable>(
        matching kind: HandleKind? = nil,
        _ body: () throws -> Result
    ) throws -> Result {
        try cell.control.withAccess(cell, matching: kind, body)
    }

    /// Records a proven native destruction without calling the release action.
    ///
    /// The native adapter must hold an enclosing frame and report each native
    /// lifetime exactly once. No dependent records may remain, including records
    /// awaiting capture retirement. Native cascades need a dedicated future adapter.
    /// Retained
    /// cleanup captures are discarded only after frame quiescence.
    ///
    /// - Returns: False if the record was already retired.
    /// - Throws: A domain or dependency error.
    @unsafe package func nativeDestroyed() throws -> Bool {
        unsafe try cell.control.nativeDestroyed(cell)
    }
}

/// Holds unique authority to request closure of one cleanup record.
///
/// Explicit close and fallback destruction share the record's terminal arbiter.
/// Neither can execute native cleanup twice. Dependent records are closed first.
package struct OwnedHandle: ~Copyable {
    let cell: HandleCell

    /// Creates a checked reference without copying destruction authority.
    package var reference: ObjectHandle { borrowing get { ObjectHandle(cell: cell) } }

    /// Requests logical closure without consuming this owner, including from callbacks.
    @discardableResult
    package borrowing func requestClose() -> CloseProgress {
        cell.control.requestClose(generation: cell.identity.generation)
    }

    /// Consumes authority and requests cleanup, deferring physical release if needed.
    ///
    /// This operation never waits for a callback on the current native stack.
    /// Cleanup is synchronous when the domain is idle and has no active frames.
    @discardableResult
    package consuming func close() -> CloseProgress {
        cell.control.requestClose(generation: cell.identity.generation)
    }

    deinit {
        cell.control.requestClose(generation: cell.identity.generation)
    }
}

/// Owns the root authority of a serialized, non-thread-affine runtime session.
///
/// Dropping this value requests closure even when copied child references remain.
/// The initial runtime accepts only cleanup actions valid on any serialized caller
/// thread. Thread-affine resources, transport polling, and async shutdown are not
/// implemented by this layer.
package struct OwnershipSession: ~Copyable {
    let control: RuntimeControl

    /// Creates an empty session with a bounded number of retained records.
    ///
    /// - Throws: An ownership error for nonpositive capacity or exhausted identity.
    package init(maximumRecords: Int = 65_536) throws {
        control = try RuntimeControl(maximumRecords: maximumRecords)
    }

    /// Transfers one native release obligation into an authoritative cleanup record.
    ///
    /// All dependencies must be live records from this session. New records can
    /// depend only on already registered records, so dependency cycles cannot form.
    /// Closing any prerequisite closes its dependents before releasing it.
    ///
    /// The adapter must own the native resource exclusively, provide its correct
    /// namespace, and supply a nonthrowing cleanup valid on any serialized thread.
    /// The action must not retain this session or its cells, introduce ownership
    /// cycles, suspend, or free another tracked resource without notification.
    /// Captured values must not independently destroy this same native allocation
    /// when the action is discarded after a native destruction notification.
    /// Success transfers ownership. On failure no action is invoked and the caller
    /// retains the native obligation. Runtime OOM termination is not recoverable.
    ///
    /// - Throws: A domain, identity, capacity, or dependency error.
    /// - Complexity: Expected O(1) plus the number of supplied dependencies.
    @unsafe package borrowing func adopt(
        nativeIdentifier: UInt64,
        kind: HandleKind,
        dependencies: [ObjectHandle] = [],
        cleanup: @escaping () -> Void
    ) throws -> OwnedHandle {
        unsafe try control.adopt(nativeIdentifier: nativeIdentifier, kind: kind,
                          dependencies: dependencies, cleanup: cleanup)
    }

    /// Protects a complete synchronous native invocation, including callback return.
    ///
    /// Use this around dispatch and iteration, not only around the Swift callback.
    /// Nested frames are supported; typed client dispatch will enforce its own
    /// recursion policy. No bookkeeping mutex is held while the body runs.
    package borrowing func withNativeFrame<Result: ~Copyable>(_ body: () throws -> Result) throws -> Result {
        try control.withNativeFrame(body)
    }

    /// Returns a serialized snapshot, including after logical closure.
    package borrowing func snapshot() throws -> OwnershipSnapshot {
        try control.snapshot()
    }

    /// Requests root closure without consuming this owner during a synchronous callback.
    @discardableResult
    package borrowing func requestClose() -> CloseProgress { control.requestClose(generation: nil) }

    /// Consumes root authority and requests closure of all native obligations.
    ///
    /// Foreign-thread requests are posted without touching native storage. The
    /// active synchronous operation drains them before surrendering the domain.
    @discardableResult
    package consuming func close() -> CloseProgress { control.requestClose(generation: nil) }

    deinit { control.requestClose(generation: nil) }
}
