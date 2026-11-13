func rejected() -> UInt8 {
    let span: Span<UInt8>
    do {
        let bytes: [UInt8] = [4]
        span = bytes.span
    }
    return span[0]
}
