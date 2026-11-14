import Testing
import RuntimeNativeTestSupport
import WaylandProtocol
import WaylandRuntime
import WaylandServer

private final class ServerArenaObservation { weak var bundle: ProtocolDescriptorBundle? }
private final class ServerRequestObservation { var count = 0 }
private final class ServerChildObservation { var child: ServerProtocolObject? }
private final class GeneratedServerObservation { var parent: ExtensionFixtureWaylandkitParentServer? }

extension DescriptorAndCallbackTests {
    @Test func generatedExtensionServerFacadesRoundtripWithIndependentClient() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let peer = unsafe try #require(runtime_extension_server_client_create(clientDescriptor))
        defer { unsafe runtime_extension_server_client_destroy(peer) }
        let bundle = try ProtocolDescriptorBundle(interfaces: ExtensionFixture.interfaces)
        let raw = unsafe try client.receiveProtocolConstructor(identifier: 2,
            descriptor: bundle.interface(named: "waylandkit_parent"), version: 2)
        let parent = try ExtensionFixtureWaylandkitParentServer(raw)
        let reference = parent.reference
        let calls = ServerRequestObservation()
        let subscription = try parent.onRequest { request in
            switch consume request {
            case .emit(let kind):
                #expect(kind == 0)
                calls.count += 1
                try reference.scalar(value: 17)
            default: Issue.record("Unexpected generated server request.")
            }
        }
        #expect(unsafe runtime_extension_server_client_request(peer) >= 0)
        try display.dispatch()
        #expect(unsafe runtime_extension_server_client_dispatch(peer) >= 1)
        #expect(unsafe runtime_extension_server_client_events(peer) == 1 && calls.count == 1)
        withExtendedLifetime(subscription) {}
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }

    @Test func managedExtensionServerResourcePinsArenaAndHandlesIndependentClient() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let peer = unsafe try #require(runtime_extension_server_client_create(clientDescriptor))
        defer { unsafe runtime_extension_server_client_destroy(peer) }
        let observation = ServerArenaObservation()
        let resource: ServerProtocolObject = try {
            let bundle = try ProtocolDescriptorBundle(interfaces: ExtensionFixture.interfaces)
            observation.bundle = bundle
            let descriptor = try bundle.interface(named: "waylandkit_parent")
            return unsafe try client.receiveProtocolConstructor(identifier: 2, descriptor: descriptor, version: 2)
        }()
        #expect(observation.bundle != nil)
        let calls = ServerRequestObservation()
        let reference = resource.reference
        let subscription = try resource.onRequest { reader in
            let argument = try reader.unsigned(0)
            #expect(reader.opcode == 2 && argument == 0)
            calls.count += 1
            try reference.send(opcode: 0, arguments: [.unsigned(17)])
        }
        #expect(unsafe runtime_extension_server_client_request(peer) >= 0)
        try display.dispatch()
        try display.flushClients()
        #expect(unsafe runtime_extension_server_client_dispatch(peer) >= 1)
        let events = unsafe runtime_extension_server_client_events(peer)
        #expect(calls.count == 1 && events == 1)
        #expect(resource.failure == nil && resource.lifetime.isValid)
        resource.close()
        #expect(!reference.isValid && observation.bundle == nil)
        withExtendedLifetime(subscription) {}
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }
}

