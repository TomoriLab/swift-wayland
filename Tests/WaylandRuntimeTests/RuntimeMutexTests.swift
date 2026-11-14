import Dispatch
import Testing
@testable import WaylandRuntime

private enum MutexTestFailure: Error { case expected }

private final class MutexPayload: Sendable {
    let releases: RuntimeMutex<Int>
    init(releases: RuntimeMutex<Int>) { self.releases = releases }
    deinit { releases.withLock { $0 += 1 } }
}

extension DescriptorAndCallbackTests {
    @Test func mutexUnlocksAfterThrowAndSerializesConcurrentMutation() throws {
        let mutex = try RuntimeMutex(0)
        #expect(throws: MutexTestFailure.self) {
            try mutex.withLock { value in
                value = 7
                throw MutexTestFailure.expected
            }
        }
        DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
            mutex.withLock { $0 += 1 }
        }
        #expect(mutex.withLock { $0 } == 1_007)
    }

    @Test func mutexStoredValueRetiresExactlyOnce() throws {
        let releases = try RuntimeMutex(0)
        func exercise() throws {
            let mutex = try RuntimeMutex(MutexPayload(releases: releases))
            let alias = mutex
            alias.withLock { value in
                #expect(value.releases === releases)
                #expect(releases.withLock { $0 } == 0)
            }
        }
        try exercise()
        #expect(releases.withLock { $0 } == 1)
    }

    @Test(arguments: [false, true])
    func mutexSurvivesLastExternalReferenceRemoval(throwing: Bool) throws {
        let releases = try RuntimeMutex(0)
        var mutex: RuntimeMutex<MutexPayload>? = try RuntimeMutex(MutexPayload(releases: releases))
        weak let observed = mutex
        do {
            try mutex!.withLock { value in
                mutex = nil
                #expect(observed != nil)
                #expect(value.releases === releases)
                #expect(releases.withLock { $0 } == 0)
                if throwing { throw MutexTestFailure.expected }
            }
            #expect(!throwing)
        } catch MutexTestFailure.expected {
            #expect(throwing)
        }
        #expect(observed == nil)
        #expect(releases.withLock { $0 } == 1)
    }
}
