import Testing
import WaylandProtocol

@Test func generatedCoreSchemaPreservesOpcodesAndNegotiatedVersions() throws {
    #expect(CoreProtocol.interfaces.count == 23)
    #expect(CoreProtocol.interfaces.reduce(0) { $0 + $1.requests.count + $1.events.count } == 134)
    let registry = try #require(CoreProtocol.interfaces.first { $0.name == "wl_registry" })
    #expect(registry.requests.map(\.name) == ["bind"])
    let surface = try #require(CoreProtocol.interfaces.first { $0.name == "wl_surface" })
    #expect(surface.requests.first?.name == "destroy")
    #expect(surface.requests.first?.destructor == true)
    let damage = try #require(surface.requests.first { $0.name == "damage_buffer" })
    #expect(damage.opcode == 9 && damage.since == 4)
    #expect(throws: ProtocolSchemaError.unsupportedVersion) { try damage.requireAvailable(version: 3) }
    try damage.requireAvailable(version: 4)
    let seat = try #require(CoreProtocol.interfaces.first { $0.name == "wl_seat" })
    #expect(seat.enumerations.first { $0.name == "capability" }?.bitfield == true)
}
