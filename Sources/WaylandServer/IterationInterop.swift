import CWaylandServer

extension ServerInterop {
    /// Traverses a caller-proven native client list without snapshot or lifetime guarantees.
    ///
    /// The caller preserves the list, current client, and next link through each
    /// callback and supplies the complete native frame when mixing safe owners.
    @unsafe public static func wl_client_for_each(_ head: UnsafeMutablePointer<wl_list>, _ body: (OpaquePointer) throws -> Void) rethrows {
        var current = unsafe head.pointee.next!
        while unsafe current != head {
            let client = unsafe CWaylandServer.wl_client_from_link(current)!
            unsafe try body(client)
            unsafe current = CWaylandServer.wl_client_get_link(client).pointee.next!
        }
    }
    /// Traverses native resource links while preserving current-node lifetime and list topology.
    @unsafe public static func wl_resource_for_each(_ head: UnsafeMutablePointer<wl_list>,
                                                     _ body: (UnsafeMutablePointer<wl_resource>) throws -> Void) rethrows {
        var current = unsafe head.pointee.next!
        while unsafe current != head {
            let resource = unsafe CWaylandServer.wl_resource_from_link(current)!
            unsafe try body(resource)
            unsafe current = CWaylandServer.wl_resource_get_link(resource).pointee.next!
        }
    }
    /// Preloads the next resource link; callbacks may remove only the current resource.
    @unsafe public static func wl_resource_for_each_safe(_ head: UnsafeMutablePointer<wl_list>,
                                                          _ body: (UnsafeMutablePointer<wl_resource>) throws -> Void) rethrows {
        var current = unsafe head.pointee.next!
        while unsafe current != head {
            let next = unsafe current.pointee.next!
            let resource = unsafe CWaylandServer.wl_resource_from_link(current)!
            unsafe try body(resource)
            unsafe current = next
        }
    }
}
