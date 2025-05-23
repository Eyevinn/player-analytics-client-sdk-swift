// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VideoStreamTracker",
    platforms: [
        .iOS(.v16), .tvOS(.v16)
    ],
    products: [
        .library(
            name: "VideoStreamTracker",
            targets: ["VideoStreamTracker", "SGAI"]
        ),
    ],
    dependencies: [], 
    targets: [
        .target(
            name: "VideoStreamTracker",
            dependencies: []
        ),
        .target(
            name: "SGAI",
            path: "Sources/SGAI"
        ),
        .testTarget(
            name: "VideoStreamTrackerTests",
            dependencies: ["VideoStreamTracker"] 
        ),
    ]
)
