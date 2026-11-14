import WaylandServer
func rejected(_ reader: inout ServerMessageReader) -> () -> Void { { _ = reader.opcode } }
