@unsafe func read(_ pointer: UnsafePointer<Int>) -> Int {
    unsafe pointer.pointee
}

@main struct AuditedPointerProbe {
    static func main() {
        let value = 5
        let result = withUnsafePointer(to: value) { pointer in
            // The synchronous pointer scope keeps initialized storage alive for read.
            unsafe read(pointer)
        }
        precondition(result == 5)
        print("PASS explicit audited unsafe boundary")
    }
}
