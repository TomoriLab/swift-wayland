import Testing
import RuntimeNativeTestSupport
import CWaylandServer
import WaylandServer
import WaylandProtocol
import WaylandRuntime

extension DescriptorAndCallbackTests {
    @Test func nativeOwnedRegistryWatchSurvivesMissingCellsAndInvalidatesOnNativeDestruction() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let peer = unsafe try #require(runtime_test_global_client_create(clientDescriptor, 0))
        defer { unsafe runtime_test_global_client_destroy(peer) }
        try display.dispatch()
        #expect(unsafe runtime_test_global_client_dispatch(peer) >= 1)
        let reference = try client.reference()
        func identity() throws -> HandleIdentity {
            let optional = try reference.object(identifier: 2, as: WlRegistry.self)
            let registry = try #require(optional)
            return registry.lifetime.identity
        }
        let first = try identity()
        let optional = try reference.object(identifier: 2, as: WlRegistry.self)
        let registry = try #require(optional)
        #expect(registry.lifetime.identity == first)
        #expect(first.kind == .serverResourceWatch)
        #expect(try display.snapshot().acquisitions == 3)
        unsafe try reference.withUnsafeNativeClient { unsafe runtime_test_client_destroy_resource($0, 2) }
        #expect(!registry.isValid && reference.lifetime.isValid)
        #expect(throws: OwnershipError.invalidHandle) { try registry.snapshot() }
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }

    @Test func borrowedReferenceReusesOwnedResourceIdentityAndCannotRegrantClosedAccess() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        defer { _ = runtime_test_descriptor_close(clientDescriptor) }
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let resource = unsafe try display.createResource(for: client, interface: wayland_kit_callback_interface(), version: 1)
        let reference = try client.reference()
        let optional = try reference.object(identifier: resource.identifier(), as: WlCallback.self)
        let borrowed = try #require(optional)
        #expect(borrowed.lifetime.identity == resource.lifetime.identity)
        #expect(try display.snapshot().acquisitions == 3)
        try client.lifetime.withAccess {
            #expect(resource.requestClose() == .deferred)
            #expect(!borrowed.isValid)
            #expect(throws: OwnershipError.invalidHandle) { try borrowed.snapshot() }
        }
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }
}
