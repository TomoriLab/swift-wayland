# Permanent proxy dispatcher lifetime

Keep dispatcher storage reachable until local proxy destruction and complete native-frame quiescence.

## Native contract and implementation gate

The pinned [libwayland 1.26.0 client source](https://raw.githubusercontent.com/wayland-mirror/wayland/1.26.0/src/wayland-client.c) establishes these adapter requirements: wl_proxy_add_dispatcher rejects an existing listener without replacing it; it stores implementation, dispatcher, and userdata until destruction. dispatch_event invokes the dispatcher outside the native display mutex, then uses the display and queued closure again. wl_proxy_destroy marks the proxy destroyed; queued closures may retain the allocation but no longer enter its dispatcher. It is therefore valid to retire Swift userdata after local proxy destruction returns and the enclosing dispatch frame has exited. No public detach operation is fabricated.

The adapter must exclusively own an ordinary proxy, never a display or proxy wrapper. All proxy access, event dispatch, and teardown must use the same serialized session. Foreign destruction and foreign listener/userdata replacement are prohibited. Interface metadata is immutable native storage and must outlive the proxy and queued closures. Protocol destructors remain the typed protocol layer's responsibility; the adapter's fallback performs local wl_proxy_destroy only.

## Lifecycle

The runtime records proxy destruction and context retirement in one obligation. Provisional storage is initialized before installation. Installation failure consumes and destroys the incoming proxy; no token is published. Record publication failure releases provisional storage and destroys the incoming proxy. Subscription cancellation only disables user delivery. Proxy close and root close invalidate the checked handle immediately and defer local destruction until outer native frames exit. The release action cancels delivery, destroys the proxy, then releases the context and its explicit userdata retain. Dependencies keep the connection and queue valid throughout destruction.

Incoming descriptor and constructor obligations require mandatory cleanup before optional delivery. The concrete client adapter snapshots scalar/string/array payloads, owns descriptor scopes, and destroys unclaimed event-created proxies after delivery. No callback error unwinds across C. Unsupported native contracts remain unsafe rather than being advertised as safe.

## Concrete event bridge

ClientProxyDispatcher installs a process-lifetime C-function trampoline with the retained context as both implementation data and reserved proxy userdata. It never reinstalls the dispatcher when a subscription changes. The generic context is erased before forming the C function pointer; a C callback cannot capture generic Swift metadata.

ClientEvent owns copied integer, fixed, string, byte-array, and object-ID observations. It exposes no raw pointer, borrowed descriptor number, or constructor authority. A mandatory C cleanup walk closes incoming descriptors once and locally destroys unclaimed event-created proxies on delivered, canceled, unavailable, and failed delivery. Native queued closures retain their own proxy references until native dispatch resumes. Incoming ownership-taking delivery remains a future typed decoder, not an implicit transfer from the observation API.

Handler/decode failures are recorded in separate diagnostics and returned as C status without unwinding. Native libwayland ignores that dispatcher return code; failure remains queryable through the owner. Diagnostics retain no handler or context after native teardown. User-created cycles in handler captures remain outside the cleanup guarantee.

## Failure, quiescence, and tests

Raw adoption consumes the proxy on every outcome. Provisional failures destroy the incoming proxy before leaving an admitted frame, so a pending prerequisite close cannot disconnect its display before rollback. Native construction and handoff must already lease tracked prerequisites; the runtime cannot protect a raw child freed before admission. Normal client constructors establish that outer lease.

Tests use a real C server/resource and libwayland client proxy over socketpair. They cover delivery, subscription cancel and drop, canceled FD and constructor events, handler failure, explicit proxy close, root shutdown before disconnect, root close during callback and installation, capacity rejection, and 10,000 native create/register/cancel/dispatch/destroy cycles. Weak context checks and C descriptor-table counts supplement record ledgers. ASan/TSan and compiler checks are recorded in <doc:OwnershipRuntime>.

The adapter owns local destruction only. Protocol destructor requests, raw foreign proxy adoption, concurrent foreign native dispatch, proxy wrappers, and display destruction outside the session require separate contracts. Thread-affine integrations remain excluded. See <doc:ClientAndServer> and <doc:ImplementationProgress> for subsequent work and remaining gates.
