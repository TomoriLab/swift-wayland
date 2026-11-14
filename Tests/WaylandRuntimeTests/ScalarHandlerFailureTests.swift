import Testing
import RuntimeNativeTestSupport
import WaylandClient
import WaylandProtocol

extension DescriptorAndCallbackTests {
    @Test func scalarHandlerFailureRemainsObservableAfterNativeDispatch() throws {
        var socket: Int32 = -1
        let server = unsafe try #require(runtime_core_server_create(&socket))
        defer { unsafe runtime_core_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: socket)
        let registry = try connection.protocolDisplay().getRegistry()
        let name = unsafe runtime_core_server_global(server, "wl_data_offer")
        let source = try registry.reference.bind(name: name, as: WlDataOffer.self, version: 3, advertisedVersion: 3)
        let identifier = try source.reference.identifier()
        let subscription = try source.onEvent { _ in throw BodyFailure.expected }
        try connection.flush()
        #expect(unsafe runtime_core_server_dispatch(server) == 0)
        let objects = [UInt32](repeating: 0, count: 20)
        objects.withUnsafeBufferPointer { identifiers in
            unsafe runtime_core_server_event(server, identifier, 2, identifiers.baseAddress, -1, 0)
        }
        try connection.withPreparedRead { try $0.read() }
        _ = try connection.dispatchPending()
        #expect(source.failure is BodyFailure)
        withExtendedLifetime(subscription) {}
        withExtendedLifetime(registry) {}
        withExtendedLifetime(source) {}
        connection.requestClose()
        #expect(try connection.snapshot().retainedRecords == 0)
    }
}
