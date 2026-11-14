import Dispatch
import Testing
@testable import WaylandRuntime

// This deliberate test-only transfer exercises runtime defenses after bypassing static isolation.
private struct TestOnlySharedControl: @unchecked Sendable {
    let control: RuntimeControl
}

@Test func foreignThreadCannotEnterButCanPostCloseDuringFrame() throws {
    let session = try OwnershipSession()
    let releases = try RuntimeMutex(0)
    let owner = unsafe try session.adopt(nativeIdentifier: 1, kind: .serverResource) {
        releases.withLock { $0 += 1 }
    }
    let reference = owner.reference
    let shared = TestOnlySharedControl(control: session.control)
    let completed = DispatchSemaphore(value: 0)
    let observedError = try RuntimeMutex<OwnershipError?>(nil)
    let observedProgress = try RuntimeMutex<CloseProgress?>(nil)
    try session.withNativeFrame {
        #expect(reference.isValidInCurrentNativeFrame)
        DispatchQueue.global().async {
            do {
                _ = try shared.control.snapshot()
            } catch {
                observedError.withLock { $0 = error as? OwnershipError }
            }
            let progress = shared.control.requestClose(generation: nil)
            observedProgress.withLock { $0 = progress }
            completed.signal()
        }
        #expect(completed.wait(timeout: .now() + 5) == .success)
        #expect(observedError.withLock { $0 } == .domainBusy)
        #expect(observedProgress.withLock { $0 } == .deferred)
        #expect(!reference.isValidInCurrentNativeFrame)
        #expect(!reference.isValid)
        #expect(releases.withLock { $0 } == 0)
    }
    #expect(releases.withLock { $0 } == 1)
    #expect(try session.snapshot().retainedRecords == 0)
}

@Test func simultaneousCloseRequestsConvergeToOnePhysicalRelease() throws {
    let session = try OwnershipSession()
    let releases = try RuntimeMutex(0)
    let owner = unsafe try session.adopt(nativeIdentifier: 1, kind: .registration) {
        releases.withLock { $0 += 1 }
    }
    let reference = owner.reference
    let shared = TestOnlySharedControl(control: session.control)
    DispatchQueue.concurrentPerform(iterations: 500) { _ in
        shared.control.requestClose(generation: nil)
    }
    #expect(!reference.isValid)
    #expect(releases.withLock { $0 } == 1)
    let snapshot = try session.snapshot()
    #expect(snapshot.runtimeReleases == 1 && snapshot.retainedRecords == 0)
}

@Test func repeatedCloseDoesNotLeaveAnEmptyAdmissionMailboxNotified() throws {
    let session = try OwnershipSession()
    let owner = unsafe try session.adopt(nativeIdentifier: 7, kind: .registration) {}
    #expect(owner.requestClose() == .complete)
    #expect(!session.control.admissionNotificationPending)
    #expect(session.requestClose() == .complete)
    #expect(!session.control.admissionNotificationPending)
    #expect(owner.requestClose() == .complete)
    #expect(session.requestClose() == .complete)
    #expect(!session.control.admissionNotificationPending)
}

@Test func concurrentSessionIdentityAllocationIsUnique() throws {
    let identities = try RuntimeMutex<Set<UInt64>>([])
    let failures = try RuntimeMutex<[String]>([])
    DispatchQueue.concurrentPerform(iterations: 256) { _ in
        do {
            let session = try OwnershipSession(maximumRecords: 1)
            let owner = unsafe try session.adopt(nativeIdentifier: 1, kind: .registration) {}
            let identity = owner.reference.identity.session
            _ = identities.withLock { $0.insert(identity) }
        } catch {
            failures.withLock { $0.append(String(describing: error)) }
        }
    }
    #expect(failures.withLock { $0 }.isEmpty)
    #expect(identities.withLock { $0.count } == 256)
}

private func admitCallback(_ control: RuntimeControl, _ reference: ObjectHandle) throws {
    try control.withCallbackFrame(reference.cell, matching: .serverResource) {}
}

@Test func callbackFastAdmissionRestoresNestedDomainsAndObservesForeignCloseBeforeDelivery() throws {
    let first = try OwnershipSession()
    let second = try OwnershipSession()
    let released = try RuntimeMutex(0)
    let owner = unsafe try first.adopt(nativeIdentifier: 1, kind: .serverResource) { released.withLock { $0 += 1 } }
    let other = unsafe try second.adopt(nativeIdentifier: 1, kind: .serverResource) {}
    let firstControl = first.control
    let secondControl = second.control
    let reference = owner.reference
    let observer = reference.destructionObserver()
    let deliveryGate = try CallbackDeliveryGate()
    let secondReference = other.reference
    #expect(throws: OwnershipError.invalidHandle) {
        try admitCallback(firstControl, reference)
    }
    try first.withNativeFrame {
        try admitCallback(firstControl, reference)
        #expect(try observer.admitCallback(gate: deliveryGate))
        deliveryGate.cancel()
        #expect(try !observer.admitCallback(gate: deliveryGate))
        try second.withNativeFrame {
            try admitCallback(secondControl, secondReference)
            #expect(throws: OwnershipError.invalidHandle) {
                try admitCallback(firstControl, reference)
            }
        }
        try admitCallback(firstControl, reference)
        let shared = TestOnlySharedControl(control: firstControl)
        let generation = reference.identity.generation
        let completed = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = shared.control.requestClose(generation: generation)
            completed.signal()
        }
        completed.wait()
        #expect(throws: OwnershipError.invalidHandle) {
            try admitCallback(firstControl, reference)
        }
        #expect(throws: OwnershipError.invalidHandle) {
            try observer.admitCallback(gate: deliveryGate)
        }
        #expect(released.withLock { $0 } == 0)
    }
    #expect(released.withLock { $0 } == 1)
    first.requestClose()
    second.requestClose()
}

@Test func finalDomainExitDoesNotLoseRacingRootClose() throws {
    for _ in 0..<500 {
        let session = try OwnershipSession()
        let releases = try RuntimeMutex(0)
        let owner = unsafe try session.adopt(nativeIdentifier: 1, kind: .registration) {
            releases.withLock { $0 += 1 }
        }
        let shared = TestOnlySharedControl(control: session.control)
        let start = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            start.wait()
            _ = shared.control.requestClose(generation: nil)
            finished.signal()
        }
        try owner.reference.withAccess { _ = start.signal() }
        #expect(finished.wait(timeout: .now() + 5) == .success)
        // This observation must precede any snapshot or explicit drain that could hide a stranded close.
        #expect(releases.withLock { $0 } == 1)
        #expect(try session.snapshot().retainedRecords == 0)
    }
}
