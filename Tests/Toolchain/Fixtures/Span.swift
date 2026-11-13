func checksum(_ bytes: borrowing Span<UInt8>) -> UInt32 {
    var result: UInt32 = 0
    for index in 0..<bytes.count { result += UInt32(bytes[index]) }
    return result
}

@main struct SpanProbe {
    static func main() {
        let bytes: [UInt8] = [2, 3, 5]
        let span = bytes.span
        precondition(checksum(span) == 10)
        precondition(checksum(bytes.span) == 10)
        print("PASS standard-library Span construction and borrowing")
    }
}
