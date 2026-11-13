final class ConsumptionLedger {
    var closes = 0
    var destructions = 0
}
struct Child: ~Copyable {
    let ledger: ConsumptionLedger
    consuming func close() { ledger.closes += 1 }
    deinit { ledger.destructions += 1 }
}
struct Parent: ~Copyable {
    let child: Child
    deinit { child.close() }
}
func scope(_ ledger: ConsumptionLedger) {
    let parent = Parent(child: Child(ledger: ledger))
    _ = parent
}
@main struct ConsumeInDeinitProbe {
    static func main() {
        let ledger = ConsumptionLedger()
        scope(ledger)
        precondition(ledger.closes == 1 && ledger.destructions == 1)
        print("PASS consuming a noncopyable field in deinit without experimental flags")
    }
}
