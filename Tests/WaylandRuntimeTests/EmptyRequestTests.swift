import Testing
import RuntimeNativeTestSupport
import WaylandClient
import WaylandProtocol
import WaylandRuntime

extension DescriptorAndCallbackTests {
    @Test func emptyRequestRejectsUnsupportedVersionWithoutSending() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_core_server_create(&descriptor))
        defer { unsafe runtime_core_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let offerName = unsafe runtime_core_server_global(server, "wl_data_offer")
        let offer = try registry.reference.bind(name: offerName, as: WlDataOffer.self, version: 1, advertisedVersion: 3)
        let surfaceName = unsafe runtime_core_server_global(server, "wl_surface")
        let surface = try registry.reference.bind(name: surfaceName, as: WlSurface.self, version: 1, advertisedVersion: 1)
        try connection.flush()
        #expect(unsafe runtime_core_server_dispatch(server) == 0)
        let before = unsafe runtime_core_server_requests(server)
        #expect(throws: TypedProtocolError.unsupportedVersion) { try offer.reference.finish() }
        // A valid request ensures the peer is dispatched after the rejected operation.
        try surface.reference.commit()
        try connection.flush()
        #expect(unsafe runtime_core_server_dispatch(server) == 0)
        #expect(unsafe runtime_core_server_requests(server) == before + 1)
        #expect(unsafe String(cString: runtime_core_server_interface(server)!) == "wl_surface")
        connection.requestClose()
        #expect(try connection.snapshot().retainedRecords == 0)
    }

    @Test func emptyRequestRejectsClosedOwnerDespiteCachedEligibility() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_core_server_create(&descriptor))
        defer { unsafe runtime_core_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let name = unsafe runtime_core_server_global(server, "wl_surface")
        let surface = try registry.reference.bind(name: name, as: WlSurface.self, version: 1, advertisedVersion: 1)
        let reference = surface.reference
        try reference.commit()
        try connection.flush()
        #expect(unsafe runtime_core_server_dispatch(server) == 0)
        _ = surface.close()
        #expect(throws: OwnershipError.invalidHandle) { try reference.commit() }
        connection.requestClose()
        #expect(try connection.snapshot().retainedRecords == 0)
    }
    @Test func emptyRequestReportsExistingTransportFailure() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_core_server_create(&descriptor))
        var serverDestroyed = false
        defer { if !serverDestroyed { unsafe runtime_core_server_destroy(server) } }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let name = unsafe runtime_core_server_global(server, "wl_surface")
        let surface = try registry.reference.bind(name: name, as: WlSurface.self, version: 1, advertisedVersion: 1)
        try connection.flush()
        #expect(unsafe runtime_core_server_dispatch(server) == 0)
        unsafe runtime_core_server_destroy(server)
        serverDestroyed = true
        var failed = false
        for _ in 0..<3 where !failed {
            do { _ = try connection.readAndDispatchPending() }
            catch { failed = true }
        }
        #expect(failed)
        #expect(throws: ClientError.self) { try surface.reference.commit() }
        connection.requestClose()
        #expect(try connection.snapshot().retainedRecords == 0)
    }
}
