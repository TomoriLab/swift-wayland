import Testing
@testable import WaylandRuntime

final class ReleaseLog {
    var values: [Int] = []
}

enum BodyFailure: Error { case expected }

@Test func closeInvalidatesAllReferenceCopiesAndReleasesOnce() throws {
    let log = ReleaseLog()
    let session = try OwnershipSession()
    let owner = unsafe try session.adopt(nativeIdentifier: 7, kind: .serverResource) { log.values.append(7) }
    let first = owner.reference
    let second = first
    #expect(first.isValid && second.isValid)
    #expect(owner.requestClose() == .complete)
    #expect(!first.isValid && !second.isValid)
    #expect(owner.requestClose() == .complete)
    owner.close()
    #expect(log.values == [7])
    #expect(throws: OwnershipError.invalidHandle) { try first.withAccess {} }
    let snapshot = try session.snapshot()
    #expect(snapshot.acquisitions == 1 && snapshot.runtimeReleases == 1)
    #expect(snapshot.outstandingObligations == 0 && snapshot.retainedRecords == 0)
}

@Test func childReferenceDoesNotKeepRootUsable() throws {
    let log = ReleaseLog()
    func create() throws -> ObjectHandle {
        let session = try OwnershipSession()
        let owner = unsafe try session.adopt(nativeIdentifier: 1, kind: .serverDisplay) { log.values.append(1) }
        let reference = owner.reference
        #expect(session.requestClose() == .complete)
        #expect(!reference.isValid)
        return reference
    }
    let reference = try create()
    #expect(!reference.isValid && log.values == [1])
    #expect(throws: OwnershipError.closedSession) { try reference.withAccess {} }
}

@Test func rootDropWithSurvivingChildAuthorityClosesAllRecords() throws {
    let log = ReleaseLog()
    func create() throws -> OwnedHandle {
        let session = try OwnershipSession()
        return unsafe try session.adopt(nativeIdentifier: 1, kind: .serverDisplay) { log.values.append(1) }
    }
    let owner = try create()
    #expect(log.values == [1] && !owner.reference.isValid)
    owner.close()
    #expect(log.values == [1])
}

@Test func discardedOwnerAndReferenceDoNotLoseCleanupObligation() throws {
    let log = ReleaseLog()
    let session = try OwnershipSession()
    func scope() throws {
        let owner = unsafe try session.adopt(nativeIdentifier: 2, kind: .serverResource) { log.values.append(2) }
        _ = owner.reference
    }
    try scope()
    #expect(log.values == [2])
    #expect(try session.snapshot().retainedRecords == 0)
}

@Test func nestedFramesDeferUntilOuterReturnIncludingThrow() throws {
    let log = ReleaseLog()
    let session = try OwnershipSession()
    let owner = unsafe try session.adopt(nativeIdentifier: 1, kind: .serverResource) { log.values.append(1) }
    let reference = owner.reference
    #expect(throws: BodyFailure.expected) {
        try session.withNativeFrame {
            try reference.withAccess {
                #expect(owner.requestClose() == .deferred)
                #expect(!reference.isValid)
                #expect(log.values.isEmpty)
                let snapshot = try session.snapshot()
                #expect(snapshot.nativeFrames == 2)
            }
            #expect(log.values.isEmpty)
            throw BodyFailure.expected
        }
    }
    #expect(log.values == [1])
    #expect(try session.snapshot().nativeFrames == 0)
}

@Test func closingPrerequisiteClosesDiamondDependentsBeforeParents() throws {
    let log = ReleaseLog()
    let session = try OwnershipSession()
    let root = unsafe try session.adopt(nativeIdentifier: 1, kind: .serverDisplay) { log.values.append(1) }
    let left = unsafe try session.adopt(nativeIdentifier: 2, kind: .serverResource, dependencies: [root.reference]) { log.values.append(2) }
    let right = unsafe try session.adopt(nativeIdentifier: 3, kind: .serverResource, dependencies: [root.reference]) { log.values.append(3) }
    let leaf = unsafe try session.adopt(nativeIdentifier: 4, kind: .serverResource,
                                      dependencies: [left.reference, right.reference, left.reference]) { log.values.append(4) }
    #expect(root.requestClose() == .complete)
    #expect(log.values.first == 4 && log.values.last == 1 && Set(log.values) == [1, 2, 3, 4])
    #expect(!left.reference.isValid && !right.reference.isValid && !leaf.reference.isValid)
    #expect(try session.snapshot().runtimeReleases == 4)
}

@Test func identityReuseNeverResurrectsOldReference() throws {
    let session = try OwnershipSession()
    let first = unsafe try session.adopt(nativeIdentifier: 42, kind: .serverResource) {}
    let old = first.reference
    first.close()
    let second = unsafe try session.adopt(nativeIdentifier: 42, kind: .serverResource) {}
    #expect(old.identity.generation != second.reference.identity.generation)
    #expect(!old.isValid && second.reference.isValid)
    #expect(throws: OwnershipError.wrongKind) { try second.reference.withAccess(matching: .eventQueue) {} }
}

