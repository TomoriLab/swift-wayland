// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "WaylandKit",
    products: [
        .library(name: "WaylandRuntime", targets: ["WaylandRuntime"]),
    ],
    targets: [
        .target(name: "CWaylandRuntime", linkerSettings: [.linkedLibrary("pthread")]),
        .target(name: "WaylandRuntime", dependencies: ["CWaylandRuntime"], swiftSettings: [.strictMemorySafety()]),
        .target(
            name: "RuntimeNativeTestSupport",
            path: "Tests/RuntimeNativeTestSupport",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("wayland-server")]
        ),
        .testTarget(
            name: "WaylandRuntimeTests",
            dependencies: ["WaylandRuntime", "RuntimeNativeTestSupport"],
            swiftSettings: [.strictMemorySafety()]
        ),
    ],
    swiftLanguageModes: [.v6]
)
