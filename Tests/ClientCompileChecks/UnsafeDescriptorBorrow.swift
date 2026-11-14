import WaylandProtocol
func rejected(_ descriptor: ProtocolDescriptor) {
    descriptor.withUnsafeInterface { _ in () }
}
