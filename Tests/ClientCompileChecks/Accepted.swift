import WaylandClient
func accepted(_ connection: borrowing ClientConnection) throws {
    try connection.withPreparedRead { read in read.cancel() }
}
