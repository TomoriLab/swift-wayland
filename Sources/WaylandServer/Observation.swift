import Glibc
import CWaylandServer
import WaylandProtocol
import WaylandRuntime

/// Copies resource metadata without granting authority over native-reserved resources.
public struct ServerResourceSnapshot: Equatable, Sendable {
    /// The native protocol ID, not a durable access capability.
    public let identifier: UInt32
    /// The immutable native interface name.
    public let interfaceName: String
    /// The exact native resource version, including zero for native-reserved objects.
    public let version: Int32
}
@unsafe func snapshotResource(_ resource: UnsafeMutablePointer<wl_resource>) -> ServerResourceSnapshot {
    unsafe ServerResourceSnapshot(identifier: wl_resource_get_id(resource),
        interfaceName: String(cString: wl_resource_get_class(resource)), version: wl_resource_get_version(resource))
}
private final class ClientSnapshotBuffer { var snapshots: [ServerClientSnapshot] = [] }
private final class ResourceSnapshotBuffer { var snapshots: [ServerResourceSnapshot] = [] }
@unsafe private func appendClient(_ client: OpaquePointer?, _ data: UnsafeMutableRawPointer?) {
    guard let client = unsafe client, let data = unsafe data else { return }
    var process: pid_t = 0; var user: uid_t = 0; var group: gid_t = 0
    unsafe wl_client_get_credentials(client, &process, &user, &group)
    unsafe Unmanaged<ClientSnapshotBuffer>.fromOpaque(data).takeUnretainedValue().snapshots.append(
        ServerClientSnapshot(processIdentifier: process, userIdentifier: user, groupIdentifier: group))
}
@unsafe private func appendResource(_ resource: UnsafeMutablePointer<wl_resource>?, _ data: UnsafeMutableRawPointer?) -> wl_iterator_result {
    if let resource = unsafe resource, let data = unsafe data {
        unsafe Unmanaged<ResourceSnapshotBuffer>.fromOpaque(data).takeUnretainedValue().snapshots.append(snapshotResource(resource))
    }
    return WL_ITERATOR_CONTINUE
}
extension ServerDisplay {
    /// Returns copied credentials after native client traversal has completed.
    public borrowing func clientSnapshots() throws -> [ServerClientSnapshot] {
        try lifetime.withAccess(matching: .serverDisplay) {
            let buffer = ClientSnapshotBuffer()
            withExtendedLifetime(buffer) {
                unsafe wayland_kit_each_client(storage.pointer, appendClient, Unmanaged.passUnretained(buffer).toOpaque())
            }
            return buffer.snapshots
        }
    }
}
extension ServerClientReference {
    /// Copies every native resource's metadata, including reserved display and registry resources.
    public func resourceSnapshots() throws -> [ServerResourceSnapshot] {
        try lifetime.withAccess(matching: .serverClient) {
            let buffer = ResourceSnapshotBuffer()
            withExtendedLifetime(buffer) {
                unsafe wl_client_for_each_resource(registry.client, appendResource, Unmanaged.passUnretained(buffer).toOpaque())
            }
            return buffer.snapshots
        }
    }
    /// Finds a typed resource through existing authority or a native-owned destruction watch.
    public func object<I: ServerInterface>(identifier: UInt32, as type: I.Type) throws -> ServerObjectReference<I>? {
        try lifetime.withAccess(matching: .serverClient) {
            guard let pointer = unsafe wl_client_get_object(registry.client, identifier) else { return nil }
            return unsafe try registry.reference(pointer, as: type)
        }
    }
    /// Flushes this client's pending native output while retaining its lifetime.
    public func flush() throws {
        try lifetime.withAccess(matching: .serverClient) { unsafe wl_client_flush(registry.client) }
    }
    /// Changes the native connection buffer limit under the client's domain.
    public func setMaximumBufferSize(_ bytes: Int) throws {
        guard bytes >= 0 else { throw ServerError.nativeFailure(EINVAL) }
        try lifetime.withAccess(matching: .serverClient) { unsafe wl_client_set_max_buffer_size(registry.client, bytes) }
    }
}

