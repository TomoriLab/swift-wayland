import WaylandCompilerProbe
import CWaylandClientProbe
import CWaylandServerProbe
import CWaylandCursorProbe
import CWaylandEGLProbe

final class CallbackState {
    var callbacks = 0
    var stage = 0
}

@unsafe func receive(_ data: UnsafeMutableRawPointer?, _ stage: Int32) {
    // The caller retains this context until the complete native destroy call returns.
    let state = unsafe Unmanaged<CallbackState>.fromOpaque(data!).takeUnretainedValue()
    state.callbacks += 1
    state.stage = Int(stage)
}

@unsafe func cycle(_ failureStage: Int32 = 0) {
    var state: CallbackState? = CallbackState()
    weak let releasedState = state
    let context = unsafe Unmanaged.passRetained(state!).toOpaque()
    let callback: @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void = { data, stage in
        unsafe receive(data, stage)
    }
    guard let registration = unsafe wayland_probe_create(callback, context, failureStage) else {
        unsafe Unmanaged<CallbackState>.fromOpaque(context).release()
        precondition(failureStage != 0)
        precondition(state!.callbacks == (failureStage == 3 ? 1 : 0))
        state = nil
        precondition(releasedState == nil)
        return
    }
    precondition(failureStage == 0)
    let stage = unsafe wayland_probe_destroy(registration)
    precondition(stage == 2 && state!.callbacks == 1 && state!.stage == 1)
    unsafe Unmanaged<CallbackState>.fromOpaque(context).release()
    state = nil
    precondition(releasedState == nil)
}

@main struct NativeCallbackProbe {
    static func main() {
        let nativeSize = wayland_probe_array_size()
        let nativeAlignment = wayland_probe_array_alignment()
        unsafe precondition(nativeSize == MemoryLayout<wl_array>.size)
        unsafe precondition(nativeAlignment == MemoryLayout<wl_array>.alignment)
        let roundtrip = wayland_probe_fixed_roundtrip(42)
        precondition(roundtrip == 42)
        let cursorSize = wayland_probe_cursor_image_size()
        precondition(cursorSize == MemoryLayout<wl_cursor_image>.size)
        // A warm-up excludes process-wide native initialization from descriptor accounting.
        unsafe cycle()
        let baseline = wayland_probe_open_descriptor_count()
        precondition(baseline >= 0)
        for _ in 0..<1_000 {
            unsafe cycle()
            for stage: Int32 in 1...3 { unsafe cycle(stage) }
        }
        precondition(wayland_probe_open_descriptor_count() == baseline)
        print("PASS four C module imports, layouts, callbacks, rollback and fd conservation")
    }
}
