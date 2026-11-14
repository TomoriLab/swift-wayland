import Glibc
import Testing
import RuntimeNativeTestSupport
import WaylandClient
import WaylandProtocol
import WaylandRuntime

private final class TypedObservations {
    var globals: [String: UInt32] = [:]
    var descriptors = 0
    var offers = 0
    var done = false
}

extension DescriptorAndCallbackTests {
    @Test func typedConstructorsDestructorsAndTerminalEvents() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let observations = TypedObservations()
        let registry = try connection.protocolDisplay().getRegistry()
        let subscription = try registry.onEvent { event in
            switch consume event {
            case .global(let name, let interface, _): observations.globals[interface] = name
            case .globalRemove: break
            }
        }
        try connection.flush()
        #expect(unsafe runtime_test_server_dispatch(server) == 0)
        try connection.withPreparedRead { try $0.read() }
        _ = try connection.dispatchPending()
        let compositor = try registry.reference.bind(name: #require(observations.globals["wl_compositor"]), as: WlCompositor.self, version: 1, advertisedVersion: 1)
        let surface = try compositor.reference.createSurface()
        let reference = surface.reference
        try surface.destroy()
        #expect(!reference.isValid)
        #expect(throws: (any Error).self) { try reference.commit() }
        let callback = try connection.protocolDisplay().sync()
        let callbackSubscription = try callback.onEvent { event in
            switch consume event { case .done: observations.done = true }
        }
        try connection.flush()
        #expect(unsafe runtime_test_server_dispatch(server) == 0)
        try connection.withPreparedRead { try $0.read() }
        _ = try connection.dispatchPending()
        #expect(observations.done && !callback.lifetime.isValid)
        withExtendedLifetime(subscription) {}
        withExtendedLifetime(callbackSubscription) {}
        connection.requestClose()
        #expect(try connection.snapshot().retainedRecords == 0)
    }

