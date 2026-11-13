import WaylandRuntime

func inspect(_ owner: borrowing OwnedHandle) -> HandleIdentity { owner.reference.identity }
func close(_ owner: consuming OwnedHandle) { owner.close() }
func reference(_ handle: ObjectHandle) throws -> Int { try handle.withAccess { 42 } }
