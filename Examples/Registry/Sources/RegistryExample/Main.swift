import WaylandKit

private final class RegistrySnapshot {
    var globals: [String: (UInt32, UInt32)] = [:]
    var synchronized = false
}
@main struct RegistryExample {
    static func main() throws {
        let connection = try ClientConnection()
        let registry = try connection.protocolDisplay().getRegistry()
        let observed = RegistrySnapshot()
        let subscription = try registry.onEvent { event in
            switch consume event {
            case .global(let name, let interface, let version): observed.globals[interface] = (name, version)
            case .globalRemove: break
            }
        }
        let synchronization = try connection.protocolDisplay().sync()
        let synchronized = try synchronization.onEvent { event in
            switch consume event { case .done: observed.synchronized = true }
        }
        let cancellation = try ReadCancellation()
        try connection.flush()
        for _ in 0..<10 where !observed.synchronized {
            _ = try connection.dispatchOnce(timeoutMilliseconds: 1_000, cancellation: cancellation)
        }
        guard observed.synchronized else { throw ExampleError.timeout }
        guard let (name, advertised) = observed.globals[WlCompositor.interfaceName] else { throw ExampleError.missingCompositor }
        let version = min(advertised, WlCompositor.schema.version)
        let compositor = try registry.reference.bind(name: name, as: WlCompositor.self, version: version, advertisedVersion: advertised)
        let surface = try compositor.reference.createSurface()
        try surface.reference.commit()
        try surface.destroy()
        try connection.flush()
        withExtendedLifetime(subscription) {}
        withExtendedLifetime(synchronized) {}
        connection.requestClose()
        let snapshot = try connection.snapshot()
        guard snapshot.retainedRecords == 0 else { throw ExampleError.incompleteCleanup }
        print("Observed \(observed.globals.count) interface names; sync completed; unmapped surface created and destroyed; all ownership records retired.")
    }
    enum ExampleError: Error { case timeout, missingCompositor, incompleteCleanup }
}