@Test func rejectsDuplicatesForeignDependenciesAndFailedTransfers() throws {
    let log = ReleaseLog()
    let session = try OwnershipSession(maximumRecords: 2)
    let other = try OwnershipSession()
    let first = unsafe try session.adopt(nativeIdentifier: 1, kind: .serverResource) {}
    let foreign = unsafe try other.adopt(nativeIdentifier: 1, kind: .serverResource) {}
    do {
        let unexpected = unsafe try session.adopt(nativeIdentifier: 1, kind: .serverResource) { log.values.append(1) }
        unexpected.close()
        Issue.record("Duplicate registration succeeded.")
    } catch { #expect(error as? OwnershipError == .duplicateNativeIdentifier) }
    do {
        let unexpected = unsafe try session.adopt(nativeIdentifier: 2, kind: .serverResource,
                                                dependencies: [foreign.reference]) { log.values.append(2) }
        unexpected.close()
        Issue.record("Foreign dependency was accepted.")
    } catch { #expect(error as? OwnershipError == .foreignSession) }
    #expect(log.values.isEmpty)
    #expect(first.reference.identity.session != foreign.reference.identity.session)
    // The same integer is valid in another native namespace.
    let queue = unsafe try session.adopt(nativeIdentifier: 1, kind: .eventQueue) {}
    #expect(queue.reference.isValid)
    do {
        let unexpected = unsafe try session.adopt(nativeIdentifier: 3, kind: .serverResource) { log.values.append(3) }
        unexpected.close()
        Issue.record("Capacity was exceeded.")
    } catch { #expect(error as? OwnershipError == .capacityExceeded) }
    #expect(log.values.isEmpty)
}

@Test func nativeDestructionInvalidatesWithoutSecondNativeRelease() throws {
    let log = ReleaseLog()
    let session = try OwnershipSession()
    let owner = unsafe try session.adopt(nativeIdentifier: 5, kind: .serverResource) { log.values.append(5) }
    let reference = owner.reference
    try session.withNativeFrame {
        #expect(unsafe try reference.nativeDestroyed())
        #expect(!reference.isValid)
        #expect(!(unsafe try reference.nativeDestroyed()))
        let snapshot = try session.snapshot()
        #expect(snapshot.nativeReleases == 1 && snapshot.outstandingObligations == 0 && snapshot.retainedRecords == 1)
    }
    #expect(try session.snapshot().retainedRecords == 0)
    owner.close()
    #expect(log.values.isEmpty)
}

@Test func nativeNotificationRequiresFrameAndLeaf() throws {
    let session = try OwnershipSession()
    let parent = unsafe try session.adopt(nativeIdentifier: 1, kind: .serverDisplay) {}
    let child = unsafe try session.adopt(nativeIdentifier: 2, kind: .serverResource, dependencies: [parent.reference]) {}
    #expect(throws: OwnershipError.invalidHandle) { unsafe try child.reference.nativeDestroyed() }
    try session.withNativeFrame {
        #expect(throws: OwnershipError.liveDependents) { unsafe try parent.reference.nativeDestroyed() }
        #expect(parent.reference.isValid && child.reference.isValid)
        _ = unsafe try child.reference.nativeDestroyed()
        #expect(throws: OwnershipError.liveDependents) { unsafe try parent.reference.nativeDestroyed() }
        #expect(parent.reference.isValid && !child.reference.isValid)
    }
}

@Test func limitsAndGenerationOverflowRejectBeforeTransfer() throws {
    #expect(throws: OwnershipError.invalidCapacity) { _ = try OwnershipSession(maximumRecords: 0) }
    let control = try RuntimeControl(maximumRecords: 1, initialGeneration: UInt64.max)
    let log = ReleaseLog()
    do {
        let unexpected = unsafe try control.adopt(nativeIdentifier: 1, kind: .serverResource, dependencies: []) { log.values.append(1) }
        unexpected.close()
        Issue.record("Generation overflow was accepted.")
    } catch { #expect(error as? OwnershipError == .identifierExhausted) }
    #expect(log.values.isEmpty)
    #expect(try control.snapshot().acquisitions == 0)
}

extension DescriptorAndCallbackTests {
    @Test func surrenderingChildAuthorityKeepsRootRecordUntilShutdown() throws {
        let session = try OwnershipSession()
        let counter = ReleaseLog()
        let owner = unsafe try session.adopt(nativeIdentifier: 9001, kind: .serverClient) { counter.values.append(1) }
        let reference = owner.surrenderToRoot()
        #expect(reference.isValid && counter.values.isEmpty)
        session.requestClose()
        #expect(!reference.isValid && counter.values == [1])
        #expect(try session.snapshot().retainedRecords == 0)
    }
}
