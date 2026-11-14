import CWaylandUtilities

extension UtilitiesInterop {
    /// Recovers a C allocation address from a caller-proven native member offset.
    ///
    /// The offset must come from the actual C layout. The resulting address must
    /// remain within the live allocation and have the target native alignment.
    @unsafe public static func wl_container_of(_ member: UnsafeMutableRawPointer, memberOffset: Int) -> UnsafeMutableRawPointer {
        precondition(memberOffset >= 0)
        return unsafe member.advanced(by: -memberOffset)
    }
    /// Visits initialized C array elements without exposing arbitrary Swift value interpretations.
    ///
    /// The caller proves allocation lifetime, a positive element size, complete
    /// initialized elements, and that callbacks do not resize or free the array.
    @unsafe public static func wl_array_for_each(
        _ array: UnsafePointer<wl_array>, elementSize: Int, _ body: (UnsafeMutableRawPointer) throws -> Void
    ) rethrows {
        let size = unsafe array.pointee.size
        precondition(elementSize > 0 && size >= 0 && size % elementSize == 0)
        if size == 0 { return }
        let data = unsafe array.pointee.data!
        var offset = 0
        while offset < size { unsafe try body(data.advanced(by: offset)); offset += elementSize }
    }
    @unsafe private static func walk(
        _ head: UnsafeMutablePointer<wl_list>, memberOffset: Int, reverse: Bool, preload: Bool,
        _ body: (UnsafeMutableRawPointer) throws -> Void
    ) rethrows {
        precondition(memberOffset >= 0)
        var current = unsafe reverse ? head.pointee.prev! : head.pointee.next!
        while unsafe current != head {
            let saved = unsafe preload ? (reverse ? current.pointee.prev! : current.pointee.next!) : current
            unsafe try body(UnsafeMutableRawPointer(current).advanced(by: -memberOffset))
            unsafe current = preload ? saved : (reverse ? current.pointee.prev! : current.pointee.next!)
        }
    }
    /// Traverses a live native intrusive list; callbacks must preserve the current node and links.
    @unsafe public static func wl_list_for_each(_ head: UnsafeMutablePointer<wl_list>, memberOffset: Int,
                                                _ body: (UnsafeMutableRawPointer) throws -> Void) rethrows {
        unsafe try walk(head, memberOffset: memberOffset, reverse: false, preload: false, body)
    }
    /// Traverses in reverse while preserving the native current-node mutation restrictions.
    @unsafe public static func wl_list_for_each_reverse(_ head: UnsafeMutablePointer<wl_list>, memberOffset: Int,
                                                        _ body: (UnsafeMutableRawPointer) throws -> Void) rethrows {
        unsafe try walk(head, memberOffset: memberOffset, reverse: true, preload: false, body)
    }
    /// Preloads the next link; callbacks may remove the current node but must retain the next node and head.
    @unsafe public static func wl_list_for_each_safe(_ head: UnsafeMutablePointer<wl_list>, memberOffset: Int,
                                                     _ body: (UnsafeMutableRawPointer) throws -> Void) rethrows {
        unsafe try walk(head, memberOffset: memberOffset, reverse: false, preload: true, body)
    }
    /// Preloads the previous link under the native reverse-safe mutation contract.
    @unsafe public static func wl_list_for_each_reverse_safe(_ head: UnsafeMutablePointer<wl_list>, memberOffset: Int,
                                                             _ body: (UnsafeMutableRawPointer) throws -> Void) rethrows {
        unsafe try walk(head, memberOffset: memberOffset, reverse: true, preload: true, body)
    }
}
