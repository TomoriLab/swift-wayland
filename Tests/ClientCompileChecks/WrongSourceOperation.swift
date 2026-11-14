import WaylandServer
func rejected(_ source: ServerEventSourceReference<ServerTimerSourceKind>) throws { try source.update(mask: .readable) }
