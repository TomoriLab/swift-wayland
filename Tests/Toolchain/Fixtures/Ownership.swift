final class ReleaseLedger {
    var releases = 0
}

final class CleanupRecord {
    let ledger: ReleaseLedger
    private var released = false

    init(_ ledger: ReleaseLedger) { self.ledger = ledger }

    func release() {
        if !released {
            released = true
            ledger.releases += 1
        }
    }
}

struct Owner: ~Copyable {
    let record: CleanupRecord
    let value: Int

    borrowing func read() -> Int { value }
    consuming func close() { record.release() }
    deinit { record.release() }
}

func transfer<Value: ~Copyable>(_ value: consuming Value) -> Value { value }

enum ProbeError: Error { case expected }

func failingScope(_ ledger: ReleaseLedger) throws(ProbeError) {
    let owner = Owner(record: CleanupRecord(ledger), value: 13)
    precondition(owner.read() == 13)
    throw .expected
}

@main struct OwnershipProbe {
    static func main() {
        let ledger = ReleaseLedger()
        let owner = Owner(record: CleanupRecord(ledger), value: 7)
        let transferred = transfer(owner)
        precondition(transferred.read() == 7)
        transferred.close()
        precondition(ledger.releases == 1)
        do {
            try failingScope(ledger)
            preconditionFailure("The expected failure did not occur.")
        } catch {
            precondition(error == .expected)
        }
        precondition(ledger.releases == 2)
        do {
            let owner = Owner(record: CleanupRecord(ledger), value: 9)
            precondition(owner.read() == 9)
        }
        precondition(ledger.releases == 3)
        var owners = UniqueArray<Owner>()
        owners.append(Owner(record: CleanupRecord(ledger), value: 11))
        precondition(owners.count == 1)
        owners.removeAll()
        precondition(ledger.releases == 4)
        print("PASS ownership transfer, explicit/fallback/throw cleanup, UniqueArray")
    }
}
