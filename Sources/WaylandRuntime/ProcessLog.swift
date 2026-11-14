import Glibc
import CWaylandRuntime

/// Owns a bounded native log message independently of the C callback scope.
public struct ProcessLogMessage: Equatable, Sendable {
    /// Formatted text with invalid UTF-8 replaced.
    public let text: String
    /// Whether the 65536-byte copied payload limit truncated the message.
    public let truncated: Bool
}
/// Describes a managed logging initialization or generation failure.
public enum ProcessLogError: Error, Equatable, Sendable {
    /// Quiescent native installation has not completed.
    case notInitialized
    /// Another initialization is in progress.
    case initializing
    /// The nonwrapping handler generation cannot advance.
    case generationExhausted
}
private struct ProcessLogSlot: Sendable {
    var ready = false
    var initializing = false
    var generation: UInt64 = 0
    var handler: (@Sendable (ProcessLogMessage) -> Void)?
}

/// Synchronizes process-global handler publication without owning native resources.
///
/// Native installation must precede concurrent logging. Published handlers run
/// outside the mutex and may be in flight after a subscription is canceled.
package final class ProcessLogStorage: Sendable {
    private let slot: RuntimeMutex<ProcessLogSlot>
    /// Allocates the audited synchronization primitive without suppressing failure.
    package init() throws { slot = try RuntimeMutex(ProcessLogSlot()) }
    /// Installs a permanent native trampoline under an externally proven quiescence contract.
    @unsafe package func initialize(_ install: () -> Void) throws {
        let needed = try slot.withLock { slot in
            if slot.ready { return false }
            guard !slot.initializing else { throw ProcessLogError.initializing }
            slot.initializing = true
            return true
        }
        if !needed { return }
        install()
        slot.withLock { $0.ready = true; $0.initializing = false }
    }
    /// Replaces the current handler and returns generation-scoped cancellation authority.
    package func observe(_ handler: @escaping @Sendable (ProcessLogMessage) -> Void) throws -> ProcessLogSubscription {
        let (generation, previous) = try slot.withLock { slot in
            guard slot.ready else { throw ProcessLogError.notInitialized }
            guard slot.generation < UInt64.max else { throw ProcessLogError.generationExhausted }
            slot.generation += 1
            let previous = slot.handler
            slot.handler = handler
            return (slot.generation, previous)
        }
        withExtendedLifetime(previous) {}
        return ProcessLogSubscription(storage: self, generation: generation)
    }
    fileprivate func cancel(_ generation: UInt64) {
        let previous = slot.withLock { slot -> (@Sendable (ProcessLogMessage) -> Void)? in
            guard slot.generation == generation else { return nil }
            let previous = slot.handler
            slot.handler = nil
            return previous
        }
        withExtendedLifetime(previous) {}
    }
    /// Copies one proven native callback argument scope and invokes a retained handler outside the mutex.
    ///
    /// Both pointers must belong to the current C log scope. This function cannot
    /// run in asynchronous signal context. Missing handlers or copy failures use stderr.
    @unsafe package func deliver(format: UnsafePointer<CChar>, arguments: UnsafeMutableRawPointer) {
        guard let handler = slot.withLock({ $0.handler }) else {
            unsafe wayland_runtime_print_log_message(format, arguments)
            return
        }
        var length = 0
        var truncated: Int32 = 0
        guard let pointer = unsafe wayland_runtime_copy_log_message(format, arguments, 65_536, &length, &truncated) else {
            unsafe wayland_runtime_print_log_message(format, arguments)
            return
        }
        let text = unsafe String(decoding: UnsafeRawBufferPointer(start: pointer, count: length), as: UTF8.self)
        unsafe wayland_runtime_free_log_message(pointer)
        handler(ProcessLogMessage(text: text, truncated: truncated != 0))
    }
}

/// Cancels a single managed process-log generation without detaching native callback code.
public struct ProcessLogSubscription: ~Copyable {
    private let storage: ProcessLogStorage
    private let generation: UInt64
    fileprivate init(storage: ProcessLogStorage, generation: UInt64) { self.storage = storage; self.generation = generation }
    /// Clears delivery only if this token still identifies the currently installed handler.
    public borrowing func cancel() { storage.cancel(generation) }
    deinit { storage.cancel(generation) }
}
