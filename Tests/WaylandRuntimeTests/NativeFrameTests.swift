import Testing
import RuntimeNativeTestSupport
@testable import WaylandRuntime

final class NativeOwnerBox {
    let session: OwnershipSession
    init() throws { session = try OwnershipSession() }
    func requestClose() -> CloseProgress { session.requestClose() }
}

final class NativeCallbackContext {
    weak let owner: NativeOwnerBox?
    var progress: CloseProgress?
    var called = false
    init(owner: NativeOwnerBox) { self.owner = owner }
}

@unsafe private func closeFromNativeCallback(_ data: UnsafeMutableRawPointer?) {
    // The test retains this context until the outer dispatch and deferred teardown finish.
    let context = unsafe Unmanaged<NativeCallbackContext>.fromOpaque(data!).takeUnretainedValue()
    context.called = true
    context.progress = context.owner?.requestClose()
}

@Test func realNativeDispatchContinuesAfterCallbackBeforePhysicalRelease() throws {
    let box = try NativeOwnerBox()
    let context = NativeCallbackContext(owner: box)
    let observer = unsafe try #require(runtime_test_observer_create())
    defer { unsafe runtime_test_observer_destroy(observer) }
    let data = unsafe Unmanaged.passRetained(context).toOpaque()
    defer { unsafe Unmanaged<NativeCallbackContext>.fromOpaque(data).release() }
    let callback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { data in
        unsafe closeFromNativeCallback(data)
    }
    let resource = unsafe try #require(runtime_test_resource_create(observer, callback, data))
    let owner = unsafe try box.session.adopt(nativeIdentifier: 1, kind: .serverDisplay) {
        unsafe runtime_test_resource_destroy(resource)
    }
    let reference = owner.reference
    try box.session.withNativeFrame {
        let stage = unsafe runtime_test_dispatch(resource)
        #expect(stage == 2)
        #expect(context.called && context.progress == .deferred)
        #expect(!reference.isValid)
        let releases = unsafe runtime_test_release_count(observer)
        #expect(releases == 0)
    }
    let releases = unsafe runtime_test_release_count(observer)
    #expect(releases == 1)
    #expect(try box.session.snapshot().outstandingObligations == 0)
    owner.close()
}
