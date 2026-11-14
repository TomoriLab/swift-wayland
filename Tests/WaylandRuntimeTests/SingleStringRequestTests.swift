import Testing
import RuntimeNativeTestSupport
import WaylandClient
import WaylandProtocol
import WaylandRuntime

extension DescriptorAndCallbackTests {
    @Test func singleStringRequestsRejectInvalidPayloadBeforeNativeSend() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_core_server_create(&descriptor))
        defer { unsafe runtime_core_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let name = unsafe runtime_core_server_global(server, "wl_data_source")
        let source = try registry.reference.bind(name: name, as: WlDataSource.self, version: 1, advertisedVersion: 1)
        for payload in ["text/plain\0suffix", String(repeating: "x", count: 4096), String(repeating: "x", count: 4084)] {
            #expect(throws: TypedProtocolError.invalidPayload) {
                try source.reference.offer(mimeType: payload)
            }
        }
        try source.reference.offer(mimeType: "waylandkit-test")
        try connection.flush()
        #expect(unsafe runtime_core_server_dispatch(server) == 0)
        #expect(unsafe runtime_core_server_requests(server) == 1)
        connection.requestClose()
        #expect(try connection.snapshot().retainedRecords == 0)
    }
    @Test func singleStringRequestRejectsClosedOwner() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_core_server_create(&descriptor))
        defer { unsafe runtime_core_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let name = unsafe runtime_core_server_global(server, "wl_data_source")
        let source = try registry.reference.bind(name: name, as: WlDataSource.self, version: 1, advertisedVersion: 1)
        let reference = source.reference
        try reference.offer(mimeType: "waylandkit-test")
        try connection.flush()
        #expect(unsafe runtime_core_server_dispatch(server) == 0)
        _ = source.close()
        #expect(throws: OwnershipError.invalidHandle) { try reference.offer(mimeType: "waylandkit-test") }
        connection.requestClose()
        #expect(try connection.snapshot().retainedRecords == 0)
    }
    @Test func singleStringRequestReportsExistingTransportFailure() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_core_server_create(&descriptor))
        var serverDestroyed = false
        defer { if !serverDestroyed { unsafe runtime_core_server_destroy(server) } }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let name = unsafe runtime_core_server_global(server, "wl_data_source")
        let source = try registry.reference.bind(name: name, as: WlDataSource.self, version: 1, advertisedVersion: 1)
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
        #expect(throws: ClientError.self) { try source.reference.offer(mimeType: "waylandkit-test") }
        connection.requestClose()
        #expect(try connection.snapshot().retainedRecords == 0)
    }
}
