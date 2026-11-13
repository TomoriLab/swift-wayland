import Dispatch
import Testing
import RuntimeNativeTestSupport
@testable import WaylandRuntime

private final class ContextRecorder {
    let log: ReleaseLog
    weak var root: NativeOwnerBox?
    var calls = 0
    var throwInHandler = false
    var action: (() -> Void)?
    init(log: ReleaseLog, root: NativeOwnerBox) { self.log = log; self.root = root }
    func handle(_ descriptor: BorrowedFileDescriptor?) throws {
        calls += 1
        if let descriptor { #expect(descriptor.isValid) }
        action?()
        if throwInHandler { throw BodyFailure.expected }
    }
    deinit { log.values.append(99) }
}

@unsafe private func invokeContext(_ data: UnsafeMutableRawPointer?, _ raw: Int32) -> Int32 {
    do {
        var incoming: ReceivedFileDescriptor? = raw >= 0 ? unsafe try ReceivedFileDescriptor(adopting: raw) : nil
        let result = unsafe CallbackAttachment<ContextRecorder>.deliver(userData: data) { context in
            if let event = incoming.take() {
                guard let root = context.root else { return }
                let descriptor = try event.register(in: root.session)
                try context.handle(descriptor.borrowed)
            } else {
                try context.handle(nil)
            }
        }
        switch result {
        case .delivered: return 1
        case .cancelled: return 0
        case .unavailable: return -1
        case .failed: return -2
        }
    } catch { return -2 }
}

extension DescriptorAndCallbackTests {
    @Test func subscriptionCancellationKeepsNativeContextUntilDetach() throws {
        let root = try NativeOwnerBox()
        let log = ReleaseLog()
        let slot = unsafe try #require(runtime_test_callback_slot_create())
        defer { unsafe runtime_test_callback_slot_destroy(slot) }
        weak var observed: ContextRecorder?
        func attach() throws -> CallbackAttachment<ContextRecorder> {
            let context = ContextRecorder(log: log, root: root)
            observed = context
            return unsafe try root.session.attachCallback(context: context) { pointer in
                unsafe runtime_test_callback_install(slot, invokeContext, pointer)
                return .installed { unsafe runtime_test_callback_detach(slot, 0) }
            }
        }
        let attachment = try attach()
        let subscription = try attachment.subscription()
        try root.session.withNativeFrame {
            let first = unsafe runtime_test_callback_invoke(slot, -1)
            #expect(first == 1 && observed?.calls == 1)
        }
        subscription.cancel()
        #expect(observed != nil && log.values.isEmpty)
        try root.session.withNativeFrame {
            let fd = runtime_test_descriptor_open()
            let cancelled = unsafe runtime_test_callback_invoke(slot, fd)
            #expect(cancelled == 0 && observed?.calls == 1)
            #expect(runtime_test_descriptor_is_open(fd) == 0)
        }
        #expect(unsafe runtime_test_callback_detach_count(slot) == 0)
        attachment.close()
        #expect(observed == nil && log.values == [99])
        #expect(unsafe runtime_test_callback_detach_count(slot) == 1)
    }

    @Test func droppedSubscriptionCancelsWithoutPhysicalDetach() throws {
        let root = try NativeOwnerBox()
        let log = ReleaseLog()
        let slot = unsafe try #require(runtime_test_callback_slot_create())
        defer { unsafe runtime_test_callback_slot_destroy(slot) }
        let attachment = unsafe try root.session.attachCallback(context: ContextRecorder(log: log, root: root)) { pointer in
            unsafe runtime_test_callback_install(slot, invokeContext, pointer)
            return .installed { unsafe runtime_test_callback_detach(slot, 0) }
        }
        do { let token = try attachment.subscription(); _ = token.cancellation }
        #expect(attachment.cancellation.isCancelled)
        #expect(unsafe runtime_test_callback_detach_count(slot) == 0)
        #expect(log.values.isEmpty)
        attachment.close()
        #expect(log.values == [99])
    }

    @Test func installationRollbackHandlesSynchronousCallbackAndReleasesOnce() throws {
        let root = try NativeOwnerBox()
        let log = ReleaseLog()
        let slot = unsafe try #require(runtime_test_callback_slot_create())
        defer { unsafe runtime_test_callback_slot_destroy(slot) }
        func failingAttach() throws {
            let attachment = unsafe try root.session.attachCallback(context: ContextRecorder(log: log, root: root)) { pointer in
                unsafe runtime_test_callback_install(slot, invokeContext, pointer)
                let result = unsafe runtime_test_callback_invoke(slot, -1)
                #expect(result == 1)
                return .failed(BodyFailure.expected, rollback: { unsafe runtime_test_callback_detach(slot, 1) })
            }
            attachment.close()
        }
        #expect(throws: BodyFailure.expected) { try failingAttach() }
        #expect(log.values == [99])
        #expect(unsafe runtime_test_callback_detach_count(slot) == 1)
        #expect(try root.session.snapshot().retainedRecords == 0)
    }

