import Testing
@testable import WaylandRuntime

@Test func boundedCloseNotificationAndAccessTracesPreserveConservation() throws {
    for trace in 0..<256 {
        let session = try OwnershipSession()
        let log = ReleaseLog()
        let owner = unsafe try session.adopt(nativeIdentifier: 1, kind: .serverResource) { log.values.append(1) }
        let reference = owner.reference
        var physicallyConsumedByNative = false
        var logicallyLive = true
        var rootClosing = false
        var encoded = trace
        try session.withNativeFrame {
            for _ in 0..<4 {
                let event = encoded % 4
                encoded /= 4
                switch event {
                case 0:
                    owner.requestClose()
                    logicallyLive = false
                case 1:
                    session.requestClose()
                    rootClosing = true
                    logicallyLive = false
                case 2:
                    let claimed = unsafe try reference.nativeDestroyed()
                    #expect(claimed == !physicallyConsumedByNative)
                    physicallyConsumedByNative = true
                    logicallyLive = false
                default:
                    #expect(reference.isValid == logicallyLive)
                    if logicallyLive {
                        let result = try reference.withAccess { 42 }
                        #expect(result == 42)
                    } else {
                        let expected: OwnershipError = rootClosing ? .closedSession : .invalidHandle
                        #expect(throws: expected) { try reference.withAccess {} }
                    }
                }
                let snapshot = try session.snapshot()
                #expect(snapshot.closing == rootClosing)
                #expect(snapshot.acquisitions == snapshot.runtimeReleases + snapshot.nativeReleases
                        + UInt64(snapshot.outstandingObligations))
                #expect(snapshot.retainedRecords == 1 && snapshot.nativeFrames == 1)
                #expect(log.values.isEmpty)
            }
        }
        session.requestClose()
        let snapshot = try session.snapshot()
        #expect(snapshot.retainedRecords == 0 && snapshot.outstandingObligations == 0)
        #expect(snapshot.nativeReleases == (physicallyConsumedByNative ? 1 : 0))
        #expect(snapshot.runtimeReleases == (physicallyConsumedByNative ? 0 : 1))
        #expect(log.values.count == (physicallyConsumedByNative ? 0 : 1))
    }
}

private final class WeakCellObserver {
    weak var cell: HandleCell?
}

@Test func cleanupRecordSurvivesLossOfItsLastReferenceCellInsideFrame() throws {
    let session = try OwnershipSession()
    let log = ReleaseLog()
    let observer = WeakCellObserver()
    func scope() throws {
        let owner = unsafe try session.adopt(nativeIdentifier: 1, kind: .registration) { log.values.append(1) }
        observer.cell = owner.reference.cell
    }
    try session.withNativeFrame {
        try scope()
        #expect(observer.cell == nil)
        let snapshot = try session.snapshot()
        #expect(snapshot.retainedRecords == 1 && snapshot.outstandingObligations == 1)
        #expect(log.values.isEmpty)
    }
    #expect(log.values == [1])
    #expect(try session.snapshot().retainedRecords == 0)
}

@Test func controlBookkeepingIsReleasedAfterLastClosedReference() throws {
    weak var observed: RuntimeControl?
    func scope() throws {
        let session = try OwnershipSession()
        observed = session.control
        let owner = unsafe try session.adopt(nativeIdentifier: 1, kind: .registration) {}
        owner.close()
        session.close()
    }
    try scope()
    #expect(observed == nil)
}
