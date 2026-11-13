import WaylandRuntime
func rejected(_ reference: BorrowedFileDescriptor) throws {
    try reference.withUnsafeDescriptor { _ in }
}
