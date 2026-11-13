import WaylandClient
func rejected(_ connection: borrowing ClientConnection) {
    let closure: @Sendable () -> Void = { _ = connection.lifetime }
    closure()
}
