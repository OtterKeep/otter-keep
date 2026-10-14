// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OtterKeep",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "OtterKeepDomain", targets: ["OtterKeepDomain"]),
        .library(name: "OtterKeepApplication", targets: ["OtterKeepApplication"]),
        .library(name: "OtterKeepStorage", targets: ["OtterKeepStorage"]),
        .library(name: "OtterKeepDatabase", targets: ["OtterKeepDatabase"]),
        .library(name: "OtterKeepCore", targets: ["OtterKeepCore"]),
        .library(name: "OtterKeepUI", targets: ["OtterKeepUI"]),
        .executable(name: "OtterKeepFinderSyncExtension", targets: ["OtterKeepFinderSyncExtension"]),
        .executable(name: "otterkeep", targets: ["OtterKeepCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0")
    ],
    targets: [
        // MARK: - Domain Layer (Pure Domain Entities & Invariants)
        .target(
            name: "OtterKeepDomain",
            dependencies: [],
            path: "Sources/OtterKeepDomain",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // MARK: - Application Layer (Ports & Use Cases)
        .target(
            name: "OtterKeepApplication",
            dependencies: ["OtterKeepDomain"],
            path: "Sources/OtterKeepApplication",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // MARK: - Storage Layer
        .target(
            name: "OtterKeepStorage",
            dependencies: ["OtterKeepDomain", "OtterKeepApplication"],
            path: "Sources/OtterKeepStorage",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // MARK: - Database Layer
        .target(
            name: "OtterKeepDatabase",
            dependencies: ["OtterKeepDomain", "OtterKeepApplication", "OtterKeepStorage"],
            path: "Sources/OtterKeepDatabase",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // MARK: - Core Engine
        .target(
            name: "OtterKeepCore",
            dependencies: ["OtterKeepDomain", "OtterKeepApplication", "OtterKeepStorage", "OtterKeepDatabase"],
            path: "Sources/OtterKeepCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // MARK: - UI
        .target(
            name: "OtterKeepUI",
            dependencies: ["OtterKeepDomain", "OtterKeepApplication", "OtterKeepStorage", "OtterKeepDatabase", "OtterKeepCore"],
            path: "Sources/OtterKeepUI",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // MARK: - Finder Sync Extension
        .executableTarget(
            name: "OtterKeepFinderSyncExtension",
            dependencies: ["OtterKeepCore"],
            path: "Sources/OtterKeepFinderSyncExtension",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // MARK: - Integration Test Suite (swift-testing, CLT-compatible)
        .testTarget(
            name: "OtterKeepIntegrationTests",
            dependencies: [
                "OtterKeepDomain",
                "OtterKeepApplication",
                "OtterKeepStorage",
                "OtterKeepDatabase",
                "OtterKeepCore",
                "OtterKeepUI"
            ],
            path: "Tests/OtterKeepIntegrationTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // MARK: - CLI Tool
        .executableTarget(
            name: "OtterKeepCLI",
            dependencies: [
                "OtterKeepDomain",
                "OtterKeepApplication",
                "OtterKeepStorage",
                "OtterKeepDatabase",
                "OtterKeepCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/OtterKeepCLI",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // MARK: - App Executable
        .executableTarget(
            name: "OtterKeepApp",
            dependencies: [
                "OtterKeepCore",
                "OtterKeepUI",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/OtterKeepApp",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
