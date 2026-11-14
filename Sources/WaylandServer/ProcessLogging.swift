import CWaylandServer
import WaylandRuntime

private let serverProcessLog = Result { try ProcessLogStorage() }
@unsafe private func deliverServerLog(_ format: UnsafePointer<CChar>?, _ scope: UnsafeMutableRawPointer?) {
    guard let format = unsafe format, let scope = unsafe scope else { return }
    if case .success(let storage) = serverProcessLog { unsafe storage.deliver(format: format, arguments: scope) }
}

/// Manages the process-global native server logging slot after explicit quiescent installation.
public enum ServerLogging {
    /// Installs permanent callback code before concurrent native logging begins.
    ///
    /// The caller proves native setter quiescence, absence of asynchronous signal
    /// delivery, and no later foreign handler replacement. Repeated completed
    /// initialization does not replace the native handler again.
    @unsafe public static func initialize() throws {
        let storage = try serverProcessLog.get()
        unsafe try storage.initialize { unsafe wayland_kit_server_raw_log_handler(deliverServerLog) }
    }
    /// Replaces optional Swift delivery with a Sendable handler receiving owned text.
    ///
    /// Canceling an older token preserves its replacement. Cancellation does not
    /// wait for handlers already retained by in-flight native logging calls.
    public static func observe(_ handler: @escaping @Sendable (ProcessLogMessage) -> Void) throws -> ProcessLogSubscription {
        try serverProcessLog.get().observe(handler)
    }
}
