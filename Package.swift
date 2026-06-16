// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Overlay",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "overlay", targets: ["overlay"]),
        .executable(name: "overlay-studio", targets: ["OverlayStudio"]),
        .library(name: "OverlayCore", targets: ["OverlayCore"])
    ],
    targets: [
        .target(
            name: "OverlayCore",
            path: "Sources/OverlayCore"
        ),
        .executableTarget(
            name: "overlay",
            dependencies: ["OverlayCore"],
            path: "Sources/overlay"
        ),
        .executableTarget(
            name: "OverlayStudio",
            dependencies: ["OverlayCore"],
            path: "Sources/OverlayStudio"
        ),
        .testTarget(
            name: "OverlayCoreTests",
            dependencies: ["OverlayCore"],
            path: "Tests/OverlayCoreTests"
        )
    ]
)
