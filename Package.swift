// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIStorageManager",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "SafetyCore", targets: ["SafetyCore"]),
        .library(name: "AppServices", targets: ["AppServices"]),
        .library(name: "AIStorageManagerUI", targets: ["AIStorageManagerUI"]),
        .executable(name: "storage-intel", targets: ["StorageIntel"]),
        .executable(name: "ai-storage-manager", targets: ["AIStorageManagerApp"]),
        .executable(name: "overview-screenshot", targets: ["OverviewScreenshot"]),
    ],
    targets: [
        .target(
            name: "SafetyCore",
            resources: [
                .copy("Resources"),
            ]
        ),
        .target(
            name: "AppServices",
            dependencies: ["SafetyCore"],
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "AIStorageManagerUI",
            dependencies: ["AppServices", "SafetyCore"]
        ),
        .testTarget(
            name: "SafetyCoreTests",
            dependencies: ["SafetyCore"]
        ),
        .testTarget(
            name: "AppServicesTests",
            dependencies: ["AppServices", "SafetyCore"]
        ),
        .executableTarget(
            name: "StorageIntel",
            dependencies: ["SafetyCore", "AppServices"]
        ),
        .executableTarget(
            name: "AIStorageManagerApp",
            dependencies: ["AIStorageManagerUI", "AppServices", "SafetyCore"]
        ),
        .executableTarget(
            name: "OverviewScreenshot",
            dependencies: ["AIStorageManagerUI", "AppServices", "SafetyCore"]
        ),
    ]
)
