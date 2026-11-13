import Testing
import RuntimeNativeTestSupport
import CWaylandClient
import WaylandClient
@testable import WaylandRuntime

private final class ProxyContext {
    let log: ReleaseLog
    var events: [ClientEvent] = []
    var action: (() throws -> Void)?
    init(_ log: ReleaseLog) { self.log = log }
    deinit { log.values.append(99) }
}

extension DescriptorAndCallbackTests {
    @Test func permanentProxyCancellationKeepsContextAndCleansIncomingObligations() throws {
        let peer = unsafe try #require(runtime_test_peer_create())
        defer { unsafe runtime_test_peer_destroy(peer) }
        let session = try OwnershipSession()
        let proxy = unsafe try #require(runtime_test_peer_proxy(peer))
        let log = ReleaseLog()
        weak var observed: ProxyContext?
        func attach() throws -> ClientProxyDispatcher<ProxyContext> {
            let context = ProxyContext(log)
            observed = context
            return unsafe try ClientProxyDispatcher(receiving: proxy, in: session, context: context) { context, event in
                context.events.append(event)
            }
        }
        let owner = try attach()
        let subscription = try owner.subscription()
        unsafe runtime_test_peer_post(peer, 0, -1)
        try session.withNativeFrame { #expect(unsafe runtime_test_peer_dispatch(peer) >= 0) }
        #expect(observed?.events.first?.arguments == [.unsigned(42)])
        subscription.cancel()
        let raw = runtime_test_descriptor_open()
        defer { _ = runtime_test_descriptor_close(raw) }
        let baseline = runtime_test_matching_descriptor_count(raw)
        unsafe runtime_test_peer_post(peer, 1, raw)
        unsafe runtime_test_peer_post(peer, 2, -1)
        try session.withNativeFrame { #expect(unsafe runtime_test_peer_dispatch(peer) >= 0) }
        #expect(runtime_test_matching_descriptor_count(raw) == baseline)
        #expect(observed != nil && log.values.isEmpty)
        #expect(observed?.events.count == 1 && owner.lifetime.isValid)
        owner.close()
        #expect(observed == nil && log.values == [99])
        #expect(try session.snapshot().runtimeReleases == 1)
    }

    @Test func permanentProxyDropAndRootShutdownDestroyBeforeDisconnect() throws {
        let peer = unsafe try #require(runtime_test_peer_create())
        defer { unsafe runtime_test_peer_destroy(peer) }
        let session = try OwnershipSession()
        let log = ReleaseLog()
        let display = unsafe try session.adopt(nativeIdentifier: 7, kind: .registration) {
            #expect(log.values == [99])
            unsafe runtime_test_peer_disconnect(peer)
        }
        let proxy = unsafe try #require(runtime_test_peer_proxy(peer))
        let owner = unsafe try ClientProxyDispatcher(receiving: proxy, in: session,
                                                    dependencies: [display.reference], context: ProxyContext(log)) { _, _ in }
        let reference = owner.lifetime
        session.requestClose()
        #expect(!reference.isValid && log.values == [99])
        owner.close()
        display.close()
        #expect(try session.snapshot().runtimeReleases == 2)
    }

    @Test func permanentProxyHandlerCloseWaitsForFullNativeFrame() throws {
        let peer = unsafe try #require(runtime_test_peer_create())
        defer { unsafe runtime_test_peer_destroy(peer) }
        let root = try NativeOwnerBox()
        let log = ReleaseLog()
        func attach() throws -> ClientProxyDispatcher<ProxyContext> {
            let context = ProxyContext(log)
            context.action = { [weak root] in _ = root?.requestClose() }
            return unsafe try ClientProxyDispatcher(receiving: runtime_test_peer_proxy(peer), in: root.session,
                                                   context: context) { context, _ in try context.action?() }
        }
        let owner = try attach()
        unsafe runtime_test_peer_post(peer, 0, -1)
        try root.session.withNativeFrame {
            #expect(unsafe runtime_test_peer_dispatch(peer) >= 0)
            #expect(log.values.isEmpty && !owner.lifetime.isValid)
        }
        #expect(log.values == [99])
        owner.close()
    }

    @Test func permanentProxyHandlerFailureStillCleansDescriptor() throws {
        let peer = unsafe try #require(runtime_test_peer_create())
        defer { unsafe runtime_test_peer_destroy(peer) }
        let session = try OwnershipSession()
        let log = ReleaseLog()
        let proxy = unsafe try #require(runtime_test_peer_proxy(peer))
        let owner = unsafe try ClientProxyDispatcher(receiving: proxy, in: session, context: ProxyContext(log)) { _, _ in
            throw BodyFailure.expected
        }
        let raw = runtime_test_descriptor_open()
        defer { _ = runtime_test_descriptor_close(raw) }
        let baseline = runtime_test_matching_descriptor_count(raw)
        unsafe runtime_test_peer_post(peer, 1, raw)
        try session.withNativeFrame { #expect(unsafe runtime_test_peer_dispatch(peer) >= 0) }
        #expect(runtime_test_matching_descriptor_count(raw) == baseline)
        let failure = owner.failure
        #expect(failure as? BodyFailure == .expected)
        owner.close()
        #expect(log.values == [99])
    }

    @Test func permanentProxyProvisionalFailuresConsumeExactlyOnce() throws {
        let session = try OwnershipSession(maximumRecords: 1)
        let log = ReleaseLog()
        var destroys = 0
        do {
            let owner = unsafe try session.receiveProxyDispatcher(nativeIdentifier: 1, context: ProxyContext(log),
                install: { _ in false }, destroy: { destroys += 1 })
            owner.close()
            Issue.record("Failed installation published proxy authority.")
        } catch { #expect(error as? ProxyDispatcherError == .installationFailed) }
        #expect(destroys == 1 && log.values == [99])
        let occupied = unsafe try session.adopt(nativeIdentifier: 8, kind: .registration) {}
        do {
            let owner = unsafe try session.receiveProxyDispatcher(nativeIdentifier: 2, context: ProxyContext(log),
                install: { _ in Issue.record("Installation ran without a cleanup record."); return true },
                destroy: { destroys += 1 })
            owner.close()
        } catch { #expect(error as? OwnershipError == .capacityExceeded) }
        #expect(destroys == 2 && log.values == [99, 99])
        occupied.close()
    }
}

extension DescriptorAndCallbackTests {
    @Test func permanentProxySubscriptionDropAndTenThousandLifecyclesBalance() throws {
        let log = ReleaseLog()
        func cycle() throws {
            let peer = unsafe try #require(runtime_test_peer_create())
            defer { unsafe runtime_test_peer_destroy(peer) }
            let session = try OwnershipSession()
            let proxy = unsafe try #require(runtime_test_peer_proxy(peer))
            let owner = unsafe try ClientProxyDispatcher(receiving: proxy, in: session, context: ProxyContext(log)) { _, _ in
                Issue.record("A dropped subscription delivered an event.")
            }
            do { let subscription = try owner.subscription(); _ = subscription.cancellation }
            unsafe runtime_test_peer_post(peer, 0, -1)
            try session.withNativeFrame { #expect(unsafe runtime_test_peer_dispatch(peer) >= 0) }
            #expect(owner.cancellation.isCancelled && owner.lifetime.isValid)
            owner.close()
            let snapshot = try session.snapshot()
            #expect(snapshot.runtimeReleases == 1 && snapshot.retainedRecords == 0)
        }
        for _ in 0..<10_000 { try cycle() }
        #expect(log.values.count == 10_000)
    }

    @Test func permanentProxyCloseDuringInstallDefersCleanupAndRejectsPublication() throws {
        let root = try NativeOwnerBox()
        let log = ReleaseLog()
        var destroys = 0
        do {
            let owner = unsafe try root.session.receiveProxyDispatcher(nativeIdentifier: 1, context: ProxyContext(log),
                install: { _ in
                    _ = root.requestClose()
                    #expect(destroys == 0 && log.values.isEmpty)
                    return true
                }, destroy: { destroys += 1 })
            owner.close()
            Issue.record("Closed installation published a proxy owner.")
        } catch { #expect(error as? OwnershipError == .closedSession) }
        #expect(destroys == 1 && log.values == [99])
        #expect(try root.session.snapshot().retainedRecords == 0)
    }
}
