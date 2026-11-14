# ``WaylandKit``

Import the client facade to use typed Wayland connections, protocol objects, and ownership-aware resources.

## Overview

Use `import WaylandKit` for the client-facing APIs re-exported from WaylandClient, WaylandProtocol, and WaylandRuntime. Import WaylandServer, WaylandCursor, WaylandEGL, or WaylandUtilities separately when those capabilities are required.

## Usage

The facade re-exports public client, protocol, and runtime APIs. It does not automatically import server, cursor, EGL, or utility APIs.

```swift
import WaylandKit

func inspectConnection() throws {
    let connection = try ClientConnection()
    defer { connection.requestClose() }
    let registry = try connection.protocolDisplay().getRegistry()
    withExtendedLifetime(registry) {}
}
```

This snippet establishes a connection and retains the registry through its scope. It does not dispatch registry events. Follow [GettingStarted](https://tomorilab.github.io/swift-wayland/documentation/project/gettingstarted)
