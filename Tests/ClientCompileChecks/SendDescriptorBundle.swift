import WaylandProtocol
func rejected(_ bundle: ProtocolDescriptorBundle) {
    let closure: @Sendable () -> Void = { _ = bundle.allocatedBytes }
    closure()
}
