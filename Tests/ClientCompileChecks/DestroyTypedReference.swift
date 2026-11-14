import WaylandClient
import WaylandProtocol
func rejected(_ reference: ClientObjectReference<WlSurface>) throws { try reference.destroy() }
