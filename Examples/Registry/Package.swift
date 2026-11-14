// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "RegistryExample",
    dependencies: [.package(path: "../..")],
    targets: [.executableTarget(name: "RegistryExample", dependencies: [.product(name: "WaylandKit", package: "swift-wayland")],
                                swiftSettings: [.strictMemorySafety()])],
    swiftLanguageModes: [.v6]
)
