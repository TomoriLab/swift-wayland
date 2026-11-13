import WaylandRuntime
func rejected(_ session: borrowing OwnershipSession) throws {
    let owner = try session.adopt(nativeIdentifier: 1, kind: .registration) {}
    owner.close()
}
