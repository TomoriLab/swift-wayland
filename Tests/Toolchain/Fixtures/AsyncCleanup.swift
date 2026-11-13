actor StartGate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

actor CleanupLedger {
    private var count = 0
    func record() { count += 1 }
    func total() -> Int { count }
}

func operation(_ ledger: CleanupLedger) async {
    precondition(Task.isCancelled)
    defer {
        await withTaskCancellationShield {
            precondition(!Task.isCancelled)
            await ledger.record()
        }
    }
    await Task.yield()
}

@main struct AsyncCleanupProbe {
    static func main() async {
        let ledger = CleanupLedger()
        let gate = StartGate()
        let task = Task {
            await gate.wait()
            await operation(ledger)
        }
        task.cancel()
        await gate.open()
        await task.value
        let result = await ledger.total()
        precondition(result == 1)
        print("PASS async defer and cancellation shield after deterministic cancellation")
    }
}
