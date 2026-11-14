import WaylandCursor
import WaylandEGL
import WaylandUtilities
import WaylandClient
import WaylandProtocol
func accepted(_ sharedMemory: ClientObjectReference<WlShm>, _ surface: ClientObjectReference<WlSurface>) throws {
    let theme = unsafe try CursorTheme(sharedMemory: sharedMemory)
    let window = try NativeWindow(surface: surface, width: 16, height: 16)
    let array = try NativeByteArray()
    try array.reference.append([1, 2])
    let copied = try array.reference.bytes()
    _ = copied
    window.requestClose()
    theme.requestClose()
}
