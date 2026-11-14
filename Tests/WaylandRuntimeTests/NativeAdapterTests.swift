import Testing
import RuntimeNativeTestSupport
import WaylandUtilities
import WaylandClient
import WaylandServer
@testable import WaylandRuntime

private let nativeLogResults = try! RuntimeMutex<[NativeLogText]>([])
@unsafe private func captureNativeLog(_ format: UnsafePointer<CChar>?, _ scope: UnsafeMutableRawPointer?) {
    guard let format = unsafe format, let scope = unsafe scope else { return }
    if let full = unsafe try? UtilitiesInterop.formatLogMessage(format: format, arguments: scope),
       let shortened = unsafe try? UtilitiesInterop.formatLogMessage(format: format, arguments: scope, maximumBytes: 8) {
        nativeLogResults.withLock { $0 += [full, shortened] }
    }
}
extension DescriptorAndCallbackTests {
    @Test func nativeVaListBridgeCopiesArgumentsAndBoundsTextWithoutConsumingTheOriginalScope() throws {
        nativeLogResults.withLock { $0.removeAll() }
        unsafe ClientInterop.wl_log_set_handler_client(captureNativeLog)
        unsafe ServerInterop.wl_log_set_handler_server(captureNativeLog)
        var managedInstalled = false
        defer {
            if !managedInstalled {
                unsafe ClientInterop.wl_log_set_handler_client(nil)
                unsafe ServerInterop.wl_log_set_handler_server(nil)
            }
        }
        let peer = unsafe try #require(runtime_test_peer_create())
        defer { unsafe runtime_test_peer_destroy(peer) }
        #expect(unsafe runtime_test_peer_generate_log(peer) == -1)
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server); _ = runtime_test_descriptor_close(descriptor) }
        #expect(unsafe runtime_test_server_generate_log(server) == 1)
        let results = nativeLogResults.withLock { $0 }
        try #require(results.count == 4)
        #expect(results[0].text.contains("listener") && !results[0].truncated)
        #expect(results[1].truncated && results[1].text.utf8.count == 8)
        #expect(results[2].text.contains("wl_compositor") && !results[2].truncated)
        #expect(results[3].truncated && results[3].text.utf8.count == 8)
        unsafe try ClientLogging.initialize()
        unsafe try ServerLogging.initialize()
        managedInstalled = true
        let received = try RuntimeMutex<[String]>([])
        let old = try ServerLogging.observe { message in received.withLock { $0.append("old:" + message.text) } }
        let replacement = try ServerLogging.observe { message in
            received.withLock { $0.append(message.text) }
            runtime_test_trigger_server_log()
            if let token = try? ClientLogging.observe({ _ in }) { token.cancel() }
        }
        old.cancel()
        runtime_test_trigger_server_log()
        #expect(received.withLock { $0.count } == 1)
        #expect(received.withLock { $0[0].contains("wl_compositor") && !$0[0].hasPrefix("old:") })
        replacement.cancel()
        runtime_test_trigger_server_log()
        #expect(received.withLock { $0.count } == 1)

    }

    @Test func intrusiveNativeListAdaptersMatchForwardReverseAndSafeRemovalContracts() throws {
        for reverse in [false, true] {
            let fixture = unsafe try #require(runtime_test_list_create())
            defer { unsafe runtime_test_list_destroy(fixture) }
            let head = unsafe runtime_test_list_head(fixture)!
            let offset = runtime_test_list_offset()
            var observed: [Int32] = []
            if reverse {
                unsafe UtilitiesInterop.wl_list_for_each_reverse(head, memberOffset: offset) { pointer in
                    observed.append(unsafe runtime_test_list_value(pointer))
                }
            } else {
                unsafe UtilitiesInterop.wl_list_for_each(head, memberOffset: offset) { pointer in
                    observed.append(unsafe runtime_test_list_value(pointer))
                }
            }
            #expect(observed == (reverse ? [3, 2, 1] : [1, 2, 3]))
            if reverse {
                unsafe UtilitiesInterop.wl_list_for_each_reverse_safe(head, memberOffset: offset) { unsafe runtime_test_list_remove($0) }
            } else {
                unsafe UtilitiesInterop.wl_list_for_each_safe(head, memberOffset: offset) { unsafe runtime_test_list_remove($0) }
            }
            #expect(unsafe UtilitiesInterop.wl_list_empty(head) == 1)
        }
    }

    @Test func unsafeClientAndResourceIterationPreservesNativeListAndRemovalSemantics() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server); _ = runtime_test_descriptor_close(descriptor) }
        var clients = 0
        unsafe ServerInterop.wl_client_for_each(runtime_test_server_clients(server)!) { _ in clients += 1 }
        #expect(clients == 1)
        var resourceDescriptor: Int32 = -1
        let resources = unsafe try #require(runtime_test_resource_list_create(&resourceDescriptor))
        defer { unsafe runtime_test_resource_list_destroy(resources); _ = runtime_test_descriptor_close(resourceDescriptor) }
        let head = unsafe runtime_test_resource_list_head(resources)!
        var count = 0
        unsafe ServerInterop.wl_resource_for_each(head) { _ in count += 1 }
        #expect(count == 3)
        unsafe ServerInterop.wl_resource_for_each_safe(head) { unsafe ServerInterop.wl_resource_destroy($0) }
        #expect(unsafe UtilitiesInterop.wl_list_empty(head) == 1)
    }
}

