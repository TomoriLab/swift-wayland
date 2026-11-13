import Foundation
import WaylandRuntime
import WaylandClient
import RuntimeNativeTestSupport

private final class Counter {
    var value = 0
}

@main struct DispatcherBenchmark {
    static func swiftSample(iterations: Int) throws -> Double {
        guard let peer = unsafe runtime_test_peer_create() else { fatalError("Cannot allocate native benchmark peer.") }
        defer { unsafe runtime_test_peer_destroy(peer) }
        guard let proxy = unsafe runtime_test_peer_proxy(peer) else { fatalError("Cannot allocate benchmark proxy.") }
        let session = try OwnershipSession()
        let counter = Counter()
        let owner = unsafe try ClientProxyDispatcher(receiving: proxy, in: session, context: counter) { counter, event in
            precondition(event.opcode == 0 && event.arguments == [.unsigned(42)])
            counter.value += 1
        }
        let start = ContinuousClock.now
        for _ in 0..<iterations {
            try session.withNativeFrame {
                unsafe runtime_test_peer_post(peer, 0, -1)
                precondition(unsafe runtime_test_peer_dispatch(peer) >= 0)
            }
        }
        let elapsed = start.duration(to: .now).components
        precondition(counter.value == iterations)
        owner.close()
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }
    static func main() throws {
        let iterations = 10_000
        _ = runtime_test_c_benchmark(1000)
        _ = try swiftSample(iterations: 1000)
        var native: [Double] = []
        var swift: [Double] = []
        for index in 0..<9 {
            if index.isMultiple(of: 2) {
                native.append(runtime_test_c_benchmark(UInt32(iterations)))
                swift.append(try swiftSample(iterations: iterations))
            } else {
                swift.append(try swiftSample(iterations: iterations))
                native.append(runtime_test_c_benchmark(UInt32(iterations)))
            }
        }
        let nativeMedian = native.sorted()[native.count / 2]
        let swiftMedian = swift.sorted()[swift.count / 2]
        let report: [String: Any] = [
            "iterationsPerSample": iterations, "warmupEvents": 1000, "samples": native.count,
            "nativeSeconds": native, "swiftSeconds": swift,
            "nativeMedianEventsPerSecond": Double(iterations) / nativeMedian,
            "swiftMedianEventsPerSecond": Double(iterations) / swiftMedian,
            "swiftThroughputLossFraction": 1 - nativeMedian / swiftMedian,
            "scope": "Scalar event through identical native socketpair peers; generic Swift observation dispatcher versus C counter dispatcher. Setup and teardown excluded.",
            "unmeasured": ["per-event allocation count", "latency distribution", "representative compositor", "generated typed dispatch"]
        ]
        let bytes = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: bytes, as: UTF8.self))
    }
}
