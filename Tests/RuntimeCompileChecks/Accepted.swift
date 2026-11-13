import WaylandRuntime

func inspect(_ owner: borrowing OwnedHandle) -> HandleIdentity { owner.reference.identity }
func close(_ owner: consuming OwnedHandle) { owner.close() }
func reference(_ handle: ObjectHandle) throws -> Int { try handle.withAccess { 42 } }

func cancelAcrossTasks(_ token: CallbackCancellation) {
    Task.detached { token.cancel() }
}
func descriptor(_ owner: borrowing OwnedFileDescriptor) -> BorrowedFileDescriptor { owner.borrowed }
func received(_ owner: consuming ReceivedFileDescriptor, session: borrowing OwnershipSession) throws -> OwnedFileDescriptor {
    try owner.register(in: session)
}

func cancelReadAcrossTasks(_ cancellation: ReadCancellation) {
    Task.detached { cancellation.cancel() }
}
