import WaylandClient
import WaylandProtocol
func rejected(_ surface: ClientObjectReference<WlSurface>, _ region: ClientObjectReference<WlRegion>) throws {
    try surface.attach(buffer: region, x: 0, y: 0)
}