/// Identifies the native direction observed by a protocol logger.
public enum ServerProtocolDirection: Sendable {
    /// A client-to-server request before native implementation dispatch.
    case request
    /// A server-to-client event observed during native marshalling.
    case event
}
/// Copies protocol logger arguments without taking native message ownership.
public enum ServerProtocolArgument: Equatable, Sendable {
    /// An exact signed scalar.
    case signed(Int32)
    /// An exact unsigned scalar.
    case unsigned(UInt32)
    /// Exact signed fixed-point wire bits.
    case fixed(Int32)
    /// A copied nullable string.
    case string(String?)
    /// Copied native array bytes.
    case bytes([UInt8])
    /// A copied existing object ID, without access authority.
    case object(UInt32?)
    /// A copied request ID or event-created resource ID, without ownership transfer.
    case newIdentifier(UInt32)
    /// An observation marker that never closes or exposes the borrowed descriptor.
    case descriptor
}
/// Owns an immutable snapshot from one native protocol logger invocation.
public struct ServerProtocolObservation: Sendable {
    /// The native request/event direction.
    public let direction: ServerProtocolDirection
    /// The copied target resource identity.
    public let resource: ServerResourceSnapshot
    /// The exact native opcode.
    public let opcode: Int32
    /// The copied message name.
    public let messageName: String
    /// Owned argument observations with no descriptor/constructor authority.
    public let arguments: [ServerProtocolArgument]
}
private final class ProtocolLoggerState {
    let handler: (ServerProtocolObservation) throws -> Void
    var observer: NativeDestructionObserver?
    var failure: (any Error)?
    var delivering = false
    init(_ handler: @escaping (ServerProtocolObservation) throws -> Void) { self.handler = handler }
}
@unsafe private func observeProtocol(_ data: UnsafeMutableRawPointer?, _ direction: wl_protocol_logger_type,
                                     _ message: UnsafePointer<wl_protocol_logger_message>?) {
    guard let data = unsafe data, let message = unsafe message else { return }
    let state = unsafe Unmanaged<ProtocolLoggerState>.fromOpaque(data).takeUnretainedValue()
    guard !state.delivering, let observer = state.observer else { return }
    do {
        try observer.withCallback {
            state.delivering = true
            defer { state.delivering = false }
            guard let resource = unsafe message.pointee.resource, let metadata = unsafe message.pointee.message else {
                throw ServerProtocolError.invalidMessage
            }
            let count = unsafe message.pointee.arguments_count
            let kinds = unsafe String(cString: metadata.pointee.signature).filter { !$0.isNumber && $0 != "?" }
            guard count >= 0, count <= 20, kinds.count == Int(count),
                  count == 0 || (unsafe message.pointee.arguments != nil) else { throw ServerProtocolError.invalidMessage }
            let values = unsafe message.pointee.arguments
            var arguments: [ServerProtocolArgument] = []
            for (index, kind) in kinds.enumerated() {
                switch kind {
                case "i": arguments.append(.signed(unsafe values![index].i))
                case "u": arguments.append(.unsigned(unsafe values![index].u))
                case "f": arguments.append(.fixed(unsafe values![index].f))
                case "s": arguments.append(.string(unsafe values![index].s.map { unsafe String(cString: $0) }))
                case "a":
                    guard let array = unsafe values![index].a, unsafe array.pointee.size <= 65_536 else { throw ServerProtocolError.invalidMessage }
                    let size = unsafe array.pointee.size
                    guard size == 0 || (unsafe array.pointee.data != nil) else { throw ServerProtocolError.invalidMessage }
                    arguments.append(.bytes(unsafe Array(UnsafeRawBufferPointer(start: array.pointee.data, count: size))))
                case "o":
                    let identifier = unsafe values![index].o.map { unsafe wl_resource_get_id(UnsafeMutableRawPointer($0).assumingMemoryBound(to: wl_resource.self)) }
                    arguments.append(.object(identifier))
                case "n":
                    if direction == WL_PROTOCOL_LOGGER_REQUEST { arguments.append(.newIdentifier(unsafe values![index].n)) }
                    else {
                        guard let object = unsafe values![index].o else { throw ServerProtocolError.invalidMessage }
                        arguments.append(.newIdentifier(unsafe wl_resource_get_id(UnsafeMutableRawPointer(object).assumingMemoryBound(to: wl_resource.self))))
                    }
                case "h": arguments.append(.descriptor)
                default: throw ServerProtocolError.invalidMessage
                }
            }
            let observation = unsafe ServerProtocolObservation(direction: direction == WL_PROTOCOL_LOGGER_REQUEST ? .request : .event,
                resource: snapshotResource(resource), opcode: message.pointee.message_opcode,
                messageName: String(cString: metadata.pointee.name), arguments: arguments)
            try state.handler(observation)
        }
    } catch { state.failure = error }
}
/// Owns protocol logging and defers list removal until complete native traversal returns.
public struct ServerProtocolLogger: ~Copyable {
    private let state: ProtocolLoggerState
    private let owner: OwnedHandle
    fileprivate init(state: ProtocolLoggerState, owner: consuming OwnedHandle) { self.state = state; self.owner = owner }
    /// Provides checked logger registration identity.
    public var lifetime: ObjectHandle { borrowing get { owner.reference } }
    /// Returns a saved decoder or user-handler exception.
    public var failure: (any Error)? { borrowing get { state.failure } }
    /// Consumes registration authority and requests one deferred native logger removal.
    @discardableResult public consuming func close() -> CloseProgress { owner.close() }
}
extension ServerDisplay {
    /// Installs synchronous owned protocol observation with recursion suppressed per logger.
    public borrowing func addProtocolLogger(_ handler: @escaping (ServerProtocolObservation) throws -> Void) throws -> ServerProtocolLogger {
        try lifetime.withAccess(matching: .serverDisplay) {
            let state = ProtocolLoggerState(handler)
            guard let pointer = unsafe wl_display_add_protocol_logger(storage.pointer, observeProtocol, Unmanaged.passUnretained(state).toOpaque()) else {
                throw ServerError.nativeFailure(ENOMEM)
            }
            var adopted = false
            defer { if !adopted { unsafe wl_protocol_logger_destroy(pointer) } }
            let owner = unsafe try lifetime.adopt(nativeIdentifier: UInt64(UInt(bitPattern: pointer)), kind: .registration, dependencies: [lifetime]) {
                withExtendedLifetime(state) { unsafe wl_protocol_logger_destroy(pointer) }
            }
            adopted = true
            state.observer = owner.reference.destructionObserver()
            return ServerProtocolLogger(state: state, owner: owner)
        }
    }
}


