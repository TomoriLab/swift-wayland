import Testing
@testable import WaylandRuntime

private final class ReentryContext {
    weak var cell: HandleCell?
    var notifications = 0
    var progress: CloseProgress?
    var failure: (any Error)?
}

@Test func destructorCanReenterWithoutDoubleReleaseOrMutexDeadlock() throws {
    let context = ReentryContext()
    let log = ReleaseLog()
    let session = try OwnershipSession()
    let owner = unsafe try session.adopt(nativeIdentifier: 1, kind: .serverResource) {
        log.values.append(1)
        guard let cell = context.cell else { return }
        do {
            let reference = ObjectHandle(cell: cell)
            let claimed = unsafe try reference.nativeDestroyed()
            #expect(!claimed)
            context.notifications += 1
            context.progress = cell.control.requestClose(generation: nil)
            let snapshot = try cell.control.snapshot()
            #expect(snapshot.nativeFrames == 1 && snapshot.outstandingObligations == 1)
        } catch { context.failure = error }
    }
    context.cell = owner.reference.cell
    #expect(owner.requestClose() == .complete)
    #expect(context.failure == nil && context.notifications == 1)
    #expect(context.progress == .deferred)
    #expect(log.values == [1])
    let snapshot = try session.snapshot()
    #expect(snapshot.runtimeReleases == 1 && snapshot.nativeReleases == 0 && snapshot.retainedRecords == 0)
}

private final class CaptureSentinel {
    let log: ReleaseLog
    init(_ log: ReleaseLog) { self.log = log }
    deinit { log.values.append(99) }
}

@Test func nativeConsumedCapturesSurviveUntilOuterFrameAndDoNotExecute() throws {
    let session = try OwnershipSession()
    let log = ReleaseLog()
    func create() throws -> OwnedHandle {
        let sentinel = CaptureSentinel(log)
        return unsafe try session.adopt(nativeIdentifier: 7, kind: .serverResource) {
            withExtendedLifetime(sentinel) { log.values.append(7) }
        }
    }
    let owner = try create()
    let reference = owner.reference
    try session.withNativeFrame {
        let claimed = unsafe try reference.nativeDestroyed()
        #expect(claimed)
        #expect(log.values.isEmpty)
        #expect(owner.requestClose() == .deferred)
        #expect(log.values.isEmpty)
    }
    #expect(log.values == [99])
    #expect(try session.snapshot().nativeReleases == 1)
}

@Test func longDependencyChainAndTenThousandLifecyclesBalance() throws {
    let session = try OwnershipSession(maximumRecords: 2_048)
    let log = ReleaseLog()
    var owners = UniqueArray<OwnedHandle>()
    var previous: ObjectHandle?
    for value in 0..<1_000 {
        let owner = unsafe try session.adopt(nativeIdentifier: UInt64(value), kind: .serverResource,
                                            dependencies: previous.map { [$0] } ?? []) { log.values.append(value) }
        previous = owner.reference
        owners.append(owner)
    }
    #expect(session.requestClose() == .complete)
    #expect(log.values == Array((0..<1_000).reversed()))
    owners.removeAll()
    let cycles = try OwnershipSession(maximumRecords: 1)
    let counter = ReleaseLog()
    for _ in 0..<10_000 {
        let owner = unsafe try cycles.adopt(nativeIdentifier: 1, kind: .registration) { counter.values.append(1) }
        owner.close()
    }
    let snapshot = try cycles.snapshot()
    #expect(counter.values.count == 10_000)
    #expect(snapshot.acquisitions == snapshot.runtimeReleases && snapshot.outstandingObligations == 0)
    #expect(snapshot.retainedRecords == 0)
}

@Test func nativeIdentifierStaysReservedUntilCaptureRetirement() throws {
    let session = try OwnershipSession()
    let owner = unsafe try session.adopt(nativeIdentifier: 9, kind: .serverResource) {}
    let reference = owner.reference
    try session.withNativeFrame {
        _ = unsafe try reference.nativeDestroyed()
        do {
            let unexpected = unsafe try session.adopt(nativeIdentifier: 9, kind: .serverResource) {}
            unexpected.close()
            Issue.record("An identifier was reused before capture quiescence.")
        } catch { #expect(error as? OwnershipError == .duplicateNativeIdentifier) }
    }
    let replacement = unsafe try session.adopt(nativeIdentifier: 9, kind: .serverResource) {}
    #expect(!reference.isValid && replacement.reference.isValid)
    #expect(replacement.reference.identity.generation != reference.identity.generation)
}