    @Test func failedInstallationWithoutNativeRetentionAndCapacityFailureReleaseContext() throws {
        let root = try NativeOwnerBox()
        let log = ReleaseLog()
        func failBeforeAttach() throws {
            let attachment = unsafe try root.session.attachCallback(context: ContextRecorder(log: log, root: root)) { _ in
                .failed(BodyFailure.expected, rollback: nil)
            }
            attachment.close()
        }
        #expect(throws: BodyFailure.expected) { try failBeforeAttach() }
        #expect(log.values == [99])
        let limited = try OwnershipSession(maximumRecords: 1)
        let occupied = unsafe try limited.adopt(nativeIdentifier: 1, kind: .registration) {}
        var installed = false
        do {
            let attachment = unsafe try limited.attachCallback(context: ContextRecorder(log: log, root: root)) { _ in
                installed = true
                return .installed {}
            }
            attachment.close()
            Issue.record("Capacity failure did not prevent native installation.")
        } catch { #expect(error as? OwnershipError == .capacityExceeded) }
        #expect(!installed && log.values == [99, 99])
        occupied.close()
    }

    @Test func handlerThrowClosesReceivedDescriptorAndNeverUnwindsC() throws {
        let root = try NativeOwnerBox()
        let log = ReleaseLog()
        let slot = unsafe try #require(runtime_test_callback_slot_create())
        defer { unsafe runtime_test_callback_slot_destroy(slot) }
        let context = ContextRecorder(log: log, root: root)
        context.throwInHandler = true
        let attachment = unsafe try root.session.attachCallback(context: context) { pointer in
            unsafe runtime_test_callback_install(slot, invokeContext, pointer)
            return .installed { unsafe runtime_test_callback_detach(slot, 0) }
        }
        try root.session.withNativeFrame {
            let fd = runtime_test_descriptor_open()
            let result = unsafe runtime_test_callback_invoke(slot, fd)
            #expect(result == -2)
            // The received owner closed logically, but the complete native frame still owns the fd lease.
            #expect(runtime_test_descriptor_is_open(fd) == 1)
        }
        #expect(try root.session.snapshot().runtimeReleases == 1)
        attachment.close()
        #expect(try root.session.snapshot().runtimeReleases == 2)
    }

    @Test func rootCloseInsideCallbackDefersDetachPastOuterNativeFrame() throws {
        let root = try NativeOwnerBox()
        let log = ReleaseLog()
        let slot = unsafe try #require(runtime_test_callback_slot_create())
        defer { unsafe runtime_test_callback_slot_destroy(slot) }
        func attach() throws -> CallbackAttachment<ContextRecorder> {
            let context = ContextRecorder(log: log, root: root)
            context.action = { [weak root] in _ = root?.requestClose() }
            return unsafe try root.session.attachCallback(context: context) { pointer in
                unsafe runtime_test_callback_install(slot, invokeContext, pointer)
                return .installed { unsafe runtime_test_callback_detach(slot, 1) }
            }
        }
        let attachment = try attach()
        try root.session.withNativeFrame {
            #expect(unsafe runtime_test_callback_invoke(slot, -1) == 1)
            #expect(unsafe runtime_test_callback_detach_count(slot) == 0)
            #expect(log.values.isEmpty && !attachment.lifetime.isValid)
        }
        #expect(unsafe runtime_test_callback_detach_count(slot) == 1)
        #expect(log.values == [99])
        attachment.close()
    }

    @Test func closeDuringInstallStillRecordsDetachBeforeRollback() throws {
        let root = try NativeOwnerBox()
        let log = ReleaseLog()
        let slot = unsafe try #require(runtime_test_callback_slot_create())
        defer { unsafe runtime_test_callback_slot_destroy(slot) }
        do {
            let attachment = unsafe try root.session.attachCallback(context: ContextRecorder(log: log, root: root)) { pointer in
                unsafe runtime_test_callback_install(slot, invokeContext, pointer)
                _ = root.requestClose()
                return .installed { unsafe runtime_test_callback_detach(slot, 1) }
            }
            attachment.close()
            Issue.record("Closing installation published a live attachment.")
        } catch { #expect(error as? OwnershipError == .closedSession) }
        #expect(log.values == [99])
        #expect(unsafe runtime_test_callback_detach_count(slot) == 1)
        #expect(try root.session.snapshot().retainedRecords == 0)
    }

    @Test func cancellationSignalsAreThreadSafeAndDoNotFreeContext() throws {
        let root = try NativeOwnerBox()
        let log = ReleaseLog()
        let slot = unsafe try #require(runtime_test_callback_slot_create())
        defer { unsafe runtime_test_callback_slot_destroy(slot) }
        let attachment = unsafe try root.session.attachCallback(context: ContextRecorder(log: log, root: root)) { pointer in
            unsafe runtime_test_callback_install(slot, invokeContext, pointer)
            return .installed { unsafe runtime_test_callback_detach(slot, 0) }
        }
        let token = try attachment.subscription()
        let cancellation = token.cancellation
        DispatchQueue.concurrentPerform(iterations: 500) { _ in cancellation.cancel() }
        #expect(log.values.isEmpty && cancellation.isCancelled)
        #expect(unsafe runtime_test_callback_detach_count(slot) == 0)
        attachment.close()
        #expect(log.values == [99])
    }
}

extension DescriptorAndCallbackTests {
    @Test func callbackEntryRequiresOuterFrameAndSingleSubscription() throws {
        let root = try NativeOwnerBox()
        let log = ReleaseLog()
        let slot = unsafe try #require(runtime_test_callback_slot_create())
        defer { unsafe runtime_test_callback_slot_destroy(slot) }
        let context = ContextRecorder(log: log, root: root)
        let attachment = unsafe try root.session.attachCallback(context: context) { pointer in
            unsafe runtime_test_callback_install(slot, invokeContext, pointer)
            return .installed { unsafe runtime_test_callback_detach(slot, 0) }
        }
        let token = try attachment.subscription()
        do {
            let unexpected = try attachment.subscription()
            unexpected.cancel()
            Issue.record("A second subscription was issued.")
        } catch { #expect(error as? CallbackContextError == .subscriptionAlreadyIssued) }
        let incoming = runtime_test_descriptor_open()
        #expect(unsafe runtime_test_callback_invoke(slot, incoming) == -1)
        #expect(context.calls == 0 && runtime_test_descriptor_is_open(incoming) == 0)
        token.cancel()
        attachment.close()
    }

    @Test func callbackDependencyDetachesBeforeDescriptorIsClosed() throws {
        let root = try NativeOwnerBox()
        let log = ReleaseLog()
        let slot = unsafe try #require(runtime_test_callback_slot_create())
        defer { unsafe runtime_test_callback_slot_destroy(slot) }
        let raw = runtime_test_descriptor_open()
        let descriptor = unsafe try root.session.adoptFileDescriptor(raw)
        let attachment = unsafe try root.session.attachCallback(
            context: ContextRecorder(log: log, root: root), dependencies: [descriptor.lifetime]
        ) { pointer in
            unsafe runtime_test_callback_install(slot, invokeContext, pointer)
            return .installed {
                #expect(runtime_test_descriptor_is_open(raw) == 1)
                unsafe runtime_test_callback_detach(slot, 1)
            }
        }
        #expect(descriptor.requestClose().progress == .complete)
        #expect(runtime_test_descriptor_is_open(raw) == 0)
        #expect(!attachment.lifetime.isValid && log.values == [99])
        #expect(unsafe runtime_test_callback_detach_count(slot) == 1)
        #expect(try root.session.snapshot().runtimeReleases == 2)
    }

    @Test func attachmentFallbackBalancesTenThousandRetainedContexts() throws {
        let root = try NativeOwnerBox()
        let log = ReleaseLog()
        let slot = unsafe try #require(runtime_test_callback_slot_create())
        defer { unsafe runtime_test_callback_slot_destroy(slot) }
        func cycle() throws {
            let attachment = unsafe try root.session.attachCallback(context: ContextRecorder(log: log, root: root)) { pointer in
                unsafe runtime_test_callback_install(slot, invokeContext, pointer)
                return .installed { unsafe runtime_test_callback_detach(slot, 1) }
            }
            #expect(attachment.lifetime.isValid)
        }
        for _ in 0..<10_000 { try cycle() }
        #expect(log.values.count == 10_000)
        #expect(unsafe runtime_test_callback_detach_count(slot) == 10_000)
        let snapshot = try root.session.snapshot()
        #expect(snapshot.acquisitions == 10_000 && snapshot.runtimeReleases == 10_000)
        #expect(snapshot.retainedRecords == 0)
    }
}
