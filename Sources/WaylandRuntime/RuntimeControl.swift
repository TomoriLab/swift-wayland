import Glibc
import CWaylandRuntime

private struct NativeKey: Hashable {
    let kind: HandleKind
    let identifier: UInt64
}

private enum RecordState {
    case live
    case closing
    case runtimeReleasing
    case nativeConsumed
    case transferred
}

private final class CleanupRecord {
    let identity: HandleIdentity
    let dependencies: Set<UInt64>
    var dependents: Set<UInt64> = []
    var state: RecordState = .live
    var cleanup: (() -> Void)?

    init(identity: HandleIdentity, dependencies: Set<UInt64>, cleanup: @escaping () -> Void) {
        self.identity = identity
        self.dependencies = dependencies
        self.cleanup = cleanup
    }
}

private struct AdmissionState: Sendable {
    var thread: pthread_t?
    var entries = 0
    var shutdownRequested = false
    var pendingShutdown = false
    var pendingRecords: Set<UInt64> = []
}

/// Serializes mutable records through a logical claim, not a mutex held over C.
///
/// Only AdmissionState is accessed by foreign callers. All record state is
/// accessed by the admitted thread, including reentrant callbacks on that thread.
/// This class deliberately has no Sendable conformance.
final class RuntimeControl {
    private let admission: RuntimeMutex<AdmissionState>
    private let session: UInt64
    private let maximumRecords: Int
    private var records: [UInt64: CleanupRecord] = [:]
    private var nativeIndex: [NativeKey: UInt64] = [:]
    private var nextGeneration: UInt64
    private var ready: [UInt64] = []
    private var queued: Set<UInt64> = []
    private var nativeFrames = 0
    private var draining = false
    private var closing = false
    private var acquisitions: UInt64 = 0
    private var runtimeReleases: UInt64 = 0
    private var nativeReleases: UInt64 = 0
    private var transfers: UInt64 = 0

    init(maximumRecords: Int, initialGeneration: UInt64 = 0) throws {
        guard maximumRecords > 0 else { throw OwnershipError.invalidCapacity }
        let identity = wayland_runtime_next_session()
        guard identity != 0 else { throw OwnershipError.identifierExhausted }
        admission = try RuntimeMutex(AdmissionState())
        session = identity
        self.maximumRecords = maximumRecords
        nextGeneration = initialGeneration
    }

    private func enter() throws {
        let current = pthread_self()
        let admitted = admission.withLock { state in
            if let thread = state.thread, thread != current { return false }
            state.thread = current
            state.entries += 1
            return true
        }
        guard admitted else { throw OwnershipError.domainBusy }
    }

    private func withDomain<Result: ~Copyable>(_ body: () throws -> Result) throws -> Result {
        try enter()
        defer { leave() }
        synchronize()
        drainReady()
        return try body()
    }

    private func leave() {
        while true {
            synchronize()
            drainReady()
            let finished = admission.withLock { state in
                precondition(state.thread == pthread_self() && state.entries > 0)
                if state.entries > 1 {
                    state.entries -= 1
                    return true
                }
                // A close posted after draining must be observed before ownership is released.
                guard !state.pendingShutdown && state.pendingRecords.isEmpty else { return false }
                state.entries = 0
                state.thread = nil
                return true
            }
            if finished { return }
        }
    }

    /// Applies only value-state transitions while holding the bookkeeping mutex.
    /// No action or captured object's final release occurs in this critical section.
    private func applyPending(_ state: inout AdmissionState) {
        if state.pendingShutdown {
            state.pendingShutdown = false
            closing = true
            for record in records.values where record.state == .live {
                record.state = .closing
                enqueue(record)
            }
        }
        for generation in state.pendingRecords { markClosing(generation) }
        state.pendingRecords.removeAll(keepingCapacity: true)
    }

    private func synchronize() {
        admission.withLock { state in applyPending(&state) }
    }

    private func enqueue(_ record: CleanupRecord) {
        if record.dependents.isEmpty && queued.insert(record.identity.generation).inserted {
            ready.append(record.identity.generation)
        }
    }

    private func markClosing(_ generation: UInt64) {
        var pending = [generation]
        while let current = pending.popLast() {
            guard let record = records[current], record.state == .live else { continue }
            record.state = .closing
            pending.append(contentsOf: record.dependents)
            enqueue(record)
        }
    }

