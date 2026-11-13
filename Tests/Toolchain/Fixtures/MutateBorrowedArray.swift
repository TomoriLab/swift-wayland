func rejected() -> UInt8 {
    var bytes: [UInt8] = [4]
    let span = bytes.span
    bytes.append(5)
    return span[0]
}
