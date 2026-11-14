import Testing
import WaylandClient
import WaylandServer
import WaylandProtocol
import WaylandRuntime
import RuntimeNativeTestSupport

private final class RegistryEffectServer {
    let display: ServerDisplay
    var source: ServerObject<WlFixes>?
    var subscription: ServerRequestSubscription?
    var registry: ServerObjectReference<WlRegistry>?
    var calls = 0
    init() throws { display = try ServerDisplay() }
}
extension DescriptorAndCallbackTests {
    @Test func registryArgumentIsConsumedWhenFixesRejectsItsForeignConnection() throws {
        var firstDescriptor: Int32 = -1
        var secondDescriptor: Int32 = -1
        let firstServer = unsafe try #require(runtime_core_server_create(&firstDescriptor))
        let secondServer = unsafe try #require(runtime_test_server_create(&secondDescriptor))
        defer { unsafe runtime_core_server_destroy(firstServer); unsafe runtime_test_server_destroy(secondServer) }
        let first = unsafe try ClientConnection(receiving: firstDescriptor)
        let second = unsafe try ClientConnection(receiving: secondDescriptor)
        let firstRegistry = try first.protocolDisplay().getRegistry()
        let fixes = try firstRegistry.reference.bind(name: unsafe runtime_core_server_global(firstServer, "wl_fixes"),
            as: WlFixes.self, version: 1, advertisedVersion: 1)
        let registry = try second.protocolDisplay().getRegistry()
        let reference = registry.reference
        do {
            try fixes.reference.destroyRegistry(registry: registry)
            Issue.record("A foreign registry was accepted.")
        } catch { #expect(error as? TypedProtocolError == .foreignObject) }
        #expect(!reference.isValid)
        #expect(firstRegistry.lifetime.isValid)
        first.requestClose(); second.requestClose()
        #expect(try first.snapshot().retainedRecords == 0)
        #expect(try second.snapshot().retainedRecords == 0)
    }

    @Test func registryArgumentDestructionSurvivesCancellationThrowAndRootClose() throws {
        for mode in ["cancel", "throw", "close"] {
            var serverDescriptor: Int32 = -1
            var clientDescriptor: Int32 = -1
            #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
            let application = try RegistryEffectServer()
            let client = unsafe try application.display.createClient(receiving: serverDescriptor)
            let global = try application.display.addGlobal(as: WlFixes.self, version: 1) { [weak application] identifier in
                application?.source = try identifier.accept()
            }
            let native = "wl_fixes".withCString { unsafe runtime_core_client_create(clientDescriptor, $0) }
            let peer = unsafe try #require(native)
            defer { unsafe runtime_core_client_destroy(peer) }
            try application.display.dispatch()
            #expect(unsafe runtime_core_client_advertisements(peer) >= 1)
            try application.display.dispatch()
            let clientReference = try client.reference()
            application.registry = try clientReference.object(identifier: 2, as: WlRegistry.self)
            application.subscription = try application.source!.onRequest { [weak application] request in
                guard let application else { return }
                switch consume request {
                case .destroyRegistry(let snapshot):
                    #expect(snapshot.identifier == 2 && snapshot.interfaceName == "wl_registry")
                    #expect(application.registry?.isValid == false)
                    #expect(throws: OwnershipError.invalidHandle) {
                        _ = try clientReference.object(identifier: 2, as: WlRegistry.self)
                    }
                    application.calls += 1
                    if mode == "throw" { throw BodyFailure.expected }
                    if mode == "close" { application.display.requestClose() }
                default: Issue.record("Unexpected fixes request.")
                }
            }
            if mode == "cancel" { application.subscription?.cancel() }
            let identifiers: [UInt32] = [2]
            let result = identifiers.withUnsafeBufferPointer { unsafe runtime_core_client_request(peer, 1, $0.baseAddress, -1, 0) }
            #expect(result >= 0)
            try application.display.dispatch()
            #expect(application.calls == (mode == "cancel" ? 0 : 1))
            #expect(application.registry?.isValid == false)
            if mode == "cancel" {
                #expect(try clientReference.object(identifier: 2, as: WlRegistry.self) == nil)
            }
            withExtendedLifetime(global) {}
            application.display.requestClose()
            #expect(try application.display.snapshot().retainedRecords == 0)
        }
    }
}
