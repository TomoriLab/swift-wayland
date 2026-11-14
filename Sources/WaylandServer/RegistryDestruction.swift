import Glibc
import CWaylandServer
import WaylandProtocol
import WaylandRuntime

extension ServerMessageReader {
    /// Applies the pinned fixes request's argument-directed destruction before optional user delivery.
    ///
    /// The result is copied metadata. The target becomes logically unavailable
    /// immediately, while a watched client-dependent record defers its physical
    /// native destruction until the complete enclosing invocation returns.
    public func destroyRegistry(_ index: Int) throws -> ServerResourceSnapshot {
        guard interfaceName == "wl_fixes", schema.name == "destroy_registry", schema.opcode == 1, index == 0 else {
            throw ServerProtocolError.invalidMessage
        }
        let target = try requiredObject(index, as: WlRegistry.self)
        let registry = self.registry
        return try registry.observer.withLiveReference { clientLifetime in
            unsafe try target.withUnsafeNativeResource { pointer in
                let snapshot = unsafe snapshotResource(pointer)
                let key = UInt(bitPattern: pointer)
                let storage = unsafe ServerNativeStorage(OpaquePointer(pointer))
                let retirement = ServerWatchRetirement(storage) { [weak registry] in
                    if registry?.destroying[key] == storage.nativeIdentity { registry?.destroying.removeValue(forKey: key) }
                }
                let owner = unsafe try clientLifetime.adopt(nativeIdentifier: UInt64(key), kind: .serverResourceDestruction,
                                                            dependencies: [clientLifetime]) {
                    withExtendedLifetime(retirement) { unsafe wl_resource_destroy(UnsafeMutablePointer<wl_resource>(storage.pointer)) }
                }
                let observer = owner.reference.destructionObserver()
                storage.observer = observer; storage.nativeIdentity = observer.identity
                unsafe storage.watch = wayland_kit_watch_resource(pointer, notifyResourceDestroyed,
                    Unmanaged.passUnretained(storage).toOpaque())
                guard unsafe storage.watch != nil else { throw ServerError.nativeFailure(ENOMEM) }
                registry.destroying[key] = observer.identity
                _ = unsafe target.lifetime.destructionObserver().protocolClosed()
                owner.close()
                return snapshot
            }
        }
    }
}
