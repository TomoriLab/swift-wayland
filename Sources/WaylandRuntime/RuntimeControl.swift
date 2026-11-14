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
    let lifetime: RecordLifetime
    var state: RecordState = .live { didSet { if state != .live { lifetime.live = false } } }
    var cleanup: (() -> Void)?
    var releaseReadiness: (() -> Bool)?

    init(identity: HandleIdentity, admission: RuntimeMutex<AdmissionState>, dependencies: Set<UInt64>, releaseReadiness: (() -> Bool)?, cleanup: @escaping () -> Void) {
        self.identity = identity
        lifetime = RecordLifetime(identity, admission: admission)
        self.dependencies = dependencies
        self.cleanup = cleanup
        self.releaseReadiness = releaseReadiness
    }
}

struct AdmissionState: Sendable {
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
    /// Exposes the close mailbox bit to ownership regression tests without granting mutation.
    var admissionNotificationPending: Bool { admission.notificationPending }
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

    private func enterValidated(_ cell: HandleCell, matching kind: HandleKind?) throws {
        guard cell.control === self else { throw OwnershipError.foreignSession }
        let current = pthread_self()
        let result: OwnershipError? = admission.withLock { state in
            if let thread = state.thread, thread != current { return .domainBusy }
            state.thread = current
            state.entries += 1
            applyPending(&state)
            if state.shutdownRequested || closing { return .closedSession }
            if let lifetime = cell.lifetime {
                guard lifetime.identity == cell.identity, lifetime.live else { return .invalidHandle }
            } else {
                guard let record = records[cell.identity.generation], record.identity == cell.identity,
                      record.state == .live else { return .invalidHandle }
            }
            if let kind, cell.identity.kind != kind { return .wrongKind }
            return nil
        }
        if let result {
            if result != .domainBusy { leave() }
            throw result
        }
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
            if !ready.isEmpty { drainReady() }
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
        // Publication holds this mutex, so an empty mailbox needs no transition or notification write.
        guard state.pendingShutdown || !state.pendingRecords.isEmpty else { return }
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
        admission.setNotification(false)
    }

    private func synchronize() {
        guard admission.notificationPending else { return }
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
        releaseReadiness: (() -> Bool)? = nil,
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
                let record = CleanupRecord(identity: identity, admission: admission, dependencies: dependencyGenerations, releaseReadiness: releaseReadiness, cleanup: cleanup)
                records[identity.generation] = record
                nativeIndex[key] = identity.generation
                for dependency in dependencyGenerations { records[dependency]!.dependents.insert(identity.generation) }
                acquisitions += 1
                return identity
            }
            return OwnedHandle(cell: HandleCell(control: self, identity: identity, lifetime: records[identity.generation]!.lifetime))
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
        try enterValidated(cell, matching: kind)
        defer { leave() }
        // Admission precedes native work; draining here could run a cleanup that closes this record.
        nativeFrames += 1
        defer { nativeFrames -= 1 }
        return try admission.withNativeScope(body)
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
            return try admission.withNativeScope(body)
        }
    }

    @discardableResult
    func requestClose(generation: UInt64?) -> CloseProgress {
        admission.withLock { state in
            if let generation {
                if !state.shutdownRequested {
                    state.pendingRecords.insert(generation)
                    admission.setNotification(true)
                }
            } else if !state.shutdownRequested {
                state.shutdownRequested = true
                state.pendingShutdown = true
                admission.setNotification(true)
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
                guard generation == root.identity.generation || (record.identity.kind == .serverResource || record.identity.kind == .serverResourceWatch || record.identity.kind == .serverResourceDestruction) else {
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

    /// Validates a copied native-callback identity while its enclosing frame retains this domain.
    func admitCallback(_ identity: HandleIdentity, lifetime: RecordLifetime? = nil) throws {
        guard admission.matchesNativeFrame else { throw OwnershipError.invalidHandle }
        synchronize()
        guard nativeFrames > 0 && !closing else { throw OwnershipError.closedSession }
        if let lifetime {
            guard lifetime.identity == identity && lifetime.live else { throw OwnershipError.invalidHandle }
        } else {
            guard let record = records[identity.generation], record.identity == identity,
                  record.state == .live else { throw OwnershipError.invalidHandle }
        }
    }

    /// Admits payload disposal without granting access to a logically closed receiver.
    func admitClosingCallback(_ identity: HandleIdentity) throws {
        guard admission.matchesNativeFrame else { throw OwnershipError.invalidHandle }
        synchronize()
        guard nativeFrames > 0, let record = records[identity.generation], record.identity == identity,
              record.state == .live || record.state == .closing || record.state == .runtimeReleasing else { throw OwnershipError.invalidHandle }
    }

    /// Reuses outer-frame protection; returning from Swift does not end the native invocation.
    func withCallbackFrame<Result: ~Copyable>(_ cell: HandleCell, matching kind: HandleKind = .registration, _ body: () throws -> Result) throws -> Result {
        guard cell.control === self else { throw OwnershipError.foreignSession }
        guard cell.identity.kind == kind else { throw OwnershipError.wrongKind }
        try admitCallback(cell.identity, lifetime: cell.lifetime)
        return try body()
    }

    private func drainReady() {
        guard nativeFrames == 0 && !draining else { return }
        draining = true
        defer { draining = false }
        var deferred: [UInt64] = []
        var progressed = false
        while true {
            synchronize()
            guard let generation = ready.popLast() else {
                for generation in deferred { if let record = records[generation] { enqueue(record) } }
                deferred.removeAll(keepingCapacity: true)
                guard progressed && !ready.isEmpty else { return }
                progressed = false
                continue
            }
            queued.remove(generation)
            guard let record = records[generation], record.dependents.isEmpty else { continue }
            switch record.state {
            case .live, .runtimeReleasing:
                continue
            case .closing:
                if let readiness = record.releaseReadiness {
                    nativeFrames += 1
                    let allowed = admission.withNativeScope { readiness() }
                    nativeFrames -= 1
                    if record.state != .closing {
                        enqueue(record)
                        progressed = true
                        continue
                    }
                    if !allowed { deferred.append(generation); continue }
                }
                // Consuming the action before entering C prevents a destroy callback from claiming it again.
                let action = record.cleanup
                record.cleanup = nil
                record.releaseReadiness = nil
                record.state = .runtimeReleasing
                nativeFrames += 1
                admission.withNativeScope { action?() }
                nativeFrames -= 1
                runtimeReleases += 1
                retire(record)
                progressed = true
                // Captures can run destructors, so their lifetime ends outside all bookkeeping locks.
                withExtendedLifetime(action) {}
            case .nativeConsumed, .transferred:
                let captures = record.cleanup
                let readiness = record.releaseReadiness
                record.cleanup = nil
                record.releaseReadiness = nil
                retire(record)
                progressed = true
                withExtendedLifetime(captures) {}
                withExtendedLifetime(readiness) {}
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
