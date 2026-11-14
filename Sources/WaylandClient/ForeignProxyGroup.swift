import CWaylandClient
import WaylandProtocol
import WaylandRuntime

/// Groups borrowed proxies whose destruction authority belongs to a native aggregate.
///
/// The aggregate's cleanup retains this group without retaining a checked handle
/// or root control. Borrowed endpoints use the aggregate's generation and never
/// install dispatchers, replace userdata, or acquire separate destruction rights.
package final class ForeignClientProxyGroup {
    private let registry: TypedClientRegistry
    private var observer: NativeDestructionObserver?
    private var keys: Set<UInt> = []

    /// Uses an existing typed connection without acquiring proxy ownership.
    package init<I: ClientInterface>(connectionOf object: ClientObjectReference<I>) {
        registry = object.endpoint.registry
    }

    /// Publishes the native aggregate lifetime before any borrowed endpoint is exposed.
    package func attach(to lifetime: ObjectHandle) { observer = lifetime.destructionObserver() }

    /// Registers a borrowed native proxy under the aggregate's checked generation.
    ///
    /// The caller proves the aggregate owns this exact proxy and keeps its native
    /// allocation and metadata valid until aggregate destruction. No dispatcher or
    /// userdata is modified. Returned references cannot destroy this allocation.
    @unsafe package func reference<I: ClientInterface>(_ pointer: OpaquePointer, as type: I.Type) throws -> ClientObjectReference<I> {
        guard let observer else { throw OwnershipError.invalidHandle }
        return try observer.withLiveReference { lifetime in
            let schema = try CoreProtocol.requireSchema(for: I.self)
            guard unsafe String(cString: wl_proxy_get_class(pointer)) == schema.name else { throw TypedProtocolError.wrongInterface }
            let key = UInt(bitPattern: pointer)
            if let existing = registry.objects[key]?.value {
                guard existing.lifetime.identity == lifetime.identity else { throw OwnershipError.duplicateNativeIdentifier }
                return ClientObjectReference(existing)
            }
            let version = unsafe wl_proxy_get_version(pointer)
            let endpoint = unsafe TypedClientEndpoint(pointer: pointer, lifetime: lifetime, registry: registry,
                                                     schema: schema, version: max(1, version))
            registry.objects[key] = WeakClientEndpoint(endpoint)
            keys.insert(key)
            return ClientObjectReference(endpoint)
        }
    }

    /// Retires weak lookup entries after the aggregate has destroyed its native proxies.
    package func retire() {
        for key in keys where registry.objects[key]?.value?.lifetime.identity == observer?.identity || registry.objects[key]?.value == nil {
            registry.objects.removeValue(forKey: key)
        }
        keys.removeAll()
    }
}