    private func validate(_ cell: HandleCell, matching kind: HandleKind? = nil) throws {
        guard cell.control === self else { throw OwnershipError.foreignSession }
        let failure: OwnershipError? = admission.withLock { state in
            // Transition application and access admission form one linearization boundary.
            applyPending(&state)
            if state.shutdownRequested || closing { return .closedSession }
            guard let record = records[cell.identity.generation],
                  record.identity == cell.identity, record.state == .live else { return .invalidHandle }
            if let kind, record.identity.kind != kind { return .wrongKind }
            return nil
        }
        if let failure { throw failure }
    }

    @unsafe func adopt(
        nativeIdentifier: UInt64,
        kind: HandleKind,
        dependencies: [ObjectHandle],
        cleanup: @escaping () -> Void
    ) throws -> OwnedHandle {
        try withDomain {
            guard !closing else { throw OwnershipError.closedSession }
            let key = NativeKey(kind: kind, identifier: nativeIdentifier)
            guard nativeIndex[key] == nil else { throw OwnershipError.duplicateNativeIdentifier }
            guard records.count < maximumRecords else { throw OwnershipError.capacityExceeded }
            guard nextGeneration < UInt64.max && acquisitions < UInt64.max else {
                throw OwnershipError.identifierExhausted
            }
            var dependencyGenerations: Set<UInt64> = []
            for dependency in dependencies {
                try validate(dependency.cell)
                dependencyGenerations.insert(dependency.identity.generation)
            }
            // A concurrent root-close publication cannot interleave with record publication.
            let identity = try admission.withLock { state in
                applyPending(&state)
                guard !state.shutdownRequested && !closing else { throw OwnershipError.closedSession }
                for generation in dependencyGenerations {
                    guard records[generation]?.state == .live else { throw OwnershipError.invalidHandle }
                }
                nextGeneration += 1
                let identity = HandleIdentity(session: session, generation: nextGeneration,
                                              nativeIdentifier: nativeIdentifier, kind: kind)
                let record = CleanupRecord(identity: identity, dependencies: dependencyGenerations, cleanup: cleanup)
                records[identity.generation] = record
                nativeIndex[key] = identity.generation
                for dependency in dependencyGenerations { records[dependency]!.dependents.insert(identity.generation) }
                acquisitions += 1
                return identity
            }
            return OwnedHandle(cell: HandleCell(control: self, identity: identity))
        }
    }

    func isValid(_ cell: HandleCell) -> Bool {
        (try? withDomain { try validate(cell); return true }) ?? false
    }

    func withAccess<Result: ~Copyable>(
        _ cell: HandleCell,
        matching kind: HandleKind?,
        _ body: () throws -> Result
    ) throws -> Result {
        try withDomain {
            try validate(cell, matching: kind)
            nativeFrames += 1
            defer { nativeFrames -= 1 }
            return try body()
        }
    }

    func withNativeFrame<Result: ~Copyable>(_ body: () throws -> Result) throws -> Result {
        try withDomain {
            let rejected = admission.withLock { state in
                applyPending(&state)
                return state.shutdownRequested || closing
            }
            guard !rejected else { throw OwnershipError.closedSession }
            nativeFrames += 1
            defer { nativeFrames -= 1 }
            return try body()
        }
    }

    @discardableResult
    func requestClose(generation: UInt64?) -> CloseProgress {
        admission.withLock { state in
            if let generation {
                if !state.shutdownRequested { state.pendingRecords.insert(generation) }
            } else if !state.shutdownRequested {
                state.shutdownRequested = true
                state.pendingShutdown = true
            }
        }
        // A busy foreign caller posts value-only work; the active thread performs native teardown.
        return (try? withDomain {
            synchronize()
            drainReady()
            if let generation { return records[generation] == nil ? .complete : .deferred }
            return records.isEmpty ? .complete : .deferred
        }) ?? .deferred
    }

    @unsafe func nativeDestroyed(_ cell: HandleCell) throws -> Bool {
        try withDomain {
            guard cell.control === self else { throw OwnershipError.foreignSession }
            guard let record = records[cell.identity.generation], record.identity == cell.identity else { return false }
            // An existing frame proves where deferred capture retirement can safely happen.
            guard nativeFrames > 0 else { throw OwnershipError.invalidHandle }
            if record.state == .runtimeReleasing || record.state == .nativeConsumed || record.state == .transferred { return false }
            guard record.dependents.isEmpty else { throw OwnershipError.liveDependents }
            record.state = .nativeConsumed
            nativeReleases += 1
            enqueue(record)
            return true
        }
    }

