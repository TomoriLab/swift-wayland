import Glibc
import Testing
import RuntimeNativeTestSupport
import WaylandClient
import WaylandRuntime

private final class ClientEvents {
    var events: [ClientEvent] = []
}

extension DescriptorAndCallbackTests {
    @Test func clientRegistryAndSyncInteroperateWithIndependentCServer() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let events = ClientEvents()
        let registry = try connection.registry(context: events) { events, event in events.events.append(event) }
        let sync = try connection.sync(context: events) { events, event in events.events.append(event) }
        let queue = try connection.createQueue()
        try connection.flush()
        #expect(unsafe runtime_test_server_dispatch(server) == 0)
        try connection.withPreparedRead { read in try read.read(); #expect(read.isResolved == true) }
        #expect(try connection.dispatchPending() >= 2)
        #expect(events.events.contains { $0.name == "global" && $0.arguments.contains(.string("wl_compositor")) })
        #expect(events.events.contains { $0.name == "done" })
        connection.requestClose()
        #expect(!registry.lifetime.isValid && !sync.lifetime.isValid && !queue.lifetime.isValid)
        #expect(try connection.snapshot().retainedRecords == 0)
        #expect(try connection.snapshot().runtimeReleases == 4)
    }

    @Test func preparedReadCancelsOnThrowAndRejectsNestedReaders() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        do {
            try connection.withPreparedRead { read in
                #expect(read.isResolved == false)
                #expect(throws: ClientCoordinationError.readAlreadyPrepared) { try connection.dispatchPending() }
                #expect(throws: ClientCoordinationError.readAlreadyPrepared) { try connection.withPreparedRead { _ in } }
                throw BodyFailure.expected
            }
            Issue.record("A throwing prepared-read scope returned normally.")
        } catch { #expect(error as? BodyFailure == .expected) }
        try connection.withPreparedRead { read in
            read.cancel()
            read.cancel()
            #expect(throws: ClientCoordinationError.reservationResolved) { try read.read() }
        }
        try connection.withPreparedRead { _ in }
        connection.requestClose()
        #expect(try connection.snapshot().retainedRecords == 0)
    }

    @Test func preparedReadRootCloseCancelsBeforeDisconnect() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        try connection.withPreparedRead { read in
            #expect(connection.requestClose() == .deferred)
            #expect(runtime_test_descriptor_is_open(descriptor) == 1)
            #expect(throws: OwnershipError.closedSession) { try read.read() }
            #expect(read.isResolved == true)
        }
        #expect(runtime_test_descriptor_is_open(descriptor) == 0)
    }
}

import Dispatch

extension DescriptorAndCallbackTests {
    @Test func clientQueueAssignmentAndDependencyTeardownAreIndependentOfDefaultQueue() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let queue = try connection.createQueue()
        let events = ClientEvents()
        let proxy = try connection.sync(on: queue, context: events) { events, event in events.events.append(event) }
        try connection.flush()
        #expect(unsafe runtime_test_server_dispatch(server) == 0)
        try connection.withPreparedRead(on: queue) { read in try read.read() }
        #expect(try connection.dispatchPending() >= 0)
        #expect(events.events.isEmpty)
        #expect(try connection.dispatchPending(on: queue) == 1)
        #expect(events.events.first?.name == "done")
        queue.close()
        #expect(!proxy.lifetime.isValid)
        proxy.close()
        connection.requestClose()
        #expect(try connection.snapshot().retainedRecords == 0)
    }

    @Test func pollTimeoutAndConcurrentCancellationResolvePreparedReads() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let timeout = try ReadCancellation()
        #expect(try connection.dispatchOnce(timeoutMilliseconds: 0, cancellation: timeout) == 0)
        for _ in 0..<100 {
            let cancellation = try ReadCancellation()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async { cancellation.cancel(); group.leave() }
            do {
                _ = try connection.dispatchOnce(timeoutMilliseconds: 1000, cancellation: cancellation)
                Issue.record("A canceled wait returned normally.")
            } catch { #expect(error is CancellationError) }
            group.wait()
            try connection.withPreparedRead { read in read.cancel() }
        }
        #expect(runtime_test_descriptor_is_open(descriptor) == 1)
        connection.requestClose()
        #expect(runtime_test_descriptor_is_open(descriptor) == 0)
    }

    @Test func readyPollReadsThenDispatchesSyncWithoutLeakingReservation() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let events = ClientEvents()
        let proxy = try connection.sync(context: events) { events, event in events.events.append(event) }
        try connection.flush()
        #expect(unsafe runtime_test_server_dispatch(server) == 0)
        let cancellation = try ReadCancellation()
        #expect(try connection.dispatchOnce(timeoutMilliseconds: 1000, cancellation: cancellation) >= 1)
        #expect(events.events.first?.name == "done")
        proxy.close()
        connection.requestClose()
    }
}

extension DescriptorAndCallbackTests {
    @Test func cancellationSignalMakesItsOwnedWakeDescriptorReadable() throws {
        let cancellation = try ReadCancellation()
        unsafe cancellation.withUnsafeWakeDescriptor { descriptor in
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async { cancellation.cancel(); group.leave() }
            #expect(unsafe Glibc.poll(&pollDescriptor, 1, 1000) == 1)
            #expect(pollDescriptor.revents & Int16(POLLIN) != 0)
            group.wait()
            #expect(cancellation.isCancelled)
        }
    }
}
