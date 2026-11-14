import Testing
import WaylandClient
import WaylandServer
import WaylandProtocol
import RuntimeNativeTestSupport

private enum ExternalMarker: ClientInterface, ServerInterface {
    static var interfaceName: String { preconditionFailure("External marker getters must never authorize native metadata.") }
    enum Event: ~Copyable {}
    enum Request: ~Copyable {}
    static func decodeEvent(_ reader: inout ClientMessageReader) throws -> Event { throw CoreInterfaceError.unsupportedMarker }
    static func decodeRequest(_ reader: inout ServerMessageReader) throws -> Request { throw CoreInterfaceError.unsupportedMarker }
}
extension DescriptorAndCallbackTests {
    @Test func externalProtocolConformanceCannotAuthorizeNativeDescriptorsOrInvokeItsNameGetter() throws {
        #expect(throws: CoreInterfaceError.unsupportedMarker) { _ = try CoreProtocol.requireSchema(for: ExternalMarker.self) }
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        #expect(throws: CoreInterfaceError.unsupportedMarker) {
            _ = try registry.reference.bind(name: 1, as: ExternalMarker.self, version: 1, advertisedVersion: 1)
        }
        #expect(try connection.snapshot().acquisitions == 2)
        connection.requestClose()
        let display = try ServerDisplay()
        #expect(throws: CoreInterfaceError.unsupportedMarker) {
            _ = try display.addGlobal(as: ExternalMarker.self, version: 1) { pending in _ = consume pending }
        }
        #expect(try display.snapshot().acquisitions == 1)
        display.requestClose()
    }
}
