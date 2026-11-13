import Testing
import CWaylandServer
import RuntimeNativeTestSupport
import WaylandRuntime
import WaylandServer

extension DescriptorAndCallbackTests {
    @Test func serverInteroperatesWithCClientAndInvalidatesNativeCascade() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let resource = unsafe try display.createResource(for: client, interface: wayland_kit_callback_interface(), version: 1)
        let identity = try resource.identifier()
        #expect(identity > 0)
        let peer = unsafe try #require(runtime_test_c_client_create(clientDescriptor))
        try display.dispatch()
        #expect(unsafe runtime_test_c_client_dispatch(peer) == 1)
        unsafe runtime_test_c_client_destroy(peer)
        try display.dispatch()
        #expect(!client.lifetime.isValid && !resource.lifetime.isValid)
        #expect(throws: OwnershipError.invalidHandle) { try resource.identifier() }
        let snapshot = try display.snapshot()
        #expect(snapshot.nativeReleases == 2 && snapshot.runtimeReleases == 0)
        #expect(snapshot.retainedRecords == 1)
        resource.close()
        client.close()
        display.requestClose()
        #expect(try display.snapshot().runtimeReleases == 1)
        #expect(try display.snapshot().retainedRecords == 0)
    }

    @Test func serverExplicitAndRootCloseDoNotRepeatNativeDestruction() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        defer { _ = runtime_test_descriptor_close(clientDescriptor) }
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let resource = unsafe try display.createResource(for: client, interface: wayland_kit_callback_interface(), version: 1)
        #expect(resource.requestClose() == .complete)
        resource.close()
        client.close()
        display.requestClose()
        let snapshot = try display.snapshot()
        #expect(snapshot.runtimeReleases == 3 && snapshot.nativeReleases == 0)
        #expect(snapshot.retainedRecords == 0 && runtime_test_descriptor_is_open(serverDescriptor) == 0)
    }

    @Test func nativeCascadeRejectsNonNativeDependentObligations() throws {
        let session = try OwnershipSession()
        let client = unsafe try session.adopt(nativeIdentifier: 1, kind: .serverClient) {}
        let foreign = unsafe try session.adopt(nativeIdentifier: 2, kind: .registration,
                                              dependencies: [client.reference]) {}
        let observer = client.reference.destructionObserver()
        try session.withNativeFrame {
            #expect(throws: OwnershipError.liveDependents) { unsafe try observer.destroyed(serverClientCascade: true) }
            #expect(client.reference.isValid && foreign.reference.isValid)
        }
        foreign.close()
        client.close()
    }
}

private final class ServerBox {
    let display: ServerDisplay
    var idle: ServerIdleSource?
    init() throws { display = try ServerDisplay() }
    func closeIdle() { if let source = idle.take() { source.close() } }
}

extension DescriptorAndCallbackTests {
    @Test func idleSelfCloseAndRootCloseDoNotRemoveNativeSourceTwice() throws {
        let root = try ServerBox()
        var calls = 0
        root.idle = try root.display.addIdle { [weak root] in
            guard let root else { return }
            calls += 1
            root.closeIdle()
            #expect(root.display.requestClose() == .deferred)
        }
        try root.display.dispatch()
        #expect(calls == 1)
        let snapshot = try root.display.snapshot()
        #expect(snapshot.nativeReleases == 1 && snapshot.runtimeReleases == 1 && snapshot.retainedRecords == 0)
    }

    @Test func idleCancellationAndThrowHaveDistinctNativeCompletion() throws {
        let display = try ServerDisplay()
        let canceled = try display.addIdle { Issue.record("Canceled idle source executed.") }
        canceled.close()
        try display.dispatch()
        let throwing = try display.addIdle { throw BodyFailure.expected }
        try display.dispatch()
        #expect(throwing.executions == 1)
        let failure = throwing.failure
        #expect(failure as? BodyFailure == .expected)
        #expect(!throwing.lifetime.isValid)
        throwing.close()
        display.requestClose()
        let snapshot = try display.snapshot()
        #expect(snapshot.runtimeReleases == 2 && snapshot.nativeReleases == 1 && snapshot.retainedRecords == 0)
    }

    @Test func serverRejectsRecursiveDispatchWithoutLeavingSourceLive() throws {
        let root = try ServerBox()
        let source = try root.display.addIdle { [weak root] in
            guard let root else { return }
            #expect(throws: ServerError.recursiveDispatch) { try root.display.dispatch() }
        }
        try root.display.dispatch()
        #expect(source.executions == 1 && !source.lifetime.isValid)
        source.close()
    }
}

extension DescriptorAndCallbackTests {
    @Test func serverClientRegistrationFailureConsumesSocketAndRollsBackNativeClient() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        defer { _ = runtime_test_descriptor_close(clientDescriptor) }
        let display = try ServerDisplay(maximumRecords: 1)
        do {
            let unexpected = unsafe try display.createClient(receiving: serverDescriptor)
            unexpected.close()
            Issue.record("A full display accepted another cleanup record.")
        } catch { #expect(error as? OwnershipError == .capacityExceeded) }
        #expect(runtime_test_descriptor_is_open(serverDescriptor) == 0)
        #expect(try display.snapshot().retainedRecords == 1)
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }
}

extension DescriptorAndCallbackTests {
    @Test func nativeClientCascadeCannotConsumeAnotherClientRecord() throws {
        let session = try OwnershipSession()
        let first = unsafe try session.adopt(nativeIdentifier: 1, kind: .serverClient) {}
        let second = unsafe try session.adopt(nativeIdentifier: 2, kind: .serverClient, dependencies: [first.reference]) {}
        let observer = first.reference.destructionObserver()
        try session.withNativeFrame {
            #expect(throws: OwnershipError.liveDependents) { unsafe try observer.destroyed(serverClientCascade: true) }
            #expect(first.reference.isValid && second.reference.isValid)
            let snapshot = try session.snapshot()
            #expect(snapshot.nativeReleases == 0)
        }
        second.close()
        first.close()
    }
}