extension ServerResource {
    /// Installs a copied destruction notification that runs after native access is invalidated.
    public borrowing func onDestroyed(_ handler: @escaping (ServerResourceSnapshot) -> Void) throws {
        try lifetime.withAccess(matching: .serverResource) { storage.resourceDestroyHandler = handler }
    }
    /// Returns the copied native destruction metadata after notification, when observed.
    public var destructionSnapshot: ServerResourceSnapshot? { borrowing get { storage.resourceDestructionSnapshot } }
}
extension ServerObject {
    /// Installs a destruction handler with copied metadata and no live native borrow.
    public borrowing func onDestroyed(_ handler: @escaping (ServerResourceSnapshot) -> Void) throws { try resource.onDestroyed(handler) }
    /// Returns copied destruction metadata even while an invalidated owner survives.
    public var destructionSnapshot: ServerResourceSnapshot? { borrowing get { resource.destructionSnapshot } }
}
extension ServerClientReference {
    /// Installs a copied client destruction notification after subtree invalidation.
    public func onDestroyed(_ handler: @escaping (ServerClientSnapshot) -> Void) throws {
        try lifetime.withAccess(matching: .serverClient) {
            guard let storage = registry.storage else { throw OwnershipError.invalidHandle }
            storage.clientDestroyHandler = handler
        }
    }
}

