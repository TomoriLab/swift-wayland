// This executable is a single-threaded reference experiment, not the production runtime.
final class GraphLedger {
    var acquisitions = 0
    var releases = 0
}

final class GraphRecord {
    let generation: UInt64
    let ledger: GraphLedger
    private(set) var live = true

    init(generation: UInt64, ledger: GraphLedger) {
        self.generation = generation
        self.ledger = ledger
        ledger.acquisitions += 1
    }

    func release() {
        if live {
            live = false
            ledger.releases += 1
        }
    }
}

final class GraphControl {
    private(set) var closing = false
    private var frames = 0
    private var records: [UInt64: GraphRecord] = [:]
    private var nextGeneration: UInt64 = 0
    let ledger: GraphLedger

    init(ledger: GraphLedger) { self.ledger = ledger }

    func create() -> GraphReference {
        precondition(!closing && nextGeneration < UInt64.max)
        nextGeneration += 1
        let record = GraphRecord(generation: nextGeneration, ledger: ledger)
        records[nextGeneration] = record
        return GraphReference(control: self, generation: record.generation)
    }

    func isValid(_ generation: UInt64) -> Bool {
        !closing && records[generation]?.live == true
    }

    func withNativeFrame(_ body: () -> Void) {
        precondition(!closing)
        frames += 1
        defer {
            frames -= 1
            drain()
        }
        body()
    }

    func requestClose() {
        closing = true
        drain()
    }

    private func drain() {
        if closing && frames == 0 {
            for record in records.values { record.release() }
            records.removeAll()
        }
    }
}

struct GraphReference {
    let control: GraphControl
    let generation: UInt64
    var valid: Bool { control.isValid(generation) }
}

struct GraphRootOwner: ~Copyable {
    let control: GraphControl
    consuming func close() { control.requestClose() }
    deinit { control.requestClose() }
}

func releaseRootWhileReferenceSurvives(_ ledger: GraphLedger) -> GraphReference {
    let control = GraphControl(ledger: ledger)
    let root = GraphRootOwner(control: control)
    let reference = control.create()
    precondition(reference.valid)
    _ = root
    return reference
}

@main struct OwnershipGraphProbe {
    static func main() {
        let ledger = GraphLedger()
        let stale = releaseRootWhileReferenceSurvives(ledger)
        precondition(!stale.valid && ledger.releases == 1)

        let control = GraphControl(ledger: ledger)
        let root = GraphRootOwner(control: control)
        let child = control.create()
        let forged = GraphReference(control: control, generation: child.generation + 1)
        precondition(!forged.valid)
        // Dropping this reference must not remove its authoritative cleanup record.
        _ = control.create()
        control.withNativeFrame {
            control.requestClose()
            precondition(!child.valid)
            precondition(ledger.releases == 1)
        }
        precondition(ledger.acquisitions == 3 && ledger.releases == 3)
        root.close()
        precondition(ledger.releases == 3)
        print("PASS reference graph: root close, lost cell, stale identity, deferred frame cleanup")
    }
}
