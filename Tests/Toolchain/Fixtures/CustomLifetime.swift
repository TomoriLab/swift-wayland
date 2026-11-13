@lifetime(borrow bytes)
func view(_ bytes: borrowing [UInt8]) -> Span<UInt8> {
    bytes.span
}
