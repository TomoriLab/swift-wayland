import Testing
import WaylandClient
import WaylandRuntime
import WaylandProtocol
import RuntimeNativeTestSupport

private final class CapturedOwner {
    var owner: ClientObject<WlDataOffer>?
    var subscription: CallbackSubscription?
}

extension DescriptorAndCallbackTests {
    @Test func explicitRootClosureBreaksAUserHandlerOwnerCaptureCycle() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_core_server_create(&descriptor))
        defer { unsafe runtime_core_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        weak var observed: CapturedOwner?
        func install() throws {
            let captured = CapturedOwner()
            observed = captured
            let name = unsafe runtime_core_server_global(server, "wl_data_offer")
            let owner = try registry.reference.bind(name: name, as: WlDataOffer.self, version: 3, advertisedVersion: 3)
            captured.subscription = try owner.onEvent { [captured] event in
                _ = consume event
                withExtendedLifetime(captured) {}
            }
            captured.owner = consume owner
        }
        try install()
        #expect(observed != nil)
        observed?.subscription?.cancel()
        #expect(observed != nil)
        connection.requestClose()
        #expect(observed == nil)
        #expect(try connection.snapshot().retainedRecords == 0)
    }
}

extension DescriptorAndCallbackTests {
    @Test func subscriptionAfterRootClosureRejectsBeforeReadingRetiredContext() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_core_server_create(&descriptor))
        defer { unsafe runtime_core_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let name = unsafe runtime_core_server_global(server, "wl_data_offer")
        let owner = try registry.reference.bind(name: name, as: WlDataOffer.self, version: 3, advertisedVersion: 3)
        connection.requestClose()
        #expect(!owner.lifetime.isValid)
        #expect(throws: OwnershipError.self) {
            let subscription = try owner.onEvent { event in _ = consume event }
            withExtendedLifetime(subscription) {}
        }
        #expect(try connection.snapshot().retainedRecords == 0)
    }
}
