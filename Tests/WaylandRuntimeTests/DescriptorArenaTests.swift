import Testing
import WaylandProtocol
import RuntimeNativeTestSupport

private func descriptorSchemas() -> [ProtocolInterfaceSchema] {
    let constructor = ProtocolMessageSchema(name: "create", opcode: 0, since: 1, deprecatedSince: nil, destructor: false,
        arguments: [ProtocolArgumentSchema(name: "identifier", kind: .newIdentifier, nullable: false, interface: "beta", enumeration: nil)])
    let event = ProtocolMessageSchema(name: "reference", opcode: 0, since: 1, deprecatedSince: nil, destructor: false,
        arguments: [ProtocolArgumentSchema(name: "parent", kind: .object, nullable: false, interface: "alpha", enumeration: nil),
                    ProtocolArgumentSchema(name: "mode", kind: .unsigned, nullable: false, interface: nil, enumeration: "alpha.mode")])
    return [ProtocolInterfaceSchema(name: "alpha", version: 2, requests: [constructor], events: [],
                enumerations: [ProtocolEnumSchema(name: "mode", bitfield: false, entries: [ProtocolEnumEntry(name: "one", value: 1, since: 1)])]),
            ProtocolInterfaceSchema(name: "beta", version: 1, requests: [], events: [event], enumerations: [])]
}

extension DescriptorAndCallbackTests {
    @Test func nativeDescriptorCyclesRoundtripAndRetainTheirCompleteArena() throws {
        weak var observed: ProtocolDescriptorBundle?
        var descriptor: ProtocolDescriptor?
        do {
            let bundle = try ProtocolDescriptorBundle(interfaces: descriptorSchemas(), maximumBytes: 16384)
            observed = bundle
            #expect(bundle.allocatedBytes > 0 && bundle.allocatedBytes <= 16384)
            #expect(bundle.interfaceNames == ["alpha", "beta"])
            descriptor = try bundle.interface(named: "alpha")
            #expect(throws: ProtocolDescriptorError.unknownInterface) { try bundle.interface(named: "missing") }
        }
        #expect(observed != nil)
        #expect(descriptor?.schema.name == "alpha")
        let result = unsafe descriptor!.withUnsafeInterface { unsafe runtime_descriptor_roundtrip($0) }
        #expect(result == 1)
        descriptor = nil
        #expect(observed == nil)
    }

    @Test func completeCoreSchemasProduceBoundedNativeDescriptors() throws {
        let bundle = try ProtocolDescriptorBundle(interfaces: CoreProtocol.interfaces)
        #expect(bundle.interfaceNames.count == 23)
        #expect(bundle.allocatedBytes < 1024 * 1024)
        #expect(throws: ProtocolDescriptorError.allocationFailed) {
            try ProtocolDescriptorBundle(interfaces: CoreProtocol.interfaces, maximumBytes: 1)
        }
        #expect(throws: ProtocolDescriptorError.quotaExceeded) {
            try ProtocolDescriptorBundle(interfaces: [], maximumBytes: Int.max)
        }
    }

    @Test func generatedSchemaAdmissionChecksTransitiveDefinitionsAndRejectsDuplicateInput() throws {
        let schemas = descriptorSchemas()
        let bundle = try ProtocolDescriptorBundle(interfaces: schemas)
        let descriptor = try bundle.interface(named: "alpha")
        try descriptor.requireEquivalent(to: schemas)
        #expect(throws: ProtocolDescriptorError.invalidSchema) {
            try descriptor.requireEquivalent(to: [schemas[0]])
        }
        let modified = ProtocolInterfaceSchema(name: "beta", version: 1, requests: [], events: [], enumerations: [])
        #expect(throws: ProtocolDescriptorError.invalidSchema) {
            try descriptor.requireEquivalent(to: [schemas[0], modified])
        }
        #expect(throws: ProtocolDescriptorError.invalidSchema) {
            try descriptor.requireEquivalent(to: [schemas[0], schemas[1], schemas[1]])
        }
    }

    @Test func descriptorValidationRejectsIncompleteOrInconsistentNativeSchemas() throws {
        let empty = ProtocolInterfaceSchema(name: "empty", version: 1, requests: [], events: [], enumerations: [])
        let badMessage = ProtocolMessageSchema(name: "message", opcode: 1, since: 1, deprecatedSince: nil, destructor: false, arguments: [])
        let nullable = ProtocolArgumentSchema(name: "scalar", kind: .unsigned, nullable: true, interface: nil, enumeration: nil)
        let invalidEvent = ProtocolMessageSchema(name: "event", opcode: 0, since: 1, deprecatedSince: nil, destructor: false, arguments: [nullable])
        let cases = [[empty, empty], [descriptorSchemas()[0]],
            [ProtocolInterfaceSchema(name: "bad\0name", version: 1, requests: [], events: [], enumerations: [])],
            [ProtocolInterfaceSchema(name: "future", version: UInt32.max, requests: [], events: [], enumerations: [])],
            [ProtocolInterfaceSchema(name: "wrong", version: 1, requests: [badMessage], events: [], enumerations: [])],
            [ProtocolInterfaceSchema(name: "nullable", version: 1, requests: [], events: [invalidEvent], enumerations: [])]]
        for schemas in cases {
            #expect(throws: ProtocolDescriptorError.invalidSchema) { try ProtocolDescriptorBundle(interfaces: schemas) }
        }
    }
}
