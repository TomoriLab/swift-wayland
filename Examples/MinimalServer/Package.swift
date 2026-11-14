// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "MinimalServerExample",
    dependencies: [.package(path: "../..")],
    targets: [.executableTarget(name: "MinimalServer", dependencies: [.product(name: "WaylandServer", package: "swift-wayland"),
                                                                     .product(name: "WaylandProtocol", package: "swift-wayland")],
                                swiftSettings: [.strictMemorySafety()])],
    swiftLanguageModes: [.v6]
)
