import Testing
import WaylandUtilities
import WaylandRuntime

extension DescriptorAndCallbackTests {
    @Test func nativeByteArrayViewsRejectReentrantMutationAndEscapedAccess() throws {
        let array = try NativeByteArray(maximumBytes: 4)
        let reference = array.reference
        try reference.append([1, 2, 3])
        var escaped: NativeByteArrayView?
        try reference.withView { (view) throws -> Void in
            escaped = view
            #expect(try view.count() == 3)
            #expect(try view.byte(at: 1) == 2)
            #expect(throws: ByteArrayError.outOfBounds) { _ = try view.byte(at: 3) }
            #expect(throws: ByteArrayError.activeView) { try reference.append([4]) }
            #expect(throws: ByteArrayError.activeView) { try reference.clear() }
        }
        let old = try #require(escaped)
        #expect(throws: ByteArrayError.expiredView) { _ = try old.bytes() }
        let copied = try reference.bytes()
        try reference.append([4])
        #expect(throws: ByteArrayError.quotaExceeded) { try reference.append([5]) }
        #expect(copied == [1, 2, 3])
        #expect(try reference.bytes() == [1, 2, 3, 4])
        try reference.clear()
        #expect(try reference.bytes().isEmpty)
        array.requestClose()
        #expect(try array.snapshot().retainedRecords == 0)
    }
    @Test func nativeByteArrayCloseAndThrowInsideViewBalanceLeases() throws {
        let array = try NativeByteArray()
        let reference = array.reference
        try reference.append([9])
        do {
            try reference.withView { (view) throws -> Void in
                #expect(array.requestClose() == .deferred)
                #expect(!reference.lifetime.isValid)
                #expect(throws: OwnershipError.invalidHandle) { _ = try view.byte(at: 0) }
                throw BodyFailure.expected
            }
            Issue.record("The throwing view returned normally.")
        } catch BodyFailure.expected {}
        #expect(try array.snapshot().retainedRecords == 0)
    }
}
