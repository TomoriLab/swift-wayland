import Glibc
import CWaylandClient
import WaylandRuntime

@safe final class QueueReadiness {
    let pointer: OpaquePointer
    let observer: NativeDestructionObserver
    init(pointer: OpaquePointer, lifetime: ObjectHandle) { unsafe self.pointer = pointer; observer = lifetime.destructionObserver() }
}

@safe final class ClientQueueState {
    private let display: OpaquePointer
    private let observer: NativeDestructionObserver
    private let metadata: ClientProtocolMetadata
    var queues: [UInt: QueueReadiness] = [:]
    init(_ display: OpaquePointer, metadata: ClientProtocolMetadata, lifetime: ObjectHandle) {
        unsafe self.display = display
        observer = lifetime.destructionObserver()
        self.metadata = metadata
    }
    func canRelease() -> Bool {
        let closing = (try? observer.withCallback { true }) != true
        if closing {
            _ = unsafe wl_display_dispatch_pending(display)
            for entry in Array(queues.values) { _ = unsafe wl_display_dispatch_queue_pending(display, entry.pointer) }
        } else {
            for entry in Array(queues.values) where (try? entry.observer.withCallback { true }) != true {
                _ = unsafe wl_display_dispatch_queue_pending(display, entry.pointer)
            }
        }
        let defaultPending = unsafe !probe(nil)
        let pending = defaultPending || queues.values.contains { unsafe !probe($0.pointer) }
        let error = unsafe wl_display_get_error(display)
        if error != 0 {
            if pending { metadata.recordCleanupError(error) }
            return true
        }
        return !pending
    }
    private func probe(_ queue: OpaquePointer?) -> Bool {
        let result: Int32
        if let queue = unsafe queue { result = unsafe wl_display_prepare_read_queue(display, queue) }
        else { result = unsafe wl_display_prepare_read(display) }
        if result == 0 { unsafe wl_display_cancel_read(display); return true }
        return false
    }
}
