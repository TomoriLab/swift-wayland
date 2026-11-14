import Glibc
import Testing
import RuntimeNativeTestSupport
import WaylandClient
import WaylandProtocol
import WaylandRuntime

@safe private final class ExtensionPeer {
    private let pointer: OpaquePointer
    init(descriptor: inout Int32) throws { unsafe pointer = try #require(runtime_protocol_peer_create(&descriptor)) }
    deinit { unsafe runtime_protocol_peer_destroy(pointer) }
    var global: UInt32 { unsafe runtime_protocol_peer_global(pointer) }
    var resources: UInt32 { unsafe runtime_protocol_peer_resources(pointer) }
    var destroyed: UInt32 { unsafe runtime_protocol_peer_destroyed(pointer) }
    var requests: UInt32 { unsafe runtime_protocol_peer_requests(pointer) }
    var descriptors: UInt32 { unsafe runtime_protocol_peer_descriptors(pointer) }
    func dispatch() { #expect(unsafe runtime_protocol_peer_dispatch(pointer) == 0) }
    func emit(_ kind: UInt32, descriptor: Int32) { unsafe runtime_protocol_peer_emit(pointer, kind, descriptor) }
}
private final class ExtensionConnectionRoot {
    var connection: ClientConnection?
    init(receiving descriptor: Int32) throws { connection = unsafe try ClientConnection(receiving: descriptor) }
}
private final class ExtensionArenaObservation { weak var bundle: ProtocolDescriptorBundle? }
private final class ExtensionObservations {
    var scalars = 0
    var constructors = 0
    var descriptor: BorrowedFileDescriptor?
    var child: ClientProtocolObject?
}
private func bindExtension(_ registry: borrowing ClientObject<WlRegistry>, peer: ExtensionPeer,
                           observation: ExtensionArenaObservation? = nil) throws -> ClientProtocolObject {
    let bundle = try ProtocolDescriptorBundle(interfaces: ExtensionFixture.interfaces)
    observation?.bundle = bundle
    return try registry.reference.bind(name: peer.global, descriptor: bundle.interface(named: "waylandkit_parent"), version: 2, advertisedVersion: 2)
}
private func readExtensionEvents(_ connection: borrowing ClientConnection) throws {
    try connection.withPreparedRead { try $0.read() }
    _ = try connection.dispatchPending()
}

extension DescriptorAndCallbackTests {
    @Test func generatedExtensionFacadeRejectsTransitiveSameNameLayoutMismatch() throws {
        var descriptor: Int32 = -1
        let peer = try ExtensionPeer(descriptor: &descriptor)
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let changed = ExtensionFixture.interfaces.map { interface -> ProtocolInterfaceSchema in
            guard interface.name == "waylandkit_child" else { return interface }
            let event = ProtocolMessageSchema(name: "value", opcode: 0, since: 1, deprecatedSince: nil,
                destructor: false, arguments: [ProtocolArgumentSchema(name: "value", kind: .signed,
                    nullable: false, interface: nil, enumeration: nil)])
            return ProtocolInterfaceSchema(name: interface.name, version: interface.version,
                requests: interface.requests, events: [event, interface.events[1]], enumerations: interface.enumerations)
        }
        let bundle = try ProtocolDescriptorBundle(interfaces: changed)
        let dynamic = try registry.reference.bind(name: peer.global, descriptor: bundle.interface(named: "waylandkit_parent"),
            version: 2, advertisedVersion: 2)
        var rejected = false
        do { _ = try ExtensionFixtureWaylandkitParentClient(dynamic) }
        catch ProtocolDescriptorError.invalidSchema { rejected = true }
        #expect(rejected)
        connection.requestClose()
        peer.dispatch()
        #expect(try connection.snapshot().retainedRecords == 0)
    }

    @Test func generatedExtensionClientFacadesRoundtripWithIndependentPeer() throws {
        var descriptor: Int32 = -1
        let peer = try ExtensionPeer(descriptor: &descriptor)
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let bundle = try ProtocolDescriptorBundle(interfaces: ExtensionFixture.interfaces)
        let parent = try registry.reference.bindWaylandkitParent(name: peer.global,
            descriptor: bundle.interface(named: "waylandkit_parent"), version: 2, advertisedVersion: 2)
        let child = try parent.reference.makeChild()
        let observations = ExtensionObservations()
        let subscription = try child.onEvent { event in
            switch consume event {
            case .value(let value):
                #expect(value == 17)
                observations.scalars += 1
            case .terminal: Issue.record("Unexpected terminal event.")
            }
        }
        try connection.flush()
        peer.dispatch()
        try readExtensionEvents(connection)
        #expect(observations.scalars == 1 && peer.resources == 2)
        try child.reference.mark(value: 17)
        try connection.flush()
        peer.dispatch()
        try child.destroy()
        try parent.destroy()
        try connection.flush()
        peer.dispatch()
        #expect(peer.resources == 0)
        withExtendedLifetime(subscription) {}
        connection.requestClose()
        #expect(try connection.snapshot().retainedRecords == 0)
    }

    @Test func managedExtensionRequestsAndConstructorsRetainMetadataUntilLastNativeConsumer() throws {
        var descriptor: Int32 = -1
        let peer = try ExtensionPeer(descriptor: &descriptor)
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let observation = ExtensionArenaObservation()
        let parent = try bindExtension(registry, peer: peer, observation: observation)
        #expect(observation.bundle != nil)
        let child = try parent.reference.construct(opcode: 0, arguments: [.constructor])
        let values = ExtensionObservations()
        let subscription = try child.onEvent { reader in
            #expect(reader.opcode == 0)
            let value = try reader.unsigned(0)
            #expect(value == 17)
            values.scalars += 1
        }
        let session = try OwnershipSession()
        let descriptorOwner = unsafe try session.receiveFileDescriptor(runtime_test_descriptor_open())
        try parent.reference.request(opcode: 1, arguments: [.unsigned(17), .object(child.reference.erased),
            .string("extension"), .bytes([1, 2, 3]), .descriptor(descriptorOwner.borrowed)])
        try parent.reference.request(opcode: 1, arguments: [.unsigned(17), .object(nil), .string(nil),
            .bytes([1, 2, 3]), .descriptor(descriptorOwner.borrowed)])
        try connection.flush(); peer.dispatch()
        try readExtensionEvents(connection)
        #expect(values.scalars == 1 && peer.descriptors == 2 && peer.resources == 2)
        let parentReference = parent.reference
        try parent.destroy(opcode: 3)
        #expect(!parentReference.isValid && observation.bundle != nil && child.reference.isValid)
        try child.reference.request(opcode: 1, arguments: [.unsigned(17)])
        try connection.flush(); peer.dispatch()
        #expect(peer.resources == 1)
        try child.destroy(opcode: 0)
        #expect(observation.bundle != nil)
        try connection.flush(); peer.dispatch()
        #expect(peer.resources == 0)
        withExtendedLifetime(subscription) {}
        session.requestClose()
        connection.requestClose()
        #expect(observation.bundle == nil)
        #expect(connection.protocolMetadataSnapshot().arenas == 0 && connection.protocolMetadataSnapshot().retired)
        #expect(try connection.snapshot().retainedRecords == 0)
        #expect(try session.snapshot().retainedRecords == 0)
    }

    @Test func extensionGenericConstructorsAndTerminalReplacementKeepIndependentArenaOwnership() throws {
        for replacement in [false, true] {
            var descriptor: Int32 = -1
            let peer = try ExtensionPeer(descriptor: &descriptor)
            let connection = unsafe try ClientConnection(receiving: descriptor)
            let registry = try connection.protocolDisplay().getRegistry()
            let observation = ExtensionArenaObservation()
            let parent = try bindExtension(registry, peer: peer, observation: observation)
            let previous = parent.reference
            if replacement {
                let child = try parent.replace(opcode: 4, arguments: [.constructor])
                #expect(!previous.isValid && observation.bundle != nil)
                try connection.flush(); peer.dispatch()
                try readExtensionEvents(connection)
                #expect(peer.resources == 1 && child.failure == nil)
                child.close()
                #expect(observation.bundle != nil)
            } else {
                let bundle = try ProtocolDescriptorBundle(interfaces: ExtensionFixture.interfaces)
                let child = try previous.construct(opcode: 5, arguments: [.constructor], descriptor: bundle.interface(named: "waylandkit_child"), version: 1, advertisedVersion: 2)
                #expect(child.reference.version == 1)
                try connection.flush(); peer.dispatch()
                try readExtensionEvents(connection)
                #expect(peer.resources == 2 && child.failure == nil)
                child.close()
                parent.close()
                #expect(observation.bundle != nil)
            }
            connection.requestClose(); peer.dispatch()
            #expect(observation.bundle == nil)
            #expect(peer.resources == 0)
            #expect(try connection.snapshot().retainedRecords == 0)
        }
    }

    @Test func extensionReceivedDescriptorsAndNewProxiesAreRetiredOnIgnoredCancelledAndThrowingDelivery() throws {
        for mode in 0..<3 {
            let oracle = runtime_test_descriptor_open()
            defer { _ = runtime_test_descriptor_close(oracle) }
            let count = runtime_test_matching_descriptor_count(oracle)
            var descriptor: Int32 = -1
            let peer = try ExtensionPeer(descriptor: &descriptor)
            let connection = unsafe try ClientConnection(receiving: descriptor)
            let registry = try connection.protocolDisplay().getRegistry()
            let parent = try bindExtension(registry, peer: peer)
            let values = ExtensionObservations()
            let subscription = try parent.onEvent { reader in
                values.scalars += 1
                if mode == 2 {
                    let received = try reader.descriptor(1)
                    values.descriptor = received.borrowed
                    _ = consume received
                    throw BodyFailure.expected
                }
            }
            if mode == 1 { subscription.cancel() }
            try connection.flush(); peer.dispatch()
            try readExtensionEvents(connection)
            peer.emit(1, descriptor: oracle)
            try readExtensionEvents(connection)
            #expect(values.scalars == (mode == 1 ? 0 : 1))
            #expect(mode != 2 || parent.failure != nil)
            #expect(values.descriptor?.isValid != true)
            #expect(runtime_test_matching_descriptor_count(oracle) == count)
            try connection.flush(); peer.dispatch()
            #expect(peer.resources == 1)
            connection.requestClose(); peer.dispatch()
            #expect(peer.resources == 0)
            #expect(try connection.snapshot().retainedRecords == 0)
            withExtendedLifetime(subscription) {}
        }
    }

    @Test func extensionArenaRemainsPinnedDuringCallbackRootClosureAndRetiresWithInvalidOwnersAlive() throws {
        let oracle = runtime_test_descriptor_open()
        defer { _ = runtime_test_descriptor_close(oracle) }
        let count = runtime_test_matching_descriptor_count(oracle)
        var descriptor: Int32 = -1
        let peer = try ExtensionPeer(descriptor: &descriptor)
        let root = try ExtensionConnectionRoot(receiving: descriptor)
        let registry = try root.connection!.protocolDisplay().getRegistry()
        let observation = ExtensionArenaObservation()
        let parent = try bindExtension(registry, peer: peer, observation: observation)
        let values = ExtensionObservations()
        let subscription = try parent.onEvent { [weak root] reader in
            let child = try reader.protocolConstructor(0)
            let received = try reader.descriptor(1)
            values.descriptor = received.borrowed
            _ = consume received
            values.child = consume child
            root?.connection?.requestClose()
            #expect(observation.bundle != nil)
        }
        try root.connection!.flush(); peer.dispatch()
        try readExtensionEvents(root.connection!)
        peer.emit(1, descriptor: oracle)
        try readExtensionEvents(root.connection!)
        #expect(!parent.reference.isValid && values.child?.reference.isValid != true)
        #expect(observation.bundle == nil)
        #expect(values.descriptor?.isValid == false)
        #expect(runtime_test_matching_descriptor_count(oracle) == count)
        #expect(try root.connection!.snapshot().retainedRecords == 0)
        peer.dispatch()
        #expect(peer.resources == 0)
        withExtendedLifetime(subscription) {}
    }
}

extension DescriptorAndCallbackTests {
    @Test func queuedExtensionConstructorsDeferReceiverFreeAndDisposeWithoutUserDelivery() throws {
        for rootClose in [false, true] {
            let oracle = runtime_test_descriptor_open()
            defer { _ = runtime_test_descriptor_close(oracle) }
            let count = runtime_test_matching_descriptor_count(oracle)
            var descriptor: Int32 = -1
            let peer = try ExtensionPeer(descriptor: &descriptor)
            let connection = unsafe try ClientConnection(receiving: descriptor)
            let registry = try connection.protocolDisplay().getRegistry()
            let observation = ExtensionArenaObservation()
            let parent = try bindExtension(registry, peer: peer, observation: observation)
            let values = ExtensionObservations()
            let subscription = try parent.onEvent { _ in values.scalars += 1 }
            try connection.flush(); peer.dispatch()
            try readExtensionEvents(connection)
            peer.emit(1, descriptor: oracle)
            try connection.withPreparedRead { try $0.read() }
            if rootClose {
                connection.requestClose()
                #expect(connection.protocolMetadataSnapshot().retired)
                #expect(observation.bundle == nil)
            } else {
                #expect(parent.close() == .deferred)
                #expect(observation.bundle != nil)
                _ = try connection.dispatchPending()
                try connection.flush(); peer.dispatch()
                #expect(peer.resources == 0)
                connection.requestClose()
                #expect(observation.bundle == nil)
            }
            #expect(values.scalars == 0)
            #expect(runtime_test_matching_descriptor_count(oracle) == count)
            #expect(try connection.snapshot().retainedRecords == 0)
            #expect(connection.protocolMetadataSnapshot().cleanupError == nil)
            peer.dispatch()
            #expect(peer.resources == 0)
            withExtendedLifetime(subscription) {}
        }
    }

    @Test func queuedScalarClosureRetainsExtensionMetadataAfterProxyDestruction() throws {
        var descriptor: Int32 = -1
        let peer = try ExtensionPeer(descriptor: &descriptor)
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let observation = ExtensionArenaObservation()
        let parent = try bindExtension(registry, peer: peer, observation: observation)
        let child = try parent.reference.construct(opcode: 0, arguments: [.constructor])
        try connection.flush(); peer.dispatch()
        try connection.withPreparedRead { try $0.read() }
        #expect(child.close() == .complete)
        #expect(observation.bundle != nil)
        _ = try connection.dispatchPending()
        connection.requestClose()
        #expect(observation.bundle == nil)
        #expect(connection.protocolMetadataSnapshot().arenas == 0)
    }

    @Test func extensionArgumentDestructorSendsOnceAndTerminalEventClosesReceivedDescriptor() throws {
        for terminalEvent in [false, true] {
            let oracle = runtime_test_descriptor_open()
            defer { _ = runtime_test_descriptor_close(oracle) }
            let count = runtime_test_matching_descriptor_count(oracle)
            var descriptor: Int32 = -1
            let peer = try ExtensionPeer(descriptor: &descriptor)
            let connection = unsafe try ClientConnection(receiving: descriptor)
            let registry = try connection.protocolDisplay().getRegistry()
            let parent = try bindExtension(registry, peer: peer)
            try connection.flush(); peer.dispatch()
            try readExtensionEvents(connection)
            if terminalEvent {
                peer.emit(2, descriptor: oracle)
                try readExtensionEvents(connection)
                #expect(!parent.reference.isValid && parent.failure == nil)
            } else {
                let session = try OwnershipSession()
                let descriptorOwner = unsafe try session.receiveFileDescriptor(runtime_test_descriptor_open())
                try parent.destroy(opcode: 6, arguments: [.descriptor(descriptorOwner.borrowed)])
                try connection.flush(); peer.dispatch()
                #expect(peer.descriptors == 1 && peer.requests == 1)
                session.requestClose()
            }
            #expect(peer.resources == 0 && peer.destroyed == 1)
            #expect(runtime_test_matching_descriptor_count(oracle) == count)
            connection.requestClose()
            #expect(try connection.snapshot().retainedRecords == 0)
        }
    }
}
