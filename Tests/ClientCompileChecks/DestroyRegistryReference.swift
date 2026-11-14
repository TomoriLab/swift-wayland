import WaylandClient
import WaylandProtocol
func cannotDestroy(_ fixes: ClientObjectReference<WlFixes>, _ registry: ClientObjectReference<WlRegistry>) throws {
    try fixes.destroyRegistry(registry: registry)
}
