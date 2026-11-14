// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SystemBackCore",
    defaultLocalization: "es",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SystemBackCore", targets: ["SystemBackCore"]),
    ],
    targets: [
        // Biblioteca: APIs nonisolated; el llamador decide dónde se ejecuta.
        .target(
            name: "SystemBackCore",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "SystemBackCoreTests",
            dependencies: ["SystemBackCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