extension ServerObjectReference {
    /// Copies live resource metadata under the checked resource lease.
    public func snapshot() throws -> ServerResourceSnapshot {
        try endpoint.lifetime.withAccess() { unsafe snapshotResource(endpoint.pointer) }
    }
    /// Posts a literal protocol error and requests client teardown after native quiescence.
    ///
    /// The message is never interpreted as a printf format string. Error codes
    /// remain interface-specific raw values and are not restricted to known enums.
    public func postError(code: UInt32, message: String) throws {
        guard !message.utf8.contains(0), message.utf8.count <= 4096 else { throw ServerProtocolError.invalidMessage }
        try endpoint.lifetime.withAccess() {
            message.withCString { unsafe wayland_kit_resource_error(endpoint.pointer, code, $0) }
            _ = unsafe endpoint.registry.observer.protocolClosed()
        }
    }
    /// Posts native out-of-memory failure and defers terminal client destruction.
    public func postNoMemory() throws {
        try endpoint.lifetime.withAccess() {
            unsafe wl_resource_post_no_memory(endpoint.pointer)
            _ = unsafe endpoint.registry.observer.protocolClosed()
        }
    }
}
extension ServerClientReference {
    /// Posts a literal implementation error and requests terminal client cleanup.
    public func postImplementationError(_ message: String) throws {
        guard !message.utf8.contains(0), message.utf8.count <= 4096 else { throw ServerProtocolError.invalidMessage }
        try lifetime.withAccess(matching: .serverClient) {
            message.withCString { unsafe wayland_kit_client_error(registry.client, $0) }
            _ = unsafe registry.observer.protocolClosed()
        }
    }
    /// Posts native allocation failure and requests client teardown after the current frame.
    public func postNoMemory() throws {
        try lifetime.withAccess(matching: .serverClient) {
            unsafe wl_client_post_no_memory(registry.client)
            _ = unsafe registry.observer.protocolClosed()
        }
    }
}
extension ServerDisplay {
    /// Borrows the native event-loop descriptor without granting close or transfer authority.
    ///
    /// The caller must not close or retain this raw number, mutate native loop
    /// registration independently, or dispatch the loop from another reader.
    @unsafe public borrowing func withUnsafeEventLoopDescriptor<Result: ~Copyable>(_ body: (Int32) throws -> Result) throws -> Result {
        unsafe try withNativeLoop { _, loop in try body(unsafe wl_event_loop_get_fd(loop)) }
    }
    /// Dispatches pending idle callbacks under the same native quiescence contract as full dispatch.
    public borrowing func dispatchIdle() throws {
        unsafe try withNativeLoop { _, loop in
            guard !storage.dispatching else { throw ServerError.recursiveDispatch }
            storage.dispatching = true
            defer { storage.dispatching = false }
            unsafe wl_event_loop_dispatch_idle(loop)
        }
    }
}

extension ServerObjectReference {
    /// Provides checked resource or watch identity without destruction authority.
    public var lifetime: ObjectHandle { endpoint.lifetime }
    /// Borrows one native resource without permitting independent destruction or userdata replacement.
    @unsafe public func withUnsafeNativeResource<Result: ~Copyable>(
        _ body: (UnsafeMutablePointer<wl_resource>) throws -> Result
    ) throws -> Result {
        try endpoint.lifetime.withAccess { unsafe try body(endpoint.pointer) }
    }
}
extension ServerClientReference {
    /// Borrows the native client while preserving all registered subtree and frame contracts.
    @unsafe public func withUnsafeNativeClient<Result: ~Copyable>(_ body: (OpaquePointer) throws -> Result) throws -> Result {
        try lifetime.withAccess(matching: .serverClient) { unsafe try body(registry.client) }
    }
}
