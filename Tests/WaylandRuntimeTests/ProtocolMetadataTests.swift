import Testing
@testable import WaylandClient
import WaylandProtocol
import WaylandRuntime

extension DescriptorAndCallbackTests {
    @Test func reentrantCommittedMetadataReservationSurvivesOuterFailure() throws {
        for sameArena in [false, true] {
            let first = try ProtocolDescriptorBundle(interfaces: ExtensionFixture.interfaces)
            let second = try ProtocolDescriptorBundle(interfaces: ExtensionFixture.interfaces)
            let metadata = try ClientProtocolMetadata(maximumBytes: first.allocatedBytes + second.allocatedBytes)
            #expect(throws: BodyFailure.expected) {
                try metadata.withPinnedDescriptor(first.interface(named: "waylandkit_parent")) {
                    try metadata.withPinnedDescriptor((sameArena ? first : second).interface(named: "waylandkit_child")) {}
                    throw BodyFailure.expected
                }
            }
            #expect(metadata.snapshot().arenas == 1)
            #expect(metadata.snapshot().nativeBytes == (sameArena ? first : second).allocatedBytes)
            metadata.retire()
            #expect(metadata.snapshot().arenas == 0 && metadata.snapshot().retired)
        }
    }

    @Test func metadataQuotaAndFailedReservationPreservePublishedEntries() throws {
        let first = try ProtocolDescriptorBundle(interfaces: ExtensionFixture.interfaces)
        let second = try ProtocolDescriptorBundle(interfaces: ExtensionFixture.interfaces)
        let metadata = try ClientProtocolMetadata(maximumBytes: first.allocatedBytes + second.allocatedBytes - 1)
        try metadata.withPinnedDescriptor(first.interface(named: "waylandkit_parent")) {}
        #expect(throws: TypedProtocolError.metadataQuotaExceeded) {
            try metadata.withPinnedDescriptor(second.interface(named: "waylandkit_child")) {}
        }
        #expect(metadata.snapshot().arenas == 1 && metadata.snapshot().nativeBytes == first.allocatedBytes)
        metadata.retire()
        #expect(throws: OwnershipError.closedSession) {
            try metadata.withPinnedDescriptor(first.interface(named: "waylandkit_parent")) {}
        }
    }
}
