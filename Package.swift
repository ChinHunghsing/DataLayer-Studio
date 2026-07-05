// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DataLayerStudio",
    platforms: [
        .macOS(.v13),
        .iOS("26.0")
    ],
    products: [
        .executable(name: "overlay", targets: ["overlay"]),
        .executable(name: "datalayer-studio", targets: ["OverlayStudio"]),
        .executable(name: "overlay-studio", targets: ["OverlayStudio"]),
        .library(name: "OverlayCore", targets: ["OverlayCore"]),
        .library(name: "OverlayStudioKit", targets: ["OverlayStudioKit"])
    ],
    targets: [
        .target(
            name: "OverlayCore",
            path: "Sources/OverlayCore"
        ),
        .target(
            name: "OverlayStudioKit",
            dependencies: ["OverlayCore"],
            path: "Sources/OverlayStudioKit"
        ),
        .executableTarget(
            name: "overlay",
            dependencies: ["OverlayCore"],
            path: "Sources/overlay"
        ),
        .executableTarget(
            name: "OverlayStudio",
            dependencies: ["OverlayCore", "OverlayStudioKit"],
            path: "Sources/OverlayStudio"
        ),
        .testTarget(
            name: "OverlayCoreTests",
            dependencies: ["OverlayCore"],
            path: "Tests/OverlayCoreTests"
        ),
        .testTarget(
            name: "OverlayStudioTests",
            dependencies: ["OverlayStudio", "OverlayStudioKit"],
            path: "Tests/OverlayStudioTests"
        ),
        .testTarget(
            name: "OverlayCLITests",
            dependencies: ["overlay"],
            path: "Tests/OverlayCLITests"
        )
    ]
)