extension DescriptorAndCallbackTests {
    @Test func managedExtensionServerGlobalBindsThroughIndependentRegistry() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let bundle = try ProtocolDescriptorBundle(interfaces: ExtensionFixture.interfaces)
        let descriptor = try bundle.interface(named: "waylandkit_parent")
        let accepted = GeneratedServerObservation()
        let global = try display.addWaylandkitParentGlobal(descriptor: descriptor, version: 2) { identifier in
            accepted.parent = try identifier.accept()
        }
        let peer = unsafe try #require(runtime_extension_server_client_prepare_global(clientDescriptor))
        defer { unsafe runtime_extension_server_client_destroy(peer) }
        try display.dispatch()
        let name = try global.name(for: client.reference())
        #expect(name != 0)
        #expect(unsafe runtime_extension_server_client_bind(peer, name) >= 0)
        try display.dispatch()
        #expect(accepted.parent?.isValid == true)
        let reference = accepted.parent?.reference
        let subscription = try accepted.parent!.onRequest { request in
            switch consume request {
            case .emit(let kind):
                #expect(kind == 0)
                try reference?.scalar(value: 17)
            default: Issue.record("Unexpected generated global request.")
            }
        }
        #expect(unsafe runtime_extension_server_client_request(peer) >= 0)
        try display.dispatch()
        #expect(unsafe runtime_extension_server_client_dispatch(peer) >= 1)
        #expect(unsafe runtime_extension_server_client_events(peer) == 1)
        try global.withdraw()
        global.close()
        withExtendedLifetime(subscription) {}
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }

    @Test func importedGlobalRejectsMatchingNameFromDifferentArena() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let advertised = try ProtocolDescriptorBundle(interfaces: ExtensionFixture.interfaces)
        let foreign = try ProtocolDescriptorBundle(interfaces: ExtensionFixture.interfaces)
        let global = try display.addProtocolGlobal(descriptor: advertised.interface(named: "waylandkit_parent"), version: 2) { identifier in
            _ = try identifier.accept(descriptor: foreign.interface(named: "waylandkit_parent"))
        }
        let peer = unsafe try #require(runtime_extension_server_client_prepare_global(clientDescriptor))
        defer { unsafe runtime_extension_server_client_destroy(peer) }
        try display.dispatch()
        let name = try global.name(for: client.reference())
        #expect(unsafe runtime_extension_server_client_bind(peer, name) >= 0)
        try display.dispatch()
        #expect(!client.lifetime.isValid)
        #expect(global.failure as? ServerProtocolError == .invalidMessage)
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }
}

extension DescriptorAndCallbackTests {
    @Test func managedExtensionServerConstructorUsesOriginatingArena() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let peer = unsafe try #require(runtime_extension_server_client_create(clientDescriptor))
        defer { unsafe runtime_extension_server_client_destroy(peer) }
        let bundle = try ProtocolDescriptorBundle(interfaces: ExtensionFixture.interfaces)
        let parentDescriptor = try bundle.interface(named: "waylandkit_parent")
        let childDescriptor = try bundle.interface(named: "waylandkit_child")
        let parent = unsafe try client.receiveProtocolConstructor(identifier: 2, descriptor: parentDescriptor, version: 2)
        let captured = ServerChildObservation()
        let subscription = try parent.onRequest { reader in
            #expect(reader.opcode == 0)
            let identifier = try reader.protocolConstructor(0)
            captured.child = try identifier.accept(descriptor: childDescriptor)
        }
        #expect(unsafe runtime_extension_server_client_construct(peer) >= 0)
        try display.dispatch()
        #expect(captured.child?.lifetime.isValid == true)
        #expect(unsafe runtime_extension_server_client_destroy_child(peer) >= 0)
        try display.dispatch()
        #expect(captured.child?.lifetime.isValid == false)
        captured.child = nil
        withExtendedLifetime(subscription) {}
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }

    @Test func canceledExtensionServerConstructorRejectsClientWithoutResourceLeak() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let peer = unsafe try #require(runtime_extension_server_client_create(clientDescriptor))
        defer { unsafe runtime_extension_server_client_destroy(peer) }
        let bundle = try ProtocolDescriptorBundle(interfaces: ExtensionFixture.interfaces)
        let parent = unsafe try client.receiveProtocolConstructor(identifier: 2,
            descriptor: bundle.interface(named: "waylandkit_parent"), version: 2)
        let subscription = try parent.onRequest { _ in Issue.record("Canceled request reached user handler.") }
        subscription.cancel()
        #expect(unsafe runtime_extension_server_client_construct(peer) >= 0)
        try display.dispatch()
        #expect(!client.lifetime.isValid && !parent.lifetime.isValid)
        withExtendedLifetime(subscription) {}
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }
}
