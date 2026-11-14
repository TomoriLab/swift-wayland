import Glibc
import CWaylandRuntime

/// Describes failure to copy a native formatted log record.
public enum NativeLogFormatError: Error, Equatable, Sendable {
    /// The requested byte quota is outside the supported range.
    case invalidQuota
    /// Native formatting or allocation failed with saved errno.
    case nativeFailure(Int32)
}
/// Owns formatted native log text after its borrowed C argument scope has ended.
public struct NativeLogText: Equatable, Sendable {
    /// Text copied by byte count with replacement for invalid UTF-8.
    public let text: String
    /// Whether the requested quota truncated the native formatted output.
    public let truncated: Bool
}
extension UtilitiesInterop {
    /// Copies a native log argument scope using va_copy entirely inside the C bridge.
    ///
    /// Both pointers must originate from the same current WlLogFunc invocation.
    /// The scope cannot be retained, modified, reused after callback return, or
    /// interpreted as an architecture-specific va_list in Swift. Every outcome
    /// releases temporary C storage. The original argument scope is unchanged.
    @unsafe public static func formatLogMessage(
        format: UnsafePointer<CChar>, arguments: UnsafeMutableRawPointer, maximumBytes: Int = 65_536
    ) throws -> NativeLogText {
        guard maximumBytes >= 0 && maximumBytes <= 1_048_576 else { throw NativeLogFormatError.invalidQuota }
        var count = 0
        var truncated: Int32 = 0
        guard let pointer = unsafe wayland_runtime_copy_log_message(format, arguments, maximumBytes, &count, &truncated) else {
            throw NativeLogFormatError.nativeFailure(errno)
        }
        defer { unsafe wayland_runtime_free_log_message(pointer) }
        let text = unsafe String(decoding: UnsafeRawBufferPointer(start: pointer, count: count), as: UTF8.self)
        return NativeLogText(text: text, truncated: truncated != 0)
    }
}
