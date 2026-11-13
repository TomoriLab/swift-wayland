import Glibc
import Testing
import RuntimeNativeTestSupport
@testable import WaylandRuntime

@Suite(.serialized)
struct DescriptorAndCallbackTests {
    @Test func descriptorCloseInvalidatesCopiesAndAttemptsOnce() throws {
        let session = try OwnershipSession()
        let raw = runtime_test_descriptor_open()
        #expect(raw >= 0)
        let owner = unsafe try session.adoptFileDescriptor(raw)
        let reference = owner.borrowed
        let copy = reference
        #expect(owner.requestClose().progress == .complete)
        let result = owner.close()
        #expect(result.errorCode == nil)
        #expect(!reference.isValid && !copy.isValid)
        #expect(runtime_test_descriptor_is_open(raw) == 0)
        #expect(reference.snapshot.closeAttempts == 1 && !reference.snapshot.ownsDescriptor)
    }

    @Test func descriptorBorrowDefersCloseAndReleasesOnThrow() throws {
        let session = try OwnershipSession()
        let raw = runtime_test_descriptor_open()
        let owner = unsafe try session.adoptFileDescriptor(raw)
        let reference = owner.borrowed
        #expect(throws: BodyFailure.expected) {
            unsafe try reference.withUnsafeDescriptor { value in
                #expect(value == raw)
                #expect(owner.requestClose().progress == .deferred)
                #expect(runtime_test_descriptor_is_open(raw) == 1)
                #expect(reference.snapshot.activeBorrows == 1)
                throw BodyFailure.expected
            }
        }
        #expect(reference.snapshot.activeBorrows == 0 && reference.snapshot.closeAttempts == 1)
        #expect(runtime_test_descriptor_is_open(raw) == 0)
    }

    @Test func descriptorTransferSurvivesNumberReuseWithoutRuntimeClose() throws {
        let session = try OwnershipSession()
        let raw = runtime_test_descriptor_open()
        let owner = unsafe try session.adoptFileDescriptor(raw)
        let reference = owner.borrowed
        let transferred = unsafe try owner.takeRawDescriptor()
        defer { _ = runtime_test_descriptor_close(transferred) }
        #expect(transferred == raw && runtime_test_descriptor_is_open(transferred) == 1)
        #expect(runtime_test_descriptor_replace(transferred) == transferred)
        #expect(session.requestClose() == .complete)
        #expect(runtime_test_descriptor_is_open(transferred) == 1)
        #expect(!reference.isValid && reference.snapshot.closeAttempts == 0)
        let snapshot = try session.snapshot()
        #expect(snapshot.transfers == 1 && snapshot.runtimeReleases == 0 && snapshot.outstandingObligations == 0)
    }

    @Test func descriptorDuplicateIsIndependentAndCloseOnExec() throws {
        let session = try OwnershipSession()
        let raw = runtime_test_descriptor_open()
        let owner = unsafe try session.adoptFileDescriptor(raw)
        let duplicate = try owner.borrowed.duplicate()
        let reference = duplicate.borrowed
        unsafe try reference.withUnsafeDescriptor { value in
            #expect(value != raw && runtime_test_descriptor_cloexec(value) == 1)
        }
        duplicate.close()
        #expect(runtime_test_descriptor_is_open(raw) == 1 && reference.snapshot.closeAttempts == 1)
        #expect(try session.snapshot().outstandingObligations == 1)
        owner.close()
        #expect(try session.snapshot().runtimeReleases == 2)
    }

    @Test func descriptorAdoptionAndReceiptHaveDistinctFailureOwnership() throws {
        let session = try OwnershipSession(maximumRecords: 1)
        let occupied = unsafe try session.adopt(nativeIdentifier: 1, kind: .registration) {}
        let raw = runtime_test_descriptor_open()
        do {
            let unexpected = unsafe try session.adoptFileDescriptor(raw)
            unexpected.close()
            Issue.record("Capacity failure was not reported.")
        } catch { #expect(error as? OwnershipError == .capacityExceeded) }
        #expect(runtime_test_descriptor_is_open(raw) == 1)
        _ = runtime_test_descriptor_close(raw)
        let incoming = runtime_test_descriptor_open()
        do {
            let unexpected = unsafe try session.receiveFileDescriptor(incoming)
            unexpected.close()
            Issue.record("Capacity failure was not reported.")
        } catch { #expect(error as? OwnershipError == .capacityExceeded) }
        #expect(runtime_test_descriptor_is_open(incoming) == 0)
        occupied.close()
    }

    @Test func descriptorReceiptDuringShutdownClosesInput() throws {
        let session = try OwnershipSession()
        session.requestClose()
        let raw = runtime_test_descriptor_open()
        do {
            let unexpected = unsafe try session.receiveFileDescriptor(raw)
            unexpected.close()
            Issue.record("Closed session accepted an incoming descriptor.")
        } catch { #expect(error as? OwnershipError == .closedSession) }
        #expect(runtime_test_descriptor_is_open(raw) == 0)
    }

    @Test func descriptorNativeErrorsRemainObservableWithoutCloseRetry() throws {
        let session = try OwnershipSession()
        let raw = runtime_test_descriptor_open()
        let owner = unsafe try session.adoptFileDescriptor(raw)
        let reference = owner.borrowed
        // Deliberate native contract violation injects EBADF without touching another owner's number.
        #expect(runtime_test_descriptor_close(raw) == 0)
        do {
            let unexpected = try reference.duplicate()
            unexpected.close()
            Issue.record("An invalid native descriptor was duplicated.")
        } catch { #expect(error as? FileDescriptorError == .duplicationFailed(EBADF)) }
        let result = owner.close()
        #expect(result.errorCode == EBADF && reference.snapshot.closeAttempts == 1)
    }

    @Test func descriptorOwnerFallbackAndRootShutdownBalanceTenThousandCycles() throws {
        let baseline = runtime_test_high_descriptor_count()
        #expect(baseline >= 0)
        let session = try OwnershipSession(maximumRecords: 1)
        func cycle() throws {
            let owner = unsafe try session.receiveFileDescriptor(runtime_test_descriptor_open())
            #expect(owner.borrowed.isValid)
        }
        for _ in 0..<10_000 { try cycle() }
        #expect(runtime_test_high_descriptor_count() == baseline)
        let snapshot = try session.snapshot()
        #expect(snapshot.acquisitions == 10_000 && snapshot.runtimeReleases == 10_000)
        #expect(snapshot.retainedRecords == 0)
        let raw = runtime_test_descriptor_open()
        let owner = unsafe try session.receiveFileDescriptor(raw)
        let reference = owner.borrowed
        session.requestClose()
        #expect(!reference.isValid && reference.snapshot.closeAttempts == 1)
        #expect(runtime_test_descriptor_is_open(raw) == 0)
    }
}

private final class DescriptorOwnerBox {
    private var owner: OwnedFileDescriptor?
    init(_ owner: consuming OwnedFileDescriptor) { self.owner = consume owner }
    @unsafe func transfer() throws -> Int32 {
        guard let value = owner.take() else { throw FileDescriptorError.noOwnership }
        return unsafe try value.takeRawDescriptor()
    }
}

extension DescriptorAndCallbackTests {
    @Test func transferDuringBorrowConsumesOwnerButDefersFallbackClose() throws {
        let session = try OwnershipSession()
        let raw = runtime_test_descriptor_open()
        let owner = unsafe try session.adoptFileDescriptor(raw)
        let reference = owner.borrowed
        let box = DescriptorOwnerBox(owner)
        unsafe try reference.withUnsafeDescriptor { _ in
            #expect(throws: FileDescriptorError.activeBorrow) { unsafe try box.transfer() }
            #expect(runtime_test_descriptor_is_open(raw) == 1)
            #expect(!reference.isValid)
        }
        #expect(runtime_test_descriptor_is_open(raw) == 0)
        #expect(reference.snapshot.closeAttempts == 1)
        #expect(try session.snapshot().transfers == 0)
    }

    @Test func transferWithDependentConsumerFailsAndClosesInDependencyOrder() throws {
        let session = try OwnershipSession()
        let raw = runtime_test_descriptor_open()
        let owner = unsafe try session.adoptFileDescriptor(raw)
        let reference = owner.borrowed
        let dependent = unsafe try session.adopt(nativeIdentifier: 77, kind: .registration,
                                                dependencies: [owner.lifetime]) {
            #expect(runtime_test_descriptor_is_open(raw) == 1)
        }
        do {
            let unexpected = unsafe try owner.takeRawDescriptor()
            _ = runtime_test_descriptor_close(unexpected)
            Issue.record("A descriptor with a live consumer was transferred.")
        } catch { #expect(error as? OwnershipError == .liveDependents) }
        #expect(!dependent.reference.isValid && !reference.isValid)
        #expect(reference.snapshot.closeAttempts == 1 && runtime_test_descriptor_is_open(raw) == 0)
        let snapshot = try session.snapshot()
        #expect(snapshot.transfers == 0 && snapshot.runtimeReleases == 2)
        #expect(snapshot.acquisitions == snapshot.runtimeReleases + snapshot.nativeReleases
                + snapshot.transfers + UInt64(snapshot.outstandingObligations))
    }

    @Test func failedDuplicateRegistrationClosesItsNewDescriptor() throws {
        let session = try OwnershipSession(maximumRecords: 1)
        let raw = runtime_test_descriptor_open()
        let owner = unsafe try session.adoptFileDescriptor(raw)
        let baseline = runtime_test_matching_descriptor_count(raw)
        #expect(baseline > 0)
        for _ in 0..<1_000 {
            do {
                let unexpected = try owner.borrowed.duplicate()
                unexpected.close()
                Issue.record("Duplicate escaped a full session.")
            } catch { #expect(error as? OwnershipError == .capacityExceeded) }
        }
        #expect(runtime_test_matching_descriptor_count(raw) == baseline)
        #expect(runtime_test_descriptor_is_open(raw) == 1)
        #expect(try session.snapshot().acquisitions == 1)
        owner.close()
    }

    @Test func unregisteredReceivedDescriptorsCloseWhenIgnoredOrRegistrationFails() throws {
        let raw = runtime_test_descriptor_open()
        func ignored() throws { let incoming = unsafe try ReceivedFileDescriptor(adopting: raw); _ = incoming }
        try ignored()
        #expect(runtime_test_descriptor_is_open(raw) == 0)
        let closed = try OwnershipSession()
        closed.requestClose()
        let next = runtime_test_descriptor_open()
        do {
            let incoming = unsafe try ReceivedFileDescriptor(adopting: next)
            let unexpected = try incoming.register(in: closed)
            unexpected.close()
            Issue.record("Received descriptor registered after shutdown.")
        } catch { #expect(error as? OwnershipError == .closedSession) }
        #expect(runtime_test_descriptor_is_open(next) == 0)
    }
}
