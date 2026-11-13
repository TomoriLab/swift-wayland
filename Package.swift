// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "WaylandKit",
    products: [
        .library(name: "WaylandRuntime", targets: ["WaylandRuntime"]),
        .library(name: "WaylandClient", targets: ["WaylandClient"]),
        .library(name: "WaylandServer", targets: ["WaylandServer"]),
        .library(name: "WaylandProtocol", targets: ["WaylandProtocol"]),
    ],
    targets: [
        .target(name: "WaylandProtocol", swiftSettings: [.strictMemorySafety()]),
        .target(name: "CWaylandServer", linkerSettings: [.linkedLibrary("wayland-server")]),
        .target(name: "WaylandServer", dependencies: ["WaylandRuntime", "CWaylandServer"], swiftSettings: [.strictMemorySafety()]),
        .target(name: "CWaylandClient", linkerSettings: [.linkedLibrary("wayland-client")]),
        .target(name: "WaylandClient", dependencies: ["WaylandRuntime", "CWaylandClient"], swiftSettings: [.strictMemorySafety()]),
        .target(name: "CWaylandRuntime", linkerSettings: [.linkedLibrary("pthread")]),
        .target(name: "WaylandRuntime", dependencies: ["CWaylandRuntime"], swiftSettings: [.strictMemorySafety()]),
        .target(
            name: "RuntimeNativeTestSupport",
            path: "Tests/RuntimeNativeTestSupport",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("wayland-server"), .linkedLibrary("wayland-client")]
        ),
        .executableTarget(name: "WaylandBenchmarks", dependencies: ["WaylandRuntime", "WaylandClient", "RuntimeNativeTestSupport"], path: "Benchmarks", swiftSettings: [.strictMemorySafety()]),
        .testTarget(
            name: "WaylandRuntimeTests",
            dependencies: ["WaylandRuntime", "WaylandClient", "CWaylandClient", "WaylandServer", "CWaylandServer", "WaylandProtocol", "RuntimeNativeTestSupport"],
            swiftSettings: [.strictMemorySafety()]
        ),
    ],
    swiftLanguageModes: [.v6]
)
