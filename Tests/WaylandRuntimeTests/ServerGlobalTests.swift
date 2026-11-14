import Glibc
import Testing
import WaylandRuntime
import WaylandServer
import WaylandProtocol
import RuntimeNativeTestSupport

private final class GlobalObservations {
    var compositor: ServerObject<WlCompositor>?
    var surface: ServerObject<WlSurface>?
    var subscription: ServerRequestSubscription?
    var client: ServerClientReference?
    var withdrawals = 0
    var binds = 0
}
private final class RunningServer { let display: ServerDisplay; init() throws { display = try ServerDisplay() } }

extension DescriptorAndCallbackTests {
    @Test func typedGlobalBindAndWithdrawPreserveOffersAndClientResources() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let observations = GlobalObservations()
        let global = try display.addGlobal(as: WlCompositor.self, version: 1) { [weak observations] identifier in
            guard let observations else { return }
            observations.client = try identifier.clientReference()
            let compositor = try identifier.accept()
            observations.subscription = try compositor.onRequest { [weak observations] request in
                switch consume request {
                case .createSurface(let identifier): observations?.surface = try identifier.accept()
                case .createRegion: break
                case .release: break
                }
            }
            observations.compositor = consume compositor
            observations.binds += 1
        }
        try global.onWithdrawn { observations.withdrawals += 1 }
        let peer = unsafe try #require(runtime_test_global_client_create(clientDescriptor, 1))
        try display.dispatch()
        #expect(unsafe runtime_test_global_client_dispatch(peer) >= 1)
        try display.dispatch()
        #expect(observations.binds == 1 && observations.surface?.lifetime.isValid == true)
        let reference = try client.reference()
        #expect(try reference.snapshot().processIdentifier == getpid())
        #expect(try global.name(for: reference) != 0)
        try global.withdraw()
        try global.withdraw()
        #expect(!global.isWithdrawn && observations.withdrawals == 0)
        try display.flushClients()
        #expect(unsafe runtime_test_global_client_dispatch(peer) >= 1)
        #expect(unsafe runtime_test_global_client_removed(peer) >= 1)
        unsafe runtime_test_global_client_destroy(peer)
        try display.dispatch()
        #expect(global.isWithdrawn && observations.withdrawals == 1)
        #expect(!client.lifetime.isValid && observations.surface?.lifetime.isValid == false)
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }

    @Test func replacingGlobalFilterCannotBeClearedByRetiringItsPredecessor() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        #expect(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let global = try display.addGlobal(as: WlCompositor.self, version: 1) { _ in }
        let old = try display.setGlobalFilter { _, _ in false }
        let replacement = try display.setGlobalFilter { client, global in
            #expect(client.processIdentifier == getpid())
            return global.interfaceName == "wl_compositor" && global.version == 1
        }
        #expect(!old.isAttached && replacement.isAttached)
        old.close()
        #expect(replacement.isAttached == true)
        let peer = unsafe try #require(runtime_test_global_client_create(clientDescriptor, 0))
        defer { unsafe runtime_test_global_client_destroy(peer) }
        try display.dispatch()
        #expect(unsafe runtime_test_global_client_dispatch(peer) >= 1)
        #expect(unsafe runtime_test_global_client_advertised(peer) == 1)
        #expect(client.lifetime.isValid && global.lifetime.isValid)
        replacement.close()
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }

    @Test func namedAcceptedClientIsRootManagedAndIgnoredBindRejectsItsConstructor() throws {
        let display = try ServerDisplay()
        let global = try display.addGlobal(as: WlCompositor.self, version: 1) { _ in }
        var directory = Array("/tmp/waylandkit-global-XXXXXX".utf8CString)
        let directoryPath = try directory.withUnsafeMutableBufferPointer { bytes in
            guard let pointer = unsafe mkdtemp(bytes.baseAddress!) else { throw ServerError.nativeFailure(errno) }
            return unsafe String(cString: pointer)
        }
        let path = directoryPath + "/wayland"
        defer { directoryPath.withCString { _ = unsafe rmdir($0) } }
        try display.addSocket(name: path)
        let peer = path.withCString { unsafe runtime_test_global_client_connect($0, 1) }
        let native = unsafe try #require(peer)
        defer { unsafe runtime_test_global_client_destroy(native) }
        try display.dispatch()
        try display.dispatch()
        #expect(unsafe runtime_test_global_client_dispatch(native) >= 1)
        try display.dispatch()
        #expect(unsafe runtime_test_global_client_dispatch(native) == -1)
        #expect(global.lifetime.isValid)
        #expect(try display.snapshot().retainedRecords == 2)
        display.requestClose()
        #expect(try display.snapshot().retainedRecords == 0)
    }

    @Test func closeInsideNativeRunTerminatesBeforeDeferredDisplayRelease() throws {
        let root = try RunningServer()
        let idle = try root.display.addIdle { [weak root] in
            #expect(root?.display.requestClose() == .deferred)
        }
        try root.display.run()
        #expect(!idle.lifetime.isValid)
        #expect(try root.display.snapshot().retainedRecords == 0)
    }
}
