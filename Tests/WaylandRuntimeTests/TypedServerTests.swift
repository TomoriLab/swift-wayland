import Glibc
import Testing
import RuntimeNativeTestSupport
import WaylandServer
import WaylandProtocol
import WaylandRuntime

private final class AcceptedSurface {
    var surface: ServerObject<WlSurface>?
    var pool: ServerObject<WlShmPool>?
    var descriptor: BorrowedFileDescriptor?
}

extension DescriptorAndCallbackTests {
    @Test func typedServerConstructorAndDestructorUseOneResourceRecord() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let peer = unsafe try #require(runtime_test_typed_client_create(clientDescriptor, 0))
        defer { unsafe runtime_test_typed_client_destroy(peer) }
        let compositor = unsafe try client.receiveConstructor(identifier: 2, as: WlCompositor.self, version: 1)
        let accepted = AcceptedSurface()
        let subscription = try compositor.onRequest { request in
            switch consume request {
            case .createSurface(let identifier): accepted.surface = try identifier.accept()
            case .createRegion: break
            case .release: break
            }
        }
        #expect(unsafe runtime_test_typed_client_construct(peer, -1) >= 0)
        try display.dispatch()
        #expect(accepted.surface?.lifetime.isValid == true)
        #expect(unsafe runtime_test_typed_client_destroy_child(peer) >= 0)
        try display.dispatch()
        #expect(accepted.surface?.lifetime.isValid == false)
        accepted.surface = nil
        withExtendedLifetime(subscription) {}
        display.requestClose()
        let snapshot = try display.snapshot()
        #expect(snapshot.retainedRecords == 0 && snapshot.acquisitions == snapshot.runtimeReleases + snapshot.nativeReleases)
    }

    @Test func typedServerReceivedDescriptorAndConstructorDropRejectWithoutLeaks() throws {
        for cancel in [false, true] {
            let raw = runtime_test_descriptor_open()
            defer { _ = runtime_test_descriptor_close(raw) }
            let count = runtime_test_matching_descriptor_count(raw)
            var serverDescriptor: Int32 = -1
            var clientDescriptor: Int32 = -1
            #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
            let display = try ServerDisplay()
            let client = unsafe try display.createClient(receiving: serverDescriptor)
            let peer = unsafe try #require(runtime_test_typed_client_create(clientDescriptor, 1))
            defer { unsafe runtime_test_typed_client_destroy(peer) }
            let shm = unsafe try client.receiveConstructor(identifier: 2, as: WlShm.self, version: 1)
            let accepted = AcceptedSurface()
            let subscription = try shm.onRequest { request in
                switch consume request {
                case .createPool(let identifier, let descriptor, let size):
                    #expect(size == 17)
                    accepted.descriptor = descriptor.borrowed
                    _ = consume descriptor
                    accepted.pool = try identifier.accept()
                    throw BodyFailure.expected
                case .release: break
                }
            }
            if cancel { subscription.cancel() }
            #expect(unsafe runtime_test_typed_client_construct(peer, raw) >= 0)
            try display.dispatch()
            #expect(!client.lifetime.isValid)
            #expect(accepted.descriptor?.snapshot.closeAttempts == (cancel ? nil : 1))
            #expect(runtime_test_matching_descriptor_count(raw) == count)
            if !cancel { #expect(shm.failure != nil) }
            accepted.pool = nil
            withExtendedLifetime(subscription) {}
            display.requestClose()
            #expect(try display.snapshot().retainedRecords == 0)
        }
    }

    @Test func typedServerEventDescriptorBorrowAndNewResourceReachIndependentCClient() throws {
        for kind: UInt32 in [2, 3] {
            var serverDescriptor: Int32 = -1
            var clientDescriptor: Int32 = -1
            #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
            let display = try ServerDisplay()
            let client = unsafe try display.createClient(receiving: serverDescriptor)
            let peer = unsafe try #require(runtime_test_typed_client_create(clientDescriptor, kind))
            defer { unsafe runtime_test_typed_client_destroy(peer) }
            if kind == 2 {
                let keyboard = unsafe try client.receiveConstructor(identifier: 2, as: WlKeyboard.self, version: 1)
                let descriptorSession = try OwnershipSession()
                let raw = runtime_test_descriptor_open()
                let descriptor = unsafe try descriptorSession.adoptFileDescriptor(raw)
                try keyboard.reference.keymap(format: .xkbV1, descriptor: descriptor.borrowed, size: 17)
                try display.dispatch()
                #expect(unsafe runtime_test_typed_client_dispatch(peer) >= 1)
                #expect(unsafe runtime_test_typed_client_descriptors(peer) == 1)
                #expect(runtime_test_descriptor_is_open(raw) == 1)
                descriptor.close()
            } else {
                let device = unsafe try client.receiveConstructor(identifier: 2, as: WlDataDevice.self, version: 1)
                let offer = try client.createObject(as: WlDataOffer.self, version: 1)
                try device.reference.dataOffer(identifier: offer.reference)
                try offer.reference.offer(mimeType: "text/plain")
                try display.dispatch()
                #expect(unsafe runtime_test_typed_client_dispatch(peer) >= 2)
                #expect(unsafe runtime_test_typed_client_offers(peer) == 1)
                #expect(unsafe runtime_test_typed_client_destroy_child(peer) >= 0)
                try display.dispatch()
                #expect(!offer.lifetime.isValid)
            }
            display.requestClose()
            #expect(try display.snapshot().retainedRecords == 0)
        }
    }
}

extension DescriptorAndCallbackTests {
    @Test func typedServerPartialDecodeFailureRejectsPendingConstructorAndClosesIncomingDescriptor() throws {
        for capacity in [3, 4] {
        let raw = runtime_test_descriptor_open()
        defer { _ = runtime_test_descriptor_close(raw) }
        let count = runtime_test_matching_descriptor_count(raw)
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay(maximumRecords: capacity)
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let peer = unsafe try #require(runtime_test_typed_client_create(clientDescriptor, 1))
        defer { unsafe runtime_test_typed_client_destroy(peer) }
        let shm = unsafe try client.receiveConstructor(identifier: 2, as: WlShm.self, version: 1)
        let subscription = try shm.onRequest { request in
            switch consume request {
            case .createPool(let identifier, let descriptor, _):
                let pool = try identifier.accept()
                _ = consume descriptor
                _ = consume pool
            case .release: break
            }
        }
        #expect(unsafe runtime_test_typed_client_construct(peer, raw) >= 0)
        try display.dispatch()
        #expect(!client.lifetime.isValid && !shm.lifetime.isValid)
        #expect(shm.failure as? OwnershipError == .capacityExceeded)
        #expect(runtime_test_matching_descriptor_count(raw) == count)
        display.requestClose()
        let snapshot = try display.snapshot()
        #expect(snapshot.acquisitions == UInt64(capacity) && snapshot.retainedRecords == 0)
        withExtendedLifetime(subscription) {}
        }
    }
}
