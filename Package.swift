// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PendingBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PendingBar", targets: ["PendingBar"]),
        .executable(name: "pendingctl", targets: ["pendingctl"]),
        .library(name: "PendingKit", targets: ["PendingKit"]),
    ],
    targets: [
        .target(name: "PendingKit"),
        .executableTarget(name: "pendingctl", dependencies: ["PendingKit"]),
        .executableTarget(name: "PendingBar", dependencies: ["PendingKit"]),
        .testTarget(name: "PendingKitTests", dependencies: ["PendingKit"]),
    ],
    swiftLanguageModes: [.v5]
)
