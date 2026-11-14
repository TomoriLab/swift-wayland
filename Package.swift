// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "WaylandKit",
    products: [
        .library(name: "WaylandKit", targets: ["WaylandKit"]),
        .library(name: "WaylandCursor", targets: ["WaylandCursor"]),
        .library(name: "WaylandEGL", targets: ["WaylandEGL"]),
        .library(name: "WaylandUtilities", targets: ["WaylandUtilities"]),
        .library(name: "WaylandRuntime", targets: ["WaylandRuntime"]),
        .library(name: "WaylandClient", targets: ["WaylandClient"]),
        .library(name: "WaylandServer", targets: ["WaylandServer"]),
        .library(name: "WaylandProtocol", targets: ["WaylandProtocol"]),
    ],
    targets: [
        .systemLibrary(name: "WaylandClientSystem", pkgConfig: "wayland-client"),
        .systemLibrary(name: "WaylandServerSystem", pkgConfig: "wayland-server"),
        .systemLibrary(name: "WaylandCursorSystem", pkgConfig: "wayland-cursor"),
        .systemLibrary(name: "WaylandEGLSystem", pkgConfig: "wayland-egl"),
        .target(name: "WaylandKit", dependencies: ["WaylandClient", "WaylandProtocol", "WaylandRuntime"], swiftSettings: [.strictMemorySafety()]),
        .target(name: "CWaylandCursor", dependencies: ["WaylandCursorSystem"], linkerSettings: [.linkedLibrary("wayland-cursor")]),
        .target(name: "CWaylandEGL", dependencies: ["WaylandEGLSystem"], linkerSettings: [.linkedLibrary("wayland-egl")]),
        .target(name: "CWaylandUtilities", dependencies: ["WaylandClientSystem"], linkerSettings: [.linkedLibrary("wayland-client")]),
        .target(name: "WaylandCursor", dependencies: ["CWaylandCursor", "WaylandClient", "WaylandProtocol", "WaylandRuntime"], swiftSettings: [.strictMemorySafety()]),
        .target(name: "WaylandEGL", dependencies: ["CWaylandEGL", "WaylandClient", "WaylandProtocol", "WaylandRuntime"], swiftSettings: [.strictMemorySafety()]),
        .target(name: "WaylandUtilities", dependencies: ["CWaylandUtilities", "CWaylandRuntime", "WaylandRuntime"], swiftSettings: [.strictMemorySafety()]),
        .target(name: "CWaylandProtocol", dependencies: ["WaylandClientSystem"]),
        .target(name: "WaylandProtocol", dependencies: ["CWaylandProtocol"], swiftSettings: [.strictMemorySafety()]),
        .target(name: "CWaylandServer", dependencies: ["WaylandServerSystem", "CWaylandRuntime"], linkerSettings: [.linkedLibrary("wayland-server")]),
        .target(name: "WaylandServer", dependencies: ["WaylandRuntime", "WaylandProtocol", "CWaylandProtocol", "CWaylandServer"], swiftSettings: [.strictMemorySafety()]),
        .target(name: "CWaylandClient", dependencies: ["WaylandClientSystem", "CWaylandRuntime"], linkerSettings: [.linkedLibrary("wayland-client")]),
        .target(name: "WaylandClient", dependencies: ["WaylandRuntime", "WaylandProtocol", "CWaylandProtocol", "CWaylandClient"], swiftSettings: [.strictMemorySafety()]),
        .target(name: "CWaylandRuntime", linkerSettings: [.linkedLibrary("pthread")]),
        .target(name: "WaylandRuntime", dependencies: ["CWaylandRuntime"], swiftSettings: [.strictMemorySafety()]),
        .target(
            name: "RuntimeNativeTestSupport",
            dependencies: ["WaylandClientSystem", "WaylandServerSystem", "WaylandCursorSystem", "WaylandEGLSystem"],
            path: "Tests/RuntimeNativeTestSupport",
            exclude: ["WaitFaults.c.fixture"],
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("wayland-server"), .linkedLibrary("wayland-client"), .linkedLibrary("wayland-cursor"), .linkedLibrary("wayland-egl")]
        ),
        .executableTarget(name: "WaylandLifecycleSoak", dependencies: ["WaylandRuntime", "WaylandProtocol", "WaylandClient", "WaylandServer", "WaylandCursor", "WaylandEGL", "WaylandUtilities", "RuntimeNativeTestSupport"], path: "Tests/LifecycleSoak", swiftSettings: [.strictMemorySafety()]),
        .executableTarget(name: "WaylandTypedBenchmarks", dependencies: ["WaylandRuntime", "WaylandProtocol", "WaylandClient", "CWaylandClient", "RuntimeNativeTestSupport"], path: "Benchmarks/Typed", swiftSettings: [.strictMemorySafety()]),
        .executableTarget(name: "WaylandBenchmarks", dependencies: ["WaylandRuntime", "WaylandClient", "RuntimeNativeTestSupport"], path: "Benchmarks", exclude: ["Typed"], swiftSettings: [.strictMemorySafety()]),
        .testTarget(
            name: "WaylandRuntimeTests",
            dependencies: ["WaylandRuntime", "WaylandClient", "CWaylandClient", "WaylandServer", "CWaylandServer", "WaylandProtocol", "WaylandCursor", "WaylandEGL", "WaylandUtilities", "RuntimeNativeTestSupport"],
            swiftSettings: [.strictMemorySafety()]
        ),
    ],
    swiftLanguageModes: [.v6]
)
