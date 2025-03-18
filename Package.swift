// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VideoStreamTracker",
    platforms: [
        .iOS(.v13), .tvOS(.v13)
    ],
    products: [
        .library(
            name: "VideoStreamTracker",
            targets: ["VideoStreamTracker"]
        ),
    ],
    dependencies: [], 
    targets: [
        .target(
            name: "VideoStreamTracker",
            dependencies: []
        ),
        .testTarget(
            name: "VideoStreamTrackerTests",
            dependencies: ["VideoStreamTracker"] 
        ),
    ]
)
