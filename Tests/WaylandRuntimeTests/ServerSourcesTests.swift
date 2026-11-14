import Glibc
import Testing
import WaylandRuntime
import WaylandServer
import RuntimeNativeTestSupport

private final class SourceObservations {
    var source: ServerFDSource?
    var invocations = 0
    var duplicate: Int32 = -1
}
extension DescriptorAndCallbackTests {
    @Test func descriptorSourceSelfCloseRetainsDuplicateThroughNativeFrame() throws {
        var input: Int32 = -1
        var output: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&input, &output) == 0)
        defer { _ = runtime_test_descriptor_close(output) }
        let session = try OwnershipSession()
        let descriptor = unsafe try session.adoptFileDescriptor(input)
        let display = try ServerDisplay()
        let observations = SourceObservations()
        observations.source = try display.addFD(descriptor.borrowed, mask: .readable) { [weak observations] mask in
            guard let observations, let reference = observations.source?.reference else { return .done }
            #expect(mask.contains(.readable))
            unsafe try reference.withUnsafeDescriptor { raw in
                observations.duplicate = raw
                #expect(runtime_test_descriptor_read_one(raw) == 1)
                #expect(observations.source?.requestClose() == .deferred)
                #expect(runtime_test_descriptor_is_open(raw) == 1)
            }
            observations.invocations += 1
            return .done
        }
        try observations.source?.reference.update(mask: [.readable])
        #expect(runtime_test_descriptor_write_one(output) == 1)
        try display.dispatch(timeoutMilliseconds: 100)
        #expect(observations.invocations == 1)
        #expect(runtime_test_descriptor_is_open(observations.duplicate) == 0)
        #expect(runtime_test_descriptor_is_open(input) == 1)
        observations.source = nil
        #expect(try display.snapshot().runtimeReleases == 2)
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }

    @Test func timerArmingDisarmingRecheckingAndFailurePreserveNativeContract() throws {
        let display = try ServerDisplay()
        let observations = SourceObservations()
        let timer = try display.addTimer { observations.invocations += 1; return .done }
        try timer.reference.update(delayMilliseconds: 0)
        try display.dispatch()
        #expect(observations.invocations == 0)
        #expect(throws: ServerError.nativeFailure(EINVAL)) { try timer.reference.update(delayMilliseconds: -1) }
        try timer.reference.update(delayMilliseconds: 1)
        try display.dispatch(timeoutMilliseconds: 100)
        #expect(observations.invocations == 1)
        let recheck = try display.addTimer {
            observations.invocations += 1
            return observations.invocations < 4 ? .recheck : .done
        }
        try recheck.reference.check()
        try recheck.reference.check()
        try display.dispatch()
        #expect(observations.invocations == 4)
        let failing = try display.addTimer { throw BodyFailure.expected }
        try failing.reference.update(delayMilliseconds: 1)
        try display.dispatch(timeoutMilliseconds: 100)
        #expect(failing.failure as? BodyFailure == .expected)
        display.requestClose()
        #expect(!timer.lifetime.isValid && !recheck.lifetime.isValid && !failing.lifetime.isValid)
        #expect(try display.snapshot().retainedRecords == 0)
    }

    @Test func descriptorSourceRegistrationFailureClosesOnlyItsOwnedDuplicate() throws {
        var input: Int32 = -1
        var output: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&input, &output) == 0)
        defer { _ = runtime_test_descriptor_close(output) }
        let session = try OwnershipSession()
        let descriptor = unsafe try session.adoptFileDescriptor(input)
        let count = runtime_test_matching_descriptor_count(input)
        let display = try ServerDisplay(maximumRecords: 2)
        do {
            let source = try display.addFD(descriptor.borrowed, mask: .readable) { _ in .done }
            _ = consume source
            Issue.record("Source publication unexpectedly ignored the configured capacity.")
        } catch { #expect(error as? OwnershipError == .capacityExceeded) }
        #expect(runtime_test_matching_descriptor_count(input) == count)
        #expect(try display.snapshot().retainedRecords == 1)
        display.requestClose()
    }
}

extension DescriptorAndCallbackTests {
    @Test func unsafeSignalSourceDeliversFromOrdinaryDispatchAndPreservesCallerMaskPolicy() throws {
        var previous = sigset_t()
        #expect(unsafe pthread_sigmask(SIG_SETMASK, nil, &previous) == 0)
        defer { _ = unsafe pthread_sigmask(SIG_SETMASK, &previous, nil) }
        let display = try ServerDisplay()
        let observations = SourceObservations()
        let source = unsafe try display.addSignal(SIGUSR1) { number in
            #expect(number == SIGUSR1)
            observations.invocations += 1
            return .done
        }
        #expect(pthread_kill(pthread_self(), SIGUSR1) == 0)
        try display.dispatch(timeoutMilliseconds: 100)
        #expect(observations.invocations == 1)
        source.close()
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }
}
