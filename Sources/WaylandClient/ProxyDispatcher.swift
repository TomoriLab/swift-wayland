import CWaylandClient
import WaylandRuntime

/// Reports failure to acquire or use a native client resource.
package enum ClientError: Error, Equatable, Sendable {
    /// The native call returned null or failed with the saved errno.
    case nativeFailure(Int32)
    /// A native event contains an unsupported argument representation.
    case invalidEvent
}

/// Contains copied event fields without native pointer ownership.
///
/// Descriptor and constructor fields are observation markers in this initial
/// dispatcher adapter. Their native obligations are always discharged after
/// delivery, including canceled delivery. Typed ownership-taking protocol
/// decoders require a separate generated path before they can publish owners.
package enum ClientEventArgument: Equatable, Sendable {
    /// An exact native signed integer.
    case signed(Int32)
    /// An exact native unsigned integer.
    case unsigned(UInt32)
    /// A fixed-point value in its native 24.8 representation.
    case fixed(Int32)
    /// A copied nullable UTF-8 string using replacement decoding.
    case string(String?)
    /// An initialized owned byte snapshot.
    case bytes([UInt8])
    /// A copied nullable object identifier without access authority.
    case object(UInt32?)
    /// An event-created proxy identifier whose local obligation is not transferred.
    case newObject(UInt32?)
    /// A received descriptor whose obligation is retained by the trampoline.
    case descriptor
}

/// Provides a fully owned, Sendable observation of one native event.
package struct ClientEvent: Equatable, Sendable {
    /// The source-order event opcode.
    package let opcode: UInt32
    /// A copied native message name.
    package let name: String
    /// Copied values in wire argument order.
    package let arguments: [ClientEventArgument]
}

final class ClientDispatcherDiagnostics {
    var failure: (any Error)?
}

final class ClientDispatcherContext {
    let diagnostics: ClientDispatcherDiagnostics
    let handler: (ClientEvent) throws -> Void
    init(diagnostics: ClientDispatcherDiagnostics, handler: @escaping (ClientEvent) throws -> Void) {
        self.diagnostics = diagnostics
        self.handler = handler
    }
}

@unsafe private func snapshotEvent(
    opcode: UInt32, message: UnsafePointer<wl_message>, arguments: UnsafeMutablePointer<wl_argument>?
) throws -> ClientEvent {
    let signature = unsafe String(cString: message.pointee.signature)
    var values: [ClientEventArgument] = []
    var index = 0
    for character in signature {
        if character.isNumber || character == "?" { continue }
        guard let arguments = unsafe arguments else { throw ClientError.invalidEvent }
        let argument = unsafe arguments[index]
        switch character {
        case "i": unsafe values.append(.signed(argument.i))
        case "u": unsafe values.append(.unsigned(argument.u))
        case "f": unsafe values.append(.fixed(argument.f))
        case "s": values.append(.string(unsafe argument.s.map { unsafe String(cString: $0) }))
        case "a":
            guard let array = unsafe argument.a else { throw ClientError.invalidEvent }
            let size = unsafe array.pointee.size
            if size == 0 { values.append(.bytes([])) }
            else {
                guard let data = unsafe array.pointee.data else { throw ClientError.invalidEvent }
                values.append(.bytes(unsafe Array(UnsafeRawBufferPointer(start: data, count: size))))
            }
        case "o", "n":
            let identifier = unsafe argument.o.map { unsafe wl_proxy_get_id($0) }
            values.append(character == "o" ? .object(identifier) : .newObject(identifier))
        case "h": values.append(.descriptor)
        default: throw ClientError.invalidEvent
        }
        index += 1
    }
    return unsafe ClientEvent(opcode: opcode, name: String(cString: message.pointee.name), arguments: values)
}

@unsafe private func dispatchClientEvent(
    _ implementation: UnsafeRawPointer?, _ target: UnsafeMutableRawPointer?, _ opcode: UInt32,
    _ message: UnsafePointer<wl_message>?, _ arguments: UnsafeMutablePointer<wl_argument>?
) -> Int32 {
    guard let message = unsafe message else { return -1 }
    // Input cleanup is unconditional and precedes native queued-closure retirement.
    defer { unsafe wayland_kit_discard_event(message, arguments) }
    let result = unsafe ProxyDispatcherOwner<ClientDispatcherContext>.deliver(
        userData: UnsafeMutableRawPointer(mutating: implementation)
    ) { context in
        do {
            let event = unsafe try snapshotEvent(opcode: opcode, message: message, arguments: arguments)
            try context.handler(event)
        } catch { context.diagnostics.failure = error; throw error }
    }
    if case .failed = result { return -1 }
    return 0
}

/// Owns one ordinary libwayland proxy and its nonremovable dispatcher.
///
/// This adapter observes copied events. Incoming descriptors and new proxies are
/// cleaned even when delivery is canceled or throws. It does not transfer event
/// constructor ownership. Native metadata must remain valid until queued native
/// closures retire. All dispatch must be enclosed by this session's native frame.
package struct ClientProxyDispatcher<Context: AnyObject>: ~Copyable {
    private let owner: ProxyDispatcherOwner<ClientDispatcherContext>
    private let diagnostics: ClientDispatcherDiagnostics

    /// Returns the last decode or handler failure even though native dispatch ignores its C return code.
    package var failure: (any Error)? { borrowing get { diagnostics.failure } }

    /// Provides checked identity for native lifetime dependencies.
    package var lifetime: ObjectHandle { borrowing get { owner.lifetime } }
    /// Provides a delivery-only cancellation handle that may cross threads.
    package var cancellation: CallbackCancellation { borrowing get { owner.cancellation } }
    /// Issues the sole logical subscription; dropping it does not destroy the proxy.
    package borrowing func subscription() throws -> CallbackSubscription { try owner.subscription() }
    /// Requests local destruction after complete native-frame quiescence.
    @discardableResult
    package borrowing func requestClose() -> CloseProgress { owner.requestClose() }
    /// Consumes proxy authority and requests local destruction exactly once.
    @discardableResult
    package consuming func close() -> CloseProgress { owner.close() }

    /// Consumes an exclusively owned ordinary proxy on success and failure.
    ///
    /// The proxy must belong to the supplied session's display and dependencies.
    /// Displays, proxy wrappers, borrowed proxies, foreign dispatchers, foreign
    /// userdata replacement, and independent destruction are prohibited. Metadata
    /// must be immutable and outlive all queued closures. The handler must not
    /// create an ARC cycle through its session. Fallback sends no protocol request.
    @unsafe package init(
        receiving proxy: OpaquePointer,
        in session: borrowing OwnershipSession,
        dependencies: [ObjectHandle] = [],
        context: Context,
        handler: @escaping (Context, ClientEvent) throws -> Void
    ) throws {
        let diagnostics = ClientDispatcherDiagnostics()
        self.diagnostics = diagnostics
        let storage = ClientDispatcherContext(diagnostics: diagnostics) { event in try handler(context, event) }
        owner = unsafe try session.receiveProxyDispatcher(
            nativeIdentifier: UInt64(UInt(bitPattern: proxy)), context: storage, dependencies: dependencies,
            install: { pointer in
                unsafe wayland_kit_install_dispatcher(proxy, dispatchClientEvent, pointer) == 0
            }, destroy: { unsafe wl_proxy_destroy(proxy) }
        )
    }
}
