// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PocketNotchKit",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PocketNotchShared", targets: ["PocketNotchShared"]),
        .library(name: "PocketNotchCore", targets: ["PocketNotchCore"]),
        .library(name: "MediaModule", targets: ["MediaModule"]),
        .library(name: "ShelfModule", targets: ["ShelfModule"]),
        .library(name: "SystemStatsModule", targets: ["SystemStatsModule"]),
        .library(name: "BrightnessModule", targets: ["BrightnessModule"]),
        .library(name: "WeatherModule", targets: ["WeatherModule"]),
        .library(name: "StockModule", targets: ["StockModule"]),
        .library(name: "ApplicationsModule", targets: ["ApplicationsModule"]),
        .library(name: "AgentEventModule", targets: ["AgentEventModule"]),
        .library(name: "AgentSessionsModule", targets: ["AgentSessionsModule"]),
        .library(name: "RecentFoldersModule", targets: ["RecentFoldersModule"]),
        .library(name: "TodoModule", targets: ["TodoModule"]),
        .library(name: "ClipboardModule", targets: ["ClipboardModule"]),
        .library(name: "TimerModule", targets: ["TimerModule"]),
        .library(name: "Display", targets: ["Display"]),
    ],
    targets: [
        .target(
            name: "PocketNotchShared"
        ),
        .target(
            name: "PocketNotchCore",
            dependencies: ["PocketNotchShared"],
            resources: [.process("Shaders")]
        ),
        .target(
            name: "MediaModule",
            dependencies: ["PocketNotchCore", "PocketNotchShared"],
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("SceneKit"),
                .linkedFramework("CoreBluetooth")
            ]
        ),
        .target(
            name: "ShelfModule",
            dependencies: ["PocketNotchCore", "PocketNotchShared"]
        ),
        .target(
            name: "SystemStatsModule",
            dependencies: ["PocketNotchCore", "PocketNotchShared"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "BrightnessModule",
            dependencies: ["PocketNotchCore", "PocketNotchShared"]
        ),
        .target(
            name: "WeatherModule",
            dependencies: ["PocketNotchCore", "PocketNotchShared"]
        ),
        .target(
            name: "StockModule",
            dependencies: ["PocketNotchCore", "PocketNotchShared"]
        ),
        .target(
            name: "ApplicationsModule",
            dependencies: ["PocketNotchCore", "PocketNotchShared"]
        ),
        .target(
            name: "AgentEventModule",
            dependencies: ["PocketNotchCore", "PocketNotchShared", "Display"],
            resources: [
                .copy("Resources/agent-events.sh"),
                .copy("Resources/perm.gif"),
                .copy("Resources/running3.gif"),
            ]
        ),
        .target(
            name: "AgentSessionsModule",
            dependencies: ["PocketNotchCore", "PocketNotchShared"],
            resources: [
                .copy("Resources/get_agent_sessions.py"),
            ]
        ),
        .target(
            name: "RecentFoldersModule",
            dependencies: ["PocketNotchCore", "PocketNotchShared"]
        ),
        .target(
            name: "TodoModule",
            dependencies: ["PocketNotchCore", "PocketNotchShared"]
        ),
        .target(
            name: "ClipboardModule",
            dependencies: ["PocketNotchCore", "PocketNotchShared"]
        ),
        .target(
            name: "TimerModule",
            dependencies: ["PocketNotchCore", "PocketNotchShared"]
        ),
        .target(
            name: "Display",
            dependencies: ["PocketNotchShared"],
            resources: [
                .copy("Agent/Lifecycle/Resources/get_agent_sessions.py"),
            ]
        ),
        .testTarget(
            name: "DisplayTests",
            dependencies: ["Display"]
        ),
        .testTarget(
            name: "PocketNotchCoreTests",
            dependencies: ["PocketNotchCore"]
        ),
        .testTarget(
            name: "MediaModuleTests",
            dependencies: ["MediaModule"]
        ),
        .testTarget(
            name: "ShelfModuleTests",
            dependencies: ["ShelfModule"]
        ),
        .testTarget(
            name: "SystemStatsModuleTests",
            dependencies: ["SystemStatsModule"]
        ),
        .testTarget(
            name: "BrightnessModuleTests",
            dependencies: ["BrightnessModule"]
        ),
        .testTarget(
            name: "WeatherModuleTests",
            dependencies: ["WeatherModule"]
        ),
        .testTarget(
            name: "StockModuleTests",
            dependencies: ["StockModule"]
        ),
        .testTarget(
            name: "AgentEventModuleTests",
            dependencies: ["AgentEventModule"]
        ),
        .testTarget(
            name: "ApplicationsModuleTests",
            dependencies: ["ApplicationsModule"]
        ),
        .testTarget(
            name: "RecentFoldersModuleTests",
            dependencies: ["RecentFoldersModule"]
        ),
        .testTarget(
            name: "TodoModuleTests",
            dependencies: ["TodoModule"]
        ),
        .testTarget(
            name: "ClipboardModuleTests",
            dependencies: ["ClipboardModule", "PocketNotchCore"]
        ),
        .testTarget(
            name: "TimerModuleTests",
            dependencies: ["TimerModule", "PocketNotchCore"]
        ),
    ]
)
