# WaylandKit

@Metadata {
    @TechnologyRoot
}

Use Swift bindings for libwayland with explicit ownership and checked resource lifetimes.

## Overview

WaylandKit provides typed client and server protocol bindings, centralized resource ownership, protocol generation, and optional cursor, EGL, and utility integration. Checked APIs validate resource generations and lifetimes. Raw native interoperability requires explicit unsafe acknowledgement. See <doc:ImplementationProgress> for measured results and remaining acceptance gates.

## Modules

| Module | Purpose |
| --- | --- |
| [WaylandKit](https://tomorilab.github.io/swift-wayland/documentation/waylandkit) | Client facade and re-exported API |
| [WaylandClient](https://tomorilab.github.io/swift-wayland/documentation/waylandclient) | Client connections and typed requests |
| [WaylandServer](https://tomorilab.github.io/swift-wayland/documentation/waylandserver) | Server resources and typed events |
| [WaylandProtocol](https://tomorilab.github.io/swift-wayland/documentation/waylandprotocol) | Protocol schemas and shared value types |
| [WaylandRuntime](https://tomorilab.github.io/swift-wayland/documentation/waylandruntime) | Ownership and resource lifetimes |
| [WaylandCursor](https://tomorilab.github.io/swift-wayland/documentation/waylandcursor) | Cursor themes and buffers |
| [WaylandEGL](https://tomorilab.github.io/swift-wayland/documentation/waylandegl) | Native EGL windows |
| [WaylandUtilities](https://tomorilab.github.io/swift-wayland/documentation/waylandutilities) | Byte arrays and native utility interoperability |

## Topics

### Start here

- <doc:GettingStarted>

### Design and guides

- <doc:AdvancedAPIs>
- <doc:Architecture>
- <doc:ClientAndServer>
- <doc:ContinuousIntegration>
- <doc:DescriptorsAndCallbacks>
- <doc:DispatchAndConcurrency>
- <doc:DispatcherBenchmark>
- <doc:Documentation>
- <doc:ImplementationProgress>
- <doc:MathematicalModel>
- <doc:NativeCompatibility>
- <doc:OwnedProtocolMetadata>
- <doc:OwnershipAndFFI>
- <doc:OwnershipRuntime>
- <doc:ProtocolGeneration>
- <doc:ProxyDispatcher>
- <doc:SafetyReview>
- <doc:ToolchainValidation>
- <doc:TypedProtocol>
- <doc:Validation>
