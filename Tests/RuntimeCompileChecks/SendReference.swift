import WaylandRuntime
func rejected(_ handle: ObjectHandle) -> @Sendable () -> Bool {
    return { handle.isValid }
}
