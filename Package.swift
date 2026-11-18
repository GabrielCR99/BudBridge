// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BudBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BudBridge", targets: ["BudBridge"]),
        .library(name: "QCYKit", targets: ["QCYKit"]),
    ],
    targets: [
        // Pure protocol layer: framing, command encoding and state decoding. No I/O, fully Sendable.
        .target(
            name: "QCYKit",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        // SwiftUI app: CoreBluetooth control link + IOBluetooth audio link. Main-actor by default.
        .executableTarget(
            name: "BudBridge",
            dependencies: ["QCYKit"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("ExistentialAny"),
            ],
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOBluetooth"),
            ]
        ),
        .testTarget(name: "QCYKitTests", dependencies: ["QCYKit"]),
    ]
)
