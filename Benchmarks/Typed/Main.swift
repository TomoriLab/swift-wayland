import Foundation
import CWaylandClient
import WaylandClient
import WaylandProtocol
import RuntimeNativeTestSupport

private struct Sample {
    let seconds: Double
    let allocations: UInt64
    let cpuSeconds: Double
    let teardownSeconds: Double
    let latencies: [UInt64]
    let phaseNanoseconds: [UInt64]
}
private final class Counter { var value = 0 }
@unsafe private func rawSwiftScalar(
    _ implementation: UnsafeRawPointer?, _ target: UnsafeMutableRawPointer?, _ opcode: UInt32,
    _ message: UnsafePointer<wl_message>?, _ arguments: UnsafeMutablePointer<wl_argument>?
) -> Int32 {
    guard opcode == 2, let implementation = unsafe implementation,
          let arguments = unsafe arguments, unsafe arguments[0].u == 17 else { return -1 }
    unsafe UnsafeMutablePointer<UInt32>(mutating: implementation.assumingMemoryBound(to: UInt32.self)).pointee += 1
    return 0
}
@unsafe private func rawSwiftReadAndDispatch(_ display: OpaquePointer?) -> Int32 {
    guard let display = unsafe display else { return -1 }
    guard unsafe wl_display_prepare_read(display) == 0 else { return -1 }
    guard unsafe wl_display_read_events(display) == 0 else { return -1 }
    return unsafe wl_display_dispatch_pending(display) < 0 ? -1 : 0
}
@main struct TypedBenchmark {
    private static func sample(iterations: Int, batch: Int, measureLatency: Bool, measurePhases: Bool, cancelDelivery: Bool = false) throws -> Sample {
        var descriptor: Int32 = -1
        guard let server = unsafe runtime_core_server_create(&descriptor) else { fatalError("Cannot allocate benchmark peer.") }
        var serverDestroyed = false
        defer { if !serverDestroyed { unsafe runtime_core_server_destroy(server) } }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        try connection.flush()
        precondition(unsafe runtime_core_server_dispatch(server) == 0)
        try connection.withPreparedRead { try $0.read() }
        _ = try connection.dispatchPending()
        let name = unsafe runtime_core_server_global(server, "wl_data_offer")
        let offer = try registry.reference.bind(name: name, as: WlDataOffer.self, version: 3, advertisedVersion: 3)
        let counter = Counter()
        let subscription = try offer.onEvent { event in
            switch consume event {
            case .action(let action): precondition(action.rawValue == 17); counter.value += 1
            default: preconditionFailure("Unexpected benchmark event.")
            }
        }
        try connection.flush()
        precondition(unsafe runtime_core_server_dispatch(server) == 0)
        let identifier = try offer.reference.identifier()
        unsafe runtime_core_server_scalar_batch(server, identifier, UInt32(batch))
        _ = try connection.readAndDispatchPending()
        counter.value = 0
        if cancelDelivery { subscription.cancel() }
        var latencies = [UInt64](repeating: 0, count: measureLatency ? (iterations + batch - 1) / batch : 0)
        var phases = [UInt64](repeating: 0, count: 3)
        let cpuStart = runtime_test_thread_nanoseconds()
        runtime_test_allocation_begin()
        let start = runtime_test_clock_nanoseconds()
        for index in stride(from: 0, to: iterations, by: batch) {
            let batchStart = measureLatency ? runtime_test_clock_nanoseconds() : 0
            let phaseStart = measurePhases ? runtime_test_clock_nanoseconds() : 0
            unsafe runtime_core_server_scalar_batch(server, identifier, UInt32(min(batch, iterations - index)))
            let sent = measurePhases ? runtime_test_clock_nanoseconds() : 0
            if measurePhases {
                try connection.withPreparedRead { try $0.read() }
                let read = runtime_test_clock_nanoseconds()
                _ = try connection.dispatchPending()
                let dispatched = runtime_test_clock_nanoseconds()
                phases[0] += sent - phaseStart
                phases[1] += read - sent
                phases[2] += dispatched - read
            } else { _ = try connection.readAndDispatchPending() }
            if measureLatency { latencies[index / batch] = runtime_test_clock_nanoseconds() - batchStart }
        }
        let elapsed = runtime_test_clock_nanoseconds() - start
        let allocations = runtime_test_allocation_end()
        let cpu = Double(runtime_test_thread_nanoseconds() - cpuStart) / 1e9
        precondition(counter.value == (cancelDelivery ? 0 : iterations))
        withExtendedLifetime(subscription) {}
        let teardownStart = runtime_test_clock_nanoseconds()
        connection.requestClose()
        unsafe runtime_core_server_destroy(server)
        serverDestroyed = true
        let teardown = Double(runtime_test_clock_nanoseconds() - teardownStart) / 1e9
        return Sample(seconds: Double(elapsed) / 1e9, allocations: allocations, cpuSeconds: cpu, teardownSeconds: teardown, latencies: latencies, phaseNanoseconds: phases)
    }
    private static func requestSample(iterations: Int, batch: Int, measureLatency: Bool = false) throws -> (seconds: Double, allocations: UInt64, latencies: [UInt64]) {
        var descriptor: Int32 = -1
        guard let server = unsafe runtime_core_server_create(&descriptor) else { fatalError("Cannot allocate benchmark peer.") }
        defer { unsafe runtime_core_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let name = unsafe runtime_core_server_global(server, "wl_surface")
        let surface = try registry.reference.bind(name: name, as: WlSurface.self, version: 1, advertisedVersion: 1)
        try surface.reference.commit()
        try connection.flush()
        precondition(unsafe runtime_core_server_dispatch(server) == 0)
        var latencies = [UInt64](repeating: 0, count: measureLatency ? (iterations + batch - 1) / batch : 0)
        let before = unsafe runtime_core_server_requests(server)
        runtime_test_allocation_begin()
        let start = runtime_test_clock_nanoseconds()
        for index in stride(from: 0, to: iterations, by: batch) {
            let batchStart = measureLatency ? runtime_test_clock_nanoseconds() : 0
            for _ in 0..<min(batch, iterations - index) { try surface.reference.commit() }
            try connection.flush()
            precondition(unsafe runtime_core_server_dispatch(server) == 0)
            if measureLatency { latencies[index / batch] = runtime_test_clock_nanoseconds() - batchStart }
        }
        let elapsed = runtime_test_clock_nanoseconds() - start
        let allocations = runtime_test_allocation_end()
        precondition(unsafe runtime_core_server_requests(server) - before == UInt32(iterations))
        connection.requestClose()
        return (Double(elapsed) / 1e9, allocations, latencies)
    }
    private static func stringRequestSample(iterations: Int, batch: Int, measureLatency: Bool = false) throws -> (seconds: Double, allocations: UInt64, latencies: [UInt64]) {
        var descriptor: Int32 = -1
        guard let server = unsafe runtime_core_server_create(&descriptor) else { fatalError("Cannot allocate benchmark peer.") }
        defer { unsafe runtime_core_server_destroy(server) }
        let connection = unsafe try ClientConnection(receiving: descriptor)
        let registry = try connection.protocolDisplay().getRegistry()
        let name = unsafe runtime_core_server_global(server, "wl_data_source")
        let source = try registry.reference.bind(name: name, as: WlDataSource.self, version: 1, advertisedVersion: 1)
        try source.reference.offer(mimeType: "waylandkit-test")
        try connection.flush()
        precondition(unsafe runtime_core_server_dispatch(server) == 0)
        var latencies = [UInt64](repeating: 0, count: measureLatency ? (iterations + batch - 1) / batch : 0)
        let before = unsafe runtime_core_server_requests(server)
        runtime_test_allocation_begin()
        let start = runtime_test_clock_nanoseconds()
        for index in stride(from: 0, to: iterations, by: batch) {
            let batchStart = measureLatency ? runtime_test_clock_nanoseconds() : 0
            for _ in 0..<min(batch, iterations - index) { try source.reference.offer(mimeType: "waylandkit-test") }
            try connection.flush()
            precondition(unsafe runtime_core_server_dispatch(server) == 0)
            if measureLatency { latencies[index / batch] = runtime_test_clock_nanoseconds() - batchStart }
        }
        let elapsed = runtime_test_clock_nanoseconds() - start
        let allocations = runtime_test_allocation_end()
        precondition(unsafe runtime_core_server_requests(server) - before == UInt32(iterations))
        connection.requestClose()
        return (Double(elapsed) / 1e9, allocations, latencies)
    }
    static func main() throws {
        if CommandLine.arguments.contains("--string-request-latency") {
            var samples: [[String: Any]] = []
            for batch in [1, 64] {
                var allocations: UInt64 = 0
                var latencies = [UInt64](repeating: 0, count: (20_000 + batch - 1) / batch)
                latencies.withUnsafeMutableBufferPointer { buffer in
                    _ = unsafe runtime_core_benchmark_string_requests(20_000, UInt32(batch), &allocations, buffer.baseAddress)
                }
                let result = try stringRequestSample(iterations: 20_000, batch: batch, measureLatency: true)
                samples.append(["batch": batch, "native": latencies, "swift": result.latencies])
            }
            print(String(decoding: try JSONSerialization.data(withJSONObject: ["samples": samples], options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
            return
        }
        if CommandLine.arguments.contains("--request-latency") {
            var samples: [[String: Any]] = []
            for batch in [1, 64] {
                var allocations: UInt64 = 0
                var latencies = [UInt64](repeating: 0, count: (20_000 + batch - 1) / batch)
                latencies.withUnsafeMutableBufferPointer { buffer in
                    _ = unsafe runtime_core_benchmark_requests(20_000, UInt32(batch), &allocations, buffer.baseAddress)
                }
                let result = try requestSample(iterations: 20_000, batch: batch, measureLatency: true)
                samples.append(["batch": batch, "native": latencies, "swift": result.latencies])
            }
            print(String(decoding: try JSONSerialization.data(withJSONObject: ["samples": samples], options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
            return
        }
        if CommandLine.arguments.contains("--requests") {
            let allocationsAvailable = runtime_test_allocation_available() != 0
            var samples: [[String: Any]] = []
            for batch in [1, 64] {
                var native: [Double] = [], swift: [Double] = []
                var nativeAllocations: [UInt64] = [], swiftAllocations: [UInt64] = []
                for index in 0..<9 {
                    func nativeSample() {
                        var allocations: UInt64 = 0
                        native.append(unsafe runtime_core_benchmark_requests(20_000, UInt32(batch), &allocations, nil))
                        nativeAllocations.append(allocations)
                    }
                    func swiftSample() throws {
                        let result = try requestSample(iterations: 20_000, batch: batch)
                        swift.append(result.seconds); swiftAllocations.append(result.allocations)
                    }
                    if index.isMultiple(of: 2) { nativeSample(); try swiftSample() }
                    else { try swiftSample(); nativeSample() }
                }
                samples.append(["batch": batch, "iterations": 20_000, "nativeSeconds": native, "swiftSeconds": swift,
                                "allocationCounterAvailable": allocationsAvailable, "nativeAllocations": nativeAllocations, "swiftAllocations": swiftAllocations,
                                "throughputLoss": 1 - native.sorted()[4] / swift.sorted()[4]])
            }
            print(String(decoding: try JSONSerialization.data(withJSONObject: ["samples": samples], options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
            return
        }
        if CommandLine.arguments.contains("--string-requests") {
            let allocationsAvailable = runtime_test_allocation_available() != 0
            var samples: [[String: Any]] = []
            for batch in [1, 64] {
                var native: [Double] = [], swift: [Double] = []
                var nativeAllocations: [UInt64] = [], swiftAllocations: [UInt64] = []
                for index in 0..<9 {
                    func nativeSample() {
                        var allocations: UInt64 = 0
                        native.append(unsafe runtime_core_benchmark_string_requests(20_000, UInt32(batch), &allocations, nil))
                        nativeAllocations.append(allocations)
                    }
                    func swiftSample() throws {
                        let result = try stringRequestSample(iterations: 20_000, batch: batch)
                        swift.append(result.seconds); swiftAllocations.append(result.allocations)
                    }
                    if index.isMultiple(of: 2) { nativeSample(); try swiftSample() }
                    else { try swiftSample(); nativeSample() }
                }
                samples.append(["batch": batch, "iterations": 20_000, "nativeSeconds": native, "swiftSeconds": swift,
                                "allocationCounterAvailable": allocationsAvailable, "nativeAllocations": nativeAllocations, "swiftAllocations": swiftAllocations,
                                "throughputLoss": 1 - native.sorted()[4] / swift.sorted()[4]])
            }
            print(String(decoding: try JSONSerialization.data(withJSONObject: ["samples": samples], options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
            return
        }
        if CommandLine.arguments.contains("--read-isolation") {
            let iterations = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 200_000
            var isolationSamples: [[String: Any]] = []
            for batch in [1, 64] {
                var native: [Double] = [], rawSwiftRead: [Double] = []
                for index in 0..<9 {
                    func nativeSample() {
                        native.append(unsafe runtime_core_benchmark_swift_callback(UInt32(iterations), UInt32(batch), rawSwiftScalar))
                    }
                    func swiftSample() {
                        rawSwiftRead.append(unsafe runtime_core_benchmark_swift_read(UInt32(iterations), UInt32(batch), rawSwiftScalar, rawSwiftReadAndDispatch))
                    }
                    if index.isMultiple(of: 2) { nativeSample(); swiftSample() }
                    else { swiftSample(); nativeSample() }
                }
                isolationSamples.append(["batch": batch, "iterations": iterations,
                                         "nativeSeconds": native, "rawSwiftReadSeconds": rawSwiftRead,
                                         "rawSwiftReadLoss": 1 - native.sorted()[native.count / 2] / rawSwiftRead.sorted()[rawSwiftRead.count / 2]])
            }
            print(String(decoding: try JSONSerialization.data(withJSONObject: ["samples": isolationSamples], options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
            return
        }
        if CommandLine.arguments.contains("--ownership-isolation") {
            let iterations = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 20_000
            var isolationSamples: [[String: Any]] = []
            for batch in [1, 64] {
                var native: [Double] = [], canceled: [Double] = []
                for index in 0..<9 {
                    func nativeSample() {
                        var allocations: UInt64 = 0
                        var cpu = 0.0, teardown = 0.0
                        native.append(unsafe runtime_core_benchmark_c(UInt32(iterations), UInt32(batch), &allocations, nil, &cpu, &teardown, nil))
                    }
                    func canceledSample() throws {
                        canceled.append(try sample(iterations: iterations, batch: batch, measureLatency: false, measurePhases: false, cancelDelivery: true).seconds)
                    }
                    if index.isMultiple(of: 2) { nativeSample(); try canceledSample() }
                    else { try canceledSample(); nativeSample() }
                }
                isolationSamples.append(["batch": batch, "iterations": iterations,
                                         "nativeSeconds": native, "canceledSeconds": canceled,
                                         "canceledDeliveryLoss": 1 - native.sorted()[native.count / 2] / canceled.sorted()[canceled.count / 2]])
            }
            print(String(decoding: try JSONSerialization.data(withJSONObject: ["samples": isolationSamples], options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
            return
        }
        if CommandLine.arguments.contains("--callback-isolation") {
            let iterations = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 200_000
            var isolationSamples: [[String: Any]] = []
            for batch in [1, 64] {
                var native: [Double] = [], rawSwift: [Double] = []
                for index in 0..<9 {
                    func nativeSample() {
                        var allocations: UInt64 = 0
                        var cpu = 0.0, teardown = 0.0
                        native.append(unsafe runtime_core_benchmark_c(UInt32(iterations), UInt32(batch), &allocations, nil, &cpu, &teardown, nil))
                    }
                    func rawSwiftSample() {
                        rawSwift.append(unsafe runtime_core_benchmark_swift_callback(UInt32(iterations), UInt32(batch), rawSwiftScalar))
                    }
                    if index.isMultiple(of: 2) { nativeSample(); rawSwiftSample() }
                    else { rawSwiftSample(); nativeSample() }
                }
                let nativeMedian = native.sorted()[native.count / 2]
                let swiftMedian = rawSwift.sorted()[rawSwift.count / 2]
                isolationSamples.append(["batch": batch, "iterations": iterations,
                                         "nativeSeconds": native, "rawSwiftSeconds": rawSwift,
                                         "rawSwiftCallbackLoss": 1 - nativeMedian / swiftMedian])
            }
            print(String(decoding: try JSONSerialization.data(withJSONObject: ["samples": isolationSamples], options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
            return
        }
        let allocationsAvailable = runtime_test_allocation_available() != 0
        let measureLatency = CommandLine.arguments.contains("--latency")
        let measurePhases = CommandLine.arguments.contains("--phases")
        var reports: [[String: Any]] = []
        for batch in [1, 64] {
            let iterations = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 20_000
            var native: [Double] = [], swift: [Double] = []
            var nativeAllocations: [UInt64] = [], swiftAllocations: [UInt64] = []
            var nativeCpu: [Double] = [], swiftCpu: [Double] = []
            var nativeTeardown: [Double] = [], swiftTeardown: [Double] = []
            var nativeLatency: [UInt64] = [], swiftLatency: [UInt64] = []
            var nativePhases: [UInt64] = [], swiftPhases: [UInt64] = []
            for index in 0..<(measureLatency || measurePhases ? 1 : 9) {
                func nativeSample() {
                    var allocations: UInt64 = 0
                    var latency = [UInt64](repeating: 0, count: measureLatency ? (iterations + batch - 1) / batch : 0)
                    var cpu = 0.0, teardown = 0.0
                    var phases = [UInt64](repeating: 0, count: 3)
                    let seconds = latency.withUnsafeMutableBufferPointer { buffer in
                        phases.withUnsafeMutableBufferPointer { phaseBuffer in
                            unsafe runtime_core_benchmark_c(UInt32(iterations), UInt32(batch), &allocations,
                                measureLatency ? buffer.baseAddress : nil, &cpu, &teardown,
                                measurePhases ? phaseBuffer.baseAddress : nil)
                        }
                    }
                    native.append(seconds)
                    nativeAllocations.append(allocations)
                    nativeCpu.append(cpu); nativeTeardown.append(teardown); nativeLatency += latency
                    nativePhases = phases
                }
                func swiftSample() throws {
                    let result = try sample(iterations: iterations, batch: batch, measureLatency: measureLatency, measurePhases: measurePhases)
                    swift.append(result.seconds); swiftAllocations.append(result.allocations)
                    swiftCpu.append(result.cpuSeconds); swiftTeardown.append(result.teardownSeconds); swiftLatency += result.latencies
                    swiftPhases = result.phaseNanoseconds
                }
                if index.isMultiple(of: 2) { nativeSample(); try swiftSample() }
                else { try swiftSample(); nativeSample() }
            }
            reports.append(["batch": batch, "iterations": iterations, "nativeSeconds": native, "swiftSeconds": swift,
                            "nativeAllocations": nativeAllocations, "swiftAllocations": swiftAllocations,
                            "nativeCpuSeconds": nativeCpu, "swiftCpuSeconds": swiftCpu,
                            "nativeTeardownSeconds": nativeTeardown, "swiftRootCloseSeconds": swiftTeardown,
                            "nativeBatchLatenciesNanoseconds": nativeLatency, "swiftBatchLatenciesNanoseconds": swiftLatency,
                            "nativePhaseNanoseconds": nativePhases, "swiftPhaseNanoseconds": swiftPhases,
                            "throughputLoss": 1 - native.sorted()[native.count / 2] / swift.sorted()[swift.count / 2]])
        }
        let report: [String: Any] = ["allocationCounterAvailable": allocationsAvailable, "samples": reports,
                                   "scope": "Typed wl_data_offer.action scalar delivery through identical native socketpair peers, including native send/read/dispatch; setup, one batch warmup, and teardown excluded."]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
