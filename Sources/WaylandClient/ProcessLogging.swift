import CWaylandClient
import WaylandRuntime

private let clientProcessLog = Result { try ProcessLogStorage() }
@unsafe private func deliverClientLog(_ format: UnsafePointer<CChar>?, _ scope: UnsafeMutableRawPointer?) {
    guard let format = unsafe format, let scope = unsafe scope else { return }
    if case .success(let storage) = clientProcessLog { unsafe storage.deliver(format: format, arguments: scope) }
}

/// Manages the process-global native client logging slot after explicit quiescent installation.
public enum ClientLogging {
    /// Installs permanent callback code before concurrent native logging begins.
    ///
    /// The caller proves native setter quiescence, absence of asynchronous signal
    /// delivery, and no later foreign handler replacement. Repeated completed
    /// initialization does not replace the native handler again.
    @unsafe public static func initialize() throws {
        let storage = try clientProcessLog.get()
        unsafe try storage.initialize { unsafe wayland_kit_client_raw_log_handler(deliverClientLog) }
    }
    /// Replaces optional Swift delivery with a Sendable handler receiving owned text.
    ///
    /// Canceling an older token preserves its replacement. Cancellation does not
    /// wait for handlers already retained by in-flight native logging calls.
    public static func observe(_ handler: @escaping @Sendable (ProcessLogMessage) -> Void) throws -> ProcessLogSubscription {
        try clientProcessLog.get().observe(handler)
    }
}
