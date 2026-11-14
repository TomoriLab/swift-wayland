# Build a typed Wayland client

Connect to a compositor through the public client-first WaylandKit product.

## Requirements

Use Swift 6.4.2 in Swift 6 language mode on Linux with the libwayland 1.26.0 development headers and libraries. The default product links the client and common runtime targets. Server, cursor, EGL, and utility products are separate opt-in dependencies. aarch64 verification remains deferred; current executable evidence is x86_64.

The repository contains a standalone consumer at Examples/Registry. Its Package.swift depends on the local repository through `.package(path: "../..")`. The consumer imports WaylandKit without package access or @testable import. This verifies that the APIs are usable outside the defining package. For another project, set the local dependency path to that project's actual checkout location and select the WaylandKit product.

```sh
source ~/.zshrc
swift run --package-path Examples/Registry -Xswiftc -warnings-as-errors
```

The example connects using native WAYLAND_DISPLAY/XDG_RUNTIME_DIR lookup. It observes the registry, waits for a synchronization callback with bounded poll operations, binds wl_compositor at a supported advertised version, creates an unmapped surface, commits it without a buffer, destroys it, and closes the connection. It creates no visible window. Missing compositor access, timeout, and native errors propagate as Swift errors.

## Ownership and subscriptions

ClientConnection owns the root session. A ClientObject owns one native proxy obligation. Its copyable reference permits checked protocol requests but has no protocol destructor. Constructor results must be retained while their native object is needed. Consuming destroy/release methods invalidate their references immediately. Native memory release waits for enclosing native calls and dependents to quiesce.

onEvent returns a noncopyable subscription. Keep it alive while delivery is needed. Cancellation disables user delivery without removing a permanent native dispatcher or freeing userdata. Received descriptors and new proxies still undergo mandatory decoding and cleanup. Avoid strongly capturing an owner in a handler retained by that owner's context; use weak application state or explicitly close the owner/root or break the captured strong references. Flag-only subscription cancellation does not release native-reachable context and does not by itself break that capture cycle.

ReadCancellation is Sendable and owns only a wake descriptor and synchronized cancellation state. It carries no display access. The connection and its objects remain non-Sendable. dispatchOnce integrates a prepared read with timeout, flush backpressure, and cancellation. withPreparedRead is a lower-level synchronous borrowed capability: it must resolve by read/cancel on the originating coordinator and cannot escape or suspend.

## Errors and shutdown

Version/class/session and payload validation happen before native marshalling. A failed native constructor or record publication rolls back every newly acquired obligation. Native protocol errors are connection-terminal and remain distinct from local argument errors. protocolError() returns copied interface/object/code information that remains usable after disconnect.

requestClose() is idempotent. It invalidates all descendants immediately and can report deferred while inside a native call. Root closure does not depend on the last Swift reference disappearing. A final snapshot with zero retained records establishes that this session's tracked obligations retired; it is not a proof against arbitrary user ARC cycles or fatal process termination.

## Paired public server example

Scripts/verify-examples.py builds both standalone packages and runs the registry client against Examples/MinimalServer in a temporary private runtime directory. The server supports only the example's control-plane surface lifecycle. It is not a rendering compositor. The check verifies typed constructor acceptance, destruction, public import boundaries, record retirement, and removal of the native socket/lock files.

```sh
python3 Scripts/verify-examples.py
```

The same client was also run against the workstation's existing KWin Wayland session. The scope is registry/sync and an unmapped surface lifecycle; it does not validate rendering, input devices, extensions, or a foreign EGL driver. See <doc:TypedProtocol>, <doc:ClientAndServer>, and <doc:AdvancedAPIs> for the full contracts.