extension DescriptorAndCallbackTests {
    @Test func nativeContainerAndArrayAdaptersUseActualCLayoutAndInitializedValues() throws {
        let fixture = unsafe try #require(runtime_test_list_create())
        defer { unsafe runtime_test_list_destroy(fixture) }
        let head = unsafe runtime_test_list_head(fixture)!
        let member = unsafe head.pointee.next!
        let recovered = unsafe UtilitiesInterop.wl_container_of(UnsafeMutableRawPointer(member), memberOffset: runtime_test_list_offset())
        #expect(unsafe runtime_test_list_value(recovered) == 1)
        let array = unsafe runtime_test_array_fixture()!
        var observed: [UInt32] = []
        unsafe UtilitiesInterop.wl_array_for_each(array, elementSize: MemoryLayout<UInt32>.stride) {
            observed.append(unsafe $0.load(as: UInt32.self))
        }
        #expect(observed == [17, 29, 41])
    }
    @Test func nativeArgumentUnionFieldsPreserveEveryCProjection() {
        #expect(unsafe runtime_test_argument(0).i == -123)
        #expect(unsafe runtime_test_argument(1).u == 0xfedcba98)
        #expect(unsafe runtime_test_argument(2).f == -456)
        #expect(unsafe String(cString: runtime_test_argument(3).s) == "waylandkit-union")
        #expect(unsafe runtime_test_argument(4).o != nil)
        #expect(unsafe runtime_test_argument(5).n == 73)
        #expect(unsafe runtime_test_argument(6).a.pointee.size == 0)
        #expect(unsafe runtime_test_argument(7).h == 19)
    }
}

private final class ReentrantLogCapture: Sendable {
    let storage: ProcessLogStorage
    let released: RuntimeMutex<Int>
    init(storage: ProcessLogStorage, released: RuntimeMutex<Int>) { self.storage = storage; self.released = released }
    deinit {
        if let subscription = try? storage.observe({ _ in }) { subscription.cancel() }
        released.withLock { $0 += 1 }
    }
}
extension DescriptorAndCallbackTests {
    @Test func replacingManagedLogHandlerReleasesCapturedValuesOutsideTheSlotMutex() throws {
        let storage = try ProcessLogStorage()
        unsafe try storage.initialize {}
        let released = try RuntimeMutex(0)
        func install() throws -> ProcessLogSubscription {
            let capture = ReentrantLogCapture(storage: storage, released: released)
            return try storage.observe { [capture] _ in withExtendedLifetime(capture) {} }
        }
        let old = try install()
        let next = try storage.observe { _ in }
        #expect(released.withLock { $0 } == 1)
        old.cancel()
        next.cancel()
    }
}
