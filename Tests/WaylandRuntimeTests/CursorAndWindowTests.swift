import Testing
import RuntimeNativeTestSupport
import WaylandClient
import WaylandCursor
import WaylandEGL
import WaylandProtocol
import WaylandRuntime

private final class AdvancedGlobals { var names: [String: UInt32] = [:] }
extension DescriptorAndCallbackTests {
    @Test func nativeWindowDependsOnSurfaceAndRejectsUseAfterLogicalClose() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let globals = AdvancedGlobals()
        let subscription = try registry.onEvent { event in
            switch consume event {
            case .global(let name, let interface, _): globals.names[interface] = name
            case .globalRemove: break
            }
        }
        try connection.flush()
        #expect(unsafe runtime_test_server_dispatch(server) == 0)
        try connection.withPreparedRead { try $0.read() }
        _ = try connection.dispatchPending()
        let compositor = try registry.reference.bind(name: #require(globals.names["wl_compositor"]), as: WlCompositor.self,
                                                     version: 1, advertisedVersion: 1)
        let surface = try compositor.reference.createSurface()
        #expect(throws: NativeWindowError.invalidDimensions) { _ = try NativeWindow(surface: surface.reference, width: 0, height: 1) }
        let window = try NativeWindow(surface: surface.reference, width: 32, height: 24)
        let initialSize = try window.attachedSize()
        #expect(initialSize.width == 0 && initialSize.height == 0)
        try window.resize(width: 48, height: 32)
        let reference = window.lifetime
        try surface.destroy()
        #expect(!reference.isValid)
        #expect(throws: OwnershipError.invalidHandle) { _ = try window.attachedSize() }
        #expect(window.requestClose() == .complete)
        withExtendedLifetime(subscription) {}
        connection.requestClose()
        #expect(try connection.snapshot().retainedRecords == 0)
    }

    @Test func cursorThemeOwnsImagesAndBuffersAcrossLazyCreationAndParentShutdown() throws {
        var descriptor: Int32 = -1
        let server = unsafe try #require(runtime_test_server_create(&descriptor))
        defer { unsafe runtime_test_server_destroy(server) }
        #expect(unsafe runtime_test_server_initialize_shm(server) == 0)
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let globals = AdvancedGlobals()
        let subscription = try registry.onEvent { event in
            switch consume event {
            case .global(let name, let interface, _): globals.names[interface] = name
            case .globalRemove: break
            }
        }
        try connection.flush()
        #expect(unsafe runtime_test_server_dispatch(server) == 0)
        try connection.withPreparedRead { try $0.read() }
        _ = try connection.dispatchPending()
        let sharedMemory = try registry.reference.bind(name: #require(globals.names["wl_shm"]), as: WlShm.self,
                                                      version: 1, advertisedVersion: 1)
        let theme = unsafe try CursorTheme(sharedMemory: sharedMemory.reference, name: "waylandkit-missing-theme", size: 24)
        let optionalCursor = try theme.cursor(named: "left_ptr")
        let cursor = try #require(optionalCursor)
        #expect(try cursor.imageCount() > 0)
        let frame = try cursor.frame(at: 173)
        let image = try cursor.image(at: frame.index)
        let metadata = try image.metadata()
        #expect(metadata.width > 0 && metadata.height > 0)
        #expect(throws: CursorError.invalidImage) { _ = try cursor.image(at: -1) }
        let buffer = try image.buffer()
        let again = try image.buffer()
        #expect(try buffer.identifier() == again.identifier())
        #expect(buffer.lifetime.identity == theme.lifetime.identity)
        try connection.flush()
        #expect(unsafe runtime_test_server_dispatch(server) == 0)
        #expect(theme.requestClose() == .complete)
        #expect(!buffer.isValid)
        #expect(throws: OwnershipError.invalidHandle) { _ = try image.metadata() }
        #expect(throws: OwnershipError.invalidHandle) { _ = try cursor.frame(at: 0) }
        withExtendedLifetime(subscription) {}
        connection.requestClose()
        #expect(try connection.snapshot().retainedRecords == 0)
    }
}
