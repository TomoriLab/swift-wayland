import WaylandCursor
import WaylandClient
import WaylandProtocol
func unacknowledged(_ sharedMemory: ClientObjectReference<WlShm>) throws {
    let theme = try CursorTheme(sharedMemory: sharedMemory)
    _ = consume theme
}
