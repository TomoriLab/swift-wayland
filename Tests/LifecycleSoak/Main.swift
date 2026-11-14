import Foundation
import WaylandClient
import WaylandServer
import WaylandCursor
import WaylandEGL
import WaylandUtilities
import WaylandProtocol
import WaylandRuntime
import RuntimeNativeTestSupport

private final class Globals { var names: [String: UInt32] = [:] }
@main struct LifecycleSoak {
    static func sharedMemoryCycle() throws {
        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        precondition(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        let display = try ServerDisplay()
        try display.initializeSharedMemory()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        guard let peer = unsafe runtime_test_shm_client_create(clientDescriptor) else { fatalError("SHM peer allocation failed.") }
        defer { unsafe runtime_test_shm_client_destroy(peer) }
        try display.dispatch()
        precondition(unsafe runtime_test_shm_client_dispatch(peer) >= 0)
        let identifier = unsafe runtime_test_shm_client_buffer(peer)
        try display.dispatch()
        let clientReference = try client.reference()
        guard let resource = try clientReference.object(identifier: identifier, as: WlBuffer.self) else { fatalError("SHM resource missing.") }
        let buffer = try display.sharedMemoryBuffer(for: resource)
        let second = try buffer.reference()
        let pool = try buffer.referencePool()
        let bytes = try second.snapshot()
        precondition(bytes == Array(UInt8(1)...UInt8(16)))
        client.requestClose()
        precondition(!resource.isValid && buffer.lifetime.isValid)
        buffer.requestClose()
        second.requestClose()
        pool.requestClose()
        display.requestClose()
        let snapshot = try display.snapshot()
        precondition(snapshot.retainedRecords == 0)
    }
    static func cycle() throws {
        var descriptor: Int32 = -1
        guard let native = unsafe runtime_test_server_create(&descriptor) else { fatalError("Native fixture allocation failed.") }
        defer { unsafe runtime_test_server_destroy(native) }
        precondition(unsafe runtime_test_server_initialize_shm(native) == 0)
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let globals = Globals()
        let subscription = try registry.onEvent { event in
            switch consume event {
            case .global(let name, let interface, _): globals.names[interface] = name
            case .globalRemove: break
            }
        }
        try connection.flush()
        precondition(unsafe runtime_test_server_dispatch(native) == 0)
        try connection.withPreparedRead { try $0.read() }
        _ = try connection.dispatchPending()
        let compositor = try registry.reference.bind(name: globals.names["wl_compositor"]!, as: WlCompositor.self, version: 1, advertisedVersion: 1)
        let sharedMemory = try registry.reference.bind(name: globals.names["wl_shm"]!, as: WlShm.self, version: 1, advertisedVersion: 1)
        let surface = try compositor.reference.createSurface()
        let window = try NativeWindow(surface: surface.reference, width: 16, height: 16)
        try window.resize(width: 24, height: 24)
        let theme = unsafe try CursorTheme(sharedMemory: sharedMemory.reference, name: "waylandkit-soak-missing", size: 16)
        guard let cursor = try theme.cursor(named: "left_ptr") else { fatalError("Native fallback cursor missing.") }
        let image = try cursor.image(at: 0)
        let buffer = try image.buffer()
        try connection.flush()
        precondition(unsafe runtime_test_server_dispatch(native) == 0)
        subscription.cancel()
        connection.requestClose()
        precondition(!buffer.isValid && !window.lifetime.isValid)
        let connectionSnapshot = try connection.snapshot()
        precondition(connectionSnapshot.retainedRecords == 0)

        var serverDescriptor: Int32 = -1
        var clientDescriptor: Int32 = -1
        precondition(unsafe runtime_test_socket_pair(&serverDescriptor, &clientDescriptor) == 0)
        defer { _ = runtime_test_descriptor_close(clientDescriptor) }
        let display = try ServerDisplay()
        let client = unsafe try display.createClient(receiving: serverDescriptor)
        let resource = try client.createObject(as: WlCallback.self, version: 1)
        let idle = try display.addIdle {}
        let timer = try display.addTimer { .done }
        let global = try display.addGlobal(as: WlCompositor.self, version: 1) { pending in _ = consume pending }
        try display.dispatch()
        display.requestClose()
        precondition(!resource.lifetime.isValid && !idle.lifetime.isValid && !timer.lifetime.isValid && !global.lifetime.isValid)
        let displaySnapshot = try display.snapshot()
        precondition(displaySnapshot.retainedRecords == 0)

        let session = try OwnershipSession()
        let descriptorOwner = unsafe try session.receiveFileDescriptor(runtime_test_descriptor_open())
        let duplicate = try descriptorOwner.borrowed.duplicate(in: descriptorOwner.lifetime)
        session.requestClose()
        precondition(!duplicate.borrowed.isValid)
        let sessionSnapshot = try session.snapshot()
        precondition(sessionSnapshot.retainedRecords == 0)
        let array = try NativeByteArray(maximumBytes: 8)
        try array.reference.append([1, 2, 3])
        let copied = try array.reference.bytes()
        array.requestClose()
        precondition(copied == [1, 2, 3])
        let arraySnapshot = try array.snapshot()
        precondition(arraySnapshot.retainedRecords == 0)
        try sharedMemoryCycle()
    }
    static func main() throws {
        let iterations = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 10_000
        precondition(iterations > 0)
        try cycle()
        let baseline = runtime_test_live_descriptor_count()
        let start = runtime_test_clock_nanoseconds()
        for _ in 0..<iterations { try cycle() }
        let final = runtime_test_live_descriptor_count()
        precondition(baseline >= 0 && final == baseline)
        let report: [String: Any] = ["iterations": iterations, "liveDescriptorsBefore": baseline, "liveDescriptorsAfter": final,
                                   "seconds": Double(runtime_test_clock_nanoseconds() - start) / 1e9,
                                   "ledgers": "All five ownership sessions had zero retained records after every cycle.",
                                   "families": ["client/registry/typed constructors/subscription cancellation", "cursor/images/lazy native buffers", "unbound EGL windows", "server/client/resource/global/idle/timer", "FD duplicate and root closure", "native byte-array snapshots", "SHM snapshots/external buffer and pool refs/client destruction"],
                                   "passed": true]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
