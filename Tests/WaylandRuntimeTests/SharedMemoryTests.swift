import Testing
import RuntimeNativeTestSupport
import WaylandServer
import WaylandProtocol
import WaylandRuntime

extension DescriptorAndCallbackTests {
    @Test func sharedMemorySnapshotsOmitPaddingAndExternalReferencesSurviveClientDestruction() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        try display.initializeSharedMemory()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let peer = unsafe try #require(runtime_test_shm_client_create(clientDescriptor))
        defer { unsafe runtime_test_shm_client_destroy(peer) }
        try display.dispatch()
        #expect(unsafe runtime_test_shm_client_dispatch(peer) >= 0)
        let identifier = unsafe runtime_test_shm_client_buffer(peer)
        try display.dispatch()
        let clientReference = try client.reference()
        let optional = try clientReference.object(identifier: identifier, as: WlBuffer.self)
        let resource = try #require(optional)
        let buffer = try display.sharedMemoryBuffer(for: resource)
        let second = try buffer.reference()
        #expect(buffer.lifetime.identity != second.lifetime.identity)
        let pool = try buffer.referencePool()
        let anotherPool = try buffer.referencePool()
        #expect(pool.lifetime.identity != anotherPool.lifetime.identity)
        let metadata = try buffer.metadata()
        #expect(metadata.width == 2 && metadata.height == 2 && metadata.stride == 12)
        #expect(try buffer.snapshot() == Array(UInt8(1)...UInt8(16)))
        #expect(throws: SharedMemoryError.quotaExceeded) { _ = try buffer.snapshot(maximumBytes: 15) }
        unsafe runtime_test_shm_client_resize(peer)
        try display.dispatch()
        #expect(try second.snapshot() == Array(UInt8(1)...UInt8(16)))
        #expect(pool.requestClose() == .complete)
        #expect(anotherPool.requestClose() == .complete)
        #expect(try buffer.snapshot() == Array(UInt8(1)...UInt8(16)))
        #expect(client.requestClose() == .complete)
        #expect(!resource.isValid && buffer.lifetime.isValid && second.lifetime.isValid)
        #expect(throws: OwnershipError.invalidHandle) { _ = try buffer.metadata() }
        #expect(throws: OwnershipError.invalidHandle) { _ = try second.snapshot() }
        #expect(buffer.requestClose() == .complete)
        #expect(second.requestClose() == .complete)
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }

    @Test func sharedMemoryFailedPublicationRollsBackItsNativeIncrement() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay(maximumRecords: 3)
        try display.initializeSharedMemory()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let peer = unsafe try #require(runtime_test_shm_client_create(clientDescriptor))
        defer { unsafe runtime_test_shm_client_destroy(peer) }
        try display.dispatch()
        #expect(unsafe runtime_test_shm_client_dispatch(peer) >= 0)
        let identifier = unsafe runtime_test_shm_client_buffer(peer)
        try display.dispatch()
        let reference = try client.reference()
        let optional = try reference.object(identifier: identifier, as: WlBuffer.self)
        let resource = try #require(optional)
        #expect(throws: OwnershipError.capacityExceeded) { _ = try display.sharedMemoryBuffer(for: resource) }
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }
}
