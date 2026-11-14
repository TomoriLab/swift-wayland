import Glibc
import CWaylandServer
import WaylandProtocol
import WaylandRuntime

extension TypedServerRegistry {
    /// Leases a native-owned resource through an existing identity or a self-detaching watch.
    @unsafe func reference<I: ServerInterface>(_ pointer: UnsafeMutablePointer<wl_resource>, as type: I.Type) throws -> ServerObjectReference<I> {
        let schema = try CoreProtocol.requireSchema(for: I.self)
        guard unsafe String(cString: wl_resource_get_class(pointer)) == schema.name,
              unsafe wl_resource_get_client(pointer) == client else { throw ServerProtocolError.foreignObject }
        return try observer.withLiveReference { clientLifetime in
            let key = UInt(bitPattern: pointer)
            guard destroying[key] == nil else { throw OwnershipError.invalidHandle }
            if let endpoint = objects[key]?.value {
                guard endpoint.lifetime.isValid else { throw OwnershipError.invalidHandle }
                return ServerObjectReference(endpoint)
            }
            guard let clientStorage = storage else { throw OwnershipError.invalidHandle }
            let identity: NativeDestructionObserver
            if let existing = clientStorage.resourceObservers[key] { identity = existing }
            else {
                let watchStorage = unsafe ServerNativeStorage(OpaquePointer(pointer))
                let retirement = ServerWatchRetirement(watchStorage) { [weak clientStorage] in
                    if let expected = watchStorage.nativeIdentity, clientStorage?.resourceObservers[key]?.identity == expected {
                        clientStorage?.resourceObservers.removeValue(forKey: key)
                    }
                }
                let owner = unsafe try clientLifetime.adopt(nativeIdentifier: UInt64(key), kind: .serverResourceWatch,
                                                            dependencies: [clientLifetime]) { withExtendedLifetime(retirement) {} }
                identity = owner.reference.destructionObserver()
                watchStorage.observer = identity; watchStorage.nativeIdentity = identity.identity
                unsafe watchStorage.watch = wayland_kit_watch_resource(pointer, notifyResourceDestroyed,
                    Unmanaged.passUnretained(watchStorage).toOpaque())
                guard unsafe watchStorage.watch != nil else { throw ServerError.nativeFailure(ENOMEM) }
                clientStorage.resourceObservers[key] = identity
                _ = owner.surrenderToRoot()
            }
            return try identity.withLiveReference { lifetime in
                let version = unsafe wl_resource_get_version(pointer)
                guard version >= 0, UInt32(version) <= schema.version else { throw ServerProtocolError.unsupportedVersion }
                let endpoint = unsafe TypedServerEndpoint(pointer: pointer, lifetime: lifetime, registry: self,
                    schema: schema, version: UInt32(version), context: nil, published: true)
                objects[key] = WeakServerEndpoint(endpoint)
                return ServerObjectReference(endpoint)
            }
        }
    }
}
