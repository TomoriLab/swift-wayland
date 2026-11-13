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