    @Test func typedReceivedDescriptorsAndConstructorsAreCleanedAfterCancellationAndThrow() throws {
        for cancel in [false, true] {
            let oracle = runtime_test_descriptor_open()
            defer { _ = runtime_test_descriptor_close(oracle) }
            let descriptorCount = runtime_test_matching_descriptor_count(oracle)
            var descriptor: Int32 = -1
            let server = unsafe try #require(runtime_test_server_create(&descriptor))
            defer { unsafe runtime_test_server_destroy(server) }
            unsafe runtime_test_server_add_typed_globals(server)
            let connection = unsafe try ClientConnection(receiving: descriptor)
            let observations = TypedObservations()
            let registry = try connection.protocolDisplay().getRegistry()
            let subscription = try registry.onEvent { event in
                switch consume event {
                case .global(let name, let interface, _): observations.globals[interface] = name
                case .globalRemove: break
                }
            }
            try connection.flush()
            #expect(unsafe runtime_test_server_dispatch(server) == 0)
            try connection.withPreparedRead { try $0.read() }
            _ = try connection.dispatchPending()
            let keyboard = try registry.reference.bind(name: #require(observations.globals["wl_keyboard"]), as: WlKeyboard.self, version: 1, advertisedVersion: 1)
            let device = try registry.reference.bind(name: #require(observations.globals["wl_data_device"]), as: WlDataDevice.self, version: 1, advertisedVersion: 1)
            let keyboardSubscription = try keyboard.onEvent { event in
                switch consume event {
                case .keymap(_, let descriptor, let size):
                    #expect(size == 17)
                    _ = consume descriptor
                    observations.descriptors += 1
                    throw BodyFailure.expected
                default: break
                }
            }
            let deviceSubscription = try device.onEvent { event in
                switch consume event {
                case .dataOffer(let offer):
                    #expect(offer.lifetime.isValid)
                    _ = consume offer
                    observations.offers += 1
                    throw BodyFailure.expected
                default: break
                }
            }
            if cancel { keyboardSubscription.cancel(); deviceSubscription.cancel() }
            try connection.flush()
            #expect(unsafe runtime_test_server_dispatch(server) == 0)
            try connection.withPreparedRead { try $0.read() }
            _ = try connection.dispatchPending()
            #expect(runtime_test_matching_descriptor_count(oracle) == descriptorCount)
            #expect(observations.descriptors == (cancel ? 0 : 1))
            #expect(observations.offers == (cancel ? 0 : 1))
            if !cancel { #expect(keyboard.failure != nil && device.failure != nil) }
            withExtendedLifetime(subscription) {}
            withExtendedLifetime(keyboardSubscription) {}
            withExtendedLifetime(deviceSubscription) {}
            connection.requestClose()
            #expect(try connection.snapshot().retainedRecords == 0)
        }
    }
}

extension DescriptorAndCallbackTests {
    @Test func typedIncomingPublicationFailureConsumesEveryObligation() throws {
        let oracle = runtime_test_descriptor_open()
        defer { _ = runtime_test_descriptor_close(oracle) }
        let descriptorCount = runtime_test_matching_descriptor_count(oracle)
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server) }
        unsafe runtime_test_server_add_typed_globals(server)
        let connection = unsafe try ClientConnection(receiving: descriptor, maximumRecords: 4)
        let observations = TypedObservations()
        let registry = try connection.protocolDisplay().getRegistry()
        let subscription = try registry.onEvent { event in
            switch consume event {
            case .global(let name, let interface, _): observations.globals[interface] = name
            case .globalRemove: break
            }
        }
        try connection.flush()
        #expect(unsafe runtime_test_server_dispatch(server) == 0)
        try connection.withPreparedRead { try $0.read() }
        _ = try connection.dispatchPending()
        let keyboard = try registry.reference.bind(name: #require(observations.globals["wl_keyboard"]), as: WlKeyboard.self, version: 1, advertisedVersion: 1)
        let device = try registry.reference.bind(name: #require(observations.globals["wl_data_device"]), as: WlDataDevice.self, version: 1, advertisedVersion: 1)
        try connection.flush()
        #expect(unsafe runtime_test_server_dispatch(server) == 0)
        try connection.withPreparedRead { try $0.read() }
        _ = try connection.dispatchPending()
        #expect(keyboard.failure != nil && device.failure != nil)
        #expect(runtime_test_matching_descriptor_count(oracle) == descriptorCount)
        #expect(try connection.snapshot().acquisitions == 4)
        withExtendedLifetime(subscription) {}
        connection.requestClose()
        let snapshot = try connection.snapshot()
        #expect(snapshot.retainedRecords == 0 && snapshot.runtimeReleases == 4)
    }

    @Test func typedConstructorRollbackAndVersionRejectionPreserveAccounting() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor, maximumRecords: 1)
        do {
            let registry = try connection.protocolDisplay().getRegistry()
            _ = consume registry
            Issue.record("Capacity-limited constructor unexpectedly succeeded.")
        } catch { #expect(error as? OwnershipError == .capacityExceeded) }
        #expect(try connection.snapshot().acquisitions == 1)
        connection.requestClose()
        #expect(try connection.snapshot().retainedRecords == 0)
    }
}

private final class ClosingTypedConnection {
    let connection: ClientConnection
    init(_ connection: consuming ClientConnection) { self.connection = connection }
}
extension DescriptorAndCallbackTests {
    @Test func typedRootCloseInsideDescriptorHandlerDiscardsQueuedConstructor() throws {
        let oracle = runtime_test_descriptor_open()
        defer { _ = runtime_test_descriptor_close(oracle) }
        let count = runtime_test_matching_descriptor_count(oracle)
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server) }
        unsafe runtime_test_server_add_typed_globals(server)
        let owner = ClosingTypedConnection(unsafe try ClientConnection(receiving: descriptor))
        let observations = TypedObservations()
        let registry = try owner.connection.protocolDisplay().getRegistry()
        let subscription = try registry.onEvent { event in
            switch consume event {
            case .global(let name, let interface, _): observations.globals[interface] = name
            case .globalRemove: break
            }
        }
        try owner.connection.flush()
        #expect(unsafe runtime_test_server_dispatch(server) == 0)
        try owner.connection.withPreparedRead { try $0.read() }
        _ = try owner.connection.dispatchPending()
        let keyboard = try registry.reference.bind(name: #require(observations.globals["wl_keyboard"]), as: WlKeyboard.self, version: 1, advertisedVersion: 1)
        let device = try registry.reference.bind(name: #require(observations.globals["wl_data_device"]), as: WlDataDevice.self, version: 1, advertisedVersion: 1)
        let keyboardSubscription = try keyboard.onEvent { [weak owner] event in
            switch consume event {
            case .keymap(_, let descriptor, _):
                #expect(owner?.connection.requestClose() == .deferred)
                #expect(descriptor.borrowed.isValid == false)
                _ = consume descriptor
            default: break
            }
        }
        try owner.connection.flush()
        #expect(unsafe runtime_test_server_dispatch(server) == 0)
        try owner.connection.withPreparedRead { try $0.read() }
        _ = try owner.connection.dispatchPending()
        #expect(!device.lifetime.isValid)
        let snapshot = try owner.connection.snapshot()
        #expect(snapshot.retainedRecords == 0 && snapshot.acquisitions == snapshot.runtimeReleases)
        #expect(runtime_test_matching_descriptor_count(oracle) == count)
        withExtendedLifetime(subscription) {}
        withExtendedLifetime(keyboardSubscription) {}
    }
}
