// swift-tools-version: 6.2
import PackageDescription

/// SwiftLint runs on every build of the source targets (build-time only; nothing ships in the app).
let swiftLint: Target.PluginUsage = .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")

let package = Package(
    name: "BudBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BudBridge", targets: ["BudBridge"]),
        .library(name: "QCYKit", targets: ["QCYKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.65.1"),
    ],
    targets: [
        // Pure protocol layer: framing, command encoding, settings lists and state. No I/O, fully Sendable.
        .target(
            name: "QCYKit",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("ExistentialAny"),
            ],
            plugins: [swiftLint]
        ),
        // SwiftUI app, MVVM-C: Services (model layer) → ViewModels → Views, wired by AppCoordinator.
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
            ],
            plugins: [swiftLint]
        ),
        .testTarget(name: "QCYKitTests", dependencies: ["QCYKit"]),
        .testTarget(
            name: "BudBridgeTests",
            dependencies: ["BudBridge", "QCYKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
