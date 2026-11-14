import Glibc
import Testing
import WaylandRuntime
import WaylandServer
import WaylandProtocol
import RuntimeNativeTestSupport

private final class ObservedServerEvents { var messages: [ServerProtocolObservation] = []; var destroyed: [ServerClientSnapshot] = [] }
extension DescriptorAndCallbackTests {
    @Test func protocolLoggerCopiesNativeMessagesAndClientResourceSnapshots() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let reference = try client.reference()
        let events = ObservedServerEvents()
        try reference.onDestroyed { events.destroyed.append($0); #expect(!reference.lifetime.isValid) }
        let logger = try display.addProtocolLogger { events.messages.append($0) }
        let peer = unsafe try #require(runtime_test_c_client_create(clientDescriptor))
        defer { unsafe runtime_test_c_client_destroy(peer) }
        try display.dispatch()
        #expect(unsafe runtime_test_c_client_dispatch(peer) == 1)
        #expect(events.messages.contains { $0.direction == .request && $0.messageName == "sync" && $0.arguments.contains(.newIdentifier(2)) })
        #expect(events.messages.contains { $0.direction == .event && $0.messageName == "done" })
        #expect(try display.clientSnapshots().count == 1)
        #expect(try reference.resourceSnapshots().contains { $0.interfaceName == "wl_display" && $0.identifier == 1 })
        logger.close()
        client.close()
        #expect(events.destroyed.count == 1)
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }

    @Test func externallyPreparedSocketIsConsumedOnSuccessAndRegistrationFailure() throws {
        for capacity in [1, 2] {
            var directory = Array("/tmp/waylandkit-socket-XXXXXX".utf8CString)
            let directoryPath = try directory.withUnsafeMutableBufferPointer { bytes in
                guard let pointer = unsafe mkdtemp(bytes.baseAddress!) else { throw ServerError.nativeFailure(errno) }
                return unsafe String(cString: pointer)
            }
            let path = directoryPath + "/socket"
            defer { path.withCString { _ = unsafe unlink($0) }; directoryPath.withCString { _ = unsafe rmdir($0) } }
            let descriptor = path.withCString { unsafe runtime_test_listening_socket($0) }
            #expect(descriptor >= 0)
            let display = try ServerDisplay(maximumRecords: capacity)
            do {
                let socket = unsafe try display.addListeningSocket(receiving: descriptor)
                #expect(capacity == 2 && socket.lifetime.isValid)
                socket.close()
            } catch { #expect(capacity == 1 && error as? OwnershipError == .capacityExceeded) }
            #expect(runtime_test_descriptor_is_open(descriptor) == 0)
            display.requestClose()
            #expect(try display.snapshot().retainedRecords == 0)
        }
    }
}

private final class ResourceDestructionObservations { var snapshot: ServerResourceSnapshot? }
extension DescriptorAndCallbackTests {
    @Test func literalResourceErrorInvalidatesClientBeforeCopiedDestroyNotification() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let peer = unsafe try #require(runtime_test_typed_client_create(clientDescriptor, 0))
        defer { unsafe runtime_test_typed_client_destroy(peer) }
        let compositor = unsafe try client.receiveConstructor(identifier: 2, as: WlCompositor.self, version: 1)
        let reference = compositor.reference
        let clientLifetime = client.lifetime
        let observations = ResourceDestructionObservations()
        try compositor.onDestroyed { snapshot in
            observations.snapshot = snapshot
            #expect(!reference.isValid && !clientLifetime.isValid)
        }
        try display.setDefaultMaximumBufferSize(0)
        try client.reference().setMaximumBufferSize(0)
        try reference.postError(code: 42, message: "Literal %s %n error")
        #expect(!reference.isValid)
        #expect(unsafe runtime_test_typed_client_dispatch(peer) == -1)
        #expect(unsafe runtime_test_typed_client_protocol_error(peer) == 42)
        #expect(observations.snapshot?.identifier == 2)
        #expect(compositor.destructionSnapshot?.interfaceName == "wl_compositor")
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }
}
