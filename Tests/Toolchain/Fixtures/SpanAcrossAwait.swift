@main struct SpanAcrossAwaitProbe {
    static func main() async {
        let bytes: [UInt8] = [1, 2]
        let span = bytes.span
        await Task.yield()
        precondition(span[0] == 1 && span.count == 2)
        print("PASS locally backed Span can survive await; no native no-suspension proof")
    }
}