    /// Server client destruction consumes only the native-owned client/resource subtree.
    @unsafe func nativeDestroyedServerSubtree(_ cell: HandleCell) throws -> Bool {
        try withDomain {
            guard cell.control === self else { throw OwnershipError.foreignSession }
            guard nativeFrames > 0 else { throw OwnershipError.invalidHandle }
            guard let root = records[cell.identity.generation], root.identity == cell.identity else { return false }
            guard root.identity.kind == .serverClient else { throw OwnershipError.wrongKind }
            var pending = [root.identity.generation]
            var subtree: Set<UInt64> = []
            while let generation = pending.popLast() {
                guard subtree.insert(generation).inserted, let record = records[generation] else { continue }
                guard generation == root.identity.generation || record.identity.kind == .serverResource else {
                    throw OwnershipError.liveDependents
                }
                pending.append(contentsOf: record.dependents)
            }
            let changed = root.state == .live || root.state == .closing
            for generation in subtree {
                guard let record = records[generation] else { continue }
                if record.state == .live || record.state == .closing {
                    record.state = .nativeConsumed
                    nativeReleases += 1
                }
                if record.state == .nativeConsumed { enqueue(record) }
            }
            return changed
        }
    }

    /// A transfer discharges ownership without executing its native release action.
    @unsafe func relinquish(_ cell: HandleCell) throws {
        try withDomain {
            try validate(cell)
            guard nativeFrames > 0, let record = records[cell.identity.generation] else {
                throw OwnershipError.invalidHandle
            }
            guard record.dependents.isEmpty else { throw OwnershipError.liveDependents }
            record.state = .transferred
            transfers += 1
            enqueue(record)
        }
    }

    /// Callback delivery requires the complete native invocation to have an existing lease.
    func withCallbackFrame<Result: ~Copyable>(_ cell: HandleCell, matching kind: HandleKind = .registration, _ body: () throws -> Result) throws -> Result {
        try withDomain {
            guard nativeFrames > 0 else { throw OwnershipError.invalidHandle }
            try validate(cell, matching: kind)
            nativeFrames += 1
            defer { nativeFrames -= 1 }
            return try body()
        }
    }

    private func drainReady() {
        guard nativeFrames == 0 && !draining else { return }
        draining = true
        defer { draining = false }
        while true {
            synchronize()
            guard let generation = ready.popLast() else { return }
            queued.remove(generation)
            guard let record = records[generation], record.dependents.isEmpty else { continue }
            switch record.state {
            case .live, .runtimeReleasing:
                continue
            case .closing:
                // Consuming the action before entering C prevents a destroy callback from claiming it again.
                let action = record.cleanup
                record.cleanup = nil
                record.state = .runtimeReleasing
                nativeFrames += 1
                action?()
                nativeFrames -= 1
                runtimeReleases += 1
                retire(record)
                // Captures can run destructors, so their lifetime ends outside all bookkeeping locks.
                withExtendedLifetime(action) {}
            case .nativeConsumed, .transferred:
                let captures = record.cleanup
                record.cleanup = nil
                retire(record)
                withExtendedLifetime(captures) {}
            }
        }
    }

    private func retire(_ record: CleanupRecord) {
        records.removeValue(forKey: record.identity.generation)
        nativeIndex.removeValue(forKey: NativeKey(kind: record.identity.kind, identifier: record.identity.nativeIdentifier))
        for generation in record.dependencies {
            guard let dependency = records[generation] else { continue }
            dependency.dependents.remove(record.identity.generation)
            if dependency.state != .live { enqueue(dependency) }
        }
    }

    func snapshot() throws -> OwnershipSnapshot {
        try withDomain {
            OwnershipSnapshot(
                acquisitions: acquisitions, runtimeReleases: runtimeReleases, nativeReleases: nativeReleases, transfers: transfers,
                outstandingObligations: records.values.reduce(0) { $0 + ($1.state == .nativeConsumed || $1.state == .transferred ? 0 : 1) },
                retainedRecords: records.count, nativeFrames: nativeFrames, closing: closing
            )
        }
    }
}
