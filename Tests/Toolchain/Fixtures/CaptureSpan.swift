func rejected(_ bytes: borrowing Span<UInt8>) -> () -> Int {
    return { bytes.count }
}
