import Glibc
import CWaylandServer
import WaylandRuntime

private final class IdleContext {
    let handler: () throws -> Void
    var observer: NativeDestructionObserver?
    var failure: (any Error)?
    var executions = 0
    init(_ handler: @escaping () throws -> Void) { self.handler = handler }
}

@unsafe private func invokeIdle(_ pointer: UnsafeMutableRawPointer?) {
    guard let pointer = unsafe pointer else { return }
    let context = unsafe Unmanaged<IdleContext>.fromOpaque(pointer).takeUnretainedValue()
    guard let observer = context.observer else { preconditionFailure("Idle callback has no native lifetime observer.") }
    do {
        try observer.withCallback {
            context.executions += 1
            do { try context.handler() } catch { context.failure = error }
        }
    } catch {
        // A logically closed source still completes its mandatory native one-shot cleanup.
    }
    do { _ = unsafe try observer.destroyed() }
    catch { preconditionFailure("Idle completion violated the framed native lifetime contract: \(error)") }
}

/// Owns a one-shot idle source without repeating native removal after execution.
///
/// Native idle dispatch removes the source after its callback. The callback
/// consumes record authority before returning and keeps context storage alive
/// through the outer loop frame. Self-close therefore never removes twice.
package struct ServerIdleSource: ~Copyable {
    private let context: IdleContext
    private let owner: OwnedHandle
    fileprivate init(context: IdleContext, owner: consuming OwnedHandle) {
        self.context = context
        self.owner = owner
    }
    /// Provides checked source identity and one-shot invalidation.
    package var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Reports the handler failure after native cleanup without unwinding through C.
    package var failure: (any Error)? { borrowing get { context.failure } }
    /// Reports how many user invocations occurred; a one-shot source admits at most one.
    package var executions: Int { borrowing get { context.executions } }
    /// Requests source removal; an executing callback resolves native removal itself.
    @discardableResult
    package borrowing func requestClose() -> CloseProgress { owner.requestClose() }
    /// Consumes source authority without repeating native one-shot completion.
    @discardableResult
    package consuming func close() -> CloseProgress { owner.close() }
}

extension ServerDisplay {
    /// Schedules one synchronous idle callback under the display's native-frame guard.
    ///
    /// The handler may throw or request root close. It must not suspend, recurse
    /// into dispatch, or create an ownership cycle through its display container.
    package borrowing func addIdle(_ handler: @escaping () throws -> Void) throws -> ServerIdleSource {
        unsafe try withNativeLoop { session, loop in
            let context = IdleContext(handler)
            guard let source = unsafe wl_event_loop_add_idle(loop, invokeIdle, Unmanaged.passUnretained(context).toOpaque()) else {
                throw ServerError.nativeFailure(errno)
            }
            var adopted = false
            defer { if !adopted { unsafe wl_event_source_remove(source) } }
            let owner = unsafe try session.adopt(nativeIdentifier: UInt64(UInt(bitPattern: source)), kind: .eventSource,
                                                dependencies: [lifetime]) {
                withExtendedLifetime(context) { _ = unsafe wl_event_source_remove(source) }
            }
            adopted = true
            context.observer = owner.reference.destructionObserver()
            return ServerIdleSource(context: context, owner: owner)
        }
    }
}
